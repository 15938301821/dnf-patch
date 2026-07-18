import { Buffer } from "node:buffer";
import { describe, expect, it } from "vitest";
import { runBoundedProcess } from "../src/main/tool-broker/process-runner.js";

const TEST_TIMEOUT_MS = 10_000;

/** 使用当前 Node 可执行文件测试跨平台子进程边界，不依赖 PowerShell 安装。 */
async function runNode(
  source: string,
  maxOutputBytes = 1024,
): ReturnType<typeof runBoundedProcess> {
  return runBoundedProcess(
    process.execPath,
    ["--eval", source],
    process.cwd(),
    TEST_TIMEOUT_MS,
    maxOutputBytes,
  );
}

describe("bounded process runner", () => {
  it("preserves complete output below the configured limit", async () => {
    const result = await runNode(
      'process.stdout.write("result"); process.stderr.write("detail");',
    );

    expect(result).toMatchObject({
      exitCode: 0,
      stdout: "result",
      stderr: "detail",
      timedOut: false,
    });
    expect(result.outputLimitExceeded).toBeUndefined();
  });

  it("marks oversized stdout and never retains bytes beyond the limit", async () => {
    const limit = 64;
    const result = await runNode(
      'process.stdout.write("x".repeat(4096));',
      limit,
    );

    expect(result.outputLimitExceeded).toBe("stdout");
    expect(Buffer.byteLength(result.stdout, "utf8")).toBe(limit);
    expect(result.timedOut).toBe(false);
  });

  it("does not expose inherited secret environment variables", async () => {
    const name = "DNF_PATCH_TEST_TOKEN";
    const previous = process.env[name];
    process.env[name] = "must-not-leak";
    try {
      const result = await runNode(
        `process.stdout.write(process.env.${name} ?? "missing");`,
      );
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toBe("missing");
    } finally {
      if (previous === undefined) {
        Reflect.deleteProperty(process.env, name);
      } else {
        process.env[name] = previous;
      }
    }
  });
});
