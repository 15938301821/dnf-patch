/**
 * @fileoverview 保存跨路由共享的客户端认证视图与纯状态转换。
 *
 * 认证 Hook 生产状态，受保护路由和应用壳消费；Store 只持有脱敏用户信息，不发请求、
 * 不持久化，也不保存 Access Token、Refresh Token 或密码。匿名转换必须同时删除用户对象，
 * 防止登出或用户切换后旧数据继续显示。
 */
import { create } from "zustand";
import type { SessionUser } from "../server/contracts.js";

/** 应用启动、匿名与已认证三种互斥的客户端会话阶段。 */
export type AuthStatus = "booting" | "anonymous" | "authenticated";

/** 认证页面与应用壳共享的纯内存状态及允许的转换。 */
export interface AuthStore {
  /** 当前会话阶段；启动恢复结束前保持 `booting`。 */
  status: AuthStatus;
  /** 服务端返回的脱敏用户视图；匿名或启动阶段不得保留旧值。 */
  user: SessionUser | undefined;
  /** 由认证 Hook 在会话确认后调用，同时写入用户和已认证状态。 */
  setAuthenticated: (user: SessionUser) => void;
  /** 由恢复失败或登出流程调用，同时清除用户并切换为匿名状态。 */
  setAnonymous: () => void;
}

/** React 组件消费的 Zustand 认证 Store；其 action 只执行同步内存更新。 */
export const useAuthStore = create<AuthStore>((set) => ({
  status: "booting",
  user: undefined,
  /** 接受认证 API 的脱敏用户，并原子切换到已认证状态。 */
  setAuthenticated(user): void {
    set({ status: "authenticated", user });
  },
  /** 清除当前用户并原子切换到匿名状态，避免跨会话数据残留。 */
  setAnonymous(): void {
    set({ status: "anonymous", user: undefined });
  },
}));
