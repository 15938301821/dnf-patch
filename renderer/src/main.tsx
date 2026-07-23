/**
 * @fileoverview 浏览器与 Electron 共用 Renderer 的启动入口。
 *
 * Vite 执行本文件后，入口先按构建模式安装同契约 Mock API，再延迟加载路由应用并挂载到
 * HTML 根节点。这里不承载页面业务或认证数据；副作用仅包括注册 Mock 拦截器和创建 React
 * 根。Mock 必须先于应用模块加载，防止页面首个请求绕过替身；根节点缺失时禁止继续渲染。
 */
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "antd/dist/reset.css";
import { apiMode } from "./api/mode.js";
import "./global.css";

/**
 * 按运行模式准备网络边界并挂载应用。
 *
 * @returns 所有启动依赖完成后结算的 Promise；根节点缺失或模块加载失败时拒绝。
 */
async function bootstrap(): Promise<void> {
  // 第一步：仅在显式 Mock 模式安装 Axios 适配器，且必须早于任何页面请求。
  if (apiMode === "mock") {
    const { configureMockApi } = await import("./mock/index.js");
    configureMockApi();
  }
  // 第二步：并行取得应用模块和 HTML 挂载点，任一缺失都不能进入渲染阶段。
  const [{ App }, root] = await Promise.all([
    import("./app/index.js"),
    Promise.resolve(document.getElementById("root")),
  ]);
  if (root === null) {
    throw new Error("Renderer root element is missing.");
  }
  // 第三步：浏览器与 Electron 都挂载同一组件树，桌面壳不复制业务逻辑。
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}

void bootstrap();
