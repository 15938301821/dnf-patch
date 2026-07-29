/**
 * @fileoverview 为前端 Mock 模式注册职业删除路由；不替代真实 Server 的所有权、事务或外键验证。
 *
 * 主 Mock Server 传入当前内存状态读取器。本模块只删除无技能、无风格的私有/被驳回职业，
 * 并返回与正式 API 一致的 204、404 或 409；受保护职业必须保留原状态。
 */
import type MockAdapter from "axios-mock-adapter";
import type {
  ProfessionSkillSummary,
  ProfessionStyle,
  ProfessionSummary,
} from "../server/contracts.js";

interface ProfessionDeleteState {
  professions: ProfessionSummary[];
  skills: ProfessionSkillSummary[];
  styles: ProfessionStyle[];
}

/**
 * 注册 `DELETE /professions/:professionId` 的同契约内存路由。
 * @param mock 主 Mock Server 拥有的 Axios 适配器。
 * @param getState 每次请求时读取当前可变状态，避免 Mock 重置后持有旧对象。
 */
export function configureMockProfessionDeleteRoute(
  mock: MockAdapter,
  getState: () => ProfessionDeleteState,
): void {
  mock.onDelete(/\/professions\/[^/]+$/u).reply((config) => {
    const state = getState();
    const professionId = config.url?.split("/")[2] ?? "";
    const professionIndex = state.professions.findIndex(
      (item) => item.id === professionId,
    );
    if (professionIndex < 0) {
      return [404, { code: "PROFESSION_NOT_FOUND", message: "职业不存在。" }];
    }
    const profession = state.professions[professionIndex];
    const hasContent =
      state.skills.some((skill) => skill.professionId === professionId) ||
      state.styles.some((style) => style.professionId === professionId);
    if (
      !profession ||
      (profession.publishStatus !== "private" &&
        profession.publishStatus !== "rejected") ||
      hasContent
    ) {
      return [
        409,
        {
          code: "PROFESSION_DELETE_NOT_ALLOWED",
          message: "仅可删除没有技能目录和职业风格的私有或被驳回职业。",
        },
      ];
    }
    state.professions.splice(professionIndex, 1);
    return [204];
  });
}
