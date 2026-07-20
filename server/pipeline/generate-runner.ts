import type { RunRequest, RunSummary } from "../shared/contracts.js";
import { BpkPackager } from "../bpk-packager.js";
import { snapshotFile } from "../lib/filesystem.js";
import { ModelOrchestrator } from "../model-orchestrator.js";
import {
  assertProfileCatalogBinding,
  assertProfileRequestBinding,
  loadExecutionProfile,
  loadToolCatalog,
} from "../profile-loader.js";
import {
  expandExecutionProfile,
  materializeExecutionConfig,
} from "../profile-runtime.js";
import type { RunStore } from "../run-store.js";
import { ToolBroker } from "../tool-broker.js";
import { freezePatchContext } from "./context-freeze.js";
import { PipelineBlockedError } from "./failure-policy.js";
import { executeProfileSteps } from "./profile-step-runner.js";

/** 执行补丁生成的 profile、三模型、固定工具和 BPK 离线交付链。 */
export async function runGeneratePatch(
  repositoryRoot: string,
  store: RunStore,
  request: RunRequest,
): Promise<RunSummary> {
  if (!request.profileId) {
    throw new PipelineBlockedError(
      "Patch generation requires a registered execution profile.",
    );
  }
  const profile = await loadExecutionProfile(repositoryRoot, request.profileId);
  assertProfileRequestBinding(
    profile,
    request.profession,
    request.theme,
    request.selectedSkills,
  );
  const catalog = await loadToolCatalog(repositoryRoot);
  await assertProfileCatalogBinding(repositoryRoot, profile, catalog);
  const expanded = expandExecutionProfile(profile, request);
  const broker = new ToolBroker(repositoryRoot, store, catalog);
  const tools = new Map(catalog.tools.map((tool) => [tool.id, tool]));

  if (request.execute) {
    if (request.provider !== "openai") {
      throw new PipelineBlockedError(
        "Mock model evidence cannot drive Aseprite, NPK, or BPK execution.",
      );
    }
    await store.update(request.runId, { currentStage: "config-freeze" });
    const configPath = await materializeExecutionConfig(
      repositoryRoot,
      expanded,
      request,
    );
    await store.emit(
      request.runId,
      "config-freeze",
      "Materialized the fixed execution config without model-controlled paths.",
      "info",
      configPath,
    );
    await executeProfileSteps(
      repositoryRoot,
      store,
      request,
      expanded,
      broker,
      tools,
      ["preflight", "inventory"],
    );
  }

  await store.update(request.runId, { currentStage: "context-freeze" });
  const frozen = await freezePatchContext(
    repositoryRoot,
    store,
    request,
    expanded,
  );
  await store.emit(
    request.runId,
    "context-freeze",
    "Frozen rules, profile, prompts, catalog and available source inventory.",
    "info",
    frozen.path,
  );
  if (request.execute && frozen.context.missingRequiredFacts.length > 0) {
    throw new PipelineBlockedError(
      `Formal execution is missing facts: ${frozen.context.missingRequiredFacts.join(", ")}`,
    );
  }

  await store.update(request.runId, { currentStage: "models" });
  const orchestrator = new ModelOrchestrator(repositoryRoot, store, request);
  const models = await orchestrator.runPatchModels(
    request,
    frozen.context,
    frozen.path,
    frozen.sha256,
    profile,
  );
  await store.emit(
    request.runId,
    "models",
    "Stored SOL task graph, GPT engineering design, image attempt and compiled style plan.",
    "info",
    models.stylePlanPath,
  );

  if (!request.execute) {
    return store.update(request.runId, {
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

  await executeProfileSteps(
    repositoryRoot,
    store,
    request,
    expanded,
    broker,
    tools,
    ["post-model"],
  );
  const npkSnapshot = await snapshotFile(
    repositoryRoot,
    expanded.outputNpkPath,
    "Native DNF NPK payload",
    false,
  );
  const validationSnapshot = await snapshotFile(
    repositoryRoot,
    expanded.delivery.validationSummaryPath,
    "Independent NPK validation summary",
    false,
  );
  const deliverySummaryPath = await store.writeEvidence(
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
          modelCallRecordSha256: models.stylePlan.source.modelCallRecordSha256,
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

  await store.update(request.runId, { currentStage: "bpk-package" });
  await store.emit(
    request.runId,
    "bpk-package",
    "Packaging the native NPK and immutable evidence into BPK.",
    "info",
    deliverySummaryPath,
  );
  const packager = new BpkPackager(repositoryRoot, store);
  const runRoot = `userData/runs/${request.runId}`;
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
  await store.emit(
    request.runId,
    "bpk-package",
    "BPK was independently reopened and every declared entry hash matched.",
    "info",
    packaged.verificationPath,
  );
  return store.update(request.runId, {
    status: "awaiting-human-review",
    currentStage: "awaiting-human-review",
    outputBpk: packaged.bpkPath,
    finishedAtUtc: new Date().toISOString(),
  });
}
