/**
 * @fileoverview 验证 Axios 认证刷新判定、Token失效状态传播与登出失败后的本地清理。
 *
 * 测试用 Axios Mock Adapter 代替真实网络，不设置 Cookie，也不发真实认证请求；因此未证明
 * 并发刷新去重、HttpOnly Cookie、Token 签发或浏览器会话恢复的端到端行为。
 */
import MockAdapter from "axios-mock-adapter";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { logout } from "../renderer/src/api/auth.js";
import {
  connectAuthStoreToTokenInvalidation,
  logoutCurrentSession,
} from "../renderer/src/hooks/use-auth.js";
import {
  server,
  shouldRefreshAccessToken,
} from "../renderer/src/server/server.js";
import {
  getAccessToken,
  setAccessToken,
} from "../renderer/src/server/token-store.js";
import { useAuthStore } from "../renderer/src/stores/auth-store.js";

let mock: MockAdapter;

beforeAll(() => {
  mock = new MockAdapter(server);
});

afterEach(() => {
  mock.reset();
  setAccessToken(undefined);
  useAuthStore.setState({ status: "booting", user: undefined });
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

  it("leaves protected client state when the access token is invalidated", () => {
    useAuthStore.getState().setAuthenticated({
      id: "11111111-1111-4111-8111-111111111111",
      username: "admin",
      displayName: "Admin",
    });
    setAccessToken("expired-test-token");
    const unsubscribe = connectAuthStoreToTokenInvalidation();

    setAccessToken(undefined);

    expect(useAuthStore.getState()).toMatchObject({
      status: "anonymous",
      user: undefined,
    });
    unsubscribe();
  });

  it("completes local logout when the remote session is unavailable", async () => {
    useAuthStore.getState().setAuthenticated({
      id: "11111111-1111-4111-8111-111111111111",
      username: "admin",
      displayName: "Admin",
    });
    setAccessToken("expired-test-token");
    mock.onPost("/auth/logout").networkError();

    await expect(logoutCurrentSession()).resolves.toBeUndefined();
    expect(getAccessToken()).toBeUndefined();
    expect(useAuthStore.getState()).toMatchObject({
      status: "anonymous",
      user: undefined,
    });
  });
});
