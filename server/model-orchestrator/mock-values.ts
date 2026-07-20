import {
  engineeringDesignSchema,
  solTaskGraphSchema,
  type EngineeringDesign,
  type RunRequest,
  type SolTaskGraph,
} from "../shared/contracts.js";
import type { ExecutionProfile } from "../shared/profile.js";

/**
 * 离线 mock 提供方的确定性模型值。
 *
 * 这些对象必须经过与 OpenAI 响应相同的 Zod schema，保证测试路径不会
 * 绕过正式提供方需要满足的结构、安全布尔值和证据约束。
 */

/** 按当前 Run 选项生成固定任务图，不读取或推断任何资源映射。 */
export function createMockTaskGraph(request: RunRequest): SolTaskGraph {
  const imageDependency = request.generateImageReferences
    ? ["image-reference"]
    : ["engineering-brief"];

  return solTaskGraphSchema.parse({
    schemaVersion: 1,
    runId: request.runId,
    planId: `${request.runId}.sol`,
    invokedSkill: "dnf-patch-maker",
    objective: `Create an auditable ${request.profession}/${request.theme ?? ""} ${request.selectedSkills.join(", ")} patch candidate without deployment.`,
    nodes: [
      {
        id: "context-freeze",
        role: "controller",
        kind: "context-freeze",
        dependsOn: [],
        objective:
          "Freeze repository rules, manifest, prompts, tool catalog and execution profile.",
        requiredEvidence: ["context/context-bundle.json"],
        blocking: true,
      },
      {
        id: "source-inventory",
        role: "adapter",
        kind: "inventory",
        dependsOn: ["context-freeze"],
        objective:
          "Export manifest-authorized frames from the hash-bound official NPK.",
        requiredEvidence: ["source-summary.json", "frame-inventory.json"],
        blocking: true,
      },
      {
        id: "engineering-brief",
        role: "engineer",
        kind: "engineering-plan",
        dependsOn: ["context-freeze"],
        objective:
          "Create a bounded visual engineering brief from the frozen prompt package.",
        requiredEvidence: ["models/engineering-brief.json"],
        blocking: true,
      },
      ...(request.generateImageReferences
        ? [
            {
              id: "image-reference",
              role: "artist" as const,
              kind: "image-reference" as const,
              dependsOn: ["engineering-brief"],
              objective:
                "Create one opaque visual reference that cannot be used as a runtime frame.",
              requiredEvidence: ["models/image-attempt.json"],
              blocking: true,
            },
          ]
        : []),
      {
        id: "engineering-final",
        role: "engineer",
        kind: "engineering-plan",
        dependsOn: imageDependency,
        objective:
          "Produce the final bounded style design after considering reference material.",
        requiredEvidence: ["models/engineering-final.json"],
        blocking: true,
      },
      {
        id: "aseprite-adaptation",
        role: "adapter",
        kind: "aseprite-adaptation",
        dependsOn: ["source-inventory", "engineering-final"],
        objective:
          "Apply the compiled finite style plan to frozen source pixels in Aseprite.",
        requiredEvidence: [
          "render-summary.json",
          "layered projects",
          "runtime PNGs",
        ],
        blocking: true,
      },
      {
        id: "npk-package",
        role: "adapter",
        kind: "npk-package",
        dependsOn: ["aseprite-adaptation"],
        objective:
          "Encode runtime PNGs to original BC formats and package authorized IMG paths.",
        requiredEvidence: ["component NPK", "build-summary.json"],
        blocking: true,
      },
      {
        id: "independent-validation",
        role: "adapter",
        kind: "independent-validation",
        dependsOn: ["npk-package"],
        objective:
          "Independently validate NPK index, every frame and pixel-state policy.",
        requiredEvidence: ["build-validation-summary.json"],
        blocking: true,
      },
      {
        id: "manual-review",
        role: "human-review",
        kind: "manual-review",
        dependsOn: ["independent-validation"],
        objective:
          "Leave visual and client validation to a human; automation cannot approve it.",
        requiredEvidence: ["pending human review status"],
        blocking: true,
      },
      {
        id: "bpk-package",
        role: "controller",
        kind: "bpk-package",
        dependsOn: ["independent-validation"],
        objective:
          "Package the native NPK and immutable evidence into an application BPK container.",
        requiredEvidence: [
          "BPK manifest",
          "independent extraction verification",
        ],
        blocking: true,
      },
    ],
    factsFromManifestOnly: true,
    arbitraryCodeExecution: false,
    fullSkillCoverageProven: false,
    deploymentAuthorized: false,
  });
}

/** 创建受执行配置约束的视觉设计，供 mock 与正式模型走同一编译链。 */
export function createMockDesign(
  request: RunRequest,
  profile: ExecutionProfile,
  phase: "brief" | "final",
): EngineeringDesign {
  return engineeringDesignSchema.parse({
    schemaVersion: 1,
    runId: request.runId,
    phase,
    palette: profile.fallbackPalette,
    styleOperations: [
      {
        type: "palette-map",
        target: "existing visible source pixels only",
        colorStops: profile.fallbackPalette,
        intensity: phase === "final" ? 0.92 : 0.82,
        blend: "source-preserving",
      },
      {
        type: "blade-core",
        target: "source-luminance-gated blade strips",
        color: profile.fallbackPalette[3] ?? "#FFFFFF",
        intensity: 0.86,
        blend: "source-preserving",
      },
      {
        type: "rim-light",
        target: "source-contrast-gated edges",
        color: profile.fallbackPalette[2] ?? "#00D4FF",
        intensity: 0.58,
        blend: "source-preserving",
      },
      {
        type: "particle-trail",
        target: "existing directional particles",
        color: profile.fallbackPalette[2] ?? "#00D4FF",
        intensity: 0.18,
        direction: "inherit source motion",
        blend: "source-preserving",
      },
      {
        type: "spatial-crack",
        target: "sparse existing visible pixels",
        color: profile.fallbackPalette[2] ?? "#00D4FF",
        intensity: 0.38,
        density: 0.035,
        blend: "source-preserving",
      },
      {
        type: "alpha-preserve",
        target: "all source pixels",
        intensity: 1,
        blend: "source-preserving",
      },
    ],
    imagePrompt:
      "Opaque reference sheet for a cold blue phantom sword dance effect, sharp white blade cores, cyan spatial fractures, sparse directional particles, no text, no watermark, no UI, reference material only.",
    rationale:
      "Preserve source geometry, alpha, timing and silhouettes while applying the theme palette through a finite pixel transform.",
    risks: [
      "Reference material cannot establish resource identity.",
      "Dense glow can obscure the inherited action silhouette.",
      "Client compatibility remains unproven without user A/B testing.",
    ],
    unresolvedFacts: [],
    arbitraryCodeAccepted: false,
    resourceFactsFromModel: false,
    fullSkillCoverageProven: false,
    deploymentAuthorized: false,
  });
}
