/**
 * @fileoverview 定义 Mock 模式的剑魂候选技能目录及选择合法性检查。
 *
 * Mock 风格种子和 Mock Server 消费这些稳定 ID；数据是前端替身事实，不是客户端发现结果，
 * 也不证明 NPK、IMG 或帧映射已经核验。模块只做确定性数组构造和纯校验。
 */
import type { ProfessionSkillSummary } from "../server/contracts.js";

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

/** 与候选名称按索引一一对应的 Mock 技能稳定 ID。 */
export const swordSoulCandidateSkillIds = swordSoulCandidateNames.map(
  (_, index) => `sword-soul-candidate-${String(index + 1).padStart(3, "0")}`,
);

/** Mock Server 返回的只读语义技能摘要，全部保持仅设计和资源未核验状态。 */
export const mockProfessionSkills: ProfessionSkillSummary[] =
  swordSoulCandidateNames.map((displayName, index) => ({
    id: swordSoulCandidateSkillIds[index] ?? "",
    professionId: "profession-sword-soul",
    displayName,
    promptStatus: "candidate",
    mappingStatus: "unverified",
    executionStatus: "draft-only",
  }));

/**
 * 判断提交的技能 ID 是否全部属于指定职业的 Mock 目录。
 *
 * @param skills Mock Server 当前技能集合，而非浏览器推断结果。
 * @param professionId 请求路径中的职业稳定 ID。
 * @param selectedSkillIds 写入 DTO 中尚未信任的技能稳定 ID。
 * @param allowEmpty 私有草稿是否允许暂时没有技能。
 * @returns 空值策略满足且每个 ID 均属于该职业时返回 `true`。
 */
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
