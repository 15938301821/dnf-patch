# DNF 补丁规则、漏洞与下一线程交接

> 历史证据文件：现行执行不依赖本文。第八至十一节的全局 skill 与单职业 skill 计划已被第十二节取代；新线程以当前根/职业/主题规则、manifest、Prompt、项目 skill 和 release 报告为准。

记录时间：2026-07-11（Asia/Shanghai）

本文件用于在新线程中继续工作。它记录当前用户要求、三级规则架构、历史产物、已确认漏洞、联网依据、尚未完成的全局 skill 工作和下一线程边界。不要把这里的女气功或樱花常量复制进所有职业通用 skill。

## 一、用户最终范围与权限

1. DNF 补丁制作规范和 `dnf-patch-maker` skill 面向整个 DNF 的所有职业，不单独针对女气功。
2. 所有职业通用规则放在仓库根 `AGENTS.md` 和全局 skill。
3. 单职业的资源映射、技能阶段和人物层边界放在对应职业目录。
4. 主题的配色、材质、Prompt 和主题验收放在对应职业的主题目录。
5. 所有 P 图使用本机 Adobe Photoshop CC 2018。
6. 只处理补丁工作区；不检查或处理游戏进程，不主动部署到 ImagePacks2。
7. 用户负责实机验证。离线解析或工具自校验不能写成“游戏已验证”。
8. 不覆盖已知正确的第二次修复基线，不删除用户文件。

## 二、本线程写入的规则文件

- `AGENTS.md`：所有职业通用规则。
- `气功师（女）/AGENTS.md`：女气功职业规则，不含樱花风格。
- `气功师（女）/樱花主题/AGENTS.md`：樱花主题规则。
- 本文件：漏洞、证据、来源和下一线程待办。

本线程没有创建或更新全局 `dnf-patch-maker` skill，没有移动 NPK，没有重新构建补丁，也没有触碰游戏目录或进程。

## 三、当前产物与可复核事实

### 已知正确的第二次修复原版

```text
路径：气功师（女）/樱花主题/npk/!!!女气功全技能-樱花粉-第二次修复原版.NPK
大小：106557702 bytes
SHA-256：264BE57F481F96A7EF4F35A7FCBDA5E940A052788A3FDF144081953A733EDD60
文件修改时间：2026-07-11 12:55:56
```

- 用户明确表示昨晚第二次修复是正确版本。
- 历史恢复包包含 491 个 IMG、5851 帧。
- 该文件必须保持不可变，用于回滚和差异基线。

### 当前优化工作产物

```text
路径：气功师（女）/樱花主题/npk/!!!女气功全技能-樱花粉.NPK
大小：106729631 bytes
SHA-256：D6626A832E7C2F612CC10FD16A387633F1C3E8E8ADEAAB2401D544442B980668
文件修改时间：2026-07-11 12:59:34
```

- 离线比较结果：493 个 IMG、5889 个总帧，其中 5876 个为非 LINK 帧。
- 与第二次修复共同的 491 个 IMG、5851 帧在 Type、geometry、canvas、Hidden 和解码 BGRA 上完全一致。
- 仅新增：
  - `lightdragonthirteen/characteraction.img`：34 帧。
  - `lightningdragon/character.img`：4 帧。
- 新增 38 帧为 `ARGB_8888`，离线检查非空、非黑并符合当前粉色通道规则。
- 以上是离线证据；当前优化包仍需用户实机验证，不能标记为已通过客户端验证。

## 四、问题时间线

1. 初版/早期修改出现大量技能为空，螺旋念气场出手为空，天雷分身步仍显示原样。
2. 第二次修复使用完整 `ARGB_8888` 替换路径，用户实机确认正确。
3. 后续“保留原 DXT 类型”的优化撤回了正确机制，产生技能针缺失和大量黑技能。
4. 审计确认黑包的项目副本与安装副本一致，问题来自产物内容而非复制过程。
5. 已从历史构建记录恢复第二次修复原版，并以它生成 additive 优化工作产物。
6. 用户要求停止处理游戏进程，后续仅制作补丁并由用户验证。
7. 用户进一步明确：全局规范/skill 必须覆盖所有职业；职业和主题内容分层存放。

