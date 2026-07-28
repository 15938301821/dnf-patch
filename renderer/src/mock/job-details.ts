/**
 * @fileoverview 登记任务详情页与固定技能参考图授权的同契约 Mock 路由。
 *
 * 主 Mock Server 传入共享 Axios 适配器和当前任务列表，本模块调用 job-detail-fixtures 取得静态
 * ViewModel，并返回详情或短期参考图授权。副作用仅限 Mock 响应和运行中读取次数计数，不执行
 * 模型、Worker 或对象存储操作。安全边界：预览只接受任务与技能 ID，技能必须由详情标记可用；
 * 静态 PNG 仅供前端测试，不证明真实 Artifact 证据、图片生成或最终补丁兼容性。
 */
import type MockAdapter from "axios-mock-adapter";
import referenceImageUrl from "../assets/style-preview.png";
import type { PatchTask } from "../server/contracts.js";
import { mockTaskDetail } from "./job-detail-fixtures.js";

/** 与静态 PNG 资源一致的脱敏元数据；URL 在每次授权响应中临时附加。 */
const referenceImage = {
  artifactId: "mock-reference-image",
  artifactName: "mock-reference.png",
  mediaType: "image/png" as const,
  byteLength: 4_841_702,
  sha256: "E464E9C65008116BA8BE63D78AA67B6673600AD2E838ABBC13B30E046D8A459F",
};

/**
 * 在共享 Axios Mock 上登记 owner-scoped 详情和固定技能参考图授权端点。
 *
 * @param mock 主 Mock Server 创建的适配器；本模块不创建第二个 Axios 实例。
 * @param getJobs 返回当前可变任务状态，用于保持列表重置后的 404 语义一致。
 */
export function configureMockTaskDetailRoutes(
  mock: MockAdapter,
  getJobs: () => PatchTask[],
): void {
  const runningDetailReadCounts = new Map<string, number>();
  mock.onGet(/\/jobs\/[^/]+$/u).reply((config) => {
    const jobId = config.url?.split("/")[2] ?? "";
    const job = getJobs().find((item) => item.id === jobId);
    const detail = job ? mockTaskDetail(job) : undefined;
    if (detail?.status === "running") {
      // 每次轮询推进 Mock 审计时间，给浏览器流程稳定的下一轮响应观察点。
      const count = (runningDetailReadCounts.get(detail.id) ?? 0) + 1;
      runningDetailReadCounts.set(detail.id, count);
      detail.updatedAt = new Date(
        Date.parse(detail.updatedAt) + count * 3_000,
      ).toISOString();
    }
    return detail
      ? [200, { data: detail }]
      : [404, { code: "PATCH_TASK_NOT_FOUND", message: "制作任务不存在。" }];
  });

  mock
    .onPost(
      /\/jobs\/[^/]+\/skills\/[^/]+\/reference-image\/download-authorization$/u,
    )
    .reply((config) => {
      const segments = config.url?.split("/") ?? [];
      const job = getJobs().find((item) => item.id === segments[2]);
      const skill = job
        ? mockTaskDetail(job).skills.find(
            (item) =>
              item.skillId === segments[4] && item.referenceImageAvailable,
          )
        : undefined;
      if (!skill) {
        return [
          404,
          {
            code: "PATCH_TASK_REFERENCE_IMAGE_NOT_READY",
            message: "该技能的模型参考图尚未生成或当前用户无权查看。",
          },
        ];
      }
      return [
        200,
        {
          data: {
            ...referenceImage,
            skillId: skill.skillId,
            downloadUrl: referenceImageUrl,
            expiresAtUtc: new Date(Date.now() + 300_000).toISOString(),
          },
        },
      ];
    });
}
