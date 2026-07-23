/**
 * @fileoverview 验证 Mock 职业风格 API 的私有草稿、结构门禁和后续动作阻断。
 *
 * Axios Mock Adapter 替代真实 Server、审核、Worker 与资源目录，并在每例前清空状态；测试只
 * 证明前端替身与客户端 DTO 语义一致，不证明真实数据库事务、授权或任务执行。
 */
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  createProfessionStyle,
  createPatchTask,
  submitStyleForReview,
  server,
  type CreateProfessionStyleInput,
} from "../renderer/src/api/index.js";
import { configureMockApi } from "../renderer/src/mock/index.js";
import { createEmptyStyleInput } from "../renderer/src/utils/profession-style.js";

beforeAll(() => {
  // 同契约替身复用客户端门禁，但不是第二套可部署后端。
  configureMockApi();
});

beforeEach(async () => {
  await server.post("/__mock/reset");
});

describe("profession style API", () => {
  it("allows a private draft without a skill catalog", async () => {
    const input = createEmptyStyleInput();
    input.name = "狂战士主题草稿";

    await expect(
      createProfessionStyle("profession-berserker", input),
    ).resolves.toMatchObject({
      name: "狂战士主题草稿",
      selectedSkillIds: [],
      skillPrompts: [],
      publishStatus: "private",
    });
  });

  it("rejects prompt rows outside the selected skill set", async () => {
    const input = createEmptyStyleInput();
    input.name = "无效主题";
    input.skillPrompts = [emptySkillPrompt("skill-outside-selection")];

    await expect(
      createProfessionStyle("profession-berserker", input),
    ).rejects.toMatchObject({
      response: { status: 400, data: { code: "STYLE_CONTENT_INVALID" } },
    });
  });

  it("blocks review and jobs when structured content is incomplete", async () => {
    // 先创建允许不完整的私有草稿，再确认两个高风险后续动作都被服务端语义阻断。
    const created = await createProfessionStyle(
      "profession-berserker",
      draft("未完成主题"),
    );

    await expect(
      submitStyleForReview("profession-berserker", created.id),
    ).rejects.toMatchObject({
      response: { status: 409, data: { code: "STYLE_CONTENT_INCOMPLETE" } },
    });
    await expect(
      createPatchTask({
        professionId: "profession-berserker",
        styleId: created.id,
      }),
    ).rejects.toMatchObject({
      response: { status: 409, data: { code: "STYLE_CONTENT_INCOMPLETE" } },
    });
  });
});

/** 根据场景名称创建不完整但结构有效的私有测试草稿。 */
function draft(name: string): CreateProfessionStyleInput {
  return { ...createEmptyStyleInput(), name };
}

/** 为指定稳定 ID 构造空的逐技能 Prompt 行，用于制造集合漂移。 */
function emptySkillPrompt(
  skillId: string,
): CreateProfessionStyleInput["skillPrompts"][number] {
  return {
    skillId,
    themePrompt: "",
    changes: "",
    acceptanceCriteria: "",
    exclusions: "",
  };
}
