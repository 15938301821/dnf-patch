/**
 * @fileoverview 连接认证 HTTP API 与内存认证 Store 的 React 生命周期 Hook。
 *
 * App 在启动时调用会话恢复 Hook，登录页和应用壳调用命令 Hook；输入来自登录表单或后端
 * 会话响应，输出写入仅含用户视图的 Zustand Store。副作用是认证请求和状态切换；Access
 * Token 由 API 模块内存保存，Refresh Token 由 HttpOnly Cookie 管理，二者都不得进入 Store。
 * 启动请求卸载后必须忽略结果，登出无论远端是否成功都必须清除当前用户，防止跨会话残留。
 */
import { useCallback, useEffect } from "react";
import {
  getCurrentUser,
  login as loginRequest,
  logout as logoutRequest,
  type LoginInput,
} from "../api/index.js";
import { useAuthStore } from "../stores/auth-store.js";

/**
 * 在应用挂载时恢复当前会话，并在卸载后阻止过期请求覆盖认证状态。
 *
 * @returns 无命令返回；认证结果直接写入全局认证 Store。
 */
export function useAuthLifecycle(): void {
  useEffect(() => {
    let active = true;
    // 第一步：请求当前用户；底层 401 拦截器可凭 HttpOnly Cookie 尝试一次会话刷新。
    void getCurrentUser()
      .then((user) => {
        // 第二步：仅仍挂载的应用可提交结果，避免 stale result（较早请求的过期结果）回写。
        if (active) {
          useAuthStore.getState().setAuthenticated(user);
        }
      })
      .catch(() => {
        if (active) {
          useAuthStore.getState().setAnonymous();
        }
      });
    return () => {
      // 第三步：卸载只撤销本 Hook 的写入资格，不操作由 HTTP 层拥有的刷新请求。
      active = false;
    };
  }, []);
}

/** 登录页与应用壳可调用的认证命令集合。 */
export interface AuthCommands {
  /** 校验并提交表单凭据，成功后把脱敏用户视图写入 Store。 */
  login: (input: LoginInput) => Promise<void>;
  /** 请求结束会话，并在成功或失败后都清空客户端用户状态。 */
  logout: () => Promise<void>;
}

/**
 * 提供登录和登出命令，并保持网络副作用位于 Store 之外。
 *
 * @returns 引用稳定的异步命令；请求失败原样拒绝，由调用页面映射为可见错误。
 */
export function useAuthCommands(): AuthCommands {
  /**
   * 提交登录表单并接受服务端签发的会话用户。
   *
   * @param input Ant Design 登录表单校验后的账号与密码，只用于本次认证请求。
   * @returns Store 更新完成后结算；认证失败时拒绝且不伪造已登录状态。
   */
  const login = useCallback(async (input: LoginInput): Promise<void> => {
    const session = await loginRequest(input);
    useAuthStore.getState().setAuthenticated(session.user);
  }, []);

  /**
   * 结束远端会话并无条件清理本地用户视图。
   *
   * @returns 清理完成后结算；即使远端请求失败，本地也不会保留旧用户。
   */
  const logout = useCallback(async (): Promise<void> => {
    try {
      await logoutRequest();
    } finally {
      useAuthStore.getState().setAnonymous();
    }
  }, []);

  return { login, logout };
}
