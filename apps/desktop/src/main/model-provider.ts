import OpenAI from "openai";
import { zodTextFormat } from "openai/helpers/zod";
import type { z } from "zod";
import {
  modelCallRecordSchema,
  type ModelCallRecord,
  type ModelRole,
  type PipelineProvider,
  type RunRequest,
} from "../shared/contracts.js";
import { OPENAI_API_KEY_ENV, resolveModelId } from "../shared/models.js";
import { sha256Buffer, sha256Text, stableStringify } from "./lib/filesystem.js";

export interface StructuredModelCall<T> {
  runId: string;
  callId: string;
  role: Exclude<ModelRole, "artist">;
  schemaName: string;
  schema: z.ZodType<T>;
  instructions: string;
  input: string;
  mockValue: T;
  image?: {
    bytes: Uint8Array;
    mediaType: "image/png";
  };
}

export interface StructuredModelResult<T> {
  value?: T;
  record: ModelCallRecord;
}

export interface ImageModelCall {
  runId: string;
  callId: string;
  prompt: string;
}

export interface ImageModelResult {
  bytes?: Uint8Array;
  record: ModelCallRecord;
  revisedPrompt?: string;
}

function safeError(error: unknown, apiKey?: string): string {
  const raw = error instanceof Error ? error.message : String(error);
  const redacted = apiKey ? raw.replaceAll(apiKey, "[REDACTED]") : raw;
  return redacted.slice(0, 4_000);
}

function finishedRecord(
  input: Omit<ModelCallRecord, "schemaVersion" | "finishedAtUtc">,
): ModelCallRecord {
  return modelCallRecordSchema.parse({
    schemaVersion: 1,
    ...input,
    finishedAtUtc: new Date().toISOString(),
  });
}

export class AgentModelProvider {
  readonly provider: PipelineProvider;
  readonly allowNetwork: boolean;
  readonly #apiKey: string | undefined;
  readonly #client: OpenAI | undefined;

  constructor(request: Pick<RunRequest, "provider" | "allowNetwork">) {
    this.provider = request.provider;
    this.allowNetwork = request.allowNetwork;
    this.#apiKey = process.env[OPENAI_API_KEY_ENV]?.trim();
    if (this.provider === "openai" && this.allowNetwork && this.#apiKey) {
      this.#client = new OpenAI({ apiKey: this.#apiKey });
    }
  }

