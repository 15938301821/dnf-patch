import axios from "axios";

interface ApiErrorBody {
  message?: unknown;
}

export function apiErrorMessage(error: unknown): string {
  if (axios.isAxiosError<ApiErrorBody>(error)) {
    const message = error.response?.data.message;
    if (typeof message === "string" && message.trim()) {
      return message;
    }
    if (error.code === "ECONNABORTED") {
      return "请求超时，请稍后重试。";
    }
  }
  return error instanceof Error ? error.message : "请求失败，请稍后重试。";
}
