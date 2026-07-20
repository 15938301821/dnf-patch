/** 可公开报告的凭据风险；结果故意不包含匹配文本。 */
export interface CredentialFinding {
  relativePath: string;
  line: number;
  ruleId: CredentialRuleId;
}

export type CredentialRuleId =
  | "api-credential-literal"
  | "bearer-token-literal"
  | "environment-secret-fallback"
  | "openai-style-secret"
  | "private-key-block";

interface CredentialRule {
  id: CredentialRuleId;
  expression: RegExp;
}

/**
 * 规则只识别高置信度凭据形态，避免把普通哈希、模型 ID 或配置变量误报。
 * 每个表达式必须使用全局模式，以便一次文件扫描返回全部风险位置。
 */
const credentialRules: readonly CredentialRule[] = [
  {
    id: "openai-style-secret",
    expression: /\bsk-[A-Za-z0-9_-]{32,}\b/gu,
  },
  {
    id: "bearer-token-literal",
    expression: /\bBearer[ \t]+[A-Za-z0-9._~+/=-]{20,}\b/gu,
  },
  {
    id: "api-credential-literal",
    expression:
      /\b(?:apiKey|api_key|accessToken|access_token)\b\s*(?::|=)\s*["'`][A-Za-z0-9._~+/=-]{16,}["'`]/giu,
  },
  {
    id: "environment-secret-fallback",
    expression:
      /process\.env(?:\.[A-Z][A-Z0-9_]*|\[["'][A-Z][A-Z0-9_]*["']\])(?:\?\.trim\(\))?\s*(?:\?\?|\|\|)\s*["'`][^"'`\r\n]{16,}["'`]/gu,
  },
  {
    id: "private-key-block",
    expression: /-----BEGIN (?:EC |OPENSSH |PGP |RSA )?PRIVATE KEY-----/gu,
  },
];

/** 扫描单个文本，并仅返回可安全展示的位置元数据。 */
export function scanCredentialText(
  relativePath: string,
  text: string,
): CredentialFinding[] {
  const lineStarts = collectLineStarts(text);
  const findings: CredentialFinding[] = [];
  for (const rule of credentialRules) {
    // 每次创建新表达式，避免全局 RegExp 的 lastIndex 跨文件漂移。
    const expression = new RegExp(
      rule.expression.source,
      rule.expression.flags,
    );
    for (const match of text.matchAll(expression)) {
      findings.push({
        relativePath,
        line: lineNumberAtOffset(lineStarts, match.index),
        ruleId: rule.id,
      });
    }
  }
  return findings.sort(
    (left, right) =>
      left.line - right.line || left.ruleId.localeCompare(right.ruleId),
  );
}

/** 预计算行首偏移，避免每个匹配都重新遍历整个文件。 */
function collectLineStarts(text: string): number[] {
  const starts = [0];
  for (let index = 0; index < text.length; index += 1) {
    if (text.charCodeAt(index) === 10) {
      starts.push(index + 1);
    }
  }
  return starts;
}

/** 用二分查找把字符偏移转换为一基行号。 */
function lineNumberAtOffset(
  lineStarts: readonly number[],
  offset: number,
): number {
  let lower = 0;
  let upper = lineStarts.length;
  while (lower < upper) {
    const middle = Math.floor((lower + upper) / 2);
    const start = lineStarts[middle];
    if (start !== undefined && start <= offset) {
      lower = middle + 1;
    } else {
      upper = middle;
    }
  }
  return Math.max(1, lower);
}
