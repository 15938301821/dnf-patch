# Vergil（维吉尔）暗蓝幻影主题规则

本文件只在当前主题目录树内生效。它必须与仓库根规则、剑魂职业规则、经核验的 manifest/inventory 和同名职业 Prompt 一起使用，不得扩大资源范围或改变职业动作。

## 主题目标

在继承同名职业 Prompt 的运动、阶段、轮廓、命中辨识和源资源边界后，追加 DMC5 维吉尔式暗蓝幻影视觉：冰蓝次元斩、幻影剑阵与空间裂纹。主题外观不得取代职业基础动作，也不得凭造型映射推断真实资源身份。

## 色板、材质与共同风格

共同 Base Style：

```text
DMC5 Vergil aesthetic, icy cobalt-blue energy, Mirage Edge phantom blades, Yamato dimensional-slash styling, spatial-rift fractures, glitch-ice particle trails, cold neon azure rim light, clean sharp blade edges, controlled anime action-game VFX layering
```

颜色锚点：

- 冰蓝主光：`#1a8fff`。
- 暗底辉光：`#0a1633`。
- 刀刃高光：`#ffffff`。
- 空间裂纹：`#00d4ff`。

刀刃使用白色锐利核心与冰蓝外辉光；幻影剑使用半透明冷光能量刃和清楚硬边；裂纹使用青色碎玻璃式空间裂纹或次元狭缝。粒子保持稀疏、方向明确，以冰晶或故障冰尾迹表现；人物或衣摆残影只在源人物轮廓已存在时追加哑黑提示。

视觉层次为：空间裂纹或次元裂隙在后，刀刃与幻影剑在中，冰蓝辉光和粒子在前。该层次不规定具体合成模式，实际层关系仍服从源资源。

幻影剑统一为冰蓝或青蓝冷光，不混入金色、红色。共同排除暖火焰色板、红橙黄火光、粉色樱花、骷髅或死亡母题、可爱粉彩、失控杂乱粒子、浑浊刃缘，以及主题额外新增的水印、无关 UI 或文字。

## 三觉立绘参考图约定

三觉 Cut-in 定稿只使用以下两张主题目录内图片作为主参考；根目录 `1.png`、`2.png`、`3.png`、`4.png` 不再参与三觉立绘定稿：

- `referencediagram/DNF剑魂3觉立绘改维吉尔.png`：主体造型参考。继承银白长发、正面人物焦点、蓝黑战装、金属护甲、双刀关系、冰蓝主刀光和冷色空间碎片。
- `referencediagram/DNF剑魂3觉立绘改维吉尔 (1).png`：电影式构图参考。继承前景人物与后景暗色幻影的双层层次、斜向主切线、黑色空间背景、紫蓝裂隙和碎片环绕关系。

两图只提供人物、服装、武器、构图、光线和材质参考，不能直接决定源 IMG、帧号或阶段。实际 Cut-in 必须在通过项目 API 能力探针的本地 Aseprite 中按经核验源帧的宽幅裁切、人物位置、时序、alpha、Canvas 和偏移逐帧适配；每个活动帧同时保存分层 `.aseprite` 工程和 runtime PNG，不得把 `1728x2304` 参考画幅直接回灌。参考图右下角的“豆包AI生成”以及任何生成式水印、签名和文字都必须从最终立绘与所有运行帧中完全移除。

三觉立绘仍以暗蓝、冰蓝、青色和白色为主；参考图中的紫色只允许作为次级空间裂隙边光，不能取代冰蓝主刀光或让整体转为紫色主题。不得复制参考图中与源 Cut-in 构图冲突的地面、完整竖幅背景或被裁断后无法辨认的装饰。

## Prompt 路由

先加载仓库根规则、剑魂职业规则和经核验的 manifest/inventory，再加载职业目录同名 Prompt，最后追加本主题同名 Prompt。共同 Base Style 从本文件加载，逐技能主题 Prompt 不重复整段共同风格。

