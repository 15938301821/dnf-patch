import type { DnfPatchDesktopApi } from "../../shared/ipc.js";

declare global {
  interface Window {
    dnfPatch: DnfPatchDesktopApi;
  }
}

export {};
