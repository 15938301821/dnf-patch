/**
 * @fileoverview 暴露 Renderer 入口安装 Mock API 所需的唯一函数。
 *
 * 本文件只重导出，不安装拦截器；真实副作用发生在入口显式调用 `configureMockApi` 时。
 */
export { configureMockApi } from "./server.js";
