/**
 * @fileoverview 验证 Mock 职业删除 API 的空内容门禁；不证明真实数据库事务或用户所有权。
 *
 * Axios Mock Adapter 替代真实 Server，并在每例前重置状态。测试只证明客户端 DELETE 契约与
 * Mock 的技能/风格保护语义一致，不能替代真实 MySQL 限制性外键验证。
 */
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  createProfession,
  deleteProfession,
  getProfessionsList,
  server,
} from "../renderer/src/api/index.js";
import { configureMockApi } from "../renderer/src/mock/index.js";

beforeAll(() => configureMockApi());
beforeEach(async () => server.post("/__mock/reset"));

describe("profession deletion API", () => {
  it("deletes a newly created empty private profession", async () => {
    const created = await createProfession({
      name: "待删除职业",
      slug: "deletable-profession",
    });

    await expect(deleteProfession(created.id)).resolves.toBeUndefined();
    await expect(getProfessionsList()).resolves.not.toContainEqual(
      expect.objectContaining({ id: created.id }),
    );
  });

  it("rejects a profession that still owns skills or styles", async () => {
    await expect(
      deleteProfession("profession-sword-soul"),
    ).rejects.toMatchObject({
      response: {
        status: 409,
        data: { code: "PROFESSION_DELETE_NOT_ALLOWED" },
      },
    });
  });
});