## 五、漏洞登记

### V-001：DXT 声明与 ARGB 载荷混合

历史错误调用：

```csharp
sprite.ReplaceImage(sprite.Type, false, picture);
```

当 `sprite.Type` 为 DXT 时，ExtractorSharp 的 `Sprite.ReplaceImage` 保留 DXT Sprite 类型；但 `Texture.CreateFromBitmap` 对大于 `LINK` 的类型执行 `type -= 4`，随后把 Bitmap 转成 ARGB 字节并 zlib 压缩，没有执行 BC1/BC2/BC3 编码，也没有生成 DDS 头。

结果：Sprite 仍是 `DXT_1/DXT_5`，Texture/载荷却是 `ARGB_1555/ARGB_8888`。工具可能能按自己的归一化逻辑重新打开，客户端会按 DXT/DDS 解释，从而出现黑帧、黑底或缺帧。

审计数量：

- 混合格式修改帧总计 5338。
- `DXT_1 -> ARGB_1555`：3117 帧。
- `DXT_5 -> ARGB_8888`：2221 帧。
- 重点包受影响示例：`doublelightningdragon` 299/303、`energyfield` 218/219、`lightdragonthirteen` 167/169、`lightningdragon` 139/146、`skythunderstep` 913/1073。

### V-002：假阳性验证

历史验证逻辑把 DXT Sprite 类型映射到 ARGB Texture 类型后视为合法，验证了工具自身可解码，却没有检查客户端要求的 DDS magic、FourCC、BC 块长度以及 Sprite/Texture 声明一致性。因此“验证成功”仍可生成游戏黑屏包。

全局修复原则：

- DXT 必须使用真正 DDS/BC 载荷并保持声明一致。
- 或者完整转换为经目标客户端验证的 ARGB 路径，使 Sprite、Texture、压缩和载荷全部一致。
- 绝对禁止混合格式。

### V-003：原始 DDS 与错误载荷的字节证据

- 原 `energyball#0` 解压后以 `44 44 53 20`（`DDS `）开头，长度 6608，符合 BC3 DDS 结构。
- 错误候选同帧解压后是裸 BGRA，长度 `25056 = 108 * 58 * 4`，前 32 字节全零，却仍保留 Sprite 的 DXT5 标记。
- DDS/BC 纹理按 4x4 块处理；非 4 倍数尺寸必须按块计算，不能用 `width * height * 4` 冒充 DXT。

### V-004：不透明黑底被错误暴露

审计中最大黑底帧位于 `doublelightningdragon/sin1bluedragon.img#20`，Canvas 为 1600x800，约 98.22% 是不透明纯黑。抽样对照的 alpha 与源逐像素一致，说明并非简单“alpha 被清空”，而是混合格式导致客户端错误解释了原本用于混合/强度的 RGB 数据。

因此不能用“把黑色全部改透明”作为通用修复。

### V-005：固定 512x512 破坏帧几何

旧规则把 512x512 写成所有帧规范。实际 IMG 帧尺寸、Canvas、偏移和锚点各不相同。512 只能用于 AI 概念画布；回灌必须逐帧继承源几何。

### V-006：强制透明背景/无角色不成立

部分资源是人物动作层、Cut-in、黑色加色层或 atlas 子图。统一要求透明、无角色会造成内容丢失或职责冲突。正确做法是 manifest 分类并默认排除人物层，而不是改变所有帧格式。

### V-007：虚构/未核验 NPK 映射

旧 `AGENTS.md` 和当前 `qigong-master-female` skill 使用 `aura_wave`、`aura_field`、`lotus_bloom`、`cutin_awakening` 等示例映射；当前实际构建器使用 `energyball`、`energyfield`、`nenflower` 等清单，项目中找不到前述映射依据。

