/**
 * @fileoverview 提供登录、当前用户恢复与登出的类型化认证 HTTP API。
 *
 * 登录页和认证 Hook 调用这些函数，所有请求经共享 Axios 客户端发送 Cookie；登录响应中的
 * Access Token 只写入内存 Token Store，Refresh Token 由 HttpOnly Cookie 管理。模块不写
 * 浏览器存储、不记录凭据；登出请求成功后才清除 Token，远端失败时由 Hook 的 finally 清理
 * 用户 Store，Axios 刷新失败也会清除 Token。
 */
import type {
  AuthSession,
  LoginInput,
  SessionUser,
} from "../server/contracts.js";
import { requestData } from "../server/server.js";
import { setAccessToken } from "../server/token-store.js";

/**
 * 通过 `POST /auth/login` 建立会话并保存短期 Access Token。
 *
 * @param input 登录表单校验后的账号与密码，只随本次受保护请求发送。
 * @returns 服务端会话 DTO；调用方只应把其中的脱敏用户写入 Store。
 */
export async function login(input: LoginInput): Promise<AuthSession> {
  const session = await requestData<AuthSession>({
    method: "POST",
    url: "/auth/login",
    data: input,
  });
  setAccessToken(session.accessToken);
  return session;
}

/**
 * 通过 `GET /auth/me` 读取当前会话的脱敏用户。
 *
 * @returns 当前用户 ViewModel；401 可由共享拦截器尝试一次 Cookie 刷新，失败则拒绝。
 */
export async function getCurrentUser(): Promise<SessionUser> {
  return requestData<SessionUser>({ method: "GET", url: "/auth/me" });
}

/**
 * 通过 `POST /auth/logout` 结束服务端会话并清除内存 Access Token。
 *
 * @returns 服务端确认后结算；请求失败时拒绝，由认证 Hook 负责无条件清理界面状态。
 */
export async function logout(): Promise<void> {
  await requestData<null>({ method: "POST", url: "/auth/logout" });
  setAccessToken(undefined);
}
