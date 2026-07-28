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
  PatchTaskReferenceImage,
  PatchTaskReferenceImageDownload,
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
 * 通过任务和技能固定语义申请 reference-image-v1 PNG 的短期授权。
 *
 * @param jobId 当前用户任务的稳定 ID，由服务端复核所有权。
 * @param skillId 详情 DTO 返回的技能稳定 ID；客户端不能提交 Artifact ID 或对象 key。
 * @param signal 预览流程拥有的取消信号，关闭预览或离开详情页时中止未完成请求。
 * @returns 当前 attempt 参考图元数据与短期 URL；URL 仅供同一调用栈立即读取。
 */
export function authorizeJobReferenceImageDownload(
  jobId: string,
  skillId: string,
  signal?: AbortSignal,
): Promise<PatchTaskReferenceImageDownload> {
  return requestData<PatchTaskReferenceImageDownload>({
    method: "POST",
    url: `/jobs/${jobId}/skills/${skillId}/reference-image/download-authorization`,
    ...(signal ? { signal } : {}),
  });
}

/**
 * 申请短期授权并把当前技能模型参考图读取为经过类型、长度和 PNG 签名复核的 Blob。
 *
 * @param jobId 当前详情路由的任务 ID。
 * @param skillId 用户从该详情 DTO 选择的技能 ID，不是 Artifact ID。
 * @param signal 由页面预览生命周期创建的取消信号；中止后不会返回可展示 Blob。
 * @returns 脱敏图片元数据与 Blob；短期 URL、到期时间和响应对象不会返回页面或进入持久状态。
 * @throws 远端失败、媒体类型不符、长度不符或 PNG 八字节签名无效时拒绝，页面不得展示该对象。
 */
export async function downloadJobReferenceImage(
  jobId: string,
  skillId: string,
  signal?: AbortSignal,
): Promise<{ image: PatchTaskReferenceImage; blob: Blob }> {
  // 第一步：只按任务和技能申请授权，浏览器从不选择对象存储中的任意 Artifact。
  const authorization = await authorizeJobReferenceImageDownload(
    jobId,
    skillId,
    signal,
  );
  if (!isPngMediaType(authorization.mediaType)) {
    throw new Error("REFERENCE_IMAGE_MEDIA_TYPE_MISMATCH");
  }
  // 第二步：短期 URL 只在当前调用栈使用；对象读取失败后禁止构造预览 URL。
  const response = await fetch(authorization.downloadUrl, {
    cache: "no-store",
    credentials: "omit",
    referrerPolicy: "no-referrer",
    ...(signal ? { signal } : {}),
  });
  if (!response.ok) throw new Error("REFERENCE_IMAGE_DOWNLOAD_FAILED");
  const blob = await response.blob();
  if (
    (blob.type && blob.type !== "image/png") ||
    blob.size !== authorization.byteLength
  ) {
    throw new Error("REFERENCE_IMAGE_RESPONSE_MISMATCH");
  }
  // 第三步：复核 PNG 固定文件签名，避免仅凭 HTTP Content-Type 展示非图片字节。
  const signature = new Uint8Array(await blob.slice(0, 8).arrayBuffer());
  const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (
    signature.length !== pngSignature.length ||
    signature.some((value, index) => value !== pngSignature[index])
  ) {
    throw new Error("REFERENCE_IMAGE_SIGNATURE_INVALID");
  }
  return {
    image: {
      artifactId: authorization.artifactId,
      skillId: authorization.skillId,
      artifactName: authorization.artifactName,
      mediaType: authorization.mediaType,
      byteLength: authorization.byteLength,
      sha256: authorization.sha256,
    },
    blob,
  };
}

/** 在编译期 DTO 之外复核实际网络响应，避免信任被代理或 Mock 篡改的媒体类型字符串。 */
function isPngMediaType(mediaType: string): boolean {
  return mediaType.toLowerCase() === "image/png";
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
