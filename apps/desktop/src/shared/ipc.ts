import type {
  DesktopState,
  PipelineEvent,
  RunRequest,
  RunSummary,
  StartRunResponse,
} from "./contracts.js";

export const IPC_CHANNELS = {
  getState: "dnf-patch:get-state",
  startRun: "dnf-patch:start-run",
  getRun: "dnf-patch:get-run",
  selectDesignFile: "dnf-patch:select-design-file",
  runEvent: "dnf-patch:run-event",
} as const;

export interface DnfPatchDesktopApi {
  getState(): Promise<DesktopState>;
  startRun(request: RunRequest): Promise<StartRunResponse>;
  getRun(runId: string): Promise<RunSummary>;
  selectDesignFile(): Promise<string | null>;
  onRunEvent(listener: (event: PipelineEvent) => void): () => void;
}
