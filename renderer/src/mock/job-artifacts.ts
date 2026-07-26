/** @fileoverview 构造任务产物 Mock DTO；仅维护前端契约，不对应真实对象存储或生产字节。 */
import type MockAdapter from "axios-mock-adapter";
import type { PatchTask, PatchTaskArtifact } from "../server/contracts.js";

/**
 * 在共享 Axios Mock 上登记三项产物查询、固定角色下载授权和旧单项兼容读取。
 *
 * @param mock 已由主 Mock Server 创建并配置延迟的适配器。
 * @param getJobs 返回当前可变 Mock 状态中的任务列表，避免本模块复制或持有状态。
 */
export function configureMockTaskArtifactRoutes(
  mock: MockAdapter,
  getJobs: () => PatchTask[],
): void {
  mock.onGet(/\/jobs\/[^/]+\/artifacts$/u).reply((config) => {
    const jobId = config.url?.split("/")[2] ?? "";
    const job = getJobs().find((item) => item.id === jobId);
    return job ? [200, { data: mockTaskArtifacts(job) }] : [404, "Not found"];
  });

  mock
    .onPost(
      /\/jobs\/[^/]+\/artifacts\/(candidate|manifest|validation)\/download-authorization$/u,
    )
    .reply((config) => {
      const segments = config.url?.split("/") ?? [];
      const job = getJobs().find((item) => item.id === segments[2]);
      const artifact = job
        ? mockTaskArtifacts(job).find((item) => item.role === segments[4])
        : undefined;
      if (!artifact) return [404, "Not found"];
      return [
        200,
        {
          data: {
            ...artifact,
            downloadUrl: `data:${artifact.mediaType},${"M".repeat(artifact.byteLength)}`,
            expiresAtUtc: new Date(Date.now() + 300_000).toISOString(),
          },
        },
      ];
    });

  mock.onGet(/\/jobs\/[^/]+\/artifact$/u).reply((config) => {
    const jobId = config.url?.split("/")[2] ?? "";
    const job = getJobs().find((item) => item.id === jobId);
    return job
      ? [200, { data: mockTaskArtifacts(job)[0] }]
      : [404, "Not found"];
  });
}

/**
 * @param job 已由 Mock 任务列表解析的任务摘要。
 * @returns 与正式 API 同形的三个固定角色；ID 和 SHA 互异，但不对应真实对象字节。
 */
export function mockTaskArtifacts(job: PatchTask): PatchTaskArtifact[] {
  return [
    {
      artifactId: `${job.id}-candidate`,
      role: "candidate",
      artifactName: job.artifactName ?? "candidate.npk",
      mediaType: "application/octet-stream",
      byteLength: 512,
      sha256: "A".repeat(64),
    },
    {
      artifactId: `${job.id}-manifest`,
      role: "manifest",
      artifactName: "manifest.json",
      mediaType: "application/json",
      byteLength: 256,
      sha256: "B".repeat(64),
    },
    {
      artifactId: `${job.id}-validation`,
      role: "validation",
      artifactName: "validation.json",
      mediaType: "application/json",
      byteLength: 384,
      sha256: "C".repeat(64),
    },
  ];
}
