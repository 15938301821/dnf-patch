/**
 * @fileoverview 验证资源导入 API 只报告后端边界并提交任务，而不在客户端执行导入。
 *
 * Axios Mock Adapter 替代真实 Server、数据库、游戏目录和 Worker，每例重置内存状态；测试不
 * 证明资源镜像可读、NPK/IMG 可解析、任务会执行或事实源已持久化。
 */
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  createResourceImportJob,
  getResourceImportOverview,
  server,
} from "../renderer/src/api/index.js";
import { configureMockApi } from "../renderer/src/mock/index.js";

beforeAll(() => {
  // 安装前端同契约替身，所有导入结果都只存在于当前 Node 进程内存。
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
