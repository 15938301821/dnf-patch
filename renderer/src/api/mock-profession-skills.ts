import type { ProfessionSkillSummary } from "./contracts.js";

const swordSoulCandidateNames = [
  "里·鬼剑术",
  "三段斩",
  "流心：刺",
  "流心：跃",
  "流心：升",
  "破军升龙击",
  "拔刀斩",
  "猛龙断空斩",
  "破军斩龙击",
  "幻影剑舞",
  "极·鬼剑术（暴风式）",
  "极·神剑术（流星落）",
  "极·神剑术（破空斩）",
  "极·神剑术（瞬斩）",
  "万剑极诣·开天斩",
  "三觉 Cut-in",
] as const;

export const swordSoulCandidateSkillIds = swordSoulCandidateNames.map(
  (_, index) => `sword-soul-candidate-${String(index + 1).padStart(3, "0")}`,
);

export const mockProfessionSkills: ProfessionSkillSummary[] =
  swordSoulCandidateNames.map((displayName, index) => ({
    id: swordSoulCandidateSkillIds[index] ?? "",
    professionId: "profession-sword-soul",
    displayName,
    promptStatus: "candidate",
    mappingStatus: "unverified",
    executionStatus: "draft-only",
  }));

export function areSelectedSkillsValid(
  skills: readonly ProfessionSkillSummary[],
  professionId: string,
  selectedSkillIds: readonly string[],
  allowEmpty = false,
): boolean {
  if (selectedSkillIds.length === 0) {
    return allowEmpty;
  }
  const professionSkillIds = new Set(
    skills
      .filter((skill) => skill.professionId === professionId)
      .map((skill) => skill.id),
  );
  return selectedSkillIds.every((skillId) => professionSkillIds.has(skillId));
}
