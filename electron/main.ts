import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { app, BrowserWindow, dialog, session } from "electron";
import { isAllowedRendererNavigation } from "./utils/window-security.js";

const mainDirectory = fileURLToPath(new URL(".", import.meta.url));

function rendererEntryUrl(): string {
  return (
    process.env.ELECTRON_RENDERER_URL ??
    pathToFileURL(join(mainDirectory, "../renderer/index.html")).toString()
  );
}

function hardenSession(): void {
  session.defaultSession.setPermissionCheckHandler(() => false);
  session.defaultSession.setPermissionRequestHandler(
    (_webContents, _permission, callback) => callback(false),
  );
}

async function createWindow(): Promise<BrowserWindow> {
  const entryUrl = rendererEntryUrl();
  const window = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 980,
    minHeight: 680,
    show: false,
    backgroundColor: "#f3f5f7",
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
  window.webContents.on("will-attach-webview", (event) => {
    event.preventDefault();
  });
  window.webContents.on("will-navigate", (event, targetUrl) => {
    if (!isAllowedRendererNavigation(targetUrl, entryUrl)) {
      event.preventDefault();
    }
  });
  window.webContents.on("will-redirect", (event, targetUrl) => {
    if (!isAllowedRendererNavigation(targetUrl, entryUrl)) {
      event.preventDefault();
    }
  });
  window.once("ready-to-show", () => window.show());
  await window.loadURL(entryUrl);
  return window;
}

app
  .whenReady()
  .then(async () => {
    hardenSession();
    await createWindow();
    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        void createWindow();
      }
    });
  })
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    dialog.showErrorBox("DNF Patch Studio 启动失败", message);
    app.exit(1);
  });

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
