import { BrowserWindow, ipcMain } from "electron";
import {
  serverRunSubscriptionSchema,
  type ServerConnectionState,
  type ServerProject,
} from "../shared/contracts/server.js";
import { IPC_CHANNELS } from "../shared/ipc.js";
import type { PatchServerClient } from "./server-client.js";

/** 注册 renderer 可见的最小服务桥；所有远端认证仍由主进程注入。 */
export function registerServerIpc(client: PatchServerClient): () => void {
  ipcMain.handle(
    IPC_CHANNELS.getServerState,
    (): ServerConnectionState => client.state(),
  );
  ipcMain.handle(
    IPC_CHANNELS.probeServer,
    async (): Promise<ServerConnectionState> => client.probe(),
  );
  ipcMain.handle(
    IPC_CHANNELS.listServerProjects,
    async (): Promise<ServerProject[]> => client.listProjects(),
  );
  ipcMain.handle(IPC_CHANNELS.subscribeServerRun, (event, input: unknown) => {
    void event;
    client.subscribeRun(serverRunSubscriptionSchema.parse(input));
  });
  return client.onEvent((serverEvent) => {
    for (const window of BrowserWindow.getAllWindows()) {
      if (!window.isDestroyed()) {
        window.webContents.send(IPC_CHANNELS.serverRunEvent, serverEvent);
      }
    }
  });
}