任何职业都不得按技能翻译名猜资源名。必须先 inventory，再维护 manifest。

### V-008：把 Ver5 转 Ver2 当作默认建议

旧规则建议新手先把 IMG Ver5 转 Ver2。版本转换可能破坏 atlas、TextureVersion、LINK、旋转、压缩和客户端兼容性。默认必须保留原版本；只有单独 A/B 验证后才允许转换。

### V-009：前缀和安全保证无依据

- `%`、`!` 前缀不能证明覆盖顺序、反和谐或不被覆盖。
- “纯视觉不会被 TP 检测”无法证明，必须删除。
- 文档只能说明本项目不主动修改 PVF/EXE/DLL/数值，不能承诺检测或账号安全。

### V-010：全技能声明缺少覆盖 manifest

旧文档只有 12 个 Prompt；当前构建器选择 24 个技能包 stem 和 17 个公共 IMG 路径。Prompt 数量与实际资源范围不一致，且没有完整记录技能起手、循环、命中、收尾和常驻阶段。

三觉 Prompt 存在，但当前 builder 未选择相应 Cut-in 包；不能声称三觉 Cut-in 已交付。

### V-011：按文件名判断人物/特效

`character.img`、`characteraction.img` 既可能是人物，也可能承载纯特效。当前新增两组被离线判定为纯特效，但长期规则必须要求逐帧证据和 manifest 分类，不能只看文件名。

### V-012：代表帧预览掩盖阶段缺失

60 个代表 IMG 联系表不能证明所有帧正常，容易漏掉起手、循环或收尾空帧。发布前需要全帧结构检查、每技能阶段覆盖，以及黑/白/棋盘背景的 alpha 检查。实机截图由用户验证时补充。

### V-013：基线与发布包可同时误部署

当前 `npk/` 同时包含两个扩展名为 `.NPK` 且内部路径重复的包。README 已警告不得同时部署，但仍存在误用风险。后续可把基线放入不可直接部署目录或使用禁用扩展名；移动前需用户确认，当前线程不改位置。

### V-014：构建依赖和路径硬编码

`tools/Build-SakuraNenPatch.ps1` 目前硬编码：

- `G:\Program Files\ExtractorSharp`
- .NET Framework x86 `csc.exe`
- 项目内 junction 和临时输出路径

这不是全职业通用接口。后续应参数化依赖位置、检查 x86 DLL/zlib，并把职业/主题 builder 下沉到对应项目域。

### V-015：发布元数据易漂移

README 中手写哈希和数量会在重建后过期。后续应自动生成 `release.json` 或验证报告，至少记录输入/输出 SHA、构建器源码哈希、工具版本、album/frame 数、允许变化和验证结果。

### V-016：Photoshop 预览命名不一致

用户要求所有 P 图使用 Photoshop CC 2018。当前 `Export-SakuraPreview.jsx` 的输出命名与 README/目录中的 `樱花粉预览.png` 不完全一致，复现链路需要下一线程核对并统一。预览导出不等于逐帧 Photoshop 制作。

### V-017：女气功 skill 职责和触发污染

当前 `qigong-master-female`：

- description 同时声称 Prompt/NPK 概念，正文只会产出 Prompt，补丁请求职责断裂。
- 把樱花、暗黑炎、雷电、赛博、圣光放入触发描述，容易因通用风格词误触女气功。
- 默认 512/256 会污染既有帧回灌。
- 内置未核验的 `aura_*` 映射。
- 默认 Prompt 固定樱花和螺旋念气场，无法代表其他主题或全技能。

应将其改为女气功 domain brief skill；通用 NPK 机制交给 `dnf-patch-maker`，主题详细规则从主题目录读取。

### V-018：全局 skill 污染风险

