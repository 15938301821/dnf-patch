/**
 * @fileoverview 集中声明浏览器客户端与后端、同契约 Mock API 之间的传输结构。
 *
 * 这些 DTO（API 传输结构）由服务端或 Mock 生产，API、页面和 Store 消费；它们不是数据库
 * 行，也不应被组件任意扩展。本文件只有类型输出、无运行时副作用；读取模型配置必须保持
 * 脱敏，认证凭据不得进入用户 ViewModel，职业与技能稳定 ID 始终以后端响应为事实源。
 */

/** 当前会话可展示的脱敏用户 DTO，不包含 Token、密码或权限实现细节。 */
export interface SessionUser {
  id: string;
  username: string;
  displayName: string;
}

/** 登录或刷新成功响应；Access Token 只能交给内存 Token Store。 */
export interface AuthSession {
  accessToken: string;
  user: SessionUser;
}

/** 登录表单提交给认证端点的一次性写入 DTO，不得持久化。 */
export interface LoginInput {
  username: string;
  password: string;
}

/** 单个固定模型角色的脱敏读取 ViewModel。 */
export interface ModelRoleConfiguration {
  endpoint: string;
  model: string;
  /** 仅表示服务端已有密钥，不表示客户端可读取或恢复密钥明文。 */
  keyConfigured: boolean;
}

/** 当前用户三个固定角色的脱敏模型配置读取 DTO。 */
export interface ModelConfiguration {
  orchestrator: ModelRoleConfiguration;
  spriteProcessor: ModelRoleConfiguration;
  referenceGenerator: ModelRoleConfiguration;
}

/** 单个模型角色的写入 DTO；API Key 只在用户主动保存或轮换时出现。 */
export interface SaveModelRoleConfigurationInput {
  endpoint: string;
  model: string;
  apiKey?: string;
}

/** 模型设置表单提交给当前用户专用端点的写入 DTO。 */
export interface SaveModelConfigurationInput {
  orchestrator: SaveModelRoleConfigurationInput;
  spriteProcessor: SaveModelRoleConfigurationInput;
  referenceGenerator: SaveModelRoleConfigurationInput;
}

/** 后端资源导入的来源模式，客户端只展示而不读取资源路径。 */
export type ResourceImportMode = "server-mirror" | "uploaded-manifest";
/** 后端资源导入流程对客户端公开的阶段。 */
export type ResourceImportStatus =
  "not-configured" | "idle" | "queued" | "running" | "failed";

/** 后端生产的资源导入状态 ViewModel，不包含本机或服务器绝对路径。 */
export interface ResourceImportOverview {
  mode: ResourceImportMode;
  status: ResourceImportStatus;
  resourceVersion?: string;
  resourceRootConfigured: boolean;
  lastImportedAt?: string;
  lastJobId?: string;
  message: string;
}

/** 创建资源导入任务后返回的排队记录摘要。 */
export interface ResourceImportJob {
  id: string;
  mode: ResourceImportMode;
  status: Exclude<ResourceImportStatus, "not-configured" | "idle">;
  createdAt: string;
}

/** 职业与风格对客户端公开的审核发布阶段。 */
export type PublishStatus = "private" | "pending" | "published" | "rejected";

/** 职业列表页消费的服务端摘要 DTO。 */
export interface ProfessionSummary {
  id: string;
  name: string;
  slug: string;
  styleCount: number;
  publishStatus: PublishStatus;
  updatedAt: string;
}

/** 新建职业表单提交的最小写入 DTO。 */
export interface CreateProfessionInput {
  name: string;
  slug: string;
}

/** 职业 Prompt 事实是否经过服务端复核。 */
export type SkillPromptStatus = "candidate" | "reviewed";
/** 技能到资源的映射是否经过受控工具链核验。 */
export type SkillMappingStatus = "unverified" | "verified";
/** 技能当前只可设计还是可进入制作任务。 */
export type SkillExecutionStatus = "draft-only" | "build-ready";

/** 后端职业目录生产的技能事实摘要；客户端不得自行发明或映射技能。 */
export interface ProfessionSkillSummary {
  id: string;
  professionId: string;
  displayName: string;
  promptStatus: SkillPromptStatus;
  mappingStatus: SkillMappingStatus;
  executionStatus: SkillExecutionStatus;
  professionPrompt?: ProfessionPromptDefinition;
  professionPromptSha256?: string;
}

/** 服务端维护的只读职业 Prompt 事实，主题编辑只能在其上追加视觉增量。 */
export interface ProfessionPromptDefinition {
  schemaVersion: 1;
  stableSemantics: string;
  commonPrompt: string;
  sourceConstraints: string;
  stageAcceptance: string;
}

/** 主题定义中的命名十六进制色值。 */
export interface ThemeColorAnchor {
  name: string;
  value: string;
}

/** 所有已选技能共享的结构化主题规则。 */
export interface ThemeDefinition {
  schemaVersion: 1;
  goal: string;
  baseStyle: string;
  colorAnchors: ThemeColorAnchor[];
  materialRules: string;
  particleRules: string;
  layeringRules: string;
  constraints: string;
  acceptanceCriteria: string;
  exclusions: string;
}

/** 与一个稳定技能 ID 一一对应的主题视觉增量。 */
export interface SkillThemePrompt {
  skillId: string;
  themePrompt: string;
  changes: string;
  acceptanceCriteria: string;
  exclusions: string;
}

/** 服务端返回并供页面展示的完整职业风格 DTO。 */
export interface ProfessionStyle {
  id: string;
  professionId: string;
  name: string;
  description: string;
  themeDefinition: ThemeDefinition;
  selectedSkillIds: string[];
  skillPrompts: SkillThemePrompt[];
  publishStatus: PublishStatus;
  updatedAt: string;
}

/** 新建或保存私有职业风格时提交的结构化写入 DTO。 */
export interface SaveProfessionStyleInput {
  name: string;
  description: string;
  themeDefinition: ThemeDefinition;
  selectedSkillIds: string[];
  skillPrompts: SkillThemePrompt[];
}

/** 新建风格当前与保存风格共享同一写入结构。 */
export type CreateProfessionStyleInput = SaveProfessionStyleInput;

/** 制作任务对客户端公开的调度与终态集合。 */
export type PatchTaskStatus =
  "queued" | "running" | "passed" | "failed" | "blocked";

/** 任务列表消费的制作任务 ViewModel，不包含执行命令或本机路径。 */
export interface PatchTask {
  id: string;
  professionName: string;
  styleName: string;
  status: PatchTaskStatus;
  progress: number;
  createdAt: string;
  artifactName?: string;
  artifactAvailable: boolean;
}

/** 已验证产物的只读元数据引用，不包含产物字节或公开下载地址。 */
export interface PatchTaskArtifact {
  artifactName: string;
  storageKey: string;
  mediaType: string;
  byteLength: number;
  sha256: string;
}

/** 创建制作任务时引用后端稳定职业与风格 ID 的声明式 DTO。 */
export interface CreatePatchTaskInput {
  professionId: string;
  styleId: string;
}

/** 所有类型化 API 成功响应共用的数据包络。 */
export interface ApiEnvelope<T> {
  data: T;
}
