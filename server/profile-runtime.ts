import { readFile } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";
import type { RunRequest, ToolInvocation } from "./shared/contracts.js";
import type { ExecutionProfile } from "./shared/profile.js";
import {
  assertNoSymlinkChain,
  fileExists,
  normalizeRelativePath,
  resolveInside,
  writeJsonCreateNew,
} from "./lib/filesystem.js";

export interface ExpandedProfileStep {
  id: string;
  toolId: string;
  phase: "preflight" | "inventory" | "post-model";
  dependsOn: string[];
  mode: "read-only" | "workspace-write";
  arguments: ToolInvocation["arguments"];
  expectedOutputs: string[];
  successPredicates: string[];
}

export interface ExpandedExecutionProfile {
  profile: ExecutionProfile;
  configPath: string;
  stylePlanPath: string;
  outputNpkPath: string;
  buildSummaryPath: string;
  steps: ExpandedProfileStep[];
  delivery: {
    npkPath: string;
    validationSummaryPath: string;
    evidencePaths: string[];
  };
}

function repositoryRelative(fromDirectory: string, target: string): string {
  const value = relative(fromDirectory, target).split(sep).join("/");
  return value.length === 0 ? "." : value;
}

function expandString(
  value: string,
  variables: Readonly<Record<string, string>>,
): string {
  const expanded = value.replace(
    /\{\{(?<name>[A-Za-z][A-Za-z0-9]*)\}\}/gu,
    (token, name: string) => variables[name] ?? token,
  );
  if (/\{\{[^{}]+\}\}/u.test(expanded)) {
    throw new Error(
      `Execution profile contains an unresolved template: ${value}`,
    );
  }
  return expanded;
}

function expandValue(
  value: unknown,
  variables: Readonly<Record<string, string>>,
): unknown {
  if (typeof value === "string") {
    return expandString(value, variables);
  }
  if (Array.isArray(value)) {
    return value.map((item) => expandValue(item, variables));
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, item]) => [
        key,
        expandValue(item, variables),
      ]),
    );
  }
  return value;
}

export function expandExecutionProfile(
  profile: ExecutionProfile,
  request: RunRequest,
): ExpandedExecutionProfile {
  const firstPass = {
    runId: request.runId,
    version: request.outputVersion,
  };
  const configPath = normalizeRelativePath(
    expandString(profile.control.materializedConfigPath, firstPass),
  );
  const stylePlanPath = normalizeRelativePath(
    expandString(profile.control.stylePlanPath, firstPass),
  );
  const outputNpkPath = normalizeRelativePath(
    expandString(profile.control.outputNpkPath, firstPass),
  );
  const buildSummaryPath = normalizeRelativePath(
    expandString(profile.control.buildSummaryPath, firstPass),
  );
  const variables = {
    ...firstPass,
    configPath,
    stylePlanPath,
    outputNpkPath,
    buildSummaryPath,
  };
  const steps = profile.steps.map((step) => ({
    ...step,
    arguments: expandValue(
      step.arguments,
      variables,
    ) as ToolInvocation["arguments"],
    expectedOutputs: step.expectedOutputs.map((path) =>
      normalizeRelativePath(expandString(path, variables)),
    ),
  }));
  return {
    profile,
    configPath,
    stylePlanPath,
    outputNpkPath,
    buildSummaryPath,
    steps,
    delivery: {
      npkPath: normalizeRelativePath(
        expandString(profile.delivery.npkPath, variables),
      ),
      validationSummaryPath: normalizeRelativePath(
        expandString(profile.delivery.validationSummaryPath, variables),
      ),
      evidencePaths: profile.delivery.evidencePaths.map((path) =>
        normalizeRelativePath(expandString(path, variables)),
      ),
    },
  };
}

export async function materializeExecutionConfig(
  repositoryRoot: string,
  expanded: ExpandedExecutionProfile,
  request: RunRequest,
): Promise<string> {
  const baseConfigPath = normalizeRelativePath(
    expandString(expanded.profile.control.baseConfigPath, {
      runId: request.runId,
      version: request.outputVersion,
    }),
  );
  const baseAbsolutePath = resolveInside(repositoryRoot, baseConfigPath);
  const outputAbsolutePath = resolveInside(repositoryRoot, expanded.configPath);
  if (await fileExists(outputAbsolutePath)) {
    throw new Error(
      `Refusing to overwrite materialized config: ${expanded.configPath}`,
    );
  }
  await assertNoSymlinkChain(repositoryRoot, baseAbsolutePath);
  await assertNoSymlinkChain(repositoryRoot, outputAbsolutePath);
  const parsed = JSON.parse(await readFile(baseAbsolutePath, "utf8")) as Record<
    string,
    unknown
  >;
  const sourceOutput = parsed.output;
  const promptBinding = parsed.promptBinding;
  const [profilePromptBinding] = expanded.profile.promptBindings;
  if (
    parsed.schemaVersion !== 1 ||
    sourceOutput === null ||
    typeof sourceOutput !== "object" ||
    promptBinding === null ||
    typeof promptBinding !== "object" ||
    profilePromptBinding === undefined
  ) {
    throw new Error(
      "Base execution config does not satisfy the materialization contract.",
    );
  }
  const outputDirectory = dirname(outputAbsolutePath);
  const baseDirectory = dirname(baseAbsolutePath);
  const schemaValue = parsed.$schema;
  const materialized = {
    ...parsed,
    ...(typeof schemaValue === "string"
      ? {
          $schema: repositoryRelative(
            outputDirectory,
            resolve(baseDirectory, schemaValue.replaceAll("/", sep)),
          ),
        }
      : {}),
    output: {
      ...(sourceOutput as Record<string, unknown>),
      componentNpkPath: repositoryRelative(
        outputDirectory,
        resolveInside(repositoryRoot, expanded.outputNpkPath),
      ),
      buildSummaryPath: repositoryRelative(
        outputDirectory,
        resolveInside(repositoryRoot, expanded.buildSummaryPath),
      ),
    },
    promptBinding: {
      ...(promptBinding as Record<string, unknown>),
      themeAgentPath: repositoryRelative(
        outputDirectory,
        resolveInside(repositoryRoot, expanded.profile.themeAgentPath),
      ),
      professionPromptPath: repositoryRelative(
        outputDirectory,
        resolveInside(
          repositoryRoot,
          profilePromptBinding.professionPromptPath,
        ),
      ),
      themePromptPath: repositoryRelative(
        outputDirectory,
        resolveInside(repositoryRoot, profilePromptBinding.themePromptPath),
      ),
    },
    agenticControl: {
      schemaVersion: 1,
      runId: request.runId,
      executionProfileId: expanded.profile.id,
      baseConfigPath,
      stylePlanPath: expanded.stylePlanPath,
      fullSkillCoverageProven: false,
      clientCompatibilityProven: false,
      deploymentAuthorized: false,
      deploymentPerformed: false,
    },
  };
  await writeJsonCreateNew(outputAbsolutePath, materialized);
  return expanded.configPath;
}
