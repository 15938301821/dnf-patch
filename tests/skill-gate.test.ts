/**
 * @fileoverview 验证技能制作门禁对目录缺失、越界 ID 与未核验资源采取失败关闭策略。
 *
 * 测试以手写技能摘要调用纯函数，不读取真实职业目录或资源；它只证明客户端是否允许发起任务
 * 请求，不证明后端授权、NPK/IMG 映射、Worker 能力或产物兼容性。
 */
import { describe, expect, it } from "vitest";
import type { ProfessionSkillSummary } from "../renderer/src/server/contracts.js";
import { evaluateSkillExecution } from "../renderer/src/utils/skill-gate.js";

/**
 * 构造默认可制作的技能摘要，并允许用例覆盖单个门禁字段。
 *
 * @param overrides 当前场景要替换的后端摘要字段。
 * @returns 不与其他用例共享的技能测试 DTO。
 */
function skill(
  overrides: Partial<ProfessionSkillSummary> = {},
): ProfessionSkillSummary {
  return {
    id: "skill-verified",
    professionId: "profession-test",
    displayName: "测试技能",
    promptStatus: "reviewed",
    mappingStatus: "verified",
    executionStatus: "build-ready",
    ...overrides,
  };
}

describe("skill execution gate", () => {
  it("blocks an unavailable skill catalog", () => {
    expect(evaluateSkillExecution([], [])).toMatchObject({
      allowed: false,
      reason: "skills-catalog-unavailable",
    });
  });

  it("requires a selected skill when the catalog exists", () => {
    expect(evaluateSkillExecution([], [skill()])).toMatchObject({
      allowed: false,
      reason: "skills-required",
    });
  });

  it("rejects ids outside the profession catalog", () => {
    expect(evaluateSkillExecution(["missing"], [skill()])).toMatchObject({
      allowed: false,
      blockedSkillIds: ["missing"],
      reason: "skill-not-found",
    });
  });

  it("keeps unverified resources in design-only mode", () => {
    expect(
      evaluateSkillExecution(
        ["skill-candidate"],
        [
          skill({
            id: "skill-candidate",
            mappingStatus: "unverified",
            executionStatus: "draft-only",
          }),
        ],
      ),
    ).toMatchObject({
      allowed: false,
      blockedSkillIds: ["skill-candidate"],
      reason: "resources-unverified",
    });
  });

  it("allows only verified build-ready resources", () => {
    expect(evaluateSkillExecution(["skill-verified"], [skill()])).toEqual({
      allowed: true,
      blockedSkillIds: [],
      reason: "ready",
    });
  });
});
