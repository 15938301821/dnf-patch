---
name: "DNF Patch Browser And Desktop Client"
description: "Use when editing the React renderer, browser state, typed HTTP API, Electron shell, CSS Modules, or frontend tests in DNF Patch Studio."
applyTo: "renderer/**/*.{ts,tsx,css,scss,html}, electron/**/*.ts, tests/**/*.{ts,tsx}, vite.config.ts, electron.vite.config.ts, playwright.config.ts"
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

## 中文备注与前端维护

### 文件头说明

新增或实质性重写的 TypeScript、TSX 和 Electron 源文件必须在 import 前提供中文文件头，
让维护者打开文件后立即知道：

1. **文件职责**：负责哪个页面、组件、状态、API 或桌面壳行为，以及明确不负责什么。
2. **流程位置**：由哪个路由、父组件、Hook 或进程入口调用，继续调用哪些模块。
3. **数据流**：数据来自 Props、Store、URL、API 还是配置，最终展示或提交到哪里。
4. **副作用**：是否发请求、订阅事件、设置定时器、写浏览器历史或触发 Electron 行为。
5. **安全与维护边界**：认证信息如何处理，哪些调用顺序、清理或隔离设置不能删除。

推荐模板：

```ts
/**
 * @fileoverview 模型配置页面的请求编排与表单状态入口。
 *
 * 流程位置：受保护路由渲染本页面；页面通过 api/model-configuration 读取和保存配置，
 * 展示组件只接收脱敏后的 ViewModel，不直接访问 Axios 或认证状态。
 *
 * 输入：当前登录用户、固定角色列表和用户在本页输入的表单值。
 * 输出：加载/空/错误/可编辑状态，以及保存成功后的脱敏配置。
 * 副作用：发起受认证 HTTPS 请求；保存后立即清空 API Key 输入框。
 * 安全边界：API Key 不能进入 Store、URL、日志或读取响应。
 */
```

纯常量或纯类型文件也必须用一至三句说明数据由谁生产、谁消费。只做显而易见重导出的
`index.ts` 可以使用简短文件头，但不能把业务逻辑藏在重导出文件中。

### 导出 API 与 JSDoc

- 所有导出的 React 组件、Hook、Store、Store action、API 函数、类、函数、接口和业务类型
  必须有中文 JSDoc。简单 DTO 可以只写一句来源与用途；非显然字段必须有属性备注。
- 复杂私有函数、异步回调、错误映射、响应规范化、路由门禁和 Electron 安全处理也必须有
  JSDoc，不能因为未导出就省略维护上下文。
- JSDoc 按实际情况说明调用者、调用时机、参数业务含义、返回值、可观察错误、外部 I/O、
  状态写入、定时器/订阅和清理方式。
- `@param` 说明值从哪里来、是否已校验以及与其他参数的关系，不能只重复参数名。
- `@returns` 说明页面或调用方能依赖的语义，以及结果不代表的状态。例如
  `keyConfigured: true` 只代表服务端已有密钥，不代表前端能读取密钥明文。
- React 组件通常不写无意义的 `@throws`；请求错误如何转换为加载、错误、空状态或通知，应在
  页面/Hook 备注中说明。

推荐模板：

```tsx
/**
 * 展示并编辑当前用户的固定角色模型配置。
 *
 * 调用关系：由 SettingsPage 渲染；数据加载和保存由 useModelConfiguration 负责，
 * 本组件只管理输入与可见交互状态。
 *
 * @param props 已脱敏的配置、保存状态和页面命令；不会包含 API Key 明文。
 * @returns 包含加载、保存、错误和 keyConfigured 状态的表单界面。
 */
```

### 页面与组件备注

- 页面文件头说明对应路由、进入条件、主要请求、页面级状态和离开页面时的清理行为。
- 组件 JSDoc 说明它是受控还是非受控、关键 Props 的业务含义、事件回调由谁处理，以及组件
  是否发请求或读取 Store。默认情况下展示组件不得暗中产生网络副作用。
- 复杂页面按“读取路由参数 -> 加载数据 -> 门禁判断 -> 用户操作 -> 提交 -> 刷新状态”等
  真实阶段添加中文步骤备注。失败时不得继续提交、跳转或覆盖新状态的原因必须写清楚。
