import type { ProfessionSkillSummary } from "../server/contracts.js";

export type SkillExecutionGateReason =
  | "skills-catalog-unavailable"
  | "skills-required"
  | "skill-not-found"
  | "resources-unverified"
  | "ready";

export interface SkillExecutionGate {
  allowed: boolean;
  blockedSkillIds: string[];
  reason: SkillExecutionGateReason;
}

export function evaluateSkillExecution(
  selectedSkillIds: readonly string[],
  skills: readonly ProfessionSkillSummary[],
): SkillExecutionGate {
  if (skills.length === 0) {
    return {
      allowed: false,
      blockedSkillIds: [],
      reason: "skills-catalog-unavailable",
    };
  }
  if (selectedSkillIds.length === 0) {
    return {
      allowed: false,
      blockedSkillIds: [],
      reason: "skills-required",
    };
  }

  const skillsById = new Map(skills.map((skill) => [skill.id, skill]));
  const selectedSkills = selectedSkillIds.map((skillId) =>
    skillsById.get(skillId),
  );
  if (selectedSkills.some((skill) => skill === undefined)) {
    return {
      allowed: false,
      blockedSkillIds: selectedSkillIds.filter(
        (skillId) => !skillsById.has(skillId),
      ),
      reason: "skill-not-found",
    };
  }

  const blockedSkillIds = selectedSkills
    .filter((skill) => skill?.executionStatus !== "build-ready")
    .map((skill) => skill?.id)
    .filter((skillId): skillId is string => skillId !== undefined);
  if (blockedSkillIds.length > 0) {
    return {
      allowed: false,
      blockedSkillIds,
      reason: "resources-unverified",
    };
  }

  return { allowed: true, blockedSkillIds: [], reason: "ready" };
}
