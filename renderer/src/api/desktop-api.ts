import type {
  DesktopState,
  PipelineEvent,
  RunRequest,
  ServerConnectionState,
  ServerProject,
  StartRunResponse,
} from "../../../server/shared/contracts.js";

/** renderer 的服务访问统一经过 preload；此模块不持有 URL、令牌或 fetch。 */
export const desktopApi = {
  getState(): Promise<DesktopState> {
    return window.dnfPatch.getState();
  },
  startRun(request: RunRequest): Promise<StartRunResponse> {
    return window.dnfPatch.startRun(request);
  },
  selectDesignFile(): Promise<string | null> {
    return window.dnfPatch.selectDesignFile();
  },
  onRunEvent(listener: (event: PipelineEvent) => void): () => void {
    return window.dnfPatch.onRunEvent(listener);
  },
  getServerState(): Promise<ServerConnectionState> {
    return window.dnfPatch.getServerState();
  },
  probeServer(): Promise<ServerConnectionState> {
    return window.dnfPatch.probeServer();
  },
  listServerProjects(): Promise<ServerProject[]> {
    return window.dnfPatch.listServerProjects();
  },
};
