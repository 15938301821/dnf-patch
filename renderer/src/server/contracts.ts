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

/** 文本模型允许用户选择的六档推理强度。 */
export type SelectableModelReasoningEffort =
  "low" | "medium" | "high" | "xhigh" | "max" | "ultra";

/** 单个固定模型角色的推理强度；default 仅兼容图片角色和历史服务端记录。 */
export type ModelReasoningEffort = "default" | SelectableModelReasoningEffort;

export interface ModelRoleConfiguration {
  endpoint: string;
  model: string;
  /** 文本角色使用六档显式值；default 仅用于不消费该参数的图片角色。 */
  reasoningEffort: ModelReasoningEffort;
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
  reasoningEffort: ModelReasoningEffort;
  apiKey?: string;
}

/** 模型设置表单提交给当前用户专用端点的写入 DTO。 */
export interface SaveModelConfigurationInput {
  orchestrator: SaveModelRoleConfigurationInput;
  spriteProcessor: SaveModelRoleConfigurationInput;
  referenceGenerator: SaveModelRoleConfigurationInput;
}

/** 后端固定的只读资源镜像模式；客户端只展示状态，不读取资源路径。 */
export type ResourceImportMode = "server-mirror";
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

/** 详情页统一使用的阶段状态；unknown 表示服务端缺少精确历史证据，客户端不得猜测。 */
export type PatchTaskStepStatus =
  "pending" | "running" | "passed" | "failed" | "blocked" | "unknown";

/** 任务级工作流的四个固定阶段，由服务端按持久化证据映射。 */
export type PatchTaskWorkflowStageKey =
  "planning" | "skill-production" | "package-validation" | "complete";

/** 顶层工作流一个阶段的脱敏 ViewModel，不包含 Job、Worker 或租约标识。 */
export interface PatchTaskWorkflowStage {
  key: PatchTaskWorkflowStageKey;
  status: PatchTaskStepStatus;
}

/** 单技能生产链的四个固定阶段，前两项为模型阶段、后两项为受控工具阶段。 */
export type PatchTaskSkillStageKey =
  | "engineer-plan"
  | "reference-image"
  | "aseprite-adaptation"
  | "runtime-validation";

/** 单技能固定阶段的服务端证据状态。 */
export interface PatchTaskSkillStage {
  key: PatchTaskSkillStageKey;
  status: PatchTaskStepStatus;
}

/** 详情页一个技能的当前 attempt 进度；参考图标记不包含 Artifact ID 或授权 URL。 */
export interface PatchTaskSkillProgress {
  skillId: string;
  displayName: string;
  status: PatchTaskStepStatus;
  stages: PatchTaskSkillStage[];
  errorCode?: string;
  referenceImageAvailable: boolean;
}

/** 浏览器可展示的固定模型角色；unknown 用于保守承接异常历史值。 */
export type PatchTaskModelRole =
  "orchestrator" | "engineer" | "artist" | "unknown";

/** 模型调用的脱敏审计状态，不携带 Provider 响应正文或错误详情。 */
export type PatchTaskModelCallStatus =
  "running" | "passed" | "failed" | "blocked" | "abandoned" | "unknown";

/** 最近模型调用的趋势样本；nullable 计量表示 Provider 未返回可靠 usage。 */
export interface PatchTaskModelCallSample {
  id: string;
  role: PatchTaskModelRole;
  model: string;
  status: PatchTaskModelCallStatus;
  createdAt: string;
  finishedAt?: string;
  inputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
  providerLatencyMs: number | null;
  outputTokensPerSecond: number | null;
}

/** 按固定角色和模型聚合的吞吐分组，用于详情页横向比较。 */
export interface PatchTaskModelGroup {
  role: PatchTaskModelRole;
  model: string;
  calls: number;
  measuredCalls: number;
  inputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
  averageOutputTokensPerSecond: number | null;
  averageProviderLatencyMs: number | null;
}

/** 任务级模型吞吐摘要；计量覆盖率与调用成功率的分母不同，界面不得混用。 */
export interface PatchTaskModelThroughput {
  totalCalls: number;
  egressCalls: number;
  runningCalls: number;
  measuredCalls: number;
  successRate: number | null;
  inputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
  averageOutputTokensPerSecond: number | null;
  averageProviderLatencyMs: number | null;
  groups: PatchTaskModelGroup[];
  recentCalls: PatchTaskModelCallSample[];
}

/** 服务端为任务详情页整理的完整 ViewModel，不包含 Prompt、模型凭据、对象 key 或短期 URL。 */
export interface PatchTaskDetail extends PatchTask {
  updatedAt: string;
  finishedAt?: string;
  currentStage: PatchTaskWorkflowStageKey;
  totalSkills: number;
  passedSkills: number;
  workflow: PatchTaskWorkflowStage[];
  skills: PatchTaskSkillProgress[];
  packageStatus: "queued" | "building" | "passed" | "failed" | "blocked";
  modelThroughput: PatchTaskModelThroughput;
}

/** Package V3 固定产物角色；客户端只能使用服务端返回的角色，不能提交任意 Artifact ID。 */
export type PatchTaskArtifactRole = "candidate" | "manifest" | "validation";

/** 已验证产物的脱敏元数据，不包含内部对象 key、产物字节或下载授权。 */
export interface PatchTaskArtifact {
  artifactId: string;
  role: PatchTaskArtifactRole;
  artifactName: string;
  mediaType: string;
  byteLength: number;
  sha256: string;
}

/** 服务端为当前用户任务的固定角色签发的短期下载授权，URL 不得持久化。 */
export interface PatchTaskArtifactDownload extends PatchTaskArtifact {
  downloadUrl: string;
  expiresAtUtc: string;
}

/** 浏览器只能请求这三个固定技能预览角色，不能提交 Artifact ID、文件名或对象 key。 */
export type PatchTaskSkillPreviewRole =
  "source-frame" | "reference-image" | "aseprite-result";

/** 源帧与 Aseprite 结果共享的公开帧身份；像素摘要和本机路径不会下发到浏览器。 */
export interface PatchTaskSkillPreviewFrame {
  entryIndex: number;
  frameIndex: number;
  internalPath: string;
  width: number;
  height: number;
  canvasWidth: number;
  canvasHeight: number;
  x: number;
  y: number;
}

/** Worker 独立重读三类像素后由 Server 透传的 V2 参考 RGB 质量证据。 */
export interface PatchTaskReferenceTransferQuality {
  schemaVersion: 1;
  evaluatedFrameCount: number;
  evaluatedPixelCount: number;
  referenceCoverage: number;
  referenceSimilarity: number;
  sourceEdgeEnergy: number;
  runtimeEdgeEnergy: number;
  edgeEnergyRatio: number;
}

/** 当前 attempt 一个固定角色的脱敏 PNG 元数据；frame 仅存在于可审计的同帧角色。 */
export interface PatchTaskSkillPreview {
  artifactId: string;
  skillId: string;
  role: PatchTaskSkillPreviewRole;
  artifactName: string;
  mediaType: "image/png";
  byteLength: number;
  sha256: string;
  frame?: PatchTaskSkillPreviewFrame;
  referenceTransferQuality?: PatchTaskReferenceTransferQuality;
}

/** 服务端为固定技能预览角色签发的短期读取授权，URL 只供当前下载调用栈使用。 */
export interface PatchTaskSkillPreviewDownload extends PatchTaskSkillPreview {
  downloadUrl: string;
  expiresAtUtc: string;
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
