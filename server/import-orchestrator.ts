import type { ZodType } from "zod";
import {
  importDesignSchema,
  importOutlineSchema,
  importPlanSchema,
  importTaskGraphSchema,
  type ContextBundle,
  type FileSnapshot,
  type ModelCallRecord,
  type RunRequest,
} from "./shared/contracts.js";
import { freezeImportAuthority } from "./import-orchestrator/authority.js";
import {
  createMockImportDesign,
  createMockImportOutline,
  createMockImportTaskGraph,
} from "./import-orchestrator/mock-values.js";
import {
  existingProfessionPromptNames,
  existingThemePromptNames,
} from "./import-orchestrator/prompt-index.js";
import {
  assertImportDesign,
  assertImportOutline,
  assertImportPlan,
  assertPassedTool,
} from "./import-orchestrator/policy.js";
import type {
  ImportModelArtifacts,
  ImportSource,
} from "./import-orchestrator/types.js";
import {
  fileExists,
  resolveInside,
  snapshotFile,
  stableStringify,
} from "./lib/filesystem.js";
import { AgentModelProvider } from "./model-provider.js";
import type { RunStore } from "./run-store.js";
import { parseJsonOutput } from "./tool-broker.js";
import type { ToolBroker } from "./tool-broker.js";

export type {
  ImportModelArtifacts,
  ImportSource,
} from "./import-orchestrator/types.js";

/** 一次结构化模型输出及其落盘证据快照。 */
interface StoredModelValue<T> {
  value: T;
  valuePath: string;
  valueSnapshot: FileSnapshot;
  record: ModelCallRecord;
  recordPath: string;
  recordSnapshot: FileSnapshot;
}

/**
 * 编排职业文本导入的模型、固定工具与证据写入顺序。
 *
 * 路径、目标白名单和写事务均由本地代码决定；本类只允许模型提供结构化
 * 语义，并在每个阶段把响应与调用元数据写入当前 Run 证据目录。
 */
export class ImportOrchestrator {
  readonly #provider: AgentModelProvider;

  constructor(
    readonly repositoryRoot: string,
    readonly store: RunStore,
    readonly broker: ToolBroker,
    request: RunRequest,
  ) {
    this.#provider = new AgentModelProvider(request);
  }

