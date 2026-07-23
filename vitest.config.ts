/**
 * @fileoverview 配置客户端纯逻辑与 Mock API 的 Vitest 单元测试边界。
 *
 * Vitest CLI 在 Node 环境读取 `tests` 目录下的 `*.test.ts`，不启动真实浏览器、Electron 或后端；
 * 当前关闭覆盖率输出，避免在仓库生成未受管报告。本配置只影响测试发现与运行环境。
 */
import { defineConfig } from "vitest/config";

/** 客户端单元测试运行配置，由 `npm run test:unit` 消费。 */
export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
    coverage: {
      enabled: false,
    },
  },
});
