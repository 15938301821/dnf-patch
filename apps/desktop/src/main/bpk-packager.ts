import { ZipArchive } from "archiver";
import { createHash } from "node:crypto";
import { createWriteStream } from "node:fs";
import { mkdir, readFile, readdir, rename, rm, stat } from "node:fs/promises";
import { basename, dirname, extname, resolve } from "node:path";
import yauzl from "yauzl";
import {
  bpkManifestSchema,
  type BpkManifest,
  type RunRequest,
} from "../shared/contracts.js";
import type { ExecutionProfile } from "../shared/profile.js";
import {
  assertNoSymlinkChain,
  fileExists,
  normalizeRelativePath,
  resolveInside,
  snapshotFile,
  writeJsonCreateNew,
} from "./lib/filesystem.js";
import type { RunStore } from "./run-store.js";

const BPK_MANIFEST_ARCHIVE_PATH = "manifest/bpk-manifest.json";

interface EntrySource {
  sourcePath: string;
  archivePath: string;
  role: BpkManifest["entries"][number]["role"];
}

export interface PackageBpkOptions {
  request: RunRequest;
  profile: ExecutionProfile;
  expandedNpkPath: string;
  validationSummaryPath: string;
  buildSummaryPath: string;
  evidencePaths: string[];
}

export interface BpkVerification {
  schemaVersion: 1;
  status: "passed";
  path: string;
  length: number;
  sha256: string;
  entryCount: number;
  manifestSha256: string;
  nativeNpkCount: number;
  deploymentAuthorized: false;
  deploymentPerformed: false;
}

function safeArchivePath(value: string): string {
  const normalized = normalizeRelativePath(value);
  if (normalized.endsWith("/") || normalized.includes(":")) {
    throw new Error(`Unsafe BPK archive path: ${value}`);
  }
  return normalized;
}

function outputFileName(request: RunRequest): string {
  const base = request.outputBaseName.startsWith("a_")
    ? request.outputBaseName
    : `a_${request.outputBaseName}`;
  return `${base}_v${request.outputVersion}.bpk`;
}

async function listFiles(path: string): Promise<string[]> {
  const item = await stat(path);
  if (item.isFile()) {
    return [path];
  }
  if (!item.isDirectory()) {
    throw new Error(`BPK evidence path has an unsupported type: ${path}`);
  }
  const files: string[] = [];
  for (const entry of await readdir(path, { withFileTypes: true })) {
    const child = resolve(path, entry.name);
    if (entry.isSymbolicLink()) {
      throw new Error(`BPK evidence cannot contain a symbolic link: ${child}`);
    }
    if (entry.isDirectory()) {
      files.push(...(await listFiles(child)));
    } else if (entry.isFile()) {
      files.push(child);
    }
  }
  return files;
}

function runArchivePath(runRootRelative: string, sourcePath: string): string {
  const normalized = normalizeRelativePath(sourcePath);
  const prefix = `${normalizeRelativePath(runRootRelative)}/`;
  if (!normalized.startsWith(prefix)) {
    throw new Error(`Run evidence is outside the current Run: ${sourcePath}`);
  }
  return safeArchivePath(`run/${normalized.slice(prefix.length)}`);
}

async function createArchive(
  outputPath: string,
  entries: EntrySource[],
  manifestPath: string,
): Promise<void> {
  await mkdir(dirname(outputPath), { recursive: true });
  const temporaryPath = `${outputPath}.staging-${crypto.randomUUID()}`;
  try {
    await new Promise<void>((resolveArchive, reject) => {
      const output = createWriteStream(temporaryPath, { flags: "wx" });
      const archive = new ZipArchive({ zlib: { level: 9 } });
      output.once("close", resolveArchive);
      output.once("error", reject);
      archive.once("error", reject);
      archive.pipe(output);
      for (const entry of entries) {
        archive.file(entry.sourcePath, {
          name: entry.archivePath,
          date: new Date(0),
        });
      }
      archive.file(manifestPath, {
        name: BPK_MANIFEST_ARCHIVE_PATH,
        date: new Date(0),
      });
      void archive.finalize();
    });
    await rename(temporaryPath, outputPath);
  } finally {
    await rm(temporaryPath, { force: true });
  }
}

function openZip(path: string): Promise<yauzl.ZipFile> {
  return new Promise((resolveZip, reject) => {
    yauzl.open(
      path,
      { lazyEntries: true, autoClose: true, validateEntrySizes: true },
      (error, zipFile) => {
        if (error) {
          reject(error);
          return;
        }
        resolveZip(zipFile);
      },
    );
  });
}

function openEntryStream(
  zipFile: yauzl.ZipFile,
  entry: yauzl.Entry,
): Promise<NodeJS.ReadableStream> {
  return new Promise((resolveStream, reject) => {
    zipFile.openReadStream(entry, (error, stream) => {
      if (error) {
        reject(error);
        return;
      }
      resolveStream(stream);
    });
  });
}

