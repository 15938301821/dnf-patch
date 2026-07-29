/**
 * @fileoverview 提供制作任务列表、详情、创建、参考图与三项产物下载的类型化 HTTP API。
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
  PatchTaskDetail,
  PatchTaskSkillPreview,
  PatchTaskSkillPreviewDownload,
  PatchTaskSkillPreviewRole,
} from "../server/contracts.js";
import { requestData, server } from "../server/server.js";

/**
 * 通过 `GET /jobs` 读取当前用户可见的任务摘要。
 *
 * @param signal 列表 Hook 当前轮次的取消信号；刷新或卸载时中止旧请求，过期结果不得覆盖新列表。
 * @returns 任务 ViewModel 列表，不包含执行命令、凭据或产物字节。
 */
export function getJobsList(signal?: AbortSignal): Promise<PatchTask[]> {
  return requestData<PatchTask[]>({
    method: "GET",
    url: "/jobs",
    ...(signal ? { signal } : {}),
  });
}

/**
 * 通过 `DELETE /jobs/:jobId` 把当前用户拥有的终态任务从默认列表软归档。
 *
 * @param jobId 任务列表返回并由服务端继续执行所有权检查的稳定 Run ID。
 * @returns 收到 204 后结算且无业务正文；成功不表示取消执行，也不表示 Run、Job、Attempt 或 Artifact 被删除。
 * @throws 服务端对活动任务返回稳定 409，对不存在或跨用户任务返回稳定 404。
 */
export async function archiveJob(jobId: string): Promise<void> {
  // 归档成功是无响应正文的 204，不能使用要求 `{ data }` 包络的 requestData。
  await server.delete(`/jobs/${jobId}`);
}

/**
 * 通过 `GET /jobs/:jobId` 读取当前用户拥有的任务详情。
 *
 * @param jobId 任务列表或当前路由提供的稳定 ID，服务端继续执行用户所有权检查。
 * @param signal 页面本轮读取的取消信号；离开路由或启动下一轮轮询时中止旧请求，防止过期结果覆盖。
 * @returns 工作流、逐技能状态和真实 Provider 计量 ViewModel；nullable usage 不会在客户端补零。
 */
