export const MODEL_IDS = {
  orchestrator: "gpt-5.6-sol",
  engineer: "gpt-5.5",
  artist: "gpt-image-2",
} as const;

export const MODEL_ENV_OVERRIDES = {
  orchestrator: "DNF_PATCH_ORCHESTRATOR_MODEL",
  engineer: "DNF_PATCH_ENGINEER_MODEL",
  artist: "DNF_PATCH_IMAGE_MODEL",
} as const;

export const OPENAI_API_KEY_ENV = "OPENAI_API_KEY";
export const OPENAI_BASE_URL_ENV = "OPENAI_BASE_URL";
export const DEFAULT_OPENAI_BASE_URL = "https://api.openai.com/v1";
export const OPENAI_REQUEST_TIMEOUT_MS = 180_000;
export const OPENAI_REQUEST_MAX_RETRIES = 2;

export interface OpenAIEndpointConfiguration {
  baseURL: string;
  identity: string;
  custom: boolean;
}

/**
 * 解析 OpenAI 兼容端点，同时剥离容易泄露凭据或改变请求语义的 URL 部分。
 *
 * 兼容网关必须显式提供 `/v1` 版本路径，避免 SDK 把请求误发到网站根目录。
 * 这里只返回非敏感端点身份；API Key 始终由独立环境变量提供。
 */
export function resolveOpenAIEndpoint(
  environment: Readonly<Record<string, string | undefined>> = {},
): OpenAIEndpointConfiguration {
  const configured = environment[OPENAI_BASE_URL_ENV]?.trim();
  const raw = configured || DEFAULT_OPENAI_BASE_URL;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Error(`${OPENAI_BASE_URL_ENV} must be an absolute URL.`);
  }
  if (url.protocol !== "https:") {
    throw new Error(`${OPENAI_BASE_URL_ENV} must use HTTPS.`);
  }
  if (url.username || url.password) {
    throw new Error(`${OPENAI_BASE_URL_ENV} must not contain credentials.`);
  }
  if (url.search || url.hash) {
    throw new Error(
      `${OPENAI_BASE_URL_ENV} must not contain a query string or fragment.`,
    );
  }
  const pathname = url.pathname.replace(/\/+$/u, "");
  if (pathname !== "/v1" && !pathname.endsWith("/v1")) {
    throw new Error(
      `${OPENAI_BASE_URL_ENV} must include its OpenAI-compatible /v1 path.`,
    );
  }
  url.pathname = pathname;
  return {
    baseURL: url.toString().replace(/\/$/u, ""),
    identity: `${url.host}${pathname}`,
    custom: configured !== undefined && configured.length > 0,
  };
}

export function resolveModelId(
  role: keyof typeof MODEL_IDS,
  environment: Readonly<Record<string, string | undefined>> = {},
): string {
  return environment[MODEL_ENV_OVERRIDES[role]]?.trim() || MODEL_IDS[role];
}
