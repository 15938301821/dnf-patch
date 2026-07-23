/**
 * @fileoverview 验证认证 Store 的状态转换与跨会话用户清理风险。
 *
 * 测试直接调用 Zustand 内存 Store 并在每例前重置，保护匿名化后不残留旧用户；未挂载 React、
 * 未发认证请求，也不证明真实 Cookie、Token 刷新或浏览器生命周期集成。
 */
import { beforeEach, describe, expect, it } from "vitest";
import { useAuthStore } from "../renderer/src/stores/auth-store.js";

beforeEach(() => {
  // 用同步内存重置替代应用启动流程，保证用例之间没有用户状态污染。
  useAuthStore.setState({ status: "booting", user: undefined });
});

describe("authentication store", () => {
  it("starts without an authenticated user", () => {
    expect(useAuthStore.getState()).toMatchObject({
      status: "booting",
      user: undefined,
    });
  });

  it("stores only the authenticated user view", () => {
    useAuthStore.getState().setAuthenticated({
      id: "user-test",
      username: "tester",
      displayName: "测试用户",
    });

    expect(useAuthStore.getState()).toMatchObject({
      status: "authenticated",
      user: {
        id: "user-test",
        username: "tester",
        displayName: "测试用户",
      },
    });
  });

  it("clears user data when the session becomes anonymous", () => {
    const store = useAuthStore.getState();
    store.setAuthenticated({
      id: "user-test",
      username: "tester",
      displayName: "测试用户",
    });
    useAuthStore.getState().setAnonymous();

    expect(useAuthStore.getState()).toMatchObject({
      status: "anonymous",
      user: undefined,
    });
  });
});
