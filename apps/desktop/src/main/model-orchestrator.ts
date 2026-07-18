import type { ZodType } from "zod";
import {
  engineeringDesignSchema,
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
import {
  createMockDesign,
  createMockTaskGraph,
} from "./model-orchestrator/mock-values.js";
import {
  createEngineeringPlan,
  createModelContext,
} from "./model-orchestrator/planning.js";
import { assertTaskGraphPolicy } from "./model-orchestrator/policy.js";

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
    const modelContext = stableStringify(createModelContext(context));
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
        mockValue: createMockTaskGraph(request),
      },
      "models/sol-task-graph.json",
      "models/calls/sol-task-graph.json",
    );
    assertTaskGraphPolicy(taskGraphResult.value, request);

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
        mockValue: createMockDesign(request, profile, "brief"),
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
      context: createModelContext(context),
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
        mockValue: createMockDesign(request, profile, "final"),
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

    const engineeringPlan = createEngineeringPlan(
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
