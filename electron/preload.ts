/**
 * @fileoverview 在 Renderer 加载前断言 Electron 隔离与沙箱安全条件。
 *
 * 主进程把本文件作为 Preload 执行；它不向页面暴露 Node、IPC、业务 API 或全局桥接对象，
 * 也不读取任何业务数据。若隔离或沙箱缺失则立即抛错，禁止以弱化配置继续启动 Renderer。
 */

if (!process.contextIsolated || !process.sandboxed) {
  throw new Error(
    "DNF Patch Studio requires context isolation and renderer sandboxing.",
  );
}

export {};
