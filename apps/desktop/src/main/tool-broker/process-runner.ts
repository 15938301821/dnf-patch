import { spawn } from "node:child_process";
import { resolve } from "node:path";
import type { ToolCatalogEntry } from "../../shared/tool-catalog.js";

const SECRET_ENVIRONMENT_NAME = /(api.?key|token|secret|password|credential)/iu;
export const MAX_TOOL_OUTPUT_BYTES = 8 * 1024 * 1024;

/** 固定工具子进程的有界输出结果。 */
export interface ProcessResult {
  exitCode: number | null;
  stdout: string;
  stderr: string;
  timedOut: boolean;
  outputLimitExceeded?: "stdout" | "stderr";
}

/** 从子进程环境中删除常见凭据名称，避免工具继承模型或宿主密钥。 */
function processEnvironment(): NodeJS.ProcessEnv {
  return Object.fromEntries(
    Object.entries(process.env).filter(
      ([name, value]) =>
        value !== undefined && !SECRET_ENVIRONMENT_NAME.test(name),
    ),
  );
}

/** 按 catalog 指定的位数解析系统 Windows PowerShell 5.1。 */
export function powershellPath(host: ToolCatalogEntry["host"]): string {
  const windows = process.env.SystemRoot ?? process.env.WINDIR ?? "C:\\Windows";
  const architectureDirectory =
    host === "windows-powershell-x86" ? "SysWOW64" : "System32";
  return resolve(
    windows,
    architectureDirectory,
    "WindowsPowerShell",
    "v1.0",
    "powershell.exe",
  );
}

/**
 * 执行无 shell 子进程，并分别限制 stdout/stderr 的内存占用。
 *
 * 任一流超限后立即终止进程并返回已捕获前缀。调用方必须把超限视为
 * 失败，不能解析截断内容或把它作为成功证据。
 */
export async function runBoundedProcess(
  executable: string,
  args: readonly string[],
  cwd: string,
  timeoutMs: number,
  maxOutputBytes: number,
): Promise<ProcessResult> {
  if (!Number.isSafeInteger(maxOutputBytes) || maxOutputBytes <= 0) {
    throw new Error("Process output limit must be a positive safe integer.");
  }
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs <= 0) {
    throw new Error("Process timeout must be a positive safe integer.");
  }

  return new Promise((resolveResult, reject) => {
    const child = spawn(executable, [...args], {
      cwd,
      windowsHide: true,
      shell: false,
      env: processEnvironment(),
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let timedOut = false;
    let outputLimitExceeded: ProcessResult["outputLimitExceeded"];

    /** 捕获不超过硬上限的字节，并在首次超限时终止工具。 */
    const capture = (stream: "stdout" | "stderr", chunk: Buffer): void => {
      const currentBytes = stream === "stdout" ? stdoutBytes : stderrBytes;
      const remaining = Math.max(0, maxOutputBytes - currentBytes);
      const retained = remaining > 0 ? chunk.subarray(0, remaining) : undefined;
      if (retained && retained.length > 0) {
        if (stream === "stdout") {
          stdoutChunks.push(retained);
          stdoutBytes += retained.length;
        } else {
          stderrChunks.push(retained);
          stderrBytes += retained.length;
        }
      }
      if (chunk.length > remaining && outputLimitExceeded === undefined) {
        outputLimitExceeded = stream;
        child.kill();
      }
    };

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill();
    }, timeoutMs);
    child.stdout.on("data", (chunk: Buffer) => capture("stdout", chunk));
    child.stderr.on("data", (chunk: Buffer) => capture("stderr", chunk));
    child.once("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.once("close", (exitCode) => {
      clearTimeout(timer);
      resolveResult({
        exitCode,
        stdout: Buffer.concat(stdoutChunks, stdoutBytes).toString("utf8"),
        stderr: Buffer.concat(stderrChunks, stderrBytes).toString("utf8"),
        timedOut,
        ...(outputLimitExceeded ? { outputLimitExceeded } : {}),
      });
    });
  });
}
