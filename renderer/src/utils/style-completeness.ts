/**
 * @fileoverview 纯函数评估结构化职业风格的草稿有效性、送审完整性与冻结包大小。
 *
 * 页面门禁与同契约 Mock API 共同消费结果；输入为用户表单写入 DTO，输出只描述客户端可见
 * 的前置条件。本模块不替代后端授权、资源核验或 Worker 验证，所有失败原因都应阻止对应的
 * 送审或任务动作。冻结包按实际 UTF-8 JSON 字节计算，不能用字符串长度近似。
 */
import type {
  SaveProfessionStyleInput,
  SkillThemePrompt,
  ThemeDefinition,
} from "../server/contracts.js";

/** 后端冻结主题定义与逐技能 Prompt 时允许的最大 UTF-8 JSON 字节数。 */
export const STYLE_PROMPT_PACKAGE_MAX_BYTES = 48 * 1_024;

/** 风格内容不能送审或制作的稳定原因集合。 */
export type StyleCompletenessReason =
  | "theme-incomplete"
  | "skills-required"
  | "skill-prompts-mismatch"
  | "skill-prompts-incomplete"
  | "prompt-package-too-large";

/** 送审与制作共用的完整性门禁结果。 */
export interface StyleCompletenessGate {
  /** 当前内容是否满足所有客户端完整性规则。 */
  allowed: boolean;
  /** 缺少任一必填增量字段的技能稳定 ID。 */
  incompleteSkillIds: string[];
  /** 按评估顺序收集的全部阻断原因。 */
  reasons: StyleCompletenessReason[];
}

/** 私有草稿保存仍必须满足的结构与大小约束结果。 */
export interface StyleDraftValidity {
  /** 是否允许把不完整内容保存为私有草稿。 */
  allowed: boolean;
  /** 即使私有草稿也不能绕过的一一对应或包大小错误。 */
  reasons: Array<
    Extract<
      StyleCompletenessReason,
      "skill-prompts-mismatch" | "prompt-package-too-large"
    >
  >;
}

/** 送审前必须包含非空文本的公共主题字段。 */
const requiredThemeFields: ReadonlyArray<
  Exclude<keyof ThemeDefinition, "schemaVersion" | "colorAnchors">
> = [
  "goal",
  "baseStyle",
  "materialRules",
  "particleRules",
  "layeringRules",
  "constraints",
  "acceptanceCriteria",
  "exclusions",
];

/** 每个已选技能在送审前必须填写的增量字段。 */
const requiredSkillFields: ReadonlyArray<
  Exclude<keyof SkillThemePrompt, "skillId">
> = ["themePrompt", "changes", "acceptanceCriteria", "exclusions"];

/**
 * 评估私有风格草稿是否完整到足以送审或创建任务。
 *
 * @param style 页面当前的结构化写入 DTO，可能仍是不完整草稿。
 * @returns 全量原因和缺失技能；`allowed` 不代表资源门禁或后端授权已通过。
 */
export function evaluateStyleCompleteness(
  style: SaveProfessionStyleInput,
): StyleCompletenessGate {
  const reasons: StyleCompletenessReason[] = [];
  // 第一步：公共主题和至少一个技能构成送审的基础内容。
  if (!isThemeComplete(style.themeDefinition)) {
    reasons.push("theme-incomplete");
  }
  if (style.selectedSkillIds.length === 0) {
    reasons.push("skills-required");
  }

  // 第二步：技能选择与逐技能 Prompt 必须无重复且按稳定 ID 一一对应。
  const selectedIds = new Set(style.selectedSkillIds);
  const promptIds = new Set(style.skillPrompts.map((prompt) => prompt.skillId));
  if (
    selectedIds.size !== style.selectedSkillIds.length ||
    promptIds.size !== style.skillPrompts.length ||
    selectedIds.size !== promptIds.size ||
    [...selectedIds].some((skillId) => !promptIds.has(skillId))
  ) {
    reasons.push("skill-prompts-mismatch");
  }

  // 第三步：逐行检查必填增量，再以真实 UTF-8 字节限制最终冻结包。
  const incompleteSkillIds = style.skillPrompts
    .filter((prompt) =>
      requiredSkillFields.some((field) => !prompt[field].trim()),
    )
    .map((prompt) => prompt.skillId);
  if (incompleteSkillIds.length > 0) {
    reasons.push("skill-prompts-incomplete");
  }
  if (stylePromptPackageBytes(style) > STYLE_PROMPT_PACKAGE_MAX_BYTES) {
    reasons.push("prompt-package-too-large");
  }

  return {
    allowed: reasons.length === 0,
    incompleteSkillIds,
    reasons,
  };
}

/**
 * 筛出私有草稿保存也不能违反的结构与大小不变量。
 *
 * @param style 用户准备保存的结构化草稿 DTO。
 * @returns 仅包含技能对应关系和冻结包大小问题的结果；其他缺失字段仍可保存。
 */
export function evaluateStyleDraftValidity(
  style: SaveProfessionStyleInput,
): StyleDraftValidity {
  const completeness = evaluateStyleCompleteness(style);
  const reasons = completeness.reasons.filter(
    (reason): reason is StyleDraftValidity["reasons"][number] =>
      reason === "skill-prompts-mismatch" ||
      reason === "prompt-package-too-large",
  );
  return { allowed: reasons.length === 0, reasons };
}

/**
 * 计算后端任务将冻结的主题 Prompt 包 UTF-8 大小。
 *
 * @param style 仅需公共主题与逐技能增量的写入数据。
 * @returns schema v1 JSON 经 UTF-8 编码后的字节数，而非 JavaScript 字符数。
 */
export function stylePromptPackageBytes(
  style: Pick<SaveProfessionStyleInput, "themeDefinition" | "skillPrompts">,
): number {
  return new TextEncoder().encode(
    JSON.stringify({
      schemaVersion: 1,
      themeDefinition: style.themeDefinition,
      skillPrompts: style.skillPrompts,
    }),
  ).byteLength;
}

/** 判断公共主题文本与颜色锚点是否全部满足送审格式。 */
function isThemeComplete(theme: ThemeDefinition): boolean {
  return (
    requiredThemeFields.every((field) => theme[field].trim()) &&
    theme.colorAnchors.length > 0 &&
    theme.colorAnchors.every(
      (anchor) => anchor.name.trim() && /^#[A-Fa-f0-9]{6}$/u.test(anchor.value),
    )
  );
}
