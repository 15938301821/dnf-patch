import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import {
  importDesignSchema,
  importPlanSchema,
  promptTreeResultSchema,
  runRequestSchema,
  toolResultSchema,
  type FileSnapshot,
  type ImportDesign,
  type ImportPlan,
  type PromptTreeResult,
  type RunRequest,
  type ToolResult,
} from "../../server/shared/contracts.js";
import type { ImportToolInvoker } from "../../server/import-transaction-writer.js";
import { sha256Buffer, snapshotFile } from "../../server/lib/filesystem.js";
import { RunStore } from "../../server/run-store.js";
import type { BrokerCall } from "../../server/tool-broker.js";

export const HASH = "A".repeat(64);
export const TEST_PROFESSION_PATH = "jobs/TestProfession";
const temporaryRoots: string[] = [];

/** 读取固定位置的 fixture 值，并在测试数据结构不完整时给出明确错误。 */
export function requireValue<T>(value: T | undefined, label: string): T {
  if (value === undefined) {
    throw new Error(`Test fixture is missing ${label}.`);
  }
  return value;
}

/** 创建默认启用写步骤、禁止网络和部署的导入请求。 */
export function request(runId: string): RunRequest {
  return runRequestSchema.parse({
    schemaVersion: 1,
    runId,
    action: "create-profession",
    provider: "mock",
    profession: "TestProfession",
    sourceDesignPath: `${TEST_PROFESSION_PATH}/design.md`,
    selectedSkills: ["Existing Skill", "New Skill"],
    execute: true,
    allowNetwork: false,
    generateImageReferences: false,
    outputBaseName: "test-import",
    outputVersion: "1",
    deploymentAuthorized: false,
  });
}

/** 创建仅包含职业稳定语义、没有资源事实声明的模型设计证据。 */
export function design(runId: string, names: string[]): ImportDesign {
  return importDesignSchema.parse({
    schemaVersion: 1,
    runId,
    profession: "TestProfession",
    professionRules: {
      responsibilitiesAndBoundaries: "只管理职业稳定语义与资源边界。",
      resourceFactAuthority: "资源事实必须等待 manifest 与 inventory 核验。",
      promptLayering: "先加载职业语义，再按核验路由组合主题增量。",
      characterEffectWeaponCutinBoundary:
        "人物、特效、武器与 Cut-in 边界必须继承源资源。",
      acceptanceAndRegression: "验收动作轮廓、阶段、锚点、几何与透明度。",
      coverageStatus: "Prompt 数量不能证明全技能覆盖。",
    },
    prompts: names.map((displayName) => ({
      displayName,
      professionStableSemantics: "动作轮廓、阶段与锚点必须保持清晰可辨。",
      professionEnglishPrompt:
        "Preserve action silhouette, timing, anchors, layers, and phase readability.",
      sourceConstraints: "保留源人物、特效、武器、Cut-in、几何与透明度边界。",
      phaseAcceptance: "逐项验收来源明确给出的起手、命中与收尾阶段。",
    })),
    rejectedResourceClaims: [],
    rejectedProcessClaims: [],
    inventoryPending: true,
    manifestCreatedOrModified: false,
    npkBuilt: false,
    deploymentPerformed: false,
  });
}

/** 根据技能名和初始文件状态建立固定导入目标计划。 */
export function plan(
  root: string,
  sourceSha256: string,
  names: string[],
  states: Partial<Record<string, "existing-file" | "missing">> = {},
): ImportPlan {
  const prompts = names.map((displayName) => ({
    displayName,
    safeName: displayName,
    fileName: `${displayName}.md`,
  }));
  const targets = [
    {
      kind: "profession-agents" as const,
      relativePath: `${TEST_PROFESSION_PATH}/AGENTS.md`,
    },
    {
      kind: "profession-index" as const,
      relativePath: `${TEST_PROFESSION_PATH}/prompts/README.md`,
    },
    ...prompts.map((prompt) => ({
      kind: "profession-prompt" as const,
      relativePath: `${TEST_PROFESSION_PATH}/prompts/${prompt.fileName}`,
    })),
  ].map((target) => ({
    ...target,
    path: resolve(root, target.relativePath),
    state: states[target.relativePath] ?? ("missing" as const),
  }));
  return importPlanSchema.parse({
    schemaVersion: 1,
    status: "passed",
    source: {
      path: resolve(root, TEST_PROFESSION_PATH, "design.md"),
      sha256: sourceSha256,
    },
    route: {
      profession: "TestProfession",
      professionPath: resolve(root, TEST_PROFESSION_PATH),
      theme: null,
      themePath: null,
    },
    prompts,
    themePrompts: [],
    targets,
    baselineChanges: [],
    errors: [],
    warnings: [],
  });
}

