# 发布闭环与 Windows PowerShell 5 契约

## 一、两阶段发布状态机

1. 盘点、资源计划和组件构建阶段保持 `fullSkillCoverageProven=false`。
2. 聚合到新的版本化 NPK 与 package summary；不覆盖基线或游戏目录。
3. 在不存在或确认为空的新验证目录运行最终验证，生成不可变 final summary、独立索引、全帧 inventory 和联系表。
4. 最终验证器只证明“允许生成人工审核模板”，不得自行把 manifest 或 release 的覆盖状态改为 true。
5. 自动化创建不可覆盖的 pending 模板后暂停。审核人必须另存 `manual-review.json`，逐张审核该 Run 的全部联系表并填写非空身份、UTC 时间和显式零 finding；自动化不得生成通过状态。
6. 人工审核通过后，只能以同一 `RunId` 恢复。审核时效、final summary 和联系表快照必须在恢复及发布前重新验证，不能只信旧步骤结果中的通过布尔值。
7. 仅从通过的 final summary 和人工审核原子生成职业 manifest 与主题 `release.json`，同时绑定资源计划、帧核算、产物、package、验证器和验证证据的路径、长度与 SHA-256。
8. 元数据更新后运行 `tools/Test-DnfReleaseClosure.ps1`。只有该门禁通过，`fullSkillCoverageProven=true` 才构成有效发布状态。
9. 最后更新 README，并运行 `tools/Test-DnfProjectGate.ps1`；README 不是事实源，不能反向授权发布。

最终验证与元数据闭环必须分开，避免 final summary 对随后生成的 manifest/release 形成自哈希循环。

## 二、声明式执行、暂停与恢复

- 职业 manifest 注册 workflow 后，以 JSON DAG、固定适配器注册表和 PowerShell runner 为唯一自动化控制面；不得绕过 DAG 手工串接发布写步骤。
- 默认调用只进行静态验证，不创建 Run。真实执行要求新的 3–64 字符小写 `RunId` 和显式 `-Execute`；部署、`ImagePacks2` 写入、进程操作与未授权网络始终禁止。
- workflow、registry、runner、适配器脚本、参数、输入和输出都纳入恢复哈希。任一现场快照漂移时拒绝复用并要求新 Run。
- 人工审核步骤是暂停点。恢复必须同时提供同一 `RunId`、`-Execute` 和 `-Resume`；已完成 Run 的同参数恢复只允许幂等返回，不得重写证据。
- 审核状态必须来自审核人另存的文件。`reviewedBy` 必须非空，`approvedAtUtc` 必须使用零偏移 UTC 且不超过 DAG 声明的时效；所有联系表必须逐项闭合，findings 必须为显式整数零，客户端兼容和部署状态必须保持 false。
- 恢复既复核审核文件哈希，也重新计算审核时效和步骤成功谓词；修改步骤结果中的 `passed=true` 不能提升 readiness。

## 三、验证目录与证据不变性

- 最终验证目录必须使用新版本名，且运行前不存在或为空；不得在旧目录上覆盖或混入证据。
- final summary 生成后视为不可变。被其记录 SHA-256 的生成器、验证器、配置、源包或组件发生变化时，必须在新的验证目录重跑，不能只改报告哈希。
- 旧 final summary 和最后一个已知正确产物保留作基线；README 只指向当前闭环通过的版本。
- 联系表必须全部保留，人工抽查结果记录在 manifest/release；抽查不能替代全帧解码与机器门禁。

## 四、路径、快照与返回类型

