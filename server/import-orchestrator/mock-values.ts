import {
  importDesignSchema,
  importOutlineSchema,
  importTaskGraphSchema,
  type ImportDesign,
  type ImportOutline,
  type ImportTaskGraph,
  type RunRequest,
} from "../shared/contracts.js";
import { canonicalPromptName } from "./prompt-index.js";

/** 离线 mock 导入值；正式写入策略会拒绝 mock 证据。 */

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

/** 保留现有顺序，只在末尾追加来源或用户显式选择的新名称。 */
function inferredMockNames(
  request: RunRequest,
  sourceText: string,
  existingNames: string[],
): string[] {
  const result = [...existingNames];
  const seen = new Set(result.map(canonicalPromptName));
  for (const candidate of sourceCandidateNames(request, sourceText)) {
    const key = canonicalPromptName(candidate);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(candidate);
  }
  if (result.length === 0) {
    result.push("Mock planning entry");
  }
  return result;
}

export function createMockImportTaskGraph(
  request: RunRequest,
): ImportTaskGraph {
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

export function createMockImportOutline(
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
  const promptKeys = new Set(promptDisplayNames.map(canonicalPromptName));
  const themePromptDisplayNames =
    request.action === "create-theme"
      ? inferredMockNames(request, sourceText, existingThemeNames).filter(
          (name) => promptKeys.has(canonicalPromptName(name)),
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

export function createMockImportDesign(
  request: RunRequest,
  names: string[],
  themeNames: string[],
): ImportDesign {
  const themeKeys = new Set(themeNames.map(canonicalPromptName));

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
      ...(themeKeys.has(canonicalPromptName(displayName))
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