/** 创建 Prompt 树门禁的结构化通过或失败结果。 */
export function validation(
  root: string,
  sourceSha256: string,
  status: "passed" | "failed",
): PromptTreeResult {
  return promptTreeResultSchema.parse({
    schemaVersion: 1,
    status,
    professionPath: resolve(root, TEST_PROFESSION_PATH),
    themePath: null,
    source: {
      path: resolve(root, TEST_PROFESSION_PATH, "design.md"),
      sha256: sourceSha256,
    },
    changes: [],
    counts: {
      professionPrompts: 2,
      themePrompts: 0,
      checkedFiles: 4,
      errors: status === "passed" ? 0 : 1,
      warnings: 0,
    },
    errors:
      status === "passed"
        ? []
        : [
            {
              code: "forced-test-failure",
              path: TEST_PROFESSION_PATH,
              message: "Forced failure.",
            },
          ],
    warnings: [],
  });
}

/** 把 Prompt 树结果封装为 broker 返回的固定工具证据。 */
export function toolResult(
  runId: string,
  result: PromptTreeResult,
): ToolResult {
  const passed = result.status === "passed";
  return toolResultSchema.parse({
    schemaVersion: 1,
    runId,
    callId: "import.validate-prompt-tree",
    toolId: "prompt-tree-gate",
    status: passed ? "passed" : "failed",
    startedAtUtc: "2026-01-01T00:00:00.000Z",
    finishedAtUtc: "2026-01-01T00:00:01.000Z",
    exitCode: passed ? 0 : 1,
    stdout: JSON.stringify(result),
    stderr: "",
    parametersSha256: HASH,
    scriptSha256: HASH,
    outputs: [],
    deploymentAuthorized: false,
    ...(passed ? {} : { error: "Forced gate failure." }),
  });
}

/** 记录 broker 调用，并可在返回结果前模拟并发文件变化。 */
export class FakeInvoker implements ImportToolInvoker {
  readonly calls: BrokerCall[] = [];

  constructor(
    readonly result: ToolResult,
    readonly beforeResult?: (call: BrokerCall) => void | Promise<void>,
  ) {}

  async invoke(call: BrokerCall): Promise<ToolResult> {
    this.calls.push(call);
    await this.beforeResult?.(call);
    return this.result;
  }
}

/** 建立包含冻结规则、工具脚本、设计源和 RunStore 的最小仓库。 */
export async function fixture(runId: string): Promise<{
  root: string;
  store: RunStore;
  sourceSha256: string;
  authoritySnapshots: FileSnapshot[];
}> {
  const root = await mkdtemp(join(tmpdir(), "dnf-import-writer-"));
  temporaryRoots.push(root);
  await mkdir(resolve(root, TEST_PROFESSION_PATH), { recursive: true });
  await mkdir(resolve(root, "tools"));
  await mkdir(
    resolve(root, ".github/skills/dnf-import-profession-text/scripts"),
    { recursive: true },
  );
  await writeFile(resolve(root, "AGENTS.md"), "# Root authority\n", "utf8");
  await writeFile(
    resolve(root, "tools/Invoke-DnfCatalogTool.ps1"),
    "# frozen host\n",
    "utf8",
  );
  await writeFile(
    resolve(
      root,
      ".github/skills/dnf-import-profession-text/scripts/Test-DnfPromptTree.ps1",
    ),
    "# frozen gate\n",
    "utf8",
  );
  const source = Buffer.from("# Test source\n", "utf8");
  await writeFile(resolve(root, TEST_PROFESSION_PATH, "design.md"), source);
  const store = new RunStore(root);
  await store.create(request(runId));
  return {
    root,
    store,
    sourceSha256: sha256Buffer(source),
    authoritySnapshots: [
      await snapshotFile(root, "AGENTS.md", "Root authority", false),
      await snapshotFile(
        root,
        "tools/Invoke-DnfCatalogTool.ps1",
        "Catalog host",
        false,
      ),
      await snapshotFile(
        root,
        ".github/skills/dnf-import-profession-text/scripts/Test-DnfPromptTree.ps1",
        "Prompt tree gate",
        false,
      ),
    ],
  };
}

/** 冻结计划中每个既有目标的字节快照，缺失目标显式记录为 undefined。 */
export async function frozenTargets(
  root: string,
  importPlan: ImportPlan,
): Promise<Map<string, FileSnapshot | undefined>> {
  const result = new Map<string, FileSnapshot | undefined>();
  for (const target of importPlan.targets) {
    result.set(
      target.relativePath,
      target.state === "existing-file"
        ? await snapshotFile(root, target.relativePath, "before")
        : undefined,
    );
  }
  return result;
}

/** 在每个测试后并行删除本模块登记的临时仓库。 */
export async function cleanupTemporaryRoots(): Promise<void> {
  await Promise.all(
    temporaryRoots
      .splice(0)
      .map((root) => rm(root, { recursive: true, force: true })),
  );
}
