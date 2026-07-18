import type { RunSummary } from "../../../shared/contracts.js";

/** 将未知异常转换为用户可见文本，不假定 IPC 抛出 Error 实例。 */
export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** 生成契约允许且适合作为证据目录名的唯一 RunId。 */
export function newRunId(): string {
  const suffix = crypto.randomUUID().replaceAll("-", "").slice(0, 10);
  return `run-${Date.now().toString(36)}-${suffix}`;
}

/** 按换行或中英文逗号拆分技能，并保留首次出现的原始显示文本。 */
export function splitSkills(value: string): string[] {
  const result: string[] = [];
  const keys = new Set<string>();
  for (const candidate of value.split(/[\n,，]+/u)) {
    const skill = candidate.trim();
    const key = skill.normalize("NFC").toLocaleLowerCase();
    if (skill && !keys.has(key)) {
      keys.add(key);
      result.push(skill);
    }
  }
  return result;
}

export function statusLabel(status: RunSummary["status"]): string {
  const labels: Record<RunSummary["status"], string> = {
    planning: "规划中",
    planned: "已规划",
    blocked: "已阻断",
    failed: "失败",
    passed: "通过",
    "committed-with-warnings": "已提交 · 有警告",
    "awaiting-human-review": "等待人工审核",
  };
  return labels[status];
}
