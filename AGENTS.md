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
- 模型 API Key 只能在用户主动保存或轮换时，作为受认证专用 HTTPS 配置请求的字段提交给后端；前端只在表单内短暂持有，提交后必须清空，不得持久化、回显或从读取接口恢复明文。
- 前端不得直接调用模型 Provider，也不得提供通用 Prompt、任意模型或模型代理入口。业务任务请求只能提交后端定义的声明式参数，不能携带 API Key、临时 endpoint 或绕过用户固定角色配置。
- 模型配置读取 DTO 只能包含固定角色、endpoint、模型 ID、配置版本和 `keyConfigured` 等脱敏元数据；不得包含密钥、密文、nonce、认证标签或 Secret Manager 引用。
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

## 中文备注与可维护性

- 代码必须以首次接触当前模块的前端工程师能够独立维护为验收标准，不能假设维护者熟悉
  既有页面流程、后端契约、Electron 安全模型或历史实现。
- 新增或实质性重写的 TypeScript、TSX、JavaScript 和 Electron 源文件必须提供中文文件头，
  说明文件职责、调用位置、输入输出、副作用及不能删除的安全边界。
- 导出的组件、Hook、Store、API 函数、公共类型和复杂私有函数必须提供中文 JSDoc；三个以上
  业务阶段、异步竞态、清理流程和安全检查必须添加中文步骤备注。
- API、认证、Mock、路由、状态与 Electron 术语在模块首次出现时必须解释。备注要说明
  “为什么”和失败后禁止发生的动作，不能只把 TypeScript 或 JSX 语法翻译成中文。
- 具体格式与模板遵守 `.github/instructions/global.instructions.md` 和
  `.github/instructions/client.instructions.md`。代码变化时必须同步更新备注，过时备注按代码
  缺陷处理。

## 验证

- 前端或桌面壳修改至少运行 `npm run typecheck`、`npm run lint` 和 `npm run test:unit`。
- 样式、路由或用户流程修改还要运行 `npm run build` 和 `npm run test:e2e`。
- 完整静态门禁使用 `npm run gate:static`，完整浏览器与桌面双目标门禁使用
  `npm run gate:project`。