async function hashEntry(
  zipFile: yauzl.ZipFile,
  entry: yauzl.Entry,
): Promise<{ length: number; sha256: string; bytes?: Buffer }> {
  const stream = await openEntryStream(zipFile, entry);
  const hash = createHash("sha256");
  const capture = entry.fileName === BPK_MANIFEST_ARCHIVE_PATH;
  const chunks: Buffer[] = [];
  let length = 0;
  return new Promise((resolveHash, reject) => {
    stream.on("data", (chunk: Buffer | string) => {
      const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      length += bytes.length;
      hash.update(bytes);
      if (capture) {
        chunks.push(bytes);
      }
    });
    stream.once("error", (error: unknown) => {
      reject(
        error instanceof Error
          ? error
          : new Error("Could not hash BPK entry stream."),
      );
    });
    stream.once("end", () => {
      resolveHash({
        length,
        sha256: hash.digest("hex").toUpperCase(),
        ...(capture ? { bytes: Buffer.concat(chunks) } : {}),
      });
    });
  });
}

export async function verifyBpk(
  repositoryRoot: string,
  bpkRelativePath: string,
): Promise<BpkVerification> {
  const bpkPath = resolveInside(repositoryRoot, bpkRelativePath);
  await assertNoSymlinkChain(repositoryRoot, bpkPath);
  const zipFile = await openZip(bpkPath);
  const observed = new Map<
    string,
    { length: number; sha256: string; bytes?: Buffer }
  >();
  const foldedNames = new Set<string>();
  for await (const entry of zipFile.eachEntry()) {
    const name = safeArchivePath(entry.fileName);
    if (
      entry.fileName.endsWith("/") ||
      (entry.generalPurposeBitFlag & 0x1) !== 0
    ) {
      throw new Error(`BPK contains a directory or encrypted entry: ${name}`);
    }
    const folded = name.toLocaleLowerCase();
    if (foldedNames.has(folded)) {
      throw new Error(`BPK contains a duplicate entry: ${name}`);
    }
    foldedNames.add(folded);
    const hashed = await hashEntry(zipFile, entry);
    if (hashed.length !== entry.uncompressedSize) {
      throw new Error(`BPK entry length mismatch: ${name}`);
    }
    observed.set(name, hashed);
  }

  const manifestEntry = observed.get(BPK_MANIFEST_ARCHIVE_PATH);
  if (!manifestEntry?.bytes) {
    throw new Error("BPK manifest is missing.");
  }
  const manifest = bpkManifestSchema.parse(
    JSON.parse(manifestEntry.bytes.toString("utf8").replace(/^\uFEFF/u, "")),
  );
  const expectedNames = new Set([
    BPK_MANIFEST_ARCHIVE_PATH,
    ...manifest.entries.map((entry) => entry.archivePath),
  ]);
  if (observed.size !== expectedNames.size) {
    throw new Error(
      `BPK entry count mismatch: ${String(observed.size)}/${String(expectedNames.size)}`,
    );
  }
  for (const entry of manifest.entries) {
    const actual = observed.get(entry.archivePath);
    if (!actual) {
      throw new Error(`BPK manifest entry is missing: ${entry.archivePath}`);
    }
    if (actual.length !== entry.length || actual.sha256 !== entry.sha256) {
      throw new Error(`BPK manifest hash mismatch: ${entry.archivePath}`);
    }
  }
  for (const name of observed.keys()) {
    if (!expectedNames.has(name)) {
      throw new Error(`BPK contains an undeclared entry: ${name}`);
    }
  }
  if (!manifest.offlineValidationPassed) {
    throw new Error("BPK does not carry a passed offline validation state.");
  }
  const nativeNpkCount = manifest.entries.filter(
    (entry) =>
      entry.role === "npk" &&
      extname(entry.archivePath).toLowerCase() === ".npk",
  ).length;
  if (nativeNpkCount !== 1) {
    throw new Error(
      `BPK must contain exactly one native NPK: ${String(nativeNpkCount)}`,
    );
  }
  const snapshot = await snapshotFile(
    repositoryRoot,
    normalizeRelativePath(bpkRelativePath),
    "Verified BPK",
    false,
  );
  return {
    schemaVersion: 1,
    status: "passed",
    path: snapshot.path,
    length: snapshot.length,
    sha256: snapshot.sha256,
    entryCount: observed.size,
    manifestSha256: manifestEntry.sha256,
    nativeNpkCount,
    deploymentAuthorized: false,
    deploymentPerformed: false,
  };
}

export class BpkPackager {
  constructor(
    readonly repositoryRoot: string,
    readonly store: RunStore,
  ) {}

