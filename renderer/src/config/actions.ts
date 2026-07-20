import type { PipelineAction } from "../../../server/shared/contracts.js";

/** 生产动作的稳定展示配置；动作权限仍由共享 Zod 契约与主进程决定。 */
export interface ActionDefinition {
  id: PipelineAction;
  eyebrow: string;
  title: string;
  description: string;
}

export const ACTIONS: readonly ActionDefinition[] = [
  {
    id: "create-profession",
    eyebrow: "PROMPT DOMAIN",
    title: "创建职业",
    description: "把设计文本拆分为职业稳定语义与逐技能 Prompt。",
  },
  {
    id: "create-theme",
    eyebrow: "STYLE LAYER",
    title: "创建风格",
    description: "在职业 Prompt 之上创建有序主题增量，不扩张技能范围。",
  },
  {
    id: "generate-patch",
    eyebrow: "AGENTIC BUILD",
    title: "生成补丁",
    description: "按固定 profile 执行 inventory、模型、Aseprite、NPK 与 BPK。",
  },
  {
    id: "validate-only",
    eyebrow: "READ-ONLY GATE",
    title: "验证项目",
    description: "执行 PowerShell 源码与项目总门禁，不写补丁或部署目录。",
  },
];

export const DEFAULT_PROFILE = "weaponmaster.vergil.illusionslash.agentic-v1";

/** 契约枚举已校验动作，找不到展示配置表示前端配置遗漏。 */
export function actionDefinition(action: PipelineAction): ActionDefinition {
  const definition = ACTIONS.find((candidate) => candidate.id === action);
  if (!definition) {
    throw new Error(`Renderer action definition is missing: ${action}`);
  }
  return definition;
}
