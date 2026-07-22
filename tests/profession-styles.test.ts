import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  createProfessionStyle,
  createPatchTask,
  submitStyleForReview,
  server,
  type CreateProfessionStyleInput,
} from "../renderer/src/api/index.js";
import { configureMockApi } from "../renderer/src/api/mock-server.js";
import { createEmptyStyleInput } from "../renderer/src/utils/profession-style.js";

beforeAll(() => {
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

function draft(name: string): CreateProfessionStyleInput {
  return { ...createEmptyStyleInput(), name };
}

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
