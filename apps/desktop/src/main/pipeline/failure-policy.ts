import { readFile } from "node:fs/promises";
import {
  importTransactionReceiptSchema,
  type RunRequest,
} from "../../shared/contracts.js";
import { fileExists, resolveInside } from "../lib/filesystem.js";
import type { RunStore } from "../run-store.js";

/** 可预期的权限、前置事实或能力缺口；最终状态应为 blocked。 */
export class PipelineBlockedError extends Error {}

/** 已提交导入优先保留成功事实，后续异常只能降级为提交后警告。 */
export function classifyPipelineFailure(
  importCommitted: boolean,
  blocked: boolean,
): "committed-with-warnings" | "blocked" | "failed" {
  if (importCommitted) {
    return "committed-with-warnings";
  }
  return blocked ? "blocked" : "failed";
}

/**
 * 判断当前 Run 是否已有与请求路由完全匹配的通过 receipt。
 *
 * 失败处理不能仅凭文件存在就声称提交成功，因此仍执行完整 Zod 解析并
 * 复核 RunId、职业和主题。损坏或其他路由的 receipt 一律视为未提交。
 */
export async function hasMatchingImportReceipt(
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
