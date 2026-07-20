import { useCallback, useEffect, useState } from "react";
import type {
  ServerConnectionState,
  ServerProject,
} from "../../../server/shared/contracts.js";
import { desktopApi } from "../api/desktop-api.js";
import { errorMessage } from "../utils/run-format.js";

export interface ServerConnectionController {
  state: ServerConnectionState | undefined;
  projects: ServerProject[];
  error: string;
  probing: boolean;
  probe: () => Promise<void>;
  refreshProjects: () => Promise<void>;
}

/** 远端状态与本地流水线状态相互独立，服务离线不会阻止本地审计 Run。 */
export function useServerConnection(): ServerConnectionController {
  const [state, setState] = useState<ServerConnectionState>();
  const [projects, setProjects] = useState<ServerProject[]>([]);
  const [error, setError] = useState("");
  const [probing, setProbing] = useState(false);

  const refreshProjects = useCallback(async (): Promise<void> => {
    try {
      setProjects(await desktopApi.listServerProjects());
      setError("");
    } catch (caught) {
      setProjects([]);
      setError(errorMessage(caught));
    }
  }, []);

  const probe = useCallback(async (): Promise<void> => {
    setProbing(true);
    try {
      const next = await desktopApi.probeServer();
      setState(next);
      setError("");
      if (next.mode === "connected") {
        await refreshProjects();
      }
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setProbing(false);
    }
  }, [refreshProjects]);

  useEffect(() => {
    void probe();
  }, [probe]);

  return { state, projects, error, probing, probe, refreshProjects };
}