- 条件渲染需要能从备注或提取函数名看出 loading、empty、error、forbidden 和 ready 的区别，
  不堆叠无法理解的多层三元表达式后再写一句泛化注释。
- JSX 备注只用于解释非显然的业务分区、无障碍关联或必须保持的 DOM 关系，不给每个容器、
  按钮和文本逐项加注释。

### Hook 与异步流程备注

- 自定义 Hook 必须说明它管理哪个生命周期、读取哪些外部状态、返回哪些命令，以及调用方
  必须满足的前置条件。
- 使用 `useEffect`、请求、订阅、定时器或 AbortController 时，必须说明创建与清理所有权、
  依赖变化后的行为、过期结果为何不会覆盖新状态。
- 多请求或保存后刷新流程必须按步骤备注顺序、可取消点和错误落点。不得只写“加载数据”或
  “处理错误”。
- 使用 `startTransition`、`useDeferredValue` 或同类并发能力时，说明哪些状态允许延后、哪些
  用户输入或安全状态必须立即生效。

### Store 备注

- Store 文件头说明状态所有权、生命周期、哪些页面共享，以及为什么该状态需要跨组件存在。
- 每个导出的 action 说明允许的状态转换和调用方。Store 必须保持纯状态，备注不得暗示它会
  发请求、设置定时器或持久化秘密。
- 重置、登出、用户切换和请求过期等清理动作必须说明会清除哪些状态，避免后期维护造成
  跨用户数据残留。

### API 与契约备注

- API 模块文件头说明对应服务端领域和认证方式，不复制服务端内部实现。
- 每个导出 API 函数说明 HTTP 方法与相对端点、请求 DTO 来源、响应 ViewModel 语义、稳定
  错误如何映射，以及是否会发送 Cookie 或 Access Token。
- DTO 和 ViewModel 首次出现时说明生产方和消费方；名称相似但安全级别不同的写入 DTO、
  读取 DTO 和表单状态必须分别备注。
- 正式 API 与 Mock API 的同名函数必须说明共享契约。Mock 备注明确它用于前端演示和测试，
  不证明真实 Server、数据库、Worker、对象存储或模型调用可用。
- 认证刷新、请求重试和并发去重必须备注触发条件、幂等前提和失败行为，避免后期加入无限
  重试或把非幂等写请求重复提交。

### Electron 备注

- `main.ts` 文件头说明开发/生产加载路径、窗口创建流程、导航限制和关闭生命周期。
- Preload 文件头明确当前允许暴露的最小能力和禁止暴露的 Node/IPC 能力。
- `contextIsolation`、`sandbox`、`nodeIntegration: false`、`webSecurity`、导航拦截、窗口拦截
  和权限拒绝旁必须用中文解释威胁边界，不能只写“安全设置”。
- Electron 主进程与 Renderer 的术语首次出现时说明二者信任边界，不能假设普通 React
  维护者熟悉 Chromium 进程模型。

### 术语首次出现时的解释

每个模块首次使用以下术语时，必须在文件头、类型 JSDoc 或相关函数备注中提供局部解释：

| 术语            | 备注中应说明的最小含义                                             |
| --------------- | ------------------------------------------------------------------ |
| DTO             | API 传输结构，不是组件可随意扩展的本地状态，也不等于服务端数据库行 |
| ViewModel       | 已整理为界面消费形状的数据，可能比原始 DTO 更少且必须保持脱敏      |
| Access Token    | 仅存于模块内存并附加到受认证请求的短期凭据                         |
| Refresh Token   | 由服务端通过 HttpOnly Cookie 管理，前端 JavaScript 不读取其明文    |
| Mock API        | 与正式 API 保持同一 DTO 和状态语义的前端替身，不是第二套业务规则   |
| `keyConfigured` | 只表示服务端存在模型密钥，不表示客户端能够读取或恢复密钥           |
| stale result    | 较早请求晚于新请求返回的过期结果，不能覆盖当前页面状态             |
| protected route | 需要当前认证会话才能进入的路由，不等于后端授权已经完成             |

