import { mkdir, readFile, rm, rmdir, stat } from "node:fs/promises";
import { dirname, extname } from "node:path";
import type { RunRequest } from "../shared/contracts.js";
import type { ImportSource } from "./import-orchestrator/types.js";
import {
  assertNoSymlinkChain,
  fileExists,
  isPathInside,
  normalizeRelativePath,
  resolveInside,
  sha256Buffer,
  snapshotFile,
  writeFileCreateNew,
} from "./lib/filesystem.js";

const RESERVED_PROFESSION_ROUTES = new Set([
  ".codex",
  ".git",
  ".github",
  "apps",
  "build",
  "docs",
  "node_modules",
  "tools",
  "validation",
]);

export interface PreparedImportSource extends ImportSource {
  professionDirectoryCreated: boolean;
}

export async function prepareImportSource(
  repositoryRoot: string,
  request: RunRequest,
): Promise<PreparedImportSource> {
  if (RESERVED_PROFESSION_ROUTES.has(request.profession.toLocaleLowerCase())) {
    throw new Error(
      `Infrastructure directory cannot be used as a profession: ${request.profession}`,
    );
  }
  const professionPath = resolveInside(repositoryRoot, request.profession);
  await assertNoSymlinkChain(repositoryRoot, professionPath);
  const professionExists = await fileExists(professionPath);
  if (professionExists) {
    const item = await stat(professionPath);
    if (!item.isDirectory()) {
      throw new Error(
        `Profession route is not a directory: ${request.profession}`,
      );
    }
  } else if (!request.designText) {
    throw new Error(
      "A repository source path requires its profession directory to exist.",
    );
  }

  if (request.sourceDesignPath) {
    const relativePath = normalizeRelativePath(request.sourceDesignPath);
    const absolutePath = resolveInside(repositoryRoot, relativePath);
    if (
      !isPathInside(professionPath, absolutePath) ||
      absolutePath === professionPath
    ) {
      throw new Error(
        "The design source must be a file inside the selected profession directory.",
      );
    }
    const extension = extname(absolutePath).toLocaleLowerCase();
    if (extension !== ".md" && extension !== ".txt") {
      throw new Error("The design source must use a .md or .txt extension.");
    }
    await assertNoSymlinkChain(repositoryRoot, absolutePath);
    const item = await stat(absolutePath);
    if (!item.isFile()) {
      throw new Error(`Design source is not a file: ${relativePath}`);
    }
    return {
      relativePath,
      absolutePath,
      snapshot: await snapshotFile(
        repositoryRoot,
        relativePath,
        "Import design source",
      ),
      temporary: false,
      professionDirectoryCreated: false,
    };
  }

  if (!request.designText) {
    throw new Error("Import design text is missing.");
  }
  if (!professionExists) {
    await mkdir(professionPath);
  }
  const relativePath = `${request.profession}/.dnf-import-source-${request.runId}.md`;
  const absolutePath = resolveInside(repositoryRoot, relativePath);
  try {
    await assertNoSymlinkChain(repositoryRoot, absolutePath);
    await writeFileCreateNew(
      absolutePath,
      Buffer.from(request.designText, "utf8"),
    );
    return {
      relativePath,
      absolutePath,
      snapshot: await snapshotFile(
        repositoryRoot,
        relativePath,
        "Staged import design source",
      ),
      temporary: true,
      professionDirectoryCreated: !professionExists,
    };
  } catch (error) {
    if (!professionExists) {
      await rmdir(professionPath).catch(() => undefined);
    }
    throw error;
  }
}

export async function cleanupImportSource(
  repositoryRoot: string,
  source: PreparedImportSource,
): Promise<void> {
  if (!source.temporary) {
    return;
  }
  await assertNoSymlinkChain(repositoryRoot, source.absolutePath);
  if (await fileExists(source.absolutePath)) {
    const bytes = await readFile(source.absolutePath);
    if (sha256Buffer(bytes) !== source.snapshot.sha256) {
      throw new Error(
        `Temporary import source changed and was not removed: ${source.relativePath}`,
      );
    }
    await rm(source.absolutePath);
  }
  if (source.professionDirectoryCreated) {
    await rmdir(dirname(source.absolutePath)).catch(() => undefined);
  }
}
