import { basename } from "node:path";
import type { ImportDesign, ImportPlan } from "../shared/contracts.js";

/** Unicode 与大小写无关的文件名比较键；原始显示名和文件名保持不变。 */
export function canonicalImportName(value: string): string {
  return value.normalize("NFC").toLocaleLowerCase();
}

function lineEnding(text: string): "\r\n" | "\n" | "\r" {
  const match = /\r\n|\n|\r/u.exec(text);
  return (match?.[0] as "\r\n" | "\n" | "\r" | undefined) ?? "\n";
}

function normalizedIndexHeading(value: string): string {
  return value
    .replace(/^\s*[\u4e00-\u9fff0-9]+[\u3001.\uff0e]\s*/u, "")
    .replace(/\s+#+\s*$/u, "")
    .trim();
}

/**
 * 只替换既有索引中有边界的“当前文件”内容。
 *
 * 保留原换行符、其余字节结构和 fenced code；找不到后续二级标题作为
 * 明确结束边界时硬失败，避免把模型生成列表覆盖到未知文档区域。
 */
export function updateCurrentFilesSection(
  source: string,
  fileNames: string[],
): string {
  const eol = lineEnding(source);
  const lines = [...source.matchAll(/.*(?:\r\n|\n|\r|$)/gu)].filter(
    (match) => match[0].length > 0,
  );
  let activeFence: string | undefined;
  let currentContentStart: number | undefined;
  let nextHeadingStart: number | undefined;

  for (const lineMatch of lines) {
    const lineWithEnding = lineMatch[0];
    const line = lineWithEnding.replace(/\r\n|\n|\r$/u, "");
    const start = lineMatch.index;
    if (activeFence) {
      const marker = activeFence[0] === "`" ? "`" : "~";
      if (
        new RegExp(
          `^[ ]{0,3}${marker}{${String(activeFence.length)},}[ \\t]*$`,
          "u",
        ).test(line)
      ) {
        activeFence = undefined;
      }
      continue;
    }
    const fenceMatch = /^[ ]{0,3}(?<fence>`{3,}|~{3,})/u.exec(line);
    if (fenceMatch?.groups?.fence) {
      activeFence = fenceMatch.groups.fence;
      continue;
    }
    const heading = /^##[ \t]+(?<title>.+?)[ \t]*$/u.exec(line)?.groups?.title;
    if (!heading) {
      continue;
    }
    if (currentContentStart !== undefined) {
      nextHeadingStart = start;
      break;
    }
    if (normalizedIndexHeading(heading) === "当前文件") {
      currentContentStart = start + lineWithEnding.length;
    }
  }
  if (currentContentStart === undefined || nextHeadingStart === undefined) {
    throw new Error(
      "Existing prompt index has no bounded current-file section to update.",
    );
  }

  const entries = fileNames.map((fileName) => `- \`${fileName}\``).join(eol);
  return `${source.slice(0, currentContentStart)}${eol}${entries}${eol}${eol}${source.slice(nextHeadingStart)}`;
}

/** 拒绝模型片段注入标题、代码围栏或 NUL，保证模板结构由本地代码控制。 */
function assertModelFragment(value: string, label: string): string {
  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    /^#{1,6}[ \t]+/mu.test(normalized) ||
    /^[ ]{0,3}(?:`{3,}|~{3,})/mu.test(normalized) ||
    normalized.includes("\0")
  ) {
    throw new Error(
      `Import model fragment contains structural markup: ${label}`,
    );
  }
  return normalized;
}

function professionAgents(profession: string, design: ImportDesign): string {
  const rules = design.professionRules;
  return [
    `# ${profession} 职业规则`,
    "",
    "## 职责与职业边界",
    "",
    assertModelFragment(
      rules.responsibilitiesAndBoundaries,
      "profession responsibilities",
    ),
    "",
    "## 资源事实源",
    "",
    assertModelFragment(rules.resourceFactAuthority, "resource authority"),
    "",
    "## Prompt 分层",
    "",
    assertModelFragment(rules.promptLayering, "prompt layering"),
    "",
    "## 人物、特效、武器与 Cut-in 边界",
    "",
    assertModelFragment(
      rules.characterEffectWeaponCutinBoundary,
      "layer boundaries",
    ),
    "",
    "## 职业验收与回归",
    "",
    assertModelFragment(rules.acceptanceAndRegression, "profession acceptance"),
    "",
    "## 覆盖状态",
    "",
    assertModelFragment(rules.coverageStatus, "coverage status"),
    "",
  ].join("\n");
}

function themeAgents(theme: string, design: ImportDesign): string {
  const rules = design.themeRules;
  if (!rules) {
    throw new Error("Theme rules are required for theme targets.");
  }
  return [
    `# ${theme} 主题规则`,
    "",
    "## 主题目标",
    "",
    assertModelFragment(rules.objective, "theme objective"),
    "",
    "## 色板、材质与风格",
    "",
    assertModelFragment(
      rules.paletteMaterialsAndStyle,
      "theme palette and materials",
    ),
    "",
    "## Prompt 路由",
    "",
    assertModelFragment(rules.promptRouting, "theme prompt routing"),
    "",
    "## 修改范围与边界",
    "",
    assertModelFragment(
      rules.modificationScopeAndBoundaries,
      "theme modification boundaries",
    ),
    "",
    "## 主题验收与回归",
    "",
    assertModelFragment(rules.acceptanceAndRegression, "theme acceptance"),
    "",
  ].join("\n");
}

function promptIndex(
  title: string,
  fileNames: string[],
  themed: boolean,
): string {
  const scope = themed ? "主题增量" : "职业稳定语义";
  const sequence = themed
    ? "先加载职业根目录同名 Prompt，再加载主题 AGENTS 共同规则和本目录同名增量。"
    : "先核验 manifest/inventory 显示名映射，再按本索引加载职业 Prompt。";
  return [
    `# ${title}`,
    "",
    "## 职责",
    "",
    `本索引只管理${scope} Prompt，不建立技术资源映射。`,
    "",
    "## 加载顺序",
    "",
    sequence,
    "",
    "## 稳定结构",
    "",
    themed
      ? "每个文件固定使用职业基础、主题增量 Prompt、具体变化、主题验收和主题排除五节。"
      : "每个文件固定使用职业稳定语义、职业通用 Prompt、源资源约束和阶段验收四节。",
    "",
    "## 当前文件",
    "",
    ...fileNames.map((fileName) => `- \`${fileName}\``),
    "",
    "## 覆盖状态",
    "",
    "Prompt 文件数量和文件名不能证明全技能覆盖；覆盖状态仍待 manifest 与实际 inventory 证据核验。",
    "",
  ].join("\n");
}

function professionPrompt(
  displayName: string,
  prompt: ImportDesign["prompts"][number],
): string {
  return [
    `# ${displayName}`,
    "",
    "## 职业稳定语义",
    "",
    assertModelFragment(
      prompt.professionStableSemantics,
      `${displayName} profession semantics`,
    ),
    "",
    "## 职业通用 Prompt",
    "",
    "```text",
    assertModelFragment(
      prompt.professionEnglishPrompt,
      `${displayName} profession prompt`,
    ),
    "```",
    "",
    "## 源资源约束",
    "",
    assertModelFragment(
      prompt.sourceConstraints,
      `${displayName} source constraints`,
    ),
    "",
    "## 阶段验收",
    "",
    assertModelFragment(
      prompt.phaseAcceptance,
      `${displayName} phase acceptance`,
    ),
    "",
  ].join("\n");
}

function themePrompt(
  displayName: string,
  theme: string,
  fileName: string,
  prompt: ImportDesign["prompts"][number],
): string {
  if (!prompt.theme) {
    throw new Error(`Theme semantics are missing for ${displayName}.`);
  }
  return [
    `# ${displayName} - ${theme}`,
    "",
    "## 职业基础",
    "",
    `引用 ../../prompts/${fileName}，以其动作、轮廓、阶段、锚点与源资源边界为基础。`,
    "",
    "## 主题增量 Prompt",
    "",
    "```text",
    assertModelFragment(
      prompt.theme.englishIncrement,
      `${displayName} theme prompt`,
    ),
    "```",
    "",
    "## 具体变化",
    "",
    assertModelFragment(prompt.theme.changes, `${displayName} theme changes`),
    "",
    "## 主题验收",
    "",
    assertModelFragment(
      prompt.theme.acceptance,
      `${displayName} theme acceptance`,
    ),
    "",
    "## 主题排除",
    "",
    assertModelFragment(
      prompt.theme.exclusions,
      `${displayName} theme exclusions`,
    ),
    "",
  ].join("\n");
}

/** 按固定计划目标选择本地模板；模型永远不能提供完整 Markdown 文件。 */
export function buildImportTargetContent(
  target: ImportPlan["targets"][number],
  plan: ImportPlan,
  design: ImportDesign,
): string {
  const professionFileNames = plan.prompts.map((prompt) => prompt.fileName);
  const themeFileNames = plan.themePrompts.map((prompt) => prompt.fileName);
  if (target.kind === "profession-agents") {
    return professionAgents(plan.route.profession, design);
  }
  if (target.kind === "profession-index") {
    return promptIndex(
      `${plan.route.profession} 职业 Prompt 索引`,
      professionFileNames,
      false,
    );
  }
  if (target.kind === "theme-agents") {
    if (!plan.route.theme) {
      throw new Error("Theme route is missing for theme AGENTS target.");
    }
    return themeAgents(plan.route.theme, design);
  }
  if (target.kind === "theme-index") {
    if (!plan.route.theme) {
      throw new Error("Theme route is missing for theme index target.");
    }
    return promptIndex(`${plan.route.theme} Prompt 索引`, themeFileNames, true);
  }

  const fileName = basename(target.relativePath);
  const promptIndexValue = plan.prompts.findIndex(
    (prompt) =>
      canonicalImportName(prompt.fileName) === canonicalImportName(fileName),
  );
  if (promptIndexValue < 0) {
    throw new Error(
      `Prompt target is not present in the fixed plan: ${fileName}`,
    );
  }
  const promptPlan = plan.prompts[promptIndexValue];
  const prompt = design.prompts[promptIndexValue];
  if (promptPlan === undefined || prompt === undefined) {
    throw new Error(`Prompt target has no fixed semantic design: ${fileName}`);
  }
  if (target.kind === "profession-prompt") {
    return professionPrompt(promptPlan.displayName, prompt);
  }
  if (!plan.route.theme) {
    throw new Error("Theme route is missing for theme prompt target.");
  }
  if (
    !plan.themePrompts.some(
      (themePlan) =>
        canonicalImportName(themePlan.fileName) ===
        canonicalImportName(fileName),
    )
  ) {
    throw new Error(
      `Theme Prompt target is not in the theme plan: ${fileName}`,
    );
  }
  return themePrompt(
    promptPlan.displayName,
    plan.route.theme,
    promptPlan.fileName,
    prompt,
  );
}
