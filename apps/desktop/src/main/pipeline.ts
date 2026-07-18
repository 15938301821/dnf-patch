import {
  runRequestSchema,
  type RunRequest,
  type RunSummary,
} from "../shared/contracts.js";
import { resolveInside } from "./lib/filesystem.js";
import {
  classifyPipelineFailure,
  hasMatchingImportReceipt,
  PipelineBlockedError,
} from "./pipeline/failure-policy.js";
import { runGeneratePatch } from "./pipeline/generate-runner.js";
import { runPromptImport } from "./pipeline/import-runner.js";
import { runProjectValidation } from "./pipeline/validation-runner.js";
import { RunStore } from "./run-store.js";

export { classifyPipelineFailure } from "./pipeline/failure-policy.js";

/**
 * 桌面与 CLI 共用的顶层 Run 状态机。
 *
 * 本类只负责请求解析、Run 创建、动作分派与统一失败收口；各动作的领域
 * 顺序位于独立 runner，避免新增动作继续扩大控制面入口。
 */
export class PatchPipeline {
  readonly store: RunStore;

  constructor(readonly repositoryRoot: string) {
    this.store = new RunStore(repositoryRoot);
  }

  /** 根据已验证动作调用唯一 runner，未实现动作保持显式阻断。 */
  async #dispatch(request: RunRequest): Promise<RunSummary> {
    if (
      request.action === "create-profession" ||
      request.action === "create-theme"
    ) {
      return await runPromptImport(this.repositoryRoot, this.store, request);
    }
    if (request.action === "generate-patch") {
      return await runGeneratePatch(this.repositoryRoot, this.store, request);
    }
    if (request.action === "validate-only") {
      return await runProjectValidation(
        this.repositoryRoot,
        this.store,
        request,
      );
    }
    throw new PipelineBlockedError(
      `Pipeline action is not implemented yet: ${request.action}`,
    );
  }

  /** 创建新 Run 并保证任何异常都收敛为持久化 summary。 */
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
      return await this.#dispatch(request);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const importReceiptPath = resolveInside(
        this.store.runDirectory(request.runId),
        "imports/transaction-receipt.json",
      );
      // 提交后的异常不能把已写入且有 receipt 的 Prompt 事务误报为失败。
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
        // Summary 是最终状态事实；终止事件仅作尽力记录，不能遮蔽原错误。
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
