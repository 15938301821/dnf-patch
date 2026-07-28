/**
 * @fileoverview 构造任务详情 Mock 中的脱敏模型调用审计样本。
 *
 * job-detail-fixtures 调用本模块生成完成态与运行态趋势数据；输入是静态测试参数，输出与正式
 * PatchTaskModelCallSample DTO 同形。无网络或状态副作用，nullable usage 只表达未计量，不能
 * 被页面解释为零；这些静态样本不证明真实 Provider 调用、吞吐或模型质量。
 */
import type { PatchTaskModelCallSample } from "../server/contracts.js";

/**
 * 构造一条最近调用审计样本；nullable 字段保持“未计量”语义。
 *
 * @param id 当前 Mock 进程内稳定的调用 ID。
 * @param role 服务端公开的固定模型角色。
 * @param model 脱敏模型标识，不包含 endpoint 或凭据。
 * @param status 调用审计状态；running 不生成 finishedAt。
 * @param createdAt 用于趋势排序的 ISO 时间。
 * @param inputTokens Provider 输入 Token，null 表示未可靠计量。
 * @param outputTokens Provider 输出 Token，null 表示未可靠计量。
 * @param totalTokens Provider 总 Token，null 表示未可靠计量。
 * @param providerLatencyMs 实际 Provider 边界耗时，null 表示未可靠计量。
 * @param outputTokensPerSecond 基于输出 Token 与 Provider 耗时计算的吞吐。
 * @returns 与正式详情 API 同形的静态调用样本。
 */
export function modelCall(
  id: string,
  role: "orchestrator" | "engineer" | "artist",
  model: string,
  status: PatchTaskModelCallSample["status"],
  createdAt: string,
  inputTokens: number | null,
  outputTokens: number | null,
  totalTokens: number | null,
  providerLatencyMs: number | null,
  outputTokensPerSecond: number | null,
): PatchTaskModelCallSample {
  return {
    id,
    role,
    model,
    status,
    createdAt,
    ...(status === "running" ? {} : { finishedAt: createdAt }),
    inputTokens,
    outputTokens,
    totalTokens,
    providerLatencyMs,
    outputTokensPerSecond,
  };
}

/**
 * 返回完成任务按时间升序排列的八条真实计量形状样本。
 *
 * @returns 与正式详情 API recentCalls 顺序一致的静态数组；不发起模型调用。
 */
export function completedModelCalls(): PatchTaskModelCallSample[] {
  return [
    modelCall(
      "complete-1",
      "orchestrator",
      "gpt-5.2",
      "passed",
      "2026-07-20T07:42:00.000Z",
      2_480,
      690,
      3_170,
      4_200,
      164.3,
    ),
    modelCall(
      "complete-2",
      "engineer",
      "gpt-5.2",
      "passed",
      "2026-07-20T07:44:00.000Z",
      3_150,
      1_240,
      4_390,
      8_500,
      145.9,
    ),
    modelCall(
      "complete-3",
      "artist",
      "gemini-3-pro-image",
      "passed",
      "2026-07-20T07:47:00.000Z",
      1_420,
      980,
      2_400,
      12_600,
      77.8,
    ),
    modelCall(
      "complete-4",
      "engineer",
      "gpt-5.2",
      "passed",
      "2026-07-20T07:50:00.000Z",
      3_020,
      1_180,
      4_200,
      7_900,
      149.4,
    ),
    modelCall(
      "complete-5",
      "artist",
      "gemini-3-pro-image",
      "passed",
      "2026-07-20T07:52:00.000Z",
      1_510,
      1_040,
      2_550,
      11_800,
      88.1,
    ),
    modelCall(
      "complete-6",
      "engineer",
      "gpt-5.2",
      "passed",
      "2026-07-20T07:55:00.000Z",
      3_260,
      1_290,
      4_550,
      8_800,
      146.6,
    ),
    modelCall(
      "complete-7",
      "artist",
      "gemini-3-pro-image",
      "passed",
      "2026-07-20T07:57:00.000Z",
      1_480,
      1_010,
      2_490,
      12_100,
      83.5,
    ),
    modelCall(
      "complete-8",
      "orchestrator",
      "gpt-5.2",
      "passed",
      "2026-07-20T07:59:00.000Z",
      1_870,
      540,
      2_410,
      3_600,
      150,
    ),
  ];
}
