import { readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { app, BrowserWindow, dialog, ipcMain } from "electron";
import {
  desktopStateSchema,
  modelCapabilitySchema,
  runRequestSchema,
  startRunResponseSchema,
  type DesktopState,
  type ModelCapability,
} from "../server/shared/contracts.js";
import { IPC_CHANNELS } from "../server/shared/ipc.js";
import {
  OPENAI_API_KEY_ENV,
  resolveModelId,
  resolveOpenAIEndpoint,
} from "../server/shared/models.js";
import {
  assertNoSymlinkChain,
  fileExists,
  toRepositoryRelative,
} from "../server/lib/filesystem.js";
import { PatchPipeline } from "../server/pipeline.js";
import { PROFESSION_ROOT } from "../server/profession-paths.js";
import { findRepositoryRoot } from "../server/repository.js";
import { registerServerIpc } from "../server/api/register-server-ipc.js";
import { PatchServerClient } from "../server/api/server-client.js";
import { LocalServerProcess } from "./utils/spawn-server.js";

const mainDirectory = fileURLToPath(new URL(".", import.meta.url));
const runIdPattern = /^[a-z0-9]+(?:[.-][a-z0-9]+)*$/u;
const modelRoles = ["orchestrator", "engineer", "artist"] as const;
const localServerProcess = new LocalServerProcess();
let serverClient: PatchServerClient | undefined;
let unregisterServerEvents: (() => void) | undefined;

async function discoverProfessions(
  repositoryRoot: string,
): Promise<DesktopState["professions"]> {
  const professions: DesktopState["professions"] = [];
  const jobsRoot = join(repositoryRoot, PROFESSION_ROOT);
  await assertNoSymlinkChain(repositoryRoot, jobsRoot);
  for (const entry of await readdir(jobsRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) {
      continue;
    }
    const professionPath = join(jobsRoot, entry.name);
    if (
      !(await fileExists(join(professionPath, "AGENTS.md"))) ||
      !(await fileExists(join(professionPath, "prompts", "README.md")))
    ) {
      continue;
    }
    await assertNoSymlinkChain(repositoryRoot, professionPath);
    const themes: string[] = [];
    for (const child of await readdir(professionPath, {
      withFileTypes: true,
    })) {
      if (!child.isDirectory()) {
        continue;
      }
      const themePath = join(professionPath, child.name);
      if (
        (await fileExists(join(themePath, "AGENTS.md"))) &&
        (await fileExists(join(themePath, "prompts", "README.md")))
      ) {
        await assertNoSymlinkChain(repositoryRoot, themePath);
        themes.push(child.name);
      }
    }
    professions.push({
      name: entry.name,
      themes: themes.sort((left, right) => left.localeCompare(right, "zh-CN")),
      hasManifest: await fileExists(join(professionPath, "manifest.json")),
    });
  }
  return professions.sort((left, right) =>
    left.name.localeCompare(right.name, "zh-CN"),
  );
}

function modelCapabilities(): ModelCapability[] {
  const apiKeyAvailable = Boolean(process.env[OPENAI_API_KEY_ENV]?.trim());
  let endpointIdentity: string | undefined;
  let endpointError: string | undefined;
  try {
    endpointIdentity = resolveOpenAIEndpoint(process.env).identity;
  } catch (error) {
    endpointError = error instanceof Error ? error.message : String(error);
  }
  return modelRoles.map((role) =>
    modelCapabilitySchema.parse({
      role,
      requestedModel: resolveModelId(role, process.env),
      provider: "openai",
      available: apiKeyAvailable && endpointError === undefined,
      checkedAtUtc: new Date().toISOString(),
      detail: !apiKeyAvailable
        ? `${OPENAI_API_KEY_ENV} is not configured; mock planning remains available.`
        : endpointError !== undefined
          ? `OpenAI-compatible endpoint configuration is invalid: ${endpointError}`
          : `${OPENAI_API_KEY_ENV} and endpoint ${endpointIdentity ?? "unknown"} are configured; reachability is checked only during an explicitly network-authorized Run.`,
    }),
  );
}

async function createWindow(): Promise<BrowserWindow> {
  const window = new BrowserWindow({
    width: 1480,
    height: 940,
    minWidth: 1060,
    minHeight: 720,
    show: false,
    backgroundColor: "#07111f",
    title: "DNF Patch Studio",
    webPreferences: {
      preload: join(mainDirectory, "../preload/index.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
    },
  });
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.once("ready-to-show", () => window.show());
  const rendererUrl = process.env.ELECTRON_RENDERER_URL;
  if (rendererUrl) {
    await window.loadURL(rendererUrl);
  } else {
    await window.loadFile(join(mainDirectory, "../renderer/index.html"));
  }
  return window;
}

function registerIpc(repositoryRoot: string, pipeline: PatchPipeline): void {
  ipcMain.handle(IPC_CHANNELS.getState, async () =>
    desktopStateSchema.parse({
      repositoryRoot,
      professions: await discoverProfessions(repositoryRoot),
      capabilities: modelCapabilities(),
      recentRuns: await pipeline.store.recent(),
    }),
  );

  ipcMain.handle(IPC_CHANNELS.startRun, async (event, input: unknown) => {
    void event;
    const request = runRequestSchema.parse(input);
    const summary = await pipeline.run(request);
    return startRunResponseSchema.parse({
      accepted: true,
      runId: request.runId,
      summary,
    });
  });

  ipcMain.handle(IPC_CHANNELS.getRun, async (event, input: unknown) => {
    void event;
    if (typeof input !== "string" || !runIdPattern.test(input)) {
      throw new Error("Invalid RunId.");
    }
    return pipeline.store.get(input);
  });

  ipcMain.handle(IPC_CHANNELS.selectDesignFile, async () => {
    const selection = await dialog.showOpenDialog({
      title: "选择职业或主题设计文本",
      properties: ["openFile"],
      filters: [
        { name: "设计文本", extensions: ["md", "txt"] },
        { name: "所有文件", extensions: ["*"] },
      ],
    });
    const [selectedPath] = selection.filePaths;
    if (selection.canceled || selectedPath === undefined) {
      return null;
    }
    await assertNoSymlinkChain(repositoryRoot, selectedPath);
    return toRepositoryRelative(repositoryRoot, selectedPath);
  });

  pipeline.store.onEvent((event) => {
    for (const window of BrowserWindow.getAllWindows()) {
      if (!window.isDestroyed()) {
        window.webContents.send(IPC_CHANNELS.runEvent, event);
      }
    }
  });
}

async function bootstrap(): Promise<void> {
  const configuredRoot = process.env.DNF_PATCH_REPOSITORY_ROOT?.trim();
  const repositoryRoot = await findRepositoryRoot(
    [configuredRoot, process.cwd(), app.getAppPath()].filter(
      (value): value is string => Boolean(value),
    ),
  );
  const pipeline = new PatchPipeline(repositoryRoot);
  registerIpc(repositoryRoot, pipeline);
  await localServerProcess.start(repositoryRoot);
  serverClient = new PatchServerClient(process.env);
  unregisterServerEvents = registerServerIpc(serverClient);
  void serverClient.probe();
  await createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      void createWindow();
    }
  });
}

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("before-quit", () => {
  unregisterServerEvents?.();
  unregisterServerEvents = undefined;
  serverClient?.close();
  serverClient = undefined;
  localServerProcess.stop();
});

app
  .whenReady()
  .then(bootstrap)
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    dialog.showErrorBox("DNF Patch Studio 启动失败", message);
    app.exit(1);
  });
