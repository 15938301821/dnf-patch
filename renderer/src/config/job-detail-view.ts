/**
 * @fileoverview 集中定义任务详情页面的状态、阶段和模型角色展示文案。
 *
 * 详情页与纯展示组件消费这些稳定映射；输入均来自服务端 ViewModel，输出只影响界面标签和
 * 图例颜色，不改变领域状态、不推断缺失证据，也不产生网络、路由或浏览器存储副作用。
 */
import type {
  PatchTaskModelCallStatus,
  PatchTaskModelRole,
  PatchTaskSkillStageKey,
  PatchTaskStatus,
  PatchTaskStepStatus,
  PatchTaskWorkflowStageKey,
} from "../server/contracts.js";

/** 状态标签所需的中文文案与 Ant Design 语义色。 */
export interface StatusView {
  label: string;
  color: string;
}

/** 任务摘要状态的固定展示映射，不用于判断轮询是否继续。 */
export const patchTaskStatusView: Record<PatchTaskStatus, StatusView> = {
  queued: { label: "排队中", color: "default" },
  running: { label: "制作中", color: "processing" },
  passed: { label: "已完成", color: "success" },
  failed: { label: "失败", color: "error" },
  blocked: { label: "已阻断", color: "warning" },
};

/** 阶段状态映射；unknown 明确显示证据不足，禁止退化为等待或成功。 */
export const patchTaskStepStatusView: Record<PatchTaskStepStatus, StatusView> =
  {
    pending: { label: "等待", color: "default" },
    running: { label: "进行中", color: "processing" },
    passed: { label: "已通过", color: "success" },
    failed: { label: "失败", color: "error" },
    blocked: { label: "已阻断", color: "warning" },
    unknown: { label: "证据不足", color: "default" },
  };

/** 任务级四阶段工作流文案。 */
export const workflowStageLabel: Record<PatchTaskWorkflowStageKey, string> = {
  planning: "任务规划",
  "skill-production": "逐技能制作",
  "package-validation": "封包与验证",
  complete: "制作完成",
};

/** 单技能固定生产链文案；参考图不等于可直接运行的技能帧。 */
export const skillStageLabel: Record<PatchTaskSkillStageKey, string> = {
  "engineer-plan": "工程方案",
  "reference-image": "模型参考图",
  "aseprite-adaptation": "像素适配",
  "runtime-validation": "独立验证",
};

/** 模型角色的名称和图表区分色；颜色只表达角色，不表达成功或失败。 */
export const modelRoleView: Record<
  PatchTaskModelRole,
  { label: string; color: string }
> = {
  orchestrator: { label: "编排模型", color: "#176448" },
  engineer: { label: "工程模型", color: "#b8662e" },
  artist: { label: "参考图模型", color: "#2f718c" },
  unknown: { label: "未知角色", color: "#77827a" },
};

/** 模型调用审计状态的固定展示映射。 */
export const modelCallStatusView: Record<PatchTaskModelCallStatus, StatusView> =
  {
    running: { label: "调用中", color: "processing" },
    passed: { label: "成功", color: "success" },
    failed: { label: "失败", color: "error" },
    blocked: { label: "已阻断", color: "warning" },
    abandoned: { label: "已放弃", color: "default" },
    unknown: { label: "未知", color: "default" },
  };

/**
 * 格式化可空整数计量。
 * @param value Provider usage 聚合值；null 表示未可靠计量而非零。
 * @returns 中文数字或“未计量”。
 */
export function formatMeasuredInteger(value: number | null): string {
  return value === null ? "未计量" : value.toLocaleString("zh-CN");
}

/**
 * 格式化可空小数计量。
 * @param value 吞吐、百分比等可空值；null 保持未计量语义。
 * @param fractionDigits 界面需要保留的小数位上限。
 * @returns 中文数字或“未计量”。
 */
export function formatMeasuredDecimal(
  value: number | null,
  fractionDigits = 1,
): string {
  return value === null
    ? "未计量"
    : value.toLocaleString("zh-CN", {
        maximumFractionDigits: fractionDigits,
      });
}

/**
 * 格式化 Provider 边界耗时。
 * @param milliseconds 仅覆盖实际 Provider 网络调用的可空毫秒值。
 * @returns 毫秒或秒文案；null 不显示为 0 ms。
 */
export function formatProviderLatency(milliseconds: number | null): string {
  if (milliseconds === null) return "未计量";
  return milliseconds >= 1_000
    ? `${(milliseconds / 1_000).toLocaleString("zh-CN", { maximumFractionDigits: 1 })} s`
    : `${milliseconds.toLocaleString("zh-CN")} ms`;
}

/**
 * 格式化服务端 ISO 时间用于当前客户端本地展示。
 * @param value 详情 DTO 中的 ISO 时间字符串。
 * @returns 中文本地日期时间；不会改变原始审计时间。
 */
export function formatJobDateTime(value: string): string {
  return new Date(value).toLocaleString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}
