/**
 * @fileoverview 验证 Axios 认证刷新判定不会刷新登录失败或无限重试原请求。
 *
 * 测试只调用纯判定函数，不安装 Axios 拦截器、不设置 Cookie，也不发真实认证请求；因此未证明
 * 并发刷新去重、HttpOnly Cookie、Token 签发或浏览器会话恢复的端到端行为。
 */
import { describe, expect, it } from "vitest";
import { shouldRefreshAccessToken } from "../renderer/src/server/server.js";

describe("API session refresh boundary", () => {
  it("does not turn an invalid login into a refresh request", () => {
    expect(shouldRefreshAccessToken(401, "/auth/login", undefined)).toBe(false);
  });

  it("allows startup session recovery through the refresh cookie", () => {
    expect(shouldRefreshAccessToken(401, "/auth/me", undefined)).toBe(true);
  });

  it("does not retry a request more than once", () => {
    expect(shouldRefreshAccessToken(401, "/jobs", true)).toBe(false);
    expect(shouldRefreshAccessToken(500, "/jobs", undefined)).toBe(false);
  });
});
