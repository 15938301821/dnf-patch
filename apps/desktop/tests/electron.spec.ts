import type { ChildProcess } from "node:child_process";
import { mkdir, readFile, rename } from "node:fs/promises";
import { resolve } from "node:path";
import { _electron as electron, expect, test } from "@playwright/test";

const desktopRoot = resolve(import.meta.dirname, "..");
const repositoryRoot = resolve(desktopRoot, "..", "..");

async function readJson(path: string): Promise<unknown> {
  return JSON.parse(await readFile(path, "utf8")) as unknown;
}

let applicationProcess: ChildProcess | undefined;
let createdRunDirectory: string | undefined;

test.afterEach(async ({ browserName }, testInfo) => {
  void browserName;
  const childProcess = applicationProcess;
  applicationProcess = undefined;
  if (childProcess !== undefined) {
    if (childProcess.exitCode === null && childProcess.signalCode === null) {
      const exitPromise = new Promise<void>((resolveExit) => {
        childProcess.once("exit", () => resolveExit());
      });
      childProcess.kill();
      await exitPromise;
    }
  }
  if (createdRunDirectory !== undefined) {
    const evidenceDirectory = testInfo.outputPath("mock-run-evidence");
    await mkdir(resolve(evidenceDirectory, ".."), { recursive: true });
    await rename(createdRunDirectory, evidenceDirectory);
    createdRunDirectory = undefined;
  }
});

test("boots the isolated production control plane", async () => {
  const launchedApplication = await electron.launch({
    args: [resolve(desktopRoot, "out", "main", "index.js")],
    cwd: desktopRoot,
    env: {
      ...process.env,
      DNF_PATCH_REPOSITORY_ROOT: repositoryRoot,
      ELECTRON_DISABLE_SECURITY_WARNINGS: "true",
      OPENAI_API_KEY: "",
    },
  });
  const electronProcess = launchedApplication.process();
  applicationProcess = electronProcess;

  const window = await launchedApplication.firstWindow();
  await expect(window).toHaveTitle("DNF Patch Studio");
  await expect(
    window.getByRole("heading", {
      name: /从设计语义到真实 NPK/u,
    }),
  ).toBeVisible();
  await expect(window.getByRole("button", { name: /创建风格/u })).toBeVisible();

  const rendererBoundary = await window.evaluate(() => {
    const scope = globalThis as unknown as Record<string, unknown>;
    return {
      nodeProcessAvailable: typeof scope.process !== "undefined",
      requireAvailable: typeof scope.require !== "undefined",
      preloadApiAvailable: typeof scope.dnfPatch === "object",
    };
  });
  expect(rendererBoundary).toEqual({
    nodeProcessAvailable: false,
    requireAvailable: false,
    preloadApiAvailable: true,
  });

  const state = await window.evaluate(async () => {
    const api = (
      globalThis as unknown as {
        dnfPatch?: {
          getState(): Promise<{
            repositoryRoot: string;
            professions: Array<{ name: string }>;
            capabilities: Array<{
              role: string;
              requestedModel: string;
            }>;
          }>;
        };
      }
    ).dnfPatch;
    if (api === undefined) {
      throw new Error("The isolated preload API was not exposed.");
    }
    return api.getState();
  });
  expect(resolve(state.repositoryRoot)).toBe(repositoryRoot);
  expect(state.professions.some((item) => item.name === "剑魂")).toBe(true);
  expect(state.capabilities).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        role: "orchestrator",
        requestedModel: "gpt-5.6-sol",
      }),
      expect.objectContaining({ role: "engineer", requestedModel: "gpt-5.5" }),
      expect.objectContaining({
        role: "artist",
        requestedModel: "gpt-image-2",
      }),
    ]),
  );

  await window.getByRole("button", { name: /生成补丁/u }).click();
  await expect(
    window.getByRole("checkbox", { name: "授权本 Run 联网" }),
  ).not.toBeChecked();
  await expect(
    window.getByRole("checkbox", { name: "执行写步骤" }),
  ).not.toBeChecked();
  await window.getByRole("button", { name: "生成审计计划" }).click();

  const plannedStatus = window.locator(".alert.status-planned");
  await expect(
    plannedStatus.getByText("已规划", { exact: true }),
  ).toBeVisible();
  const statusText = await plannedStatus.textContent();
  const runMatch = /run-[a-z0-9]+-[a-f0-9]{10}/u.exec(statusText ?? "");
  const [runId] = runMatch ?? [];
  if (runId === undefined) {
    throw new Error(`The planned RunId was not rendered: ${statusText ?? ""}`);
  }
  createdRunDirectory = resolve(
    repositoryRoot,
    "apps",
    "desktop",
    ".runs",
    runId,
  );

  await expect
    .poll(async () => window.locator(".event").count())
    .toBeGreaterThanOrEqual(3);
  const eventStages = await window.locator(".event strong").allTextContents();
  expect(eventStages).toEqual(
    expect.arrayContaining(["bootstrap", "context-freeze", "models"]),
  );

  await expect(
    readJson(resolve(createdRunDirectory, "request.json")),
  ).resolves.toMatchObject({
    runId,
    action: "generate-patch",
    provider: "mock",
    execute: false,
    allowNetwork: false,
    generateImageReferences: false,
    deploymentAuthorized: false,
  });
  await expect(
    readJson(resolve(createdRunDirectory, "summary.json")),
  ).resolves.toMatchObject({
    runId,
    status: "planned",
    currentStage: "planned",
    deploymentAuthorized: false,
    deploymentPerformed: false,
  });
  for (const callId of [
    "sol-task-graph",
    "engineering-brief",
    "engineering-final",
    "image-reference",
  ]) {
    await expect(
      readJson(
        resolve(createdRunDirectory, "models", "calls", `${callId}.json`),
      ),
    ).resolves.toMatchObject({
      provider: "mock",
      networkAuthorized: false,
    });
  }

  await window.close();
  await expect.poll(() => electronProcess.exitCode).toBe(0);
  applicationProcess = undefined;
});
