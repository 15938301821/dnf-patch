/**
 * @fileoverview 提供受保护页面共用的桌面侧栏、移动抽屉、身份区与嵌套路由出口。
 *
 * App 的受保护路由渲染本组件，导航来自当前 location，用户来自认证 Store；唯一外部副作用
 * 是导航和调用认证 Hook 登出。组件不判定后端授权，不读取 Token；登出后 Store 状态驱动
 * 根路由离开受保护区域，移动导航命令必须同时关闭抽屉。
 */
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

/** 应用壳展示的稳定一级路由，不包含业务权限推断。 */
const navigation = [
  { key: "/professions", icon: <BookOpen size={18} />, label: "职业与风格" },
  { key: "/jobs", icon: <Boxes size={18} />, label: "制作任务" },
  { key: "/settings", icon: <Settings size={18} />, label: "模型设置" },
];

/** 把嵌套路由路径收敛为侧栏的一级选中键。 */
function selectedPath(pathname: string): string {
  if (pathname.startsWith("/jobs")) {
    return "/jobs";
  }
  if (pathname.startsWith("/settings")) {
    return "/settings";
  }
  return "/professions";
}

/**
 * 渲染已认证客户端的响应式应用外壳。
 *
 * @returns 固定侧栏或移动抽屉、身份命令及当前子路由 Outlet。
 */
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
