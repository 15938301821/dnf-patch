/**
 * @fileoverview 解析并导出浏览器客户端使用的 API 运行模式。
 *
 * 本模块只把 Vite 环境值收敛为稳定枚举，供入口和界面标识消费；不创建网络客户端，
 * 也不决定服务端地址。读取 `import.meta.env` 是唯一外部输入，未知值按远程模式处理，
 * 避免部署环境因拼写错误而静默启用仅供开发使用的 Mock API。
 */

/** 客户端可选择的正式远程 API 或前端 Mock API 模式。 */
export type ApiMode = "mock" | "remote";

/**
 * 将构建环境值收敛为客户端支持的 API 模式。
 *
 * @param value Vite 注入的原始模式；只有精确的 `mock` 才允许启用前端替身。
 * @returns 可供入口和组件直接判断的模式，缺失或未知值均为 `remote`。
 */
export function resolveApiMode(value: string | undefined): ApiMode {
  return value === "mock" ? "mock" : "remote";
}

/** 当前构建实例的 API 模式，由应用入口决定是否安装 Mock 适配器。 */
export const apiMode = resolveApiMode(import.meta.env.VITE_API_MODE);
