import {
  contextBundleSchema,
  type ContextBundle,
  type RunRequest,
} from "../shared/contracts.js";
import { buildContextBundle } from "../context-builder.js";
import { snapshotFile } from "../lib/filesystem.js";
import type { ExpandedExecutionProfile } from "../profile-runtime.js";
import type { RunStore } from "../run-store.js";
import { requireOutputBySuffix } from "./profile-step-runner.js";

export interface FrozenPatchContext {
  context: ContextBundle;
  path: string;
  sha256: string;
}

/**
 * 冻结补丁生成所需的规则、Prompt、profile、配置和 inventory。
 * 仅在正式执行时绑定 materialized config 与现场 inventory；规划模式保持
 * 对缺失执行产物的真实描述，不用历史输出填充。
 */
export async function freezePatchContext(
  repositoryRoot: string,
  store: RunStore,
  request: RunRequest,
  expanded: ExpandedExecutionProfile,
): Promise<FrozenPatchContext> {
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
    await buildContextBundle(repositoryRoot, request, {
      ...(request.execute
        ? {
            materializedConfigPath: expanded.configPath,
            ...inventoryInputs,
          }
        : {}),
    }),
  );
  const path = await store.writeEvidence(
    request.runId,
    "context/context-bundle.json",
    context,
  );
  const snapshot = await snapshotFile(
    repositoryRoot,
    path,
    "Frozen context bundle",
    false,
  );
  return { context, path, sha256: snapshot.sha256 };
}
