/**
 * @fileoverview 验证职业风格值创建、技能 Prompt 对齐和旧响应规范化。
 *
 * 测试只操作内存对象，不调用 API 或挂载表单；它保护可变数组隔离和兼容映射不发明逐技能
 * 内容，但不证明真实旧数据迁移、服务端写入或页面交互。
 */
import { describe, expect, it } from "vitest";
import {
  createEmptyStyleInput,
  normalizeProfessionStyle,
  reconcileSkillPrompts,
} from "../renderer/src/utils/profession-style.js";

describe("profession style values", () => {
  it("creates independent empty drafts", () => {
    const first = createEmptyStyleInput();
    const second = createEmptyStyleInput();
    first.themeDefinition.colorAnchors.push({ name: "主色", value: "#FFFFFF" });

    expect(second.themeDefinition.colorAnchors).toEqual([]);
  });

  it("preserves selected prompts in selection order", () => {
    expect(
      reconcileSkillPrompts(
        ["skill-b", "skill-a"],
        [
          {
            skillId: "skill-a",
            themePrompt: "prompt-a",
            changes: "changes-a",
            acceptanceCriteria: "accept-a",
            exclusions: "exclude-a",
          },
        ],
      ),
    ).toEqual([
      {
        skillId: "skill-b",
        themePrompt: "",
        changes: "",
        acceptanceCriteria: "",
        exclusions: "",
      },
      {
        skillId: "skill-a",
        themePrompt: "prompt-a",
        changes: "changes-a",
        acceptanceCriteria: "accept-a",
        exclusions: "exclude-a",
      },
    ]);
  });

  it("maps legacy agent and prompt only into the common theme layer", () => {
    const normalized = normalizeProfessionStyle({
      id: "style-legacy",
      professionId: "profession-test",
      name: "旧主题",
      description: "旧数据",
      agent: "保持源语义",
      prompt: "cold blue energy",
      selectedSkillIds: ["skill-a"],
      publishStatus: "private",
      updatedAt: "2026-07-22T00:00:00.000Z",
    });

    expect(normalized.themeDefinition).toMatchObject({
      baseStyle: "cold blue energy",
      constraints: "保持源语义",
    });
    expect(normalized.skillPrompts).toEqual([
      expect.objectContaining({ skillId: "skill-a", themePrompt: "" }),
    ]);
  });
});
