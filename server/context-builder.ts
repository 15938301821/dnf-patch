import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  contextBundleSchema,
  type ContextBundle,
  type FileSnapshot,
  type RunRequest,
} from "./shared/contracts.js";
import { executionProfileSchema } from "./shared/profile.js";
import { fileExists, snapshotFile } from "./lib/filesystem.js";
import {
  professionRelativePath,
  themeRelativePath,
} from "./profession-paths.js";

const PATCH_MAKER_SKILL = ".github/skills/dnf-patch-maker/SKILL.md";
const IMPORT_SKILL = ".github/skills/dnf-import-profession-text/SKILL.md";
const TOOL_CATALOG = "tools/catalog/dnf-tools.json";
const PROFILE_ROOT = "tools/profiles";

export interface ContextBundleInputs {
  materializedConfigPath?: string;
  sourceSummaryPath?: string;
  sourceInventoryPath?: string;
}

async function optionalSnapshot(
  repositoryRoot: string,
  relativePath: string,
  label: string,
  includeContent = true,
): Promise<FileSnapshot | undefined> {
  if (!(await fileExists(resolve(repositoryRoot, relativePath)))) {
    return undefined;
  }
  return snapshotFile(repositoryRoot, relativePath, label, includeContent);
}

async function listPromptSnapshots(
  repositoryRoot: string,
  directoryRelativePath: string,
  labelPrefix: string,
  selectedSkills: string[],
): Promise<FileSnapshot[]> {
  const directory = resolve(repositoryRoot, directoryRelativePath);
  if (!(await fileExists(directory))) {
    return [];
  }
  const selected = new Set(
    selectedSkills.map((name) => `${name}.md`.toLocaleLowerCase()),
  );
  const entries = await readdir(directory, { withFileTypes: true });
  const names = entries
    .filter(
      (entry) =>
        entry.isFile() &&
        entry.name.endsWith(".md") &&
        entry.name !== "README.md",
    )
    .map((entry) => entry.name)
    .filter(
      (name) => selected.size === 0 || selected.has(name.toLocaleLowerCase()),
    )
    .sort((left, right) => left.localeCompare(right, "zh-CN"));

  return Promise.all(
    names.map((name) =>
      snapshotFile(
        repositoryRoot,
        `${directoryRelativePath}/${name}`,
        `${labelPrefix}: ${name}`,
      ),
    ),
  );
}

function readCoverage(manifestText: string | undefined): boolean {
  if (!manifestText) {
    return false;
  }
  try {
    const value = JSON.parse(manifestText) as {
      coverage?: { fullSkillCoverageProven?: unknown };
      fullSkillCoverageProven?: unknown;
    };
    return (
      value.coverage?.fullSkillCoverageProven === true ||
      value.fullSkillCoverageProven === true
    );
  } catch {
    return false;
  }
}

function workflowFromManifest(
  manifestText: string | undefined,
): string | undefined {
  if (!manifestText) {
    return undefined;
  }
  try {
    const value = JSON.parse(manifestText) as {
      activityMigration?: { workflow?: { path?: unknown } };
    };
    const path = value.activityMigration?.workflow?.path;
    return typeof path === "string" && path.length > 0 ? path : undefined;
  } catch {
    return undefined;
  }
}

