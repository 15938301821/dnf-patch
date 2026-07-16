---
name: dnf-patch-maker
description: 为当前仓库所有职业创建、检查、修复、比较、导出、逐帧重绘、验证、封装、闭环发布，并仅在用户明确要求时部署 DNF NPK/IMG 视觉补丁。当请求涉及 DNF 视觉补丁、NPK、IMG、ImagePacks2、Sprite 或 Texture 替换与调色、AI 逐帧重绘、ControlNet、LoRA、图像生成 API、MCP/外部适配器、职业或主题补丁生成、资源 inventory/manifest、黑帧、缺帧、透明异常、正确基线恢复、产物验证、发布报告、发布引用闭环、项目总门禁、工程提示词优化、正确工程回写、skill 反馈循环或部署时使用。职业事实与通用提示从职业目录读取，具体美术变化从主题目录读取；禁止按名称猜测资源映射。
---

# DNF NPK 通用补丁生成

把仓库根 `AGENTS.md` 作为不可放宽的二进制完整性、安全和交付契约。本 skill 只保存跨职业通用机制，不保存任何职业、技能或主题常量。

## 一、每次线程自举

1. 把每次调用视为没有可靠对话历史的新线程。
2. 从当前 skill 路径解析仓库根，并完整重读 `../../../AGENTS.md`。
3. 重新读取目标职业规则、manifest、职业 Prompt、主题规则、主题 Prompt、工具入口和当前产物元数据。
4. 现场复核源包、基线、产物和部署目录的路径、大小、时间、SHA-256、inventory 与冲突。
5. 不把聊天记忆、旧线程摘要、历史 handoff 或上次命令输出作为唯一事实源。
6. 本地契约缺失或互相矛盾时，中止依赖该事实的操作并准确报告缺口，不从记忆补全。

## 二、解析请求范围

1. 把任务归类为检查、盘点、素材导出、逐帧重绘、构建、修复、比较、验证、封装、部署或其组合。
2. 只从用户明确表述或工作路径确定职业；不得从翻译名或猜测的 NPK 名反推职业。
3. 指定主题时，只加载该主题；不读取或混入无关主题。
4. 部署必须由当前用户请求明确授权；构建授权不等于部署授权。

职业或主题路由必须读取 [路由与领域契约](references/routing-and-domain-contract.md)。

## 三、加载分层上下文

按以下顺序读取并合成：

```text
根 AGENTS.md
-> 职业 AGENTS.md
-> 职业 manifest.json
-> 职业 prompts/README.md 与相关职业 Prompt
-> 主题 AGENTS.md
-> 主题 prompts/README.md 与相关主题 Prompt
```

生成 domain brief，至少包含精确源 NPK、内部 IMG、动作阶段、人物/特效分类、include/exclude、不可变基线、允许变化和主题验收条件。

Prompt 的中文稳定结构和合成规则见 [Prompt 契约](references/prompt-contract.md)。manifest 建立或修复见 [Manifest 契约](references/manifest-contract.md)。

## 四、建立事实与允许变化

1. 保持原始 NPK 只读，记录来源、大小、时间和 SHA-256。
2. 修改前 inventory 真实 NPK、IMG 版本、帧数、帧元数据、Sprite/Texture 关系和解码状态。
3. 以经核验 manifest 为资源事实源；manifest 缺失、过期或不完整时先盘点，并把未解决映射显式标为未完成。
4. 把允许变化计算为“用户目标 ∩ manifest include ∩ 职业边界 ∩ 主题范围 - exclusions”。
5. 不以 Prompt 数量、预览数量或产物文件名证明覆盖率。

## 五、在工作区构建

