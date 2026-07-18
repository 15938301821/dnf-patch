import { lstat, readdir, stat } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import {
  toolInvocationSchema,
  toolResultSchema,
  type FileSnapshot,
  type ToolInvocation,
  type ToolResult,
} from "../shared/contracts.js";
import type { ToolCatalog, ToolCatalogEntry } from "../shared/tool-catalog.js";
import {
  assertNoSymlinkChain,
  fileExists,
  isPathInside,
  normalizeRelativePath,
  resolveInside,
  sha256Text,
  snapshotFile,
  stableStringify,
} from "./lib/filesystem.js";
import type { RunStore } from "./run-store.js";
import {
  MAX_TOOL_OUTPUT_BYTES,
  powershellPath,
  runBoundedProcess,
  type ProcessResult,
} from "./tool-broker/process-runner.js";

const HOST_SCRIPT = "tools/Invoke-DnfCatalogTool.ps1";
const DEFAULT_TIMEOUT_MS = 45 * 60 * 1_000;

export interface BrokerCall {
  invocation: ToolInvocation;
  expectedOutputs: string[];
  expectedScriptSha256?: string;
  expectedHostScriptSha256?: string;
  timeoutMs?: number;
}

interface PreparedCall {
  tool: ToolCatalogEntry;
  scriptPath: string;
  scriptSha256: string;
  arguments: Record<string, unknown>;
  expectedOutputs: string[];
}

function sameJson(left: unknown, right: unknown): boolean {
  return stableStringify(left) === stableStringify(right);
}

async function listOutputFiles(path: string): Promise<string[]> {
  const item = await lstat(path);
  if (item.isSymbolicLink()) {
    throw new Error(`Output cannot be a symbolic link or junction: ${path}`);
  }
  if (item.isFile()) {
    return [path];
  }
  if (!item.isDirectory()) {
    throw new Error(`Expected output has an unsupported type: ${path}`);
  }
  const files: string[] = [];
  for (const entry of await readdir(path, { withFileTypes: true })) {
    const child = resolve(path, entry.name);
    if (entry.isSymbolicLink()) {
      throw new Error(`Output cannot contain a symbolic link: ${child}`);
    }
    if (entry.isDirectory()) {
      files.push(...(await listOutputFiles(child)));
    } else if (entry.isFile()) {
      files.push(child);
    }
  }
  return files;
}

function resolveArgumentPath(repositoryRoot: string, value: string): string {
  return isAbsolute(value)
    ? resolve(value)
    : resolveInside(repositoryRoot, normalizeRelativePath(value));
}

export function parseKeyValueOutput(text: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of text.split(/\r\n|\n|\r/u)) {
    const match = /^(?<key>[A-Za-z][A-Za-z0-9]*)=(?<value>.*)$/u.exec(line);
    if (!match?.groups) {
      continue;
    }
    const key = match.groups.key;
    const value = match.groups.value;
    if (key === undefined || value === undefined) {
      throw new Error("Tool output contains an invalid key/value line.");
    }
    if (Object.hasOwn(result, key)) {
      throw new Error(`Tool output contains duplicate key: ${key}`);
    }
    result[key] = value;
  }
  return result;
}

