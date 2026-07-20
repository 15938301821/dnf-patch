import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { runRequestSchema } from "../shared/contracts.js";
import { PatchPipeline } from "../pipeline.js";
import { findRepositoryRoot } from "../repository.js";

interface CliOptions {
  requestPath: string;
  repositoryRoot?: string;
}

function usage(): string {
  return [
    "Usage: npm run agent -- --request <request.json> [--repo <repository-root>]",
    "",
    "The request is parsed by the same Zod contract and executed by the same",
    "PatchPipeline used by the Electron application.",
  ].join("\n");
}

function parseOptions(arguments_: string[]): CliOptions {
  let requestPath: string | undefined;
  let repositoryRoot: string | undefined;
  for (let index = 0; index < arguments_.length; index += 1) {
    const token = arguments_[index];
    const value = arguments_[index + 1];
    if ((token === "--request" || token === "--repo") && value === undefined) {
      throw new Error(`Missing value for ${token}.`);
    }
    if (token === "--request") {
      requestPath = value;
      index += 1;
    } else if (token === "--repo") {
      repositoryRoot = value;
      index += 1;
    } else if (token === "--help" || token === "-h") {
      process.stdout.write(`${usage()}\n`);
      process.exit(0);
    } else {
      throw new Error(`Unknown CLI argument: ${token ?? "<empty>"}`);
    }
  }
  if (requestPath === undefined) {
    throw new Error("--request is required.");
  }
  return {
    requestPath: resolve(requestPath),
    ...(repositoryRoot === undefined
      ? {}
      : { repositoryRoot: resolve(repositoryRoot) }),
  };
}

async function main(): Promise<void> {
  const options = parseOptions(process.argv.slice(2));
  const repositoryRoot = await findRepositoryRoot([
    ...(options.repositoryRoot ? [options.repositoryRoot] : []),
    process.cwd(),
    dirname(options.requestPath),
  ]);
  const input = runRequestSchema.parse(
    JSON.parse(await readFile(options.requestPath, "utf8")) as unknown,
  );
  const summary = await new PatchPipeline(repositoryRoot).run(input);
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  if (summary.status === "failed" || summary.status === "blocked") {
    process.exitCode = 1;
  }
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`${message}\n\n${usage()}\n`);
  process.exitCode = 1;
});
