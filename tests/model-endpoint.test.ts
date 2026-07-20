import { z } from "zod";
import { afterEach, describe, expect, it } from "vitest";
import { AgentModelProvider } from "../server/model-provider.js";
import {
  DEFAULT_OPENAI_BASE_URL,
  OPENAI_API_KEY_ENV,
  OPENAI_BASE_URL_ENV,
  OPENAI_REQUEST_MAX_RETRIES,
  OPENAI_REQUEST_TIMEOUT_MS,
  resolveOpenAIEndpoint,
} from "../server/shared/models.js";

const originalApiKey = process.env[OPENAI_API_KEY_ENV];
const originalBaseURL = process.env[OPENAI_BASE_URL_ENV];

/** 每个测试结束后恢复宿主环境，避免模型配置影响其他测试。 */
afterEach(() => {
  restoreEnvironment(OPENAI_API_KEY_ENV, originalApiKey);
  restoreEnvironment(OPENAI_BASE_URL_ENV, originalBaseURL);
});

function restoreEnvironment(name: string, value: string | undefined): void {
  if (value === undefined) {
    Reflect.deleteProperty(process.env, name);
    return;
  }
  process.env[name] = value;
}

describe("OpenAI-compatible endpoint configuration", () => {
  it("uses the fixed official endpoint when no override is configured", () => {
    expect(resolveOpenAIEndpoint({})).toEqual({
      baseURL: DEFAULT_OPENAI_BASE_URL,
      identity: "api.openai.com/v1",
      custom: false,
    });
  });

  it("normalizes a custom HTTPS v1 endpoint without exposing credentials", () => {
    expect(
      resolveOpenAIEndpoint({
        [OPENAI_BASE_URL_ENV]: "https://gateway.example.test/v1/",
      }),
    ).toEqual({
      baseURL: "https://gateway.example.test/v1",
      identity: "gateway.example.test/v1",
      custom: true,
    });
  });

  it.each([
    "http://gateway.example.test/v1",
    "https://user:secret@gateway.example.test/v1",
    "https://gateway.example.test/v1?token=secret",
    "https://gateway.example.test/v1#fragment",
    "https://gateway.example.test",
  ])("rejects unsafe or incomplete endpoint %s", (baseURL) => {
    expect(() =>
      resolveOpenAIEndpoint({ [OPENAI_BASE_URL_ENV]: baseURL }),
    ).toThrow();
  });

  it("records a custom endpoint without attempting a request when the key is absent", async () => {
    Reflect.deleteProperty(process.env, OPENAI_API_KEY_ENV);
    process.env[OPENAI_BASE_URL_ENV] = "https://gateway.example.test/v1";
    const provider = new AgentModelProvider({
      provider: "openai",
      allowNetwork: true,
    });

    const result = await provider.structured({
      runId: "endpoint-audit",
      callId: "endpoint-audit.engineer",
      role: "engineer",
      schemaName: "endpoint_audit",
      schema: z.object({ ok: z.literal(true) }),
      instructions: "Return the test object.",
      input: "No network request is allowed without a key.",
      mockValue: { ok: true as const },
    });

    expect(result.value).toBeUndefined();
    expect(result.record).toMatchObject({
      status: "failed",
      networkAuthorized: true,
      endpointIdentity: "gateway.example.test/v1",
      requestTimeoutMs: OPENAI_REQUEST_TIMEOUT_MS,
      requestMaxRetries: OPENAI_REQUEST_MAX_RETRIES,
      responseStoragePolicy: "endpoint-does-not-expose-store-control",
    });
    expect(result.record.error).toContain(OPENAI_API_KEY_ENV);
  });

  it("fails closed and never records the API key when endpoint validation fails", async () => {
    const secret = "endpoint-test-secret";
    process.env[OPENAI_API_KEY_ENV] = secret;
    process.env[OPENAI_BASE_URL_ENV] = "http://gateway.example.test/v1";
    const provider = new AgentModelProvider({
      provider: "openai",
      allowNetwork: true,
    });

    const result = await provider.image({
      runId: "endpoint-invalid",
      callId: "endpoint-invalid.artist",
      prompt: "No request should be sent.",
    });

    expect(result.record).toMatchObject({
      status: "failed",
      endpointIdentity: "configuration-invalid",
      networkAuthorized: true,
    });
    expect(result.record.error).toContain("must use HTTPS");
    expect(JSON.stringify(result.record)).not.toContain(secret);
  });
});
