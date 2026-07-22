import type {
  SaveProfessionStyleInput,
  SkillThemePrompt,
  ThemeDefinition,
} from "../api/contracts.js";

export const STYLE_PROMPT_PACKAGE_MAX_BYTES = 48 * 1_024;

export type StyleCompletenessReason =
  | "theme-incomplete"
  | "skills-required"
  | "skill-prompts-mismatch"
  | "skill-prompts-incomplete"
  | "prompt-package-too-large";

export interface StyleCompletenessGate {
  allowed: boolean;
  incompleteSkillIds: string[];
  reasons: StyleCompletenessReason[];
}

export interface StyleDraftValidity {
  allowed: boolean;
  reasons: Array<
    Extract<
      StyleCompletenessReason,
      "skill-prompts-mismatch" | "prompt-package-too-large"
    >
  >;
}

const requiredThemeFields: ReadonlyArray<
  Exclude<keyof ThemeDefinition, "schemaVersion" | "colorAnchors">
> = [
  "goal",
  "baseStyle",
  "materialRules",
  "particleRules",
  "layeringRules",
  "constraints",
  "acceptanceCriteria",
  "exclusions",
];

const requiredSkillFields: ReadonlyArray<
  Exclude<keyof SkillThemePrompt, "skillId">
> = ["themePrompt", "changes", "acceptanceCriteria", "exclusions"];

/** Evaluates whether a private style draft is complete enough for review. */
export function evaluateStyleCompleteness(
  style: SaveProfessionStyleInput,
): StyleCompletenessGate {
  const reasons: StyleCompletenessReason[] = [];
  if (!isThemeComplete(style.themeDefinition)) {
    reasons.push("theme-incomplete");
  }
  if (style.selectedSkillIds.length === 0) {
    reasons.push("skills-required");
  }

  const selectedIds = new Set(style.selectedSkillIds);
  const promptIds = new Set(style.skillPrompts.map((prompt) => prompt.skillId));
  if (
    selectedIds.size !== style.selectedSkillIds.length ||
    promptIds.size !== style.skillPrompts.length ||
    selectedIds.size !== promptIds.size ||
    [...selectedIds].some((skillId) => !promptIds.has(skillId))
  ) {
    reasons.push("skill-prompts-mismatch");
  }

  const incompleteSkillIds = style.skillPrompts
    .filter((prompt) =>
      requiredSkillFields.some((field) => !prompt[field].trim()),
    )
    .map((prompt) => prompt.skillId);
  if (incompleteSkillIds.length > 0) {
    reasons.push("skill-prompts-incomplete");
  }
  if (stylePromptPackageBytes(style) > STYLE_PROMPT_PACKAGE_MAX_BYTES) {
    reasons.push("prompt-package-too-large");
  }

  return {
    allowed: reasons.length === 0,
    incompleteSkillIds,
    reasons,
  };
}

/** Validates invariants required even when incomplete private drafts are saved. */
export function evaluateStyleDraftValidity(
  style: SaveProfessionStyleInput,
): StyleDraftValidity {
  const completeness = evaluateStyleCompleteness(style);
  const reasons = completeness.reasons.filter(
    (reason): reason is StyleDraftValidity["reasons"][number] =>
      reason === "skill-prompts-mismatch" ||
      reason === "prompt-package-too-large",
  );
  return { allowed: reasons.length === 0, reasons };
}

/** Returns the UTF-8 size of the content that will be frozen into a task. */
export function stylePromptPackageBytes(
  style: Pick<SaveProfessionStyleInput, "themeDefinition" | "skillPrompts">,
): number {
  return new TextEncoder().encode(
    JSON.stringify({
      schemaVersion: 1,
      themeDefinition: style.themeDefinition,
      skillPrompts: style.skillPrompts,
    }),
  ).byteLength;
}

function isThemeComplete(theme: ThemeDefinition): boolean {
  return (
    requiredThemeFields.every((field) => theme[field].trim()) &&
    theme.colorAnchors.length > 0 &&
    theme.colorAnchors.every(
      (anchor) => anchor.name.trim() && /^#[A-Fa-f0-9]{6}$/u.test(anchor.value),
    )
  );
}
