import { io, type Socket } from "socket.io-client";
import { z } from "zod";
import {
  serverConnectionStateSchema,
  serverHealthSchema,
  serverProjectSchema,
  serverRunEventSchema,
  serverRunSubscriptionSchema,
  type ServerConnectionState,
  type ServerProject,
  type ServerRunEvent,
  type ServerRunSubscription,
} from "../shared/contracts/server.js";
import {
  resolveServerConfiguration,
  type ServerConfiguration,
} from "./server-config.js";

const requestTimeoutMs = 5_000;

type ServerEventListener = (event: ServerRunEvent) => void;

/** 主进程专用服务客户端；renderer 永远拿不到认证令牌或原始远端响应。 */
export class PatchServerClient {
  readonly #configuration: ServerConfiguration | undefined;
  readonly #configurationError: string | undefined;
  readonly #listeners = new Set<ServerEventListener>();
  #socket: Socket | undefined;
  #state: ServerConnectionState;

  constructor(environment: Readonly<Record<string, string | undefined>>) {
    let configuration: ServerConfiguration | undefined;
    let configurationError: string | undefined;
    try {
      configuration = resolveServerConfiguration(environment);
    } catch (error) {
      configurationError = safeError(error);
    }
    this.#configuration = configuration;
    this.#configurationError = configurationError;
    this.#state = serverConnectionStateSchema.parse({
      schemaVersion: 1,
      mode: configuration ? "offline" : "disabled",
      configured: Boolean(configuration?.token),
      endpointIdentity:
        configuration?.endpoint.identity ?? "configuration-invalid",
      detail: configurationError ?? "服务连接尚未探测。",
      checkedAtUtc: new Date().toISOString(),
    });
  }

  state(): ServerConnectionState {
    return this.#state;
  }

  async probe(): Promise<ServerConnectionState> {
    const configuration = this.#configuration;
    if (!configuration) {
      return this.#setState(
        "disabled",
        this.#configurationError ?? "服务配置无效。",
      );
    }
    try {
      const health = serverHealthSchema.parse(
        await this.#requestJson(
          `${configuration.endpoint.baseUrl}/health`,
          false,
        ),
      );
      if (!configuration.token) {
        return this.#setState(
          "degraded",
          "服务可达，但主进程未配置客户端令牌。",
          health,
        );
      }
      if (health.database !== "available") {
        return this.#setState(
          "degraded",
          "服务可达，但 MySQL 不可用。",
          health,
        );
      }
      this.#connectSocket({ ...configuration, token: configuration.token });
      return this.#setState("connected", "REST 与事件通道配置可用。", health);
    } catch (error) {
      this.#disconnectSocket();
      return this.#setState("offline", safeError(error));
    }
  }

  async listProjects(): Promise<ServerProject[]> {
    const configuration = this.#requireAuthenticatedConfiguration();
    const value = await this.#requestJson(
      `${configuration.endpoint.baseUrl}/projects`,
      true,
    );
    return z.array(serverProjectSchema).parse(value);
  }

  subscribeRun(input: ServerRunSubscription): void {
    const parsed = serverRunSubscriptionSchema.parse(input);
    if (!this.#socket?.connected) {
      throw new Error("服务事件通道尚未连接。");
    }
    this.#socket.emit("run:subscribe", parsed);
  }

  onEvent(listener: ServerEventListener): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  close(): void {
    this.#disconnectSocket();
    this.#listeners.clear();
  }

  async #requestJson(url: string, authenticated: boolean): Promise<unknown> {
    const configuration = this.#configuration;
    if (!configuration) {
      throw new Error(this.#configurationError ?? "服务配置无效。");
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), requestTimeoutMs);
    try {
      const response = await fetch(url, {
        method: "GET",
        signal: controller.signal,
        ...(authenticated && configuration.token
          ? { headers: { Authorization: `Bearer ${configuration.token}` } }
          : {}),
      });
      if (!response.ok) {
        throw new Error(`服务请求失败，HTTP ${String(response.status)}。`);
      }
      return await response.json();
    } finally {
      clearTimeout(timeout);
    }
  }

  #requireAuthenticatedConfiguration(): ServerConfiguration & {
    token: string;
  } {
    const configuration = this.#configuration;
    if (!configuration?.token) {
      throw new Error("主进程未配置服务客户端令牌。");
    }
    return { ...configuration, token: configuration.token };
  }

  #connectSocket(configuration: ServerConfiguration & { token: string }): void {
    if (this.#socket) {
      return;
    }
    const socket = io(configuration.endpoint.socketUrl, {
      auth: { token: configuration.token },
      autoConnect: true,
      reconnection: true,
      transports: ["websocket"],
    });
    socket.on("run:event", (value: unknown) => {
      const result = serverRunEventSchema.safeParse(value);
      if (result.success) {
        for (const listener of this.#listeners) {
          listener(result.data);
        }
      }
    });
    socket.on("connect_error", () => {
      this.#setState("degraded", "REST 可用，但事件通道连接失败。");
    });
    this.#socket = socket;
  }

  #disconnectSocket(): void {
    this.#socket?.disconnect();
    this.#socket = undefined;
  }

  #setState(
    mode: ServerConnectionState["mode"],
    detail: string,
    health?: ServerConnectionState["health"],
  ): ServerConnectionState {
    this.#state = serverConnectionStateSchema.parse({
      schemaVersion: 1,
      mode,
      configured: Boolean(this.#configuration?.token),
      endpointIdentity:
        this.#configuration?.endpoint.identity ?? "configuration-invalid",
      detail,
      checkedAtUtc: new Date().toISOString(),
      ...(health ? { health } : {}),
    });
    return this.#state;
  }
}

function safeError(error: unknown): string {
  if (error instanceof DOMException && error.name === "AbortError") {
    return "服务连接超时。";
  }
  return (error instanceof Error ? error.message : String(error)).slice(
    0,
    1_000,
  );
}
