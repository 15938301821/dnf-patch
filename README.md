# DNF Patch Studio

DNF Patch Studio 是共享 React 前端与最小 Electron 桌面壳。它负责职业与风格管理、
技能范围选择、三角色模型配置、任务状态和产物下载；职业目录、资源核验、AI 调用、
补丁生成和文件存储均由后端服务负责。

## 本地运行

```powershell
npm ci
npm run dev
```

`npm run dev` 启动 Electron 桌面端，`npm run dev:web` 只启动浏览器端。两者加载同一套
Renderer，开发服务固定监听 `http://127.0.0.1:5173`。普通开发默认连接正式后端；只有
显式设置 `VITE_API_MODE=mock` 时才加载 Mock API。E2E 独立读取 `.env.e2e`，不会改变
普通开发模式。

## 远程 API

在未提交的 `renderer/.env.local` 中配置：

```dotenv
VITE_API_MODE=remote
VITE_API_BASE_URL=http://127.0.0.1:56789/v1
```

前端要求后端使用统一的 `{ "data": ... }` 响应包络。Access Token 只保存在浏览器
内存中；Refresh Token 应由后端设置为 HttpOnly Cookie。模型 API Key 只通过 HTTPS
提交给后端，后端响应不得返回明文。

## 项目结构

```text
renderer/
├─ index.html
└─ src/
   ├─ api/          # DTO、Axios 客户端与 Mock API
   ├─ app/          # Provider、路由与登录保护
   ├─ assets/       # 只读前端资源
   ├─ components/   # 可复用组件与同名 SCSS Modules
   ├─ config/       # Ant Design 等展示配置
   ├─ hooks/        # 浏览器生命周期
   ├─ pages/        # 职业、编辑、任务、模型设置与登录页面
   ├─ stores/       # Zustand 状态
   └─ utils/        # 纯函数与错误映射
electron/
├─ main.ts          # 安全 BrowserWindow 容器
├─ preload.ts       # 无业务桥接的隔离环境断言
└─ utils/           # 导航安全纯函数
tests/
├─ e2e/             # Playwright 浏览器与桌面流程
└─ *.test.ts        # Vitest 单元测试
```

本仓库不包含本地后端、Worker、CLI、职业资产、NPK/IMG 处理、游戏目录访问或部署
实现。Electron 只加载同一套前端，不提供业务 IPC。职业、技能、资源映射和任务状态均
以后端响应为事实源。

## 命令

| 命令                   | 说明                            |
| ---------------------- | ------------------------------- |
| `npm run dev`          | 启动 Electron 桌面开发环境      |
| `npm run dev:web`      | 仅启动浏览器开发服务            |
| `npm run build`        | 构建 `dist-web/` 与 `out/`      |
| `npm run preview`      | 预览生产构建                    |
| `npm run typecheck`    | 检查前端、桌面壳与测试配置      |
| `npm run lint`         | 检查前端边界和代码质量          |
| `npm run test:unit`    | 运行 Vitest 单元测试            |
| `npm run test:e2e`     | 构建并运行浏览器与桌面 E2E      |
| `npm run gate:static`  | 运行格式、类型、Lint 与单测门禁 |
| `npm run gate:project` | 运行静态门禁和完整双目标 E2E    |

## 构建与安全

- 页面、组件、Hook 和 Store 只能通过 `renderer/src/api/` 访问后端。
- Electron 保持上下文隔离、沙箱和 Node 禁用，并拒绝外部导航、新窗口与权限请求。
- Mock 与远程 API 共用同一套 DTO 和页面代码。
- AI 只能生成已选稳定技能 ID 的设计草稿，不能自行发明技能或推断资源映射。
- 资源未被后端标记为 `build-ready` 时，前端和 Mock 都会阻止创建制作任务。
- `dist-web/`、`out/`、`test-results/`、`playwright-report/` 和本地环境文件不进入源码。
