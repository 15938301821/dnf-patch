import type { RunRequest, RunSummary } from "../shared/contracts.js";
import { buildContextBundle } from "../context-builder.js";
import { loadToolCatalog } from "../profile-loader.js";
import type { RunStore } from "../run-store.js";
import { parseJsonOutput, ToolBroker } from "../tool-broker.js";
import { requireObject } from "./profile-step-runner.js";

const VALIDATION_TOOL_IDS = ["powershell-source-gate", "project-gate"] as const;

/** 执行只读工程验证；规划模式只冻结上下文，不调用工具。 */
export async function runProjectValidation(
  repositoryRoot: string,
  store: RunStore,
  request: RunRequest,
): Promise<RunSummary> {
  const catalog = await loadToolCatalog(repositoryRoot);
  const broker = new ToolBroker(repositoryRoot, store, catalog);
  if (!request.execute) {
    const context = await buildContextBundle(repositoryRoot, request);
    await store.writeEvidence(
      request.runId,
      "context/context-bundle.json",
      context,
    );
    return store.update(request.runId, {
      status: "planned",
      currentStage: "planned-validation",
      finishedAtUtc: new Date().toISOString(),
    });
  }

  for (const toolId of VALIDATION_TOOL_IDS) {
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
  return store.update(request.runId, {
    status: "passed",
    currentStage: "validation-passed",
    finishedAtUtc: new Date().toISOString(),
  });
}