export async function buildContextBundle(
  repositoryRoot: string,
  request: RunRequest,
  inputs: ContextBundleInputs = {},
): Promise<ContextBundle> {
  const importAction =
    request.action === "create-profession" || request.action === "create-theme";
  const selectedPromptNames = importAction ? [] : request.selectedSkills;
  const professionPath = professionRelativePath(request.profession);
  const themePath = request.theme
    ? themeRelativePath(request.profession, request.theme)
    : undefined;
  const professionExists = await fileExists(
    resolve(repositoryRoot, professionPath),
  );
  const themeExists = themePath
    ? await fileExists(resolve(repositoryRoot, themePath))
    : false;

  const rootRules = await snapshotFile(
    repositoryRoot,
    "AGENTS.md",
    "Root AGENTS",
  );
  const patchMakerSkill = await snapshotFile(
    repositoryRoot,
    PATCH_MAKER_SKILL,
    "dnf-patch-maker skill",
  );
  const importSkill = importAction
    ? await optionalSnapshot(
        repositoryRoot,
        IMPORT_SKILL,
        "dnf-import-profession-text skill",
      )
    : undefined;
  const professionRules = professionExists
    ? await optionalSnapshot(
        repositoryRoot,
        `${professionPath}/AGENTS.md`,
        "Profession AGENTS",
      )
    : undefined;
  const manifest = professionExists
    ? await optionalSnapshot(
        repositoryRoot,
        `${professionPath}/manifest.json`,
        "Profession manifest",
      )
    : undefined;
  const professionPromptIndex = professionExists
    ? await optionalSnapshot(
        repositoryRoot,
        `${professionPath}/prompts/README.md`,
        "Profession prompt index",
      )
    : undefined;
  const professionPrompts = professionExists
    ? await listPromptSnapshots(
        repositoryRoot,
        `${professionPath}/prompts`,
        "Profession prompt",
        selectedPromptNames,
      )
    : [];
  const themeRules =
    themeExists && themePath
      ? await optionalSnapshot(
          repositoryRoot,
          `${themePath}/AGENTS.md`,
          "Theme AGENTS",
        )
      : undefined;
  const themePromptIndex =
    themeExists && themePath
      ? await optionalSnapshot(
          repositoryRoot,
          `${themePath}/prompts/README.md`,
          "Theme prompt index",
        )
      : undefined;
  const themePrompts =
    themeExists && themePath
      ? await listPromptSnapshots(
          repositoryRoot,
          `${themePath}/prompts`,
          "Theme prompt",
          selectedPromptNames,
        )
      : [];

  const manifestWorkflow = workflowFromManifest(manifest?.content);
  const configuredWorkflow =
    request.workflowPath ??
    (manifestWorkflow ? `${professionPath}/${manifestWorkflow}` : undefined);
  const workflow = configuredWorkflow
    ? await optionalSnapshot(
        repositoryRoot,
        configuredWorkflow,
        "Registered workflow",
      )
    : undefined;
  const executionProfile = request.profileId
    ? await optionalSnapshot(
        repositoryRoot,
        `${PROFILE_ROOT}/${request.profileId}.json`,
        "Execution profile",
      )
    : undefined;
  const executionProfileInputs: FileSnapshot[] = [];
  if (executionProfile?.content) {
    const parsedProfile = executionProfileSchema.parse(
      JSON.parse(executionProfile.content),
    );
    const profileInputPaths = [
      parsedProfile.control.baseConfigPath,
      parsedProfile.themeAgentPath,
      ...parsedProfile.promptBindings.flatMap((binding) => [
        binding.professionPromptPath,
        binding.themePromptPath,
      ]),
    ];
    for (const relativePath of [...new Set(profileInputPaths)]) {
      const snapshot = await optionalSnapshot(
        repositoryRoot,
        relativePath,
        `Execution profile input: ${relativePath}`,
      );
      if (snapshot) {
        executionProfileInputs.push(snapshot);
      }
    }
  }
  const toolCatalog = await snapshotFile(
    repositoryRoot,
    TOOL_CATALOG,
    "Tool catalog",
  );
  const materializedConfig = inputs.materializedConfigPath
    ? await optionalSnapshot(
        repositoryRoot,
        inputs.materializedConfigPath,
        "Materialized execution config",
      )
    : undefined;
  const sourceSummary = inputs.sourceSummaryPath
    ? await optionalSnapshot(
        repositoryRoot,
        inputs.sourceSummaryPath,
        "Official source summary",
      )
    : undefined;
  const sourceInventory = inputs.sourceInventoryPath
    ? await optionalSnapshot(
        repositoryRoot,
        inputs.sourceInventoryPath,
        "Official source frame inventory",
      )
    : undefined;

  const missingRequiredFacts: string[] = [];
  if (!professionExists) {
    missingRequiredFacts.push("profession-directory-missing");
  }
  if (professionExists && !professionRules) {
    missingRequiredFacts.push("profession-agents-missing");
  }
  if (professionExists && !manifest) {
    missingRequiredFacts.push("profession-manifest-missing");
  }
  if (request.theme && !themeExists) {
    missingRequiredFacts.push("theme-directory-missing");
  }
  if (themeExists && !themeRules) {
    missingRequiredFacts.push("theme-agents-missing");
  }
  if (request.action === "generate-patch" && !workflow && !request.profileId) {
    missingRequiredFacts.push("registered-workflow-or-profile-missing");
  }
  if (request.profileId && !executionProfile) {
    missingRequiredFacts.push("execution-profile-missing");
  }
  if (executionProfile && executionProfileInputs.length === 0) {
    missingRequiredFacts.push("execution-profile-inputs-missing");
  }
  if (request.action === "generate-patch" && request.execute) {
    if (!materializedConfig) {
      missingRequiredFacts.push("materialized-config-missing");
    }
    if (!sourceSummary) {
      missingRequiredFacts.push("official-source-summary-missing");
    }
    if (!sourceInventory) {
      missingRequiredFacts.push("official-source-inventory-missing");
    }
  }

  return contextBundleSchema.parse({
    schemaVersion: 1,
    runId: request.runId,
    capturedAtUtc: new Date().toISOString(),
    repositoryRoot,
    professionPath,
    ...(themePath ? { themePath } : {}),
    rootRules,
    patchMakerSkill,
    ...(importSkill ? { importSkill } : {}),
    ...(professionRules ? { professionRules } : {}),
    ...(manifest ? { manifest } : {}),
    ...(professionPromptIndex ? { professionPromptIndex } : {}),
    professionPrompts,
    ...(themeRules ? { themeRules } : {}),
    ...(themePromptIndex ? { themePromptIndex } : {}),
    themePrompts,
    ...(workflow ? { workflow } : {}),
    ...(executionProfile ? { executionProfile } : {}),
    executionProfileInputs,
    ...(materializedConfig ? { materializedConfig } : {}),
    ...(sourceSummary ? { sourceSummary } : {}),
    ...(sourceInventory ? { sourceInventory } : {}),
    toolCatalog,
    missingRequiredFacts,
    fullSkillCoverageProven: readCoverage(manifest?.content),
    deploymentAuthorized: false,
  });
}

export async function readDesignText(
  repositoryRoot: string,
  request: RunRequest,
): Promise<string> {
  if (request.designText) {
    return request.designText;
  }
  if (!request.sourceDesignPath) {
    return "";
  }
  return (
    await readFile(resolve(repositoryRoot, request.sourceDesignPath), "utf8")
  ).replace(/^\uFEFF/u, "");
}
