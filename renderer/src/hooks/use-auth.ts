/**
 * @fileoverview 连接认证 HTTP API 与内存认证 Store 的 React 生命周期 Hook。
 *
 * App 在启动时调用会话恢复 Hook，登录页和应用壳调用命令 Hook；输入来自登录表单或后端
 * 会话响应，输出写入仅含用户视图的 Zustand Store。副作用是认证请求和状态切换；Access
 * Token 由 API 模块内存保存，Refresh Token 由 HttpOnly Cookie 管理，二者都不得进入 Store。
 * 启动请求卸载后必须忽略结果；刷新失败会通过内存失效事件立即离开受保护路由，登出无论
 * 远端是否成功都作为本地成功完成，防止旧用户残留或未处理 Promise。
 */
import { useCallback, useEffect } from "react";
import {
  getCurrentUser,
  login as loginRequest,
  logout as logoutRequest,
  type LoginInput,
} from "../api/index.js";
import { subscribeToAccessTokenInvalidation } from "../server/token-store.js";
import { useAuthStore } from "../stores/auth-store.js";

/**
 * 在应用挂载时恢复当前会话，并在卸载后阻止过期请求覆盖认证状态。
 *
 * @returns 无命令返回；认证结果直接写入全局认证 Store。
 */
export function useAuthLifecycle(): void {
  useEffect(() => {
    let active = true;
    const unsubscribe = connectAuthStoreToTokenInvalidation();
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
      // 第三步：卸载同时撤销请求写入资格和失效订阅，不操作由 HTTP 层拥有的刷新请求。
      active = false;
      unsubscribe();
    };
  }, []);
}

/**
 * 把HTTP层的Token失效事件连接到纯认证Store。
 *
 * @returns 取消订阅函数；调用方卸载时必须执行，避免旧应用生命周期继续切换状态。
 */
export function connectAuthStoreToTokenInvalidation(): () => void {
  return subscribeToAccessTokenInvalidation(() => {
    useAuthStore.getState().setAnonymous();
  });
}

/**
 * 尝试结束远端会话，并始终完成本地匿名转换。
 *
 * @returns 本地清理完成后正常结算；远端会话已过期或网络失败不会阻止用户退出。
 */
export async function logoutCurrentSession(): Promise<void> {
  try {
    await logoutRequest();
  } catch {
    // 远端会话可能已经失效；API 层已清 Token，本地退出仍必须完成。
  }
  useAuthStore.getState().setAnonymous();
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
  const logout = useCallback(logoutCurrentSession, []);

  return { login, logout };
}
