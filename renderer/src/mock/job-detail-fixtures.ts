/**
 * @fileoverview 构造任务详情页的运行中与完成态同契约 Mock ViewModel。
 *
 * job-details 路由模块传入当前任务列表摘要，本模块输出工作流、逐技能阶段和模型吞吐静态样本；
 * 无网络、定时器或可变状态副作用，也不复制 Server 聚合算法。nullable usage 与 unknown 阶段
 * 保持正式 DTO 语义；样本只服务前端开发和测试，不证明 Worker、Provider 或 Artifact 真实可用。
 */
import type {
  PatchTask,
  PatchTaskDetail,
  PatchTaskModelGroup,
  PatchTaskSkillProgress,
} from "../server/contracts.js";
import { completedModelCalls, modelCall } from "./job-detail-model-calls.js";

/**
 * 将 Mock 列表摘要映射到两份稳定详情样本。
 *
 * @param job 当前 Mock 状态中已存在的任务摘要。
 * @returns 完成任务包含三技能与完整计量，其他任务返回可轮询的运行中样本。
 */
export function mockTaskDetail(job: PatchTask): PatchTaskDetail {
  return job.id === "job-demo-complete"
    ? completedDetail(job)
    : runningDetail(job);
}

/** 构造完成态详情样本；聚合值与静态八条审计调用保持一致。 */
function completedDetail(job: PatchTask): PatchTaskDetail {
  return {
    ...job,
    updatedAt: "2026-07-20T08:00:20.000Z",
    finishedAt: "2026-07-20T08:00:20.000Z",
    currentStage: "complete",
    totalSkills: 3,
    passedSkills: 3,
    workflow: [
      { key: "planning", status: "passed" },
      { key: "skill-production", status: "passed" },
      { key: "package-validation", status: "passed" },
      { key: "complete", status: "passed" },
    ],
    skills: [
      completedSkill("skill-nen-guard", "念气罩"),
      completedSkill("skill-lion-roar", "狮子吼"),
      completedSkill("skill-spiral-sphere", "螺旋念气场"),
    ],
    packageStatus: "passed",
    modelThroughput: {
      totalCalls: 8,
      egressCalls: 8,
      runningCalls: 0,
      measuredCalls: 8,
      successRate: 100,
      inputTokens: 18_190,
      outputTokens: 7_970,
      totalTokens: 26_160,
      averageOutputTokensPerSecond: 114.7,
      averageProviderLatencyMs: 8_688,
      groups: [
        modelGroup(
          "engineer",
          "gpt-5.2",
          3,
          9_430,
          3_710,
          13_140,
          147.2,
          8_400,
        ),
        modelGroup(
          "artist",
          "gemini-3-pro-image",
          3,
          4_410,
          3_030,
          7_440,
          83,
          12_167,
        ),
        modelGroup(
          "orchestrator",
          "gpt-5.2",
          2,
          4_350,
          1_230,
          5_580,
          157.7,
          3_900,
        ),
      ],
      recentCalls: completedModelCalls(),
    },
  };
}

