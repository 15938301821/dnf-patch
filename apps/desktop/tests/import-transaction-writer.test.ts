import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
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
} from "../src/shared/contracts.js";
import {
  ImportTransactionWriter,
  buildImportTargetContent,
  type ImportToolInvoker,
} from "../src/main/import-transaction-writer.js";
import { RunStore } from "../src/main/run-store.js";
import { sha256Buffer, snapshotFile } from "../src/main/lib/filesystem.js";
import type { BrokerCall } from "../src/main/tool-broker.js";

const HASH = "A".repeat(64);
const temporaryRoots: string[] = [];

function requireValue<T>(value: T | undefined, label: string): T {
  if (value === undefined) {
    throw new Error(`Test fixture is missing ${label}.`);
  }
  return value;
}

function request(runId: string): RunRequest {
  return runRequestSchema.parse({
    schemaVersion: 1,
    runId,
    action: "create-profession",
    provider: "mock",
    profession: "TestProfession",
    sourceDesignPath: "TestProfession/design.md",
    selectedSkills: ["Existing Skill", "New Skill"],
    execute: true,
    allowNetwork: false,
    generateImageReferences: false,
    outputBaseName: "test-import",
    outputVersion: "1",
    deploymentAuthorized: false,
  });
}

function design(runId: string, names: string[]): ImportDesign {
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

function plan(
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
      relativePath: "TestProfession/AGENTS.md",
    },
    {
      kind: "profession-index" as const,
      relativePath: "TestProfession/prompts/README.md",
    },
    ...prompts.map((prompt) => ({
      kind: "profession-prompt" as const,
      relativePath: `TestProfession/prompts/${prompt.fileName}`,
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
      path: resolve(root, "TestProfession/design.md"),
      sha256: sourceSha256,
    },
    route: {
      profession: "TestProfession",
      professionPath: resolve(root, "TestProfession"),
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

function validation(
  root: string,
  sourceSha256: string,
  status: "passed" | "failed",
): PromptTreeResult {
  return promptTreeResultSchema.parse({
    schemaVersion: 1,
    status,
    professionPath: resolve(root, "TestProfession"),
    themePath: null,
    source: {
      path: resolve(root, "TestProfession/design.md"),
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
              path: "TestProfession",
              message: "Forced failure.",
            },
          ],
    warnings: [],
  });
}

function toolResult(runId: string, result: PromptTreeResult): ToolResult {
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

class FakeInvoker implements ImportToolInvoker {
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

async function fixture(runId: string): Promise<{
  root: string;
  store: RunStore;
  sourceSha256: string;
  authoritySnapshots: FileSnapshot[];
}> {
  const root = await mkdtemp(join(tmpdir(), "dnf-import-writer-"));
  temporaryRoots.push(root);
  await mkdir(resolve(root, "TestProfession"));
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
  await writeFile(resolve(root, "TestProfession/design.md"), source);
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

async function frozenTargets(
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

afterEach(async () => {
  await Promise.all(
    temporaryRoots
      .splice(0)
      .map((root) => rm(root, { recursive: true, force: true })),
  );
});

describe("ImportTransactionWriter", () => {
  it("commits only fixed targets and preserves source and unrelated bytes", async () => {
    const runId = "writer-success";
    const { root, store, sourceSha256, authoritySnapshots } =
      await fixture(runId);
    await writeFile(
      resolve(root, "TestProfession/unrelated.bin"),
      Buffer.from([1, 2, 3]),
    );
    const names = ["Existing Skill", "New Skill"];
    const importPlan = plan(root, sourceSha256, names);
    const targetSnapshots = await frozenTargets(root, importPlan);
    const writer = new ImportTransactionWriter(
      root,
      store,
      new FakeInvoker(
        toolResult(runId, validation(root, sourceSha256, "passed")),
      ),
    );

    const result = await writer.commit(
      request(runId),
      importPlan,
      design(runId, names),
      "TestProfession/design.md",
      targetSnapshots,
      authoritySnapshots,
    );

    expect(result.validation.status).toBe("passed");
    expect(
      await readFile(resolve(root, "TestProfession/design.md"), "utf8"),
    ).toBe("# Test source\n");
    expect(
      await readFile(resolve(root, "TestProfession/unrelated.bin")),
    ).toEqual(Buffer.from([1, 2, 3]));
    const professionPrompt = await readFile(
      resolve(root, "TestProfession/prompts/New Skill.md"),
      "utf8",
    );
    expect(professionPrompt).toContain(
      "## \u804c\u4e1a\u7a33\u5b9a\u8bed\u4e49",
    );
    expect(professionPrompt).toContain("```text\nPreserve action silhouette");
    expect(professionPrompt).not.toContain("manifest.json");
  });

  it("restores existing bytes and removes created targets when the gate fails", async () => {
    const runId = "writer-rollback";
    const { root, store, sourceSha256, authoritySnapshots } =
      await fixture(runId);
    const promptsPath = resolve(root, "TestProfession/prompts");
    await mkdir(promptsPath);
    const existingAgents = Buffer.from("# Existing rules\r\n", "utf8");
    const existingPrompt = Buffer.from("# Existing Skill\r\n", "utf8");
    const existingIndex = Buffer.from(
      [
        "# Existing index",
        "",
        "## \u804c\u8d23",
        "existing",
        "## \u52a0\u8f7d\u987a\u5e8f",
        "existing",
        "## \u7a33\u5b9a\u7ed3\u6784",
        "existing",
        "## \u5f53\u524d\u6587\u4ef6",
        "",
        "- `Existing Skill.md`",
        "",
        "## \u8986\u76d6\u72b6\u6001",
        "existing",
        "",
      ].join("\r\n"),
      "utf8",
    );
    await writeFile(resolve(root, "TestProfession/AGENTS.md"), existingAgents);
    await writeFile(resolve(promptsPath, "README.md"), existingIndex);
    await writeFile(resolve(promptsPath, "Existing Skill.md"), existingPrompt);
    const names = ["Existing Skill", "New Skill"];
    const states = {
      "TestProfession/AGENTS.md": "existing-file" as const,
      "TestProfession/prompts/README.md": "existing-file" as const,
      "TestProfession/prompts/Existing Skill.md": "existing-file" as const,
    };
    const importPlan = plan(root, sourceSha256, names, states);
    const targetSnapshots = await frozenTargets(root, importPlan);
    const writer = new ImportTransactionWriter(
      root,
      store,
      new FakeInvoker(
        toolResult(runId, validation(root, sourceSha256, "failed")),
      ),
    );

    await expect(
      writer.commit(
        request(runId),
        importPlan,
        design(runId, names),
        "TestProfession/design.md",
        targetSnapshots,
        authoritySnapshots,
      ),
    ).rejects.toThrow("Prompt tree gate failed");

    expect(await readFile(resolve(root, "TestProfession/AGENTS.md"))).toEqual(
      existingAgents,
    );
    expect(await readFile(resolve(promptsPath, "README.md"))).toEqual(
      existingIndex,
    );
    expect(await readFile(resolve(promptsPath, "Existing Skill.md"))).toEqual(
      existingPrompt,
    );
    await expect(
      readFile(resolve(promptsPath, "New Skill.md")),
    ).rejects.toThrow();
  });

  it("blocks before writing when a frozen target changes", async () => {
    const runId = "writer-drift";
    const { root, store, sourceSha256, authoritySnapshots } =
      await fixture(runId);
    const agentsPath = resolve(root, "TestProfession/AGENTS.md");
    await writeFile(agentsPath, "# Before\n", "utf8");
    const names = ["Existing Skill", "New Skill"];
    const importPlan = plan(root, sourceSha256, names, {
      "TestProfession/AGENTS.md": "existing-file",
    });
    const targetSnapshots = await frozenTargets(root, importPlan);
    await writeFile(agentsPath, "# Concurrent edit\n", "utf8");
    const writer = new ImportTransactionWriter(
      root,
      store,
      new FakeInvoker(
        toolResult(runId, validation(root, sourceSha256, "passed")),
      ),
    );

    await expect(
      writer.commit(
        request(runId),
        importPlan,
        design(runId, names),
        "TestProfession/design.md",
        targetSnapshots,
        authoritySnapshots,
      ),
    ).rejects.toThrow("changed after model context freeze");

    expect(await readFile(agentsPath, "utf8")).toBe("# Concurrent edit\n");
    await expect(
      readFile(resolve(root, "TestProfession/prompts/README.md")),
    ).rejects.toThrow();
  });

  it("blocks with zero target writes when a frozen authority changes", async () => {
    const runId = "writer-authority-drift-before";
    const { root, store, sourceSha256, authoritySnapshots } =
      await fixture(runId);
    const names = ["Existing Skill", "New Skill"];
    const importPlan = plan(root, sourceSha256, names);
    const targetSnapshots = await frozenTargets(root, importPlan);
    await writeFile(
      resolve(root, "AGENTS.md"),
      "# Concurrent authority\n",
      "utf8",
    );
    const invoker = new FakeInvoker(
      toolResult(runId, validation(root, sourceSha256, "passed")),
    );
    const writer = new ImportTransactionWriter(root, store, invoker);

    await expect(
      writer.commit(
        request(runId),
        importPlan,
        design(runId, names),
        "TestProfession/design.md",
        targetSnapshots,
        authoritySnapshots,
      ),
    ).rejects.toThrow("authority input changed after context freeze");

    expect(invoker.calls).toHaveLength(0);
    await expect(
      readFile(resolve(root, "TestProfession/AGENTS.md")),
    ).rejects.toThrow();
    await expect(
      readFile(resolve(root, "TestProfession/prompts/New Skill.md")),
    ).rejects.toThrow();
  });

  it("rolls back target writes when authority changes during the gate", async () => {
    const runId = "writer-authority-drift-after";
    const { root, store, sourceSha256, authoritySnapshots } =
      await fixture(runId);
    const names = ["Existing Skill", "New Skill"];
    const importPlan = plan(root, sourceSha256, names);
    const targetSnapshots = await frozenTargets(root, importPlan);
    const invoker = new FakeInvoker(
      toolResult(runId, validation(root, sourceSha256, "passed")),
      async () => {
        await writeFile(
          resolve(root, "AGENTS.md"),
          "# Concurrent authority\n",
          "utf8",
        );
      },
    );
    const writer = new ImportTransactionWriter(root, store, invoker);

    await expect(
      writer.commit(
        request(runId),
        importPlan,
        design(runId, names),
        "TestProfession/design.md",
        targetSnapshots,
        authoritySnapshots,
      ),
    ).rejects.toThrow("authority input changed after context freeze");

    expect(invoker.calls).toHaveLength(1);
    expect(invoker.calls[0]?.expectedScriptSha256).toBe(
      authoritySnapshots[2]?.sha256,
    );
    expect(invoker.calls[0]?.expectedHostScriptSha256).toBe(
      authoritySnapshots[1]?.sha256,
    );
    await expect(
      readFile(resolve(root, "TestProfession/AGENTS.md")),
    ).rejects.toThrow();
    await expect(
      readFile(resolve(root, "TestProfession/prompts/New Skill.md")),
    ).rejects.toThrow();
    await expect(
      readFile(
        resolve(
          root,
          `apps/desktop/.runs/${runId}/imports/transaction-receipt.json`,
        ),
      ),
    ).rejects.toThrow();
  });

  it("keeps the full profession index while building a theme subset", () => {
    const runId = "writer-theme-subset";
    const names = ["Skill One", "Skill Two"];
    const importDesign = importDesignSchema.parse({
      ...design(runId, names),
      theme: "Theme",
      themeRules: {
        objective: "主题目标只来自设计来源。",
        paletteMaterialsAndStyle: "色板、材质与风格保持来源约束。",
        promptRouting: "先加载职业 Prompt，再加载主题增量。",
        modificationScopeAndBoundaries: "修改范围不增加资源或帧。",
        acceptanceAndRegression: "主题验收保留动作轮廓与阶段。",
      },
      prompts: [
        design(runId, names).prompts[0],
        {
          ...design(runId, names).prompts[1],
          theme: {
            englishIncrement: "Apply a restrained cyan material language.",
            changes: "仅第二项使用来源明确支持的主题增量。",
            acceptance: "主题线索与动作轮廓均保持清晰。",
            exclusions: "不删除源人物、武器、背景或界面内容。",
          },
        },
      ],
    });
    const prompts = names.map((displayName) => ({
      displayName,
      safeName: displayName,
      fileName: `${displayName}.md`,
    }));
    const subsetPlan = importPlanSchema.parse({
      schemaVersion: 1,
      status: "passed",
      source: { path: "C:\\repo\\TestProfession\\design.md", sha256: HASH },
      route: {
        profession: "TestProfession",
        professionPath: "C:\\repo\\TestProfession",
        theme: "Theme",
        themePath: "C:\\repo\\TestProfession\\Theme",
      },
      prompts,
      themePrompts: [prompts[1]],
      targets: [
        {
          kind: "profession-index",
          path: "C:\\repo\\TestProfession\\prompts\\README.md",
          relativePath: "TestProfession/prompts/README.md",
          state: "missing",
        },
        {
          kind: "theme-index",
          path: "C:\\repo\\TestProfession\\Theme\\prompts\\README.md",
          relativePath: "TestProfession/Theme/prompts/README.md",
          state: "missing",
        },
        {
          kind: "theme-prompt",
          path: "C:\\repo\\TestProfession\\Theme\\prompts\\Skill Two.md",
          relativePath: "TestProfession/Theme/prompts/Skill Two.md",
          state: "missing",
        },
      ],
      baselineChanges: [],
      errors: [],
      warnings: [],
    });

    const professionIndex = buildImportTargetContent(
      requireValue(subsetPlan.targets[0], "profession index target"),
      subsetPlan,
      importDesign,
    );
    const themeIndex = buildImportTargetContent(
      requireValue(subsetPlan.targets[1], "theme index target"),
      subsetPlan,
      importDesign,
    );
    expect(professionIndex).toContain("- `Skill One.md`");
    expect(professionIndex).toContain("- `Skill Two.md`");
    expect(themeIndex).not.toContain("- `Skill One.md`");
    expect(themeIndex).toContain("- `Skill Two.md`");
  });

  it("builds theme Prompt references only from fixed plan file names", () => {
    const runId = "writer-theme-content";
    const importDesign = importDesignSchema.parse({
      ...design(runId, ["Skill: One"]),
      theme: "Theme",
      themeRules: {
        objective: "主题目标只来自设计来源。",
        paletteMaterialsAndStyle: "色板、材质与风格保持来源约束。",
        promptRouting: "先加载职业 Prompt，再加载主题增量。",
        modificationScopeAndBoundaries: "修改范围不增加资源或帧。",
        acceptanceAndRegression: "主题验收保留动作轮廓与阶段。",
      },
      prompts: [
        {
          ...design(runId, ["Skill: One"]).prompts[0],
          displayName: "Skill: One",
          theme: {
            englishIncrement: "Apply a restrained cyan material language.",
            changes: "使用来源明确支持的青色材质增量。",
            acceptance: "主题线索与动作轮廓均保持清晰。",
            exclusions: "不删除源人物、武器、背景或界面内容。",
          },
        },
      ],
    });
    const fakePlan = importPlanSchema.parse({
      schemaVersion: 1,
      status: "passed",
      source: { path: "C:\\repo\\TestProfession\\design.md", sha256: HASH },
      route: {
        profession: "TestProfession",
        professionPath: "C:\\repo\\TestProfession",
        theme: "Theme",
        themePath: "C:\\repo\\TestProfession\\Theme",
      },
      prompts: [
        {
          displayName: "Skill: One",
          safeName: "Skill\uff1a One",
          fileName: "Skill\uff1a One.md",
        },
      ],
      themePrompts: [
        {
          displayName: "Skill: One",
          safeName: "Skill\uff1a One",
          fileName: "Skill\uff1a One.md",
        },
      ],
      targets: [
        {
          kind: "theme-prompt",
          path: "C:\\repo\\TestProfession\\Theme\\prompts\\Skill\uff1a One.md",
          relativePath: "TestProfession/Theme/prompts/Skill\uff1a One.md",
          state: "missing",
        },
        {
          kind: "profession-agents",
          path: "C:\\repo\\TestProfession\\AGENTS.md",
          relativePath: "TestProfession/AGENTS.md",
          state: "missing",
        },
        {
          kind: "profession-index",
          path: "C:\\repo\\TestProfession\\prompts\\README.md",
          relativePath: "TestProfession/prompts/README.md",
          state: "missing",
        },
      ],
      baselineChanges: [],
      errors: [],
      warnings: [],
    });

    const content = buildImportTargetContent(
      requireValue(fakePlan.targets[0], "theme prompt target"),
      fakePlan,
      importDesign,
    );
    expect(content).toContain("../../prompts/Skill\uff1a One.md");
    expect(content).toContain("# Skill: One - Theme");
    expect(content).not.toContain("C:\\repo");
  });
});
