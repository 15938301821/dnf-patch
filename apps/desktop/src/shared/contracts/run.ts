import { z } from "zod";
import {
  repositoryRelativePathSchema,
  runIdSchema,
  safeLeafNameSchema,
  sha256Schema,
} from "./primitives.js";

/** Run、桌面状态和冻结上下文的共享契约。 */

/** 固定三模型角色；角色决定允许调用的模型与证据类型。 */
export const modelRoleSchema = z.enum(["orchestrator", "engineer", "artist"]);
export type ModelRole = z.infer<typeof modelRoleSchema>;

/** 桌面和 CLI 可提交的受控流水线动作。 */
export const pipelineActionSchema = z.enum([
  "create-profession",
  "create-theme",
  "generate-patch",
  "validate-only",
  "package-bpk",
]);
export type PipelineAction = z.infer<typeof pipelineActionSchema>;

/** 模型提供方；mock 只生成本地规划证据。 */
export const pipelineProviderSchema = z.enum(["mock", "openai"]);
export type PipelineProvider = z.infer<typeof pipelineProviderSchema>;

/**
 * Run 请求及跨字段授权边界。
 *
 * 单字段 schema 只验证格式；联网、恢复、导入来源和正式写入资格必须在
 * superRefine 中联合判断，避免 renderer 或 CLI 通过字段组合绕过约束。
 */
export const runRequestSchema = z
  .object({
    schemaVersion: z.literal(1),
    runId: runIdSchema,
    action: pipelineActionSchema,
    provider: pipelineProviderSchema,
    profession: safeLeafNameSchema,
    theme: safeLeafNameSchema.optional(),
    designText: z.string().min(1).max(200_000).optional(),
    sourceDesignPath: repositoryRelativePathSchema.optional(),
    workflowPath: repositoryRelativePathSchema.optional(),
    profileId: z
      .string()
      .regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/)
      .optional(),
    selectedSkills: z.array(safeLeafNameSchema).max(256).default([]),
    execute: z.boolean().default(false),
    resume: z.boolean().default(false),
    allowNetwork: z.boolean().default(false),
    generateImageReferences: z.boolean().default(false),
    outputBaseName: safeLeafNameSchema.default("dnf-patch"),
    outputVersion: z
      .string()
      .regex(/^[0-9]+(?:\.[0-9]+){0,2}$/)
      .default("1"),
    // 部署授权不是 UI 开关；契约将其固定为 false，防止请求提升权限。
    deploymentAuthorized: z.literal(false).default(false),
  })
  .superRefine((value, context) => {
    // 网络只能由当前 Run 显式授权，不能由 provider 选择隐式开启。
    if (value.provider === "openai" && !value.allowNetwork) {
      context.addIssue({
        code: "custom",
        path: ["allowNetwork"],
        message:
          "OpenAI provider requires explicit run-level network authorization.",
      });
    }
    // 恢复会继续已有写事务，因此必须与 execute 一起开启。
    if (value.resume && !value.execute) {
      context.addIssue({
        code: "custom",
        path: ["resume"],
        message: "Resume requires execute.",
      });
    }
    if (
      (value.action === "create-profession" ||
        value.action === "create-theme") &&
      !value.designText &&
      !value.sourceDesignPath
    ) {
      context.addIssue({
        code: "custom",
        path: ["designText"],
        message:
          "Creation actions require design text or a repository source path.",
      });
    }
    if (value.designText && value.sourceDesignPath) {
      context.addIssue({
        code: "custom",
        path: ["sourceDesignPath"],
        message: "Provide either design text or a source path, not both.",
      });
    }
    if (value.action === "create-theme" && !value.theme) {
      context.addIssue({
        code: "custom",
        path: ["theme"],
        message: "Theme creation requires a theme name.",
      });
    }
    if (value.action === "create-profession" && value.theme) {
      context.addIssue({
        code: "custom",
        path: ["theme"],
        message: "Profession creation cannot include a theme route.",
      });
    }
    // 正式导入的叶路径必须来自用户冻结名称，不能由模型临时推断。
    if (
      value.execute &&
      (value.action === "create-profession" ||
        value.action === "create-theme") &&
      value.selectedSkills.length === 0
    ) {
      context.addIssue({
        code: "custom",
        path: ["selectedSkills"],
        message:
          "Executing a creation import requires user-frozen selected skills; model-inferred names are planning-only.",
      });
    }
    const selectedSkillKeys = new Set<string>();
    for (const [index, skill] of value.selectedSkills.entries()) {
      const key = skill.normalize("NFC").toLocaleLowerCase();
      if (selectedSkillKeys.has(key)) {
        context.addIssue({
          code: "custom",
          path: ["selectedSkills", index],
          message:
            "Selected skill display names must be unique after Unicode and case normalization.",
        });
      }
      selectedSkillKeys.add(key);
    }
  });
