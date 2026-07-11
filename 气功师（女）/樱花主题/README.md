# 女气功樱花粉补丁

## 目录

```text
樱花主题/
├─ prompts/       相对职业通用 Prompt 的樱花主题视觉增量
├─ frames/        原版参考、联系表和后续透明 PNG 帧
├─ npk/           最终补丁与第二版回滚基线
├─ 樱花粉预览.png  Photoshop 导出的当前预览
└─ README.md
```

## 主补丁

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

## 构建

默认生成优化第二版：

```powershell
.\tools\Build-SakuraNenPatch.ps1 -ImagePacks2 '<DNF ImagePacks2>'
```

默认输出：`气功师（女）\樱花主题\npk\!!!女气功全技能-樱花粉.NPK`

精确复现历史第二版：

```powershell
.\tools\Build-SakuraNenPatch.ps1 -ImagePacks2 '<DNF ImagePacks2>' -ExactSecondFix
```

默认输出：`气功师（女）\樱花主题\npk\!!!女气功全技能-樱花粉-第二次修复原版.NPK`

显式传入 `-OutputFile` 时可覆盖默认路径。

## 预览

- `frames\preview\全技能联系表.png`：60 个代表性 IMG。
- `frames\preview\重点技能联系表.png`：螺旋念气场、天雷分身步和雷龙等重点 IMG。
- `frames\reference\天雷分身步-原版参考.png`：原包对照。
- `樱花粉预览.png`：由 Adobe Photoshop CC 2018 从当前全技能联系表导出。

Photoshop 导出脚本：`tools\Export-SakuraPreview.jsx`。

## Prompt 分层

- 职业通用运动、轮廓与阶段提示：`../prompts/`。
- 樱花色板、材质和技能具体变化：`prompts/`。
- 两层 Prompt 都不代替 `../manifest.json`，也不能单独证明全技能覆盖。
