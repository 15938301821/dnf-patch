import { mkdir, readFile, rm, rmdir } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
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
import type { RunStore } from "./run-store.js";
import { parseJsonOutput, type BrokerCall } from "./tool-broker.js";
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

interface BeforeImage {
  existed: boolean;
  bytes?: Uint8Array;
  sha256?: string;
}

interface PreparedWrite {
  kind: ImportPlan["targets"][number]["kind"];
  relativePath: string;
  absolutePath: string;
  before: BeforeImage;
  bytes: Uint8Array;
  sha256: string;
  operation: "created" | "updated-index" | "preserved-existing";
}

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

function canonicalName(value: string): string {
  return value.normalize("NFC").toLocaleLowerCase();
}

function lineEnding(text: string): "\r\n" | "\n" | "\r" {
  const match = /\r\n|\n|\r/u.exec(text);
  return (match?.[0] as "\r\n" | "\n" | "\r" | undefined) ?? "\n";
}

function normalizedIndexHeading(value: string): string {
  return value
    .replace(/^\s*[\u4e00-\u9fff0-9]+[\u3001.\uff0e]\s*/u, "")
    .replace(/\s+#+\s*$/u, "")
    .trim();
}

function updateCurrentFilesSection(
  source: string,
  fileNames: string[],
): string {
  const eol = lineEnding(source);
  const lines = [...source.matchAll(/.*(?:\r\n|\n|\r|$)/gu)].filter(
    (match) => match[0].length > 0,
  );
  let activeFence: string | undefined;
  let currentContentStart: number | undefined;
  let nextHeadingStart: number | undefined;
  for (const lineMatch of lines) {
    const lineWithEnding = lineMatch[0];
    const line = lineWithEnding.replace(/\r\n|\n|\r$/u, "");
    const start = lineMatch.index;
    if (activeFence) {
      const marker = activeFence[0] === "`" ? "`" : "~";
      if (
        new RegExp(
          `^[ ]{0,3}${marker}{${String(activeFence.length)},}[ \\t]*$`,
          "u",
        ).test(line)
      ) {
        activeFence = undefined;
      }
      continue;
    }
    const fenceMatch = /^[ ]{0,3}(?<fence>`{3,}|~{3,})/u.exec(line);
    if (fenceMatch?.groups?.fence) {
      activeFence = fenceMatch.groups.fence;
      continue;
    }
    const heading = /^##[ \t]+(?<title>.+?)[ \t]*$/u.exec(line)?.groups?.title;
    if (!heading) {
      continue;
    }
    if (currentContentStart !== undefined) {
      nextHeadingStart = start;
      break;
    }
    if (normalizedIndexHeading(heading) === "\u5f53\u524d\u6587\u4ef6") {
      currentContentStart = start + lineWithEnding.length;
    }
  }
  if (currentContentStart === undefined || nextHeadingStart === undefined) {
    throw new Error(
      "Existing prompt index has no bounded current-file section to update.",
    );
  }
  const entries = fileNames.map((fileName) => `- \`${fileName}\``).join(eol);
  return `${source.slice(0, currentContentStart)}${eol}${entries}${eol}${eol}${source.slice(nextHeadingStart)}`;
}

function assertModelFragment(value: string, label: string): string {
  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    /^#{1,6}[ \t]+/mu.test(normalized) ||
    /^[ ]{0,3}(?:`{3,}|~{3,})/mu.test(normalized) ||
    normalized.includes("\0")
  ) {
    throw new Error(
      `Import model fragment contains structural markup: ${label}`,
    );
  }
  return normalized;
}

function professionAgents(profession: string, design: ImportDesign): string {
  const rules = design.professionRules;
  return [
    `# ${profession} \u804c\u4e1a\u89c4\u5219`,
    "",
    "## \u804c\u8d23\u4e0e\u804c\u4e1a\u8fb9\u754c",
    "",
    assertModelFragment(
      rules.responsibilitiesAndBoundaries,
      "profession responsibilities",
    ),
    "",
    "## \u8d44\u6e90\u4e8b\u5b9e\u6e90",
    "",
    assertModelFragment(rules.resourceFactAuthority, "resource authority"),
    "",
    "## Prompt \u5206\u5c42",
    "",
    assertModelFragment(rules.promptLayering, "prompt layering"),
    "",
    "## \u4eba\u7269\u3001\u7279\u6548\u3001\u6b66\u5668\u4e0e Cut-in \u8fb9\u754c",
    "",
    assertModelFragment(
      rules.characterEffectWeaponCutinBoundary,
      "layer boundaries",
    ),
    "",
    "## \u804c\u4e1a\u9a8c\u6536\u4e0e\u56de\u5f52",
    "",
    assertModelFragment(rules.acceptanceAndRegression, "profession acceptance"),
    "",
    "## \u8986\u76d6\u72b6\u6001",
    "",
    assertModelFragment(rules.coverageStatus, "coverage status"),
    "",
  ].join("\n");
}

function themeAgents(theme: string, design: ImportDesign): string {
  const rules = design.themeRules;
  if (!rules) {
    throw new Error("Theme rules are required for theme targets.");
  }
  return [
    `# ${theme} \u4e3b\u9898\u89c4\u5219`,
    "",
    "## \u4e3b\u9898\u76ee\u6807",
    "",
    assertModelFragment(rules.objective, "theme objective"),
    "",
    "## \u8272\u677f\u3001\u6750\u8d28\u4e0e\u98ce\u683c",
    "",
    assertModelFragment(
      rules.paletteMaterialsAndStyle,
      "theme palette and materials",
    ),
    "",
    "## Prompt \u8def\u7531",
    "",
    assertModelFragment(rules.promptRouting, "theme prompt routing"),
    "",
    "## \u4fee\u6539\u8303\u56f4\u4e0e\u8fb9\u754c",
    "",
    assertModelFragment(
      rules.modificationScopeAndBoundaries,
      "theme modification boundaries",
    ),
    "",
    "## \u4e3b\u9898\u9a8c\u6536\u4e0e\u56de\u5f52",
    "",
    assertModelFragment(rules.acceptanceAndRegression, "theme acceptance"),
    "",
  ].join("\n");
}

function promptIndex(
  title: string,
  fileNames: string[],
  themed: boolean,
): string {
  const scope = themed
    ? "\u4e3b\u9898\u589e\u91cf"
    : "\u804c\u4e1a\u7a33\u5b9a\u8bed\u4e49";
  const sequence = themed
    ? "\u5148\u52a0\u8f7d\u804c\u4e1a\u6839\u76ee\u5f55\u540c\u540d Prompt\uff0c\u518d\u52a0\u8f7d\u4e3b\u9898 AGENTS \u5171\u540c\u89c4\u5219\u548c\u672c\u76ee\u5f55\u540c\u540d\u589e\u91cf\u3002"
    : "\u5148\u6838\u9a8c manifest/inventory \u663e\u793a\u540d\u6620\u5c04\uff0c\u518d\u6309\u672c\u7d22\u5f15\u52a0\u8f7d\u804c\u4e1a Prompt\u3002";
  return [
    `# ${title}`,
    "",
    "## \u804c\u8d23",
    "",
    `\u672c\u7d22\u5f15\u53ea\u7ba1\u7406${scope} Prompt\uff0c\u4e0d\u5efa\u7acb\u6280\u672f\u8d44\u6e90\u6620\u5c04\u3002`,
    "",
    "## \u52a0\u8f7d\u987a\u5e8f",
    "",
    sequence,
    "",
    "## \u7a33\u5b9a\u7ed3\u6784",
    "",
    themed
      ? "\u6bcf\u4e2a\u6587\u4ef6\u56fa\u5b9a\u4f7f\u7528\u804c\u4e1a\u57fa\u7840\u3001\u4e3b\u9898\u589e\u91cf Prompt\u3001\u5177\u4f53\u53d8\u5316\u3001\u4e3b\u9898\u9a8c\u6536\u548c\u4e3b\u9898\u6392\u9664\u4e94\u8282\u3002"
      : "\u6bcf\u4e2a\u6587\u4ef6\u56fa\u5b9a\u4f7f\u7528\u804c\u4e1a\u7a33\u5b9a\u8bed\u4e49\u3001\u804c\u4e1a\u901a\u7528 Prompt\u3001\u6e90\u8d44\u6e90\u7ea6\u675f\u548c\u9636\u6bb5\u9a8c\u6536\u56db\u8282\u3002",
    "",
    "## \u5f53\u524d\u6587\u4ef6",
    "",
    ...fileNames.map((fileName) => `- \`${fileName}\``),
    "",
    "## \u8986\u76d6\u72b6\u6001",
    "",
    "Prompt \u6587\u4ef6\u6570\u91cf\u548c\u6587\u4ef6\u540d\u4e0d\u80fd\u8bc1\u660e\u5168\u6280\u80fd\u8986\u76d6\uff1b\u8986\u76d6\u72b6\u6001\u4ecd\u5f85 manifest \u4e0e\u5b9e\u9645 inventory \u8bc1\u636e\u6838\u9a8c\u3002",
    "",
  ].join("\n");
}

function professionPrompt(
  displayName: string,
  prompt: ImportDesign["prompts"][number],
): string {
  return [
    `# ${displayName}`,
    "",
    "## \u804c\u4e1a\u7a33\u5b9a\u8bed\u4e49",
    "",
    assertModelFragment(
      prompt.professionStableSemantics,
      `${displayName} profession semantics`,
    ),
    "",
    "## \u804c\u4e1a\u901a\u7528 Prompt",
    "",
    "```text",
    assertModelFragment(
      prompt.professionEnglishPrompt,
      `${displayName} profession prompt`,
    ),
    "```",
    "",
    "## \u6e90\u8d44\u6e90\u7ea6\u675f",
    "",
    assertModelFragment(
      prompt.sourceConstraints,
      `${displayName} source constraints`,
    ),
    "",
    "## \u9636\u6bb5\u9a8c\u6536",
    "",
    assertModelFragment(
      prompt.phaseAcceptance,
      `${displayName} phase acceptance`,
    ),
    "",
  ].join("\n");
}

function themePrompt(
  displayName: string,
  theme: string,
  fileName: string,
  prompt: ImportDesign["prompts"][number],
): string {
  if (!prompt.theme) {
    throw new Error(`Theme semantics are missing for ${displayName}.`);
  }
  return [
    `# ${displayName} - ${theme}`,
    "",
    "## \u804c\u4e1a\u57fa\u7840",
    "",
    `\u5f15\u7528 ../../prompts/${fileName}\uff0c\u4ee5\u5176\u52a8\u4f5c\u3001\u8f6e\u5ed3\u3001\u9636\u6bb5\u3001\u951a\u70b9\u4e0e\u6e90\u8d44\u6e90\u8fb9\u754c\u4e3a\u57fa\u7840\u3002`,
    "",
    "## \u4e3b\u9898\u589e\u91cf Prompt",
    "",
    "```text",
    assertModelFragment(
      prompt.theme.englishIncrement,
      `${displayName} theme prompt`,
    ),
    "```",
    "",
    "## \u5177\u4f53\u53d8\u5316",
    "",
    assertModelFragment(prompt.theme.changes, `${displayName} theme changes`),
    "",
    "## \u4e3b\u9898\u9a8c\u6536",
    "",
    assertModelFragment(
      prompt.theme.acceptance,
      `${displayName} theme acceptance`,
    ),
    "",
    "## \u4e3b\u9898\u6392\u9664",
    "",
    assertModelFragment(
      prompt.theme.exclusions,
      `${displayName} theme exclusions`,
    ),
    "",
  ].join("\n");
}

export function buildImportTargetContent(
  target: ImportPlan["targets"][number],
  plan: ImportPlan,
  design: ImportDesign,
): string {
  const professionFileNames = plan.prompts.map((prompt) => prompt.fileName);
  const themeFileNames = plan.themePrompts.map((prompt) => prompt.fileName);
  if (target.kind === "profession-agents") {
    return professionAgents(plan.route.profession, design);
  }
  if (target.kind === "profession-index") {
    return promptIndex(
      `${plan.route.profession} \u804c\u4e1a Prompt \u7d22\u5f15`,
      professionFileNames,
      false,
    );
  }
  if (target.kind === "theme-agents") {
    if (!plan.route.theme) {
      throw new Error("Theme route is missing for theme AGENTS target.");
    }
    return themeAgents(plan.route.theme, design);
  }
  if (target.kind === "theme-index") {
    if (!plan.route.theme) {
      throw new Error("Theme route is missing for theme index target.");
    }
    return promptIndex(
      `${plan.route.theme} Prompt \u7d22\u5f15`,
      themeFileNames,
      true,
    );
  }
  const fileName = basename(target.relativePath);
  const promptIndexValue = plan.prompts.findIndex(
    (prompt) => canonicalName(prompt.fileName) === canonicalName(fileName),
  );
  if (promptIndexValue < 0) {
    throw new Error(
      `Prompt target is not present in the fixed plan: ${fileName}`,
    );
  }
  const promptPlan = plan.prompts[promptIndexValue];
  const prompt = design.prompts[promptIndexValue];
  if (promptPlan === undefined || prompt === undefined) {
    throw new Error(`Prompt target has no fixed semantic design: ${fileName}`);
  }
  if (target.kind === "profession-prompt") {
    return professionPrompt(promptPlan.displayName, prompt);
  }
  if (!plan.route.theme) {
    throw new Error("Theme route is missing for theme prompt target.");
  }
  if (
    !plan.themePrompts.some(
      (themePlan) =>
        canonicalName(themePlan.fileName) === canonicalName(fileName),
    )
  ) {
    throw new Error(
      `Theme Prompt target is not in the theme plan: ${fileName}`,
    );
  }
  return themePrompt(
    promptPlan.displayName,
    plan.route.theme,
    promptPlan.fileName,
    prompt,
  );
}

async function removeEmptyParents(
  startPath: string,
  stopAt: string,
): Promise<void> {
  let current = startPath;
  while (current !== stopAt && current.startsWith(`${stopAt}\\`)) {
    try {
      await rmdir(current);
    } catch {
      return;
    }
    current = dirname(current);
  }
}

export class ImportTransactionWriter {
  constructor(
    readonly repositoryRoot: string,
    readonly store: RunStore,
    readonly broker: ImportToolInvoker,
  ) {}

  async #assertAuthoritySnapshots(
    snapshots: readonly FileSnapshot[],
    ignoredPaths: ReadonlySet<string> = new Set(),
  ): Promise<void> {
    const ignored = new Set(
      [...ignoredPaths].map((path) =>
        canonicalName(path.replaceAll("\\", "/")),
      ),
    );
    const seen = new Set<string>();
    for (const expected of snapshots) {
      const key = canonicalName(expected.path.replaceAll("\\", "/"));
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
        canonicalName(snapshot.path.replaceAll("\\", "/")),
        snapshot,
      ]),
    );
    const hostScript = authorityByPath.get(canonicalName(CATALOG_HOST_PATH));
    const gateScript = authorityByPath.get(
      canonicalName(PROMPT_TREE_GATE_PATH),
    );
    if (!hostScript || !gateScript) {
      throw new Error(
        "Import transaction is missing frozen host or Prompt tree gate authority.",
      );
    }
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