计划中的 `dnf-patch-maker` 不得包含女气功、念气、樱花、第二次修复、当前色板、当前 builder 名称或项目绝对路径。否则其他职业任务会被错误套用粉色主题和女气功资源映射。

### V-019：按统一 IMG 布局处理所有版本

多个开源实现都把 IMG Ver1/Ver2/Ver4/Ver5/Ver6 路由到不同 handler。Ver5 额外包含共享 Texture 表、texture index、裁剪矩形和旋转等关系。只按职业名或扩展名选择统一处理逻辑，会破坏版本专有结构。必须先读 magic/version，再选择 handler。

### V-020：本机缺少可确认的 BC 编码链

本轮没有在本机发现 `texconv`、`nvcompress` 或 Compressonator，也未确认 Photoshop CC 2018 已安装 DDS 插件。因此 Photoshop 导出 PNG/PSD 后仍不能直接宣称得到客户端兼容的 DDS/BC；后续若要保留 DXT，应先建立并验证独立 BC 编码器链。此项只描述 2026-07-11 的本机检查状态，不是通用环境事实。

## 六、当前正确代码路径与边界

当前 `tools/Build-SakuraNenPatch.cs` 使用：

```csharp
sprite.ReplaceImage(ColorBits.ARGB_8888, false, picture);
```

并检查输出 Sprite/Texture 均为期望 `ARGB_8888`、几何不变、可见源帧未意外透明、主题像素符合规则。该路径复现了用户确认正确的第二次修复机制。

边界：这是当前客户端和当前女气功项目的实测基线，不应写成“所有 DNF 版本都必须转 ARGB”。所有职业通用优先级仍是：保留源结构 > 真正 DXT 编码 > 经目标客户端验证的完整 ARGB 转换；禁止混合格式。

## 七、联网研究记录

访问日期均为 2026-07-11。

### ExtractorSharp

- 固定提交：`433a8fddd85dea669623a1de905c2dec536b9ec5`
- README：https://github.com/d-mod/ExtractorSharp/blob/433a8fddd85dea669623a1de905c2dec536b9ec5/README.md#L20-L35
- `Sprite.ReplaceImage`：https://github.com/d-mod/ExtractorSharp/blob/433a8fddd85dea669623a1de905c2dec536b9ec5/ExtractorSharp.Core/Model/Sprite.cs#L151-L180
- `Texture.CreateFromBitmap`：https://github.com/d-mod/ExtractorSharp/blob/433a8fddd85dea669623a1de905c2dec536b9ec5/ExtractorSharp.Core/Model/Texture.cs#L20-L53
- Ver5 handler：https://github.com/d-mod/ExtractorSharp/blob/433a8fddd85dea669623a1de905c2dec536b9ec5/ExtractorSharp.Core/Handle/FifthHandler.cs#L18-L50
- NPK coder：https://github.com/d-mod/ExtractorSharp/blob/433a8fddd85dea669623a1de905c2dec536b9ec5/ExtractorSharp.Core/Coder/NpkCoder.cs#L245-L281
- Handler 注册：https://github.com/d-mod/ExtractorSharp/blob/433a8fddd85dea669623a1de905c2dec536b9ec5/ExtractorSharp.Core/Handle/Handler.cs#L69-L106

README 声称 NPK/IMG 可读写，支持 IMG Ver1/2/4/5/6；DDS 只列为可读并支持 DXT1/3/5。源码中的 `Texture.CreateFromBitmap` 只做 Bitmap 到 ARGB 字节和 zlib，没有 BC 编码步骤。这支持 V-001 的判断。该提交源码 AssemblyVersion 为 1.7.3.2，与本机 DLL 版本一致，但版本相同仍不单独证明二进制逐字节同源；本轮同时用本机 DLL 行为和产物字节做了交叉验证。

### DNFExtractor

