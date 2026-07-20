import { EventEmitter } from "node:events";
import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  pipelineEventSchema,
  runSummarySchema,
  type PipelineEvent,
  type RunRequest,
  type RunSummary,
} from "./shared/contracts.js";
import {
  fileExists,
  normalizeRelativePath,
  resolveInside,
  toRepositoryRelative,
  writeFileCreateNew,
  writeJsonAtomic,
  writeJsonCreateNew,
} from "./lib/filesystem.js";

export class RunStore {
  readonly root: string;
  readonly #events = new EventEmitter();
  readonly #sequences = new Map<string, number>();

  constructor(readonly repositoryRoot: string) {
    this.root = resolve(repositoryRoot, "userData", "runs");
  }

  runDirectory(runId: string): string {
    return resolve(this.root, runId);
  }

  toRelative(path: string): string {
    return toRepositoryRelative(this.repositoryRoot, path);
  }

  async create(request: RunRequest): Promise<RunSummary> {
    const directory = this.runDirectory(request.runId);
    if (await fileExists(directory)) {
      throw new Error(`Run already exists: ${request.runId}`);
    }
    const summary: RunSummary = {
      schemaVersion: 1,
      runId: request.runId,
      status: "planning",
      action: request.action,
      provider: request.provider,
      startedAtUtc: new Date().toISOString(),
      currentStage: "bootstrap",
      deploymentAuthorized: false,
      deploymentPerformed: false,
    };
    await writeJsonCreateNew(resolve(directory, "request.json"), request);
    await writeJsonCreateNew(resolve(directory, "summary.json"), summary);
    this.#sequences.set(request.runId, 0);
    return summary;
  }

  async get(runId: string): Promise<RunSummary> {
    const path = resolve(this.runDirectory(runId), "summary.json");
    return runSummarySchema.parse(JSON.parse(await readFile(path, "utf8")));
  }

  async update(runId: string, patch: Partial<RunSummary>): Promise<RunSummary> {
    const current = await this.get(runId);
    const updated = runSummarySchema.parse({ ...current, ...patch });
    await writeJsonAtomic(
      resolve(this.runDirectory(runId), "summary.json"),
      updated,
    );
    return updated;
  }

  async writeEvidence(
    runId: string,
    relativePath: string,
    value: unknown,
  ): Promise<string> {
    const normalized = normalizeRelativePath(relativePath);
    const path = resolveInside(this.runDirectory(runId), normalized);
    await writeJsonCreateNew(path, value);
    return this.toRelative(path);
  }

  async writeTextEvidence(
    runId: string,
    relativePath: string,
    value: string,
  ): Promise<string> {
    const normalized = normalizeRelativePath(relativePath);
    const path = resolveInside(this.runDirectory(runId), normalized);
    await writeFileCreateNew(path, value);
    return this.toRelative(path);
  }

  async writeBinaryEvidence(
    runId: string,
    relativePath: string,
    value: Uint8Array,
  ): Promise<string> {
    const normalized = normalizeRelativePath(relativePath);
    const path = resolveInside(this.runDirectory(runId), normalized);
    await writeFileCreateNew(path, value);
    return this.toRelative(path);
  }

  async emit(
    runId: string,
    stage: string,
    message: string,
    level: PipelineEvent["level"] = "info",
    evidencePath?: string,
  ): Promise<PipelineEvent> {
    const sequence = this.#sequences.get(runId) ?? 0;
    this.#sequences.set(runId, sequence + 1);
    const event = pipelineEventSchema.parse({
      schemaVersion: 1,
      runId,
      sequence,
      timestampUtc: new Date().toISOString(),
      level,
      stage,
      message,
      ...(evidencePath ? { evidencePath } : {}),
    });
    await writeJsonCreateNew(
      resolve(
        this.runDirectory(runId),
        "events",
        `${String(sequence).padStart(5, "0")}.json`,
      ),
      event,
    );
    this.#events.emit("event", event);
    return event;
  }

  onEvent(listener: (event: PipelineEvent) => void): () => void {
    this.#events.on("event", listener);
    return () => this.#events.off("event", listener);
  }

  async recent(limit = 20): Promise<RunSummary[]> {
    if (!(await fileExists(this.root))) {
      return [];
    }
    const entries = await readdir(this.root, { withFileTypes: true });
    const summaries: RunSummary[] = [];
    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }
      try {
        summaries.push(await this.get(entry.name));
      } catch {
        // An incomplete run remains local evidence but is omitted from the overview.
      }
    }
    return summaries
      .sort((left, right) =>
        right.startedAtUtc.localeCompare(left.startedAtUtc),
      )
      .slice(0, limit);
  }
}
