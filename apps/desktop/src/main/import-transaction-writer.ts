import { mkdir, readFile, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import {
  importTransactionReceiptSchema,
  promptTreeResultSchema,
  type FileSnapshot,
  type ImportDesign,
  type ImportPlan,
  type PromptTreeResult,
  type RunRequest,
  type ToolResult,
} from "../shared/contracts.js";
import {
  buildImportTargetContent,
  canonicalImportName,
  updateCurrentFilesSection,
} from "./import-transaction-writer/content.js";
import {
  removeEmptyParents,
  type PreparedWrite,
} from "./import-transaction-writer/transaction-state.js";
import {
  assertNoSymlinkChain,
  fileExists,
  resolveInside,
  sha256Buffer,
  sha256Text,
  snapshotFile,
  writeFileAtomic,
  writeFileCreateNew,
} from "./lib/filesystem.js";
import type { RunStore } from "./run-store.js";
import { parseJsonOutput, type BrokerCall } from "./tool-broker.js";

export { buildImportTargetContent } from "./import-transaction-writer/content.js";

const CATALOG_HOST_PATH = "tools/Invoke-DnfCatalogTool.ps1";
const PROMPT_TREE_GATE_PATH =
  ".github/skills/dnf-import-profession-text/scripts/Test-DnfPromptTree.ps1";

export interface ImportTransactionResult {
  receiptPath: string;
  validationPath: string;
  validation: PromptTreeResult;
}

export interface ImportToolInvoker {
  invoke(call: BrokerCall): Promise<ToolResult>;
}

/**
 * 对固定 Prompt 目标执行职业级互斥、CAS、门禁、receipt 和逆序回滚。
 *
 * 模型只能提供经 schema 验证的文本片段；文件路径、模板结构、写操作和
 * 回滚都由本地代码控制。任何并发字节漂移都会在写入前硬失败。
 */
export class ImportTransactionWriter {
  constructor(
    readonly repositoryRoot: string,
    readonly store: RunStore,
    readonly broker: ImportToolInvoker,
  ) {}

  /** 复核上下文冻结后的规则和工具字节；允许忽略本事务自身目标。 */
  async #assertAuthoritySnapshots(
    snapshots: readonly FileSnapshot[],
    ignoredPaths: ReadonlySet<string> = new Set(),
  ): Promise<void> {
    const ignored = new Set(
      [...ignoredPaths].map((path) =>
        canonicalImportName(path.replaceAll("\\", "/")),
      ),
    );
    const seen = new Set<string>();
    for (const expected of snapshots) {
      const key = canonicalImportName(expected.path.replaceAll("\\", "/"));
      if (ignored.has(key) || seen.has(key)) {
        continue;
      }
      seen.add(key);

      let actual: FileSnapshot;
      try {
        actual = await snapshotFile(
          this.repositoryRoot,
          expected.path,
          expected.label,
          false,
        );
      } catch (error) {
        throw new Error(
          `Import authority input disappeared: ${expected.path}`,
          { cause: error },
        );
      }
      if (
        actual.sha256 !== expected.sha256 ||
        actual.length !== expected.length
      ) {
        throw new Error(
          `Import authority input changed after context freeze: ${expected.path}`,
        );
      }
    }
  }

  /** 生成目标字节并核对规划后快照，不在此阶段修改文件系统。 */
  async #prepare(
    plan: ImportPlan,
    design: ImportDesign,
    expectedTargetSnapshots: ReadonlyMap<string, FileSnapshot | undefined>,
  ): Promise<PreparedWrite[]> {
    const prepared: PreparedWrite[] = [];
    for (const target of plan.targets) {
      const absolutePath = resolveInside(
        this.repositoryRoot,
        target.relativePath,
      );
      await assertNoSymlinkChain(this.repositoryRoot, absolutePath);
      const exists = await fileExists(absolutePath);
      if (exists !== (target.state === "existing-file")) {
        throw new Error(
          `Import target state changed before transaction: ${target.relativePath}`,
        );
      }
      if (!expectedTargetSnapshots.has(target.relativePath)) {
        throw new Error(
          `Import target has no frozen post-plan snapshot: ${target.relativePath}`,
        );
      }

      const beforeBytes = exists ? await readFile(absolutePath) : undefined;
      const beforeSha256 = beforeBytes ? sha256Buffer(beforeBytes) : undefined;
      const expectedSnapshot = expectedTargetSnapshots.get(target.relativePath);
      if (
        Boolean(expectedSnapshot) !== exists ||
        (expectedSnapshot && expectedSnapshot.sha256 !== beforeSha256)
      ) {
        throw new Error(
          `Import target changed after model context freeze: ${target.relativePath}`,
        );
      }

      const generated = buildImportTargetContent(target, plan, design);
      let bytes: Uint8Array;
      let operation: PreparedWrite["operation"];
      if (beforeBytes && target.kind.endsWith("-index")) {
        // 索引是唯一允许机械更新的既有文件，并保留 BOM 与换行符。
        const hasBom =
          beforeBytes.length >= 3 &&
          beforeBytes[0] === 0xef &&
          beforeBytes[1] === 0xbb &&
          beforeBytes[2] === 0xbf;
        const existingText = beforeBytes.toString().replace(/^\uFEFF/u, "");
        const updated = updateCurrentFilesSection(
          existingText,
          (target.kind === "theme-index"
            ? plan.themePrompts
            : plan.prompts
          ).map((prompt) => prompt.fileName),
        );
        bytes = Buffer.from(`${hasBom ? "\uFEFF" : ""}${updated}`, "utf8");
        operation =
          sha256Buffer(bytes) === beforeSha256
            ? "preserved-existing"
            : "updated-index";
      } else if (beforeBytes) {
        // 既有规则和 Prompt 字节保持不动，模型不能覆盖高权威内容。
        bytes = beforeBytes;
        operation = "preserved-existing";
      } else {
        bytes = Buffer.from(generated, "utf8");
        operation = "created";
      }

      prepared.push({
        kind: target.kind,
        relativePath: target.relativePath,
        absolutePath,
        before: {
          existed: exists,
          ...(beforeBytes
            ? { bytes: beforeBytes, sha256: sha256Buffer(beforeBytes) }
            : {}),
        },
        bytes,
        sha256: sha256Buffer(bytes),
        operation,
      });
    }
    return prepared;
  }

  /** 按应用逆序恢复本事务字节；并发修改过的文件绝不覆盖。 */
  async #rollback(writes: PreparedWrite[]): Promise<string[]> {
    const failures: string[] = [];
    for (const write of [...writes].reverse()) {
      if (write.operation === "preserved-existing") {
        continue;
      }
      try {
        if (!(await fileExists(write.absolutePath))) {
          if (write.before.existed) {
            failures.push(`${write.relativePath}: target disappeared`);
          }
          continue;
        }
        const current = await readFile(write.absolutePath);
        if (sha256Buffer(current) !== write.sha256) {
          failures.push(`${write.relativePath}: bytes changed concurrently`);
          continue;
        }
        if (write.before.existed && write.before.bytes) {
          await writeFileAtomic(write.absolutePath, write.before.bytes);
        } else {
          await rm(write.absolutePath, { force: true });
          await removeEmptyParents(
            dirname(write.absolutePath),
            this.repositoryRoot,
          );
        }
      } catch (error) {
        failures.push(
          `${write.relativePath}: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }
    return failures;
  }

  /** 在真正写入前再次执行 CAS，并在写后立刻复核目标哈希。 */
  async #apply(write: PreparedWrite): Promise<void> {
    if (write.operation === "preserved-existing") {
      return;
    }
    const exists = await fileExists(write.absolutePath);
    if (exists !== write.before.existed) {
      throw new Error(
        `Import target state changed immediately before write: ${write.relativePath}`,
      );
    }
    if (exists) {
      const current = await readFile(write.absolutePath);
      if (sha256Buffer(current) !== write.before.sha256) {
        throw new Error(
          `Import target bytes changed immediately before write: ${write.relativePath}`,
        );
      }
      await writeFileAtomic(write.absolutePath, write.bytes);
    } else {
      await writeFileCreateNew(write.absolutePath, write.bytes);
    }
    const current = await readFile(write.absolutePath);
    if (sha256Buffer(current) !== write.sha256) {
      throw new Error(
        `Import target did not retain the committed bytes: ${write.relativePath}`,
      );
    }
  }

  /** 提交固定目标，门禁通过并完成最终复核后才生成 transaction receipt。 */
  async commit(
    request: RunRequest,
    plan: ImportPlan,
    design: ImportDesign,
    sourceRelativePath: string,
    expectedTargetSnapshots: ReadonlyMap<string, FileSnapshot | undefined>,
    authoritySnapshots: readonly FileSnapshot[],
  ): Promise<ImportTransactionResult> {
    const authorityByPath = new Map(
      authoritySnapshots.map((snapshot) => [
        canonicalImportName(snapshot.path.replaceAll("\\", "/")),
        snapshot,
      ]),
    );
    const hostScript = authorityByPath.get(
      canonicalImportName(CATALOG_HOST_PATH),
    );
    const gateScript = authorityByPath.get(
      canonicalImportName(PROMPT_TREE_GATE_PATH),
    );
    if (!hostScript || !gateScript) {
      throw new Error(
        "Import transaction is missing frozen host or Prompt tree gate authority.",
      );
    }

    // 锁按职业绝对身份哈希，防止两个 Run 同时修改同一 Prompt 树。
    const lockParent = resolve(this.store.root, ".locks");
    const professionLockIdentity = resolveInside(
      this.repositoryRoot,
      request.profession,
    )
      .normalize("NFC")
      .toLocaleLowerCase();
    const lockPath = resolve(
      lockParent,
      `import-${sha256Text(professionLockIdentity).slice(0, 24)}.lock`,
    );
    await mkdir(lockParent, { recursive: true });
    try {
      await mkdir(lockPath);
    } catch (error) {
      throw new Error(
        `Another import transaction holds the profession lock: ${request.profession}`,
        { cause: error },
      );
    }

    const appliedWrites: PreparedWrite[] = [];
    try {
      await this.#assertAuthoritySnapshots(authoritySnapshots);
      const writes = await this.#prepare(plan, design, expectedTargetSnapshots);
      const sourceBefore = await readFile(
        resolveInside(this.repositoryRoot, sourceRelativePath),
      );
      const sourceBeforeSha256 = sha256Buffer(sourceBefore);
      if (sourceBeforeSha256 !== plan.source.sha256) {
        throw new Error("Import source changed before transaction commit.");
      }

      for (const write of writes) {
        try {
          await this.#apply(write);
          if (write.operation !== "preserved-existing") {
            appliedWrites.push(write);
          }
        } catch (error) {
          // 写调用抛错后文件可能已成功落盘；哈希匹配时也必须纳入回滚。
          if (await fileExists(write.absolutePath)) {
            const current = await readFile(write.absolutePath);
            if (
              write.operation !== "preserved-existing" &&
              sha256Buffer(current) === write.sha256 &&
              !appliedWrites.includes(write)
            ) {
              appliedWrites.push(write);
            }
          }
          throw error;
        }
      }

      const gateResult = await this.broker.invoke({
        invocation: {
          schemaVersion: 1,
          runId: request.runId,
          callId: "import.validate-prompt-tree",
          toolId: "prompt-tree-gate",
          arguments: {
            ProfessionPath: request.profession,
            ...(request.theme
              ? { ThemePath: `${request.profession}/${request.theme}` }
              : {}),
            SourcePath: sourceRelativePath,
            ExpectedSourceSha256: plan.source.sha256,
            ExpectedPromptFileName: plan.prompts.map(
              (prompt) => prompt.fileName,
            ),
            ExpectedThemePromptFileName: plan.themePrompts.map(
              (prompt) => prompt.fileName,
            ),
            AllowedChangedRelativePath: plan.targets.map(
              (target) => target.relativePath,
            ),
            BaselineChange: plan.baselineChanges,
          },
          allowNetwork: false,
          execute: true,
        },
        expectedOutputs: [],
        expectedScriptSha256: gateScript.sha256,
        expectedHostScriptSha256: hostScript.sha256,
      });
      let validation: PromptTreeResult;
      try {
        validation = promptTreeResultSchema.parse(
          parseJsonOutput(gateResult.stdout),
        );
      } catch (error) {
        throw new Error("Prompt tree gate returned invalid JSON evidence.", {
          cause: error,
        });
      }
      const validationPath = await this.store.writeEvidence(
        request.runId,
        "imports/prompt-tree-result.json",
        validation,
      );
      if (
        gateResult.status !== "passed" ||
        gateResult.exitCode !== 0 ||
        validation.status !== "passed" ||
        validation.counts.errors !== 0
      ) {
        throw new Error(
          `Prompt tree gate failed: ${validation.errors
            .map((issue) => issue.message)
            .join(" | ")}`,
        );
      }

      // Receipt 前再次确认源、目标和非目标权威输入均未漂移。
      const sourceAfter = await readFile(
        resolveInside(this.repositoryRoot, sourceRelativePath),
      );
      if (sha256Buffer(sourceAfter) !== sourceBeforeSha256) {
        throw new Error("Import source bytes changed during transaction.");
      }
      for (const write of writes) {
        const current = await readFile(write.absolutePath);
        if (sha256Buffer(current) !== write.sha256) {
          throw new Error(
            `Committed target changed before receipt: ${write.relativePath}`,
          );
        }
      }
      await this.#assertAuthoritySnapshots(
        authoritySnapshots,
        new Set(plan.targets.map((target) => target.relativePath)),
      );

      const receipt = importTransactionReceiptSchema.parse({
        schemaVersion: 1,
        runId: request.runId,
        status: "passed",
        source: {
          relativePath: sourceRelativePath,
          sha256: sourceBeforeSha256,
          bytesPreserved: true,
        },
        route: {
          profession: request.profession,
          ...(request.theme ? { theme: request.theme } : {}),
        },
        targets: writes.map((write) => ({
          kind: write.kind,
          relativePath: write.relativePath,
          operation: write.operation,
          beforeSha256: write.before.sha256 ?? null,
          afterSha256: write.sha256,
        })),
        validationPath,
        warningCount: validation.counts.warnings,
        authoritySnapshots,
        inventoryPending: true,
        fullSkillCoverageProven: false,
        manifestCreatedOrModified: false,
        npkBuilt: false,
        deploymentAuthorized: false,
        deploymentPerformed: false,
      });
      const receiptPath = await this.store.writeEvidence(
        request.runId,
        "imports/transaction-receipt.json",
        receipt,
      );
      return { receiptPath, validationPath, validation };
    } catch (error) {
      const rollbackFailures = await this.#rollback(appliedWrites);
      if (rollbackFailures.length > 0) {
        throw new Error(
          `${error instanceof Error ? error.message : String(error)} Rollback was incomplete: ${rollbackFailures.join(" | ")}`,
          { cause: error },
        );
      }
      throw error;
    } finally {
      await rm(lockPath, { recursive: true, force: true });
    }
  }
}
