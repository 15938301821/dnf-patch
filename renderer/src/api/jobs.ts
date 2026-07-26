/**
 * @fileoverview 提供制作任务列表、创建、三项产物元数据与短期下载授权的类型化 HTTP API。
 *
 * 任务页面和风格编辑页调用本模块，请求经受认证 Axios 客户端发送；创建请求只提交后端稳定
 * 职业/风格 ID，并携带幂等键防止重复调度。下载授权只提交任务 ID 和固定角色，不接收对象 key
 * 或任意 Artifact ID；模块不执行本机工具，也不证明 Worker、对象存储或客户端兼容性。
 */
import type {
  CreatePatchTaskInput,
  PatchTask,
  PatchTaskArtifact,
  PatchTaskArtifactDownload,
  PatchTaskArtifactRole,
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
 * 通过 `GET /jobs/:jobId/artifacts` 查询 Package V3 三项已验证产物元数据。
 *
 * @param jobId 任务列表返回的稳定 ID。
 * @returns candidate、manifest、validation 固定角色的名称、类型、大小与摘要；不返回实际字节。
 */
export function getJobArtifacts(jobId: string): Promise<PatchTaskArtifact[]> {
  return requestData<PatchTaskArtifact[]>({
    method: "GET",
    url: `/jobs/${jobId}/artifacts`,
  });
}

/**
 * 通过 `POST /jobs/:jobId/artifacts/:role/download-authorization` 取得短期 GET URL。
 *
 * @param jobId 任务列表返回并由服务端执行所有权检查的稳定 ID。
 * @param role 从三项元数据选择的固定角色；客户端不提交 Artifact ID 或对象存储定位信息。
 * @returns 选中角色的脱敏元数据与短期 URL；URL 到期失效且不表示下载、兼容或部署已完成。
 */
export function authorizeJobArtifactDownload(
  jobId: string,
  role: PatchTaskArtifactRole,
): Promise<PatchTaskArtifactDownload> {
  return requestData<PatchTaskArtifactDownload>({
    method: "POST",
    url: `/jobs/${jobId}/artifacts/${role}/download-authorization`,
  });
}

/**
 * 为固定角色申请短期授权并读取实际 Artifact 字节。
 *
 * @param jobId 当前用户任务的稳定 ID，由服务端执行所有权检查。
 * @param role 三项元数据中的固定角色，不接收对象 key 或任意 Artifact ID。
 * @returns 服务端元数据和经长度复核的 Blob；短期 URL 只存在于当前调用栈且不会向页面返回。
 */
export async function downloadJobArtifact(
  jobId: string,
  role: PatchTaskArtifactRole,
): Promise<{ artifact: PatchTaskArtifact; blob: Blob }> {
  const authorization = await authorizeJobArtifactDownload(jobId, role);
  const response = await fetch(authorization.downloadUrl, {
    cache: "no-store",
    credentials: "omit",
    referrerPolicy: "no-referrer",
  });
  if (!response.ok) throw new Error("ARTIFACT_DOWNLOAD_FAILED");
  const blob = await response.blob();
  if (blob.size !== authorization.byteLength) {
    throw new Error("ARTIFACT_DOWNLOAD_LENGTH_MISMATCH");
  }
  return { artifact: authorization, blob };
}
