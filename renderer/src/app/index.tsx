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
import { StyleEditorPage } from "../pages/style-editor/index.js";
import { useAuthStore } from "../stores/auth-store.js";
import styles from "./index.module.scss";

function ProtectedShell(): React.JSX.Element {
  const status = useAuthStore((state) => state.status);
  if (status !== "authenticated") {
    return <Navigate replace to="/login" />;
  }
  return <AppShell />;
}

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
