import type {
  ProfessionStyle,
  SaveProfessionStyleInput,
  SkillThemePrompt,
  ThemeDefinition,
} from "../server/contracts.js";

interface LegacyProfessionStyle {
  id: string;
  professionId: string;
  name: string;
  description: string;
  agent: string;
  prompt: string;
  selectedSkillIds: string[];
  publishStatus: ProfessionStyle["publishStatus"];
  updatedAt: string;
}

/** Creates a new empty theme value without sharing mutable arrays. */
export function createEmptyThemeDefinition(): ThemeDefinition {
  return {
    schemaVersion: 1,
    goal: "",
    baseStyle: "",
    colorAnchors: [],
    materialRules: "",
    particleRules: "",
    layeringRules: "",
    constraints: "",
    acceptanceCriteria: "",
    exclusions: "",
  };
}

/** Creates a private style draft that may be saved before it is complete. */
export function createEmptyStyleInput(): SaveProfessionStyleInput {
  return {
    name: "",
    description: "",
    themeDefinition: createEmptyThemeDefinition(),
    selectedSkillIds: [],
    skillPrompts: [],
  };
}

/** Preserves selected skill drafts while removing stale and adding empty rows. */
export function reconcileSkillPrompts(
  selectedSkillIds: readonly string[],
  current: readonly SkillThemePrompt[],
): SkillThemePrompt[] {
  const currentBySkillId = new Map(
    current.map((prompt) => [prompt.skillId, prompt]),
  );
  return selectedSkillIds.map(
    (skillId) =>
      currentBySkillId.get(skillId) ?? createEmptySkillPrompt(skillId),
  );
}

/** Maps the previous agent/prompt response into the V2 common theme layer. */
export function normalizeProfessionStyle(
  style: ProfessionStyle | LegacyProfessionStyle,
): ProfessionStyle {
  if ("themeDefinition" in style) {
    return style;
  }
  return {
    id: style.id,
    professionId: style.professionId,
    name: style.name,
    description: style.description,
    themeDefinition: {
      ...createEmptyThemeDefinition(),
      baseStyle: style.prompt,
      constraints: style.agent,
    },
    selectedSkillIds: style.selectedSkillIds,
    skillPrompts: reconcileSkillPrompts(style.selectedSkillIds, []),
    publishStatus: style.publishStatus,
    updatedAt: style.updatedAt,
  };
}

export function hasSkillPromptContent(prompt: SkillThemePrompt): boolean {
  return [
    prompt.themePrompt,
    prompt.changes,
    prompt.acceptanceCriteria,
    prompt.exclusions,
  ].some((value) => value.trim().length > 0);
}

function createEmptySkillPrompt(skillId: string): SkillThemePrompt {
  return {
    skillId,
    themePrompt: "",
    changes: "",
    acceptanceCriteria: "",
    exclusions: "",
  };
}
