/**
 * @fileoverview 汇总 Renderer 页面允许使用的类型化 HTTP API 与共享 DTO。
 *
 * 页面从此入口消费认证、职业、模型、任务和资源导入能力；本文件只重导出，不发请求、
 * 不复制服务端逻辑。`server` 主要供同契约 Mock 与测试安装适配器，业务页面不得绕过领域 API。
 */
export * from "./auth.js";
export * from "../server/contracts.js";
export * from "./jobs.js";
export * from "./model-configuration.js";
export * from "./professions.js";
export * from "./resource-imports.js";
export { server } from "../server/server.js";