- 相对路径始终以“拥有该路径字段的 JSON 文件所在目录”为基准解析；禁止在 manifest、release 和 final summary 之间混用基准目录。
- 快照至少包含 `path`、`length`、`sha256`。缺少长度或哈希、文件不存在或现场值不符均为硬失败。
- 快照验证函数必须返回类型稳定的结构对象，例如 `{ path, length, sha256 }`；若只返回字符串，变量名必须以 `Path` 结尾，调用方不得读取不存在的属性。
- 多字段门禁拆成独立布尔或逐项断言，并在错误中输出字段名、实际值与期望值；不得用一个无诊断的长复合表达式掩盖失败条件。
- manifest、release、final summary 必须解析到同一个产物、package、资源计划、独立索引和全帧 inventory；工具哈希也必须三方一致。
- workflow 声明路径、适配器路径参数与运行证据必须在仓库及允许写根内，拒绝绝对路径、`..` 越界、未声明写输出和 reparse point 穿越。

## 五、发布元数据事务与回滚

- `release.json` 必须写入不存在的新路径；manifest 使用同目录临时文件和原子替换，禁止就地截断后写入。
- 发布脚本在提交前再次验证 final summary、人工审核、当前 manifest 起始状态和所有快照；提交后立即运行发布引用闭环。
- 后置闭环失败时必须删除新 release，并以原始备份字节恢复 manifest。正常回滚后不得残留临时文件或备份。
- 回滚动作本身失败时，必须继续尝试清理另一侧提交，保留仍存在的 manifest 备份并报告其精确路径；不得用原始门禁异常掩盖回滚失败，也不得宣称事务已恢复。
- 使用 `tools/Test-DnfReleaseMetadataRollbackFixture.ps1` 对失败注入路径验证 manifest 字节身份、release 删除和临时文件清理。

## 六、Windows PowerShell 5 源码约束

- 只含 ASCII 的 `.ps1/.psm1/.psd1` 使用无 BOM ASCII/UTF-8；包含任何非 ASCII 源码字面量时必须使用 UTF-8 BOM。
- 设置 `$OutputEncoding` 或 `[Console]::OutputEncoding` 只影响输出，不会修复 Windows PowerShell 5 对无 BOM 源码的解码。
- 尽量从 UTF-8 JSON/manifest 读取本地化路径与名称；能用稳定文件名或 ID 比较时，不在脚本源码嵌入中文路径常量。
- 在对象初始化前先计算条件值，并把泛型 List 显式 `ToArray()`；避免 Windows PowerShell 5 动态绑定产生 `Argument types do not match`。
- 修改 PowerShell 文件后必须运行 `tools/Test-DnfPowerShellSource.ps1`，同时检查编码和 Windows PowerShell 5 语法。

## 七、固定闭环门禁

```powershell
& .\tools\Test-DnfPowerShellSource.ps1 -Path . -AsJson
& .\tools\Test-DnfPromptTree.ps1 -ProfessionPath <职业目录> -ThemePath <主题目录> -RepoRoot .
& .\tools\Invoke-DnfWorkflow.ps1 -WorkflowPath <manifest 注册的 workflow JSON>
& .\tools\Test-DnfWorkflowFixtures.ps1 -RepoRoot . -AsJson
& .\tools\Test-DnfReleaseMetadataRollbackFixture.ps1 -RepoRoot . -AsJson
& .\tools\Test-DnfReleaseClosure.ps1 -ProfessionManifestPath <职业 manifest.json> -AsJson
& .\tools\Test-DnfProjectGate.ps1 -AsJson
```

`Invoke-DnfWorkflow.ps1` 的上述调用只做静态验证。`Test-DnfReleaseClosure.ps1` 是只读后置门禁：复核 3 份发布元数据、所有引用快照、当前工具/来源 provenance，并实时重跑资源计划验证器与独立 NPK 索引。`Test-DnfProjectGate.ps1` 再统一检查项目 skills、所有 JSON、PowerShell 源码、职业/主题 Prompt 树、控制面 fixtures、正式 workflow 静态状态、已有完整发布闭环和 `git diff --check`。

任何一步失败时保持“发布被门禁阻断”，不得降级为警告、不得部署，也不得向用户宣称完整覆盖。
