# 路由与领域契约

## 一、新线程独立性

每次调用都从当前文件系统开始，不要求先有旧对话、handoff、记忆路径或记忆哈希。历史文档只能解释规则来源，不能覆盖当前规则、manifest、Prompt、inventory、产物和部署状态。

## 二、固定加载顺序

1. 根 `AGENTS.md`：二进制完整性、来源、验证、安全、交付和回滚。
2. 职业 `AGENTS.md`：职业边界、阶段语义、人物/特效分类和职业回归。
3. 职业 `manifest.json`：经核验的 NPK、IMG、帧、来源哈希、include/exclude 和覆盖事实。
4. 职业 `prompts/`：主题无关的运动、轮廓、阶段、层次、锚点和构图语义。
5. 主题 `AGENTS.md`：色板、材质、允许视觉变化和更严格验收。
6. 主题 `prompts/`：所选主题的具体视觉增量。

下层可以缩小范围或增加更严格验收，不能放宽根规则或扩大 manifest。

## 三、职业选择

- 从用户明确表述或工作区路径选择职业。
- 多个职业都可能匹配时，只列出含职业规则的候选并请求目标。
- 不从 Prompt 标题、NPK 翻译名或经验推断职业和资源。

## 四、Prompt 合成

```text
源帧语义与几何
+ 职业 Prompt 的稳定运动、轮廓与阶段
+ 主题 AGENTS.md 的共同 Base Style、色板、材质和边界
+ 主题 Prompt 的粒子、光线和逐技能增量
```

Prompt 和主题规则不建立资源映射。主题 `AGENTS.md` 与主题 Prompt 都不能加入 manifest 未允许的帧、album、NPK、人物层或 Cut-in。

逐技能 Prompt 只有在 manifest/inventory 明确证明技术资源与显示名映射后才可路由。映射状态为未核验时，不得根据同名文件、翻译名或 Replay 名称套用逐技能 Prompt；只允许使用源帧事实和不依赖显示名的共同主题规则。

全量生成时，职业 `prompts/`、主题 `AGENTS.md` 与主题 `prompts/` 必须作为 Prompt 包进入图像模型和 Aseprite run plan。职业 Prompt 是构图骨架，主题 `AGENTS.md` 是共同风格与边界，主题 Prompt 是逐技能外观增量；只使用主题 Prompt 不能证明动作阶段、轮廓和锚点构图正确。用户点名单技能 Prompt 时，只能在绑定主题 `AGENTS.md` 和同名职业 Prompt 后，于对应资源/帧白名单内提升该技能 Prompt 优先级，不能替代全量 Prompt 包。路由证据必须记录主题 `AGENTS.md`、Prompt 文件快照和合成哈希；纯调色配置、endpoint recolor 或构建摘要中的文件引用不等同于 Prompt 已驱动图像生成或 Aseprite 修改。

## 五、冲突处理

1. 根规则决定完整性与安全。
2. manifest 决定资源身份和映射事实。
3. 职业规则/Prompt 决定职业稳定语义。
4. 主题规则/Prompt 只决定具体外观。
5. 用户决定目标与部署授权。

任何必要事实未解决时，记录缺口并停止依赖它的构建或覆盖声明。