1. 保留最后一个已知正确基线。
2. 写入新的临时工作区产物，不直接覆盖基线或游戏目录。
3. 先按 IMG magic/version 选择 handler，再解释或写入帧结构。
4. 保留所有未授权路径、帧序、几何、偏移、Hidden/LINK、图集、TextureVersion、旋转、共享关系和解码像素。
5. 只有 manifest 已核验显示名映射时，才应用对应逐技能职业 Prompt 与主题增量；映射未核验时只使用源帧语义和 manifest 独立授权的主题共同规则。
6. 全量生成、批量逐帧重绘、单技能试制或用户要求“跑项目/生成补丁/制作技能”时，默认入口必须走“官方源 NPK 现场冻结 inventory/source frames -> 职业 `prompts/` 动作骨架 -> 主题 `AGENTS.md` 共同风格 -> 主题 `prompts/` 技能增量 -> 模型 style plan -> Aseprite 分层工程与 runtime PNG -> 回灌封装 -> 独立验证”的注册 workflow。已存在的 NPK、组件、runtime 图、验证摘要或历史 release 只能作为基线、隔离证据或差异比较输入，不得作为新生成源。
7. 全量生成或批量逐帧重绘时，图像模型输入必须使用“职业 `prompts/` 动作骨架 + 主题 `AGENTS.md` 共同风格 + 主题 `prompts/` 技能增量”的 Prompt 包。职业 Prompt 提供动作、阶段、轮廓、锚点和命中辨识；主题 `AGENTS.md` 提供共同 Base Style、色板、材质、边界和验收；主题 Prompt 只提供逐技能粒子、光线和主题变化。只喂主题 Prompt 不能证明构图完全正确。
8. 单技能试制或用户点名某个逐技能 Prompt 时，该 Prompt 必须与主题 `AGENTS.md` 和同名职业 Prompt 绑定，只在对应资源/帧白名单内作为最高优先级输入；三者必须进入 run plan、SHA-256、Aseprite 分层工程、runtime PNG 和最终验证证据。单技能绑定不能替代全量 Prompt 包；纯 DDS endpoint 调色、色板配置或构建脚本引用不能报告为 Prompt 已生效。
9. 涉及 AI 或外部生成服务时，先冻结源帧 inventory 和机器可读运行计划；分离 source、generated、edited、runtime，记录每帧实际配置与哈希。生成结果经项目本地 Aseprite 适配、保存分层 `.aseprite` 工程、导出 runtime PNG 并通过真实 API 能力与重开验证后才可进入回灌。
10. 外部适配器默认最小权限、网络关闭且不能写游戏目录；不采用未经现场验证的 MCP、端口、模型端点、包装器或绝对路径配置。
11. Aseprite 只承担栅格编辑与 PNG 导出，不承担 DDS/BC 编码、IMG/NPK 封装或客户端兼容证明；压缩和封装继续由经验证的 DirectXTex、实际 IMG handler 与独立检查路径完成。
12. 缺少模型输出、Prompt 包快照、Aseprite 分层工程、runtime PNG、源帧 inventory 或注册 workflow 证据时必须阻断；不得回退到 endpoint recolor、历史 Photoshop/JSX、旧组件 NPK 或旧验证目录来交付新补丁。
13. 临时产物通过全部门禁后，再原子更新最终工作区产物。
14. 存在职业 manifest 注册的 workflow 时，先按声明式控制面静态验证；真实执行必须显式 `-Execute` 和新 `RunId`，不得直接串接未注册脚本。legacy 或 diagnostic 脚本必须显式 opt-in，且不能作为默认生成结果。

构建或修复时读取 [NPK/IMG 工作流](references/npk-img-workflow.md)。修改 Sprite/Texture 前读取 [纹理完整性](references/texture-integrity.md)。
涉及逐帧重绘、ControlNet/LoRA、图像生成 API、MCP 或外部包装器时读取 [逐帧重绘与外部适配器契约](references/frame-redraw-and-adapter-contract.md)。
涉及声明式 DAG、白名单适配器、暂停、人工审核、恢复或遗留隔离时读取 [自动化工作流契约](references/automation-workflow-contract.md)。

## 六、验证与发布

