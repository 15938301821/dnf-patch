# Vergil（维吉尔）暗蓝幻影主题

## 当前活动状态

活动图像编辑契约已迁移到项目本地 Aseprite。当前机器尚未导入合法 Aseprite，帧 3–26 的 24 个分层工程、24 个 runtime PNG、新 Cut-in NPK、活动聚合包和新 final summary 均未生成，因此活动状态为门禁阻断，`fullSkillCoverageProven=false`。

DNF 源通过仓库根的忽略型本地配置解析，官方 `ImagePacks2` 始终只读。ExtractorSharp 与 DirectXTex 已使用项目本地入口；Aseprite 必须由用户从工作区外导入授权副本，项目不提交或分发其二进制。

## 历史 v1 发布

旧契约下的 manifest-scope v1 定制 NPK 已完成当时的离线发布门禁，历史状态为 `offline-validated-client-pending`、历史 `fullSkillCoverageProven=true`：

    npk\full-skill-v1\weaponmaster-vergil-dark-blue-manifest-scope-v1.NPK

- 大小：`35,037,857` 字节。
- SHA-256：`531DBE6E9E2261531C71293EC7223DE36B57D02948D79831190D4C68FFF247D7`。
- 发布报告：`validation\full-skill-v1\release.json`。
- 最终验证摘要：`validation\full-skill-v1\final-v3\final-validation-summary.json`。
- package summary：`validation\full-skill-v1\package-v1\package-summary-v1.json`。

这里的历史“完整覆盖”严格限定为旧 final summary 当时证明的男鬼剑剑魂视觉资源范围：28 个技术根、31 个显式选择组件、417 个组件 IMG，以及唯一获准的 `cutin_weaponmaster_neo.img`，最终共 418 个 IMG、3822 帧。它不把零匹配 Replay 名称猜成资源别名，也不证明中文 Prompt 显示名逐项映射、客户端加载优先级或目标客户端兼容，更不能授权当前 Aseprite 契约下的新发布。

## 变化与保留

- 组件实际变化 3593 帧，三觉 Cut-in 实际变化 24 帧，最终实际变化 3617 帧。
- 显式保留 128 帧、构建后动态保留 74 帧、Cut-in 透明占位保留 3 帧，最终安全保留 205 帧。
- 74 个动态保留帧由 22 个近黑帧、16 个无可见颜色变化帧和 36 个暖色源保护帧组成；其压缩载荷、DDS 与 BGRA 哈希均与源一致。
- 6 个没有安全实际变化的整 IMG、共 19 帧不进入最终包；候选池总排除为 221 帧。
- `AshenFork`、`BackStepCutter`、`HitBack`、`ChargeBurst` 经当前男鬼剑资源审计没有独立视觉根，不猜别名。
- `atultimateblade`、`atillusionslash`、`tripleslashbs` 因职业域或归属证据不足而排除。

共同色板仍为 `#0A1633`、`#1A8FFF`、`#00D4FF`、`#FFFFFF`。三觉 Cut-in 只聚合 `sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img`；`#3-26` 为变化帧，`#0-2` 为 1x1 透明占位，原 Cut-in 包另外 25 个 IMG 不进入最终定制 NPK。

## Aseprite 活动链

从工作区外导入合法 Aseprite，并运行版本、SHA-256 与真实 API 30 能力门禁：

    & '.\tools\Import-DnfAseprite.ps1' -SourceDirectory '<合法 Aseprite 安装目录>'
    & '.\tools\Test-DnfLocalToolchain.ps1' -RequireAseprite

使用同一个 `RunId` 渲染并构建 Cut-in；两个入口均拒绝覆盖已有路径：

    $runId = 'cutin-weaponmaster-neo-aseprite-v1'
    & '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\tools\Render-CutinWeaponmasterNeoVergil.ps1' -RunId $runId
    & '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\tools\Build-VergilCutinWeaponmasterNeo.ps1' -RunId $runId

渲染阶段输出 `frames\edited\<RunId>\aseprite`、`frames\runtime\<RunId>\png` 和 `validation\<RunId>\render-summary.json`。构建阶段只接受该摘要绑定的 runtime PNG，并输出 `npk\<RunId>` 与 `validation\build-<RunId>`。Aseprite 不编码 DDS/BC；BC3、Ver5 和 NPK 门禁仍由 DirectXTex、实际 handler、texdiag 与独立索引完成。

当前活动资源计划为 `configs\full-skill-v1\resource-plan-v4.json`。它继承 31 个历史组件证据，但停用历史 Cut-in v2 复用项，并在 Aseprite 与新 Cut-in 证据齐全前保持阻断。活动计划门禁：

    & '.\tools\Test-VergilAsepriteMigrationPlan.ps1' -ResourcePlanPath '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\configs\full-skill-v1\resource-plan-v4.json'

只有计划返回 `ReadyForAggregation=true` 后，才可在新的版本化路径聚合 31 个组件与新 Cut-in，并使用新的活动最终验证入口写入新的空目录。不得覆盖历史 v1 package、final 或 release 证据。

