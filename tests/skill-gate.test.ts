import { describe, expect, it } from "vitest";
import type { ProfessionSkillSummary } from "../renderer/src/api/contracts.js";
import { evaluateSkillExecution } from "../renderer/src/utils/skill-gate.js";

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
