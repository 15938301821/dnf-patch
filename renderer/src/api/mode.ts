export type ApiMode = "mock" | "remote";

export function resolveApiMode(value: string | undefined): ApiMode {
  return value === "mock" ? "mock" : "remote";
}

export const apiMode = resolveApiMode(import.meta.env.VITE_API_MODE);
