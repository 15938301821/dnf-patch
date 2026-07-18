import { readFile } from "node:fs/promises";
import {
  contextBundleSchema,
  importTransactionReceiptSchema,
  runRequestSchema,
  type ContextBundle,
  type RunRequest,
  type RunSummary,
  type ToolResult,
} from "../shared/contracts.js";
import {
  toolCatalogSchema,
  type ToolCatalogEntry,
} from "../shared/tool-catalog.js";
import { BpkPackager } from "./bpk-packager.js";
import { buildContextBundle } from "./context-builder.js";
import {
  assertProfileCatalogBinding,
  assertProfileRequestBinding,
  loadExecutionProfile,
  loadToolCatalog,
} from "./profile-loader.js";
import {
  expandExecutionProfile,
  materializeExecutionConfig,
  type ExpandedExecutionProfile,
  type ExpandedProfileStep,
} from "./profile-runtime.js";
import { ModelOrchestrator } from "./model-orchestrator.js";
import { ImportOrchestrator } from "./import-orchestrator.js";
import { cleanupImportSource, prepareImportSource } from "./import-source.js";
import { ImportTransactionWriter } from "./import-transaction-writer.js";
import { RunStore } from "./run-store.js";
import {
  ToolBroker,
  parseJsonOutput,
  parseKeyValueOutput,
} from "./tool-broker.js";
import { fileExists, resolveInside, snapshotFile } from "./lib/filesystem.js";

class PipelineBlockedError extends Error {}

export function classifyPipelineFailure(
  importCommitted: boolean,
  blocked: boolean,
): "committed-with-warnings" | "blocked" | "failed" {
  if (importCommitted) {
    return "committed-with-warnings";
  }
  return blocked ? "blocked" : "failed";
}

async function hasMatchingImportReceipt(
  store: RunStore,
  request: RunRequest,
): Promise<boolean> {
  if (
    request.action !== "create-profession" &&
    request.action !== "create-theme"
  ) {
    return false;
  }
  const path = resolveInside(
    store.runDirectory(request.runId),
    "imports/transaction-receipt.json",
  );
  if (!(await fileExists(path))) {
    return false;
  }
  try {
    const receipt = importTransactionReceiptSchema.parse(
      JSON.parse(
        (await readFile(path, "utf8")).replace(/^\uFEFF/u, ""),
      ) as unknown,
    );
    return (
      receipt.runId === request.runId &&
      receipt.route.profession === request.profession &&
      receipt.route.theme === request.theme
    );
  } catch {
    return false;
  }
}

function requireOutputBySuffix(
  step: ExpandedProfileStep,
  suffix: string,
): string {
  const matches = step.expectedOutputs.filter((path) => path.endsWith(suffix));
  const [match] = matches;
  if (matches.length !== 1 || match === undefined) {
    throw new Error(
      `Profile step ${step.id} must declare exactly one ${suffix} output.`,
    );
  }
  return match;
}

