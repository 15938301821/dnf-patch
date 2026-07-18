import { readFile, stat } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import {
  executionProfileIndexSchema,
  type ExecutionProfile,
} from "../src/shared/profile.js";
import type { RunRequest } from "../src/shared/contracts/run.js";
import { MODEL_IDS } from "../src/shared/models.js";
import type {
  ToolCatalog,
  ToolCatalogEntry,
} from "../src/shared/tool-catalog.js";
import {
  assertProfileCatalogBinding,
  loadExecutionProfile,
  loadToolCatalog,
} from "../src/main/profile-loader.js";
import { expandExecutionProfile } from "../src/main/profile-runtime.js";
import { findRepositoryRoot } from "../src/main/repository.js";
import {
  assertNoSymlinkChain,
  fileExists,
  isPathInside,
  resolveInside,
  sha256Buffer,
} from "../src/main/lib/filesystem.js";

const profileIndexPath = "tools/profiles/index.json";
const hostScriptPath = "tools/Invoke-DnfCatalogTool.ps1";
const requiredDesktopEntrypoints = [
  "apps/desktop/src/main/index.ts",
  "apps/desktop/src/preload/index.ts",
  "apps/desktop/src/renderer/index.html",
  "apps/desktop/src/renderer/src/main.tsx",
  "apps/desktop/src/cli/index.ts",
] as const;
const importAuthorityPaths = [
  "tools/Invoke-DnfCatalogTool.ps1",
  ".github/skills/dnf-import-profession-text/scripts/Inspect-DnfProfessionText.ps1",
  ".github/skills/dnf-import-profession-text/scripts/Test-DnfImportPlan.ps1",
  ".github/skills/dnf-import-profession-text/scripts/Test-DnfPromptTree.ps1",
] as const;
const importMirrorPaths = [
  "SKILL.md",
  "agents/openai.yaml",
  "references/source-decomposition-contract.md",
  "scripts/Inspect-DnfProfessionText.ps1",
  "scripts/Test-DnfImportPlan.ps1",
  "scripts/Test-DnfPromptTree.ps1",
] as const;

interface ValidationSummary {
  schemaVersion: 1;
  status: "passed";
  repositoryRoot: string;
  modelIds: typeof MODEL_IDS;
  entrypointCount: number;
  toolCount: number;
  brokerExecutableToolCount: number;
  enabledProfileCount: number;
  importAuthorityCount: number;
  importMirrorCount: number;
  deploymentAuthorized: false;
  deploymentPerformed: false;
}

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function canonical(value: string): string {
  return value.normalize("NFC").toLocaleLowerCase();
}

function assertUnique(values: readonly string[], label: string): void {
  const observed = new Set<string>();
  for (const value of values) {
    const key = canonical(value);
    assert(!observed.has(key), `${label} contains a duplicate: ${value}`);
    observed.add(key);
  }
}

async function assertFile(
  repositoryRoot: string,
  relativePath: string,
  label: string,
): Promise<string> {
  const path = resolveInside(repositoryRoot, relativePath);
  assert(await fileExists(path), `${label} is missing: ${relativePath}`);
  await assertNoSymlinkChain(repositoryRoot, path);
  assert(
    (await stat(path)).isFile(),
    `${label} is not a file: ${relativePath}`,
  );
  return path;
}

async function assertPathWithinRepository(
  repositoryRoot: string,
  relativePath: string,
  label: string,
): Promise<string> {
  const path = resolveInside(repositoryRoot, relativePath);
  await assertNoSymlinkChain(repositoryRoot, path);
  assert(
    isPathInside(repositoryRoot, path),
    `${label} escapes the repository.`,
  );
  return path;
}

function assertAcyclicProfile(profile: ExecutionProfile): void {
  const dependencies = new Map(
    profile.steps.map((step) => [step.id, step.dependsOn]),
  );
  const visiting = new Set<string>();
  const visited = new Set<string>();
  const visit = (stepId: string): void => {
    if (visiting.has(stepId)) {
      throw new Error(
        `Execution profile ${profile.id} has a cycle at ${stepId}.`,
      );
    }
    if (visited.has(stepId)) {
      return;
    }
    visiting.add(stepId);
    for (const dependency of dependencies.get(stepId) ?? []) {
      visit(dependency);
    }
    visiting.delete(stepId);
    visited.add(stepId);
  };
  for (const stepId of dependencies.keys()) {
    visit(stepId);
  }
}

