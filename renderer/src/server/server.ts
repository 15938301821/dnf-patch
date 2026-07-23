/**
 * @fileoverview 配置受认证 Axios 客户端、响应解包及一次性会话刷新策略。
 *
 * 各领域 API 提供请求配置，本模块附加内存 Access Token 并返回包络内数据；外部副作用是
 * HTTPS/同源请求、Cookie 随请求发送及 Token 内存更新。Refresh Token 仅由后端 HttpOnly
 * Cookie 管理。并发 401 共用一个刷新 Promise，每个原请求最多重放一次；刷新失败必须清除
 * Access Token，禁止无限重试或把登录失败转换为刷新请求。
 */
import axios, {
  type AxiosError,
  type AxiosRequestConfig,
  type InternalAxiosRequestConfig,
} from "axios";
import type { ApiEnvelope, AuthSession } from "./contracts.js";
import { getAccessToken, setAccessToken } from "./token-store.js";

/** 远程 API 基址只来自 Vite 环境，缺失时使用同源 `/v1`。 */
const apiBaseUrl = import.meta.env.VITE_API_BASE_URL?.trim() || "/v1";

/** 领域 API 共用的 Axios 实例，会附加 Access Token 并处理一次 401 重试。 */
export const server = axios.create({
  baseURL: apiBaseUrl,
  timeout: 15_000,
  withCredentials: true,
  headers: { Accept: "application/json" },
});

/** 专用于刷新会话的无响应重试客户端，避免刷新请求递归触发自身拦截器。 */
export const refreshClient = axios.create({
  baseURL: apiBaseUrl,
  timeout: 15_000,
  withCredentials: true,
  headers: { Accept: "application/json" },
});

/** 当前进行中的刷新请求；存在时所有并发 401 必须复用。 */
let refreshRequest: Promise<string> | undefined;

/** 把已签发 Token 转为标准 Bearer 请求头值。 */
function authorizationHeader(token: string): string {
  return `Bearer ${token}`;
}

/**
 * 判断一次失败是否允许通过 Cookie 刷新后重放原请求。
 *
 * @param status Axios 响应状态；网络错误没有状态且不能触发刷新。
 * @param url 原请求相对地址；登录端点的 401 表示凭据无效，不可刷新。
 * @param retriedAfterRefresh 原请求是否已经重放过，用于阻止循环。
 * @returns 仅首次、非登录的 401 返回 `true`。
 */
export function shouldRefreshAccessToken(
  status: number | undefined,
  url: string | undefined,
  retriedAfterRefresh: boolean | undefined,
): boolean {
  return (
    status === 401 && url !== "/auth/login" && retriedAfterRefresh !== true
  );
}

/**
 * 创建或复用一次会话刷新，并更新内存 Access Token。
 *
 * @returns 新的短期 Token；请求失败时拒绝，完成后始终释放去重槽位。
 */
async function refreshAccessToken(): Promise<string> {
  refreshRequest ??= refreshClient
    .post<ApiEnvelope<AuthSession>>("/auth/refresh")
    .then((response) => {
      setAccessToken(response.data.data.accessToken);
      return response.data.data.accessToken;
    })
    .finally(() => {
      refreshRequest = undefined;
    });
  return refreshRequest;
}

/** 为受认证请求附加当前内存 Token；无 Token 时保持请求原样。 */
server.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  const token = getAccessToken();
  if (token) {
    config.headers.Authorization = authorizationHeader(token);
  }
  return config;
});

/**
 * 对符合条件的 401 执行“标记原请求 -> 共用刷新 -> 更新认证头 -> 重放”流程。
 * 任一步失败都会清除内存 Token 并把刷新错误交给页面，禁止继续重放写请求。
 */
server.interceptors.response.use(undefined, async (error: AxiosError) => {
  const request = error.config as
    | (InternalAxiosRequestConfig & { retriedAfterRefresh?: boolean })
    | undefined;
  if (
    !request ||
    !shouldRefreshAccessToken(
      error.response?.status,
      request.url,
      request.retriedAfterRefresh,
    )
  ) {
    throw error;
  }
  // 第一步：在等待刷新前标记原请求，确保后续 401 不会再次进入重试。
  request.retriedAfterRefresh = true;
  try {
    // 第二步：并发请求共用一次刷新，再用新 Token 重放各自原请求。
    request.headers.Authorization = authorizationHeader(
      await refreshAccessToken(),
    );
    return await server.request(request);
  } catch (refreshError) {
    // 第三步：刷新或重放失败后清除旧凭据，让上层回到匿名/错误处理路径。
    setAccessToken(undefined);
    throw refreshError;
  }
});

/**
 * 执行类型化请求并只返回成功包络中的业务数据。
 *
 * @param config 领域 API 生成的 Axios 方法、相对路径、DTO 与可选请求头。
 * @returns 服务端 `ApiEnvelope` 内的类型化数据；HTTP 或解析错误原样拒绝。
 */
export async function requestData<T>(config: AxiosRequestConfig): Promise<T> {
  const response = await server.request<ApiEnvelope<T>>(config);
  return response.data.data;
}
