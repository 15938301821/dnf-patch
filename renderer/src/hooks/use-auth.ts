import { useCallback, useEffect } from "react";
import {
  getCurrentUser,
  login as loginRequest,
  logout as logoutRequest,
  type LoginInput,
} from "../api/index.js";
import { useAuthStore } from "../stores/auth-store.js";

export function useAuthLifecycle(): void {
  useEffect(() => {
    let active = true;
    void getCurrentUser()
      .then((user) => {
        if (active) {
          useAuthStore.getState().setAuthenticated(user);
        }
      })
      .catch(() => {
        if (active) {
          useAuthStore.getState().setAnonymous();
        }
      });
    return () => {
      active = false;
    };
  }, []);
}

export interface AuthCommands {
  login: (input: LoginInput) => Promise<void>;
  logout: () => Promise<void>;
}

export function useAuthCommands(): AuthCommands {
  const login = useCallback(async (input: LoginInput): Promise<void> => {
    const session = await loginRequest(input);
    useAuthStore.getState().setAuthenticated(session.user);
  }, []);

  const logout = useCallback(async (): Promise<void> => {
    try {
      await logoutRequest();
    } finally {
      useAuthStore.getState().setAnonymous();
    }
  }, []);

  return { login, logout };
}
