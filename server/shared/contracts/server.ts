import { z } from "zod";

export const serverHealthSchema = z.object({
  schemaVersion: z.literal(1),
  status: z.enum(["ok", "degraded"]),
  service: z.literal("dnf-patch-server"),
  version: z.string().min(1),
  database: z.enum(["available", "unavailable"]),
  checkedAtUtc: z.iso.datetime(),
});

export const serverConnectionStateSchema = z.object({
  schemaVersion: z.literal(1),
  mode: z.enum(["disabled", "offline", "degraded", "connected"]),
  configured: z.boolean(),
  endpointIdentity: z.string().min(1).max(300),
  detail: z.string().min(1).max(1_000),
  checkedAtUtc: z.iso.datetime(),
  health: serverHealthSchema.optional(),
});

export const serverProjectSchema = z.object({
  id: z.uuid(),
  factoryId: z.string().min(1).max(128),
  clientProjectId: z.string().max(128).optional(),
  displayName: z.string().min(1).max(160),
  canonicalName: z.string().min(1).max(200),
  version: z.number().int().positive(),
  archived: z.boolean(),
  createdAtUtc: z.iso.datetime(),
  updatedAtUtc: z.iso.datetime(),
});

export const serverRunEventSchema = z.object({
  runId: z.uuid(),
  sequence: z.number().int().nonnegative(),
  level: z.enum(["info", "warning", "error"]),
  stage: z.string().min(1).max(96),
  message: z.string().min(1).max(8_000),
  evidenceArtifactId: z.uuid().optional(),
  createdAtUtc: z.iso.datetime(),
});

export const serverRunSubscriptionSchema = z.object({
  runId: z.uuid(),
  afterSequence: z.number().int().min(-1).default(-1),
});

export type ServerHealth = z.infer<typeof serverHealthSchema>;
export type ServerConnectionState = z.infer<typeof serverConnectionStateSchema>;
export type ServerProject = z.infer<typeof serverProjectSchema>;
export type ServerRunEvent = z.infer<typeof serverRunEventSchema>;
export type ServerRunSubscription = z.infer<typeof serverRunSubscriptionSchema>;
