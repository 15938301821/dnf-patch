/**
 * @fileoverview 创建、对齐并兼容读取职业风格表单使用的结构化值。
 *
 * 页面表单和 API 响应规范化调用这些纯函数；输入来自当前选择或后端 DTO，输出为互不共享
 * 可变数组的表单/风格对象。本模块不发请求、不修改 Store，也不把旧版字段扩展成新的技能
 * 事实；旧数据只映射到公共主题层，逐技能内容保持空白等待用户确认。
 */
import type {
  ProfessionStyle,
  SaveProfessionStyleInput,
  SkillThemePrompt,
  ThemeDefinition,
} from "../server/contracts.js";

/** 仅用于读取旧版 API 响应的最小兼容结构，不作为新的写入契约。 */
interface LegacyProfessionStyle {
  id: string;
  professionId: string;
  name: string;
  description: string;
  agent: string;
  prompt: string;
  selectedSkillIds: string[];
  publishStatus: ProfessionStyle["publishStatus"];
  updatedAt: string;
}

/**
 * 创建不共享可变数组的空主题定义。
 *
 * @returns 可直接交给新建表单的 schema v1 值；不代表内容已满足送审条件。
 */
export function createEmptyThemeDefinition(): ThemeDefinition {
  return {
    schemaVersion: 1,
    goal: "",
    baseStyle: "",
    colorAnchors: [],
    materialRules: "",
    particleRules: "",
    layeringRules: "",
    constraints: "",
    acceptanceCriteria: "",
    exclusions: "",
  };
}

/**
 * 创建允许不完整保存的私有风格草稿。
 *
 * @returns 带独立主题与技能数组的写入 DTO，仍需门禁函数判断送审和制作资格。
 */
export function createEmptyStyleInput(): SaveProfessionStyleInput {
  return {
    name: "",
    description: "",
    themeDefinition: createEmptyThemeDefinition(),
    selectedSkillIds: [],
    skillPrompts: [],
  };
}

/**
 * 使逐技能 Prompt 与当前技能选择一一对应，并保留仍被选择的已有内容。
 *
 * @param selectedSkillIds 表单当前按界面顺序选择的技能稳定 ID。
 * @param current 现有逐技能草稿；已取消选择的行不会出现在返回值中。
 * @returns 按选择顺序排列的新数组，新增技能使用空内容且不共享对象。
 */
export function reconcileSkillPrompts(
  selectedSkillIds: readonly string[],
  current: readonly SkillThemePrompt[],
): SkillThemePrompt[] {
  const currentBySkillId = new Map(
    current.map((prompt) => [prompt.skillId, prompt]),
  );
  return selectedSkillIds.map(
    (skillId) =>
      currentBySkillId.get(skillId) ?? createEmptySkillPrompt(skillId),
  );
}

/**
 * 将当前或旧版职业风格响应规范化为结构化风格 ViewModel。
 *
 * ViewModel 是整理给界面消费的形状，不等于数据库行。旧版 `agent/prompt` 仅进入公共主题
 * 约束和基线，不能据此生成逐技能事实。
 *
 * @param style API 返回的当前风格 DTO 或受限旧版结构。
 * @returns 当前结构；已是新版时保持原对象，旧版则返回新建的 schema v1 对象。
 */
export function normalizeProfessionStyle(
  style: ProfessionStyle | LegacyProfessionStyle,
): ProfessionStyle {
  if ("themeDefinition" in style) {
    return style;
  }
  return {
    id: style.id,
    professionId: style.professionId,
    name: style.name,
    description: style.description,
    themeDefinition: {
      ...createEmptyThemeDefinition(),
      baseStyle: style.prompt,
      constraints: style.agent,
    },
    selectedSkillIds: style.selectedSkillIds,
    skillPrompts: reconcileSkillPrompts(style.selectedSkillIds, []),
    publishStatus: style.publishStatus,
    updatedAt: style.updatedAt,
  };
}

/**
 * 判断逐技能草稿是否包含用户内容，用于移除前的丢失确认。
 *
 * @param prompt 表单中某个技能对应的结构化增量。
 * @returns 任一可编辑字段去除空白后非空时返回 `true`。
 */
export function hasSkillPromptContent(prompt: SkillThemePrompt): boolean {
  return [
    prompt.themePrompt,
    prompt.changes,
    prompt.acceptanceCriteria,
    prompt.exclusions,
  ].some((value) => value.trim().length > 0);
}

/** 为新选择的稳定技能 ID 创建独立空 Prompt 行。 */
function createEmptySkillPrompt(skillId: string): SkillThemePrompt {
  return {
    skillId,
    themePrompt: "",
    changes: "",
    acceptanceCriteria: "",
    exclusions: "",
  };
}
