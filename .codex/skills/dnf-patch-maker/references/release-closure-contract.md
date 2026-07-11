# 发布闭环与 Windows PowerShell 5 契约

## 一、两阶段发布状态机

1. 盘点、资源计划和组件构建阶段保持 `fullSkillCoverageProven=false`。
2. 聚合到新的版本化 NPK 与 package summary；不覆盖基线或游戏目录。
3. 在不存在或确认为空的新验证目录运行最终验证，生成不可变 final summary、独立索引、全帧 inventory 和联系表。
4. 最终验证器只证明“允许生成发布元数据”，不得自行把 manifest 或 release 的覆盖状态改为 true。
5. 仅从通过的 final summary 更新职业 manifest 与主题 `release.json`，同时绑定资源计划、帧核算、产物、package、验证器和验证证据的路径、长度与 SHA-256。
6. 元数据更新后运行 `tools/Test-DnfReleaseClosure.ps1`。只有该门禁通过，`fullSkillCoverageProven=true` 才构成有效发布状态。
7. 最后更新 README，并运行 `tools/Test-DnfProjectGate.ps1`；README 不是事实源，不能反向授权发布。

最终验证与元数据闭环必须分开，避免 final summary 对随后生成的 manifest/release 形成自哈希循环。

## 二、验证目录与证据不变性

- 最终验证目录必须使用新版本名，且运行前不存在或为空；不得在旧目录上覆盖或混入证据。
- final summary 生成后视为不可变。被其记录 SHA-256 的生成器、验证器、配置、源包或组件发生变化时，必须在新的验证目录重跑，不能只改报告哈希。
- 旧 final summary 和最后一个已知正确产物保留作基线；README 只指向当前闭环通过的版本。
- 联系表必须全部保留，人工抽查结果记录在 manifest/release；抽查不能替代全帧解码与机器门禁。

## 三、路径、快照与返回类型

- 相对路径始终以“拥有该路径字段的 JSON 文件所在目录”为基准解析；禁止在 manifest、release 和 final summary 之间混用基准目录。
- 快照至少包含 `path`、`length`、`sha256`。缺少长度或哈希、文件不存在或现场值不符均为硬失败。
- 快照验证函数必须返回类型稳定的结构对象，例如 `{ path, length, sha256 }`；若只返回字符串，变量名必须以 `Path` 结尾，调用方不得读取不存在的属性。
- 多字段门禁拆成独立布尔或逐项断言，并在错误中输出字段名、实际值与期望值；不得用一个无诊断的长复合表达式掩盖失败条件。
- manifest、release、final summary 必须解析到同一个产物、package、资源计划、独立索引和全帧 inventory；工具哈希也必须三方一致。

## 四、Windows PowerShell 5 源码约束

- 只含 ASCII 的 `.ps1/.psm1/.psd1` 使用无 BOM ASCII/UTF-8；包含任何非 ASCII 源码字面量时必须使用 UTF-8 BOM。
- 设置 `$OutputEncoding` 或 `[Console]::OutputEncoding` 只影响输出，不会修复 Windows PowerShell 5 对无 BOM 源码的解码。
- 尽量从 UTF-8 JSON/manifest 读取本地化路径与名称；能用稳定文件名或 ID 比较时，不在脚本源码嵌入中文路径常量。
- 在对象初始化前先计算条件值，并把泛型 List 显式 `ToArray()`；避免 Windows PowerShell 5 动态绑定产生 `Argument types do not match`。
- 修改 PowerShell 文件后必须运行 `tools/Test-DnfPowerShellSource.ps1`，同时检查编码和 Windows PowerShell 5 语法。

## 五、固定闭环门禁

```powershell
& .\tools\Test-DnfPowerShellSource.ps1 -Path . -AsJson
& .\tools\Test-DnfPromptTree.ps1 -ProfessionPath <职业目录> -ThemePath <主题目录> -RepoRoot .
& .\tools\Test-DnfReleaseClosure.ps1 -ProfessionManifestPath <职业 manifest.json> -AsJson
& .\tools\Test-DnfProjectGate.ps1 -AsJson
```

`Test-DnfReleaseClosure.ps1` 是只读后置门禁：复核 3 份发布元数据、所有引用快照、当前工具/来源 provenance，并实时重跑资源计划验证器与独立 NPK 索引。`Test-DnfProjectGate.ps1` 再统一检查项目 skills、所有 JSON、PowerShell 源码、职业/主题 Prompt 树、已有完整发布闭环和 `git diff --check`。

任何一步失败时保持“发布被门禁阻断”，不得降级为警告、不得部署，也不得向用户宣称完整覆盖。