1. 同时使用生成器校验和至少一个独立解析/检查路径。
2. 解码每个非 LINK 帧并验证每个 LINK 目标。
3. 比较路径集、版本、索引、帧序、几何、Hidden、LINK、图集、旋转、TextureVersion、格式和未授权 BGRA。
4. 格式/载荷混合、非法 DDS/BC、意外空帧/黑帧、未声明差异或报告不完整时立即中止。
5. 生成覆盖全帧的黑、白、棋盘联系表；代表帧只能补充。
6. 逐帧重绘时额外对账 source/generated/edited/runtime/final 的帧键与哈希，拒绝缺帧、重帧、错序、尺寸漂移和未声明配置漂移，并结合源序列检查相邻帧连续性。
7. 记录输入/输出哈希、工具版本、模型/适配器 provenance、每帧实际 seed、数量、允许/实际变化、排除项、异常和待实机项。
8. 最终验证写入新的空版本目录；被 final summary 记录哈希的工具或来源变化后必须重跑，不能只改报告。
9. 保持资源计划起始覆盖状态为 false，由 final summary 授权生成 manifest/release 元数据，再运行发布后闭环门禁。
10. 更新 README 后运行项目总门禁；任何引用漂移、PowerShell 编码、Prompt 树或 JSON 问题都阻断交付。
11. 人工审核模板不得由自动化改成通过；审核人另存审核证据后，只能用同一 `RunId`、`-Execute` 和 `-Resume` 继续。

封装或部署前读取 [验证与发布](references/validation-and-release.md)。生成完整覆盖元数据或收口发布时必须读取 [发布闭环契约](references/release-closure-contract.md)。选择工具前读取 [项目工具表](references/tool-map.md)。

## 七、工程回写循环

1. 每次生成、修复、验证或发布后，先形成“可回写候选”清单，逐项标注来源证据、验证入口、适用层级和禁止写入位置。
2. 只有满足以下条件的结论才可回写：当前线程现场验证通过，至少一个独立检查路径一致，结论可复用于同类工程，且不会扩大 manifest 或降低根规则。
3. 按作用域分流：项目级流程、工具顺序和门禁写入根规则或项目级 skill；职业/主题稳定语义写入对应 `AGENTS.md` 或 Prompt；资源身份、IMG/帧、哈希和一次性产物只写入 manifest、验证报告或发布证据。
4. 回写 Prompt 时只补充稳定动作、阶段、构图、色板、材质或验收条件；不得写入 NPK/IMG 猜测、临时路径、模型私有端点、单次 seed、客户端兼容或账号安全结论。
5. 回写 skill 时只保存跨职业通用机制，不保存职业名、技能名、主题色、历史产物路径或单次运行统计。
6. 回写后重新运行对应门禁：Prompt 或 AGENTS 变化运行 Prompt 树验证；skill 或根规则变化运行项目总门禁；验证失败即撤回或修正本次回写。
7. 最终汇报必须区分“已回写的稳定工程规则”“仅保留为证据的产物事实”和“仍需 inventory、人工审核或实机 A/B 的待验项”。

## 八、仅在明确授权时部署

1. 把构建和部署作为两个独立动作。
2. 部署前备份现有安装包，使用非 `.NPK` 临时扩展名暂存并校验哈希。
3. 在同目录原子替换并独立复核部署后哈希。
4. 不同时部署包含重复内部 IMG 路径的多个 NPK。
5. 除非用户另行要求，不检查、启动、结束或监控游戏进程。
6. 不使用时间戳随机化、签名伪造、虚假来源、特殊前缀或封装参数规避扫描或检测。
7. 用户未完成目标客户端验证前，状态始终写为“离线验证通过、实机待验”。

## 九、稳定中文交付结构

按以下固定顺序汇报：

1. `结果`：成功、失败或被门禁阻断。
2. `产物`：路径、大小、SHA-256。
3. `变化`：相对基线允许且实际发生的差异。
4. `验证`：结构、解码、格式、像素、联系表和独立检查结果。
5. `部署`：目标、备份、原子替换和部署后哈希；未授权时写“未部署”。
6. `待验`：目标客户端测试、未证明覆盖和其他剩余风险。

不得在没有证据时宣称全技能覆盖、客户端兼容、检测规避或账号安全。
