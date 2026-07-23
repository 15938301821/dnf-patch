/**
 * @fileoverview 验证风格草稿保存、送审完整性和 UTF-8 冻结包大小门禁。
 *
 * 测试使用内存 DTO 调用纯函数，保护技能 Prompt 漂移和超限内容不能进入后续动作；未调用真实
 * Server 或 Worker，不证明后端授权、资源核验、模型生成或产物验证。
 */
import { describe, expect, it } from "vitest";
import type { SaveProfessionStyleInput } from "../renderer/src/server/contracts.js";
import {
  STYLE_PROMPT_PACKAGE_MAX_BYTES,
  evaluateStyleDraftValidity,
  evaluateStyleCompleteness,
  stylePromptPackageBytes,
} from "../renderer/src/utils/style-completeness.js";

/** @returns 满足当前客户端完整性规则的独立结构化测试草稿。 */
function completeStyle(): SaveProfessionStyleInput {
  return {
    name: "暗蓝幻影",
    description: "冷色剑气主题",
    themeDefinition: {
      schemaVersion: 1,
      goal: "保持动作语义并追加暗蓝幻影视觉。",
      baseStyle: "icy cobalt-blue energy, clean sharp blade edges",
      colorAnchors: [{ name: "冰蓝主光", value: "#1A8FFF" }],
      materialRules: "使用白色刃核与冰蓝外辉光。",
      particleRules: "粒子稀疏且方向明确。",
      layeringRules: "裂纹在后，剑刃居中，辉光在前。",
      constraints: "保持源帧几何、锚点和动作阶段。",
      acceptanceCriteria: "动作轮廓和命中焦点保持可读。",
      exclusions: "排除暖色、无关 UI 与文字。",
    },
    selectedSkillIds: ["skill-draw-slash"],
    skillPrompts: [
      {
        skillId: "skill-draw-slash",
        themePrompt: "horizontal dimensional rift",
        changes: "水平斩痕转为冰蓝次元裂隙。",
        acceptanceCriteria: "水平裂隙保持主辨识。",
        exclusions: "排除密集剑阵遮挡主切线。",
      },
    ],
  };
}

describe("style completeness", () => {
  it("accepts a complete structured style", () => {
    expect(evaluateStyleCompleteness(completeStyle())).toEqual({
      allowed: true,
      incompleteSkillIds: [],
      reasons: [],
    });
  });

  it("allows an incomplete private draft but reports review blockers", () => {
    // 私有保存与送审门禁必须区分，避免缺字段草稿被误判为完全无效。
    const style = completeStyle();
    style.themeDefinition.goal = "";
    style.selectedSkillIds = [];
    style.skillPrompts = [];

    expect(evaluateStyleCompleteness(style)).toMatchObject({
      allowed: false,
      reasons: ["theme-incomplete", "skills-required"],
    });
    expect(evaluateStyleDraftValidity(style)).toEqual({
      allowed: true,
      reasons: [],
    });
  });

  it("detects selected skill and prompt collection drift", () => {
    // 人为制造一一对应关系漂移，模拟表单合并或旧数据造成的结构风险。
    const style = completeStyle();
    const prompt = style.skillPrompts[0];
    if (!prompt) throw new Error("TEST_PROMPT_REQUIRED");
    style.skillPrompts[0] = {
      ...prompt,
      skillId: "skill-outside-selection",
    };

    expect(evaluateStyleCompleteness(style).reasons).toContain(
      "skill-prompts-mismatch",
    );
    expect(evaluateStyleDraftValidity(style).allowed).toBe(false);
  });

  it("enforces the frozen prompt package budget", () => {
    const style = completeStyle();
    const prompt = style.skillPrompts[0];
    if (!prompt) throw new Error("TEST_PROMPT_REQUIRED");
    style.skillPrompts[0] = {
      ...prompt,
      themePrompt: "x".repeat(STYLE_PROMPT_PACKAGE_MAX_BYTES),
    };

    expect(stylePromptPackageBytes(style)).toBeGreaterThan(
      STYLE_PROMPT_PACKAGE_MAX_BYTES,
    );
    expect(evaluateStyleCompleteness(style).reasons).toContain(
      "prompt-package-too-large",
    );
  });
});
