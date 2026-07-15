# 逐帧重绘与外部适配器契约

## 一、适用范围

当任务涉及 AI 逐帧重绘、ControlNet、Canny、Lineart、LoRA、图像生成 API、MCP、ExtractorSharp 包装器或其他外部服务时使用本契约。本契约只定义跨职业的执行和证据边界；具体资源、技能、阶段、主题和允许变化仍由职业 manifest、职业规则与主题规则决定。

不得另建与 `dnf-patch-maker` 重叠的职业或重绘 skill。外部服务只是可替换适配器，不是资源映射、客户端兼容或部署授权的事实源。

## 二、源帧冻结

生成前必须从经核验 inventory 建立逐帧输入表，每项至少记录：

- 技术资源 ID、内部 IMG 路径和帧索引；
- IMG 版本、handler、动作阶段与人物/特效/武器/Cut-in 分类；
- 源导出图相对路径、像素尺寸、SHA-256、alpha 状态和色彩模式；
- `Width`、`Height`、`CanvasWidth`、`CanvasHeight`、`X`、`Y`、Hidden/LINK、图集和纹理关系；
- 目标导入接口期望的位图尺寸与载荷类型。

源帧导出目录是只读证据。显示名映射未核验时，目录使用 manifest 的技术资源 ID，不使用中文技能名、翻译名或猜测的 NPK 名。导出 PNG 的编号必须与真实帧索引一一对应，不以文件自然排序推断帧序。

## 三、运行计划与确定性

每次生成使用新的 `runId` 和机器可读运行计划。计划至少包含：

1. 输入 inventory 路径、长度和 SHA-256。
2. 目标帧白名单、排除帧及分组 `groupId`。
3. 模型名称、版本或哈希；LoRA/ControlNet 等适配器名称、版本或哈希。
4. 采样器、调度器、步数、CFG、降噪强度、输入/输出尺寸和批次参数。
5. Prompt、Negative Prompt 及其 SHA-256；逐技能 Prompt 仍受显示名映射门禁约束。
6. 全量任务的 Prompt 包绑定；包括职业 `prompts/README.md`、主题 `AGENTS.md` 路径、主题 `prompts/README.md`、每个已核验技能的职业 Prompt 路径、主题 Prompt 路径、三类输入的长度、SHA-256、合成文本哈希、适用资源/帧白名单和 UI 帧位置尺寸严格保持策略。
7. 单技能试制或用户点名逐技能 Prompt 时的局部绑定；包括主题 `AGENTS.md` 路径、职业 Prompt 路径、主题 Prompt 路径、三类输入的长度、SHA-256、合成文本哈希、优先级 `1`、适用资源/帧白名单和 UI 帧位置尺寸严格保持策略。该绑定不能替代全量 Prompt 包。
8. seed 策略以及每帧实际 seed。重试必须产生新 attempt 记录，不能覆盖失败结果。
9. 外部入口身份、版本、命令或 URL 的非敏感标识、超时和网络需求。
10. 原始生成目录、Aseprite 分层工程目录、运行帧目录和报告目录。

同一动作组默认固定模型、适配器、采样器、分辨率、控制参数和 Prompt 哈希。允许逐帧改变的字段必须在计划中列明。全量动作组必须先加载职业 Prompt 的动作骨架，再追加主题 `AGENTS.md` 共同风格和主题逐技能增量；只使用主题 Prompt 不足以证明动作阶段、轮廓、锚点和命中构图正确。用户点名的逐技能 Prompt 必须与主题 `AGENTS.md` 和同名职业 Prompt 绑定后，只在该技能资源/帧白名单内作为最高优先级输入贯穿 generated、edited、runtime 和 final 证据。共享 seed 可以作为时序一致性策略，但不是硬编码要求，也不能证明没有闪烁；确定性要求的是每帧实际参数可复现。

ControlNet、Canny、Lineart 或 LoRA 均为可选实现。只有来源、授权和模型身份可追踪，且不会越过人物/特效/Cut-in 边界时才可使用。不得把特定模型、端口、工作流或本机路径写成项目通用必需项。

## 四、目录隔离与 Aseprite 适配

仅在对应工作流真实使用时建立以下分层，目录名可由主题规则进一步约束：

```text
frames/source/<resource-id>/
frames/generated/<run-id>/<resource-id>/
frames/edited/<run-id>/<resource-id>/
frames/runtime/<run-id>/<resource-id>/
validation/<run-id>/redraw/
```

- `source`：从只读 NPK 导出的不可变证据。
- `generated`：外部生成服务的原始结果，不得直接回灌。
- `edited`：Aseprite 分层 `.aseprite` 工程与人工精修结果。
- `runtime`：按目标 handler 导入契约导出的最终 PNG 或纹理输入。
- `validation`：运行计划、逐帧记录、哈希、异常和时序验收。

外部生成不得覆盖任何已有文件。每次 attempt 使用新路径。Aseprite 适配必须恢复源帧所需的尺寸、Canvas/偏移语义、alpha、边缘和构图；不能统一采用 `256x256`、`512x512`、`1024x1024`、透明背景、居中或无人物。mipmap、Sprite/Texture 类型和压缩方式由源 IMG 与目标 handler 决定，不得统一关闭或转换。

Aseprite 使用以下活动门禁：