同一文件无需重复解释同一术语，但不能只写“见服务端”或“同上”。未知后端状态和错误码必须
在使用位置说明对界面的影响。

### 样式备注

- CSS/SCSS 不逐属性翻译。复杂布局按页面区块写中文备注，说明网格、固定尺寸、滚动容器、
  z-index、断点和内容溢出的设计原因。
- 为避免控件跳动而设置的 `minmax()`、`aspect-ratio`、最小高度或固定轨道必须说明它保护的
  动态内容场景。
- 覆盖 Ant Design 或跨状态选择器时，备注覆盖范围、不能使用全局选择器的原因和可能影响的
  交互状态。

### 测试备注

- 测试名称使用“场景 + 预期结果”，让维护者不读实现也能理解业务规则。
- 认证、竞态、路由门禁、敏感字段清理和 Electron 安全测试必须在 Arrange 前用一至三句中文
  说明保护的真实风险。
- Mock、fake timer 或伪造响应首次建立时说明替代哪个外部边界，以及本测试没有证明的真实
  浏览器、Electron、Server 或 Worker 集成能力。
- 关键的 `not.toHaveBeenCalled()` 必须能从测试名或备注看出失败后禁止发生的是提交、导航、
  状态覆盖、外部打开还是敏感值持久化。

## HTTP 与安全

- 页面、组件、Hook 和 Store 不直接调用 `fetch`、Axios、WebSocket、EventSource 或
  XMLHttpRequest，只调用 `api/` 导出的类型化函数。
- `api/` 不导入 Node、Electron、文件系统、后端实现、数据库 SDK 或模型 SDK。
- Access Token 仅保存在模块内存；Refresh Token 由后端通过 HttpOnly Cookie 管理。
- API Key 只在用户主动保存或轮换时随受认证的专用 HTTPS 配置请求发给后端；提交后清空表单值，不进入 Store、浏览器存储、URL、日志、Mock 快照或返回 DTO。
- 客户端不导入模型 SDK、不直接调用模型 Provider，也不暴露通用 Prompt 或模型代理界面。业务任务请求不得携带 API Key、临时 endpoint 或任意模型 ID，只引用后端固定角色配置。
- 模型配置读取与保存响应只能消费 endpoint、固定角色模型 ID、配置版本和 `keyConfigured` 等脱敏字段，不得声明或处理密钥、密文、nonce、认证标签和 Secret Manager 引用。
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

## AI 生成前自检

- [ ] 新增或实质性重写的源码具有中文文件头，能说明职责、调用链、数据流、副作用和不能
      删除的安全边界；已有文件的行为变化已同步更新相关备注。
- [ ] 导出的组件、Hook、Store、API、类型和复杂私有函数具有中文 JSDoc，参数来源、返回
      语义、错误状态和清理方式没有留给维护者猜测。
- [ ] 三阶段以上的页面、请求或保存流程具有中文步骤备注，失败后禁止发生的提交、导航、状态
      覆盖或敏感值持久化已经说明。
- [ ] DTO、ViewModel、认证、Mock、过期请求结果和 Electron 术语在当前模块首次出现时已有
      局部解释，不能只依赖 Server 代码或历史对话。
- [ ] `useEffect`、订阅、定时器、AbortController 和并发请求的创建、取消、清理与过期结果保护
      已写清楚。
- [ ] API 与 Mock 的备注没有形成第二套业务规则，也没有把 Mock 测试描述为真实 Server、
      Worker、数据库、模型或对象存储集成已通过。
- [ ] Electron 安全设置旁说明了信任边界；备注没有建议暴露通用 IPC、Node 能力或本机执行。
- [ ] 样式备注只解释复杂布局、稳定尺寸、响应式和可访问性原因，没有逐属性翻译 CSS。
- [ ] 备注没有“显然”“简单”“不用管”等含糊措辞，没有过时或超出证据的承诺，并与当前
      实现、API 契约和测试一致。

## 验证

- 客户端或桌面壳改动运行 `npm run gate:static`。
- 路由、响应式布局或完整用户流程改动运行 `npm run gate:project`。
