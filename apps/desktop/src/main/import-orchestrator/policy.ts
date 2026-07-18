import type {
  ImportDesign,
  ImportOutline,
  ImportPlan,
  RunRequest,
  ToolResult,
} from "../../shared/contracts.js";
import { stableStringify } from "../lib/filesystem.js";
import { canonicalPromptName } from "./prompt-index.js";
import type { ImportSource } from "./types.js";

/** 固定工具必须同时报告 passed 与零退出码。 */
export function assertPassedTool(result: ToolResult, label: string): void {
  if (result.status !== "passed" || result.exitCode !== 0) {
    throw new Error(result.error ?? `${label} failed.`);
  }
}

function assertUniquePromptNames(names: string[], label: string): void {
  const seen = new Set<string>();
  for (const name of names) {
    const key = canonicalPromptName(name);
    if (seen.has(key)) {
      throw new Error(`${label} contains a duplicate display name: ${name}`);
    }
    seen.add(key);
  }
}

/** 验证模型 outline 与固定 Run 路由、既有索引和用户冻结技能一致。 */
export function assertImportOutline(
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

  // 现有索引必须作为精确前缀保留，防止模型删除、重命名或重排已有 Prompt。
  for (let index = 0; index < existingNames.length; index += 1) {
    if (outline.promptDisplayNames[index] !== existingNames[index]) {
      throw new Error(
        "Import outline must preserve the complete existing profession prompt order as an exact prefix.",
      );
    }
  }
  assertUniquePromptNames(outline.promptDisplayNames, "Import outline");
  assertUniquePromptNames(
    outline.themePromptDisplayNames,
    "Theme import outline",
  );
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

  // 主题 Prompt 只能是职业 Prompt 的同序子集。
  const professionIndex = new Map(
    outline.promptDisplayNames.map((name, index) => [
      canonicalPromptName(name),
      index,
    ]),
  );
  let previousIndex = -1;
  for (const name of outline.themePromptDisplayNames) {
    const index = professionIndex.get(canonicalPromptName(name));
    if (index === undefined || index <= previousIndex) {
      throw new Error(
        "Theme prompt outline must be an ordered subset of the profession prompt outline.",
      );
    }
    previousIndex = index;
  }

  if (request.selectedSkills.length === 0) {
    return;
  }
  const mergeSelected = (existing: string[]): string[] => {
    const result = [...existing];
    const keys = new Set(result.map(canonicalPromptName));
    for (const name of request.selectedSkills) {
      const key = canonicalPromptName(name);
      if (!keys.has(key)) {
        keys.add(key);
        result.push(name);
      }
    }
    return result;
  };

  const expectedProfession = mergeSelected(existingNames);
  if (
    stableStringify(outline.promptDisplayNames) !==
    stableStringify(expectedProfession)
  ) {
    throw new Error(
      "Import outline differs from the explicitly selected profession skills.",
    );
  }
  if (request.action === "create-theme") {
    const selectedKeys = new Set(
      request.selectedSkills.map(canonicalPromptName),
    );
    const expectedTheme = mergeSelected(existingThemeNames).filter(
      (name) =>
        existingThemeNames.some(
          (existing) =>
            canonicalPromptName(existing) === canonicalPromptName(name),
        ) || selectedKeys.has(canonicalPromptName(name)),
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

/** 验证固定 PowerShell 规划器输出的来源绑定、顺序和完整目标白名单。 */
export function assertImportPlan(
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
    [...actual].some((path) => {
      const normalized = path.toLocaleLowerCase();
      return (
        normalized.endsWith("/manifest.json") ||
        normalized.includes("/npk/") ||
        normalized.includes("/validation/")
      );
    })
  ) {
    throw new Error("Import target whitelist contains a forbidden artifact.");
  }
}

/** 验证最终设计逐项覆盖固定 Prompt，并严格匹配主题同名子集。 */
export function assertImportDesign(
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
    plan.themePrompts.map((prompt) => canonicalPromptName(prompt.displayName)),
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
      Boolean(actual.theme) !==
      themePromptKeys.has(canonicalPromptName(expected))
    ) {
      throw new Error(
        `Import design theme content mismatch for ${actual.displayName}.`,
      );
    }
  }
}
