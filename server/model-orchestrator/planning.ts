import {
  engineeringPlanSchema,
  type ContextBundle,
  type EngineeringDesign,
  type EngineeringPlan,
  type RunRequest,
} from "../shared/contracts.js";
import type { ExecutionProfile } from "../shared/profile.js";
import { computePromptPackageSha256 } from "../style-compiler.js";

/** 将冻结上下文收敛为模型可见数据，排除本机绝对路径等非必要信息。 */
export function createModelContext(context: ContextBundle): unknown {
  return {
    schemaVersion: context.schemaVersion,
    runId: context.runId,
    professionPath: context.professionPath,
    themePath: context.themePath,
    rootRules: context.rootRules,
    patchMakerSkill: context.patchMakerSkill,
    professionRules: context.professionRules,
    manifest: context.manifest,
    professionPrompts: context.professionPrompts,
    themeRules: context.themeRules,
    themePrompts: context.themePrompts,
    executionProfile: context.executionProfile,
    executionProfileInputs: context.executionProfileInputs,
    materializedConfig: context.materializedConfig,
    sourceSummary: context.sourceSummary,
    sourceInventory: context.sourceInventory,
    toolCatalog: context.toolCatalog,
    missingRequiredFacts: context.missingRequiredFacts,
    // 模型输入不能携带可提升的覆盖或部署状态。
    fullSkillCoverageProven: false,
    deploymentAuthorized: false,
  };
}

/**
 * 把最终设计绑定到仓库冻结 Prompt 和固定执行配置。
 *
 * 工具 ID、参数、输出根和执行模式全部来自已校验 profile；模型只能提供
 * 有限 style operation 与未解决事实，不能改变控制面。
 */
export function createEngineeringPlan(
  request: RunRequest,
  context: ContextBundle,
  profile: ExecutionProfile,
  design: EngineeringDesign,
): EngineeringPlan {
  const promptPackageSha256 = computePromptPackageSha256(context);

  return engineeringPlanSchema.parse({
    schemaVersion: 1,
    runId: request.runId,
    planId: `${request.runId}.engineering`,
    promptBinding: {
      geometryPolicy: "strict-preserve-source-frame-position-size",
      professionPromptPaths: profile.promptBindings.map(
        (binding) => binding.professionPromptPath,
      ),
      themeAgentPath: profile.themeAgentPath,
      themePromptPaths: profile.promptBindings.map(
        (binding) => binding.themePromptPath,
      ),
      promptPackageSha256,
    },
    palette: design.palette,
    styleOperations: design.styleOperations,
    steps: profile.steps.map((step) => ({
      ...step,
      rationale: `Fixed execution profile ${profile.id}; model output cannot change tool identity, script path, mode or output roots.`,
    })),
    unresolvedFacts: design.unresolvedFacts,
    requiresHumanReview: true,
    arbitraryCodeAccepted: false,
    resourceFactsFromModel: false,
    fullSkillCoverageProven: false,
    deploymentAuthorized: false,
  });
}