- 固定提交：`6ded7a0f3551a30d21d31eb9ed4060ca11bca1c2`
- 结构与常量：https://github.com/KiraMaple/DNFExtractor/blob/6ded7a0f3551a30d21d31eb9ed4060ca11bca1c2/DNFExtractor/Extractor.h#L13-L74
- NPK/IMG 读取：https://github.com/KiraMaple/DNFExtractor/blob/6ded7a0f3551a30d21d31eb9ed4060ca11bca1c2/DNFExtractor/Extractor.cpp#L5-L55

该项目是较早的社区 NPK extractor，可用于交叉理解 NPK/IMG 结构和 zlib 处理，但代码年代较早、不是官方规范，不能单独作为当前客户端写入兼容性的证明。

### OjoDnfExtractor 与 PyDnfEx

- OjoDnfExtractor README（固定提交 `0d16371aba577e6868c75e8f9518698dc958bc46`）：https://github.com/HsOjo/OjoDnfExtractor/blob/0d16371aba577e6868c75e8f9518698dc958bc46/README.md#L1-L5
- PyDnfEx 格式常量（固定提交 `e417cefe43f54a40e20ef0df235aa1c8ecd8595a`）：https://github.com/HsOjo/PyDnfEx/blob/e417cefe43f54a40e20ef0df235aa1c8ecd8595a/pydnfex/hard_code.py#L1-L36
- NPK 读取/保存：https://github.com/HsOjo/PyDnfEx/blob/e417cefe43f54a40e20ef0df235aa1c8ecd8595a/pydnfex/npk/__init__.py#L18-L83
- Ver5 sprite 表：https://github.com/HsOjo/PyDnfEx/blob/e417cefe43f54a40e20ef0df235aa1c8ecd8595a/pydnfex/img/version/v5.py#L14-L94
- sprite 解压与 DDS/raw 分流：https://github.com/HsOjo/PyDnfEx/blob/e417cefe43f54a40e20ef0df235aa1c8ecd8595a/pydnfex/img/image/sprite.py#L29-L99

这些实现用于交叉验证格式码、NPK 索引、路径 XOR、IMG 版本分流和 Ver5 Texture 关系。其写入路径未经过本项目客户端验证，不能作为制作范例直接照搬。

### Microsoft DDS/BC 文档

- DDS Programming Guide：https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dx-graphics-dds-pguide
- DDS_HEADER：https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dds-header
- DDS_PIXELFORMAT：https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dds-pixelformat
- Block Compression：https://learn.microsoft.com/en-us/windows/win32/direct3d10/d3d10-graphics-programming-guide-resources-block-compression
- Texture Block Compression：https://learn.microsoft.com/en-us/windows/win32/direct3d11/texture-block-compression-in-direct3d-11
- Microsoft 文档固定提交：`8e75e578b68b316f488d3a6961dcbecfa5fbee61`

可直接用于全局验证规则的事实：

- DDS 基础文件至少包含 4 字节 `DDS ` magic、124 字节 `DDS_HEADER`，基础头总计 128 字节。
- DXT1 对应 BC1/FourCC `DXT1`，每个 4x4 块 8 字节。
- DXT3 对应 BC2/FourCC `DXT3`，每块 16 字节。
- DXT5 对应 BC3/FourCC `DXT5`，每块 16 字节。
- block-compressed pitch 为 `max(1, (width + 3) / 4) * blockSize`；高度也按 4 像素块向上取整计算总数据量。
- BC1 只提供无 alpha 或 1-bit alpha；BC3 提供独立插值 alpha，连续半透明光效不能无依据从 DXT5 降为 DXT1。

### Microsoft DirectXTex

- 固定提交：`bf256afaed1c789ddd444fb45105ffbcab283efe`
- README：https://github.com/microsoft/DirectXTex/blob/bf256afaed1c789ddd444fb45105ffbcab283efe/README.md#L9-L37
- `Compress`/`SaveToDDS` API：https://github.com/microsoft/DirectXTex/blob/bf256afaed1c789ddd444fb45105ffbcab283efe/DirectXTex/DirectXTex.h#L583-L618

