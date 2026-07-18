import { z } from "zod";

const sha256 = z.string().regex(/^[A-F0-9]{64}$/);
const byte = z.number().int().min(0).max(255);
const rgb = z.tuple([byte, byte, byte]);
const ratio = z.number().min(0).max(1);

export const asepriteStylePlanSchema = z.object({
  schemaVersion: z.literal(1),
  kind: z.literal("dnf-aseprite-pixel-style-plan-v1"),
  runId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  compiler: z.object({
    id: z.literal("dnf-style-compiler"),
    version: z.literal("1.0.0"),
  }),
  source: z.object({
    contextBundlePath: z.string().min(1),
    contextBundleSha256: sha256,
    engineeringDesignPath: z.string().min(1),
    engineeringDesignSha256: sha256,
    modelCallRecordPath: z.string().min(1),
    modelCallRecordSha256: sha256,
    model: z.string().min(1),
    provider: z.enum(["mock", "openai"]),
    modelEvidenceEligible: z.boolean(),
    promptPackageSha256: sha256,
    executionProfileId: z.string().min(1),
  }),
  geometryPolicy: z.literal("strict-preserve-source-frame-position-size"),
  alphaPolicy: z.literal("preserve-source-alpha-byte-exact"),
  palette: z.object({
    shadow: rgb,
    midtone: rgb,
    rim: rgb,
    core: rgb,
  }),
  parameters: z.object({
    sourceColorMix: ratio,
    coreThreshold: z.number().min(0.5).max(0.95),
    coreIntensity: ratio,
    rimThreshold: z.number().min(0).max(0.8),
    rimIntensity: ratio,
    phaseAmount: ratio,
    crackDensity: z.number().min(0).max(0.25),
    crackIntensity: ratio,
  }),
  enabledOperations: z.array(
    z.enum([
      "palette-map",
      "rim-light",
      "particle-trail",
      "spatial-crack",
      "blade-core",
      "alpha-preserve",
    ]),
  ),
  safety: z.object({
    arbitraryCodeAccepted: z.literal(false),
    resourceFactsFromModel: z.literal(false),
    runtimeImageFromImageModel: z.literal(false),
    fullSkillCoverageProven: z.literal(false),
    deploymentAuthorized: z.literal(false),
  }),
});
export type AsepriteStylePlan = z.infer<typeof asepriteStylePlanSchema>;