  async package(options: PackageBpkOptions): Promise<{
    bpkPath: string;
    manifestPath: string;
    verificationPath: string;
    verification: BpkVerification;
  }> {
    const { request, profile } = options;
    const theme = request.theme;
    if (theme === undefined) {
      throw new Error("BPK packaging requires a fixed theme route.");
    }
    const npkPath = normalizeRelativePath(options.expandedNpkPath);
    const validationSummaryPath = normalizeRelativePath(
      options.validationSummaryPath,
    );
    const buildSummaryPath = normalizeRelativePath(options.buildSummaryPath);
    const professionManifestPath = `${request.profession}/manifest.json`;
    for (const requiredPath of [
      npkPath,
      validationSummaryPath,
      buildSummaryPath,
      professionManifestPath,
    ]) {
      const absolutePath = resolveInside(this.repositoryRoot, requiredPath);
      if (!(await fileExists(absolutePath))) {
        throw new Error(`Required BPK input is missing: ${requiredPath}`);
      }
      await assertNoSymlinkChain(this.repositoryRoot, absolutePath);
    }
    const validation = JSON.parse(
      await readFile(
        resolveInside(this.repositoryRoot, validationSummaryPath),
        "utf8",
      ),
    ) as { status?: unknown };
    if (validation.status !== "passed") {
      throw new Error("BPK requires a passed independent validation summary.");
    }

    const sources = new Map<string, EntrySource>();
    const addSource = (
      sourcePath: string,
      archivePath: string,
      role: EntrySource["role"],
    ): void => {
      const normalizedSource = normalizeRelativePath(sourcePath);
      const normalizedArchive = safeArchivePath(archivePath);
      const key = normalizedArchive.toLocaleLowerCase();
      const existing = sources.get(key);
      if (existing !== undefined) {
        if (existing.sourcePath !== normalizedSource) {
          throw new Error(`BPK archive path collision: ${normalizedArchive}`);
        }
        return;
      }
      sources.set(key, {
        sourcePath: normalizedSource,
        archivePath: normalizedArchive,
        role,
      });
    };

    addSource(npkPath, `payload/${basename(npkPath)}`, "npk");
    addSource(
      professionManifestPath,
      "manifest/profession-manifest.json",
      "manifest",
    );
    addSource(
      validationSummaryPath,
      "validation/build-validation-summary.json",
      "final-summary",
    );
    addSource(
      buildSummaryPath,
      "validation/build-summary.json",
      "validation-evidence",
    );

    const runRootRelative = this.store.toRelative(
      this.store.runDirectory(request.runId),
    );
    const evidence = new Set(options.evidencePaths.map(normalizeRelativePath));
    evidence.add(`${runRootRelative}/request.json`);
    evidence.add(`${runRootRelative}/context/context-bundle.json`);
    evidence.add(`${runRootRelative}/plans/engineering-plan.json`);
    evidence.add(`${runRootRelative}/models/aseprite-style-plan.json`);
    for (const evidencePath of evidence) {
      const absolutePath = resolveInside(this.repositoryRoot, evidencePath);
      if (!(await fileExists(absolutePath))) {
        throw new Error(`Declared BPK evidence is missing: ${evidencePath}`);
      }
      for (const file of await listFiles(absolutePath)) {
        const relativePath = this.store.toRelative(file);
        const archivePath = relativePath.startsWith(`${runRootRelative}/`)
          ? runArchivePath(runRootRelative, relativePath)
          : `evidence/${relativePath}`;
        addSource(relativePath, archivePath, "run-evidence");
      }
    }

    const entrySources = [...sources.values()].sort((left, right) =>
      left.archivePath.localeCompare(right.archivePath),
    );
    const entries: BpkManifest["entries"] = [];
    for (const source of entrySources) {
      const snapshot = await snapshotFile(
        this.repositoryRoot,
        source.sourcePath,
        `BPK source ${source.archivePath}`,
        false,
      );
      entries.push({
        archivePath: source.archivePath,
        sourcePath: snapshot.path,
        length: snapshot.length,
        sha256: snapshot.sha256,
        role: source.role,
      });
    }
    const packageId = `${profile.id}.v${request.outputVersion}`;
    const manifest = bpkManifestSchema.parse({
      schemaVersion: 1,
      format: "dnf-patch-bpk-v1",
      packageId,
      profession: request.profession,
      theme,
      version: request.outputVersion,
      createdAtUtc: new Date().toISOString(),
      entries,
      offlineValidationPassed: true,
      fullSkillCoverageProven: false,
      clientCompatibilityProven: false,
      deploymentAuthorized: false,
      deploymentPerformed: false,
      note: "BPK is an application delivery container, not a native DNF package. The native payload is the included NPK.",
    });
    const manifestPath = resolve(
      this.store.runDirectory(request.runId),
      "delivery",
      "bpk-manifest.json",
    );
    await writeJsonCreateNew(manifestPath, manifest);

    const bpkRelativePath = normalizeRelativePath(
      `build/${request.profession}/${theme}/${outputFileName(request)}`,
    );
    const bpkPath = resolveInside(this.repositoryRoot, bpkRelativePath);
    if (await fileExists(bpkPath)) {
      throw new Error(`Refusing to overwrite BPK: ${bpkRelativePath}`);
    }
    await createArchive(
      bpkPath,
      entrySources.map((source) => ({
        ...source,
        sourcePath: resolveInside(this.repositoryRoot, source.sourcePath),
      })),
      manifestPath,
    );
    const verification = await verifyBpk(this.repositoryRoot, bpkRelativePath);
    const verificationPath = await this.store.writeEvidence(
      request.runId,
      "delivery/bpk-verification.json",
      verification,
    );
    return {
      bpkPath: bpkRelativePath,
      manifestPath: this.store.toRelative(manifestPath),
      verificationPath,
      verification,
    };
  }
}
