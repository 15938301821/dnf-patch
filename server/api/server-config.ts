export const SERVER_URL_ENV = "DNF_PATCH_SERVER_URL";
export const SERVER_CLIENT_TOKEN_ENV = "DNF_PATCH_SERVER_CLIENT_TOKEN";
export const DEFAULT_SERVER_URL = "http://127.0.0.1:56789/v1";

export interface ServerEndpoint {
  baseUrl: string;
  socketUrl: string;
  identity: string;
}

export interface ServerConfiguration {
  endpoint: ServerEndpoint;
  token?: string;
}

/**
 * 服务端允许本机 HTTP 或任意 HTTPS；禁止 URL 凭据、查询参数和缺失 `/v1`。
 * 客户端令牌单独读取，绝不拼入 URL、错误文本或 renderer 数据。
 */
export function resolveServerConfiguration(
  environment: Readonly<Record<string, string | undefined>> = {},
): ServerConfiguration {
  const endpoint = resolveServerEndpoint(
    environment[SERVER_URL_ENV]?.trim() || DEFAULT_SERVER_URL,
  );
  const token = environment[SERVER_CLIENT_TOKEN_ENV]?.trim();
  if (token !== undefined && token.length > 0 && token.length < 32) {
    throw new Error(
      `${SERVER_CLIENT_TOKEN_ENV} must contain at least 32 characters.`,
    );
  }
  return {
    endpoint,
    ...(token ? { token } : {}),
  };
}

export function resolveServerEndpoint(value: string): ServerEndpoint {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`${SERVER_URL_ENV} must be an absolute URL.`);
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Error(
      `${SERVER_URL_ENV} must not contain credentials, query data or fragments.`,
    );
  }
  const loopback = ["127.0.0.1", "::1", "localhost"].includes(url.hostname);
  if (url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) {
    throw new Error(
      `${SERVER_URL_ENV} must use HTTPS unless it targets loopback.`,
    );
  }
  const pathname = url.pathname.replace(/\/+$/u, "");
  if (pathname !== "/v1" && !pathname.endsWith("/v1")) {
    throw new Error(`${SERVER_URL_ENV} must include the versioned /v1 path.`);
  }
  url.pathname = pathname;
  return {
    baseUrl: url.toString().replace(/\/$/u, ""),
    socketUrl: `${url.origin}/runs`,
    identity: `${url.host}${pathname}`,
  };
}
