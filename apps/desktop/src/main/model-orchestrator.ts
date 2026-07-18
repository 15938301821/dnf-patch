import type { ZodType } from "zod";
import {
  engineeringDesignSchema,
  engineeringPlanSchema,
  imageAttemptSchema,
  modelCallRecordSchema,
  solTaskGraphSchema,
  type ContextBundle,
  type EngineeringDesign,
  type EngineeringPlan,
  type FileSnapshot,
  type ImageAttempt,
  type ModelCallRecord,
  type RunRequest,
  type SolTaskGraph,
} from "../shared/contracts.js";
import { MODEL_IDS, resolveModelId } from "../shared/models.js";
import type { ExecutionProfile } from "../shared/profile.js";
import type { AsepriteStylePlan } from "../shared/style-plan.js";
import {
  compileAsepriteStylePlan,
  computePromptPackageSha256,
} from "./style-compiler.js";
import { AgentModelProvider } from "./model-provider.js";
import type { RunStore } from "./run-store.js";
import {
  sha256Text,
  snapshotFile,
  snapshotMetadata,
  stableStringify,
} from "./lib/filesystem.js";

interface StoredModelValue<T> {
  value: T;
  valuePath: string;
  valueSnapshot: FileSnapshot;
  record: ModelCallRecord;
  recordPath: string;
  recordSnapshot: FileSnapshot;
}

export interface PatchModelArtifacts {
  taskGraph: SolTaskGraph;
  brief: EngineeringDesign;
  finalDesign: EngineeringDesign;
  engineeringPlan: EngineeringPlan;
  imageAttempt: ImageAttempt;
  stylePlan: AsepriteStylePlan;
  stylePlanPath: string;
  modelEvidenceEligible: boolean;
}

function contextForModel(context: ContextBundle): unknown {
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
    fullSkillCoverageProven: false,
    deploymentAuthorized: false,
  };
}

