import { AppNavigation } from "./components/app-navigation.js";
import { Topbar } from "./components/topbar.js";
import { usePatchStudio } from "./hooks/use-patch-studio.js";
import { useServerConnection } from "./hooks/use-server-connection.js";
import { DashboardPage } from "./pages/dashboard-page.js";
import { MonitorPage } from "./pages/monitor-page.js";
import { ProjectSetupPage } from "./pages/project-setup-page.js";
import { SettingsPage } from "./pages/settings-page.js";
import { useNavigationStore } from "./stores/navigation-store.js";

/** 页面组合层；本地流水线和服务连接使用独立状态控制器。 */
export function App(): React.JSX.Element {
  const studio = usePatchStudio();
  const server = useServerConnection();
  const navigation = useNavigationStore();

  return (
    <div className="app-shell">
      <Topbar />
      <AppNavigation
        onNavigate={navigation.navigate}
        page={navigation.page}
        serverState={server.state}
      />
      <main className={`page-${navigation.page}`}>
        {navigation.page === "dashboard" ? (
          <DashboardPage studio={studio} />
        ) : null}
        {navigation.page === "project-setup" ? (
          <ProjectSetupPage server={server} studio={studio} />
        ) : null}
        {navigation.page === "monitor" ? <MonitorPage studio={studio} /> : null}
        {navigation.page === "settings" ? (
          <SettingsPage server={server} studio={studio} />
        ) : null}
      </main>
    </div>
  );
}
