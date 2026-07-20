import { readFile } from "node:fs/promises";
import type { ToolResult } from "../shared/contracts.js";
import type { ToolCatalogEntry } from "../shared/tool-catalog.js";
import type {
  ExpandedExecutionProfile,
  ExpandedProfileStep,
} from "../profile-runtime.js";
import { resolveInside } from "../lib/filesystem.js";
import type { RunStore } from "../run-store.js";
import {
  parseJsonOutput,
  parseKeyValueOutput,
  type ToolBroker,
} from "../tool-broker.js";
import type { RunRequest } from "../shared/contracts.js";
import { PipelineBlockedError } from "./failure-policy.js";

/** 从固定 profile 步骤中要求唯一的某类输出。 */
export function requireOutputBySuffix(
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

/** 将未知 JSON 收窄为普通对象，拒绝数组与 null。 */
export function requireObject(
  value: unknown,
  label: string,
): Record<string, unknown> {
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

/**
 * 校验固定工具的领域成功谓词。
 *
 * 退出码只证明脚本结束；每个关键步骤还必须解析独立摘要，复核来源哈希、
 * 帧数量、模型 provenance、字节重算和始终未部署状态。
 */
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

/** 对选定阶段执行稳定拓扑排序；未选阶段的依赖视为已在其他阶段完成。 */
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

/** 按 profile DAG 顺序调用固定 catalog 工具并记录阶段事件。 */
export async function executeProfileSteps(
  repositoryRoot: string,
  store: RunStore,
  request: RunRequest,
  expanded: ExpandedExecutionProfile,
  broker: ToolBroker,
  tools: ReadonlyMap<string, ToolCatalogEntry>,
  phases: ExpandedProfileStep["phase"][],
): Promise<void> {
  for (const step of topologicalSteps(expanded.steps, new Set(phases))) {
    const tool = tools.get(step.toolId);
    if (!tool) {
      throw new Error(`Profile tool disappeared from catalog: ${step.toolId}`);
    }
    await store.update(request.runId, { currentStage: step.id });
    await store.emit(
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
    await assertStepSuccess(repositoryRoot, tool, step, result);
    await store.emit(
      request.runId,
      step.id,
      `Fixed catalog tool ${tool.id} passed.`,
      "info",
      `userData/runs/${request.runId}/tools/step.${step.id}/result.json`,
    );
  }
}