function validationRequest(profile: ExecutionProfile): RunRequest {
  return {
    schemaVersion: 1,
    runId: "desktop-static-validation",
    action: "generate-patch",
    provider: "mock",
    profession: profile.profession,
    theme: profile.theme,
    profileId: profile.id,
    selectedSkills: [...profile.selectedSkills],
    execute: false,
    resume: false,
    allowNetwork: false,
    generateImageReferences: false,
    outputBaseName: "desktop-static-validation",
    outputVersion: "1",
    deploymentAuthorized: false,
  };
}

function assertStepCatalogContract(
  profile: ExecutionProfile,
  catalog: ToolCatalog,
): void {
  const tools = new Map(catalog.tools.map((tool) => [tool.id, tool]));
  for (const step of profile.steps) {
    const tool = tools.get(step.toolId);
    assert(
      tool !== undefined,
      `Profile ${profile.id} references unknown tool ${step.toolId}.`,
    );
    const providedNames = Object.keys(step.arguments);
    for (const name of providedNames) {
      assert(
        tool.allowedParameters.includes(name),
        `Profile step ${step.id} provides disallowed parameter ${name}.`,
      );
    }
    for (const required of tool.requiredParameters) {
      assert(
        Object.hasOwn(step.arguments, required) ||
          Object.hasOwn(tool.forcedParameters, required),
        `Profile step ${step.id} does not provide required parameter ${required}.`,
      );
    }
  }
}

async function assertExpandedWriteBoundaries(
  repositoryRoot: string,
  profile: ExecutionProfile,
  catalog: ToolCatalog,
): Promise<void> {
  const expanded = expandExecutionProfile(profile, validationRequest(profile));
  const tools = new Map(catalog.tools.map((tool) => [tool.id, tool]));
  for (const step of expanded.steps) {
    const tool = tools.get(step.toolId);
    assert(tool !== undefined, `Expanded profile lost tool ${step.toolId}.`);
    const allowedRoots = await Promise.all(
      tool.allowedWriteRoots.map((path) =>
        assertPathWithinRepository(
          repositoryRoot,
          path,
          `Tool ${tool.id} write root`,
        ),
      ),
    );
    for (const output of step.expectedOutputs) {
      const outputPath = await assertPathWithinRepository(
        repositoryRoot,
        output,
        `Profile ${profile.id} output`,
      );
      assert(
        allowedRoots.some((root) => isPathInside(root, outputPath)),
        `Profile output is outside tool ${tool.id} write roots: ${output}`,
      );
    }
    for (const parameter of tool.writePathParameters) {
      const value = step.arguments[parameter];
      if (value === undefined) {
        continue;
      }
      assert(
        typeof value === "string",
        `Write parameter ${step.id}/${parameter} must be a string.`,
      );
      const valuePath = await assertPathWithinRepository(
        repositoryRoot,
        value,
        `Profile ${profile.id} write parameter`,
      );
      assert(
        allowedRoots.some((root) => isPathInside(root, valuePath)),
        `Write parameter ${step.id}/${parameter} is outside catalog roots.`,
      );
    }
  }
}

async function assertProfileBindings(
  repositoryRoot: string,
  profile: ExecutionProfile,
): Promise<void> {
  await assertFile(
    repositoryRoot,
    profile.themeAgentPath,
    `Profile ${profile.id} theme AGENTS`,
  );
  await assertFile(
    repositoryRoot,
    profile.control.baseConfigPath,
    `Profile ${profile.id} base config`,
  );
  assertUnique(
    profile.promptBindings.map((binding) => binding.displayName),
    `Profile ${profile.id} prompt display names`,
  );
  for (const binding of profile.promptBindings) {
    assert(
      profile.selectedSkills.includes(binding.displayName),
      `Profile ${profile.id} prompt binding is outside selectedSkills: ${binding.displayName}`,
    );
    await assertFile(
      repositoryRoot,
      binding.professionPromptPath,
      `Profile ${profile.id} profession Prompt`,
    );
    await assertFile(
      repositoryRoot,
      binding.themePromptPath,
      `Profile ${profile.id} theme Prompt`,
    );
  }
  assert(
    profile.promptBindings.length === profile.selectedSkills.length,
    `Profile ${profile.id} does not bind every selected skill Prompt.`,
  );
}

