import type { ContextBundle, FileSnapshot } from "../shared/contracts.js";
import { snapshotFile, snapshotMetadata } from "../lib/filesystem.js";

/** 导入模型与事务必须共同绑定的稳定契约文件。 */
const PROMPT_CONTRACT =
  ".github/skills/dnf-patch-maker/references/prompt-contract.md";
const ROUTING_CONTRACT =
  ".github/skills/dnf-patch-maker/references/routing-and-domain-contract.md";
const DECOMPOSITION_CONTRACT =
  ".github/skills/dnf-import-profession-text/references/source-decomposition-contract.md";
const IMPORT_TOOL_PATHS = [
  "tools/Invoke-DnfCatalogTool.ps1",
  ".github/skills/dnf-import-profession-text/scripts/Inspect-DnfProfessionText.ps1",
  ".github/skills/dnf-import-profession-text/scripts/Test-DnfImportPlan.ps1",
  ".github/skills/dnf-import-profession-text/scripts/Test-DnfPromptTree.ps1",
] as const;

export interface ImportAuthority {
  promptContract: FileSnapshot;
  routingContract: FileSnapshot;
  decompositionContract: FileSnapshot;
  hostScript: FileSnapshot;
  inspectScript: FileSnapshot;
  planScript: FileSnapshot;
  authoritySnapshots: readonly FileSnapshot[];
}

/** 收集上下文中的现行规则、manifest、索引和 Prompt 权威快照。 */
function contextAuthoritySnapshots(context: ContextBundle): FileSnapshot[] {
  return [
    context.rootRules,
    context.patchMakerSkill,
    ...(context.importSkill ? [context.importSkill] : []),
    ...(context.professionRules ? [context.professionRules] : []),
    ...(context.manifest ? [context.manifest] : []),
    ...(context.professionPromptIndex ? [context.professionPromptIndex] : []),
    ...context.professionPrompts,
    ...(context.themeRules ? [context.themeRules] : []),
    ...(context.themePromptIndex ? [context.themePromptIndex] : []),
    ...context.themePrompts,
    context.toolCatalog,
  ];
}

/**
 * 冻结导入所依赖的规则与固定工具。
 *
 * 返回的工具哈希会传给 broker 做执行前 CAS，authoritySnapshots 则写入
 * transaction receipt，确保模型规划和最终提交引用同一组权威字节。
 */
export async function freezeImportAuthority(
  repositoryRoot: string,
  context: ContextBundle,
): Promise<ImportAuthority> {
  const [promptContract, routingContract, decompositionContract] =
    await Promise.all([
      snapshotFile(
        repositoryRoot,
        PROMPT_CONTRACT,
        "Prompt structure contract",
      ),
      snapshotFile(
        repositoryRoot,
        ROUTING_CONTRACT,
        "Routing and domain contract",
      ),
      snapshotFile(
        repositoryRoot,
        DECOMPOSITION_CONTRACT,
        "Source decomposition contract",
      ),
    ]);
  const importToolSnapshots = await Promise.all(
    IMPORT_TOOL_PATHS.map((path) =>
      snapshotFile(repositoryRoot, path, `Import tool: ${path}`, false),
    ),
  );
  const importTools = new Map(
    importToolSnapshots.map((snapshot) => [snapshot.path, snapshot]),
  );
  const hostScript = importTools.get(IMPORT_TOOL_PATHS[0]);
  const inspectScript = importTools.get(IMPORT_TOOL_PATHS[1]);
  const planScript = importTools.get(IMPORT_TOOL_PATHS[2]);
  if (!hostScript || !inspectScript || !planScript) {
    throw new Error("Import tool authority snapshots are incomplete.");
  }

  return {
    promptContract,
    routingContract,
    decompositionContract,
    hostScript,
    inspectScript,
    planScript,
    authoritySnapshots: [
      ...contextAuthoritySnapshots(context),
      promptContract,
      routingContract,
      decompositionContract,
      ...importToolSnapshots,
    ].map(snapshotMetadata),
  };
}
