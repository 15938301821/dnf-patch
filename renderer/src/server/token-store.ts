/**
 * @fileoverview 在当前 JavaScript 进程内保存短期 Access Token。
 *
 * 认证 API 与 Axios 拦截器读写该值，页面和 Store 不直接消费；模块不使用 Local Storage、
 * Session Storage 或日志，因此刷新页面即丢失。Refresh Token 由服务端 HttpOnly Cookie
 * 管理，前端 JavaScript 不读取其明文；登出或刷新失败必须把本值清空。
 */

let accessToken: string | undefined;

/** @returns 当前内存中的短期 Access Token；匿名或已清理时为 `undefined`。 */
export function getAccessToken(): string | undefined {
  return accessToken;
}

/**
 * 替换或清除内存 Access Token。
 *
 * @param value 登录/刷新响应中的短期凭据，或登出与刷新失败时传入的 `undefined`。
 */
export function setAccessToken(value: string | undefined): void {
  accessToken = value;
}
