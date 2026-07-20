# 女气功樱花主题补丁

## 当前状态

现有两个 NPK 和根目录 `樱花粉预览.png` 是旧契约下的历史产物，均保持不可变。活动图像编辑链已迁移为项目本地 Aseprite，但当前机器尚未导入合法 Aseprite，因此还没有新的 Aseprite 预览、分层工程或重绘 NPK。

活动 NPK 构建仍是程序调色，不等于逐帧 Aseprite 重绘。Prompt 数量、旧文件名中的“全技能”和一张预览图都不能证明完整资源覆盖。

## 目录

```text
樱花主题/
├─ prompts/       相对职业通用 Prompt 的樱花主题视觉增量
├─ frames/        原版参考、联系表及按 RunId 生成的 Aseprite 活动输出
├─ npk/           历史补丁、回滚基线及新的版本化活动输出
├─ validation/    构建与 Aseprite 导出 provenance
├─ 樱花粉预览.png  历史 Photoshop 预览，不由活动流程覆盖
└─ README.md
```

## 历史主补丁

`!!!女气功全技能-樱花粉.NPK`

- 基于已实机验证正确的第二次修复机制：所有替换帧统一写为 `ARGB_8888`。
- 保留第二版原有 491 个 IMG，并新增两组此前误跳过的纯技能特效：
  - `lightdragonthirteen/characteraction.img`：34 帧
  - `lightningdragon/character.img`：4 帧
- 人物本体 `doublelightningdragon/awakebody_nenmaster_0000.img` 不改色。
- SHA-256：`D6626A832E7C2F612CC10FD16A387633F1C3E8E8ADEAAB2401D544442B980668`

## 第二版原件

`!!!女气功全技能-樱花粉-第二次修复原版.NPK`

- 从历史构建记录精确恢复，用于回滚和对照。
- 文件大小：`106557702` 字节
- SHA-256：`264BE57F481F96A7EF4F35A7FCBDA5E940A052788A3FDF144081953A733EDD60`

不要同时把两个 NPK 放进游戏目录，它们包含重复的内部 IMG 路径。

## 活动工具链

DNF 源、ExtractorSharp、DirectXTex 和 Aseprite 均通过仓库根的本地配置与项目工具模块解析。官方 `ImagePacks2` 只读，活动输出只写当前主题工作区。

用户须从工作区外提供合法 Aseprite 安装目录；导入副本位于被忽略的本地工具槽位，不提交、不分发：

& '.\tools\Import-DnfAseprite.ps1' -SourceDirectory '<合法 Aseprite 安装目录>'

导入后运行真实 API 能力与本地工具链门禁：

& '.\tools\Test-DnfLocalToolchain.ps1' -RequireAseprite

## 程序调色构建

默认从本地配置解析只读 `ImagePacks2`，并写入新的 `RunId` 目录：

& '.\tools\Build-SakuraNenPatch.ps1' -RunId 'sakura-program-recolor-v1'

默认输出为 `npk\sakura-program-recolor-v1\nenmaster-sakura-program-recolor-v1.NPK`。入口拒绝覆盖已有输出；复跑必须使用新的 `RunId`。

精确复现历史第二版：

& '.\tools\Build-SakuraNenPatch.ps1' -RunId 'sakura-second-fix-reproduction-v1' -ExactSecondFix

复现产物使用独立文件名，不覆盖历史第二版原件。显式 `-OutputFile` 仍必须位于当前主题工作区且目标不存在。

## 预览

- `frames\preview\全技能联系表.png`：60 个代表性 IMG。
- `frames\preview\重点技能联系表.png`：螺旋念气场、天雷分身步和雷龙等重点 IMG。
- `frames\reference\天雷分身步-原版参考.png`：原包对照。
- `樱花粉预览.png`：旧契约下由 Adobe Photoshop CC 2018 导出的历史预览，保持不可变。

活动 Aseprite 预览入口：

& '.\tools\Export-SakuraPreview.ps1' -RunId 'sakura-preview-aseprite-v1'

默认输出为 `frames\preview\sakura-preview-aseprite-v1\樱花粉预览.png`，provenance 为 `validation\sakura-preview-aseprite-v1\preview-export.json`。入口在写入前验证 Aseprite 版本、SHA-256 和真实 API 能力，并拒绝覆盖已有路径。

`tools\Export-SakuraPreview.jsx` 只保留作历史复现证据，不再是活动入口。预览导出不创建分层逐帧工程，也不能授权 NPK 发布。

## Prompt 分层

- 职业通用运动、轮廓与阶段提示：`../prompts/`。
- 樱花色板、材质和技能具体变化：`prompts/`。
- 两层 Prompt 都不代替 `../manifest.json`，也不能单独证明全技能覆盖。
