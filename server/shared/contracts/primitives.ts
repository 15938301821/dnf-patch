import { z } from "zod";

/**
 * 共享契约的基础值约束。
 *
 * 本文件只负责字符串和哈希的词法校验。真实路径是否位于仓库内、
 * 是否经过重解析点，以及文件是否存在，仍由主进程文件系统边界验证。
 */
export const sha256Schema = z.string().regex(/^[A-F0-9]{64}$/);

/** RunId 同时用于目录名和证据关联键，因此只允许稳定的小写标识符。 */
export const runIdSchema = z
  .string()
  .regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/)
  .min(3)
  .max(64);

/**
 * 仓库相对路径的词法格式。
 *
 * 这里只拒绝绝对路径、反斜杠和上级跳转；调用方仍必须执行仓库包含性
 * 与 reparse-point 检查，不能把通过该 schema 当作文件系统授权。
 */
export const repositoryRelativePathSchema = z
  .string()
  .min(1)
  .refine(
    (value) =>
      !value.includes("\\") &&
      !value.includes(":") &&
      !value.startsWith("/") &&
      !value.split("/").includes(".."),
    "Expected a normalized repository-relative path",
  );

/** Windows 目录或文件叶名称；不接受路径分隔符和保留结尾。 */
export const safeLeafNameSchema = z
  .string()
  .trim()
  .min(1)
  .max(120)
  .refine(
    (value) => !/[<>:"/\\|?*]/u.test(value) && !/[ .]$/u.test(value),
    "Expected a Windows-safe leaf name",
  );

/** 模型可建议的 Prompt 显示名；最终文件名仍由固定本地计划计算。 */
export const promptDisplayNameCandidateSchema = z
  .string()
  .trim()
  .min(1)
  .max(120)
  .refine((value) => {
    for (const character of value) {
      const code = character.codePointAt(0) ?? 0;
      if (code <= 0x1f || code === 0x7f) {
        return false;
      }
    }
    return value !== "." && value !== "..";
  }, "Expected a single-line prompt display name");

/** 需要进入仓库规则文件的稳定中文说明。 */
export const chineseProseSchema = z
  .string()
  .min(1)
  .max(12_000)
  .refine(
    (value) => /[\u3400-\u9fff]/u.test(value),
    "Expected Chinese stable prose",
  );

/** 直接交给图像模型组合的英文 Prompt 片段。 */
export const englishPromptSchema = z
  .string()
  .min(1)
  .max(8_000)
  .refine(
    (value) => /[A-Za-z]/u.test(value) && !/[\u3400-\u9fff]/u.test(value),
    "Expected an English-only composable prompt",
  );