export type RunRequest = z.infer<typeof runRequestSchema>;

/** 可哈希、可复核的仓库文件快照。 */
export const fileSnapshotSchema = z.object({
  label: z.string().min(1),
  path: repositoryRelativePathSchema,
  length: z.number().int().nonnegative(),
  sha256: sha256Schema,
  content: z.string().optional(),
});
export type FileSnapshot = z.infer<typeof fileSnapshotSchema>;

/** 模型和工具共享的冻结权威上下文。 */
export const contextBundleSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  capturedAtUtc: z.iso.datetime(),
  repositoryRoot: z.string().min(1),
  professionPath: repositoryRelativePathSchema,
  themePath: repositoryRelativePathSchema.optional(),
  rootRules: fileSnapshotSchema,
  patchMakerSkill: fileSnapshotSchema,
  importSkill: fileSnapshotSchema.optional(),
  professionRules: fileSnapshotSchema.optional(),
  manifest: fileSnapshotSchema.optional(),
  professionPromptIndex: fileSnapshotSchema.optional(),
  professionPrompts: z.array(fileSnapshotSchema),
  themeRules: fileSnapshotSchema.optional(),
  themePromptIndex: fileSnapshotSchema.optional(),
  themePrompts: z.array(fileSnapshotSchema),
  workflow: fileSnapshotSchema.optional(),
  executionProfile: fileSnapshotSchema.optional(),
  executionProfileInputs: z.array(fileSnapshotSchema),
  materializedConfig: fileSnapshotSchema.optional(),
  sourceSummary: fileSnapshotSchema.optional(),
  sourceInventory: fileSnapshotSchema.optional(),
  toolCatalog: fileSnapshotSchema,
  missingRequiredFacts: z.array(z.string()),
  fullSkillCoverageProven: z.boolean(),
  // 上下文可以描述事实，但不能通过模型上下文授予部署权限。
  deploymentAuthorized: z.literal(false),
});
export type ContextBundle = z.infer<typeof contextBundleSchema>;

/** 按顺序写入磁盘并广播给 renderer 的 Run 事件。 */
export const pipelineEventSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  sequence: z.number().int().nonnegative(),
  timestampUtc: z.iso.datetime(),
  level: z.enum(["info", "warning", "error"]),
  stage: z.string().min(1),
  message: z.string().min(1),
  evidencePath: repositoryRelativePathSchema.optional(),
});
export type PipelineEvent = z.infer<typeof pipelineEventSchema>;

/** Run 的持久化最终或中间状态。 */
export const runSummarySchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  status: z.enum([
    "planning",
    "planned",
    "blocked",
    "failed",
    "passed",
    "committed-with-warnings",
    "awaiting-human-review",
  ]),
  action: pipelineActionSchema,
  provider: pipelineProviderSchema,
  startedAtUtc: z.iso.datetime(),
  finishedAtUtc: z.iso.datetime().optional(),
  currentStage: z.string(),
  outputBpk: repositoryRelativePathSchema.optional(),
  error: z.string().optional(),
  deploymentAuthorized: z.literal(false),
  deploymentPerformed: z.literal(false),
});
export type RunSummary = z.infer<typeof runSummarySchema>;

/** 桌面端展示的模型能力，不执行隐式网络探测。 */
export const modelCapabilitySchema = z.object({
  role: modelRoleSchema,
  requestedModel: z.string().min(1),
  provider: pipelineProviderSchema,
  available: z.boolean(),
  checkedAtUtc: z.iso.datetime(),
  detail: z.string(),
});
export type ModelCapability = z.infer<typeof modelCapabilitySchema>;

/** renderer 启动时读取的只读状态。 */
export const desktopStateSchema = z.object({
  repositoryRoot: z.string(),
  professions: z.array(
    z.object({
      name: z.string(),
      themes: z.array(z.string()),
      hasManifest: z.boolean(),
    }),
  ),
  capabilities: z.array(modelCapabilitySchema),
  recentRuns: z.array(runSummarySchema),
});
export type DesktopState = z.infer<typeof desktopStateSchema>;

/** 主进程接受 Run 后返回的已验证响应。 */
export const startRunResponseSchema = z.object({
  accepted: z.boolean(),
  runId: runIdSchema,
  summary: runSummarySchema,
});
export type StartRunResponse = z.infer<typeof startRunResponseSchema>;