function requireObject(value: unknown, label: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object.`);
  }
  return value as Record<string, unknown>;
}

async function readJsonObject(
  repositoryRoot: string,
  relativePath: string,
): Promise<Record<string, unknown>> {
  const text = await readFile(
    resolveInside(repositoryRoot, relativePath),
    "utf8",
  );
  return requireObject(
    JSON.parse(text.replace(/^\uFEFF/u, "")) as unknown,
    relativePath,
  );
}

function assertToolResult(result: ToolResult, step: ExpandedProfileStep): void {
  if (result.status !== "passed" || result.exitCode !== 0) {
    const detail = result.error ?? (result.stderr.trim() || result.status);
    throw new Error(`Profile step ${step.id} failed: ${detail}`);
  }
}

async function assertStepSuccess(
  repositoryRoot: string,
  tool: ToolCatalogEntry,
  step: ExpandedProfileStep,
  result: ToolResult,
): Promise<void> {
  assertToolResult(result, step);
  if (tool.id === "local-toolchain-gate") {
    const output = requireObject(parseJsonOutput(result.stdout), tool.id);
    const aseprite = requireObject(output.aseprite, `${tool.id}.aseprite`);
    const prerequisites = requireObject(
      output.systemPrerequisites,
      `${tool.id}.systemPrerequisites`,
    );
    if (
      output.status !== "passed" ||
      aseprite.available !== true ||
      prerequisites.x86PowerShellAvailable !== true
    ) {
      throw new PipelineBlockedError(
        "Local toolchain gate did not prove Aseprite and x86 PowerShell availability.",
      );
    }
    return;
  }
  if (tool.id === "export-vergil-illusionslash-source") {
    const output = parseKeyValueOutput(result.stdout);
    if (
      !/^[A-F0-9]{64}$/u.test(output.SourceSha256 ?? "") ||
      Number.parseInt(output.FrameCount ?? "0", 10) <= 0 ||
      Number.parseInt(output.RuntimeRequiredFrameCount ?? "0", 10) <= 0 ||
      output.Deployment !== "not-authorized-not-performed"
    ) {
      throw new Error(
        "Official source export did not satisfy its success contract.",
      );
    }
    const inventory = await readJsonObject(
      repositoryRoot,
      requireOutputBySuffix(step, "/frame-inventory.json"),
    );
    if (inventory.status !== "passed") {
      throw new Error("Official source frame inventory is not passed.");
    }
    return;
  }
  if (tool.id === "render-vergil-illusionslash-aseprite") {
    const output = parseKeyValueOutput(result.stdout);
    if (
      Number.parseInt(output.FrameCount ?? "0", 10) <= 0 ||
      output.Deployment !== "not-authorized-not-performed"
    ) {
      throw new Error("Aseprite render did not satisfy its output contract.");
    }
    const summary = await readJsonObject(
      repositoryRoot,
      requireOutputBySuffix(step, "/render-summary.json"),
    );
    const validation = requireObject(
      summary.validation,
      "render-summary.validation",
    );
    const styleApplication = requireObject(
      summary.styleApplication,
      "render-summary.styleApplication",
    );
    const accounting = requireObject(
      summary.accounting,
      "render-summary.accounting",
    );
    if (
      summary.status !== "passed" ||
      validation.modelStylePlanAppliedByRenderer !==
        "passed-byte-exact-recompute" ||
      styleApplication.provider !== "openai" ||
      styleApplication.appliedFrameCount !== accounting.expectedFrames ||
      styleApplication.byteExactRecomputeCount !== accounting.expectedFrames
    ) {
      throw new Error(
        "Aseprite render lacks closed model style application evidence.",
      );
    }
    return;
  }
  if (tool.id === "build-vergil-illusionslash-aseprite") {
    const output = parseKeyValueOutput(result.stdout);
    if (
      !/^[A-F0-9]{64}$/u.test(output.OutputSha256 ?? "") ||
      output.Deployment !== "not-authorized-not-performed"
    ) {
      throw new Error("NPK build did not satisfy its output contract.");
    }
    const validation = await readJsonObject(
      repositoryRoot,
      requireOutputBySuffix(step, "/build-validation-summary.json"),
    );
    const modelStyle = requireObject(
      validation.modelStyleApplication,
      "build-validation-summary.modelStyleApplication",
    );
    if (
      validation.status !== "passed" ||
      modelStyle.provider !== "openai" ||
      modelStyle.appliedFrameCount !== modelStyle.byteExactRecomputeCount
    ) {
      throw new Error(
        "Independent NPK validation lacks model style provenance.",
      );
    }
  }
}

function topologicalSteps(
  steps: ExpandedProfileStep[],
  selectedPhases: Set<ExpandedProfileStep["phase"]>,
): ExpandedProfileStep[] {
  const byId = new Map(steps.map((step) => [step.id, step]));
  const selected = new Set(
    steps
      .filter((step) => selectedPhases.has(step.phase))
      .map((step) => step.id),
  );
  const completed = new Set<string>();
  const result: ExpandedProfileStep[] = [];
  while (result.length < selected.size) {
    const ready = steps.find(
      (step) =>
        selected.has(step.id) &&
        !completed.has(step.id) &&
        step.dependsOn.every(
          (dependency) =>
            completed.has(dependency) || !selected.has(dependency),
        ),
    );
    if (!ready) {
      throw new Error(
        "Selected execution profile phases are cyclic or incomplete.",
      );
    }
    for (const dependency of ready.dependsOn) {
      if (!byId.has(dependency)) {
        throw new Error(
          `Unknown profile dependency: ${ready.id}/${dependency}`,
        );
      }
    }
    completed.add(ready.id);
    result.push(ready);
  }
  return result;
}

export class PatchPipeline {
  readonly store: RunStore;

  constructor(readonly repositoryRoot: string) {
    this.store = new RunStore(repositoryRoot);
  }

  async #executeSteps(
    request: RunRequest,
    expanded: ExpandedExecutionProfile,
    broker: ToolBroker,
    tools: Map<string, ToolCatalogEntry>,
    phases: ExpandedProfileStep["phase"][],
  ): Promise<void> {
    for (const step of topologicalSteps(expanded.steps, new Set(phases))) {
      const tool = tools.get(step.toolId);
      if (!tool) {
        throw new Error(
          `Profile tool disappeared from catalog: ${step.toolId}`,
        );
      }
      await this.store.update(request.runId, { currentStage: step.id });
      await this.store.emit(
        request.runId,
        step.id,
        `Executing fixed catalog tool ${tool.id}.`,
      );
      const result = await broker.invoke({
        invocation: {
          schemaVersion: 1,
          runId: request.runId,
          callId: `step.${step.id}`,
          toolId: step.toolId,
          arguments: step.arguments,
          allowNetwork: false,
          execute: true,
        },
        expectedOutputs: step.expectedOutputs,
      });
      await assertStepSuccess(this.repositoryRoot, tool, step, result);
      await this.store.emit(
        request.runId,
        step.id,
        `Fixed catalog tool ${tool.id} passed.`,
        "info",
        `apps/desktop/.runs/${request.runId}/tools/step.${step.id}/result.json`,
      );
    }
  }

  async #freezeContext(
    request: RunRequest,
    expanded: ExpandedExecutionProfile,
  ): Promise<{ context: ContextBundle; path: string; sha256: string }> {
    const inventoryStep = expanded.steps.find(
      (step) => step.phase === "inventory",
    );
    const inventoryInputs = inventoryStep
      ? {
          sourceSummaryPath: requireOutputBySuffix(
            inventoryStep,
            "/source-summary.json",
          ),
          sourceInventoryPath: requireOutputBySuffix(
            inventoryStep,
            "/frame-inventory.json",
          ),
        }
      : {};
    const context = contextBundleSchema.parse(
      await buildContextBundle(this.repositoryRoot, request, {
        ...(request.execute
          ? {
              materializedConfigPath: expanded.configPath,
              ...inventoryInputs,
            }
          : {}),
      }),
    );
    const path = await this.store.writeEvidence(
      request.runId,
      "context/context-bundle.json",
      context,
    );
    const snapshot = await snapshotFile(
      this.repositoryRoot,
      path,
      "Frozen context bundle",
      false,
    );
    return { context, path, sha256: snapshot.sha256 };
  }

  async #runGeneratePatch(request: RunRequest): Promise<RunSummary> {
    if (!request.profileId) {
      throw new PipelineBlockedError(
        "Patch generation requires a registered execution profile.",
      );
    }
    const profile = await loadExecutionProfile(
      this.repositoryRoot,
      request.profileId,
    );
    assertProfileRequestBinding(
      profile,
      request.profession,
      request.theme,
      request.selectedSkills,
    );
    const catalog = await loadToolCatalog(this.repositoryRoot);
    await assertProfileCatalogBinding(this.repositoryRoot, profile, catalog);
    const expanded = expandExecutionProfile(profile, request);
    const broker = new ToolBroker(this.repositoryRoot, this.store, catalog);
    const tools = new Map(catalog.tools.map((tool) => [tool.id, tool]));

    if (request.execute) {
      if (request.provider !== "openai") {
        throw new PipelineBlockedError(
          "Mock model evidence cannot drive Aseprite, NPK, or BPK execution.",
        );
      }
      await this.store.update(request.runId, { currentStage: "config-freeze" });
      const configPath = await materializeExecutionConfig(
        this.repositoryRoot,
        expanded,
        request,
      );
      await this.store.emit(
        request.runId,
        "config-freeze",
        "Materialized the fixed execution config without model-controlled paths.",
        "info",
        configPath,
      );
      await this.#executeSteps(request, expanded, broker, tools, [
        "preflight",
        "inventory",
      ]);
    }

    await this.store.update(request.runId, { currentStage: "context-freeze" });
    const frozen = await this.#freezeContext(request, expanded);
    await this.store.emit(
      request.runId,
      "context-freeze",
      "Frozen rules, profile, prompts, catalog and available source inventory.",
      "info",
      frozen.path,
    );
    if (request.execute && frozen.context.missingRequiredFacts.length > 0) {
      throw new PipelineBlockedError(
        `Formal execution is missing facts: ${frozen.context.missingRequiredFacts.join(
          ", ",
        )}`,
      );
    }

    await this.store.update(request.runId, { currentStage: "models" });
    const orchestrator = new ModelOrchestrator(
      this.repositoryRoot,
      this.store,
      request,
    );
    const models = await orchestrator.runPatchModels(
      request,
      frozen.context,
      frozen.path,
      frozen.sha256,
      profile,
    );
    await this.store.emit(
      request.runId,
      "models",
      "Stored SOL task graph, GPT engineering design, image attempt and compiled style plan.",
      "info",
      models.stylePlanPath,
    );

    if (!request.execute) {
      return this.store.update(request.runId, {
        status: "planned",
        currentStage: "planned",
        finishedAtUtc: new Date().toISOString(),
      });
    }
    if (
      !models.modelEvidenceEligible ||
      models.stylePlan.source.provider !== "openai"
    ) {
      throw new PipelineBlockedError(
        "Formal rendering requires eligible OpenAI GPT-5.5 style evidence.",
      );
    }
    if (models.stylePlanPath !== expanded.stylePlanPath) {
      throw new Error(
        `Style plan path does not match the fixed profile: ${models.stylePlanPath}/${expanded.stylePlanPath}`,
      );
    }

    await this.#executeSteps(request, expanded, broker, tools, ["post-model"]);
    const npkSnapshot = await snapshotFile(
      this.repositoryRoot,
      expanded.outputNpkPath,
      "Native DNF NPK payload",
      false,
    );
    const validationSnapshot = await snapshotFile(
      this.repositoryRoot,
      expanded.delivery.validationSummaryPath,
      "Independent NPK validation summary",
      false,
    );
    const deliverySummaryPath = await this.store.writeEvidence(
      request.runId,
      "delivery/offline-delivery-summary.json",
      {
        schemaVersion: 1,
        runId: request.runId,
        status: "offline-validation-passed-awaiting-human-review",
        executionProfileId: profile.id,
        models: {
          orchestrator: models.taskGraph.planId,
          engineerPlan: models.engineeringPlan.planId,
          stylePlan: {
            path: models.stylePlanPath,
            provider: models.stylePlan.source.provider,
            model: models.stylePlan.source.model,
            contextBundleSha256: models.stylePlan.source.contextBundleSha256,
            engineeringDesignSha256:
              models.stylePlan.source.engineeringDesignSha256,
            modelCallRecordSha256:
              models.stylePlan.source.modelCallRecordSha256,
          },
          imageReference: {
            status: models.imageAttempt.status,
            directRuntimeUseAllowed: false,
          },
        },
        payload: npkSnapshot,
        independentValidation: validationSnapshot,
        fullSkillCoverageProven: false,
        clientCompatibilityProven: false,
        humanReviewPassed: false,
        deploymentAuthorized: false,
        deploymentPerformed: false,
      },
    );
    await this.store.update(request.runId, { currentStage: "bpk-package" });
    await this.store.emit(
      request.runId,
      "bpk-package",
      "Packaging the native NPK and immutable evidence into BPK.",
      "info",
      deliverySummaryPath,
    );
    const packager = new BpkPackager(this.repositoryRoot, this.store);
    const runRoot = `apps/desktop/.runs/${request.runId}`;
    const packaged = await packager.package({
      request,
      profile,
      expandedNpkPath: expanded.outputNpkPath,
      validationSummaryPath: expanded.delivery.validationSummaryPath,
      buildSummaryPath: expanded.buildSummaryPath,
      evidencePaths: [
        ...expanded.delivery.evidencePaths,
        `${runRoot}/models`,
        `${runRoot}/plans`,
        `${runRoot}/tools`,
        `${runRoot}/events`,
        deliverySummaryPath,
      ],
    });
    await this.store.emit(
      request.runId,
      "bpk-package",
      "BPK was independently reopened and every declared entry hash matched.",
      "info",
      packaged.verificationPath,
    );
    return this.store.update(request.runId, {
      status: "awaiting-human-review",
      currentStage: "awaiting-human-review",
      outputBpk: packaged.bpkPath,
      finishedAtUtc: new Date().toISOString(),
    });
  }

  async #runImport(request: RunRequest): Promise<RunSummary> {
    const source = await prepareImportSource(this.repositoryRoot, request);
    try {
      await this.store.update(request.runId, {
        currentStage: "import-source-freeze",
      });
      await this.store.emit(
        request.runId,
        "import-source-freeze",
        "Frozen a repository-local UTF-8 design source without granting it resource authority.",
        "info",
        source.relativePath,
      );
      const context = contextBundleSchema.parse(
        await buildContextBundle(this.repositoryRoot, request),
      );
      const contextPath = await this.store.writeEvidence(
        request.runId,
        "context/context-bundle.json",
        context,
      );
      await this.store.emit(
        request.runId,
        "import-context-freeze",
        "Frozen root rules, import skill, existing prompt tree and tool catalog.",
        "info",
        contextPath,
      );

      if (!context.toolCatalog.content) {
        throw new Error("Frozen import tool catalog content is missing.");
      }
      const catalog = toolCatalogSchema.parse(
        JSON.parse(
          context.toolCatalog.content.replace(/^\uFEFF/u, ""),
        ) as unknown,
      );
      const broker = new ToolBroker(this.repositoryRoot, this.store, catalog);
      await this.store.update(request.runId, {
        currentStage: "import-models",
      });
      const orchestrator = new ImportOrchestrator(
        this.repositoryRoot,
        this.store,
        broker,
        request,
      );
      const artifacts = await orchestrator.run(request, context, source);
      await this.store.emit(
        request.runId,
        "import-models",
        "Stored the SOL import graph, GPT-5.5 outline, fixed target plan and fixed-target semantic design.",
        "info",
        "apps/desktop/.runs/" +
          request.runId +
          "/models/import-fixed-target-design.json",
      );

      if (!request.execute) {
        return await this.store.update(request.runId, {
          status: "planned",
          currentStage: "planned-import",
          finishedAtUtc: new Date().toISOString(),
        });
      }
      if (request.provider !== "openai" || !artifacts.modelEvidenceEligible) {
        throw new PipelineBlockedError(
          "Repository import writes require eligible OpenAI GPT-5.5 store=false evidence; mock output is planning-only.",
        );
      }

      await this.store.update(request.runId, {
        currentStage: "import-transaction",
      });
      const writer = new ImportTransactionWriter(
        this.repositoryRoot,
        this.store,
        broker,
      );
      const transaction = await writer.commit(
        request,
        artifacts.plan,
        artifacts.design,
        source.relativePath,
        artifacts.targetSnapshots,
        artifacts.authoritySnapshots,
      );
      await this.store.emit(
        request.runId,
        "import-transaction",
        "Committed only fixed import targets and passed the independent Prompt tree gate.",
        transaction.validation.counts.warnings > 0 ? "warning" : "info",
        transaction.receiptPath,
      );
      return await this.store.update(request.runId, {
        status: "passed",
        currentStage: "prompt-import-passed",
        finishedAtUtc: new Date().toISOString(),
      });
    } finally {
      await cleanupImportSource(this.repositoryRoot, source);
    }
  }

  async #runValidation(request: RunRequest): Promise<RunSummary> {
    const catalog = await loadToolCatalog(this.repositoryRoot);
    const broker = new ToolBroker(this.repositoryRoot, this.store, catalog);
    const toolIds = ["powershell-source-gate", "project-gate"];
    if (!request.execute) {
      const context = await buildContextBundle(this.repositoryRoot, request);
      await this.store.writeEvidence(
        request.runId,
        "context/context-bundle.json",
        context,
      );
      return this.store.update(request.runId, {
        status: "planned",
        currentStage: "planned-validation",
        finishedAtUtc: new Date().toISOString(),
      });
    }
    for (const toolId of toolIds) {
      const result = await broker.invoke({
        invocation: {
          schemaVersion: 1,
          runId: request.runId,
          callId: `validate.${toolId}`,
          toolId,
          arguments: {},
          allowNetwork: false,
          execute: true,
        },
        expectedOutputs: [],
      });
      if (result.status !== "passed" || result.exitCode !== 0) {
        throw new Error(result.error ?? `${toolId} failed.`);
      }
      const output = requireObject(parseJsonOutput(result.stdout), toolId);
      if (output.status !== "passed") {
        throw new Error(`${toolId} returned a non-passed status.`);
      }
    }
    return this.store.update(request.runId, {
      status: "passed",
      currentStage: "validation-passed",
      finishedAtUtc: new Date().toISOString(),
    });
  }

  async run(input: unknown): Promise<RunSummary> {
    const request = runRequestSchema.parse(input);
    if (request.resume) {
      throw new PipelineBlockedError(
        "Resume checkpoints are not yet available for this pipeline version.",
      );
    }
    await this.store.create(request);
    await this.store.emit(
      request.runId,
      "bootstrap",
      `Accepted ${request.action} Run with deployment disabled.`,
    );
    try {
      if (
        request.action === "create-profession" ||
        request.action === "create-theme"
      ) {
        return await this.#runImport(request);
      }
      if (request.action === "generate-patch") {
        return await this.#runGeneratePatch(request);
      }
      if (request.action === "validate-only") {
        return await this.#runValidation(request);
      }
      throw new PipelineBlockedError(
        `Pipeline action is not implemented yet: ${request.action}`,
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const importReceiptPath = resolveInside(
        this.store.runDirectory(request.runId),
        "imports/transaction-receipt.json",
      );
      const importCommitted = await hasMatchingImportReceipt(
        this.store,
        request,
      );
      const status = classifyPipelineFailure(
        importCommitted,
        error instanceof PipelineBlockedError,
      );
      try {
        await this.store.emit(
          request.runId,
          "pipeline",
          importCommitted
            ? `Prompt import was committed, but finalization reported: ${message}`
            : message,
          importCommitted ? "warning" : "error",
          importCommitted
            ? this.store.toRelative(importReceiptPath)
            : undefined,
        );
      } catch {
        // Summary state is more important than a best-effort terminal event.
      }
      return this.store.update(request.runId, {
        status,
        currentStage: importCommitted
          ? "prompt-import-committed-with-warnings"
          : status,
        finishedAtUtc: new Date().toISOString(),
        error: importCommitted
          ? `Post-commit finalization warning: ${message}`
          : message,
      });
    }
  }
}