- 授权二进制只导入被忽略的 `tools/bin/aseprite/<version-hash-slot>/`，不提交、不分发；解析入口绑定 `current.json` 或显式路径中的版本、长度和 SHA-256。
- `--version` 不构成脚本兼容证明。任何活动 Lua 在写输出前必须通过 `tools/Test-DnfAsepriteApi.lua` 的真实 API 探针；使用 `Image.context` 的流程最低要求 API 30。
- 每个 runtime PNG 必须绑定唯一分层工程、源帧和 run plan 记录；工程从磁盘重开后再次导出或合成的像素必须与已记录 runtime 输出一致。
- Aseprite 只处理分层栅格和 PNG。DDS/BC 编码、Sprite/Texture 声明、IMG/NPK 写入与客户端兼容仍由 DirectXTex、目标版本 handler 和独立验证器证明。

## 五、外部适配器与 MCP 边界

项目不要求 MCP，也不提交个人级模型配置。需要外部适配器时遵守：

- Extractor 适配器默认只能读取已固定哈希的源包，并只能向当前主题工作区的新路径写入。
- 图像生成适配器只能读取运行计划列出的源图，只能写入 `generated/<run-id>`；不得获得 NPK 封装、游戏目录或部署能力。
- 网络默认关闭。确需本机或远端 API 时，当前任务必须明确需要，配置只保存非敏感端点标识；密钥和令牌留在用户环境，不写入仓库或报告。
- 固定包装器路径、命令参数、版本或 SHA-256、超时和退出码；保存请求摘要、响应摘要和生成文件哈希。
- 不信任工具自报成功。输出必须由工作区验证器重新读取，并与运行计划和源 inventory 对账。
- 通用 skill、manifest 和共享配置不得包含机器绝对路径、个人模型 `base_url` 或可写 `ImagePacks2` 的权限。

## 六、逐帧与时序门禁

回灌前至少验证：

1. 白名单中的每个帧键恰好有一个获准 runtime 输出；排除帧没有输出替换。
2. source、generated、edited、runtime 和最终 NPK 之间的路径、帧索引与哈希引用闭合。
3. runtime 位图满足目标 handler 的精确尺寸、alpha 和色彩模式要求。
4. 模型、适配器、Prompt、seed 或其他配置没有发生未声明漂移。
5. 全量任务的职业 Prompt 包、主题 `AGENTS.md`、主题 Prompt 包、每个已核验技能的合成文本哈希和帧白名单在 source/generated/edited/runtime/final 证据中一致；缺失职业 Prompt 包或主题 `AGENTS.md` 时不得宣称构图或主题共同风格完全正确。
6. 用户点名逐技能 Prompt 的主题 `AGENTS.md`、路径、长度、SHA-256、合成文本哈希和优先级在 source/generated/edited/runtime/final 证据中一致；缺失时不得宣称 Prompt 已用于定制技能图。
7. 帧数、顺序、阶段、锚点和源轮廓保持；相邻帧的可见边界、alpha 覆盖与视觉焦点没有无依据跳变。
8. 全帧黑、白、棋盘联系表通过；代表帧和生成服务预览不能代替全序列验收。
9. 最终 NPK 继续通过结构、格式、载荷、未授权 BGRA 和独立索引门禁。

自动相邻帧差异、轮廓或 alpha 统计只能标记异常，不能用一个通用阈值删除合法爆发、透明占位或阶段突变。人工验收必须结合源序列和职业/主题阶段规则。

## 七、发布证据

涉及逐帧重绘的发布报告和 final summary 还必须绑定：

- source inventory；
- redraw run plan 与逐帧 attempt summary；
- 模型、适配器与外部包装器 provenance；
- generated、edited、runtime 的逐帧哈希清单；
- 全量任务的职业 Prompt 包、主题 `AGENTS.md`、主题 Prompt 包、每个已核验技能的 Prompt 文件快照、合成文本哈希和每帧引用闭环；
- 用户点名逐技能 Prompt 的主题 `AGENTS.md`、路径、长度、SHA-256、合成文本哈希、优先级和每帧引用闭环；
- Aseprite 可执行文件、API 能力探针与适配说明；
- 分层工程重开、runtime PNG 和像素等价证据；
- 配置漂移、缺帧、重帧、错序和时序异常计数；
- 未完成的人工时序检查与目标客户端 A/B 项。

可读 changelog 只能复述这些机器证据，不能代替 manifest、运行计划或发布报告。

## 八、明确禁止

- 根据职业名或技能名猜测 NPK、IMG 或帧目录。
- 把同一 seed、LoRA 或 ControlNet 当作覆盖率或无闪烁证明。
- 全量生成时只喂主题 `prompts/`，却宣称动作阶段、轮廓、锚点和命中构图已完全正确。
- 把纯 DDS endpoint 调色、色板映射或构建脚本引用当作用户点名 Prompt 已驱动模型与 Aseprite 定制图像的证明。
- 让生成服务直接修改 NPK、覆盖唯一源帧或写入 `ImagePacks2`。
- 统一强制方形尺寸、透明背景、无人物、关闭 mipmap、ARGB 或 DXT 转换。
- 随机化、伪造或回填时间戳、签名、来源或其他元数据以规避扫描或检测。
- 把封装、压缩、加密或文件名前缀描述成客户端优先级、检测规避或账号安全保证。
