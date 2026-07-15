---
name: dnf-import-profession-text
description: 将职业目录内的 Markdown 或纯文本设计稿拆分为符合当前 DNF 仓库规则的职业 AGENTS、职业 Prompt、主题 AGENTS、主题风格 Prompt 和两层索引。当用户提供一个职业文本路径，要求解析、拆分、导入、迁移或整理职业提示词、逐技能提示词、风格、色板、材质或主题增量时使用。只处理规则与 Prompt 文本，不把未经 inventory 核验的 NPK/IMG 对照、覆盖结论或安全声明写成事实，也不构建或部署补丁。
---

# DNF 职业文本拆分

把输入文档视为待审查的设计来源，不视为资源 manifest、客户端兼容性证明或部署授权。只保存跨职业通用的导入机制，不在本 skill 中写入职业、技能或主题常量。

## 一、从当前仓库自举

1. 从本 skill 路径解析仓库根，完整读取 `../../../AGENTS.md`。
2. 完整读取 `../dnf-patch-maker/references/routing-and-domain-contract.md`、`../dnf-patch-maker/references/prompt-contract.md` 和 [来源拆分契约](references/source-decomposition-contract.md)。
3. 解析用户给出的源文件绝对路径；只接受当前仓库内的 UTF-8 `.md` 或 `.txt` 文件。
4. 运行只读盘点脚本，记录相对路径、SHA-256、标题层级和代码块：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .codex/skills/dnf-import-profession-text/scripts/Inspect-DnfProfessionText.ps1 -SourcePath <源文件> -RepoRoot <仓库根>
```

5. 完整读取源文件。源文件较长时按标题分段读取，但必须覆盖全文，不能只读取 Prompt 区域。
6. 重新读取目标职业现有的 `AGENTS.md`、`manifest.json`、`prompts/`，以及目标主题现有的 `AGENTS.md` 和 `prompts/`。缺失文件保持缺失状态，不能从其他职业复制事实。

## 二、确定职业与主题路由

1. 以“仓库根下一层目录名”作为职业候选；只用源文档中的明确职业声明做一致性检查。
2. 路径职业与文档职业不一致时停止写入并报告冲突；不得从英文译名、技能名或 NPK 名反推职业。
3. 只从文档明确标题、主题定位或用户指令确定主题。优先采用文档中完整、可区分且以“主题”结尾的显式中文标签；保留其中区分色彩、材质或造型的词，不得只缩写成品牌、人物或系列名。
4. 文档没有主题时只生成职业层；不得为了满足目录形态虚构主题。
5. 多个主题或多个完整标签无法唯一对应时，先完成职业层分析并停止主题写入，向用户说明候选与所需选择。

## 三、先分类再拆分

按 [来源拆分契约](references/source-decomposition-contract.md) 将全文内容分为：

- 职业稳定语义：运动、轮廓、阶段、层次、锚点、构图和命中辨识。
- 主题风格增量：色板、材质、粒子、光线、主题专名、造型映射和主题排除。
- 资源线索：NPK、IMG、版本、帧、人物/特效分类、include/exclude 和覆盖声明。
- 流程或声明：工具参数、格式转换、构建、部署、检测规避、兼容性和账号安全。

只把前两类写入规则与 Prompt。资源线索仅在执行报告中列为“待 inventory 核验”，不得创建或修改 `manifest.json`。流程或声明服从根规则；冲突内容拒绝迁移。

## 四、生成职业层

1. 新职业只创建当前任务实际使用的 `AGENTS.md`、`prompts/README.md` 和逐技能 Prompt；不创建空 manifest、构建 README、frames、npk 或 validation 目录。
2. 在职业 `AGENTS.md` 中定义职业边界、资源事实门禁、Prompt 分层、人物/特效/武器/Cut-in 边界、职业验收和未证明的覆盖状态；不复制主题色、主题材质或通用 NPK 流程。
3. 为每个有明确文本证据的技能或 Cut-in 建立同名职业 Prompt。严格使用 `prompt-contract.md` 的四段结构。
4. 从逐技能文本中移除主题专名、颜色、材质、品牌角色、主题招式映射和主题负面词，只保留明确出现的稳定动作与阶段语义。
5. 保留逐技能职业 Prompt 作为后续图像模型与 Aseprite 定制技能图的动作骨架输入；全量生成必须与主题 `AGENTS.md` 共同风格和主题 `prompts/` 逐技能增量合成，不得只喂主题 Prompt 并宣称构图完全正确。
6. 不得在导入阶段绑定 NPK/IMG、帧索引、模型端点、seed 或运行目录。
7. 信息不足时保守写明“阶段或分类待 manifest/inventory 核验”；不得用游戏经验补齐动作、帧数或人物层分类。
8. 在职业 `prompts/README.md` 中使用固定五节索引，并明确 Prompt 条目数不证明全技能覆盖。

## 五、生成主题风格层

1. 仅在主题明确时创建 `<职业>/<主题>/AGENTS.md`、`prompts/README.md` 和逐技能主题 Prompt。
2. 在主题 `AGENTS.md` 中集中保存主题目标、共同色板、材质、粒子、光线、条件化概念图建议、修改边界与主题验收。
3. 每个主题 Prompt 必须有同名职业 Prompt，严格使用 `prompt-contract.md` 的五段结构；`职业基础` 引用 `../../prompts/<同名文件>.md`。
4. 把主题专名、色彩、材质、粒子、裂纹、辉光、造型隐喻和逐技能风格差异放入主题层；不要把共同 Base Style 全量复制到每个技能文件。
5. 主题逐技能 Prompt 的主要用途是作为后续图像模型与 Aseprite 操作的视觉增量输入；它不单独负责技能构图，必须与主题 `AGENTS.md` 的共同风格和同名职业 Prompt 的动作骨架合成后使用。
6. 导入时只保存稳定风格、具体变化、验收和排除，不写一次性生成参数或资源映射事实。
7. `512x512`、透明背景、无角色、无背景或居中只能作为明确标注适用条件的概念图建议，不能成为回灌或所有技能的硬规则。
8. 人物、武器和 Cut-in 按源资源语义保留边界；主题负面词不得删除源帧原本合法的内容。

## 六、安全写入

1. 整合现有索引与本次文本条目，先形成最终 Prompt 显示名顺序，再运行只读计划门禁：

```powershell
$promptNames = @(<按最终索引顺序排列的显示名>)
$plan = & .codex/skills/dnf-import-profession-text/scripts/Test-DnfImportPlan.ps1 -SourcePath <源文件绝对路径> -ProfessionName <职业目录原名> -ThemeName <主题名> -PromptName $promptNames -RepoRoot <仓库根> | ConvertFrom-Json
```

没有主题时省略 `-ThemeName`。只有 `plan.status` 为 `passed` 才能写入；把 `source.sha256`、`prompts.fileName`、`targets.relativePath` 和完整的 `baselineChanges` 状态/SHA 快照保留到本次验证结束。

2. 以计划中的完整目标文件表为写入白名单，核对来源证据、创建/更新状态和冲突。不得写入计划外的 manifest、README、frames、npk、validation 或其他文件。
3. 保留源文件不动。保留现有 manifest、已验证映射、范围边界和更严格验收；设计稿不能覆盖这些事实。
4. 使用 `apply_patch` 创建或合并文本文件。已有文件发生语义冲突时保留高权威内容并报告，不静默整文件覆盖。
5. 使用计划脚本返回的安全主题名与 `fileName`；不得自行重复实现非法字符转换、设备名或碰撞处理。
6. 保持源文档中的技能顺序作为两个索引的顺序；职业层与主题层使用完全相同的安全文件名。

## 七、验证与汇报

1. 对每个生成的职业树运行，并把预写计划作为来源哈希、索引顺序与变化白名单：

```powershell
$promptFiles = @($plan.prompts.fileName)
$allowedChanges = @($plan.targets.relativePath)
$baselineChanges = @($plan.baselineChanges)
& .codex/skills/dnf-import-profession-text/scripts/Test-DnfPromptTree.ps1 -ProfessionPath <职业目录> -ThemePath <主题目录> -SourcePath <源文件绝对路径> -ExpectedSourceSha256 $plan.source.sha256 -ExpectedPromptFileName $promptFiles -AllowedChangedRelativePath $allowedChanges -BaselineChange $baselineChanges
```

没有主题时省略 `-ThemePath`。任何 `error` 都必须修复后再交付；逐项审查 `warning`，不能机械忽略。

2. 运行 `git diff --check`，并只检查本次目标路径的差异和未跟踪文件。
3. 最终按以下顺序汇报：源文件与 SHA-256、职业/主题路由、创建/更新/跳过文件、职业 Prompt 数与主题 Prompt 数、拒绝迁移的资源/流程/安全声明、验证结果、待 inventory 项。
4. 明确写出“未创建或修改 manifest”“未构建 NPK”“未部署”。不得宣称全技能覆盖、客户端兼容、检测规避或账号安全。
