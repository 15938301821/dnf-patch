# DNF Patch Studio 仓库规则

## 项目定位

本仓库只包含 DNF Patch Studio 的浏览器前端和 Electron 桌面壳。职业、技能、风格、
模型配置、任务、产物生成和下载地址均由后端 API 提供；本地 Mock 只用于前端开发和
演示。浏览器与桌面端加载同一套 `renderer/`，桌面壳不复制业务逻辑。

不得在本仓库重新引入本地后端、Worker、CLI、NPK/IMG 处理、职业事实源、补丁工具链、
运行证据或部署能力。前端和 Electron 壳都不得读取游戏目录、执行本机工具、解析补丁
文件或宣称资源映射、产物兼容性、覆盖率和部署状态。

## 目录边界

- `renderer/`：React 应用、页面、组件、状态、HTTP API 与 Mock API。
- `electron/`：最小桌面容器、窗口安全和无业务 Preload。
- `tests/`：纯函数、状态、浏览器用户流程和桌面壳安全测试。
- `vite.config.ts`：浏览器开发与生产构建入口。
- `electron.vite.config.ts`：桌面主进程、Preload 与同一 Renderer 的构建入口。
- `.github/instructions/`：当前工程规则。

禁止创建 `server/`、`jobs/`、`tools/`、`resources/`、`userData/`、`apps/desktop/`、
`desktop/` 或根级 `src/`。构建输出只允许出现在被忽略的 `dist-web/` 与 `out/`，
测试输出只允许出现在被忽略的 `test-results/` 与 `playwright-report/`。

## 前端边界

- 页面、组件、Hook 和 Store 只能通过 `renderer/src/api/` 调用后端。
- `renderer/src/api/` 使用 Axios 和类型化 DTO；不得从服务端实现复制执行逻辑。
- `VITE_API_MODE=remote` 时连接 `VITE_API_BASE_URL`；其他情况使用同契约 Mock。
- Access Token 只保存在内存中；Refresh Token 由后端使用 HttpOnly Cookie 管理。
- 模型 API Key 只能作为 HTTPS 请求字段提交给后端，前端不得持久化或回显明文。
- 不在源码、环境示例、日志、测试、URL、Local Storage 或 Session Storage 中保存凭据。
- 后端返回的职业、技能和稳定 ID 是业务事实；AI 只能生成草稿，不能发明技能或推断
  NPK/IMG 资源映射。
- 任务创建必须尊重后端返回的资源核验与可执行状态；Mock 也必须执行同样门禁。
- Electron 必须保持 `contextIsolation`、`sandbox`、`nodeIntegration: false` 和
  `webSecurity`；Preload 只做环境断言，不暴露通用 IPC 或业务桥接对象。
- Electron 主进程拒绝未授权的新窗口、外部导航、WebView 与权限请求。

## 工程规则

- 单个 TypeScript、TSX、JavaScript 或样式文件不得超过 500 个物理行；达到 400 行
  时先拆分职责。复杂组件达到 300 行时优先拆分组件、Hook 或纯函数。
- 新目录和源码文件使用 kebab-case；React 组件和类型使用 PascalCase；函数、变量和
  Hook 使用 camelCase，Hook 以 `use` 开头。
- 组件样式使用同目录同名 `*.module.scss`；`renderer/src/global.css` 只保存全局令牌、
  reset 和可访问性基础规则。
- 不覆盖或回退用户未提交的无关修改，不提交构建输出、测试输出或凭据。
- 修改行为时补充与风险相称的测试；保持正式 API 与 Mock API 的 DTO 和状态语义一致。

## 验证

- 前端或桌面壳修改至少运行 `npm run typecheck`、`npm run lint` 和 `npm run test:unit`。
- 样式、路由或用户流程修改还要运行 `npm run build` 和 `npm run test:e2e`。
- 完整静态门禁使用 `npm run gate:static`，完整浏览器与桌面双目标门禁使用
  `npm run gate:project`。
