/**
 * @fileoverview 将页面捕获的未知请求错误收敛为可展示的中文消息。
 *
 * API 与页面异步流程调用本模块；输入可能是 Axios 错误、普通 Error 或未知值，输出只用于
 * 用户提示，不改变请求状态、不记录敏感响应，也不取代基于 HTTP 状态的业务分支。
 */
import axios from "axios";

/** 客户端允许从错误响应读取的最小结构，其他服务端字段不会在此传播。 */
interface ApiErrorBody {
  message?: unknown;
}

/**
 * 从未知错误中提取安全且稳定的用户提示。
 *
 * @param error 页面或 Hook 捕获的未知异常，尚未假定来源或响应结构。
 * @returns 优先使用服务端字符串消息，其次映射超时与普通 Error，最后返回通用提示。
 */
export function apiErrorMessage(error: unknown): string {
  // 先验证 Axios 错误与消息类型，禁止把任意响应对象隐式转为字符串展示。
  if (axios.isAxiosError<ApiErrorBody>(error)) {
    const message = error.response?.data.message;
    if (typeof message === "string" && message.trim()) {
      return message;
    }
    if (error.code === "ECONNABORTED") {
      return "请求超时，请稍后重试。";
    }
  }
  // 非 Axios 异常只接受标准 Error.message，未知值不泄漏内部序列化结果。
  return error instanceof Error ? error.message : "请求失败，请稍后重试。";
}
