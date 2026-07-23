/**
 * @fileoverview 配置浏览器 Playwright E2E 的目录、产物和本地预览服务器。
 *
 * `npm run test:e2e` 消费本配置，先由项目脚本构建浏览器与桌面目标，再让浏览器测试连接
 * 回环预览地址；跟踪和结果只写受管测试目录。单 Worker 保持共享 Mock 状态隔离，本配置不
 * 证明真实后端、Worker、模型或对象存储集成。
 */
import { defineConfig } from "@playwright/test";

/** 浏览器 E2E 运行器配置；Electron 用例由同一测试目录中的专用启动代码管理。 */
export default defineConfig({
  testDir: "./tests/e2e",
  outputDir: "./test-results",
  timeout: 30_000,
  fullyParallel: true,
  workers: 1,
  reporter: "list",
  use: {
    baseURL: "http://127.0.0.1:4173",
    trace: "retain-on-failure",
  },
  webServer: {
    command: "npm run preview -- --host 127.0.0.1 --port 4173 --strictPort",
    url: "http://127.0.0.1:4173",
    reuseExistingServer: false,
  },
});
