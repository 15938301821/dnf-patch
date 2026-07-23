/**
 * @fileoverview 创建并维护只加载同一 Renderer 的最小 Electron 桌面窗口。
 *
 * Electron 主进程（拥有 Node 与窗口权限）在应用就绪后调用本文件，开发环境加载受限本地
 * URL，生产环境加载构建后的 Renderer；React 业务仍完全位于 Renderer。副作用包括窗口、
 * 会话权限策略和应用生命周期。必须保持进程隔离、沙箱、Node 禁用、Web 安全以及导航、
 * 重定向、新窗口、WebView 和权限的失败关闭策略，不得在此读取游戏目录或执行本机工具。
 */
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { app, BrowserWindow, dialog, session } from "electron";
import { isAllowedRendererNavigation } from "./utils/window-security.js";

/** 构建后主进程入口目录，仅用于解析受控 Preload 与 Renderer 产物。 */
const mainDirectory = fileURLToPath(new URL(".", import.meta.url));

/**
 * 解析本次窗口允许加载的唯一 Renderer 入口。
 *
 * @returns 开发服务器 URL 或生产 HTML 文件 URL；不接受页面运行时输入。
 */
function rendererEntryUrl(): string {
  return (
    process.env.ELECTRON_RENDERER_URL ??
    pathToFileURL(join(mainDirectory, "../renderer/index.html")).toString()
  );
}

/** 拒绝默认会话中的全部 Chromium 权限检查和交互式权限请求。 */
function hardenSession(): void {
  session.defaultSession.setPermissionCheckHandler(() => false);
  session.defaultSession.setPermissionRequestHandler(
    (_webContents, _permission, callback) => callback(false),
  );
}

/**
 * 创建、加固并加载一个桌面窗口。
 *
 * @returns Renderer 成功加载后的 BrowserWindow；加载或安全初始化失败时拒绝。
 */
async function createWindow(): Promise<BrowserWindow> {
  const entryUrl = rendererEntryUrl();
  const window = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 980,
    minHeight: 680,
    show: false,
    backgroundColor: "#f3f5f7",
    title: "DNF Patch Studio",
    webPreferences: {
      preload: join(mainDirectory, "../preload/index.cjs"),
      // Renderer 与 Preload 使用不同全局对象，阻止页面直接取得高权限上下文。
      contextIsolation: true,
      // 页面不得使用 Node 模块、require 或文件系统能力。
      nodeIntegration: false,
      // Chromium 沙箱限制被攻陷 Renderer 可触达的操作系统能力。
      sandbox: true,
      // 保留同源、证书和混合内容检查，不能为开发便利关闭。
      webSecurity: true,
    },
  });

  // 所有新窗口和 WebView 默认拒绝，防止不受控页面获得桌面窗口上下文。
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-attach-webview", (event) => {
    event.preventDefault();
  });
  window.webContents.on("will-navigate", (event, targetUrl) => {
    // 仅允许同一入口文件内的 Hash 路由；跨源或相邻文件导航必须中止。
    if (!isAllowedRendererNavigation(targetUrl, entryUrl)) {
      event.preventDefault();
    }
  });
  window.webContents.on("will-redirect", (event, targetUrl) => {
    // HTTP 重定向同样经过入口白名单，不能绕过主动导航限制。
    if (!isAllowedRendererNavigation(targetUrl, entryUrl)) {
      event.preventDefault();
    }
  });
  window.once("ready-to-show", () => window.show());
  await window.loadURL(entryUrl);
  return window;
}

/** 应用就绪后按“加固会话 -> 创建窗口 -> 注册重新激活”执行；任一步失败都退出而不降级安全设置。 */
app
  .whenReady()
  .then(async () => {
    // 第一步：先安装会话权限拒绝策略，再创建任何可加载网页的窗口。
    hardenSession();
    await createWindow();
    // 第二步：macOS 激活且无窗口时复用同一安全创建流程。
    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        void createWindow();
      }
    });
  })
  .catch((error: unknown) => {
    // 第三步：启动链失败只显示错误并退出，禁止以降级安全配置继续运行。
    const message = error instanceof Error ? error.message : String(error);
    dialog.showErrorBox("DNF Patch Studio 启动失败", message);
    app.exit(1);
  });

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
