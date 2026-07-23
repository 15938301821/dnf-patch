/**
 * @fileoverview 纯函数计算风格所选技能是否具备创建制作任务的资源条件。
 *
 * 风格编辑页和同契约 Mock API 提供所选稳定 ID 与后端技能目录，本模块返回界面门禁结果；
 * 不发请求、不发现技能，也不推断 NPK、IMG 或帧映射。只有后端目录明确标记为可制作的技能
 * 才能放行，目录缺失、越界 ID 与未核验资源均必须失败关闭。
 */
import type { ProfessionSkillSummary } from "../server/contracts.js";

/** 技能制作门禁的稳定原因，供页面提示与 Mock 错误语义共同消费。 */
export type SkillExecutionGateReason =
  | "skills-catalog-unavailable"
  | "skills-required"
  | "skill-not-found"
  | "resources-unverified"
  | "ready";

/** 技能制作门禁结果；阻断 ID 只描述输入问题，不代表客户端已核验资源。 */
export interface SkillExecutionGate {
  /** 是否允许进入后端任务创建请求。 */
  allowed: boolean;
  /** 不存在于目录或尚不可制作的所选技能稳定 ID。 */
  blockedSkillIds: string[];
  /** 页面可映射为用户提示的首要门禁原因。 */
  reason: SkillExecutionGateReason;
}

/**
 * 按目录存在性、选择合法性和资源状态依次评估任务门禁。
 *
 * @param selectedSkillIds 风格草稿提交的技能稳定 ID，尚未信任其属于当前职业。
 * @param skills 后端返回的当前职业技能摘要；空数组表示目录当前不可用。
 * @returns 失败关闭的门禁结果；`ready` 只代表前端允许发请求，最终授权仍由后端决定。
 */
export function evaluateSkillExecution(
  selectedSkillIds: readonly string[],
  skills: readonly ProfessionSkillSummary[],
): SkillExecutionGate {
  // 第一步：没有服务端事实目录时不能靠客户端猜测技能或资源状态。
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

  // 第二步：确认每个稳定 ID 均属于当前目录，越界选择不得进入资源判定。
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

  // 第三步：仅目录明确声明 build-ready 的技能可通过；其余保持仅设计模式。
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