DirectXTex/texconv 是后续建立真正 BC 编码链的优先候选；是否安装和具体参数仍需在下一线程验证，不能仅凭文档宣称本机可用。

### 多实现交叉事实

- 社区实现一致使用格式码 14/15/16 表示 ARGB1555/4444/8888，17 表示 LINK，18/19/20 表示 DXT1/3/5。
- NPK 索引包含 offset、size 和 256 字节内部路径；路径使用固定 256 字节 key XOR。多个实现使用 `NeoplePack_Bill` 和 `Neople Img File` 标识并在保存头后写 SHA-256。
- IMG 版本布局不同；ExtractorSharp 为 Ver1/2/4/5/6 注册不同 handler，不能宣称同一写入流程支持所有版本。
- Ver5 包含共享/外置 Texture 表以及每帧 texture index、裁剪矩形和旋转元数据，这些都属于必须保留的结构。
- 本项目更大范围的原生 Ver5 样本中，26740 个非 LINK 帧未发现一例 DXT Sprite 搭配外置 ARGB Texture；这属于当前样本证据，不是 Neople 官方保证。

本轮搜索未找到可作为权威写入规范的官方 DNF NPK/IMG 文档。因此 skill 必须把 Microsoft 的标准 DDS 事实、社区逆向实现和本项目实机结论分开标注。

### 尚未确认、不得写成事实

- 未找到 Neople 官方 NPK/IMG 格式规范。
- 客户端对同内部路径多个补丁的精确覆盖顺序没有在线官方依据。
- ExtractorSharp 枚举中存在更高 IMG 版本，但所查提交未注册 Ver7/Ver8/Ver9 handler，不能宣称支持。
- TextureVersion 的完整业务语义未确认；正确策略是原样保留，不自行推导。
- 其他地区、历史版本或 IMG 变体是否接受某类完整外置 ARGB 纹理未确认。
- Photoshop CC 2018 是否具有可用 DDS 插件、插件输出是否匹配 DNF Ver5 均未确认。

## 八、全局 skill 目标架构（下一线程实施）

推荐全局安装位置：

```text
C:\Users\39592\.codex\skills\dnf-patch-maker\
├─ SKILL.md
├─ agents\openai.yaml
└─ references\
   ├─ project-layout.md
   ├─ npk-img-workflow.md
   ├─ texture-formats.md
   ├─ validation-checklist.md
   └─ sources.md
```

职责：创建、检查、修复、比较、验证、封装并在明确授权时部署所有职业的 DNF NPK/IMG 视觉补丁。职业与主题范围必须由用户、项目 `AGENTS.md` 或本地 domain skill 提供。

建议 frontmatter description：

```text
Create, inspect, repair, compare, validate, package, and optionally deploy DNF NPK/IMG visual patches. Use for ImagePacks2, ExtractorSharp, sprite-album edits, missing, black, or transparent effects, known-good patch recovery, recoloring or replacement, and NPK artifact verification. Obtain profession- and theme-specific scope from the user or project-local rules and skills.
```

主流程：

1. 确认操作类型、源包、已知正确基线、输出、domain brief 和部署权限。
2. 固化并哈希输入。
3. inventory album/sprite/texture。
4. 声明允许变化集合。
5. 在新输出上最小修改。
6. 保存并执行结构、DDS/ARGB、解码、alpha、空/黑帧和 baseline diff 验证。
7. 报告产物、哈希、变化、异常和待用户实机验证项。

全局污染扫描应满足：

```powershell
rg -i 'qigong|nenmaster|女气功|樱花|sakura|C43F73|lightdragon|second-fix|Build-Sakura' `
  'C:\Users\39592\.codex\skills\dnf-patch-maker'
