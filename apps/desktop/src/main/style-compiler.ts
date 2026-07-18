import {
  engineeringDesignSchema,
  type ContextBundle,
  type EngineeringDesign,
  type ModelCallRecord,
} from "../shared/contracts.js";
import type { ExecutionProfile } from "../shared/profile.js";
import {
  asepriteStylePlanSchema,
  type AsepriteStylePlan,
} from "../shared/style-plan.js";
import { sha256Text, stableStringify } from "./lib/filesystem.js";

function parseColor(value: string): [number, number, number] {
  const normalized = value.replace(/^#/u, "");
  return [
    Number.parseInt(normalized.slice(0, 2), 16),
    Number.parseInt(normalized.slice(2, 4), 16),
    Number.parseInt(normalized.slice(4, 6), 16),
  ];
}

function operationAmount(
  design: EngineeringDesign,
  type: EngineeringDesign["styleOperations"][number]["type"],
  fallback: number,
  field: "intensity" | "density" = "intensity",
): number {
  const operation = design.styleOperations.find((item) => item.type === type);
  const value = operation?.[field];
  return typeof value === "number" ? value : fallback;
}

export interface CompileStylePlanOptions {
  design: EngineeringDesign;
  contextBundlePath: string;
  contextBundleSha256: string;
  designPath: string;
  designSha256: string;
  modelCallRecord: ModelCallRecord;
  modelCallRecordPath: string;
  modelCallRecordSha256: string;
  promptPackageSha256: string;
  profile: ExecutionProfile;
}

export function compileAsepriteStylePlan({
  design: inputDesign,
  contextBundlePath,
  contextBundleSha256,
  designPath,
  designSha256,
  modelCallRecord,
  modelCallRecordPath,
  modelCallRecordSha256,
  promptPackageSha256,
  profile,
}: CompileStylePlanOptions): AsepriteStylePlan {
  const design = engineeringDesignSchema.parse(inputDesign);
  if (design.phase !== "final") {
    throw new Error("Only a final engineering design can drive Aseprite.");
  }
  if (
    modelCallRecord.runId !== design.runId ||
    modelCallRecord.role !== "engineer" ||
    modelCallRecord.status !== "passed"
  ) {
    throw new Error("The final design is not bound to a passed engineer call.");
  }
  const palette = [...design.palette];
  if (profile.fallbackPalette.length === 0) {
    throw new Error("Execution profile fallback palette is empty.");
  }
  while (palette.length < 4) {
    const fallbackColor =
      profile.fallbackPalette[palette.length % profile.fallbackPalette.length];
    if (fallbackColor === undefined) {
      throw new Error("Execution profile fallback palette is incomplete.");
    }
    palette.push(fallbackColor);
  }
  const [shadow, midtone, rim, core] = palette;
  if (
    shadow === undefined ||
    midtone === undefined ||
    rim === undefined ||
    core === undefined
  ) {
    throw new Error("Compiled style palette must contain four colors.");
  }
  const enabled = new Set(design.styleOperations.map((item) => item.type));
  enabled.add("palette-map");
  enabled.add("alpha-preserve");

  const coreIntensity = enabled.has("blade-core")
    ? operationAmount(design, "blade-core", 0.86)
    : 0;
  const rimIntensity = enabled.has("rim-light")
    ? operationAmount(design, "rim-light", 0.58)
    : 0;
  const phaseAmount = enabled.has("particle-trail")
    ? operationAmount(design, "particle-trail", 0.18)
    : 0;
  const crackDensity = enabled.has("spatial-crack")
    ? operationAmount(design, "spatial-crack", 0.035, "density")
    : 0;
  const crackIntensity = enabled.has("spatial-crack")
    ? operationAmount(design, "spatial-crack", 0.38)
    : 0;

  return asepriteStylePlanSchema.parse({
    schemaVersion: 1,
    kind: "dnf-aseprite-pixel-style-plan-v1",
    runId: design.runId,
    compiler: { id: "dnf-style-compiler", version: "1.0.0" },
    source: {
      contextBundlePath,
      contextBundleSha256,
      engineeringDesignPath: designPath,
      engineeringDesignSha256: designSha256,
      modelCallRecordPath,
      modelCallRecordSha256,
      model: modelCallRecord.model,
      provider: modelCallRecord.provider,
      modelEvidenceEligible: modelCallRecord.provider === "openai",
      promptPackageSha256,
      executionProfileId: profile.id,
    },
    geometryPolicy: "strict-preserve-source-frame-position-size",
    alphaPolicy: "preserve-source-alpha-byte-exact",
    palette: {
      shadow: parseColor(shadow),
      midtone: parseColor(midtone),
      rim: parseColor(rim),
      core: parseColor(core),
    },
    parameters: {
      sourceColorMix: 0.08,
      coreThreshold: 0.62,
      coreIntensity,
      rimThreshold: 0.1,
      rimIntensity,
      phaseAmount,
      crackDensity,
      crackIntensity,
    },
    enabledOperations: [...enabled].sort(),
    safety: {
      arbitraryCodeAccepted: false,
      resourceFactsFromModel: false,
      runtimeImageFromImageModel: false,
      fullSkillCoverageProven: false,
      deploymentAuthorized: false,
    },
  });
}

export function computePromptPackageSha256(context: ContextBundle): string {
  const snapshots = [
    context.professionRules,
    context.manifest,
    ...context.professionPrompts,
    context.themeRules,
    ...context.themePrompts,
  ]
    .filter((item) => item !== undefined)
    .map((item) => ({ path: item.path, sha256: item.sha256 }));
  return sha256Text(stableStringify(snapshots));
}