/** 构造运行中详情样本，其中 Artist 当前调用没有 usage，界面必须显示“未计量”而非零。 */
function runningDetail(job: PatchTask): PatchTaskDetail {
  return {
    ...job,
    updatedAt: "2026-07-28T01:30:24.000Z",
    currentStage: "skill-production",
    totalSkills: 4,
    passedSkills: 1,
    workflow: [
      { key: "planning", status: "passed" },
      { key: "skill-production", status: "running" },
      { key: "package-validation", status: "pending" },
      { key: "complete", status: "pending" },
    ],
    skills: [
      completedSkill("skill-sword-guard", "格挡"),
      {
        skillId: "skill-handling-sword",
        displayName: "里·鬼剑术",
        status: "running",
        stages: [
          { key: "engineer-plan", status: "passed" },
          { key: "reference-image", status: "running" },
          { key: "aseprite-adaptation", status: "pending" },
          { key: "runtime-validation", status: "pending" },
        ],
        referenceImageAvailable: false,
      },
      pendingSkill("skill-invisible-cut", "流心：刺"),
      pendingSkill("skill-momentary-slash", "瞬斩"),
    ],
    packageStatus: "queued",
    modelThroughput: {
      totalCalls: 4,
      egressCalls: 3,
      runningCalls: 1,
      measuredCalls: 2,
      successRate: 100,
      inputTokens: 5_630,
      outputTokens: 1_930,
      totalTokens: 7_560,
      averageOutputTokensPerSecond: 152,
      averageProviderLatencyMs: 6_350,
      groups: [
        modelGroup(
          "orchestrator",
          "gpt-5.2",
          1,
          2_480,
          690,
          3_170,
          164.3,
          4_200,
        ),
        modelGroup(
          "engineer",
          "gpt-5.2",
          2,
          3_150,
          1_240,
          4_390,
          145.9,
          8_500,
          1,
        ),
        modelGroup(
          "artist",
          "gemini-3-pro-image",
          1,
          null,
          null,
          null,
          null,
          null,
          0,
        ),
      ],
      recentCalls: [
        modelCall(
          "run-orchestrator",
          "orchestrator",
          "gpt-5.2",
          "passed",
          "2026-07-28T01:20:00.000Z",
          2_480,
          690,
          3_170,
          4_200,
          164.3,
        ),
        modelCall(
          "run-engineer",
          "engineer",
          "gpt-5.2",
          "passed",
          "2026-07-28T01:23:00.000Z",
          3_150,
          1_240,
          4_390,
          8_500,
          145.9,
        ),
        modelCall(
          "blocked-engineer",
          "engineer",
          "gpt-5.2",
          "blocked",
          "2026-07-28T01:26:00.000Z",
          null,
          null,
          null,
          null,
          null,
        ),
        modelCall(
          "run-artist",
          "artist",
          "gemini-3-pro-image",
          "running",
          "2026-07-28T01:30:00.000Z",
          null,
          null,
          null,
          null,
          null,
        ),
      ],
    },
  };
}

/** 构造四阶段均通过且可申请参考图的技能样本。 */
function completedSkill(
  skillId: string,
  displayName: string,
): PatchTaskSkillProgress {
  return {
    skillId,
    displayName,
    status: "passed",
    stages: [
      { key: "engineer-plan", status: "passed" },
      { key: "reference-image", status: "passed" },
      { key: "aseprite-adaptation", status: "passed" },
      { key: "runtime-validation", status: "passed" },
    ],
    referenceImageAvailable: true,
  };
}

/** 构造尚未领取生产的技能样本，不伪造任何模型或本机阶段证据。 */
function pendingSkill(
  skillId: string,
  displayName: string,
): PatchTaskSkillProgress {
  return {
    skillId,
    displayName,
    status: "pending",
    stages: [
      { key: "engineer-plan", status: "pending" },
      { key: "reference-image", status: "pending" },
      { key: "aseprite-adaptation", status: "pending" },
      { key: "runtime-validation", status: "pending" },
    ],
    referenceImageAvailable: false,
  };
}

/** 构造静态分组；measuredCalls 可低于 calls 以表达未出站或 Provider 未计量。 */
function modelGroup(
  role: "orchestrator" | "engineer" | "artist",
  model: string,
  calls: number,
  inputTokens: number | null,
  outputTokens: number | null,
  totalTokens: number | null,
  averageOutputTokensPerSecond: number | null,
  averageProviderLatencyMs: number | null,
  measuredCalls = calls,
): PatchTaskModelGroup {
  return {
    role,
    model,
    calls,
    measuredCalls,
    inputTokens,
    outputTokens,
    totalTokens,
    averageOutputTokensPerSecond,
    averageProviderLatencyMs,
  };
}