职业 Prompt 决定动作和阶段；主题 Prompt 只补充色板、材质、粒子、光线、裂纹和造型隐喻。任何主题专名都只是外观语言，不建立资源映射。

## 修改范围与边界

- 只允许改变经 manifest 明确授权范围内的视觉像素；人物、武器、Cut-in、背景、UI、文字和纯特效分类不得由主题推断。
- 裂纹、幻影剑和辉光不得遮没职业 Prompt 中的起手、行进、循环、命中、爆发或收尾辨识。
- 主题 Negative Prompt 只能排除新增的主题外观，不能删除源资源原本合法的人物、脸部、背景、UI、文字或 Cut-in 内容。
- 仅在 inventory/manifest 已确认素材为孤立纯特效，且目标只是适用的 AI 概念图建议时，才可选择 512x512 概念画布、transparent background、no character 或 no UI。这些不是回灌硬规则；回灌必须按源帧尺寸、构图、透明度、锚点和分类处理，也不得统一居中。
- 不在主题层保存具体资源路径、帧号、构建、封包、部署、兼容或账号安全结论。

## 主题验收与回归

- 冷蓝主光、白色刃核、青色裂纹和暗蓝底辉光层级清楚，暗部不能形成意外全画布黑块。
- 幻影剑色相统一、轮廓可读；裂纹、剑刃、辉光与粒子不能吞没职业动作和命中焦点。
- 拔刀斩、极·神剑术（破空斩）和幻影剑舞分别保持 Judgment Cut、Judgment Cut End 与 Summoned Swords 的主题招牌语言，但不得改变职业基础动作。
- 人物、武器与 Cut-in 只按源语义处理；黑、白、棋盘背景下的 alpha 和全阶段联系表仍须通过根规则门禁。
- 三觉 Cut-in 必须能追溯到本文件列出的两张主参考图，并通过无水印检查、宽幅裁切检查和全阶段人物焦点检查。
- 主题 Prompt 数量和招牌技能优先级不证明真实资源覆盖，所有覆盖状态仍待 manifest/inventory 核验。

## 领域工具路由

- 当前主题的离线试制入口是 tools/Build-VergilMomentarySlashPilot.ps1；它只能读取职业 manifest 已核验并授权的单包、内部 IMG 与帧集合。
- 逐纹理发布门禁入口是 tools/Test-VergilMomentarySlashTextures.ps1；它只读比较源包和候选包，并输出 40 纹理的 DDS、alpha 块、BGRA、alpha 哈希与 texdiag 结果。
- C# 构建器只允许保留 Ver5 和源 DXT5 结构，在 BC3 块内保留原 alpha 数据并替换允许帧的颜色数据；不得调用会重建图集关系的 Adjust、Refresh 或 Bitmap 替换接口。
- 该入口是部分资源 pilot，不得扩展到其他 NPK、从技术资源 ID 推断中文技能名，也不得据此声明全技能覆盖或目标客户端兼容。
- 构建产物只写入当前主题工作区；部署只在用户当前请求明确授权时作为独立步骤执行。

活动三觉 Cut-in 使用以下两阶段入口：

- tools/Render-CutinWeaponmasterNeoVergil.ps1：冻结源 inventory、24 张源帧和两张参考图，在同一 `RunId` 下生成帧 3–26 的 24 个分层 `.aseprite` 工程、24 个 1068x600 runtime PNG 与 `render-summary.json`。写输出前必须通过 Aseprite API 30 能力探针；工程重开和 runtime 像素等价均为硬门禁。
- tools/Build-VergilCutinWeaponmasterNeo.ps1：只接受与自身 `RunId` 完全一致且通过的渲染摘要和 runtime PNG；帧 0–2 保留 1x1 透明占位，帧 3–26 才允许变化。输出使用新的版本化 NPK 与验证目录，不覆盖历史 Cut-in v2。
- Aseprite 只负责分层编辑和 PNG。构建阶段仍由 DirectXTex 编码真实 DDS/BC3，由 Ver5 handler 保留 TextureVersion、纹理索引、图集裁剪、旋转、共享关系、几何和压缩语义，并由 texdiag 与独立索引复核。
- Render 和 Build 必须显式使用同一 `RunId`；历史 Photoshop JSX、历史 Cut-in v2 payload 和旧 final summary 不能代替当前 Aseprite 渲染摘要或授权新发布。

