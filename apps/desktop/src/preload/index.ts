import { contextBridge, ipcRenderer } from "electron";
import {
  desktopStateSchema,
  pipelineEventSchema,
  runRequestSchema,
  runSummarySchema,
  startRunResponseSchema,
  type DesktopState,
  type PipelineEvent,
  type RunRequest,
  type RunSummary,
  type StartRunResponse,
} from "../shared/contracts.js";
import { IPC_CHANNELS, type DnfPatchDesktopApi } from "../shared/ipc.js";

if (!process.contextIsolated || !process.sandboxed) {
  throw new Error(
    "DNF Patch Studio preload requires context isolation and renderer sandboxing.",
  );
}

const api: DnfPatchDesktopApi = {
  async getState(): Promise<DesktopState> {
    const value: unknown = await ipcRenderer.invoke(IPC_CHANNELS.getState);
    return desktopStateSchema.parse(value);
  },

  async startRun(request: RunRequest): Promise<StartRunResponse> {
    const input = runRequestSchema.parse(request);
    const value: unknown = await ipcRenderer.invoke(
      IPC_CHANNELS.startRun,
      input,
    );
    return startRunResponseSchema.parse(value);
  },

  async getRun(runId: string): Promise<RunSummary> {
    const value: unknown = await ipcRenderer.invoke(IPC_CHANNELS.getRun, runId);
    return runSummarySchema.parse(value);
  },

  async selectDesignFile(): Promise<string | null> {
    const value: unknown = await ipcRenderer.invoke(
      IPC_CHANNELS.selectDesignFile,
    );
    if (value !== null && typeof value !== "string") {
      throw new Error("Design file selection returned an invalid path.");
    }
    return value;
  },

  onRunEvent(listener: (event: PipelineEvent) => void): () => void {
    const handler = (
      event: Electron.IpcRendererEvent,
      payload: unknown,
    ): void => {
      void event;
      listener(pipelineEventSchema.parse(payload));
    };
    ipcRenderer.on(IPC_CHANNELS.runEvent, handler);
    return () => ipcRenderer.removeListener(IPC_CHANNELS.runEvent, handler);
  },
};

contextBridge.exposeInMainWorld("dnfPatch", api);
