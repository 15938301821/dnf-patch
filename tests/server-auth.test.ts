/**
 * @fileoverview 验证 Axios 认证刷新判定与登出失败后的内存 Token 清理。
 *
 * 测试用 Axios Mock Adapter 代替真实网络，不设置 Cookie，也不发真实认证请求；因此未证明
 * 并发刷新去重、HttpOnly Cookie、Token 签发或浏览器会话恢复的端到端行为。
 */
import MockAdapter from "axios-mock-adapter";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { logout } from "../renderer/src/api/auth.js";
import {
  server,
  shouldRefreshAccessToken,
} from "../renderer/src/server/server.js";
import {
  getAccessToken,
  setAccessToken,
} from "../renderer/src/server/token-store.js";

let mock: MockAdapter;

beforeAll(() => {
  mock = new MockAdapter(server);
});

afterEach(() => {
  mock.reset();
  setAccessToken(undefined);
});

afterAll(() => {
  mock.restore();
});

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

  it("clears the in-memory access token when logout loses the network", async () => {
    setAccessToken("short-lived-test-token");
    mock.onPost("/auth/logout").networkError();

    await expect(logout()).rejects.toThrow();
    expect(getAccessToken()).toBeUndefined();
  });
});
