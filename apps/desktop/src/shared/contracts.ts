/**
 * 桌面应用共享契约的兼容入口。
 *
 * 消费方继续从本文件导入；具体 schema 按职责拆到叶模块。显式导出固定
 * 原有公共 API，内部基础约束不会意外成为主进程或 renderer 的依赖。
 */
export {
  contextBundleSchema,
  desktopStateSchema,
  fileSnapshotSchema,
  modelCapabilitySchema,
  modelRoleSchema,
  pipelineActionSchema,
  pipelineEventSchema,
  pipelineProviderSchema,
  runRequestSchema,
  runSummarySchema,
  startRunResponseSchema,
} from "./contracts/run.js";
export type {
  ContextBundle,
  DesktopState,
  FileSnapshot,
  ModelCapability,
  ModelRole,
  PipelineAction,
  PipelineEvent,
  PipelineProvider,
  RunRequest,
  RunSummary,
  StartRunResponse,
} from "./contracts/run.js";

export {
  engineeringDesignSchema,
  engineeringPlanSchema,
  engineeringStepSchema,
  imageAttemptSchema,
  modelCallRecordSchema,
  promptBindingSchema,
  solTaskGraphSchema,
  styleOperationSchema,
  taskNodeSchema,
} from "./contracts/patch-model.js";
export type {
  EngineeringDesign,
  EngineeringPlan,
  ImageAttempt,
  ModelCallRecord,
  SolTaskGraph,
} from "./contracts/patch-model.js";

export {
  importDesignSchema,
  importFileProposalSchema,
  importOutlineSchema,
  importPlanSchema,
  importPromptSemanticSchema,
  importProposalSchema,
  importTaskGraphSchema,
  importTransactionReceiptSchema,
  promptTreeResultSchema,
} from "./contracts/import-pipeline.js";
export type {
  ImportDesign,
  ImportOutline,
  ImportPlan,
  ImportProposal,
  ImportTaskGraph,
  ImportTransactionReceipt,
  PromptTreeResult,
} from "./contracts/import-pipeline.js";

export {
  bpkEntrySchema,
  bpkManifestSchema,
  toolInvocationSchema,
  toolResultSchema,
} from "./contracts/tool-delivery.js";
export type {
  BpkManifest,
  ToolInvocation,
  ToolResult,
} from "./contracts/tool-delivery.js";
