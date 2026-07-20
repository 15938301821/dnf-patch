import type {
  DesktopState,
  PipelineEvent,
  RunRequest,
  RunSummary,
  ServerConnectionState,
  ServerProject,
  ServerRunEvent,
  ServerRunSubscription,
  StartRunResponse,
} from "./contracts.js";

export const IPC_CHANNELS = {
  getState: "dnf-patch:get-state",
  startRun: "dnf-patch:start-run",
  getRun: "dnf-patch:get-run",
  selectDesignFile: "dnf-patch:select-design-file",
  runEvent: "dnf-patch:run-event",
  getServerState: "dnf-patch:get-server-state",
  probeServer: "dnf-patch:probe-server",
  listServerProjects: "dnf-patch:list-server-projects",
  subscribeServerRun: "dnf-patch:subscribe-server-run",
  serverRunEvent: "dnf-patch:server-run-event",
} as const;

export interface DnfPatchDesktopApi {
  getState(): Promise<DesktopState>;
  startRun(request: RunRequest): Promise<StartRunResponse>;
  getRun(runId: string): Promise<RunSummary>;
  selectDesignFile(): Promise<string | null>;
  onRunEvent(listener: (event: PipelineEvent) => void): () => void;
  getServerState(): Promise<ServerConnectionState>;
  probeServer(): Promise<ServerConnectionState>;
  listServerProjects(): Promise<ServerProject[]>;
  subscribeServerRun(input: ServerRunSubscription): Promise<void>;
  onServerRunEvent(listener: (event: ServerRunEvent) => void): () => void;
}
