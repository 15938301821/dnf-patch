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
  authorizeJobSkillPreviewDownload,
  createPatchTask,
  downloadJobArtifact,
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

  it("forwards the artifact lifecycle signal to metadata requests", async () => {
    // 页面切换任务或卸载时必须能中止旧请求，迟到元数据不得覆盖当前弹窗。
    const controller = new AbortController();
    let observedSignal: unknown;
    const interceptorId = server.interceptors.request.use((config) => {
      if (config.url === "/jobs/job-demo-complete/artifacts") {
        observedSignal = config.signal;
      }
      return config;
    });
    try {
      await getJobArtifacts("job-demo-complete", controller.signal);
    } finally {
      server.interceptors.request.eject(interceptorId);
    }
    expect(observedSignal).toBe(controller.signal);
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

  it("forwards the artifact lifecycle signal to the byte download", async () => {
    // fetch 替身只观察取消所有权；授权仍经过 Axios Mock，不证明真实对象存储连接释放。
    const originalFetch = globalThis.fetch;
    const controller = new AbortController();
    let observedSignal: AbortSignal | null | undefined;
    globalThis.fetch = (_input, init) => {
      observedSignal = init?.signal;
      return Promise.resolve(
        new Response(new Blob(["M".repeat(384)]), { status: 200 }),
      );
    };
    try {
      await downloadJobArtifact(
        "job-demo-complete",
        "validation",
        controller.signal,
      );
    } finally {
      globalThis.fetch = originalFetch;
    }
    expect(observedSignal).toBe(controller.signal);
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
      expect(result.image.referenceTransferQuality).toMatchObject({
        referenceCoverage: 0.96,
        referenceSimilarity: 0.94,
        edgeEnergyRatio: 1.255,
      });
      expect(result.blob.type).toBe("image/png");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("rejects preview access for a skill without current passed evidence", async () => {
    await expect(
      authorizeJobSkillPreviewDownload(
        "job-demo-running",
        "skill-handling-sword",
        "reference-image",
      ),
    ).rejects.toMatchObject({
      response: {
        status: 404,
        data: { code: "PATCH_TASK_SKILL_PREVIEW_NOT_READY" },
      },
    });
  });
});
