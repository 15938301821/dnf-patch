import { z } from "zod";
import {
  chineseProseSchema,
  englishPromptSchema,
  promptDisplayNameCandidateSchema,
  repositoryRelativePathSchema,
  runIdSchema,
  safeLeafNameSchema,
  sha256Schema,
} from "./primitives.js";
import { fileSnapshotSchema } from "./run.js";

/** 职业文本导入的模型输出、固定计划、验证和事务证据契约。 */

export const importFileProposalSchema = z.object({
  relativePath: repositoryRelativePathSchema,
  kind: z.enum([
    "profession-agents",
    "profession-index",
    "profession-prompt",
    "theme-agents",
    "theme-index",
    "theme-prompt",
  ]),
  content: z.string().min(1).max(200_000),
});

/** 模型提案始终维持 inventoryPending，且禁止修改 manifest 或构建 NPK。 */
export const importProposalSchema = z.object({
  schemaVersion: z.literal(1),
  profession: safeLeafNameSchema,
  theme: safeLeafNameSchema.optional(),
  promptNames: z.array(safeLeafNameSchema).min(1).max(256),
  files: z.array(importFileProposalSchema).min(3).max(520),
  rejectedResourceClaims: z.array(z.string()),
  rejectedProcessClaims: z.array(z.string()),
  inventoryPending: z.literal(true),
  manifestCreatedOrModified: z.literal(false),
  npkBuilt: z.literal(false),
  deploymentPerformed: z.literal(false),
});
export type ImportProposal = z.infer<typeof importProposalSchema>;

/** 导入步骤顺序与权限固定，模型不能选择路径或跳过回滚。 */
export const importTaskGraphSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  workflow: z.literal("profession-text-import"),
  orderedSteps: z.tuple([
    z.literal("inspect-source"),
    z.literal("extract-prompt-outline"),
    z.literal("compute-fixed-targets"),
    z.literal("propose-fixed-target-content"),
    z.literal("write-whitelisted-targets"),
    z.literal("validate-prompt-tree"),
    z.literal("rollback-on-failure"),
  ]),
  controls: z.object({
    modelMayChoosePaths: z.literal(false),
    modelMayCreateOrModifyManifest: z.literal(false),
    modelMayBuildNpk: z.literal(false),
    modelMayDeploy: z.literal(false),
    preserveSourceBytes: z.literal(true),
    rollbackTargetBytesOnFailure: z.literal(true),
  }),
});
export type ImportTaskGraph = z.infer<typeof importTaskGraphSchema>;

export const importOutlineSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  profession: safeLeafNameSchema,
  theme: safeLeafNameSchema.optional(),
  promptDisplayNames: z.array(promptDisplayNameCandidateSchema).min(1).max(256),
  themePromptDisplayNames: z.array(promptDisplayNameCandidateSchema).max(256),
  classificationSummary: z.object({
    professionStableSemantics: z.array(z.string().min(1).max(2_000)).max(256),
    themeVisualIncrements: z.array(z.string().min(1).max(2_000)).max(256),
    rejectedResourceOrCoverageClaims: z
      .array(z.string().min(1).max(2_000))
      .max(128),
  }),
  requiresTheme: z.boolean(),
  unresolvedConflicts: z.array(z.string().min(1).max(2_000)).max(128),
});
export type ImportOutline = z.infer<typeof importOutlineSchema>;

export const importPromptSemanticSchema = z.object({
  displayName: promptDisplayNameCandidateSchema,
  professionStableSemantics: chineseProseSchema,
  professionEnglishPrompt: englishPromptSchema,
  sourceConstraints: chineseProseSchema,
  phaseAcceptance: chineseProseSchema,
  theme: z
    .object({
      englishIncrement: englishPromptSchema,
      changes: chineseProseSchema,
      acceptance: chineseProseSchema,
      exclusions: chineseProseSchema,
    })
    .optional(),
});

export const importDesignSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  profession: safeLeafNameSchema,
  theme: safeLeafNameSchema.optional(),
  professionRules: z.object({
    responsibilitiesAndBoundaries: chineseProseSchema,
    resourceFactAuthority: chineseProseSchema,
    promptLayering: chineseProseSchema,
    characterEffectWeaponCutinBoundary: chineseProseSchema,
    acceptanceAndRegression: chineseProseSchema,
    coverageStatus: chineseProseSchema,
  }),
  themeRules: z
    .object({
      objective: chineseProseSchema,
      paletteMaterialsAndStyle: chineseProseSchema,
      promptRouting: chineseProseSchema,
      modificationScopeAndBoundaries: chineseProseSchema,
      acceptanceAndRegression: chineseProseSchema,
    })
    .optional(),
  prompts: z.array(importPromptSemanticSchema).min(1).max(256),
  rejectedResourceClaims: z.array(z.string().min(1).max(2_000)).max(128),
  rejectedProcessClaims: z.array(z.string().min(1).max(2_000)).max(128),
  inventoryPending: z.literal(true),
  manifestCreatedOrModified: z.literal(false),
  npkBuilt: z.literal(false),
  deploymentPerformed: z.literal(false),
});
export type ImportDesign = z.infer<typeof importDesignSchema>;

