# Manifest 中文稳定结构契约

## 一、来源字段

每个源 NPK 至少记录：来源或客户端说明、精确路径、文件大小、修改时间、SHA-256、inventory 时间和工具版本。

## 二、资源字段

在最窄的已核验层级记录：

- 稳定职业技能或资源 ID；
- 仅在核验后记录的显示名；
- 源 NPK 与内部 IMG；
- IMG 版本和 handler；
- 动作阶段；
- 特效、人物、武器、Cut-in 或共享分类；
- include/exclude 与证据；
- 期望帧数和元数据；
- 源哈希或条目哈希。

## 三、覆盖状态

显式记录覆盖状态。只有技能专包、共享资源以及起手、循环、命中、爆发、收尾、常驻阶段均完成映射时，才允许把 `fullSkillCoverageProven` 设为 true。

## 四、允许变化

声明目标 NPK/IMG/帧、允许变化的元数据、像素规则、主题验收、不可变集合和排除集合。验证必须同时拒绝未声明变化与缺少的必需变化。

涉及逐帧重绘时，manifest 只保存技术资源与动作组的稳定映射、允许帧和导入契约；模型、seed、采样器、外部端点等单次运行参数写入版本化 redraw run plan，不把执行参数伪装成资源事实。

## 五、Prompt 路由

manifest 只记录职业 Prompt 索引、主题 Prompt 索引模式和合成顺序，不把 Prompt 文本复制成资源映射。

显示名映射状态必须逐资源显式记录。状态未核验时不得路由同名逐技能 Prompt，只能使用不依赖显示名的职业/主题共同规则。

## 六、完整发布状态

- 资源计划和最终验证开始时必须记录 `fullSkillCoverageProven=false`。
- final summary 通过后，manifest 的完整发布节点至少绑定 artifact、package summary、资源计划、构建后帧核算、独立索引、全帧 inventory、工具链、deployment 和待实机项。
- manifest 与主题 `release.json` 的每个文件引用使用所属 JSON 目录作为相对路径基准，并记录长度和 SHA-256。
- final summary 只授权元数据转换，不直接修改 manifest/release；元数据写入后必须通过 `tools/Test-DnfReleaseClosure.ps1`。
- 发布使用逐帧重绘时，完整发布节点还要绑定 source inventory、redraw run plan、逐帧 attempt summary、generated/edited/runtime 哈希清单和模型/适配器/包装器 provenance。
- README 只复述已闭环的机器可读事实，不参与覆盖状态判定。
