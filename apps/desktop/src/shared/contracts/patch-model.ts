import { z } from "zod";
import {
  repositoryRelativePathSchema,
  runIdSchema,
  sha256Schema,
} from "./primitives.js";
import {
  fileSnapshotSchema,
  modelRoleSchema,
  pipelineProviderSchema,
} from "./run.js";

/** 补丁任务图、工程设计与三模型调用证据契约。 */

export const taskNodeSchema = z.object({
  id: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  role: z.enum(["controller", "engineer", "artist", "adapter", "human-review"]),
  kind: z.enum([
    "context-freeze",
    "import-plan",
    "inventory",
    "engineering-plan",
    "image-reference",
    "aseprite-adaptation",
    "npk-package",
    "independent-validation",
    "manual-review",
    "bpk-package",
  ]),
  dependsOn: z.array(z.string()),
  objective: z.string().min(1).max(2_000),
  requiredEvidence: z.array(z.string()).min(1),
  blocking: z.boolean(),
});

/** GPT-5.6 SOL 生成的有向任务图；模型不能引入任意执行或资源事实。 */
export const solTaskGraphSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  planId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  invokedSkill: z.literal("dnf-patch-maker"),
  objective: z.string().min(1).max(4_000),
  nodes: z.array(taskNodeSchema).min(2).max(64),
  factsFromManifestOnly: z.literal(true),
  arbitraryCodeExecution: z.literal(false),
  fullSkillCoverageProven: z.literal(false),
  deploymentAuthorized: z.literal(false),
});
export type SolTaskGraph = z.infer<typeof solTaskGraphSchema>;

export const styleOperationSchema = z.object({
  type: z.enum([
    "palette-map",
    "rim-light",
    "particle-trail",
    "spatial-crack",
    "blade-core",
    "alpha-preserve",
  ]),
  target: z.string().min(1).max(500).optional(),
  color: z
    .string()
    .regex(/^#[0-9A-Fa-f]{6}$/)
    .optional(),
  colorStops: z
    .array(z.string().regex(/^#[0-9A-Fa-f]{6}$/))
    .max(16)
    .optional(),
  intensity: z.number().min(0).max(1).optional(),
  density: z.number().min(0).max(1).optional(),
  direction: z.string().max(120).optional(),
  blend: z
    .enum([
      "source-preserving",
      "additive-reference-only",
      "normal-reference-only",
    ])
    .optional(),
  notes: z.string().max(1_000).optional(),
});

export const promptBindingSchema = z.object({
  geometryPolicy: z.literal("strict-preserve-source-frame-position-size"),
  professionPromptPaths: z.array(repositoryRelativePathSchema),
  themeAgentPath: repositoryRelativePathSchema,
  themePromptPaths: z.array(repositoryRelativePathSchema),
  promptPackageSha256: sha256Schema,
});

export const engineeringStepSchema = z.object({
  id: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  toolId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  dependsOn: z.array(z.string()),
  mode: z.enum(["read-only", "workspace-write"]),
  arguments: z.record(z.string(), z.json()),
  expectedOutputs: z.array(repositoryRelativePathSchema),
  successPredicates: z.array(z.string()).min(1),
  rationale: z.string().min(1).max(2_000),
});

/** GPT-5.5 生成的固定工具执行计划。 */
export const engineeringPlanSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  planId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  promptBinding: promptBindingSchema.optional(),
  palette: z
    .array(z.string().regex(/^#[0-9A-Fa-f]{6}$/))
    .min(1)
    .max(16)
    .optional(),
  styleOperations: z.array(styleOperationSchema).max(32).default([]),
  steps: z.array(engineeringStepSchema).max(64),
  unresolvedFacts: z.array(z.string()),
  requiresHumanReview: z.literal(true),
  arbitraryCodeAccepted: z.literal(false),
  resourceFactsFromModel: z.literal(false),
  fullSkillCoverageProven: z.literal(false),
  deploymentAuthorized: z.literal(false),
});
export type EngineeringPlan = z.infer<typeof engineeringPlanSchema>;

/** gpt-image-2 前后的工程化设计对象，仅描述参考素材样式。 */
export const engineeringDesignSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  phase: z.enum(["brief", "final"]),
  palette: z
    .array(z.string().regex(/^#[0-9A-Fa-f]{6}$/))
    .min(4)
    .max(16),
  styleOperations: z.array(styleOperationSchema).min(1).max(32),
  imagePrompt: z.string().min(1).max(8_000),
  rationale: z.string().min(1).max(4_000),
  risks: z.array(z.string().min(1).max(1_000)).max(32),
  unresolvedFacts: z.array(z.string().min(1).max(1_000)).max(64),
  arbitraryCodeAccepted: z.literal(false),
  resourceFactsFromModel: z.literal(false),
  fullSkillCoverageProven: z.literal(false),
  deploymentAuthorized: z.literal(false),
});
export type EngineeringDesign = z.infer<typeof engineeringDesignSchema>;

/** 每次模型调用只记录哈希与提供方元数据，不保存原始响应。 */
export const modelCallRecordSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  callId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  role: modelRoleSchema,
  model: z.string().min(1),
  provider: pipelineProviderSchema,
  status: z.enum(["passed", "failed", "skipped"]),
  startedAtUtc: z.iso.datetime(),
  finishedAtUtc: z.iso.datetime(),
  requestSha256: sha256Schema,
  responseSha256: sha256Schema.optional(),
  responseId: z.string().optional(),
  networkAuthorized: z.boolean(),
  responseStoragePolicy: z.enum([
    "store-false",
    "endpoint-does-not-expose-store-control",
    "mock-local-only",
  ]),
  error: z.string().optional(),
});
export type ModelCallRecord = z.infer<typeof modelCallRecordSchema>;

/** gpt-image-2 参考素材尝试；directRuntimeUseAllowed 固定为 false。 */
export const imageAttemptSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  attemptId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  model: z.literal("gpt-image-2"),
  promptSha256: sha256Schema,
  inputSnapshots: z.array(fileSnapshotSchema.omit({ content: true })),
  outputPath: repositoryRelativePathSchema.optional(),
  outputSha256: sha256Schema.optional(),
  backgroundPolicy: z.literal("opaque-reference-material-only"),
  directRuntimeUseAllowed: z.literal(false),
  status: z.enum(["generated", "failed", "skipped"]),
  error: z.string().optional(),
});
export type ImageAttempt = z.infer<typeof imageAttemptSchema>;
