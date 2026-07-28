/**
 * @fileoverview 验证任务 API 的幂等请求头、Mock 门禁与产物元数据边界。
 *
 * Axios Mock Adapter 替代真实 Server、Worker 和对象存储，并在每例前重置内存状态；测试可证明
 * 客户端请求形状与替身语义，不证明真实任务调度、制作、上传、下载或产物校验。
 */
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  archiveJob,
  authorizeJobArtifactDownload,
  authorizeJobReferenceImageDownload,
  authorizeJobSkillPreviewDownload,
  createPatchTask,
  downloadJobArtifact,
  downloadJobReferenceImage,
  downloadJobSkillPreview,
  getJobArtifacts,
  getJobDetail,
  getJobsList,
  server,
} from "../renderer/src/api/index.js";
import { configureMockApi } from "../renderer/src/mock/index.js";

beforeAll(() => {
  // 仅安装同契约内存适配器，不建立真实网络连接。
  configureMockApi();
});

beforeEach(async () => {
  await server.post("/__mock/reset");
});

describe("patch task API", () => {
  it("sends the caller's Idempotency-Key when creating a task", async () => {
    // 请求拦截器只观察最终 Axios 头；任务仍应被资源门禁阻断，不能据此认为 Worker 已运行。
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

  it("advances a running task on consecutive list polls", async () => {
    // 连续 API 调用替代 Hook timer，只证明 Mock 响应可观察变化；串行调度与 DOM 更新由 E2E 覆盖。
    const first = await getJobsList();
    const second = await getJobsList();
    const firstProgress = first.find(
      (job) => job.id === "job-demo-running",
    )?.progress;
    const secondProgress = second.find(
      (job) => job.id === "job-demo-running",
    )?.progress;

    expect(firstProgress).toBeTypeOf("number");
    expect(secondProgress).toBe((firstProgress ?? 0) + 1);
  });

  it("rejects archiving an active task and keeps it visible", async () => {
    await expect(archiveJob("job-demo-running")).rejects.toMatchObject({
      response: {
        status: 409,
        data: { code: "PATCH_TASK_ACTIVE" },
      },
    });
    await expect(getJobsList()).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: "job-demo-running" }),
      ]),
    );
  });

  it("hides an archived terminal task while retaining detail and artifacts", async () => {
    await expect(archiveJob("job-demo-complete")).resolves.toBeUndefined();

    const visibleJobs = await getJobsList();
    expect(visibleJobs).not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: "job-demo-complete" }),
      ]),
    );
    await expect(getJobDetail("job-demo-complete")).resolves.toMatchObject({
      id: "job-demo-complete",
      status: "passed",
    });
    await expect(getJobArtifacts("job-demo-complete")).resolves.toHaveLength(3);
  });

  it("returns three distinct Package artifact roles without object bytes", async () => {
    const artifacts = await getJobArtifacts("job-demo-complete");

    expect(artifacts.map((artifact) => artifact.role)).toEqual([
      "candidate",
      "manifest",
      "validation",
    ]);
    expect(new Set(artifacts.map((artifact) => artifact.artifactId)).size).toBe(
      3,
    );
    expect(new Set(artifacts.map((artifact) => artifact.sha256)).size).toBe(3);
  });

  it("requests a short-lived download authorization by fixed role", async () => {
    const authorization = await authorizeJobArtifactDownload(
      "job-demo-complete",
      "validation",
    );

    expect(authorization.role).toBe("validation");
    expect(authorization.artifactName).toBe("validation.json");
    expect(authorization.sha256).toBe("C".repeat(64));
    expect(authorization.downloadUrl.startsWith("data:application/json")).toBe(
      true,
    );
  });

  it("reads authorized bytes through the typed API", async () => {
    const result = await downloadJobArtifact("job-demo-complete", "validation");

    expect(result.artifact.role).toBe("validation");
    await expect(result.blob.text()).resolves.toBe("M".repeat(384));
  });

  it("returns running and completed detail views without filling missing usage", async () => {
    const [running, completed] = await Promise.all([
      getJobDetail("job-demo-running"),
      getJobDetail("job-demo-complete"),
    ]);

    expect(running.status).toBe("running");
    expect(running.currentStage).toBe("skill-production");
    expect(
      running.modelThroughput.recentCalls.find(
        (call) => call.id === "run-artist",
      )?.outputTokensPerSecond,
    ).toBeNull();
    expect(completed.status).toBe("passed");
    expect(completed.passedSkills).toBe(completed.totalSkills);
    expect(completed.modelThroughput.measuredCalls).toBe(8);
  });

  it("authorizes a reference image by task and fixed skill instead of Artifact ID", async () => {
    const authorization = await authorizeJobReferenceImageDownload(
      "job-demo-complete",
      "skill-nen-guard",
    );

    expect(authorization.skillId).toBe("skill-nen-guard");
    expect(authorization.mediaType).toBe("image/png");
    expect(authorization.downloadUrl).not.toContain(authorization.artifactId);
  });

  it("verifies PNG signature and length before returning a reference Blob", async () => {
    // fetch 替身只替代静态资源读取；授权仍经过 Axios Mock，测试不证明真实对象存储或网络可用。
    const originalFetch = globalThis.fetch;
    const bytes = new Uint8Array(4_841_702);
    bytes.set([137, 80, 78, 71, 13, 10, 26, 10]);
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(new Blob([bytes], { type: "image/png" }), { status: 200 }),
      );
    try {
      const result = await downloadJobReferenceImage(
        "job-demo-complete",
        "skill-nen-guard",
      );
      expect(result.image.skillId).toBe("skill-nen-guard");
      expect(result.blob.type).toBe("image/png");
      expect(result.blob.size).toBe(4_841_702);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("downloads a fixed comparison role with public same-frame metadata", async () => {
    const originalFetch = globalThis.fetch;
    const bytes = new Uint8Array(4_841_702);
    bytes.set([137, 80, 78, 71, 13, 10, 26, 10]);
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(new Blob([bytes], { type: "image/png" }), { status: 200 }),
      );
    try {
      const authorization = await authorizeJobSkillPreviewDownload(
        "job-demo-complete",
        "skill-nen-guard",
        "source-frame",
      );
      expect(authorization.role).toBe("source-frame");
      expect(authorization.frame).toMatchObject({
        frameIndex: 3,
        internalPath: "sprite/effect/nen_guard.img",
      });

      const result = await downloadJobSkillPreview(
        "job-demo-complete",
        "skill-nen-guard",
        "aseprite-result",
      );
      expect(result.image.role).toBe("aseprite-result");
      expect(result.image.frame).toEqual(authorization.frame);
      expect(result.blob.type).toBe("image/png");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("rejects reference image access for a skill without current passed evidence", async () => {
    await expect(
      authorizeJobReferenceImageDownload(
        "job-demo-running",
        "skill-handling-sword",
      ),
    ).rejects.toMatchObject({
      response: {
        status: 404,
        data: { code: "PATCH_TASK_REFERENCE_IMAGE_NOT_READY" },
      },
    });
  });
});