## 正式自动化工作流

活动链已注册为 `weaponmaster.vergil.aseprite-full-skill-v1`，声明文件位于 `workflows\aseprite-full-skill-v1.json`。它按固定顺序执行 PowerShell 源码门禁、本地工具链、迁移 readiness、32 源聚合、最终验证、人工审核模板、人工审核门禁、原子发布元数据、发布闭环和项目总门禁。

默认入口只做静态验证，不创建 Run 目录，也不运行 Aseprite、构建或发布：

    & '.\tools\Invoke-DnfWorkflow.ps1' -WorkflowPath '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\workflows\aseprite-full-skill-v1.json'

真实执行必须提供新的 `RunId` 和显式执行开关：

    $runId = 'weaponmaster-vergil-aseprite-20260714-v1'
    & '.\tools\Invoke-DnfWorkflow.ps1' -WorkflowPath '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\workflows\aseprite-full-skill-v1.json' -RunId $runId -Execute

最终验证通过后，工作流生成不可覆盖的 `manual-review-template.json`，随后因缺少 `manual-review.json` 暂停。审核人必须逐张检查该 Run 绑定的全部黑、白、棋盘联系表，把模板另存为 `manual-review.json`，填写审核人、UTC 审核时间、通过状态，并确保五类 findings 均为零。不得修改模板、final summary 或联系表。

完成审核后使用同一 `RunId` 恢复：

    & '.\tools\Invoke-DnfWorkflow.ps1' -WorkflowPath '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\workflows\aseprite-full-skill-v1.json' -RunId $runId -Execute -Resume

恢复要求 workflow、适配器注册表、runner、适配器脚本、参数和已有输入输出证据均未漂移。发布元数据步骤会生成 transaction receipt；release/receipt 仅在同一 Run 恢复时用 `resume-reconcile` 对账既有文件，manifest 提交受命名 Mutex 和 manifest-before CAS 保护。任一绑定变化时必须新建 Run，不能只改哈希或报告。该 DAG 永远禁止联网、部署、`ImagePacks2` 写入和 DNF 进程操作。

当前 v3 基线已按原迁移证据要求的长度 `383297` 和 SHA-256 `C9E65A869F21497E293976A113193550E297CCCC4D1853103E502A2232315EB8` 恢复。活动仍受 Aseprite 未导入、24 帧活动工程/runtime、组件现场复核、新 Cut-in 构建与最终验证等真实 blocker 约束，因此仍不得执行聚合或宣称当前契约已发布。

## 历史验证

历史 v1 已通过以下门禁：

- 独立 PowerShell/.NET NPK 索引：418 条目、418 唯一路径、头部 SHA-256 与 IMG magic 全部有效。
- package summary、最终 NPK 与 32 个组件来源逐 IMG payload 长度和 SHA-256 一致。
- 411 个 Ver5 IMG 与 7 个 Ver2 IMG 全部解析；3822 个非 LINK 帧全部解码，LINK=0、Hidden=0。
- 最终格式为 1850 帧 DXT1、1930 帧 DXT5、10 帧 ARGB1555、32 帧 ARGB8888。
- 生成 15 张覆盖全帧的黑、白、棋盘联系表；已人工抽查 `frames-0001.png`、`frames-0008.png`、`frames-0015.png`，未见空白页、意外整画布黑帧或布局异常。
- Cut-in 目标联系表未见参考图水印，源几何、Canvas、偏移和 3 个透明占位保持。

旧 final summary、package、release 和资源计划保持不可变。当前总门禁只校验这些历史文件及产物的引用完整性，不把旧根规则哈希或旧 Photoshop Cut-in 证据提升为当前 Aseprite 契约。

## 部署与回滚

本次完整产物未部署，未写入 `ImagePacks2`，也未检查、启动、结束或监控 DNF 进程。文件名只用于人工识别，不能证明客户端优先加载。

后续只有在用户明确授权部署并确认目标路径后，才可把部署作为独立步骤执行。由于当前没有部署，本次不产生游戏目录备份；若以后把该独立定制 NPK 写入游戏目录，回滚应先核对路径和 SHA-256，再只移除该独立定制文件，不改动官方 NPK。

目标客户端 A/B、加载顺序、兼容性和账号风险仍待用户实机确认，离线验证不对此作保证。

## 历史产物

- `npk\progress-v1\!weaponmaster_vergil_darkblue_progress_v1.NPK` 是历史进度预览包，只有 9 个 IMG、67 帧，不是本次完整产物；其历史部署记录见 `validation\progress-v1\release.json`。
- `npk\cutin-weaponmaster-neo-v2\sprite_character_swordman_effect_cutin.NPK` 是 Cut-in v2 历史完整替换组件；本次最终定制 NPK 只复用其中一个目标 IMG payload。
- `npk\vergil-momentaryslash-pilot-v1.NPK` 是早期 Ver5 DXT5 调色链路试制，保留作不可变历史证据。