  /** 调用结构化模型，并在返回给下游前冻结调用记录和输出字节。 */
  async #storeStructured<T>(
    request: RunRequest,
    call: {
      runId: string;
      callId: string;
      role: "orchestrator" | "engineer";
      schemaName: string;
      schema: ZodType<T>;
      instructions: string;
      input: string;
      mockValue: T;
    },
    valueEvidencePath: string,
    recordEvidencePath: string,
  ): Promise<StoredModelValue<T>> {
    const result = await this.#provider.structured(call);
    const recordPath = await this.store.writeEvidence(
      request.runId,
      recordEvidencePath,
      result.record,
    );
    const recordSnapshot = await snapshotFile(
      this.repositoryRoot,
      recordPath,
      `Model call ${result.record.callId}`,
      false,
    );
    if (!result.value) {
      throw new Error(
        result.record.error ?? `Model call failed: ${call.callId}`,
      );
    }

    const valuePath = await this.store.writeEvidence(
      request.runId,
      valueEvidencePath,
      result.value,
    );
    const valueSnapshot = await snapshotFile(
      this.repositoryRoot,
      valuePath,
      `Model output ${result.record.callId}`,
      false,
    );
    return {
      value: result.value,
      valuePath,
      valueSnapshot,
      record: result.record,
      recordPath,
      recordSnapshot,
    };
  }

  /** 执行只读来源检查、模型规划和固定目标计算，不写职业 Prompt 树。 */
  async run(
    request: RunRequest,
    context: ContextBundle,
    source: ImportSource,
  ): Promise<ImportModelArtifacts> {
    // 先冻结所有规则与工具字节，后续执行只接受这些哈希。
    const {
      promptContract,
      routingContract,
      decompositionContract,
      hostScript,
      inspectScript,
      planScript,
      authoritySnapshots,
    } = await freezeImportAuthority(this.repositoryRoot, context);

    const inspectResult = await this.broker.invoke({
      invocation: {
        schemaVersion: 1,
        runId: request.runId,
        callId: "import.inspect-source",
        toolId: "import-profession-inspect",
        arguments: { SourcePath: source.relativePath },
        allowNetwork: false,
        execute: true,
      },
      expectedOutputs: [],
      expectedScriptSha256: inspectScript.sha256,
      expectedHostScriptSha256: hostScript.sha256,
    });
    assertPassedTool(inspectResult, "Import source inspection");
    const inspection = parseJsonOutput(inspectResult.stdout);
    const inspectionObject =
      inspection !== null && typeof inspection === "object"
        ? (inspection as Record<string, unknown>)
        : undefined;
    const inspectionSource =
      inspectionObject?.source !== null &&
      typeof inspectionObject?.source === "object"
        ? (inspectionObject.source as Record<string, unknown>)
        : undefined;
    if (inspectionSource?.sha256 !== source.snapshot.sha256) {
      throw new Error(
        "Import source inspection hash does not match the frozen source.",
      );
    }
    await this.store.writeEvidence(
      request.runId,
      "imports/source-inspection.json",
      inspection,
    );

    // 既有索引顺序进入模型上下文，并由 outline 策略强制作为精确前缀。
    const existingNames = existingProfessionPromptNames(context);
    const existingThemeNames = existingThemePromptNames(context);
    const sourceText = source.snapshot.content ?? "";
    const importContext = {
      schemaVersion: 1,
      runId: request.runId,
      action: request.action,
      route: {
        profession: request.profession,
        ...(request.theme ? { theme: request.theme } : {}),
      },
      source: source.snapshot,
      sourceInspection: inspection,
      rootRules: context.rootRules,
      patchMakerSkill: context.patchMakerSkill,
      importSkill: context.importSkill,
      promptContract,
      routingContract,
      decompositionContract,
      existing: {
        professionRules: context.professionRules,
        manifest: context.manifest,
        professionPromptIndex: context.professionPromptIndex,
        professionPrompts: context.professionPrompts,
        themeRules: context.themeRules,
        themePromptIndex: context.themePromptIndex,
        themePrompts: context.themePrompts,
        professionPromptDisplayNamesInOrder: existingNames,
        themePromptDisplayNamesInOrder: existingThemeNames,
      },
      toolCatalog: context.toolCatalog,
      controls: {
        modelMayChoosePaths: false,
        modelMayCreateOrModifyManifest: false,
        modelMayBuildNpk: false,
        modelMayDeploy: false,
        fullSkillCoverageProven: false,
      },
    };
    const contextPath = await this.store.writeEvidence(
      request.runId,
      "context/import-context.json",
      importContext,
    );
    const contextSnapshot = await snapshotFile(
      this.repositoryRoot,
      contextPath,
      "Frozen import context",
      false,
    );
    const modelContext = stableStringify(importContext);

    const taskGraphResult = await this.#storeStructured(
      request,
      {
        runId: request.runId,
        callId: "import-sol-task-graph",
        role: "orchestrator",
        schemaName: "dnf_import_task_graph",
        schema: importTaskGraphSchema,
        instructions:
          "You are the controller for a DNF profession-text import. Return exactly the fixed workflow order required by the schema. Do not choose file paths, script paths, shell commands, resource mappings, manifest changes, NPK work, deployment, coverage, compatibility, or approval states. Preserve source bytes and require byte rollback on validation failure.",
        input: modelContext,
        mockValue: createMockImportTaskGraph(request),
      },
      "models/import-sol-task-graph.json",
      "models/calls/import-sol-task-graph.json",
    );
    if (taskGraphResult.value.runId !== request.runId) {
      throw new Error("Import SOL task graph RunId mismatch.");
    }

    const outlineResult = await this.#storeStructured(
      request,
      {
        runId: request.runId,
        callId: "import-prompt-outline",
        role: "engineer",
        schemaName: "dnf_import_prompt_outline",
        schema: importOutlineSchema,
        instructions:
          "Extract a conservative import outline from the frozen source and contracts. promptDisplayNames is the complete final profession index order: preserve every existing profession prompt title as an exact prefix, then append only source-supported entries in source order. themePromptDisplayNames is an ordered subset of promptDisplayNames: preserve every existing theme prompt as an exact prefix, then append only entries with explicit theme evidence in this source. For create-profession it must be empty; for create-theme it must be nonempty. A display name is content, not a path; do not normalize it or add extensions. When selectedSkills is nonempty, it is the complete user-authorized set of source entries and you may not add or omit entries. Separate profession-stable motion and phase semantics from theme palette/material/particle/light increments. Resource names, frame mappings, coverage claims, build steps, deployment, compatibility and safety claims are rejected evidence only. Report every unresolved routing or source conflict; never guess.",
        input: modelContext,
        mockValue: createMockImportOutline(
          request,
          sourceText,
          existingNames,
          existingThemeNames,
        ),
      },
      "models/import-prompt-outline.json",
      "models/calls/import-prompt-outline.json",
    );
    assertImportOutline(
      outlineResult.value,
      request,
      existingNames,
      existingThemeNames,
    );

    // 文件名和目标路径只由固定 PowerShell 规划器计算。
    const planResult = await this.broker.invoke({
      invocation: {
        schemaVersion: 1,
        runId: request.runId,
        callId: "import.compute-fixed-targets",
        toolId: "import-profession-plan",
        arguments: {
          SourcePath: source.relativePath,
          ProfessionName: request.profession,
          ...(request.theme ? { ThemeName: request.theme } : {}),
          PromptName: outlineResult.value.promptDisplayNames,
          ThemePromptName: outlineResult.value.themePromptDisplayNames,
        },
        allowNetwork: false,
        execute: true,
      },
      expectedOutputs: [],
      expectedScriptSha256: planScript.sha256,
      expectedHostScriptSha256: hostScript.sha256,
    });
    if (planResult.status !== "passed" || planResult.exitCode !== 0) {
      let detail = planResult.error ?? "Fixed import planning failed.";
      try {
        const failedPlan = parseJsonOutput(planResult.stdout) as {
          errors?: { message?: string }[];
        };
        const messages = failedPlan.errors
          ?.map((issue) => issue.message)
          .filter((message): message is string => Boolean(message));
        if (messages && messages.length > 0) {
          detail = `${detail} ${messages.join(" | ")}`;
        }
      } catch {
        // Broker 结果仍是权威失败证据；无法解析的 stdout 不覆盖它。
      }
      throw new Error(detail);
    }
    const plan = importPlanSchema.parse(parseJsonOutput(planResult.stdout));
    assertImportPlan(plan, request, outlineResult.value, source);
    await this.store.writeEvidence(
      request.runId,
      "imports/import-plan.json",
      plan,
    );

    // 逐目标冻结提交前字节，事务写入器稍后使用这些快照执行 CAS。
    const targetSnapshots = new Map<string, FileSnapshot | undefined>();
    for (const target of plan.targets) {
      const absolutePath = resolveInside(
        this.repositoryRoot,
        target.relativePath,
      );
      const exists = await fileExists(absolutePath);
      if (exists !== (target.state === "existing-file")) {
        throw new Error(
          `Import target state changed after planning: ${target.relativePath}`,
        );
      }
      targetSnapshots.set(
        target.relativePath,
        exists
          ? await snapshotFile(
              this.repositoryRoot,
              target.relativePath,
              `Import target before write: ${target.relativePath}`,
            )
          : undefined,
      );
    }

    const fixedTargetContext = {
      frozenImportContextSha256: contextSnapshot.sha256,
      taskGraph: taskGraphResult.value,
      outline: outlineResult.value,
      fixedPlan: {
        source: {
          relativePath: source.relativePath,
          sha256: source.snapshot.sha256,
        },
        route: {
          profession: plan.route.profession,
          theme: plan.route.theme,
        },
        prompts: plan.prompts,
        themePrompts: plan.themePrompts,
        targets: plan.targets.map(({ kind, relativePath, state }) => ({
          kind,
          relativePath,
          state,
          existingContent: targetSnapshots.get(relativePath)?.content,
        })),
      },
      authorityOrder: [
        "root rules",
        "verified existing manifest and prompt tree",
        "import contracts",
        "source design text",
      ],
      writerPolicy:
        "Existing rules and prompts are preserved byte-for-byte. Existing indexes may only receive a mechanical current-file list update. Model fields are used only for missing fixed targets.",
    };
    const designResult = await this.#storeStructured(
      request,
      {
        runId: request.runId,
        callId: "import-fixed-target-design",
        role: "engineer",
        schemaName: "dnf_import_fixed_target_design",
        schema: importDesignSchema,
        instructions:
          "Produce semantic content for every fixed profession prompt in exact plan order. You cannot add, remove, rename, reorder or choose paths. A prompt object may contain theme fields if and only if its displayName is in fixedPlan.themePrompts; never invent theme content for other profession prompts. Follow the four-section profession Prompt and five-section theme Prompt contracts, but return only the schema fields, never Markdown files. Chinese prose fields must be conservative and source-grounded; English prompt fields must contain English only. Existing rules, manifests and prompts are higher authority and may not be weakened. Do not emit NPK/IMG mappings, frame counts, coverage completion, compatibility, safety, build, deployment, model endpoint, seed, shell, code, or approval claims. Keep every required safety boolean at its fixed false/pending value.",
        input: stableStringify(fixedTargetContext),
        mockValue: createMockImportDesign(
          request,
          plan.prompts.map((prompt) => prompt.displayName),
          plan.themePrompts.map((prompt) => prompt.displayName),
        ),
      },
      "models/import-fixed-target-design.json",
      "models/calls/import-fixed-target-design.json",
    );
    assertImportDesign(designResult.value, request, plan);

    return {
      taskGraph: taskGraphResult.value,
      outline: outlineResult.value,
      plan,
      design: designResult.value,
      contextPath,
      contextSha256: contextSnapshot.sha256,
      targetSnapshots,
      authoritySnapshots,
      modelEvidenceEligible:
        designResult.record.provider === "openai" &&
        designResult.record.status === "passed" &&
        designResult.record.responseStoragePolicy === "store-false",
    };
  }
}
