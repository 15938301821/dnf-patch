import { useState } from "react";
import { Avatar, Button, Drawer, Layout, Menu, Tooltip } from "antd";
import {
  BookOpen,
  Boxes,
  LogOut,
  Menu as MenuIcon,
  Settings,
} from "lucide-react";
import { Outlet, useLocation, useNavigate } from "react-router-dom";
import { apiMode } from "../../api/mode.js";
import { useAuthCommands } from "../../hooks/use-auth.js";
import { useAuthStore } from "../../stores/auth-store.js";
import styles from "./index.module.scss";

const navigation = [
  { key: "/professions", icon: <BookOpen size={18} />, label: "职业与风格" },
  { key: "/jobs", icon: <Boxes size={18} />, label: "制作任务" },
  { key: "/settings", icon: <Settings size={18} />, label: "模型设置" },
];

function selectedPath(pathname: string): string {
  if (pathname.startsWith("/jobs")) {
    return "/jobs";
  }
  if (pathname.startsWith("/settings")) {
    return "/settings";
  }
  return "/professions";
}

export function AppShell(): React.JSX.Element {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();
  const user = useAuthStore((state) => state.user);
  const { logout } = useAuthCommands();

  const menu = (
    <Menu
      className={styles.menu}
      items={navigation}
      mode="inline"
      onClick={({ key }) => {
        void navigate(key);
        setDrawerOpen(false);
      }}
      selectedKeys={[selectedPath(location.pathname)]}
    />
  );

  return (
    <Layout className={styles.shell}>
      <Layout.Sider className={styles.sider} theme="light" width={232}>
        <div className={styles.brand}>
          <span className={styles.mark}>DP</span>
          <div>
            <strong>DNF Patch</strong>
            <span>Studio</span>
          </div>
        </div>
        {menu}
        <div className={styles["sider-foot"]}>
          <span>{apiMode === "mock" ? "Mock API" : "Remote API"}</span>
          <strong>{apiMode === "mock" ? "前端联调" : "服务端连接"}</strong>
        </div>
      </Layout.Sider>

      <Drawer
        onClose={() => setDrawerOpen(false)}
        open={drawerOpen}
        placement="left"
        size={280}
        title="DNF Patch Studio"
      >
        {menu}
      </Drawer>

      <Layout className={styles.workspace}>
        <Layout.Header className={styles.header}>
          <Button
            aria-label="打开导航"
            className={styles["menu-button"] ?? ""}
            icon={<MenuIcon size={19} />}
            onClick={() => setDrawerOpen(true)}
            type="text"
          />
          <div className={styles.identity}>
            <Avatar className={styles.avatar ?? ""} size={34}>
              {user?.displayName.slice(0, 1) ?? "U"}
            </Avatar>
            <span>{user?.displayName}</span>
            <Tooltip title="退出登录">
              <Button
                aria-label="退出登录"
                icon={<LogOut size={17} />}
                onClick={() => void logout()}
                type="text"
              />
            </Tooltip>
          </div>
        </Layout.Header>
        <Layout.Content className={styles.content}>
          <Outlet />
        </Layout.Content>
      </Layout>
    </Layout>
  );
}
