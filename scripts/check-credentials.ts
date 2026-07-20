import { lstat, readFile, readdir } from "node:fs/promises";
import { extname, relative, resolve, sep } from "node:path";
import { findRepositoryRoot } from "../server/repository.js";
import {
  scanCredentialText,
  type CredentialFinding,
} from "../server/security/credential-scanner.js";

type ScanMode = "build" | "source";

const maxTextFileBytes = 5 * 1024 * 1024;
const textExtensions = new Set([
  ".cjs",
  ".css",
  ".html",
  ".js",
  ".json",
  ".jsx",
  ".lua",
  ".md",
  ".mjs",
  ".ps1",
  ".psm1",
  ".toml",
  ".ts",
  ".tsx",
  ".txt",
  ".yaml",
  ".yml",
]);
const textFileNames = new Set([".gitignore"]);
const sourceIgnoredDirectories = new Set([
  ".git",
  "automation-runs",
  "bin",
  "build",
  "coverage",
  "dist",
  "frames",
  "legacy-runs",
  "node_modules",
  "npk",
  "out",
  "playwright-report",
  "runs",
  "test-results",
  "validation",
]);

interface ScanSummary {
  schemaVersion: 1;
  status: "passed";
  mode: ScanMode;
  scannedFileCount: number;
  findingCount: 0;
  matchedValuesReported: false;
}

/** 只扫描明确的文本类型，避免把 NPK、图片和工具二进制解码为字符串。 */
function isTextFile(path: string): boolean {
  const name = path.split(/[\\/]/u).at(-1)?.toLocaleLowerCase() ?? "";
  return textFileNames.has(name) || textExtensions.has(extname(name));
}

/** 递归收集文件；符号链接或超大文本均阻断，防止绕过扫描边界。 */
async function collectTextFiles(
  root: string,
  ignoredDirectories: ReadonlySet<string>,
): Promise<string[]> {
  const files: string[] = [];
  const visit = async (directory: string): Promise<void> => {
    const entries = await readdir(directory, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isSymbolicLink()) {
        throw new Error(
          `Credential scan refuses symbolic links: ${entry.name}`,
        );
      }
      const path = resolve(directory, entry.name);
      if (entry.isDirectory()) {
        if (!ignoredDirectories.has(entry.name.toLocaleLowerCase())) {
          await visit(path);
        }
        continue;
      }
      if (!entry.isFile() || !isTextFile(path)) {
        continue;
      }
      const item = await lstat(path);
      if (item.size > maxTextFileBytes) {
        throw new Error(`Text file exceeds credential scan limit: ${path}`);
      }
      files.push(path);
    }
  };
  await visit(root);
  return files.sort((left, right) => left.localeCompare(right));
}

async function scanFiles(
  repositoryRoot: string,
  paths: readonly string[],
): Promise<CredentialFinding[]> {
  const findings: CredentialFinding[] = [];
  for (const path of paths) {
    const repositoryPath = relative(repositoryRoot, path).split(sep).join("/");
    findings.push(
      ...scanCredentialText(repositoryPath, await readFile(path, "utf8")),
    );
  }
  return findings;
}

function parseMode(value: string | undefined): ScanMode {
  if (value === "source" || value === "build") {
    return value;
  }
  throw new Error("Credential scan mode must be source or build.");
}

async function main(): Promise<void> {
  const mode = parseMode(process.argv[2]);
  const repositoryRoot = await findRepositoryRoot([process.cwd()]);
  const scanRoot =
    mode === "source" ? repositoryRoot : resolve(repositoryRoot, "out");
  const ignored =
    mode === "source" ? sourceIgnoredDirectories : new Set<string>();
  const paths = await collectTextFiles(scanRoot, ignored);
  const findings = await scanFiles(repositoryRoot, paths);
  if (findings.length > 0) {
    for (const finding of findings) {
      process.stderr.write(
        `Credential risk ${finding.ruleId} at ${finding.relativePath}:${String(finding.line)}; matched value withheld.\n`,
      );
    }
    throw new Error(
      `Credential scan found ${String(findings.length)} risk(s).`,
    );
  }
  const summary: ScanSummary = {
    schemaVersion: 1,
    status: "passed",
    mode,
    scannedFileCount: paths.length,
    findingCount: 0,
    matchedValuesReported: false,
  };
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`Credential scan failed: ${message}\n`);
  process.exitCode = 1;
});