const importIssueSchema = z.object({
  code: z.string().min(1),
  path: z.string(),
  message: z.string().min(1),
});

const importBaselineChangeSchema = z.object({
  status: z.string().length(2),
  relativePath: repositoryRelativePathSchema,
  exists: z.boolean(),
  sha256: sha256Schema.nullable(),
});

/** 本地计算的唯一目标集合和提交前基线，不接收模型自选路径。 */
export const importPlanSchema = z.object({
  schemaVersion: z.literal(1),
  status: z.enum(["passed", "failed"]),
  source: z.object({ path: z.string().min(1), sha256: sha256Schema }),
  route: z.object({
    profession: safeLeafNameSchema,
    professionPath: z.string().min(1),
    theme: safeLeafNameSchema.nullable(),
    themePath: z.string().nullable(),
  }),
  prompts: z
    .array(
      z.object({
        displayName: promptDisplayNameCandidateSchema,
        safeName: safeLeafNameSchema,
        fileName: z.string().min(4).endsWith(".md"),
      }),
    )
    .min(1)
    .max(256),
  themePrompts: z
    .array(
      z.object({
        displayName: promptDisplayNameCandidateSchema,
        safeName: safeLeafNameSchema,
        fileName: z.string().min(4).endsWith(".md"),
      }),
    )
    .max(256),
  targets: z
    .array(
      z.object({
        kind: z.enum([
          "profession-agents",
          "profession-index",
          "profession-prompt",
          "theme-agents",
          "theme-index",
          "theme-prompt",
        ]),
        path: z.string().min(1),
        relativePath: repositoryRelativePathSchema,
        state: z.enum(["existing-file", "missing"]),
      }),
    )
    .min(3)
    .max(520),
  baselineChanges: z.array(importBaselineChangeSchema).max(10_000),
  errors: z.array(importIssueSchema),
  warnings: z.array(importIssueSchema),
});
export type ImportPlan = z.infer<typeof importPlanSchema>;

export const promptTreeResultSchema = z.object({
  schemaVersion: z.literal(1),
  status: z.enum(["passed", "failed"]),
  professionPath: z.string().min(1),
  themePath: z.string().nullable(),
  source: z
    .object({ path: z.string().min(1), sha256: sha256Schema })
    .nullable(),
  changes: z.array(importBaselineChangeSchema).max(10_000),
  counts: z.object({
    professionPrompts: z.number().int().nonnegative(),
    themePrompts: z.number().int().nonnegative(),
    checkedFiles: z.number().int().nonnegative(),
    errors: z.number().int().nonnegative(),
    warnings: z.number().int().nonnegative(),
  }),
  errors: z.array(importIssueSchema),
  warnings: z.array(importIssueSchema),
});
export type PromptTreeResult = z.infer<typeof promptTreeResultSchema>;

/**
 * 导入提交 receipt 绑定源字节、路由、逐目标哈希与权威快照。
 * 通过导入只证明 Prompt 文本事务完成，不证明资源映射、NPK 或全技能覆盖。
 */
export const importTransactionReceiptSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  status: z.literal("passed"),
  source: z.object({
    relativePath: repositoryRelativePathSchema,
    sha256: sha256Schema,
    bytesPreserved: z.literal(true),
  }),
  route: z.object({
    profession: safeLeafNameSchema,
    theme: safeLeafNameSchema.optional(),
  }),
  targets: z.array(
    z.object({
      kind: z.enum([
        "profession-agents",
        "profession-index",
        "profession-prompt",
        "theme-agents",
        "theme-index",
        "theme-prompt",
      ]),
      relativePath: repositoryRelativePathSchema,
      operation: z.enum(["created", "updated-index", "preserved-existing"]),
      beforeSha256: sha256Schema.nullable(),
      afterSha256: sha256Schema,
    }),
  ),
  validationPath: repositoryRelativePathSchema,
  warningCount: z.number().int().nonnegative(),
  authoritySnapshots: z.array(fileSnapshotSchema),
  inventoryPending: z.literal(true),
  fullSkillCoverageProven: z.literal(false),
  manifestCreatedOrModified: z.literal(false),
  npkBuilt: z.literal(false),
  deploymentAuthorized: z.literal(false),
  deploymentPerformed: z.literal(false),
});
export type ImportTransactionReceipt = z.infer<
  typeof importTransactionReceiptSchema
>;
