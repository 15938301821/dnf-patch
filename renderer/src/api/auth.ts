import type {
  AuthSession,
  LoginInput,
  SessionUser,
} from "../server/contracts.js";
import { requestData } from "../server/server.js";
import { setAccessToken } from "../server/token-store.js";

export async function login(input: LoginInput): Promise<AuthSession> {
  const session = await requestData<AuthSession>({
    method: "POST",
    url: "/auth/login",
    data: input,
  });
  setAccessToken(session.accessToken);
  return session;
}

export async function getCurrentUser(): Promise<SessionUser> {
  return requestData<SessionUser>({ method: "GET", url: "/auth/me" });
}

export async function logout(): Promise<void> {
  await requestData<null>({ method: "POST", url: "/auth/logout" });
  setAccessToken(undefined);
}
