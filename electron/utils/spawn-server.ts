import { createHash } from "node:crypto";
import { lstat, readFile, realpath } from "node:fs/promises";
import { resolve } from "node:path";
import { spawn, type ChildProcess } from "node:child_process";

export interface LocalServerProcessState {
  status: "disabled" | "missing" | "started" | "stopped";
  detail: string;
}

/**
 * 只在显式环境开关启用时启动固定同级服务入口。无 shell、无 renderer 参数，
 * 因而不能退化为任意命令执行器；数据库迁移仍由部署流程独立完成。
 */
export class LocalServerProcess {
  #child: ChildProcess | undefined;

  async start(repositoryRoot: string): Promise<LocalServerProcessState> {
    if (process.env.DNF_PATCH_SERVER_AUTOSTART !== "true") {
      return { status: "disabled", detail: "服务自动启动未授权。" };
    }
    if (this.#child) {
      return { status: "started", detail: "服务进程已启动。" };
    }
    const serverRoot = resolve(repositoryRoot, "..", "dnf-patch-server");
    const entrypoint = resolve(serverRoot, "dist", "main.js");
    const expectedSha256 =
      process.env.DNF_PATCH_SERVER_ENTRY_SHA256?.trim().toUpperCase();
    if (!expectedSha256 || !/^[A-F0-9]{64}$/u.test(expectedSha256)) {
      return { status: "disabled", detail: "服务入口 SHA-256 未固定。" };
    }
    try {
      const item = await lstat(entrypoint);
      if (!item.isFile() || item.isSymbolicLink()) {
        return { status: "missing", detail: "固定服务入口不是普通文件。" };
      }
      if (
        canonicalPath(resolve(await realpath(entrypoint))) !==
        canonicalPath(entrypoint)
      ) {
        return { status: "missing", detail: "固定服务入口路径不一致。" };
      }
      if ((await sha256File(entrypoint)) !== expectedSha256) {
        return { status: "missing", detail: "固定服务入口 SHA-256 不匹配。" };
      }
    } catch {
      return { status: "missing", detail: "未找到已构建的固定服务入口。" };
    }
    this.#child = spawn(process.execPath, [entrypoint], {
      cwd: serverRoot,
      env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" },
      shell: false,
      stdio: "ignore",
      windowsHide: true,
    });
    this.#child.once("exit", () => {
      this.#child = undefined;
    });
    return { status: "started", detail: "固定本地服务入口已启动。" };
  }

  stop(): LocalServerProcessState {
    if (!this.#child) {
      return { status: "stopped", detail: "没有活动服务进程。" };
    }
    this.#child.kill();
    this.#child = undefined;
    return { status: "stopped", detail: "服务进程已请求停止。" };
  }
}

async function sha256File(path: string): Promise<string> {
  return createHash("sha256")
    .update(await readFile(path))
    .digest("hex")
    .toUpperCase();
}

function canonicalPath(path: string): string {
  return process.platform === "win32" ? path.toLocaleLowerCase() : path;
}
