import axios, {
  type AxiosError,
  type AxiosRequestConfig,
  type InternalAxiosRequestConfig,
} from "axios";
import type { ApiEnvelope, AuthSession } from "./contracts.js";
import { getAccessToken, setAccessToken } from "./token-store.js";

const apiBaseUrl = import.meta.env.VITE_API_BASE_URL?.trim() || "/v1";

export const server = axios.create({
  baseURL: apiBaseUrl,
  timeout: 15_000,
  withCredentials: true,
  headers: { Accept: "application/json" },
});

export const refreshClient = axios.create({
  baseURL: apiBaseUrl,
  timeout: 15_000,
  withCredentials: true,
  headers: { Accept: "application/json" },
});

let refreshRequest: Promise<string> | undefined;

function authorizationHeader(token: string): string {
  return `Bearer ${token}`;
}

export function shouldRefreshAccessToken(
  status: number | undefined,
  url: string | undefined,
  retriedAfterRefresh: boolean | undefined,
): boolean {
  return (
    status === 401 && url !== "/auth/login" && retriedAfterRefresh !== true
  );
}

async function refreshAccessToken(): Promise<string> {
  refreshRequest ??= refreshClient
    .post<ApiEnvelope<AuthSession>>("/auth/refresh")
    .then((response) => {
      setAccessToken(response.data.data.accessToken);
      return response.data.data.accessToken;
    })
    .finally(() => {
      refreshRequest = undefined;
    });
  return refreshRequest;
}

server.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  const token = getAccessToken();
  if (token) {
    config.headers.Authorization = authorizationHeader(token);
  }
  return config;
});

server.interceptors.response.use(undefined, async (error: AxiosError) => {
  const request = error.config as
    | (InternalAxiosRequestConfig & { retriedAfterRefresh?: boolean })
    | undefined;
  if (
    !request ||
    !shouldRefreshAccessToken(
      error.response?.status,
      request.url,
      request.retriedAfterRefresh,
    )
  ) {
    throw error;
  }
  request.retriedAfterRefresh = true;
  try {
    request.headers.Authorization = authorizationHeader(
      await refreshAccessToken(),
    );
    return await server.request(request);
  } catch (refreshError) {
    setAccessToken(undefined);
    throw refreshError;
  }
});

export async function requestData<T>(config: AxiosRequestConfig): Promise<T> {
  const response = await server.request<ApiEnvelope<T>>(config);
  return response.data.data;
}
