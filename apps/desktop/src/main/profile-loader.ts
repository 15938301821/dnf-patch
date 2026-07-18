import { readFile } from "node:fs/promises";
import {
  executionProfileIndexSchema,
  executionProfileSchema,
  type ExecutionProfile,
} from "../shared/profile.js";
import { toolCatalogSchema, type ToolCatalog } from "../shared/tool-catalog.js";
import { resolveInside } from "./lib/filesystem.js";

const CATALOG_PATH = "tools/catalog/dnf-tools.json";
const PROFILE_INDEX_PATH = "tools/profiles/index.json";

async function readJson(path: string): Promise<unknown> {
  return JSON.parse(await readFile(path, "utf8")) as unknown;
}

export async function loadToolCatalog(
  repositoryRoot: string,
): Promise<ToolCatalog> {
  return toolCatalogSchema.parse(
    await readJson(resolveInside(repositoryRoot, CATALOG_PATH)),
  );
}

export async function loadExecutionProfile(
  repositoryRoot: string,
  profileId: string,
): Promise<ExecutionProfile> {
  const index = executionProfileIndexSchema.parse(
    await readJson(resolveInside(repositoryRoot, PROFILE_INDEX_PATH)),
  );
  const registration = index.profiles.find(
    (candidate) => candidate.id === profileId && candidate.enabled,
  );
  if (!registration) {
    throw new Error(`Execution profile is not registered: ${profileId}`);
  }
  const profile = executionProfileSchema.parse(
    await readJson(resolveInside(repositoryRoot, registration.path)),
  );
  if (profile.id !== registration.id) {
    throw new Error(
      `Execution profile identity mismatch: ${registration.id}/${profile.id}`,
    );
  }
  return profile;
}

export async function assertProfileCatalogBinding(
  repositoryRoot: string,
  profile: ExecutionProfile,
  catalog?: ToolCatalog,
): Promise<ToolCatalog> {
  const resolvedCatalog = catalog ?? (await loadToolCatalog(repositoryRoot));
  const tools = new Map(resolvedCatalog.tools.map((tool) => [tool.id, tool]));
  const stepIds = new Set(profile.steps.map((step) => step.id));
  for (const step of profile.steps) {
    const tool = tools.get(step.toolId);
    if (!tool) {
      throw new Error(
        `Profile ${profile.id} references unknown tool ${step.toolId}.`,
      );
    }
    if (!tool.brokerExecutable || !tool.defaultGenerationEligible) {
      throw new Error(`Tool is not eligible for profile execution: ${tool.id}`);
    }
    if (tool.mode !== step.mode) {
      throw new Error(`Profile/tool mode mismatch: ${step.id}/${tool.id}`);
    }
    if (
      tool.scope === "profession-specific" &&
      tool.professionId !== profile.professionId
    ) {
      throw new Error(
        `Profile/tool profession mismatch: ${profile.id}/${tool.id}`,
      );
    }
    for (const dependency of step.dependsOn) {
      if (!stepIds.has(dependency) || dependency === step.id) {
        throw new Error(
          `Invalid dependency in profile ${profile.id}: ${step.id}/${dependency}`,
        );
      }
    }
  }
  return resolvedCatalog;
}

export function assertProfileRequestBinding(
  profile: ExecutionProfile,
  profession: string,
  theme: string | undefined,
  selectedSkills: string[],
): void {
  if (profile.profession !== profession || profile.theme !== theme) {
    throw new Error(
      `Request route does not match profile ${profile.id}: ${profession}/${theme ?? ""}`,
    );
  }
  const requested = new Set(selectedSkills);
  if (
    requested.size > 0 &&
    [...requested].some((skill) => !profile.selectedSkills.includes(skill))
  ) {
    throw new Error(`Request selects a skill outside profile ${profile.id}.`);
  }
}
