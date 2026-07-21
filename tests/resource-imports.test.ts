import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  createResourceImportJob,
  getResourceImportOverview,
  server,
} from "../renderer/src/api/index.js";
import { configureMockApi } from "../renderer/src/api/mock-server.js";

beforeAll(() => {
  configureMockApi();
});

beforeEach(async () => {
  await server.post("/__mock/reset");
});

describe("resource import API", () => {
  it("reports the server-side resource import boundary", async () => {
    await expect(getResourceImportOverview()).resolves.toMatchObject({
      mode: "server-mirror",
      status: "idle",
      resourceRootConfigured: true,
    });
  });

  it("queues a backend worker import job", async () => {
    const job = await createResourceImportJob();
    expect(job).toMatchObject({
      mode: "server-mirror",
      status: "queued",
    });

    await expect(getResourceImportOverview()).resolves.toMatchObject({
      lastJobId: job.id,
      status: "queued",
    });
  });
});