```

预期零命中。

## 九、项目内女气功 skill 的下一步

把 `.codex/skills/qigong-master-female` 改为职业 domain skill：

- 仅在请求明确涉及女气功时触发。
- 支持三种模式：概念 Prompt、既有帧美术适配、职业补丁 domain brief。
- 只有概念模式可以建议 512/256；补丁模式继承原几何和 alpha。
- 删除通用主题词触发和未核验 `aura_*` 映射。
- NPK 机制单向交给 `$dnf-patch-maker`。
- 樱花等详细主题从对应主题目录加载，不常驻职业 skill。

用户说“单职业放到对应职业文件夹”。下一线程应在不破坏 Codex 发现机制的前提下决定：把职业 skill 的规范引用下沉到职业目录，或把 skill 实体迁移/链接到职业目录。迁移前先验证项目级 skill discovery，不能直接删除当前可发现路径。

## 十、下一线程验收与待办

1. 重新读取根、职业、主题三级 `AGENTS.md` 和本交接文件。
2. 使用 `$skill-creator` 创建全局 `dnf-patch-maker`；当前机器的 `python.exe` 只是 Microsoft Store alias，`init_skill.py`/`quick_validate.py` 不能直接运行。下一线程需先确认可用 Python，或明确记录采用等价手工 scaffold 和 PowerShell 验证的原因。
3. 创建精简 `SKILL.md` 和按需加载的 references；不得复制女气功或樱花常量。
4. 更新项目内 `qigong-master-female` 的职责、触发描述和元数据。
5. 建立女气功机器可读 manifest，来源必须是实际 NPK inventory；不要从旧 Prompt 表复制映射。
6. 参数化或下沉 `Build-SakuraNenPatch.*` 和 Photoshop JSX；不在没有必要时移动当前产物。
7. 自动生成验证报告/release metadata，覆盖输入/输出 SHA、album/frame、geometry、格式一致性、空/黑帧和 diff。
8. 对 global-only 其他职业、qigong-only Prompt、两者组合补丁做三个新上下文 forward-test。
9. 用户验证前，不部署、不处理游戏进程、不把当前优化包写成实机通过。

## 十一、新线程启动提示

在新线程中可直接使用：

```text
请读取 E:\My Project\DnfPatch\AGENTS.md 和
E:\My Project\DnfPatch\docs\thread-handoff-2026-07-11.md，
继续完成所有职业通用的 $dnf-patch-maker 全局 skill，并按交接文件更新项目内
$qigong-master-female。不要重建或部署 NPK，不要处理游戏进程；先完成 skill、
manifest 方案和验证，再汇报。
```

## 十二、后续架构决议（覆盖第八至十一节的未完成计划）

本节记录同日后续用户决议。第八至十一节保留为历史计划和缺陷证据，但不再是现行执行方案。

1. 不在用户级 `C:\Users\39592\.codex\skills` 安装 DNF 项目 skill。
2. 仓库根只注册一个项目级跨职业 skill：`.codex/skills/dnf-patch-maker/`。
3. 已删除项目级单职业 `qigong-master-female` 及孤立旧 Prompt skill 文件。
4. 职业事实和主题无关提示由职业根的 `AGENTS.md`、`manifest.json`、`prompts/` 提供，不再注册为项目级单职业 skill。
5. 主题目录 `prompts/` 只保存相对职业 Prompt 的具体视觉增量；真实 NPK/IMG 映射仍只来自 manifest/inventory。
6. 每次新线程必须从当前工作区自举，重新读取根规则、职业规则/manifest/Prompt、主题规则/Prompt，并现场复核路径、哈希、inventory、产物和部署状态。
7. 本 handoff 只保留历史证据，不是构建、验证或部署的必读前置。
8. 当前机器没有可用 Python 解释器，`skill-creator` 的 `init_skill.py` 与 `quick_validate.py` 无法直接执行；本次按脚本契约使用等价手工 scaffold 和 PowerShell 校验，未安装额外 Python。
9. 项目 skill、职业 Prompt 和主题 Prompt 统一使用稳定中文章节；英文只保留在可直接交给图像模型或工具的代码块中。
