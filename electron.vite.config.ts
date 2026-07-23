/**
 * @fileoverview 配置 Electron 主进程、最小 Preload 与共用 Renderer 的构建入口。
 *
 * electron-vite 在开发和桌面构建时消费本配置，输入为仓库手写入口，输出只写受管 `out/`；
 * 不打包业务后端或本机工具。Preload 固定输出 CommonJS 文件供主进程加载，Renderer 仍使用
 * `renderer/` 与其环境目录；开发服务器只监听回环地址并占用固定端口。
 */
import { resolve } from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "electron-vite";

/** Electron 三进程目标的构建配置，由 electron-vite CLI 消费。 */
export default defineConfig({
  main: {
    build: {
      externalizeDeps: true,
      rollupOptions: {
        input: { index: resolve("electron/main.ts") },
      },
    },
  },
  preload: {
    build: {
      externalizeDeps: false,
      rollupOptions: {
        input: { index: resolve("electron/preload.ts") },
        output: {
          format: "cjs",
          entryFileNames: "[name].cjs",
        },
      },
    },
  },
  renderer: {
    root: resolve("renderer"),
    envDir: resolve("renderer"),
    plugins: [react()],
    server: {
      host: "127.0.0.1",
      port: 5173,
      strictPort: true,
    },
    build: {
      rollupOptions: {
        input: resolve("renderer/index.html"),
      },
    },
  },
});
