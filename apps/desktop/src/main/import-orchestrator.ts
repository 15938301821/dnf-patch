import { basename } from "node:path";
import type { ZodType } from "zod";
import {
  importDesignSchema,
  importOutlineSchema,
  importPlanSchema,
  importTaskGraphSchema,
  type ContextBundle,
  type FileSnapshot,
  type ImportDesign,
  type ImportOutline,
  type ImportPlan,
  type ImportTaskGraph,
  type ModelCallRecord,
  type RunRequest,
  type ToolResult,
} from "../shared/contracts.js";
import { AgentModelProvider } from "./model-provider.js";
import type { RunStore } from "./run-store.js";
import { parseJsonOutput } from "./tool-broker.js";
import type { ToolBroker } from "./tool-broker.js";
import {
  fileExists,
  resolveInside,
  snapshotMetadata,
  snapshotFile,
  stableStringify,
} from "./lib/filesystem.js";

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

interface StoredModelValue<T> {
  value: T;
  valuePath: string;
  valueSnapshot: FileSnapshot;
  record: ModelCallRecord;
  recordPath: string;
  recordSnapshot: FileSnapshot;
}

export interface ImportSource {
  relativePath: string;
  absolutePath: string;
  snapshot: FileSnapshot;
  temporary: boolean;
}

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

function assertPassedTool(result: ToolResult, label: string): void {
  if (result.status !== "passed" || result.exitCode !== 0) {
    throw new Error(result.error ?? `${label} failed.`);
  }
}

function canonicalName(value: string): string {
  return value.normalize("NFC").toLocaleLowerCase();
}

function promptTitle(snapshot: FileSnapshot): string {
  const match = /^#[ \t]+(?<title>.+?)[ \t]*$/mu.exec(snapshot.content ?? "");
  const title = match?.groups?.title?.trim();
  if (!title) {
    throw new Error(`Existing prompt has no single H1 title: ${snapshot.path}`);
  }
  return title;
}