  async structured<T>(
    call: StructuredModelCall<T>,
  ): Promise<StructuredModelResult<T>> {
    const model = resolveModelId(call.role, process.env);
    const startedAtUtc = new Date().toISOString();
    const imageDataUrl = call.image
      ? `data:${call.image.mediaType};base64,${Buffer.from(call.image.bytes).toString("base64")}`
      : undefined;
    const input = imageDataUrl
      ? [
          {
            role: "user" as const,
            content: [
              { type: "input_text" as const, text: call.input },
              {
                type: "input_image" as const,
                detail: "high" as const,
                image_url: imageDataUrl,
              },
            ],
          },
        ]
      : call.input;
    const bodyEvidence = {
      model,
      instructions: call.instructions,
      input,
      text: { format: call.schemaName },
      tools: [],
      store: false,
      reasoning: { effort: call.role === "orchestrator" ? "high" : "medium" },
    };
    const requestSha256 = sha256Text(stableStringify(bodyEvidence));

    if (this.provider === "mock") {
      const value = call.schema.parse(call.mockValue);
      const responseSha256 = sha256Text(stableStringify(value));
      return {
        value,
        record: finishedRecord({
          runId: call.runId,
          callId: call.callId,
          role: call.role,
          model,
          provider: "mock",
          status: "passed",
          startedAtUtc,
          requestSha256,
          responseSha256,
          networkAuthorized: false,
          responseStoragePolicy: "mock-local-only",
        }),
      };
    }

    if (!this.allowNetwork) {
      return {
        record: finishedRecord({
          runId: call.runId,
          callId: call.callId,
          role: call.role,
          model,
          provider: "openai",
          status: "failed",
          startedAtUtc,
          requestSha256,
          networkAuthorized: false,
          responseStoragePolicy: "store-false",
          error:
            "OpenAI call blocked because this Run did not authorize network access.",
        }),
      };
    }
    if (!this.#client || !this.#apiKey) {
      return {
        record: finishedRecord({
          runId: call.runId,
          callId: call.callId,
          role: call.role,
          model,
          provider: "openai",
          status: "failed",
          startedAtUtc,
          requestSha256,
          networkAuthorized: true,
          responseStoragePolicy: "store-false",
          error: `${OPENAI_API_KEY_ENV} is not available in the process environment.`,
        }),
      };
    }

    try {
      const response = await this.#client.responses.parse({
        model,
        instructions: call.instructions,
        input,
        text: { format: zodTextFormat(call.schema, call.schemaName) },
        tools: [],
        store: false,
        reasoning: {
          effort: call.role === "orchestrator" ? "high" : "medium",
        },
      });
      if (response.output_parsed === null) {
        throw new Error("The model returned no parsed structured output.");
      }
      const value = call.schema.parse(response.output_parsed);
      return {
        value,
        record: finishedRecord({
          runId: call.runId,
          callId: call.callId,
          role: call.role,
          model,
          provider: "openai",
          status: "passed",
          startedAtUtc,
          requestSha256,
          responseSha256: sha256Text(
            stableStringify({ id: response.id, output: value }),
          ),
          responseId: response.id,
          networkAuthorized: true,
          responseStoragePolicy: "store-false",
        }),
      };
    } catch (error) {
      return {
        record: finishedRecord({
          runId: call.runId,
          callId: call.callId,
          role: call.role,
          model,
          provider: "openai",
          status: "failed",
          startedAtUtc,
          requestSha256,
          networkAuthorized: true,
          responseStoragePolicy: "store-false",
          error: safeError(error, this.#apiKey),
        }),
      };
    }
  }

  async image(call: ImageModelCall): Promise<ImageModelResult> {
    const model = resolveModelId("artist", process.env);
    const startedAtUtc = new Date().toISOString();
    const bodyEvidence = {
      model,
      prompt: call.prompt,
      n: 1,
      size: "1536x1024",
      quality: "high",
      background: "opaque",
      output_format: "png",
    };
    const requestSha256 = sha256Text(stableStringify(bodyEvidence));

    if (this.provider === "mock") {
      return {
        record: finishedRecord({
          runId: call.runId,
          callId: call.callId,
          role: "artist",
          model,
          provider: "mock",
          status: "skipped",
          startedAtUtc,
          requestSha256,
          networkAuthorized: false,
          responseStoragePolicy: "mock-local-only",
          error:
            "Mock provider does not call gpt-image-2 or create image bytes.",
        }),
      };
    }
    if (!this.allowNetwork) {
      return {
        record: finishedRecord({
          runId: call.runId,
          callId: call.callId,
          role: "artist",
          model,
          provider: "openai",
          status: "failed",
          startedAtUtc,
          requestSha256,
          networkAuthorized: false,
          responseStoragePolicy: "endpoint-does-not-expose-store-control",
          error:
            "OpenAI image call blocked because this Run did not authorize network access.",
        }),
      };
    }
    if (!this.#client || !this.#apiKey) {
      return {
        record: finishedRecord({
          runId: call.runId,
          callId: call.callId,
          role: "artist",
          model,
          provider: "openai",
          status: "failed",
          startedAtUtc,
          requestSha256,
          networkAuthorized: true,
          responseStoragePolicy: "endpoint-does-not-expose-store-control",
          error: `${OPENAI_API_KEY_ENV} is not available in the process environment.`,
        }),
      };
    }

    try {
      const response = await this.#client.images.generate({
        model,
        prompt: call.prompt,
        n: 1,
        size: "1536x1024",
        quality: "high",
        background: "opaque",
        output_format: "png",
      });
      const image = response.data?.[0];
      if (!image?.b64_json) {
        throw new Error("gpt-image-2 returned no base64 image payload.");
      }
      const bytes = Buffer.from(image.b64_json, "base64");
      if (bytes.length === 0) {
        throw new Error("gpt-image-2 returned an empty image payload.");
      }
      return {
        bytes,
        ...(image.revised_prompt
          ? { revisedPrompt: image.revised_prompt }
          : {}),
        record: finishedRecord({
          runId: call.runId,
          callId: call.callId,
          role: "artist",
          model,
          provider: "openai",
          status: "passed",
          startedAtUtc,
          requestSha256,
          responseSha256: sha256Buffer(bytes),
          networkAuthorized: true,
          responseStoragePolicy: "endpoint-does-not-expose-store-control",
        }),
      };
    } catch (error) {
      return {
        record: finishedRecord({
          runId: call.runId,
          callId: call.callId,
          role: "artist",
          model,
          provider: "openai",
          status: "failed",
          startedAtUtc,
          requestSha256,
          networkAuthorized: true,
          responseStoragePolicy: "endpoint-does-not-expose-store-control",
          error: safeError(error, this.#apiKey),
        }),
      };
    }
  }
}
