# Vergil（维吉尔）暗蓝幻影主题

## 当前发布

当前 manifest 已证明范围的 v1 定制 NPK 已完成离线发布门禁，状态为 `offline-validated-client-pending`，`fullSkillCoverageProven=true`：

    npk\full-skill-v1\weaponmaster-vergil-dark-blue-manifest-scope-v1.NPK

- 大小：`35,037,857` 字节。
- SHA-256：`531DBE6E9E2261531C71293EC7223DE36B57D02948D79831190D4C68FFF247D7`。
- 发布报告：`validation\full-skill-v1\release.json`。
- 最终验证摘要：`validation\full-skill-v1\final-v3\final-validation-summary.json`。
- package summary：`validation\full-skill-v1\package-v1\package-summary-v1.json`。

这里的“完整覆盖”严格限定为当前 manifest 已证明的男鬼剑剑魂视觉资源范围：28 个技术根、31 个显式选择组件、417 个组件 IMG，以及唯一获准的 `cutin_weaponmaster_neo.img`，最终共 418 个 IMG、3822 帧。它不把零匹配 Replay 名称猜成资源别名，也不证明中文 Prompt 显示名逐项映射、客户端加载优先级或目标客户端兼容。

## 变化与保留

- 组件实际变化 3593 帧，三觉 Cut-in 实际变化 24 帧，最终实际变化 3617 帧。
- 显式保留 128 帧、构建后动态保留 74 帧、Cut-in 透明占位保留 3 帧，最终安全保留 205 帧。
- 74 个动态保留帧由 22 个近黑帧、16 个无可见颜色变化帧和 36 个暖色源保护帧组成；其压缩载荷、DDS 与 BGRA 哈希均与源一致。
- 6 个没有安全实际变化的整 IMG、共 19 帧不进入最终包；候选池总排除为 221 帧。
- `AshenFork`、`BackStepCutter`、`HitBack`、`ChargeBurst` 经当前男鬼剑资源审计没有独立视觉根，不猜别名。
- `atultimateblade`、`atillusionslash`、`tripleslashbs` 因职业域或归属证据不足而排除。

共同色板仍为 `#0A1633`、`#1A8FFF`、`#00D4FF`、`#FFFFFF`。三觉 Cut-in 只聚合 `sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img`；`#3-26` 为变化帧，`#0-2` 为 1x1 透明占位，原 Cut-in 包另外 25 个 IMG 不进入最终定制 NPK。

## 构建

先在仓库根目录运行资源计划门禁：

    & '.\tools\Test-VergilResourcePlan.ps1' -ResourcePlanPath '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\configs\full-skill-v1\resource-plan-v2.json'

需要从已验证组件生成新版本时，必须使用新的版本化输出和摘要路径，不能覆盖 v1：

    $plan = Get-Content '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\configs\full-skill-v1\resource-plan-v2.json' -Raw -Encoding UTF8 | ConvertFrom-Json
    $components = @($plan.components | Where-Object { $_.selectedForAggregation -eq $true })
    $reuse = @($plan.reuseComponents | Where-Object { $_.requiredForFinalAggregation -eq $true })
    $sources = @($components | ForEach-Object { Join-Path $PWD $_.output.componentNpkPath }) + @((Join-Path $PWD $reuse[0].sourceComponent.path))
    $imgs = @($components | ForEach-Object { $_.selectedImgPaths }) + @($reuse[0].selectedImgPaths)
    & '.\tools\New-DnfCustomNpk.ps1' -SourceNpk $sources -IncludeImgPath $imgs -OutputPath '<新的版本化 NPK 路径>' -SummaryPath '<新的 package summary JSON 路径>'

封装器按原始 payload 聚合，不重新编码 IMG；输入必须保持 32 个唯一源 NPK 和 418 个唯一 IMG 路径。

## 验证

v1 已通过以下门禁：

- 独立 PowerShell/.NET NPK 索引：418 条目、418 唯一路径、头部 SHA-256 与 IMG magic 全部有效。
- package summary、最终 NPK 与 32 个组件来源逐 IMG payload 长度和 SHA-256 一致。
- 411 个 Ver5 IMG 与 7 个 Ver2 IMG 全部解析；3822 个非 LINK 帧全部解码，LINK=0、Hidden=0。
- 最终格式为 1850 帧 DXT1、1930 帧 DXT5、10 帧 ARGB1555、32 帧 ARGB8888。
- 生成 15 张覆盖全帧的黑、白、棋盘联系表；已人工抽查 `frames-0001.png`、`frames-0008.png`、`frames-0015.png`，未见空白页、意外整画布黑帧或布局异常。
- Cut-in 目标联系表未见参考图水印，源几何、Canvas、偏移和 3 个透明占位保持。

复核现有 v1 时必须使用新的空验证目录，避免混入旧证据：

    & '.\tools\Test-VergilFullSkillRelease.ps1' -ResourcePlanPath '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\configs\full-skill-v1\resource-plan-v2.json' -FinalNpk '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\npk\full-skill-v1\weaponmaster-vergil-dark-blue-manifest-scope-v1.NPK' -PackageSummaryPath '.\剑魂\Vergil（维吉尔）暗蓝幻影主题\validation\full-skill-v1\package-v1\package-summary-v1.json' -OutputDirectory '<新的空验证目录>' -ExtractorDirectory 'G:\Program Files\ExtractorSharp'

## 部署与回滚

本次完整产物未部署，未写入 `ImagePacks2`，也未检查、启动、结束或监控 DNF 进程。文件名只用于人工识别，不能证明客户端优先加载。

后续只有在用户明确授权部署并确认目标路径后，才可把部署作为独立步骤执行。由于当前没有部署，本次不产生游戏目录备份；若以后把该独立定制 NPK 写入游戏目录，回滚应先核对路径和 SHA-256，再只移除该独立定制文件，不改动官方 NPK。

目标客户端 A/B、加载顺序、兼容性和账号风险仍待用户实机确认，离线验证不对此作保证。

## 历史产物

- `npk\progress-v1\!weaponmaster_vergil_darkblue_progress_v1.NPK` 是历史进度预览包，只有 9 个 IMG、67 帧，不是本次完整产物；其历史部署记录见 `validation\progress-v1\release.json`。
- `npk\cutin-weaponmaster-neo-v2\sprite_character_swordman_effect_cutin.NPK` 是 Cut-in v2 历史完整替换组件；本次最终定制 NPK 只复用其中一个目标 IMG payload。
- `npk\vergil-momentaryslash-pilot-v1.NPK` 是早期 Ver5 DXT5 调色链路试制，保留作不可变历史证据。
