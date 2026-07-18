import { randomBytes } from "node:crypto";
import { resolve } from "node:path";
import { defineConfig } from "@playwright/test";

// Playwright 会在创建 worker 前递归删除旧输出。Windows 索引器或报告查看器若仍持有
// 证据文件句柄，该删除会阻塞整个门禁，因此每次 CLI 进程使用独立目录。目录保留在
// 仓库卷内，以便测试把 .runs 证据原子搬入失败报告，不触发 Windows 跨卷错误。
// 配置会在主进程、加载器和 worker 中分别求值；首次生成 token 后写入环境，后续
// 子进程继承同一 token，确保用例证据与 .last-run.json 永远落在同一目录。
const runTokenEnvironment = "DNF_PATCH_PLAYWRIGHT_RUN_TOKEN";
const runTokenPattern = /^[a-f0-9]{32}$/u;
const inheritedRunToken = process.env[runTokenEnvironment]?.trim();
const runToken =
  inheritedRunToken !== undefined && runTokenPattern.test(inheritedRunToken)
    ? inheritedRunToken
    : randomBytes(16).toString("hex");
process.env[runTokenEnvironment] = runToken;
const outputDir = resolve(
  import.meta.dirname,
  "test-results",
  `run-${runToken}`,
);

export default defineConfig({
  testDir: "./tests",
  outputDir,
  // Windows 上递归删除刚写完的证据树可能被索引器无限阻塞。每次运行已有唯一
  // 目录且 test-results 被 Git 忽略，因此成功与失败证据均保留供审计和人工清理。
  preserveOutput: "always",
  timeout: 30_000,
  fullyParallel: false,
  workers: 1,
  reporter: "list",
  use: {
    trace: "retain-on-failure",
  },
});
