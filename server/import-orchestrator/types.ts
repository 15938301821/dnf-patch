import type {
  FileSnapshot,
  ImportDesign,
  ImportOutline,
  ImportPlan,
  ImportTaskGraph,
} from "../shared/contracts.js";

/** 导入模型编排器与来源准备器共享的数据边界。 */
export interface ImportSource {
  relativePath: string;
  absolutePath: string;
  snapshot: FileSnapshot;
  temporary: boolean;
}

/** 完成模型规划后交给事务写入器的冻结产物。 */
export interface ImportModelArtifacts {
  taskGraph: ImportTaskGraph;
  outline: ImportOutline;
  plan: ImportPlan;
  design: ImportDesign;
  contextPath: string;
  contextSha256: string;
  targetSnapshots: ReadonlyMap<string, FileSnapshot | undefined>;
  authoritySnapshots: readonly FileSnapshot[];
  modelEvidenceEligible: boolean;
}
