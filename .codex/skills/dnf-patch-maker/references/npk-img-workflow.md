# NPK/IMG 中文稳定工作流

## 一、盘点

1. 哈希并固化源包和已知正确基线。
2. 读取 NPK magic、索引、内部路径、offset、size 和头部哈希。
3. 读取每个 IMG magic/version 并路由到版本 handler。
4. 盘点帧、LINK、Hidden、几何、Canvas、偏移、压缩、Texture、图集、旋转和共享关系。
5. 区分职业特效、人物层、武器、Cut-in 和共享资源。

## 二、计划

1. 从 manifest 选择用户要求的条目。
2. 应用职业 include/exclude。
3. 只对剩余获准帧应用主题。
4. 修改前记录期望路径、帧、元数据和像素差异。

## 三、逐帧素材流水线

任务涉及 AI、外部图像服务或批量重绘时，先读取 `frame-redraw-and-adapter-contract.md`：

1. 从 inventory 导出并冻结 source 帧及结构 sidecar，不按显示名猜目录或帧序。
2. 使用新的 runId 建立运行计划，记录分组、模型/适配器、Prompt 哈希、每帧 seed、输入输出尺寸和外部工具 provenance。
3. 把原始生成、Photoshop 适配和 runtime 输入分目录保存；生成服务不得直接写 NPK。
4. runtime 帧逐项满足目标 handler 的尺寸、alpha、色彩和载荷输入契约后，才进入构建。

## 四、构建

1. 使用只读输入和新的临时输出。
2. 未授权条目和帧在解码后逐字节保持不变。
3. 除非 manifest 明确允许，保留几何、阶段、alpha 和版本专有关系。
4. 保存并关闭临时文件，再从磁盘重新验证。
5. 所有硬门禁通过后才原子更新工作区最终产物。

## 五、修复

- 比较故障产物、正确基线和源 inventory。
- 找到解释故障的最小结构或像素差异。
- 只在新产物中修复声明集合。
- 不把黑色转透明、IMG 转版本或纹理转格式当作通用修复。

## 六、封装

发布产物和回滚基线分开存放。生成机器可读报告，不依赖 README 中手写且易漂移的数量和哈希。

完整发布使用两阶段闭环：先在新的空目录生成 final summary，再从通过的摘要更新 manifest/release，随后运行 `tools/Test-DnfReleaseClosure.ps1` 和 `tools/Test-DnfProjectGate.ps1`。final summary 记录的工具或来源变化后必须新建验证目录重跑。
