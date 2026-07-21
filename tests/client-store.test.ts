import { beforeEach, describe, expect, it } from "vitest";
import { useAuthStore } from "../renderer/src/stores/auth-store.js";

beforeEach(() => {
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