export function parseJsonOutput(text: string): unknown {
  const trimmed = text.trim().replace(/^\uFEFF/u, "");
  if (!trimmed) {
    throw new Error("Tool did not return JSON output.");
  }
  try {
    return JSON.parse(trimmed) as unknown;
  } catch {
    const starts = [...trimmed.matchAll(/[[{]/gu)].map((match) => match.index);
    for (const start of starts.reverse()) {
      try {
        return JSON.parse(trimmed.slice(start)) as unknown;
      } catch {
        // Continue until a complete trailing JSON value is found.
      }
    }
    throw new Error("Tool output does not contain a complete JSON value.");
  }
}

export class ToolBroker {
  readonly #tools: Map<string, ToolCatalogEntry>;

  constructor(
    readonly repositoryRoot: string,
    readonly store: RunStore,
    readonly catalog: ToolCatalog,
  ) {
    this.#tools = new Map(catalog.tools.map((tool) => [tool.id, tool]));
  }

  async #resolveWritePath(
    tool: ToolCatalogEntry,
    value: string,
    label: string,
  ): Promise<string> {
    const absolutePath = resolveArgumentPath(this.repositoryRoot, value);
    if (!isPathInside(this.repositoryRoot, absolutePath)) {
      throw new Error(`${label} must stay inside the repository.`);
    }
    const allowed = tool.allowedWriteRoots.some((root) =>
      isPathInside(resolveInside(this.repositoryRoot, root), absolutePath),
    );
    if (!allowed) {
      throw new Error(`${label} is outside the catalog write roots: ${value}`);
    }
    await assertNoSymlinkChain(this.repositoryRoot, absolutePath);
    return absolutePath;
  }

  async #prepare(call: BrokerCall): Promise<PreparedCall> {
    const invocation = toolInvocationSchema.parse(call.invocation);
    const tool = this.#tools.get(invocation.toolId);
    if (!tool) {
      throw new Error(`Tool is not registered: ${invocation.toolId}`);
    }
    if (!tool.brokerExecutable) {
      throw new Error(`Tool is not broker executable: ${tool.id}`);
    }
    if (!invocation.execute) {
      throw new Error("Catalog execution requires execute=true.");
    }
    if (invocation.allowNetwork || tool.network !== "forbidden") {
      throw new Error(`Catalog tool network access is forbidden: ${tool.id}`);
    }

    const allowedNames = new Map(
      tool.allowedParameters.map((name) => [name.toLocaleLowerCase(), name]),
    );
    const argumentsValue: Record<string, unknown> = {};
    for (const [providedName, value] of Object.entries(invocation.arguments)) {
      const canonicalName = allowedNames.get(providedName.toLocaleLowerCase());
      if (!canonicalName) {
        throw new Error(
          `Parameter is not allowlisted for ${tool.id}: ${providedName}`,
        );
      }
      argumentsValue[canonicalName] = value;
    }
    for (const [name, value] of Object.entries(tool.forcedParameters)) {
      if (
        Object.hasOwn(argumentsValue, name) &&
        !sameJson(argumentsValue[name], value)
      ) {
        throw new Error(
          `Parameter ${name} conflicts with the catalog-forced value.`,
        );
      }
      argumentsValue[name] = value;
    }
    for (const name of tool.requiredParameters) {
      if (!Object.hasOwn(argumentsValue, name)) {
        throw new Error(
          `Required parameter is missing for ${tool.id}: ${name}`,
        );
      }
    }

    for (const name of tool.pathParameters) {
      const value = argumentsValue[name];
      if (value === undefined || value === null || value === "") {
        continue;
      }
      if (typeof value !== "string") {
        throw new Error(`Path parameter must be a string: ${name}`);
      }
      const absolutePath = tool.writePathParameters.includes(name)
        ? await this.#resolveWritePath(tool, value, `Parameter ${name}`)
        : resolveArgumentPath(this.repositoryRoot, value);
      if (isPathInside(this.repositoryRoot, absolutePath)) {
        await assertNoSymlinkChain(this.repositoryRoot, absolutePath);
      }
      argumentsValue[name] = absolutePath;
    }

    const expectedOutputs: string[] = [];
    for (const value of call.expectedOutputs) {
      const absolutePath = await this.#resolveWritePath(
        tool,
        value,
        "Expected output",
      );
      if (await fileExists(absolutePath)) {
        throw new Error(
          `Refusing to overwrite expected output: ${absolutePath}`,
        );
      }
      expectedOutputs.push(absolutePath);
    }
    for (const name of tool.writePathParameters) {
      const value = argumentsValue[name];
      if (typeof value === "string" && (await fileExists(value))) {
        throw new Error(
          `Refusing to overwrite write parameter ${name}: ${value}`,
        );
      }
    }

    const scriptPath = resolveInside(this.repositoryRoot, tool.script);
    await assertNoSymlinkChain(this.repositoryRoot, scriptPath);
    const scriptItem = await stat(scriptPath);
    if (!scriptItem.isFile()) {
      throw new Error(`Catalog script is not a file: ${tool.script}`);
    }
    const scriptSnapshot = await snapshotFile(
      this.repositoryRoot,
      tool.script,
      `Catalog script ${tool.id}`,
      false,
    );
    if (
      call.expectedScriptSha256 &&
      scriptSnapshot.sha256 !== call.expectedScriptSha256
    ) {
      throw new Error(
        `Catalog script changed after context freeze: ${tool.script}`,
      );
    }
    return {
      tool,
      scriptPath,
      scriptSha256: scriptSnapshot.sha256,
      arguments: argumentsValue,
      expectedOutputs,
    };
  }

  async #snapshotOutputs(paths: string[]): Promise<FileSnapshot[]> {
    const snapshots: FileSnapshot[] = [];
    const seen = new Set<string>();
    for (const output of paths) {
      if (!(await fileExists(output))) {
        throw new Error(`Expected output was not created: ${output}`);
      }
      await assertNoSymlinkChain(this.repositoryRoot, output);
      for (const file of await listOutputFiles(output)) {
        const relativePath = this.store.toRelative(file);
        if (seen.has(relativePath)) {
          continue;
        }
        seen.add(relativePath);
        snapshots.push(
          await snapshotFile(
            this.repositoryRoot,
            relativePath,
            `Tool output ${relativePath}`,
            false,
          ),
        );
      }
    }
    return snapshots.sort((left, right) => left.path.localeCompare(right.path));
  }

  async invoke(call: BrokerCall): Promise<ToolResult> {
    const invocation = toolInvocationSchema.parse(call.invocation);
    const evidenceRoot = `tools/${invocation.callId}`;
    await this.store.writeEvidence(
      invocation.runId,
      `${evidenceRoot}/invocation.json`,
      invocation,
    );
    const startedAtUtc = new Date().toISOString();
    let scriptSha256 = sha256Text("unresolved-catalog-script");
    let parametersSha256 = sha256Text(stableStringify(invocation.arguments));
    let processResult: ProcessResult = {
      exitCode: null,
      stdout: "",
      stderr: "",
      timedOut: false,
    };
    let outputs: FileSnapshot[] = [];
    let error: string | undefined;
    let status: ToolResult["status"];

    try {
      const prepared = await this.#prepare(call);
      scriptSha256 = prepared.scriptSha256;
      parametersSha256 = sha256Text(stableStringify(prepared.arguments));
      const hostScriptPath = resolveInside(this.repositoryRoot, HOST_SCRIPT);
      const hostScriptSnapshot = await snapshotFile(
        this.repositoryRoot,
        HOST_SCRIPT,
        "Catalog PowerShell host",
        false,
      );
      if (
        call.expectedHostScriptSha256 &&
        hostScriptSnapshot.sha256 !== call.expectedHostScriptSha256
      ) {
        throw new Error(
          `Catalog PowerShell host changed after context freeze: ${HOST_SCRIPT}`,
        );
      }
      const hostRequestPath = await this.store.writeEvidence(
        invocation.runId,
        `${evidenceRoot}/host-request.json`,
        {
          schemaVersion: 1,
          runId: invocation.runId,
          callId: invocation.callId,
          toolId: prepared.tool.id,
          repositoryRoot: this.repositoryRoot,
          scriptPath: prepared.scriptPath,
          scriptSha256: prepared.scriptSha256,
          hostScriptSha256: hostScriptSnapshot.sha256,
          arguments: prepared.arguments,
          expectedOutputs: prepared.expectedOutputs.map((path) =>
            this.store.toRelative(path),
          ),
          networkAuthorized: false,
          deploymentAuthorized: false,
        },
      );
      processResult = await runBoundedProcess(
        powershellPath(prepared.tool.host),
        [
          "-NoLogo",
          "-NoProfile",
          "-NonInteractive",
          "-ExecutionPolicy",
          "Bypass",
          "-File",
          hostScriptPath,
          "-HostRequestPath",
          resolveInside(this.repositoryRoot, hostRequestPath),
        ],
        this.repositoryRoot,
        call.timeoutMs ?? DEFAULT_TIMEOUT_MS,
        MAX_TOOL_OUTPUT_BYTES,
      );
      if (processResult.timedOut) {
        throw new Error(`Tool timed out: ${prepared.tool.id}`);
      }
      if (processResult.outputLimitExceeded) {
        throw new Error(
          `Tool ${processResult.outputLimitExceeded} exceeded ${String(MAX_TOOL_OUTPUT_BYTES)} bytes: ${prepared.tool.id}`,
        );
      }
      if (processResult.exitCode !== 0) {
        throw new Error(
          `Tool exited with code ${String(processResult.exitCode)}: ${prepared.tool.id}`,
        );
      }
      outputs = await this.#snapshotOutputs(prepared.expectedOutputs);
      status = "passed";
    } catch (caught) {
      error = caught instanceof Error ? caught.message : String(caught);
      status = processResult.exitCode === null ? "blocked" : "failed";
    }

    await this.store.writeTextEvidence(
      invocation.runId,
      `${evidenceRoot}/stdout.txt`,
      processResult.stdout,
    );
    await this.store.writeTextEvidence(
      invocation.runId,
      `${evidenceRoot}/stderr.txt`,
      processResult.stderr,
    );
    const result = toolResultSchema.parse({
      schemaVersion: 1,
      runId: invocation.runId,
      callId: invocation.callId,
      toolId: invocation.toolId,
      status,
      startedAtUtc,
      finishedAtUtc: new Date().toISOString(),
      exitCode: processResult.exitCode,
      stdout: processResult.stdout,
      stderr: processResult.stderr,
      parametersSha256,
      scriptSha256,
      outputs,
      deploymentAuthorized: false,
      ...(error ? { error } : {}),
    });
    await this.store.writeEvidence(
      invocation.runId,
      `${evidenceRoot}/result.json`,
      result,
    );
    return result;
  }
}
