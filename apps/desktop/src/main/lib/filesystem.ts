import { createHash } from "node:crypto";
import { constants } from "node:fs";
import {
  access,
  lstat,
  link,
  mkdir,
  readFile,
  realpath,
  rename,
  rm,
  stat,
  unlink,
  writeFile,
} from "node:fs/promises";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import type { FileSnapshot } from "../../shared/contracts.js";

export function normalizeRelativePath(value: string): string {
  const normalized = value.replaceAll("\\", "/").replace(/^\.\//u, "");
  if (
    normalized.length === 0 ||
    normalized.startsWith("/") ||
    /^[A-Za-z]:/u.test(normalized) ||
    normalized.split("/").includes("..")
  ) {
    throw new Error(`Unsafe repository-relative path: ${value}`);
  }
  return normalized;
}

export function toRepositoryRelative(
  repositoryRoot: string,
  absolutePath: string,
): string {
  const result = relative(repositoryRoot, absolutePath).split(sep).join("/");
  return normalizeRelativePath(result);
}

export function resolveInside(repositoryRoot: string, value: string): string {
  const candidate = isAbsolute(value)
    ? resolve(value)
    : resolve(repositoryRoot, normalizeRelativePath(value));
  const route = relative(repositoryRoot, candidate);
  if (route === ".." || route.startsWith(`..${sep}`) || isAbsolute(route)) {
    throw new Error(`Path must stay inside the repository: ${candidate}`);
  }
  return candidate;
}

export async function assertNoSymlinkChain(
  repositoryRoot: string,
  targetPath: string,
): Promise<void> {
  const root = resolve(repositoryRoot);
  let current = resolve(targetPath);
  const route = relative(root, current);
  if (route === ".." || route.startsWith(`..${sep}`) || isAbsolute(route)) {
    throw new Error(`Path must stay inside the repository: ${current}`);
  }

  for (;;) {
    try {
      const item = await lstat(current);
      if (item.isSymbolicLink()) {
        throw new Error(
          `Path cannot traverse a symbolic link or junction: ${current}`,
        );
      }
    } catch (error) {
      if (!isMissingFileError(error)) {
        throw error;
      }
    }
    if (current.toLocaleLowerCase() === root.toLocaleLowerCase()) {
      break;
    }
    const parent = dirname(current);
    if (parent === current) {
      throw new Error(
        `Could not resolve repository ancestry for: ${targetPath}`,
      );
    }
    current = parent;
  }

  const realRoot = await realpath(root);
  let existing = resolve(targetPath);
  for (;;) {
    try {
      const realExisting = await realpath(existing);
      const realRoute = relative(realRoot, realExisting);
      if (
        realRoute === ".." ||
        realRoute.startsWith(`..${sep}`) ||
        isAbsolute(realRoute)
      ) {
        throw new Error(`Resolved path escapes the repository: ${targetPath}`);
      }
      break;
    } catch (error) {
      if (!isMissingFileError(error)) {
        throw error;
      }
      const parent = dirname(existing);
      if (parent === existing) {
        throw error;
      }
      existing = parent;
    }
  }
}

export function sha256Buffer(value: Uint8Array): string {
  return createHash("sha256").update(value).digest("hex").toUpperCase();
}

export function sha256Text(value: string): string {
  return sha256Buffer(Buffer.from(value, "utf8"));
}

export function snapshotMetadata(snapshot: FileSnapshot): FileSnapshot {
  return {
    label: snapshot.label,
    path: snapshot.path,
    length: snapshot.length,
    sha256: snapshot.sha256,
  };
}

export function stableStringify(value: unknown): string {
  return JSON.stringify(sortJson(value));
}

function sortJson(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(sortJson);
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, child]) => [key, sortJson(child)]),
    );
  }
  return value;
}

export async function snapshotFile(
  repositoryRoot: string,
  relativePath: string,
  label: string,
  includeContent = true,
): Promise<FileSnapshot> {
  const normalized = normalizeRelativePath(relativePath);
  const absolutePath = resolveInside(repositoryRoot, normalized);
  await assertNoSymlinkChain(repositoryRoot, absolutePath);
  const bytes = await readFile(absolutePath);
  const item = await stat(absolutePath);
  if (!item.isFile()) {
    throw new Error(`Snapshot target is not a file: ${normalized}`);
  }
  return {
    label,
    path: normalized,
    length: item.size,
    sha256: sha256Buffer(bytes),
    ...(includeContent
      ? { content: bytes.toString("utf8").replace(/^\uFEFF/u, "") }
      : {}),
  };
}

export async function fileExists(path: string): Promise<boolean> {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

export async function writeFileCreateNew(
  path: string,
  data: string | Uint8Array,
): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.staging-${crypto.randomUUID()}`;
  try {
    await writeFile(temporary, data, { flag: "wx" });
    await link(temporary, path);
  } finally {
    await rm(temporary, { force: true });
  }
}

export async function writeFileAtomic(
  path: string,
  data: string | Uint8Array,
): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.staging-${crypto.randomUUID()}`;
  try {
    await writeFile(temporary, data, { flag: "wx" });
    await rename(temporary, path);
  } finally {
    await rm(temporary, { force: true });
  }
}

export async function writeJsonCreateNew(
  path: string,
  value: unknown,
): Promise<void> {
  const text = `${JSON.stringify(value, null, 2)}\n`;
  JSON.parse(text) as unknown;
  await writeFileCreateNew(path, text);
}

export async function writeJsonAtomic(
  path: string,
  value: unknown,
): Promise<void> {
  const text = `${JSON.stringify(value, null, 2)}\n`;
  JSON.parse(text) as unknown;
  await writeFileAtomic(path, text);
}

export async function removeFilesAndEmptyParents(
  paths: string[],
  stopAt: string,
): Promise<void> {
  for (const path of [...paths].reverse()) {
    await rm(path, { force: true, recursive: true });
    let parent = dirname(path);
    while (
      relative(stopAt, parent) !== "" &&
      !relative(stopAt, parent).startsWith(`..${sep}`)
    ) {
      try {
        await unlink(parent);
      } catch {
        try {
          await rm(parent, { recursive: false });
        } catch {
          break;
        }
      }
      parent = dirname(parent);
    }
  }
}

export function isMissingFileError(
  error: unknown,
): error is NodeJS.ErrnoException {
  return (
    error instanceof Error &&
    "code" in error &&
    (error as NodeJS.ErrnoException).code === "ENOENT"
  );
}
