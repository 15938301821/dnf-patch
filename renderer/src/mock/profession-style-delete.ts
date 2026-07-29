/**
 * @fileoverview 为前端 Mock 模式注册职业风格删除路由；不替代真实 Server 所有权、事务或外键验证。
 *
 * 主 Mock Server 传入当前内存状态读取器和计数重算回调。本模块只删除无任务引用的私有/被驳回
 * 草稿，并返回与正式 API 一致的 204、404 或 409；生产记录存在时必须保留原状态。
 */
import type MockAdapter from "axios-mock-adapter";
import type {
  PatchTask,
  ProfessionStyle,
  ProfessionSummary,
} from "../server/contracts.js";

interface ProfessionStyleDeleteState {
  professions: ProfessionSummary[];
  styles: ProfessionStyle[];
  jobs: PatchTask[];
}

/**
 * 注册 `DELETE /professions/:professionId/styles/:styleId` 的同契约内存路由。
 *
 * @param mock 主 Mock Server 拥有的 Axios 适配器。
 * @param getState 每次请求时读取当前可变状态，避免重置后闭包持有旧对象。
 */
export function configureMockProfessionStyleDeleteRoute(
  mock: MockAdapter,
  getState: () => ProfessionStyleDeleteState,
): void {
  mock.onDelete(/\/professions\/[^/]+\/styles\/[^/]+$/u).reply((config) => {
    const state = getState();
    const parts = config.url?.split("/") ?? [];
    const professionId = parts[2] ?? "";
    const styleId = parts[4] ?? "";
    const styleIndex = state.styles.findIndex(
      (item) => item.id === styleId && item.professionId === professionId,
    );
    if (styleIndex < 0) {
      return [404, { code: "STYLE_NOT_FOUND", message: "职业风格不存在。" }];
    }
    const style = state.styles[styleIndex];
    const profession = state.professions.find(
      (item) => item.id === professionId,
    );
    const hasProduction = state.jobs.some(
      (job) =>
        job.professionName === profession?.name &&
        job.styleName === style?.name,
    );
    if (
      !style ||
      (style.publishStatus !== "private" &&
        style.publishStatus !== "rejected") ||
      hasProduction
    ) {
      return [
        409,
        {
          code: "STYLE_DELETE_NOT_ALLOWED",
          message: "仅可删除尚未进入生产链的私有或被驳回风格草稿。",
        },
      ];
    }
    state.styles.splice(styleIndex, 1);
    if (profession) {
      profession.styleCount = state.styles.filter(
        (item) => item.professionId === professionId,
      ).length;
      profession.updatedAt = new Date().toISOString();
    }
    return [204];
  });
}
