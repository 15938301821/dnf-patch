import { z } from "zod";
import {
  repositoryRelativePathSchema,
  runIdSchema,
  safeLeafNameSchema,
  sha256Schema,
} from "./primitives.js";
import { fileSnapshotSchema } from "./run.js";

/** 固定工具调用与离线 BPK 交付清单契约。 */

/** broker 只接受白名单工具 ID 和结构化参数，不接受命令文本。 */
export const toolInvocationSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  callId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  toolId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  arguments: z.record(z.string(), z.json()),
  allowNetwork: z.boolean(),
  execute: z.boolean(),
});
export type ToolInvocation = z.infer<typeof toolInvocationSchema>;

/** 固定工具结果携带脚本、参数和输出快照，且不能授予部署权限。 */
export const toolResultSchema = z.object({
  schemaVersion: z.literal(1),
  runId: runIdSchema,
  callId: z.string(),
  toolId: z.string(),
  status: z.enum(["passed", "failed", "blocked"]),
  startedAtUtc: z.iso.datetime(),
  finishedAtUtc: z.iso.datetime(),
  exitCode: z.number().int().nullable(),
  stdout: z.string(),
  stderr: z.string(),
  parametersSha256: sha256Schema,
  scriptSha256: sha256Schema,
  outputs: z.array(fileSnapshotSchema.omit({ content: true })),
  deploymentAuthorized: z.literal(false),
  error: z.string().optional(),
});
export type ToolResult = z.infer<typeof toolResultSchema>;

export const bpkEntrySchema = z.object({
  archivePath: z
    .string()
    .min(1)
    .refine(
      (value) => !value.startsWith("/") && !value.split("/").includes(".."),
    ),
  sourcePath: repositoryRelativePathSchema,
  length: z.number().int().nonnegative(),
  sha256: sha256Schema,
  role: z.enum([
    "npk",
    "manifest",
    "final-summary",
    "validation-evidence",
    "run-evidence",
  ]),
});

/**
 * BPK 是应用交付容器，不是 DNF 原生包。
 * 客户端兼容与部署字段固定为 false，防止封装动作提升发布结论。
 */
export const bpkManifestSchema = z.object({
  schemaVersion: z.literal(1),
  format: z.literal("dnf-patch-bpk-v1"),
  packageId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  profession: safeLeafNameSchema,
  theme: safeLeafNameSchema,
  version: z.string().regex(/^[0-9]+(?:\.[0-9]+){0,2}$/),
  createdAtUtc: z.iso.datetime(),
  entries: z.array(bpkEntrySchema).min(2),
  offlineValidationPassed: z.boolean(),
  fullSkillCoverageProven: z.boolean(),
  clientCompatibilityProven: z.literal(false),
  deploymentAuthorized: z.literal(false),
  deploymentPerformed: z.literal(false),
  note: z.literal(
    "BPK is an application delivery container, not a native DNF package. The native payload is the included NPK.",
  ),
});
export type BpkManifest = z.infer<typeof bpkManifestSchema>;