export function getJobDetail(
  jobId: string,
  signal?: AbortSignal,
): Promise<PatchTaskDetail> {
  return requestData<PatchTaskDetail>({
    method: "GET",
    url: `/jobs/${jobId}`,
    ...(signal ? { signal } : {}),
  });
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
export function getJobArtifacts(
  jobId: string,
  signal?: AbortSignal,
): Promise<PatchTaskArtifact[]> {
  return requestData<PatchTaskArtifact[]>({
    method: "GET",
    url: `/jobs/${jobId}/artifacts`,
    ...(signal ? { signal } : {}),
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
  signal?: AbortSignal,
): Promise<PatchTaskArtifactDownload> {
  return requestData<PatchTaskArtifactDownload>({
    method: "POST",
    url: `/jobs/${jobId}/artifacts/${role}/download-authorization`,
    ...(signal ? { signal } : {}),
  });
}

/**
 * 通过任务、技能和固定角色申请一张对比图的短期授权。
 *
 * @param jobId 当前用户任务的稳定 ID，由服务端继续复核所有权。
 * @param skillId 详情 DTO 返回的技能 ID，不是 Artifact ID。
 * @param role 仅允许源帧、模型参考图或 Aseprite 结果三种固定语义。
 * @param signal 对比弹窗生命周期的取消信号；关闭后未完成请求不得写入页面状态。
 * @returns 当前 attempt 的脱敏 PNG 元数据与只供立即下载使用的短期 URL。
 */
export function authorizeJobSkillPreviewDownload(
  jobId: string,
  skillId: string,
  role: PatchTaskSkillPreviewRole,
  signal?: AbortSignal,
): Promise<PatchTaskSkillPreviewDownload> {
  return requestData<PatchTaskSkillPreviewDownload>({
    method: "POST",
    url: `/jobs/${jobId}/skills/${skillId}/previews/${role}/download-authorization`,
    ...(signal ? { signal } : {}),
  });
}

/**
 * 申请一个固定角色并返回经媒体类型、长度与 PNG 签名复核的 Blob。
 *
 * @param jobId 当前详情任务 ID。
 * @param skillId 用户选择的详情技能 ID。
 * @param role 三种固定预览角色之一；不会转发 Artifact ID 或对象定位信息。
 * @param signal 对比组件本轮加载的取消信号。
 * @returns 可展示的脱敏元数据与 Blob；短期 URL 和响应对象不会进入 React 状态。
 */
export async function downloadJobSkillPreview(
  jobId: string,
  skillId: string,
  role: PatchTaskSkillPreviewRole,
  signal?: AbortSignal,
): Promise<{ image: PatchTaskSkillPreview; blob: Blob }> {
  const authorization = await authorizeJobSkillPreviewDownload(
    jobId,
    skillId,
    role,
    signal,
  );
  if (authorization.role !== role || authorization.skillId !== skillId) {
    throw new Error("SKILL_PREVIEW_ROLE_MISMATCH");
  }
  const blob = await downloadVerifiedPng(authorization, signal);
  const image: PatchTaskSkillPreview = {
    artifactId: authorization.artifactId,
    skillId: authorization.skillId,
    role: authorization.role,
    artifactName: authorization.artifactName,
    mediaType: authorization.mediaType,
    byteLength: authorization.byteLength,
    sha256: authorization.sha256,
    ...(authorization.frame ? { frame: authorization.frame } : {}),
    ...(authorization.referenceTransferQuality
      ? {
          referenceTransferQuality: authorization.referenceTransferQuality,
        }
      : {}),
  };
  return { image, blob };
}

/** 在编译期 DTO 之外复核实际网络响应，避免信任被代理或 Mock 篡改的媒体类型字符串。 */
function isPngMediaType(mediaType: string): boolean {
  return mediaType.toLowerCase() === "image/png";
}

/**
 * 读取并复核一个短期 PNG 授权；失败后禁止调用方创建 Object URL。
 * @param authorization 服务端固定角色授权，包含预期媒体类型、长度与临时 URL。
 * @param signal 所属预览生命周期的取消信号。
 */
async function downloadVerifiedPng(
  authorization: {
    mediaType: string;
    byteLength: number;
    downloadUrl: string;
  },
  signal: AbortSignal | undefined,
): Promise<Blob> {
  if (!isPngMediaType(authorization.mediaType)) {
    throw new Error("SKILL_PREVIEW_MEDIA_TYPE_MISMATCH");
  }
  const response = await fetch(authorization.downloadUrl, {
    cache: "no-store",
    credentials: "omit",
    referrerPolicy: "no-referrer",
    ...(signal ? { signal } : {}),
  });
  if (!response.ok) throw new Error("SKILL_PREVIEW_DOWNLOAD_FAILED");
  const blob = await response.blob();
  if (
    (blob.type && blob.type !== "image/png") ||
    blob.size !== authorization.byteLength
  ) {
    throw new Error("SKILL_PREVIEW_RESPONSE_MISMATCH");
  }
  // PNG 固定八字节签名是展示前最后一道本地门禁，不能只信任响应 Content-Type。
  const signature = new Uint8Array(await blob.slice(0, 8).arrayBuffer());
  const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (
    signature.length !== pngSignature.length ||
    signature.some((value, index) => value !== pngSignature[index])
  ) {
    throw new Error("SKILL_PREVIEW_SIGNATURE_INVALID");
  }
  return blob;
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
  signal?: AbortSignal,
): Promise<{ artifact: PatchTaskArtifact; blob: Blob }> {
  const authorization = await authorizeJobArtifactDownload(jobId, role, signal);
  const response = await fetch(authorization.downloadUrl, {
    cache: "no-store",
    credentials: "omit",
    referrerPolicy: "no-referrer",
    ...(signal ? { signal } : {}),
  });
  if (!response.ok) throw new Error("ARTIFACT_DOWNLOAD_FAILED");
  const blob = await response.blob();
  if (blob.size !== authorization.byteLength) {
    throw new Error("ARTIFACT_DOWNLOAD_LENGTH_MISMATCH");
  }
  return { artifact: authorization, blob };
}
