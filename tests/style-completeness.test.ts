import { describe, expect, it } from "vitest";
import type { SaveProfessionStyleInput } from "../renderer/src/api/contracts.js";
import {
  STYLE_PROMPT_PACKAGE_MAX_BYTES,
  evaluateStyleDraftValidity,
  evaluateStyleCompleteness,
  stylePromptPackageBytes,
} from "../renderer/src/utils/style-completeness.js";

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
