---
name: "DNF Patch Browser And Desktop Client"
description: "Use when editing the React renderer, browser state, typed HTTP API, Electron shell, CSS Modules, or frontend tests in DNF Patch Studio."
applyTo:
  [
    "renderer/**/*.{ts,tsx,css,scss,html}",
    "electron/**/*.ts",
    "tests/**/*.{ts,tsx}",
    "vite.config.ts",
    "electron.vite.config.ts",
    "playwright.config.ts",
  ]
---

# 浏览器与桌面客户端规范

## 目录职责

| 路径                       | 职责                                       |
| -------------------------- | ------------------------------------------ |
| `renderer/src/api/`        | DTO、认证、Axios 客户端与同契约 Mock       |
| `renderer/src/app/`        | 应用 Provider、路由与受保护页面组合        |
| `renderer/src/pages/`      | 路由页面、请求编排和页面级状态             |
| `renderer/src/components/` | 可复用展示与交互组件                       |
| `renderer/src/hooks/`      | 单一浏览器生命周期或命令                   |
| `renderer/src/stores/`     | Zustand 领域状态，不持有网络和持久化副作用 |
| `renderer/src/config/`     | 稳定、无副作用的展示配置                   |
| `renderer/src/utils/`      | 无副作用计算与错误映射                     |
| `electron/`                | 安全窗口、导航策略和无业务 Preload         |

## 类与函数注释

- 新增公共类、公共方法、导出函数以及复杂私有方法必须使用 JSDoc。
- JSDoc 必须按实际情况说明职责、参数、返回值、异常、外部 I/O、数据库写入、广播或其他副作用。
- 简单 DTO、Zod schema、Nest 模块装配和语义显然的薄封装无需逐字段复述。
- 注释必须解释“为什么这样约束”和边界条件，禁止把代码逐句翻译成中文。
- 复杂事务、状态机、幂等处理、租约 fencing、哈希规范化、递归输入检查和安全降级必须注释其不变量。
- 注释不得作出未验证承诺，例如“完全兼容”“已经部署”“覆盖全部技能”或“生产可用”。

## HTTP 与安全

- 页面、组件、Hook 和 Store 不直接调用 `fetch`、Axios、WebSocket、EventSource 或
  XMLHttpRequest，只调用 `api/` 导出的类型化函数。
- `api/` 不导入 Node、Electron、文件系统、后端实现、数据库 SDK 或模型 SDK。
- Access Token 仅保存在模块内存；Refresh Token 由后端通过 HttpOnly Cookie 管理。
- API Key 只随保存请求发给后端，不进入 Store、浏览器存储、URL、日志或返回 DTO。
- 远程 API 基址只来自 `VITE_API_BASE_URL`，不得在组件中读取或展示服务凭据。
- Mock 使用与正式 API 相同的函数、DTO、错误码和执行门禁，不形成第二套页面逻辑。

## Electron 壳

- `BrowserWindow` 必须使用 `contextIsolation: true`、`sandbox: true`、
  `nodeIntegration: false` 和 `webSecurity: true`。
- 主进程拒绝外部导航、重定向、新窗口、WebView 和权限请求；开发 URL 只能来自
  `ELECTRON_RENDERER_URL`，生产环境只加载构建后的同一 Renderer。
- Preload 不暴露 `ipcRenderer`、通用 `send/invoke/on`、Node 对象或业务 API；当前只
  校验隔离环境。
- 主进程不读取职业目录、不启动后端、不执行本机工具、不写 Run 证据。

## React 与状态

- 组件内短暂 UI 状态使用 `useState`；跨页面会话状态使用按领域拆分的 Zustand Store。
- Store 保持纯状态，不发请求、不设定时器、不访问浏览器存储。
- 副作用放在页面或专责 Hook，具备明确依赖、过期结果保护和清理路径。
- 测试使用角色、可访问名称和可观察状态，不依赖 CSS Modules 生成类名。

## 样式

- `renderer/src/global.css` 只包含设计令牌、reset、字体继承和全局可访问性基础规则。
- 页面与组件样式必须位于同目录同名 `*.module.scss`，不使用全局组件选择器、
  CSS-in-JS 或跨组件样式导入。
- 固定格式控件使用稳定尺寸、网格、`aspect-ratio` 或 `minmax()`，并验证桌面与
  390px 移动视口无水平溢出或文字遮挡。

## 验证

- 客户端或桌面壳改动运行 `npm run gate:static`。
- 路由、响应式布局或完整用户流程改动运行 `npm run gate:project`。
