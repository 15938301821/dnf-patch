import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  importDesignSchema,
  importPlanSchema,
} from "../server/shared/contracts.js";
import {
  ImportTransactionWriter,
  buildImportTargetContent,
} from "../server/import-transaction-writer.js";
import {
  FakeInvoker,
  HASH,
  cleanupTemporaryRoots,
  design,
  fixture,
  frozenTargets,
  plan,
  request,
  requireValue,
  TEST_PROFESSION_PATH,
  toolResult,
  validation,
} from "./fixtures/import-transaction.js";

afterEach(async () => {
  await cleanupTemporaryRoots();
});

describe("ImportTransactionWriter", () => {
  it("commits only fixed targets and preserves source and unrelated bytes", async () => {
    const runId = "writer-success";
    const { root, store, sourceSha256, authoritySnapshots } =
      await fixture(runId);
    await writeFile(
      resolve(root, TEST_PROFESSION_PATH, "unrelated.bin"),
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
      `${TEST_PROFESSION_PATH}/design.md`,
      targetSnapshots,
      authoritySnapshots,
    );

    expect(result.validation.status).toBe("passed");
    expect(
      await readFile(resolve(root, TEST_PROFESSION_PATH, "design.md"), "utf8"),
    ).toBe("# Test source\n");
    expect(
      await readFile(resolve(root, TEST_PROFESSION_PATH, "unrelated.bin")),
    ).toEqual(Buffer.from([1, 2, 3]));
    const professionPrompt = await readFile(
      resolve(root, TEST_PROFESSION_PATH, "prompts/New Skill.md"),
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
    const promptsPath = resolve(root, TEST_PROFESSION_PATH, "prompts");
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
    await writeFile(
      resolve(root, TEST_PROFESSION_PATH, "AGENTS.md"),
      existingAgents,
    );
    await writeFile(resolve(promptsPath, "README.md"), existingIndex);
    await writeFile(resolve(promptsPath, "Existing Skill.md"), existingPrompt);
    const names = ["Existing Skill", "New Skill"];
    const states = {
      "jobs/TestProfession/AGENTS.md": "existing-file" as const,
      "jobs/TestProfession/prompts/README.md": "existing-file" as const,
      "jobs/TestProfession/prompts/Existing Skill.md": "existing-file" as const,
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
        `${TEST_PROFESSION_PATH}/design.md`,
        targetSnapshots,
        authoritySnapshots,
      ),
    ).rejects.toThrow("Prompt tree gate failed");

    expect(
      await readFile(resolve(root, TEST_PROFESSION_PATH, "AGENTS.md")),
    ).toEqual(existingAgents);
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
    const agentsPath = resolve(root, TEST_PROFESSION_PATH, "AGENTS.md");
    await writeFile(agentsPath, "# Before\n", "utf8");
    const names = ["Existing Skill", "New Skill"];
    const importPlan = plan(root, sourceSha256, names, {
      "jobs/TestProfession/AGENTS.md": "existing-file",
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
        `${TEST_PROFESSION_PATH}/design.md`,
        targetSnapshots,
        authoritySnapshots,
      ),
    ).rejects.toThrow("changed after model context freeze");

    expect(await readFile(agentsPath, "utf8")).toBe("# Concurrent edit\n");
    await expect(
      readFile(resolve(root, TEST_PROFESSION_PATH, "prompts/README.md")),
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
        `${TEST_PROFESSION_PATH}/design.md`,
        targetSnapshots,
        authoritySnapshots,
      ),
    ).rejects.toThrow("authority input changed after context freeze");

    expect(invoker.calls).toHaveLength(0);
    await expect(
      readFile(resolve(root, TEST_PROFESSION_PATH, "AGENTS.md")),
    ).rejects.toThrow();
    await expect(
      readFile(resolve(root, TEST_PROFESSION_PATH, "prompts/New Skill.md")),
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
        `${TEST_PROFESSION_PATH}/design.md`,
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
    expect(invoker.calls[0]?.invocation.arguments.ProfessionPath).toBe(
      TEST_PROFESSION_PATH,
    );
    await expect(
      readFile(resolve(root, TEST_PROFESSION_PATH, "AGENTS.md")),
    ).rejects.toThrow();
    await expect(
      readFile(resolve(root, TEST_PROFESSION_PATH, "prompts/New Skill.md")),
    ).rejects.toThrow();
    await expect(
      readFile(
        resolve(
          root,
          `userData/runs/${runId}/imports/transaction-receipt.json`,
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
      source: {
        path: "C:\\repo\\jobs\\TestProfession\\design.md",
        sha256: HASH,
      },
      route: {
        profession: "TestProfession",
        professionPath: "C:\\repo\\jobs\\TestProfession",
        theme: "Theme",
        themePath: "C:\\repo\\jobs\\TestProfession\\Theme",
      },
      prompts,
      themePrompts: [prompts[1]],
      targets: [
        {
          kind: "profession-index",
          path: "C:\\repo\\jobs\\TestProfession\\prompts\\README.md",
          relativePath: "jobs/TestProfession/prompts/README.md",
          state: "missing",
        },
        {
          kind: "theme-index",
          path: "C:\\repo\\jobs\\TestProfession\\Theme\\prompts\\README.md",
          relativePath: "jobs/TestProfession/Theme/prompts/README.md",
          state: "missing",
        },
        {
          kind: "theme-prompt",
          path: "C:\\repo\\jobs\\TestProfession\\Theme\\prompts\\Skill Two.md",
          relativePath: "jobs/TestProfession/Theme/prompts/Skill Two.md",
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
      source: {
        path: "C:\\repo\\jobs\\TestProfession\\design.md",
        sha256: HASH,
      },
      route: {
        profession: "TestProfession",
        professionPath: "C:\\repo\\jobs\\TestProfession",
        theme: "Theme",
        themePath: "C:\\repo\\jobs\\TestProfession\\Theme",
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
          path: "C:\\repo\\jobs\\TestProfession\\Theme\\prompts\\Skill\uff1a One.md",
          relativePath: "jobs/TestProfession/Theme/prompts/Skill\uff1a One.md",
          state: "missing",
        },
        {
          kind: "profession-agents",
          path: "C:\\repo\\jobs\\TestProfession\\AGENTS.md",
          relativePath: "jobs/TestProfession/AGENTS.md",
          state: "missing",
        },
        {
          kind: "profession-index",
          path: "C:\\repo\\jobs\\TestProfession\\prompts\\README.md",
          relativePath: "jobs/TestProfession/prompts/README.md",
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
