/**
 * @fileoverview 声明 Vite 注入给 Renderer 的构建环境类型。
 *
 * 这些值由 Vite 构建或开发服务器生产，API 模式与 HTTP 客户端消费；本文件不读取环境、
 * 不产生运行时代码，也不允许声明凭据字段。三斜线指令必须保留，以加载 Vite 客户端类型。
 */
/// <reference types="vite/client" />

/** Renderer 可读取的非敏感构建参数；未知运行模式会由 API 层按远程模式处理。 */
interface ImportMetaEnv {
  readonly VITE_API_BASE_URL?: string;
  readonly VITE_API_MODE?: "mock" | "remote";
}

/** 为 `import.meta` 关联受约束的 Vite 环境结构。 */
interface ImportMeta {
  readonly env: ImportMetaEnv;
}
