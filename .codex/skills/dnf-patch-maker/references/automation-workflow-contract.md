# 自动化工作流契约

## 一、适用范围

本契约约束仓库内由 JSON 工作流组织的离线 NPK/IMG 构建、验证、人工审核和发布闭环。它只编排已经存在且经项目门禁约束的脚本，不替代 IMG handler、DirectXTex、Aseprite、独立解析器、manifest、职业规则或主题规则。

工作流默认不联网、不部署、不写 `ImagePacks2`、不操作 DNF 进程。即使用户授权联网，也只能运行注册表中声明 `explicit-authorization-required` 的固定适配器；当前正式活动工作流未注册任何联网适配器。部署必须使用独立流程和当前请求的明确授权，不能加入离线发布 DAG。

## 二、事实源和入口

每个活动工作流必须同时具备：

1. 职业 manifest 中的工作流注册记录。
2. 主题目录内的版本化 workflow JSON。
3. `tools/workflow/adapter-registry.json` 中的固定适配器白名单。
4. `tools/workflow/schemas/workflow.schema.json` 和 `step-result.schema.json` 的机器契约。
5. `tools/Test-DnfWorkflow.ps1` 静态入口和 `tools/Invoke-DnfWorkflow.ps1` 执行入口。

manifest 注册的 `workflowId` 必须与 workflow JSON 一致。项目总门禁必须静态验证所有注册工作流；没有注册工作流的活动迁移不得进入自动发布链。

## 三、静态验证

不带 `-Execute` 调用执行入口时只做静态验证，不创建 Run 目录，不调用任何适配器。静态验证至少拒绝：

- 重复步骤、缺失依赖、自依赖和 DAG 环。
- 未注册适配器、错误 PowerShell 宿主、模式不匹配和未授权网络策略。
- 非白名单参数、绝对路径、路径逃逸和仓库外路径。
- 写参数未与步骤 `outputs` 精确绑定。
- `create-new` 输出落在 Run 目录之外。
- 未显式列入 `allowedAtomicReplacePaths` 的 `atomic-replace`。
- 少于两个成功谓词，或仅依赖 `status` 的步骤。
- 未绑定 workflow、registry、runner、脚本、参数和输入输出快照的恢复策略。

静态通过只表示声明结构安全，不表示 Aseprite、来源、活动证据、构建或发布已经通过。

## 四、执行和写入边界

执行必须显式提供 `-Execute` 和新的 `RunId`。非恢复执行拒绝任何已存在 Run 目录。所有普通输出使用 `create-new`，只能写到 `{{runDirectory}}` 下的新路径。

职业 manifest 是正式活动 DAG 唯一允许的 `atomic-replace` 路径。发布元数据生成器必须先生成新的 release 报告和 manifest 临时文件，再提交两者并立即运行发布闭环；闭环失败时恢复 manifest 原字节、删除 release，并清理临时与备份文件。

适配器只能从固定注册表解析脚本、PowerShell 位数、模式、网络策略、参数白名单、路径参数和写路径参数。workflow JSON 不能指定任意脚本、命令行或宿主。

## 五、成功语义

退出码为零或 `status=passed` 不能单独证明步骤成功。每步至少声明两个结构化谓词，并至少一个谓词检查状态字段之外的事实，例如 readiness、数量、覆盖状态、独立索引、人工审核绑定、部署 false 或闭环状态。

适配器返回 JSON、成功谓词、输入快照、输出快照和治理哈希共同形成正式步骤结果。失败步骤只写带时间戳的 attempt 证据，不写正式 `.result.json`，避免恢复器误把失败结果当作通过。

## 六、暂停、人工审核和恢复

最终验证通过后，模板生成器创建不可覆盖的 `manual-review-template.json`。模板保持 `pending-human-review` 和 `approved=false`。审核人必须逐张检查 final summary 绑定的全部黑、白、棋盘联系表，再把模板另存为同一 Run 目录下的 `manual-review.json`，填写：

- `status=passed`、`approved=true` 和 UTC `approvedAtUtc`。
- 非空 `reviewedBy`。
- `reviewedAllContactSheets=true`。
- 五类 findings 均为零。
- `targetClientCompatibilityProven=false`。
- deployment 四项均为 false。

不得修改原模板或 final summary。人工审核门禁同时验证摘要哈希、全部联系表路径/长度/哈希、背景集合、时效和部署状态。

恢复必须同时使用原 `RunId`、`-Execute` 和 `-Resume`。只复用满足以下条件的正式通过步骤：

- workflow、registry、runner、适配器脚本和参数 SHA-256 不变。
- 输入和输出快照仍匹配；原子替换步骤以当前输出快照为准，不要求旧输入字节仍存在。
- 所有成功谓词通过。
- 人工审批仍在时效内。

任一治理绑定或普通输入/输出漂移时拒绝恢复，必须创建新 Run。失败步骤没有正式结果，可在同一 Run 中重试，但参数证据必须不变。已完成 Run 的恢复只返回原通过摘要，不重复执行步骤。

## 七、覆盖状态机

资源计划、聚合和 final summary 始终保持 `fullSkillCoverageProven=false`。final summary 只能声明“允许生成发布元数据”，不能自行修改 manifest 或 release。

人工审核通过后，发布元数据生成器才可原子更新 manifest/release，使当前 manifest 范围的离线覆盖转为 true。随后必须运行发布闭环和项目总门禁。目标客户端兼容、加载优先级和 A/B 仍为 false/待验。

合法活动状态只有：

- `blocked-pre-aggregation`：manifest 和活动迁移 coverage 均为 false，没有 `fullSkillRelease`。
- `offline-release-closed-client-pending`：发布闭环已通过，manifest 和活动迁移 coverage 为 true，且绑定 final summary、manual review、release 和 `fullSkillRelease`。

资源计划本身即使在闭环后也保持验证起始状态 false。

## 八、遗留隔离

没有职业规则、manifest、来源 inventory 和验证证据的顶层 NPK 只能登记到 `docs/legacy-quarantine.json`。隔离清单必须冻结相对路径、大小、UTC 修改时间和 SHA-256，并保持构建、发布、部署、资源映射和提升资格全部为 false。

项目总门禁拒绝未分类顶层目录、未登记的隔离文件和隔离内容漂移。隔离文件名不能证明职业、资源、来源、安全或可发布性。提升必须建立完整职业工程和新版本产物，不能直接修改隔离状态。

## 九、必跑门禁

修改控制面后至少运行：

1. `tools/Test-DnfPowerShellSource.ps1`。
2. `tools/Test-DnfWorkflow.ps1`。
3. `tools/Test-DnfWorkflowFixtures.ps1`。
4. `tools/Test-DnfReleaseMetadataRollbackFixture.ps1`。
5. 历史发布完整性门禁。
6. `tools/Test-DnfProjectGate.ps1`。
7. `git diff --check`。

活动工作流的真实执行还必须现场通过工具链、迁移 readiness、聚合、最终验证、全联系表人工审核、发布闭环和项目总门禁。任何 blocker 都必须中止，不得通过修改期望哈希、伪造审核或沿用旧 Run 证据绕过。