function indexFileNames(content: string | undefined): string[] {
  if (!content) {
    return [];
  }
  const lines = content.split(/\r\n|\n|\r/u);
  const result: string[] = [];
  let inCurrentFiles = false;
  let fence: string | undefined;
  for (const line of lines) {
    if (fence) {
      if (
        new RegExp(
          `^[ ]{0,3}${fence[0] === "`" ? "`" : "~"}{${String(fence.length)},}[ \\t]*$`,
          "u",
        ).test(line)
      ) {
        fence = undefined;
      }
      continue;
    }
    const fenceMatch = /^[ ]{0,3}(?<fence>`{3,}|~{3,})/u.exec(line);
    if (fenceMatch?.groups?.fence) {
      fence = fenceMatch.groups.fence;
      continue;
    }
    const heading = /^##[ \t]+(?<title>.+?)[ \t]*$/u.exec(line)?.groups?.title;
    if (heading) {
      const normalized = heading
        .replace(/^\s*[\u4e00-\u9fff0-9]+[\u3001.\uff0e]\s*/u, "")
        .trim();
      if (inCurrentFiles) {
        break;
      }
      inCurrentFiles = normalized === "\u5f53\u524d\u6587\u4ef6";
      continue;
    }
    if (!inCurrentFiles) {
      continue;
    }
    const codeEntry = /^\s*[-*+]\s+`(?<path>[^`]+\.md)`\s*$/iu.exec(line)
      ?.groups?.path;
    const linkEntry = /^\s*[-*+]\s+\[[^\]]+\]\((?<path>[^)]+\.md)\)\s*$/iu.exec(
      line,
    )?.groups?.path;
    const entry = codeEntry ?? linkEntry;
    if (entry && !entry.includes("/") && !entry.includes("\\")) {
      result.push(entry);
    }
  }
  return result;
}

function existingPromptNames(context: ContextBundle): string[] {
  const snapshots = new Map(
    context.professionPrompts.map((snapshot) => [
      canonicalName(basename(snapshot.path)),
      snapshot,
    ]),
  );
  const ordered: FileSnapshot[] = [];
  const seen = new Set<string>();
  for (const fileName of indexFileNames(
    context.professionPromptIndex?.content,
  )) {
    const key = canonicalName(fileName);
    const snapshot = snapshots.get(key);
    if (!snapshot || seen.has(key)) {
      continue;
    }
    seen.add(key);
    ordered.push(snapshot);
  }
  for (const snapshot of context.professionPrompts) {
    const key = canonicalName(basename(snapshot.path));
    if (!seen.has(key)) {
      seen.add(key);
      ordered.push(snapshot);
    }
  }
  return ordered.map(promptTitle);
}

function existingThemePromptNames(context: ContextBundle): string[] {
  const professionByFileName = new Map(
    context.professionPrompts.map((snapshot) => [
      canonicalName(basename(snapshot.path)),
      promptTitle(snapshot),
    ]),
  );
  const themeByFileName = new Map(
    context.themePrompts.map((snapshot) => [
      canonicalName(basename(snapshot.path)),
      snapshot,
    ]),
  );
  const orderedFileNames = [
    ...indexFileNames(context.themePromptIndex?.content),
    ...context.themePrompts.map((snapshot) => basename(snapshot.path)),
  ];
  const result: string[] = [];
  const seen = new Set<string>();
  for (const fileName of orderedFileNames) {
    const key = canonicalName(fileName);
    if (seen.has(key) || !themeByFileName.has(key)) {
      continue;
    }
    const professionName = professionByFileName.get(key);
    if (!professionName) {
      throw new Error(
        `Existing theme Prompt has no same-name profession Prompt: ${fileName}`,
      );
    }
    seen.add(key);
    result.push(professionName);
  }
  return result;
}

function sourceCandidateNames(
  request: RunRequest,
  sourceText: string,
): string[] {
  const candidates =
    request.selectedSkills.length > 0
      ? request.selectedSkills
      : [...sourceText.matchAll(/^#{2,4}[ \t]+(?<name>.+?)[ \t]*$/gmu)]
          .map((match) => match.groups?.name?.trim())
          .filter((name): name is string => Boolean(name))
          .slice(0, 32);
  return candidates
    .map((candidate) =>
      candidate
        .replace(/^\s*[0-9]+[.\u3001]\s*/u, "")
        .replace(/\s+[-\u2013\u2014].*$/u, "")
        .trim(),
    )
    .filter((candidate) => candidate.length > 0);
}

function inferredMockNames(
  request: RunRequest,
  sourceText: string,
  existingNames: string[],
): string[] {
  const result = [...existingNames];
  const seen = new Set(result.map(canonicalName));
  for (const candidate of sourceCandidateNames(request, sourceText)) {
    if (seen.has(canonicalName(candidate))) {
      continue;
    }
    seen.add(canonicalName(candidate));
    result.push(candidate);
  }
  if (result.length === 0) {
    result.push("Mock planning entry");
  }
  return result;
}

function mockTaskGraph(request: RunRequest): ImportTaskGraph {
  return importTaskGraphSchema.parse({
    schemaVersion: 1,
    runId: request.runId,
    workflow: "profession-text-import",
    orderedSteps: [
      "inspect-source",
      "extract-prompt-outline",
      "compute-fixed-targets",
      "propose-fixed-target-content",
      "write-whitelisted-targets",
      "validate-prompt-tree",
      "rollback-on-failure",
    ],
    controls: {
      modelMayChoosePaths: false,
      modelMayCreateOrModifyManifest: false,
      modelMayBuildNpk: false,
      modelMayDeploy: false,
      preserveSourceBytes: true,
      rollbackTargetBytesOnFailure: true,
    },
  });
}

function mockOutline(
  request: RunRequest,
  sourceText: string,
  existingNames: string[],
  existingThemeNames: string[],
): ImportOutline {
  const promptDisplayNames = inferredMockNames(
    request,
    sourceText,
    existingNames,
  );
  const promptKeys = new Set(promptDisplayNames.map(canonicalName));
  const themePromptDisplayNames =
    request.action === "create-theme"
      ? inferredMockNames(request, sourceText, existingThemeNames).filter(
          (name) => promptKeys.has(canonicalName(name)),
        )
      : [];
  return importOutlineSchema.parse({
    schemaVersion: 1,
    runId: request.runId,
    profession: request.profession,
    ...(request.theme ? { theme: request.theme } : {}),
    promptDisplayNames,
    themePromptDisplayNames,
    classificationSummary: {
      professionStableSemantics: [
        "Mock-only classification; it is not eligible for repository writes.",
      ],
      themeVisualIncrements: request.theme
        ? ["Mock-only theme classification; no image model was invoked."]
        : [],
      rejectedResourceOrCoverageClaims: [],
    },
    requiresTheme: request.action === "create-theme",
    unresolvedConflicts: [],
  });
}

function mockDesign(
  request: RunRequest,
  names: string[],
  themeNames: string[],
): ImportDesign {
  const themeKeys = new Set(themeNames.map(canonicalName));
  return importDesignSchema.parse({
    schemaVersion: 1,
    runId: request.runId,
    profession: request.profession,
    ...(request.theme ? { theme: request.theme } : {}),
    professionRules: {
      responsibilitiesAndBoundaries: "仅用于 mock 规划，不能用于仓库写入。",
      resourceFactAuthority: "资源身份仍待 manifest 与 inventory 核验。",
      promptLayering: "仅在路由核验后组合职业语义、主题规则与同名主题增量。",
      characterEffectWeaponCutinBoundary:
        "在 inventory 证明分类前保留既有人物、特效、武器与 Cut-in 边界。",
      acceptanceAndRegression:
        "既有运动、轮廓、阶段辨识、几何与 alpha 必须保持可复核。",
      coverageStatus: "Prompt 数量不能证明全技能覆盖，覆盖状态仍未证明。",
    },
    ...(request.theme
      ? {
          themeRules: {
            objective: "仅用于 mock 规划的主题目标，不能用于仓库写入。",
            paletteMaterialsAndStyle:
              "色板、材质与风格决策仅限输入设计来源明确支持的范围。",
            promptRouting:
              "先加载职业稳定语义，再加载主题共同规则与同名逐技能增量。",
            modificationScopeAndBoundaries:
              "不得新增资源、帧、图层、部署权限或 manifest 权威。",
            acceptanceAndRegression: "复核每个既有阶段，拒绝轮廓或源语义丢失。",
          },
        }
      : {}),
    prompts: names.map((displayName) => ({
      displayName,
      professionStableSemantics:
        "仅用于 mock 的稳定语义，仍待真实 GPT-5.5 导入调用。",
      professionEnglishPrompt:
        "Preserve the source action silhouette, timing, anchors, layers, and phase readability.",
      sourceConstraints:
        "在 inventory 核验前保留源几何、alpha、人物、特效、武器与 Cut-in 边界。",
      phaseAcceptance: "复核来源明确给出的全部动作阶段，不推断缺失的资源事实。",
      ...(themeKeys.has(canonicalName(displayName))
        ? {
            theme: {
              englishIncrement:
                "Apply only the supplied theme language while preserving the inherited action semantics.",
              changes: "仅用于 mock 的主题变化，仍待真实 GPT-5.5 导入调用。",
              acceptance: "既有动作与来源明确给出的主题线索均保持可辨识。",
              exclusions: "不得新增资源或删除源资源中的合法内容。",
            },
          }
        : {}),
    })),
    rejectedResourceClaims: [],
    rejectedProcessClaims: [],
    inventoryPending: true,
    manifestCreatedOrModified: false,
    npkBuilt: false,
    deploymentPerformed: false,
  });
}

function assertOutline(
  outline: ImportOutline,
  request: RunRequest,
  existingNames: string[],
  existingThemeNames: string[],
): void {
  if (
    outline.runId !== request.runId ||
    outline.profession !== request.profession ||
    outline.theme !== request.theme
  ) {
    throw new Error(
      "Import outline route does not match the fixed Run request.",
    );
  }
  if (outline.requiresTheme !== (request.action === "create-theme")) {
    throw new Error(
      "Import outline theme requirement does not match the action.",
    );
  }
  if (outline.unresolvedConflicts.length > 0) {
    throw new Error(
      `Import outline contains unresolved conflicts: ${outline.unresolvedConflicts.join(" | ")}`,
    );
  }
  for (let index = 0; index < existingNames.length; index += 1) {
    if (outline.promptDisplayNames[index] !== existingNames[index]) {
      throw new Error(
        "Import outline must preserve the complete existing profession prompt order as an exact prefix.",
      );
    }
  }
  const assertUnique = (names: string[], label: string): void => {
    const seen = new Set<string>();
    for (const name of names) {
      const key = canonicalName(name);
      if (seen.has(key)) {
        throw new Error(`${label} contains a duplicate display name: ${name}`);
      }
      seen.add(key);
    }
  };
  assertUnique(outline.promptDisplayNames, "Import outline");
  assertUnique(outline.themePromptDisplayNames, "Theme import outline");
  for (let index = 0; index < existingThemeNames.length; index += 1) {
    if (outline.themePromptDisplayNames[index] !== existingThemeNames[index]) {
      throw new Error(
        "Import outline must preserve the complete existing theme prompt order as an exact prefix.",
      );
    }
  }
  if (
    (request.action === "create-profession" &&
      outline.themePromptDisplayNames.length > 0) ||
    (request.action === "create-theme" &&
      outline.themePromptDisplayNames.length === 0)
  ) {
    throw new Error(
      "Import outline theme prompt subset does not match the action.",
    );
  }
  const professionIndex = new Map(
    outline.promptDisplayNames.map((name, index) => [
      canonicalName(name),
      index,
    ]),
  );
  let previousIndex = -1;
  for (const name of outline.themePromptDisplayNames) {
    const index = professionIndex.get(canonicalName(name));
    if (index === undefined || index <= previousIndex) {
      throw new Error(
        "Theme prompt outline must be an ordered subset of the profession prompt outline.",
      );
    }
    previousIndex = index;
  }
  if (request.selectedSkills.length > 0) {
    const merge = (existing: string[]): string[] => {
      const result = [...existing];
      const keys = new Set(result.map(canonicalName));
      for (const name of request.selectedSkills) {
        if (!keys.has(canonicalName(name))) {
          keys.add(canonicalName(name));
          result.push(name);
        }
      }
      return result;
    };
    const expectedProfession = merge(existingNames);
    if (
      stableStringify(outline.promptDisplayNames) !==
      stableStringify(expectedProfession)
    ) {
      throw new Error(
        "Import outline differs from the explicitly selected profession skills.",
      );
    }
    if (request.action === "create-theme") {
      const selectedKeys = new Set(request.selectedSkills.map(canonicalName));
      const expectedTheme = merge(existingThemeNames).filter(
        (name) =>
          existingThemeNames.some(
            (existing) => canonicalName(existing) === canonicalName(name),
          ) || selectedKeys.has(canonicalName(name)),
      );
      if (
        stableStringify(outline.themePromptDisplayNames) !==
        stableStringify(expectedTheme)
      ) {
        throw new Error(
          "Theme import outline differs from the explicitly selected theme skills.",
        );
      }
    }
  }
}

function assertPlan(
  plan: ImportPlan,
  request: RunRequest,
  outline: ImportOutline,
  source: ImportSource,
): void {
  const theme = request.theme;
  if (plan.status !== "passed" || plan.errors.length > 0) {
    throw new Error("The fixed import planner did not return passed status.");
  }
  if (
    plan.route.profession !== request.profession ||
    plan.route.theme !== (request.theme ?? null) ||
    plan.source.sha256 !== source.snapshot.sha256
  ) {
    throw new Error("Import plan route or source hash does not match the Run.");
  }
  if (
    plan.prompts.length !== outline.promptDisplayNames.length ||
    plan.prompts.some(
      (prompt, index) =>
        prompt.displayName !== outline.promptDisplayNames[index],
    )
  ) {
    throw new Error("Import plan prompt order differs from the model outline.");
  }
  if (
    plan.themePrompts.length !== outline.themePromptDisplayNames.length ||
    plan.themePrompts.some(
      (prompt, index) =>
        prompt.displayName !== outline.themePromptDisplayNames[index],
    )
  ) {
    throw new Error(
      "Import plan theme prompt order differs from the model outline.",
    );
  }
  const expected = new Set<string>([
    `${request.profession}/AGENTS.md`,
    `${request.profession}/prompts/README.md`,
    ...plan.prompts.map(
      (prompt) => `${request.profession}/prompts/${prompt.fileName}`,
    ),
    ...(theme
      ? [
          `${request.profession}/${theme}/AGENTS.md`,
          `${request.profession}/${theme}/prompts/README.md`,
          ...plan.themePrompts.map(
            (prompt) =>
              `${request.profession}/${theme}/prompts/${prompt.fileName}`,
          ),
        ]
      : []),
  ]);
  const actual = new Set(plan.targets.map((target) => target.relativePath));
  if (
    expected.size !== actual.size ||
    [...expected].some((path) => !actual.has(path)) ||
    [...actual].some((path) => !expected.has(path))
  ) {
    throw new Error("Import planner returned an unexpected target whitelist.");
  }
  if (
    [...actual].some(
      (path) =>
        path.toLocaleLowerCase().endsWith("/manifest.json") ||
        path.toLocaleLowerCase().includes("/npk/") ||
        path.toLocaleLowerCase().includes("/validation/"),
    )
  ) {
    throw new Error("Import target whitelist contains a forbidden artifact.");
  }
}

function assertDesign(
  design: ImportDesign,
  request: RunRequest,
  plan: ImportPlan,
): void {
  if (
    design.runId !== request.runId ||
    design.profession !== request.profession ||
    design.theme !== request.theme
  ) {
    throw new Error(
      "Import design route does not match the fixed Run request.",
    );
  }
  if (Boolean(design.themeRules) !== Boolean(request.theme)) {
    throw new Error("Import design theme rules do not match the fixed route.");
  }
  if (design.prompts.length !== plan.prompts.length) {
    throw new Error("Import design does not cover every fixed prompt target.");
  }
  const themePromptKeys = new Set(
    plan.themePrompts.map((prompt) => canonicalName(prompt.displayName)),
  );
  for (const [index, promptPlan] of plan.prompts.entries()) {
    const expected = promptPlan.displayName;
    const actual = design.prompts[index];
    if (actual === undefined) {
      throw new Error(`Import design is missing prompt ${expected}.`);
    }
    if (actual.displayName !== expected) {
      throw new Error(
        `Import design prompt order mismatch: ${actual.displayName}/${expected}`,
      );
    }
    if (
      Boolean(actual.theme) !== themePromptKeys.has(canonicalName(expected))
    ) {
      throw new Error(
        `Import design theme content mismatch for ${actual.displayName}.`,
      );
    }
  }
}

export class ImportOrchestrator {
  readonly #provider: AgentModelProvider;

  constructor(
    readonly repositoryRoot: string,
    readonly store: RunStore,
    readonly broker: ToolBroker,
    request: RunRequest,
  ) {
    this.#provider = new AgentModelProvider(request);
  }

  async #storeStructured<T>(
    request: RunRequest,
    call: {
      runId: string;
      callId: string;
      role: "orchestrator" | "engineer";
      schemaName: string;
      schema: ZodType<T>;
      instructions: string;
      input: string;
      mockValue: T;
    },
    valueEvidencePath: string,
    recordEvidencePath: string,
  ): Promise<StoredModelValue<T>> {
    const result = await this.#provider.structured(call);
    const recordPath = await this.store.writeEvidence(
      request.runId,
      recordEvidencePath,
      result.record,
    );
    const recordSnapshot = await snapshotFile(
      this.repositoryRoot,
      recordPath,
      `Model call ${result.record.callId}`,
      false,
    );
    if (!result.value) {
      throw new Error(
        result.record.error ?? `Model call failed: ${call.callId}`,
      );
    }
    const valuePath = await this.store.writeEvidence(
      request.runId,
      valueEvidencePath,
      result.value,
    );
    const valueSnapshot = await snapshotFile(
      this.repositoryRoot,
      valuePath,
      `Model output ${result.record.callId}`,
      false,
    );
    return {
      value: result.value,
      valuePath,
      valueSnapshot,
      record: result.record,
      recordPath,
      recordSnapshot,
    };
  }

  async run(
    request: RunRequest,
    context: ContextBundle,
    source: ImportSource,
  ): Promise<ImportModelArtifacts> {
    const promptContract = await snapshotFile(
      this.repositoryRoot,
      PROMPT_CONTRACT,
      "Prompt structure contract",
    );
    const routingContract = await snapshotFile(
      this.repositoryRoot,
      ROUTING_CONTRACT,
      "Routing and domain contract",
    );
    const decompositionContract = await snapshotFile(
      this.repositoryRoot,
      DECOMPOSITION_CONTRACT,
      "Source decomposition contract",
    );
    const importToolSnapshots = await Promise.all(
      IMPORT_TOOL_PATHS.map((path) =>
        snapshotFile(this.repositoryRoot, path, `Import tool: ${path}`, false),
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
    const authoritySnapshots = [
      ...contextAuthoritySnapshots(context),
      promptContract,
      routingContract,
      decompositionContract,
      ...importToolSnapshots,
    ].map(snapshotMetadata);

    const inspectResult = await this.broker.invoke({
      invocation: {
        schemaVersion: 1,
        runId: request.runId,
        callId: "import.inspect-source",
        toolId: "import-profession-inspect",
        arguments: { SourcePath: source.relativePath },
        allowNetwork: false,
        execute: true,
      },
      expectedOutputs: [],
      expectedScriptSha256: inspectScript.sha256,
      expectedHostScriptSha256: hostScript.sha256,
    });
    assertPassedTool(inspectResult, "Import source inspection");
    const inspection = parseJsonOutput(inspectResult.stdout);
    const inspectionObject =
      inspection !== null && typeof inspection === "object"
        ? (inspection as Record<string, unknown>)
        : undefined;
    const inspectionSource =
      inspectionObject?.source !== null &&
      typeof inspectionObject?.source === "object"
        ? (inspectionObject.source as Record<string, unknown>)
        : undefined;
    if (inspectionSource?.sha256 !== source.snapshot.sha256) {
      throw new Error(
        "Import source inspection hash does not match the frozen source.",
      );
    }
    await this.store.writeEvidence(
      request.runId,
      "imports/source-inspection.json",
      inspection,
    );

    const existingNames = existingPromptNames(context);
    const existingThemeNames = existingThemePromptNames(context);
    const sourceText = source.snapshot.content ?? "";
    const importContext = {
      schemaVersion: 1,
      runId: request.runId,
      action: request.action,
      route: {
        profession: request.profession,
        ...(request.theme ? { theme: request.theme } : {}),
      },
      source: source.snapshot,
      sourceInspection: inspection,
      rootRules: context.rootRules,
      patchMakerSkill: context.patchMakerSkill,
      importSkill: context.importSkill,
      promptContract,
      routingContract,
      decompositionContract,
      existing: {
        professionRules: context.professionRules,
        manifest: context.manifest,
        professionPromptIndex: context.professionPromptIndex,
        professionPrompts: context.professionPrompts,
        themeRules: context.themeRules,
        themePromptIndex: context.themePromptIndex,
        themePrompts: context.themePrompts,
        professionPromptDisplayNamesInOrder: existingNames,
        themePromptDisplayNamesInOrder: existingThemeNames,
      },
      toolCatalog: context.toolCatalog,
      controls: {
        modelMayChoosePaths: false,
        modelMayCreateOrModifyManifest: false,
        modelMayBuildNpk: false,
        modelMayDeploy: false,
        fullSkillCoverageProven: false,
      },
    };
    const contextPath = await this.store.writeEvidence(
      request.runId,
      "context/import-context.json",
      importContext,
    );
    const contextSnapshot = await snapshotFile(
      this.repositoryRoot,
      contextPath,
      "Frozen import context",
      false,
    );
    const modelContext = stableStringify(importContext);

    const taskGraphResult = await this.#storeStructured(
      request,
      {
        runId: request.runId,
        callId: "import-sol-task-graph",
        role: "orchestrator",
        schemaName: "dnf_import_task_graph",
        schema: importTaskGraphSchema,
        instructions:
          "You are the controller for a DNF profession-text import. Return exactly the fixed workflow order required by the schema. Do not choose file paths, script paths, shell commands, resource mappings, manifest changes, NPK work, deployment, coverage, compatibility, or approval states. Preserve source bytes and require byte rollback on validation failure.",
        input: modelContext,
        mockValue: mockTaskGraph(request),
      },
      "models/import-sol-task-graph.json",
      "models/calls/import-sol-task-graph.json",
    );
    if (taskGraphResult.value.runId !== request.runId) {
      throw new Error("Import SOL task graph RunId mismatch.");
    }

    const outlineResult = await this.#storeStructured(
      request,
      {
        runId: request.runId,
        callId: "import-prompt-outline",
        role: "engineer",
        schemaName: "dnf_import_prompt_outline",
        schema: importOutlineSchema,
        instructions:
          "Extract a conservative import outline from the frozen source and contracts. promptDisplayNames is the complete final profession index order: preserve every existing profession prompt title as an exact prefix, then append only source-supported entries in source order. themePromptDisplayNames is an ordered subset of promptDisplayNames: preserve every existing theme prompt as an exact prefix, then append only entries with explicit theme evidence in this source. For create-profession it must be empty; for create-theme it must be nonempty. A display name is content, not a path; do not normalize it or add extensions. When selectedSkills is nonempty, it is the complete user-authorized set of source entries and you may not add or omit entries. Separate profession-stable motion and phase semantics from theme palette/material/particle/light increments. Resource names, frame mappings, coverage claims, build steps, deployment, compatibility and safety claims are rejected evidence only. Report every unresolved routing or source conflict; never guess.",
        input: modelContext,
        mockValue: mockOutline(
          request,
          sourceText,
          existingNames,
          existingThemeNames,
        ),
      },
      "models/import-prompt-outline.json",
      "models/calls/import-prompt-outline.json",
    );
    assertOutline(
      outlineResult.value,
      request,
      existingNames,
      existingThemeNames,
    );

    const planResult = await this.broker.invoke({
      invocation: {
        schemaVersion: 1,
        runId: request.runId,
        callId: "import.compute-fixed-targets",
        toolId: "import-profession-plan",
        arguments: {
          SourcePath: source.relativePath,
          ProfessionName: request.profession,
          ...(request.theme ? { ThemeName: request.theme } : {}),
          PromptName: outlineResult.value.promptDisplayNames,
          ThemePromptName: outlineResult.value.themePromptDisplayNames,
        },
        allowNetwork: false,
        execute: true,
      },
      expectedOutputs: [],
      expectedScriptSha256: planScript.sha256,
      expectedHostScriptSha256: hostScript.sha256,
    });
    if (planResult.status !== "passed" || planResult.exitCode !== 0) {
      let detail = planResult.error ?? "Fixed import planning failed.";
      try {
        const failedPlan = parseJsonOutput(planResult.stdout) as {
          errors?: { message?: string }[];
        };
        const messages = failedPlan.errors
          ?.map((issue) => issue.message)
          .filter((message): message is string => Boolean(message));
        if (messages && messages.length > 0) {
          detail = `${detail} ${messages.join(" | ")}`;
        }
      } catch {
        // The broker result remains the authoritative failure evidence.
      }
      throw new Error(detail);
    }
    const plan = importPlanSchema.parse(parseJsonOutput(planResult.stdout));
    assertPlan(plan, request, outlineResult.value, source);
    await this.store.writeEvidence(
      request.runId,
      "imports/import-plan.json",
      plan,
    );

    const targetSnapshots = new Map<string, FileSnapshot | undefined>();
    for (const target of plan.targets) {
      const absolutePath = resolveInside(
        this.repositoryRoot,
        target.relativePath,
      );
      const exists = await fileExists(absolutePath);
      if (exists !== (target.state === "existing-file")) {
        throw new Error(
          `Import target state changed after planning: ${target.relativePath}`,
        );
      }
      targetSnapshots.set(
        target.relativePath,
        exists
          ? await snapshotFile(
              this.repositoryRoot,
              target.relativePath,
              `Import target before write: ${target.relativePath}`,
            )
          : undefined,
      );
    }

    const fixedTargetContext = {
      frozenImportContextSha256: contextSnapshot.sha256,
      taskGraph: taskGraphResult.value,
      outline: outlineResult.value,
      fixedPlan: {
        source: {
          relativePath: source.relativePath,
          sha256: source.snapshot.sha256,
        },
        route: {
          profession: plan.route.profession,
          theme: plan.route.theme,
        },
        prompts: plan.prompts,
        themePrompts: plan.themePrompts,
        targets: plan.targets.map(({ kind, relativePath, state }) => ({
          kind,
          relativePath,
          state,
          existingContent: targetSnapshots.get(relativePath)?.content,
        })),
      },
      authorityOrder: [
        "root rules",
        "verified existing manifest and prompt tree",
        "import contracts",
        "source design text",
      ],
      writerPolicy:
        "Existing rules and prompts are preserved byte-for-byte. Existing indexes may only receive a mechanical current-file list update. Model fields are used only for missing fixed targets.",
    };
    const designResult = await this.#storeStructured(
      request,
      {
        runId: request.runId,
        callId: "import-fixed-target-design",
        role: "engineer",
        schemaName: "dnf_import_fixed_target_design",
        schema: importDesignSchema,
        instructions:
          "Produce semantic content for every fixed profession prompt in exact plan order. You cannot add, remove, rename, reorder or choose paths. A prompt object may contain theme fields if and only if its displayName is in fixedPlan.themePrompts; never invent theme content for other profession prompts. Follow the four-section profession Prompt and five-section theme Prompt contracts, but return only the schema fields, never Markdown files. Chinese prose fields must be conservative and source-grounded; English prompt fields must contain English only. Existing rules, manifests and prompts are higher authority and may not be weakened. Do not emit NPK/IMG mappings, frame counts, coverage completion, compatibility, safety, build, deployment, model endpoint, seed, shell, code, or approval claims. Keep every required safety boolean at its fixed false/pending value.",
        input: stableStringify(fixedTargetContext),
        mockValue: mockDesign(
          request,
          plan.prompts.map((prompt) => prompt.displayName),
          plan.themePrompts.map((prompt) => prompt.displayName),
        ),
      },
      "models/import-fixed-target-design.json",
      "models/calls/import-fixed-target-design.json",
    );
    assertDesign(designResult.value, request, plan);

    return {
      taskGraph: taskGraphResult.value,
      outline: outlineResult.value,
      plan,
      design: designResult.value,
      contextPath,
      contextSha256: contextSnapshot.sha256,
      targetSnapshots,
      authoritySnapshots,
      modelEvidenceEligible:
        designResult.record.provider === "openai" &&
        designResult.record.status === "passed" &&
        designResult.record.responseStoragePolicy === "store-false",
    };
  }
}