async function assertCatalog(
  repositoryRoot: string,
  catalog: ToolCatalog,
): Promise<void> {
  assertUnique(
    catalog.tools.map((tool) => tool.id),
    "Tool catalog IDs",
  );
  for (const tool of catalog.tools) {
    assertUnique(tool.allowedParameters, `Tool ${tool.id} allowed parameters`);
    assertUnique(tool.allowedWriteRoots, `Tool ${tool.id} write roots`);
    assert(
      tool.script.toLocaleLowerCase().endsWith(".ps1"),
      `Catalog tool is not a PowerShell script: ${tool.id}/${tool.script}`,
    );
    await assertFile(repositoryRoot, tool.script, `Catalog tool ${tool.id}`);
    for (const root of tool.allowedWriteRoots) {
      await assertPathWithinRepository(
        repositoryRoot,
        root,
        `Catalog tool ${tool.id} write root`,
      );
    }
    if (tool.mode === "workspace-write") {
      assert(
        tool.allowedWriteRoots.length > 0,
        `Workspace-write tool has no catalog write roots: ${tool.id}`,
      );
    }
  }
}

async function assertImportMirror(repositoryRoot: string): Promise<void> {
  for (const path of importMirrorPaths) {
    const githubPath = await assertFile(
      repositoryRoot,
      `.github/skills/dnf-import-profession-text/${path}`,
      "GitHub import skill mirror",
    );
    const codexPath = await assertFile(
      repositoryRoot,
      `.codex/skills/dnf-import-profession-text/${path}`,
      "Codex import skill",
    );
    const [githubBytes, codexBytes] = await Promise.all([
      readFile(githubPath),
      readFile(codexPath),
    ]);
    assert(
      sha256Buffer(githubBytes) === sha256Buffer(codexBytes),
      `Import skill mirror differs: ${path}`,
    );
  }
}

async function main(): Promise<void> {
  const repositoryRoot = await findRepositoryRoot([
    process.cwd(),
    resolve(dirname(new URL(import.meta.url).pathname), "../../.."),
  ]);

  assertUnique(Object.values(MODEL_IDS), "Model IDs");
  const modelIds: Readonly<Record<string, string>> = MODEL_IDS;
  assert(
    modelIds.orchestrator === "gpt-5.6-sol" &&
      modelIds.engineer === "gpt-5.5" &&
      modelIds.artist === "gpt-image-2",
    "The fixed model role mapping has drifted.",
  );

  for (const path of requiredDesktopEntrypoints) {
    await assertFile(repositoryRoot, path, "Desktop entrypoint");
  }
  await assertFile(repositoryRoot, hostScriptPath, "Catalog PowerShell host");
  for (const path of importAuthorityPaths) {
    await assertFile(repositoryRoot, path, "Import authority file");
  }

  const catalog = await loadToolCatalog(repositoryRoot);
  await assertCatalog(repositoryRoot, catalog);

  const index = executionProfileIndexSchema.parse(
    JSON.parse(
      await readFile(resolveInside(repositoryRoot, profileIndexPath), "utf8"),
    ) as unknown,
  );
  assertUnique(
    index.profiles.map((profile) => profile.id),
    "Execution profile registrations",
  );
  assertUnique(
    index.profiles.map((profile) => profile.path),
    "Execution profile paths",
  );
  const enabledProfiles = index.profiles.filter((profile) => profile.enabled);
  assert(enabledProfiles.length > 0, "No execution profile is enabled.");
  for (const registration of enabledProfiles) {
    await assertFile(
      repositoryRoot,
      registration.path,
      `Execution profile ${registration.id}`,
    );
    const profile = await loadExecutionProfile(repositoryRoot, registration.id);
    await assertProfileCatalogBinding(repositoryRoot, profile, catalog);
    assertAcyclicProfile(profile);
    assertStepCatalogContract(profile, catalog);
    await assertExpandedWriteBoundaries(repositoryRoot, profile, catalog);
    await assertProfileBindings(repositoryRoot, profile);
  }

  await assertImportMirror(repositoryRoot);

  const summary: ValidationSummary = {
    schemaVersion: 1,
    status: "passed",
    repositoryRoot,
    modelIds: MODEL_IDS,
    entrypointCount: requiredDesktopEntrypoints.length,
    toolCount: catalog.tools.length,
    brokerExecutableToolCount: catalog.tools.filter(
      (tool: ToolCatalogEntry) => tool.brokerExecutable,
    ).length,
    enabledProfileCount: enabledProfiles.length,
    importAuthorityCount: importAuthorityPaths.length,
    importMirrorCount: importMirrorPaths.length,
    deploymentAuthorized: false,
    deploymentPerformed: false,
  };
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`Desktop project validation failed: ${message}\n`);
  process.exitCode = 1;
});
