/**
 * @fileoverview 配置浏览器目标的 Vite 开发服务器与生产构建。
 *
 * Vite CLI 读取 Renderer HTML 和 React 源码，开发时只监听回环地址，构建时写入受管
 * `dist-web/` 并清理旧输出。端口可由根启动器选择，但始终只监听回环地址；本配置不启动
 * API、Worker 或 Electron，也不读取凭据。
 */
import { resolve } from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

/** 读取可选的非敏感开发端口；直接运行保持 5173，拒绝会被 Vite 隐式修正的非法值。 */
function rendererDevelopmentPort(): number {
  const port = Number(process.env.DNF_PATCH_RENDERER_PORT ?? "5173");
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error(
      "DNF_PATCH_RENDERER_PORT must be an integer from 1 to 65535.",
    );
  }
  return port;
}

/** 浏览器 Renderer 的 Vite 配置，由开发、构建和预览脚本消费。 */
export default defineConfig({
  root: resolve("renderer"),
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: rendererDevelopmentPort(),
    strictPort: true,
  },
  build: {
    outDir: resolve("dist-web"),
    emptyOutDir: true,
    rollupOptions: {
      input: resolve("renderer/index.html"),
    },
  },
});
