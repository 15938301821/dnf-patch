/**
 * @fileoverview 组合 Renderer 根 Provider、认证启动状态与浏览器/桌面共用路由。
 *
 * 启动入口渲染 App，App 调用认证生命周期并按 Store 状态切换登录页或受保护页面；页面数据
 * 仍由各自 API 模块加载。本文件只产生路由和 Provider 渲染副作用，不发领域请求。protected
 * route（受保护路由）仅表示客户端已有会话视图，不能替代后端对每个请求的认证与授权。
 */
import { ConfigProvider, Spin } from "antd";
import zhCN from "antd/locale/zh_CN";
import { HashRouter, Navigate, Route, Routes } from "react-router-dom";
import { AppShell } from "../components/app-shell/index.js";
import { antdTheme } from "../config/antd-theme.js";
import { useAuthLifecycle } from "../hooks/use-auth.js";
import { LoginPage } from "../pages/login/index.js";
import { JobsPage } from "../pages/jobs/index.js";
import { ProfessionsPage } from "../pages/professions/index.js";
import { SettingsPage } from "../pages/settings/index.js";
import { StyleCreatePage } from "../pages/style-create/index.js";
import { StyleEditorPage } from "../pages/style-editor/index.js";
import { useAuthStore } from "../stores/auth-store.js";
import styles from "./index.module.scss";

/**
 * 在客户端认证状态确认后渲染应用壳，否则替换历史并返回登录页。
 *
 * @returns 已认证时的嵌套路由容器，或匿名状态下的重定向指令。
 */
function ProtectedShell(): React.JSX.Element {
  const status = useAuthStore((state) => state.status);
  if (status !== "authenticated") {
    return <Navigate replace to="/login" />;
  }
  return <AppShell />;
}

/**
 * 提供全局主题、HashRouter 与认证驱动的顶层路由树。
 *
 * @returns 浏览器和 Electron 共用的应用组件；启动恢复期间只显示阻塞加载状态。
 */
export function App(): React.JSX.Element {
  useAuthLifecycle();
  const status = useAuthStore((state) => state.status);

  return (
    <ConfigProvider locale={zhCN} theme={antdTheme}>
      <HashRouter>
        {status === "booting" ? (
          <div className={styles.boot}>
            <Spin size="large" />
          </div>
        ) : (
          <Routes>
            <Route element={<LoginPage />} path="/login" />
            <Route element={<ProtectedShell />}>
              <Route element={<ProfessionsPage />} path="/professions" />
              <Route
                element={<StyleCreatePage />}
                path="/professions/:professionId/styles/new"
              />
              <Route
                element={<StyleEditorPage />}
                path="/professions/:professionId/styles/:styleId"
              />
              <Route element={<JobsPage />} path="/jobs" />
              <Route element={<SettingsPage />} path="/settings" />
            </Route>
            <Route element={<Navigate replace to="/professions" />} path="*" />
          </Routes>
        )}
      </HashRouter>
    </ConfigProvider>
  );
}