function mockTaskGraph(request: RunRequest): SolTaskGraph {
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

function mockDesign(
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

function assertTaskGraph(graph: SolTaskGraph, request: RunRequest): void {
  if (graph.runId !== request.runId) {
    throw new Error("SOL task graph RunId mismatch.");
  }
  const nodes = new Map(graph.nodes.map((node) => [node.id, node]));
  const requiredKinds = [
    "context-freeze",
    "inventory",
    "engineering-plan",
    "aseprite-adaptation",
    "npk-package",
    "independent-validation",
    "manual-review",
    "bpk-package",
  ] as const;
  for (const kind of requiredKinds) {
    if (!graph.nodes.some((node) => node.kind === kind)) {
      throw new Error(`SOL task graph is missing required node kind: ${kind}`);
    }
  }
  if (
    request.generateImageReferences &&
    !graph.nodes.some((node) => node.kind === "image-reference")
  ) {
    throw new Error(
      "SOL task graph is missing the requested image-reference node.",
    );
  }
  for (const node of graph.nodes) {
    for (const dependency of node.dependsOn) {
      if (!nodes.has(dependency) || dependency === node.id) {
        throw new Error(
          `SOL task graph has an invalid dependency: ${node.id}/${dependency}`,
        );
      }
    }
  }
  const visiting = new Set<string>();
  const visited = new Set<string>();
  const visit = (id: string): void => {
    if (visiting.has(id)) {
      throw new Error(`SOL task graph contains a cycle at ${id}.`);
    }
    if (visited.has(id)) {
      return;
    }
    visiting.add(id);
    for (const dependency of nodes.get(id)?.dependsOn ?? []) {
      visit(dependency);
    }
    visiting.delete(id);
    visited.add(id);
  };
  for (const id of nodes.keys()) {
    visit(id);
  }
}

function buildEngineeringPlan(
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

export class ModelOrchestrator {
  readonly #provider: AgentModelProvider;

  constructor(
    readonly repositoryRoot: string,
    readonly store: RunStore,
    request: RunRequest,
  ) {
    this.#provider = new AgentModelProvider(request);
  }

  async #storeStructured<T>(
    request: RunRequest,
    call: Parameters<AgentModelProvider["structured"]>[0] & {
      schema: ZodType<T>;
      mockValue: T;
    },
    valueEvidencePath: string,
    recordEvidencePath: string,
  ): Promise<StoredModelValue<T>> {
    const result = await this.#provider.structured(call);
    const recordPath = await this.store.writeEvidence(
      request.runId,
      recordEvidencePath,
      result.record,
    );
    const recordSnapshot = await snapshotFile(
      this.repositoryRoot,
      recordPath,
      `Model call ${result.record.callId}`,
      false,
    );
    if (!result.value) {
      throw new Error(
        result.record.error ?? `Model call failed: ${call.callId}`,
      );
    }
    const valuePath = await this.store.writeEvidence(
      request.runId,
      valueEvidencePath,
      result.value,
    );
    const valueSnapshot = await snapshotFile(
      this.repositoryRoot,
      valuePath,
      `Model output ${result.record.callId}`,
      false,
    );
    return {
      value: result.value,
      valuePath,
      valueSnapshot,
      record: result.record,
      recordPath,
      recordSnapshot,
    };
  }

  async runPatchModels(
    request: RunRequest,
    context: ContextBundle,
    contextBundlePath: string,
    contextBundleSha256: string,
    profile: ExecutionProfile,
  ): Promise<PatchModelArtifacts> {
    const modelContext = stableStringify(contextForModel(context));
    const taskGraphResult = await this.#storeStructured(
      request,
      {
        runId: request.runId,
        callId: "sol-task-graph",
        role: "orchestrator",
        schemaName: "dnf_sol_task_graph",
        schema: solTaskGraphSchema,
        instructions:
          "You are the controller for a DNF visual patch pipeline. Read the frozen root rules and dnf-patch-maker skill. Return only a dependency graph. Never choose script paths, resource mappings, frame indexes, shell commands, deployment actions or approval states. All resource facts come from the frozen manifest/profile. Keep fullSkillCoverageProven and deploymentAuthorized false.",
        input: modelContext,
        mockValue: mockTaskGraph(request),
      },
      "models/sol-task-graph.json",
      "models/calls/sol-task-graph.json",
    );
    assertTaskGraph(taskGraphResult.value, request);

    const briefResult = await this.#storeStructured(
      request,
      {
        runId: request.runId,
        callId: "engineering-brief",
        role: "engineer",
        schemaName: "dnf_engineering_brief",
        schema: engineeringDesignSchema,
        instructions:
          "You are the engineering design brain for a DNF visual patch. Return a bounded visual design only. Do not provide resource mappings, scripts, arbitrary code, tool choices, paths, shell commands, deployment, approval or compatibility claims. Preserve source geometry and alpha. Use only the allowed style operation enum and set all safety booleans to false as required by schema.",
        input: modelContext,
        mockValue: mockDesign(request, profile, "brief"),
      },
      "models/engineering-brief.json",
      "models/calls/engineering-brief.json",
    );
    if (briefResult.value.phase !== "brief") {
      throw new Error("Engineering brief returned the wrong phase.");
    }

    let imageBytes: Uint8Array | undefined;
    let imageAttempt: ImageAttempt;
    if (request.generateImageReferences) {
      const imageResult = await this.#provider.image({
        runId: request.runId,
        callId: "image-reference",
        prompt: briefResult.value.imagePrompt,
      });
      await this.store.writeEvidence(
        request.runId,
        "models/calls/image-reference.json",
        imageResult.record,
      );
      const promptSha256 = sha256Text(briefResult.value.imagePrompt);
      const inputSnapshots = [
        ...context.professionPrompts,
        ...context.themePrompts,
      ].map(snapshotMetadata);
      if (imageResult.bytes) {
        imageBytes = imageResult.bytes;
        const outputPath = await this.store.writeBinaryEvidence(
          request.runId,
          "models/image-reference.png",
          imageBytes,
        );
        const outputSnapshot = await snapshotFile(
          this.repositoryRoot,
          outputPath,
          "gpt-image-2 opaque reference",
          false,
        );
        imageAttempt = imageAttemptSchema.parse({
          schemaVersion: 1,
          runId: request.runId,
          attemptId: "image-reference",
          model: MODEL_IDS.artist,
          promptSha256,
          inputSnapshots,
          outputPath,
          outputSha256: outputSnapshot.sha256,
          backgroundPolicy: "opaque-reference-material-only",
          directRuntimeUseAllowed: false,
          status: "generated",
        });
      } else {
        imageAttempt = imageAttemptSchema.parse({
          schemaVersion: 1,
          runId: request.runId,
          attemptId: "image-reference",
          model: MODEL_IDS.artist,
          promptSha256,
          inputSnapshots,
          backgroundPolicy: "opaque-reference-material-only",
          directRuntimeUseAllowed: false,
          status:
            imageResult.record.status === "skipped" ? "skipped" : "failed",
          error: imageResult.record.error,
        });
        if (request.provider === "openai") {
          await this.store.writeEvidence(
            request.runId,
            "models/image-attempt.json",
            imageAttempt,
          );
          throw new Error(
            imageAttempt.error ?? "Image reference generation failed.",
          );
        }
      }
    } else {
      const now = new Date().toISOString();
      const skippedRecord = modelCallRecordSchema.parse({
        schemaVersion: 1,
        runId: request.runId,
        callId: "image-reference",
        role: "artist",
        model: resolveModelId("artist", process.env),
        provider: request.provider,
        status: "skipped",
        startedAtUtc: now,
        finishedAtUtc: now,
        requestSha256: sha256Text("image-reference-disabled"),
        networkAuthorized: false,
        responseStoragePolicy:
          request.provider === "mock"
            ? "mock-local-only"
            : "endpoint-does-not-expose-store-control",
        error: "Image reference generation was disabled for this Run.",
      });
      await this.store.writeEvidence(
        request.runId,
        "models/calls/image-reference.json",
        skippedRecord,
      );
      imageAttempt = imageAttemptSchema.parse({
        schemaVersion: 1,
        runId: request.runId,
        attemptId: "image-reference",
        model: MODEL_IDS.artist,
        promptSha256: sha256Text(briefResult.value.imagePrompt),
        inputSnapshots: [],
        backgroundPolicy: "opaque-reference-material-only",
        directRuntimeUseAllowed: false,
        status: "skipped",
        error: "Image reference generation was disabled for this Run.",
      });
    }
    await this.store.writeEvidence(
      request.runId,
      "models/image-attempt.json",
      imageAttempt,
    );

    const finalInput = stableStringify({
      context: contextForModel(context),
      engineeringBrief: briefResult.value,
      referenceMaterial: imageBytes
        ? "One opaque gpt-image-2 reference image is attached. Treat it as visual reference only."
        : "No image bytes are attached; do not claim that an image model affected the design.",
    });
    const finalResult = await this.#storeStructured(
      request,
      {
        runId: request.runId,
        callId: "engineering-final",
        role: "engineer",
        schemaName: "dnf_engineering_final",
        schema: engineeringDesignSchema,
        instructions:
          "Return the final bounded visual engineering design. Use the frozen prompt package and, when attached, the opaque image only as reference. Never infer resource identities from the image. Do not choose tools or paths and do not emit code. Preserve source geometry and alpha. The result will be compiled by local code into a finite numeric pixel DSL.",
        input: finalInput,
        mockValue: mockDesign(request, profile, "final"),
        ...(imageBytes
          ? { image: { bytes: imageBytes, mediaType: "image/png" as const } }
          : {}),
      },
      "models/engineering-final.json",
      "models/calls/engineering-final.json",
    );
    if (finalResult.value.phase !== "final") {
      throw new Error("Final engineering design returned the wrong phase.");
    }

    const engineeringPlan = buildEngineeringPlan(
      request,
      context,
      profile,
      finalResult.value,
    );
    await this.store.writeEvidence(
      request.runId,
      "plans/engineering-plan.json",
      engineeringPlan,
    );

    const stylePlan = compileAsepriteStylePlan({
      design: finalResult.value,
      contextBundlePath,
      contextBundleSha256,
      designPath: finalResult.valuePath,
      designSha256: finalResult.valueSnapshot.sha256,
      modelCallRecord: finalResult.record,
      modelCallRecordPath: finalResult.recordPath,
      modelCallRecordSha256: finalResult.recordSnapshot.sha256,
      promptPackageSha256: computePromptPackageSha256(context),
      profile,
    });
    const stylePlanPath = await this.store.writeEvidence(
      request.runId,
      "models/aseprite-style-plan.json",
      stylePlan,
    );

    return {
      taskGraph: taskGraphResult.value,
      brief: briefResult.value,
      finalDesign: finalResult.value,
      engineeringPlan,
      imageAttempt,
      stylePlan,
      stylePlanPath,
      modelEvidenceEligible: stylePlan.source.modelEvidenceEligible,
    };
  }
}
