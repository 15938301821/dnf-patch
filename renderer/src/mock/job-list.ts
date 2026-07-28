/**
 * @fileoverview 登记制作任务列表轮询与软归档的同契约 Mock 路由；不创建任务、不返回详情，
 * 也不证明真实 Server、MySQL 事务、用户所有权、Worker 或证据保留可用。
 *
 * 流程位置：主 Mock Server 创建 Axios Mock Adapter 后调用本模块，并注入可重置的共享任务状态；
 * JobsPage 仍只通过正式 api/jobs 函数访问这些替身路由。
 * 输入输出：GET 返回未归档 PatchTask ViewModel，DELETE 对活动任务返回 409、对终态返回 204。
 * 副作用：仅推进演示任务的有界进度并记录内存归档 ID；原任务对象不删除，供详情与 Artifact Mock
 * 继续读取。安全边界：Mock API 是前端替身，不得据此宣称真实数据库锁或审计证据已经验证。
 */
import type MockAdapter from "axios-mock-adapter";
import type { ApiEnvelope, PatchTask } from "../server/contracts.js";

/** 主 Mock Server 拥有并在测试 reset 时整体替换的最小任务列表状态。 */
export interface MockTaskListState {
  jobs: PatchTask[];
  archivedJobIds: string[];
}

/**
 * 在共享 Axios Mock 上登记 `GET /jobs` 与 `DELETE /jobs/:id`。
 *
 * @param mock 主 Mock Server 创建的适配器，本模块不创建第二个客户端。
 * @param getState 每次请求读取当前共享状态，保证 `/__mock/reset` 替换对象后路由仍指向新状态。
 */
export function configureMockTaskListRoutes(
  mock: MockAdapter,
  getState: () => MockTaskListState,
): void {
  mock.onGet("/jobs").reply(() => {
    const state = getState();
    // 每次读取只推进一个有界演示百分比，让浏览器能观察轮询结果而不依赖请求计数。
    const runningJob = state.jobs.find(
      (job) => job.id === "job-demo-running" && job.status === "running",
    );
    if (runningJob) runningJob.progress = Math.min(95, runningJob.progress + 1);
    const visibleJobs = state.jobs.filter(
      (job) => !state.archivedJobIds.includes(job.id),
    );
    const response: ApiEnvelope<PatchTask[]> = { data: visibleJobs };
    return [200, response];
  });

  /** 活动任务失败关闭；终态只改变列表可见性，原任务继续作为详情与产物替身事实。 */
  mock.onDelete(/\/jobs\/[^/]+$/u).reply((config) => {
    const state = getState();
    const jobId = config.url?.split("/")[2];
    const job = state.jobs.find((candidate) => candidate.id === jobId);
    if (!job) {
      return [
        404,
        {
          code: "PATCH_TASK_NOT_FOUND",
          message: "制作任务不存在或当前用户无权操作。",
        },
      ];
    }
    if (job.status === "queued" || job.status === "running") {
      return [
        409,
        {
          code: "PATCH_TASK_ACTIVE",
          message: "制作任务仍在运行，完成后才能从列表移除。",
        },
      ];
    }
    if (!state.archivedJobIds.includes(job.id)) {
      state.archivedJobIds.push(job.id);
    }
    return [204];
  });
}
