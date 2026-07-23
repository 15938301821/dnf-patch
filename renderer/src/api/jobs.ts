/**
 * @fileoverview 提供制作任务列表、创建与产物元数据查询的类型化 HTTP API。
 *
 * 任务页面和风格编辑页调用本模块，请求经受认证 Axios 客户端发送；创建请求只提交后端稳定
 * 职业/风格 ID，并携带幂等键防止重复调度。模块不执行本机工具、不下载产物字节，也不证明
 * Worker 或对象存储可用；服务端门禁和错误会原样拒绝给页面。
 */
import type {
  CreatePatchTaskInput,
  PatchTask,
  PatchTaskArtifact,
} from "../server/contracts.js";
import { requestData } from "../server/server.js";

/**
 * 通过 `GET /jobs` 读取当前用户可见的任务摘要。
 *
 * @returns 任务 ViewModel 列表，不包含执行命令、凭据或产物字节。
 */
export function getJobsList(): Promise<PatchTask[]> {
  return requestData<PatchTask[]>({ method: "GET", url: "/jobs" });
}

/**
 * 通过 `POST /jobs` 请求后端创建制作任务。
 *
 * @param input 已选职业与风格的后端稳定 ID；不允许携带 Prompt、模型密钥或工具路径。
 * @param idempotencyKey 单次用户意图的稳定键；省略时为本次调用生成随机键。
 * @returns 服务端接受后的任务摘要；客户端门禁通过不代表后端一定创建成功。
 */
export function createPatchTask(
  input: CreatePatchTaskInput,
  idempotencyKey = `patch.${crypto.randomUUID()}`,
): Promise<PatchTask> {
  return requestData<PatchTask>({
    method: "POST",
    url: "/jobs",
    data: input,
    headers: { "Idempotency-Key": idempotencyKey },
  });
}

/**
 * 通过 `GET /jobs/:jobId/artifact` 查询已验证产物的元数据引用。
 *
 * @param jobId 任务列表返回的稳定 ID。
 * @returns 名称、存储引用、媒体类型、大小与摘要；不返回或下载实际字节。
 */
export function getJobArtifactMetadata(
  jobId: string,
): Promise<PatchTaskArtifact> {
  return requestData<PatchTaskArtifact>({
    method: "GET",
    url: `/jobs/${jobId}/artifact`,
  });
}
