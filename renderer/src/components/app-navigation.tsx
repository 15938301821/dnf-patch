import { FolderKanban, Gauge, LayoutDashboard, Settings } from "lucide-react";
import type { ServerConnectionState } from "../../../server/shared/contracts.js";
import type { AppPage, NavigationItem } from "../types/navigation.js";

interface AppNavigationProps {
  page: AppPage;
  serverState: ServerConnectionState | undefined;
  onNavigate: (page: AppPage) => void;
}

const items: readonly NavigationItem[] = [
  { id: "dashboard", label: "控制台", description: "本地生产入口" },
  { id: "project-setup", label: "项目", description: "事实源与注册" },
  { id: "monitor", label: "监控", description: "Run 与事件" },
  { id: "settings", label: "设置", description: "连接与模型" },
];

const icons = {
  dashboard: LayoutDashboard,
  "project-setup": FolderKanban,
  monitor: Gauge,
  settings: Settings,
} as const;

/** 顶层视图导航；页面切换不触发任何生产动作。 */
export function AppNavigation({
  page,
  serverState,
  onNavigate,
}: AppNavigationProps): React.JSX.Element {
  return (
    <nav aria-label="应用视图" className="app-navigation">
      <div className="navigation-items">
        {items.map((item) => {
          const Icon = icons[item.id];
          return (
            <button
              aria-current={page === item.id ? "page" : undefined}
              className={page === item.id ? "active" : undefined}
              key={item.id}
              onClick={() => onNavigate(item.id)}
              title={item.description}
              type="button"
            >
              <Icon aria-hidden="true" size={16} />
              <span>{item.label}</span>
            </button>
          );
        })}
      </div>
      <div
        className={`server-indicator mode-${serverState?.mode ?? "offline"}`}
      >
        <i />
        <span>
          {serverState?.mode === "connected" ? "服务已连接" : "本地模式"}
        </span>
      </div>
    </nav>
  );
}
