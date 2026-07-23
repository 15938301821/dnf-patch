import { create } from "zustand";
import type { SessionUser } from "../server/contracts.js";

export type AuthStatus = "booting" | "anonymous" | "authenticated";

export interface AuthStore {
  status: AuthStatus;
  user: SessionUser | undefined;
  setAuthenticated: (user: SessionUser) => void;
  setAnonymous: () => void;
}

export const useAuthStore = create<AuthStore>((set) => ({
  status: "booting",
  user: undefined,
  setAuthenticated(user): void {
    set({ status: "authenticated", user });
  },
  setAnonymous(): void {
    set({ status: "anonymous", user: undefined });
  },
}));
