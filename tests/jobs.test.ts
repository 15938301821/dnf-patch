/**
 * @fileoverview 验证任务 API 的幂等请求头、Mock 门禁与产物元数据边界。
 *
 * Axios Mock Adapter 替代真实 Server、Worker 和对象存储，并在每例前重置内存状态；测试可证明
 * 客户端请求形状与替身语义，不证明真实任务调度、制作、上传、下载或产物校验。
 */
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  authorizeJobArtifactDownload,
  createPatchTask,
  downloadJobArtifact,
  getJobArtifacts,
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
});
