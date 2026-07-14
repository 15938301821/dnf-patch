# 项目工具中文索引

## 一、独立 NPK 索引检查

`tools/Test-DnfNpkIndex.ps1`

- 仅使用 PowerShell/.NET，不依赖 ExtractorSharp。
- 检查 NPK magic、entry count、路径解密/唯一性、头部 SHA-256、条目边界、IMG magic/version。
- 不能代替完整帧、纹理和像素验证。

## 二、全帧 inventory 与联系表

`tools/Export-DnfNpkValidation.ps1`

- 使用 ExtractorSharp 解码帧并导出 album/frame inventory。
- 记录 LINK、Hidden、几何、Texture、图集和旋转字段。
- 生成全帧黑/白/棋盘分页联系表。
- 当前 ExtractorSharp 使用 x86 zlib 时必须用 32 位 PowerShell。
- 与常见生成器共享 ExtractorSharp，不能作为独立解析路径。

## 三、选定帧像素检查

`tools/Test-DnfNpkPixels.ps1`

- 检查获准帧的透明、可见黑色和全画布不透明黑色。
- 必须结合源语义和基线；合法透明/黑色源帧不能因通用阈值被误判。

## 四、代表帧预览

`tools/Preview-ExtractorSharpNpk.ps1`

- 只生成有限代表预览。
- 不能证明全帧或全技能覆盖。

## 五、Prompt 树门禁

`tools/Test-DnfPromptTree.ps1`

- 统一调用项目现有 Prompt 契约验证器。
- 校验职业/主题索引、固定章节、同名关系、越界路径和 manifest JSON。
- Prompt 发生变化后运行；不建立资源映射或覆盖证明。

## 六、PowerShell 5 源码门禁

`tools/Test-DnfPowerShellSource.ps1`

- 解析所有 `.ps1/.psm1/.psd1`，拒绝语法错误、非法 UTF-8、非 ASCII 无 BOM 源码和 UTF-16/UTF-32。
- 用于防止 Windows PowerShell 5 把中文路径或字符串错误解码。

## 七、发布后引用闭环

`tools/Test-DnfReleaseClosure.ps1`

- 只读核对 manifest、`release.json`、final summary、资源计划、帧核算、产物、package、全帧证据和工具 provenance。
- 实时重跑 final summary 绑定的资源计划验证器和 `Test-DnfNpkIndex.ps1`；不重新编码、不写产物、不部署。
- 只在新的最终验证摘要已经通过、发布元数据已更新后运行。

## 八、声明式工作流、人工审核与事务发布

`tools/Invoke-DnfWorkflow.ps1`、`tools/workflow/DnfPatch.Workflow.psm1`

- 读取 manifest 注册的 JSON DAG，通过 `tools/workflow/adapter-registry.json` 固定 PowerShell 适配器、宿主、参数、网络策略和写路径参数。
- 默认只做静态验证；真实写步骤必须使用新的 `RunId` 和显式 `-Execute`。恢复必须使用同一 `RunId`、`-Execute -Resume`，并复核 workflow、registry、runner、适配器脚本、参数及输入输出哈希。
- 所有声明路径必须留在仓库和 workflow 允许写根内，拒绝绝对路径、越界、未绑定写输出和 reparse point 穿越。恢复时从保存的适配器原始结果重新计算成功谓词，并重新检查人工批准时效。
- `tools/workflow/schemas/workflow.schema.json` 与 `step-result.schema.json` 保存声明和结果结构；runtime 仍以模块中的逐字段门禁为执行事实源。

`tools/New-DnfFinalManualReviewTemplate.ps1`、`tools/Test-DnfFinalManualReview.ps1`

- 最终验证后只创建不可覆盖的 pending 模板；自动化不得生成通过状态或填写审核人。
- 审核人另存 `manual-review.json`，填写非空身份和 UTC 审核时间，检查该 Run 的全部联系表；所有 finding 必须是显式整数零，客户端兼容与四个部署字段必须为 false。
- 正式 workflow 的审核有效期由 DAG 固定；过期审核在首次执行、恢复和发布元数据生成时都必须重新拒绝。

`tools/New-DnfReleaseMetadata.ps1`

- 再次验证 final summary 与人工审核后，用新 release 临时文件和 manifest 原子替换提交发布元数据，随即运行发布闭环。
- 任一后置门禁失败时删除新 release 并按字节恢复旧 manifest；若回滚本身失败，保留 manifest 备份并以硬失败报告其路径。

`tools/Test-DnfWorkflowFixtures.ps1`、`tools/Test-DnfReleaseMetadataRollbackFixture.ps1`

- 前者覆盖 DAG、路径、写边界、成功谓词、人工审核和恢复安全；后者验证闭环失败后的 manifest 字节恢复、release 删除和临时文件清理。
- 两者均为隔离 fixture，不执行真实职业工作流、不联网、不部署。

## 九、项目总门禁

`tools/Test-DnfProjectGate.ps1`

- 检查项目 skills、全仓 JSON、PowerShell 5 源码、所有职业/主题 Prompt 树、已有完整发布闭环和 `git diff --check`。
- 同时运行声明式 workflow fixtures、发布元数据回滚 fixture、manifest 注册的正式 workflow 静态检查，以及活动/历史状态机和遗留隔离门禁。
- 作为 README 更新后的最后只读门禁，不代替职业/主题的二进制深度验证器。

## 十、AI 与外部适配器

- 项目没有通用必需的 SD API、ControlNet、LoRA、MCP 或固定端口；按任务读取 `references/frame-redraw-and-adapter-contract.md`。
- 外部生成服务只产出 `generated` 素材，不能直接回灌、封装或部署。Extractor 包装器默认只读官方源，写入范围限制在当前主题工作区的新路径。
- 使用前固定入口、参数、版本或 SHA-256、超时、网络需求和输出目录，并保存逐帧请求摘要与文件哈希；工具自报成功不能代替工作区验证。
- 个人模型端点、密钥、机器绝对路径和可写 `ImagePacks2` 的配置不进入仓库通用 skill 或共享配置。

带职业或主题名称的 builder/图像脚本属于领域工具，只能通过对应职业/主题规则发现，不能登记为通用默认链。

## 十一、项目本地 Aseprite

`tools/Import-DnfAseprite.ps1`

- 从用户提供的工作区外授权安装目录导入完整 Aseprite 运行目录到被忽略的版本/哈希槽位。
- 导入前后复核版本、SHA-256、签名策略和真实 API 能力；商业二进制不得提交或随项目分发。

`tools/Test-DnfAsepriteApi.lua` 与 `Test-DnfAsepriteApiCapability()`

- 实际执行 `Image.context`、路径绘制、裁切、缩放、图层、混合模式、工程/PNG 保存、重开和像素等价检查。
- 活动 Cut-in 要求 Aseprite API 30 或更高；仅有 `--version` 输出不能通过门禁。

`tools/Test-DnfLocalToolchain.ps1`

- 只读检查本地配置、只读 DNF 源、ExtractorSharp、DirectXTex、Aseprite 和系统前置条件。
- 不带 `-RequireAseprite` 时，尚未导入会明确报告 `partial-aseprite-not-imported`；活动栅格编辑和发布迁移必须使用 `-RequireAseprite`。

`tools/Export-SakuraPreview.ps1`

- 从冻结联系表经 Aseprite 批量导出新的版本化 PNG，并记录输入、输出、脚本、可执行文件和 API 能力 provenance。
- 只生成主题工作区预览，不构建 NPK、不部署，也不覆盖历史 Photoshop 预览。