## 活动迁移门禁

- 旧 v1 manifest-scope 发布及其 final/release/package 只作为旧契约下的不可变历史证据。
- 根规则、主题规则、Aseprite 脚本、构建器、资源计划或验证器发生变化后，活动链必须从新的 `fullSkillCoverageProven=false` 资源计划开始，并在新的空目录重跑聚合、全帧验证和发布闭环。
- 未导入合法 Aseprite、API 能力不满足、24 帧工程/runtime/摘要未生成或新的独立最终验证未通过时，活动状态保持阻断，不得沿用旧 v1 已归档的覆盖结论宣称新契约已经完成。

## 正式 DAG 路由

- 当前主题正式 workflow ID 为 `weaponmaster.vergil.aseprite-full-skill-v1`，声明文件为 `workflows/aseprite-full-skill-v1.json`；职业 manifest 必须保持该注册关系，不能从 README 或历史 handoff 猜入口。
- DAG 固定为 10 步：PowerShell 源码门禁、本地 Aseprite 工具链、活动迁移 readiness、32 源聚合、新目录最终验证、pending 人工审核模板、人工审核门禁、发布元数据事务、发布引用闭环、项目总门禁。
- 默认调用 `tools/Invoke-DnfWorkflow.ps1` 只做静态验证。真实执行必须使用新的 3–64 字符小写 `RunId` 和 `-Execute`；已有 Run 只能使用同一 `RunId -Execute -Resume` 恢复。
- 最终验证通过后只允许生成不可覆盖的 `manual-review-template.json`。审核人必须另存同一 Run 下的 `manual-review.json`，填写非空身份与零偏移 UTC 审核时间，逐张审核全部黑、白、棋盘联系表，并把五类 findings 写成显式整数零；客户端兼容和四个部署字段必须为 false。
- 人工审核有效期为 168 小时。首次审核门禁、恢复复用和发布元数据生成都会重新检查时效、证据快照和成功谓词；修改结果 JSON 中的通过状态不能绕过门禁。
- 发布元数据步骤只允许原子替换职业 manifest、创建新的主题 release 和写入 transaction receipt；release/receipt 输出只可在同一 Run 的 `-Resume` 下由 `resume-reconcile` 对账既有文件。提交受命名 Mutex 和 manifest-before CAS 保护；后置闭环失败时必须删除新 release 并按字节恢复旧 manifest。该 DAG 始终禁止网络、部署、`ImagePacks2` 写入和 DNF 进程操作。
- 当前机器尚未导入合法 Aseprite，且新的 24 帧分层工程/runtime、Cut-in 构建、32 源聚合和最终验证证据均不存在，因此只允许静态验证；不得执行正式写链、生成审核通过状态或提升活动覆盖结论。

## 本主题本地成品约定

- 官方源 NPK 只读。本主题的最终交付必须使用带 `weaponmaster-vergil-dark-blue` 与版本号的独立文件名，不得沿用官方 NPK 文件名。
- 最终定制 NPK 只封装已通过 manifest/inventory 授权、离线结构验证、全帧解码、像素门禁和独立索引检查的修改 IMG；未修改的官方 IMG 不复制进定制包。
- 三觉 Cut-in、技术资源 pilot 与后续技能只有在各自映射和门禁均通过后才可加入同一发布包；未核验条目不得为了凑成“全技能”而封装。
- 离线验证通过后把成品、SHA-256、变更清单和发布报告保存在本主题目录。`ImagePacks2` 部署、覆盖优先级测试、备份和回滚全部由用户自行处理，本主题工具不得写入游戏目录。
