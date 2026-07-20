import type { DnfPatchDesktopApi } from "../../server/shared/ipc.js";

declare global {
  interface Window {
    dnfPatch: DnfPatchDesktopApi;
  }
}

export {};
