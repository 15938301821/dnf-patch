import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  createPatchTask,
  getJobArtifactMetadata,
  server,
} from "../renderer/src/api/index.js";
import { configureMockApi } from "../renderer/src/api/mock-server.js";

beforeAll(() => {
  configureMockApi();
});

beforeEach(async () => {
  await server.post("/__mock/reset");
});

describe("patch task API", () => {
  it("sends the caller's Idempotency-Key when creating a task", async () => {
    let observedKey: unknown;
    const interceptorId = server.interceptors.request.use((config) => {
      observedKey = config.headers.get("Idempotency-Key");
      return config;
    });
    await expect(
      createPatchTask(
        {
          professionId: "profession-sword-soul",
          styleId: "style-vergil",
        },
        "patch.request-1",
      ),
    ).rejects.toMatchObject({
      response: {
        status: 409,
        data: { code: "STYLE_SKILLS_NOT_BUILD_READY" },
      },
    });
    server.interceptors.request.eject(interceptorId);
    expect(observedKey).toBe("patch.request-1");
  });

  it("keeps the mock boundary aligned with the required header", async () => {
    await expect(
      server.post("/jobs", {
        professionId: "profession-sword-soul",
        styleId: "style-vergil",
      }),
    ).rejects.toMatchObject({
      response: {
        status: 400,
        data: { code: "IDEMPOTENCY_KEY_INVALID" },
      },
    });
  });

  it("returns artifact metadata instead of mock download bytes", async () => {
    await expect(getJobArtifactMetadata("job-demo-complete")).resolves.toEqual({
      artifactName: "mock-sakura-preview.bpk",
      storageKey: "mock-artifacts/job-demo-complete/mock-sakura-preview.bpk",
      mediaType: "application/octet-stream",
      byteLength: 512,
      sha256: "A".repeat(64),
    });
  });
});
