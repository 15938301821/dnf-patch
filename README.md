# DNF Patch Studio

Electron 控制面通过 OpenAI SDK 调用固定的三模型角色。模型只能生成受契约约束的规划与参考素材；网络必须由当前 Run 显式授权，部署始终关闭。

## 本地模型配置

应用只从进程环境读取配置，不读取或提交仓库内凭据文件。

| 环境变量                       | 必需                 | 说明                                                                              |
| ------------------------------ | -------------------- | --------------------------------------------------------------------------------- |
| `OPENAI_API_KEY`               | OpenAI provider 必需 | 只在本机环境配置；不得写入源码、日志、测试、构建产物或 Run 证据。                 |
| `OPENAI_BASE_URL`              | 可选                 | 默认 `https://api.openai.com/v1`。兼容网关必须使用 HTTPS，并显式包含 `/v1` 路径。 |
| `DNF_PATCH_ORCHESTRATOR_MODEL` | 可选                 | 调度模型覆盖；默认 `gpt-5.6-sol`。                                                |
| `DNF_PATCH_ENGINEER_MODEL`     | 可选                 | 工程模型覆盖；默认 `gpt-5.5`。                                                    |
| `DNF_PATCH_IMAGE_MODEL`        | 可选                 | 图像模型覆盖；默认 `gpt-image-2`。                                                |

自定义端点不得包含用户名、密码、查询参数或 URL 片段。应用启动时只做本地格式检查，不会隐式联网；端点可达性和模型能力只在明确授权联网的 Run 中验证。

第三方兼容网关可能忽略 `store: false`、不支持 Responses JSON Schema 或不支持图像生成参数。模型列表中出现某个模型 ID 不能单独证明接口可用，正式生成仍以每次调用的模型证据为准。

## 客户端架构

```text
DnfPatch/
├─ electron/
│  ├─ main.ts                 # Electron 主进程真实入口
│  ├─ preload.ts              # 沙箱 preload 与安全 IPC
│  └─ utils/spawn-server.ts   # 显式授权的固定后端进程入口
├─ renderer/
│  ├─ index.html
│  └─ src/
│     ├─ pages/               # Dashboard、Project Setup、Monitor、Settings
│     ├─ components/          # 可复用视图组件
│     ├─ hooks/               # 本地 Run 与服务连接状态
│     ├─ stores/              # 页面导航状态
│     ├─ types/               # Renderer 展示类型
│     ├─ utils/               # 状态映射和格式化
│     └─ api/                 # preload API 的唯一 Renderer 访问层
├─ server/
│  ├─ api/                    # 独立后端 REST/Socket.IO 客户端与 IPC 映射
│  ├─ cli/                    # 与 Electron 共用 PatchPipeline 的命令入口
│  ├─ shared/                 # Electron、Renderer、CLI 共用的 Zod 契约
│  ├─ pipeline/               # 本地可审计流水线阶段
│  ├─ security/               # 凭据与边界校验
│  └─ *.ts                    # Run、模型、工具和封装核心
├─ jobs/                      # 职业与主题事实源；显示身份不含 jobs 前缀
├─ resources/                 # 只读打包资源边界
└─ userData/
   └─ runs/                   # 新 Run 的本地可写证据目录
```

仓库根同时是 Electron 包根与 DNF 事实源根。职业物理路径固定为 `jobs/<职业>`，但桌面显示值、API、manifest 与 BPK 继续只使用职业名。项目脚本、测试和构建配置位于运行时层之外，只负责开发门禁，不承载第二套业务实现。旧 `apps/desktop`、`desktop`、根级职业目录、`src`、顶层 `shared`/`cli`、`server/server` 与 `.runs` 兼容路径由静态结构门禁明确拒绝。

`renderer` 不直接使用 Node、文件系统、`fetch`、Socket.IO、数据库或服务令牌。主进程服务不可用时，本地 `PatchPipeline`、Mock 规划和只读门禁继续工作；远端服务状态不能提升部署、全技能覆盖或客户端兼容结论。

## 后端服务连接

| 环境变量                        | 默认值                      | 说明                                                                   |
| ------------------------------- | --------------------------- | ---------------------------------------------------------------------- |
| `DNF_PATCH_SERVER_URL`          | `http://127.0.0.1:56789/v1` | 非回环地址必须 HTTPS，且必须包含版本化 `/v1`。                         |
| `DNF_PATCH_SERVER_CLIENT_TOKEN` | 无                          | 只由 Electron 主进程读取；应与服务端 `CLIENT_SHARED_TOKEN` 一致。      |
| `DNF_PATCH_SERVER_AUTOSTART`    | `false`                     | 显式设为 `true` 时只启动固定的同级后端构建入口，不接受 renderer 参数。 |
| `DNF_PATCH_SERVER_ENTRY_SHA256` | 无                          | 自动启动时必需，绑定后端 `dist/main.js` 的实际 SHA-256。               |

服务端 REST 与 Socket.IO 连接由主进程管理。Renderer 只能读取裁剪后的端点身份、健康状态和项目元数据，看不到完整认证头、模型密钥或数据库连接串。

## 安全门禁

- `npm run check:credentials`：扫描受管源码，不回显匹配到的凭据内容。
- `npm run build`：构建前扫描源码，构建后扫描 Electron 生产输出。
- `npm run gate:static`：执行凭据扫描、类型检查、ESLint、单元测试和静态契约校验。
- `npm run gate:project`：在静态门禁之后执行生产构建和 Electron E2E。

一旦密钥出现在聊天、日志、源码或构建产物中，应立即在服务商后台撤销并创建新密钥；仅从本地文件删除旧值不能恢复其安全性。
