/**
 * @fileoverview 配置由 Server 隔离运行时编排的 remote API 浏览器验证。
 *
 * 该配置只运行 `tests/e2e-remote`，不会混入默认 Mock Playwright。Server harness 提供已构建
 * 页面、随机回环 URL 和 sandbox 输出目录；trace、截图、视频全部关闭，避免一次性登录字段
 * 进入持久测试产物。缺少任一显式环境时立即失败，不自行启动 Server 或回退 Mock。
 */
import { defineConfig } from "@playwright/test";

/** remote 场景必须由隔离总编排提供 URL 和临时输出目录。 */
export default defineConfig({
  testDir: "./e2e-remote",
  outputDir: requiredEnvironment("REAL_BROWSER_OUTPUT_DIR"),
  timeout: 30_000,
  fullyParallel: false,
  workers: 1,
  reporter: "list",
  use: {
    baseURL: requiredEnvironment("REAL_BROWSER_BASE_URL"),
    trace: "off",
    screenshot: "off",
    video: "off",
  },
});

/** 读取总编排注入的非空测试参数；值只进入 Playwright 配置，不写入报告。 */
function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required by the remote browser runtime test.`);
  }
  return value;
}
