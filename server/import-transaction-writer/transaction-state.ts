import { rmdir } from "node:fs/promises";
import { dirname } from "node:path";
import type { ImportPlan } from "../shared/contracts.js";

/** 目标写入前的可恢复字节。 */
export interface BeforeImage {
  existed: boolean;
  bytes?: Uint8Array;
  sha256?: string;
}

/** 完成所有 CAS 检查、尚未写入磁盘的事务目标。 */
export interface PreparedWrite {
  kind: ImportPlan["targets"][number]["kind"];
  relativePath: string;
  absolutePath: string;
  before: BeforeImage;
  bytes: Uint8Array;
  sha256: string;
  operation: "created" | "updated-index" | "preserved-existing";
}

/** 删除本事务新建且仍为空的父目录，不越过仓库根。 */
export async function removeEmptyParents(
  startPath: string,
  stopAt: string,
): Promise<void> {
  let current = startPath;
  while (current !== stopAt && current.startsWith(`${stopAt}\\`)) {
    try {
      await rmdir(current);
    } catch {
      // 非空、并发占用或权限错误都表示不应继续向父级删除。
      return;
    }
    current = dirname(current);
  }
}
