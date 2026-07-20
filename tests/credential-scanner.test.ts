import { describe, expect, it } from "vitest";
import { scanCredentialText } from "../server/security/credential-scanner.js";

describe("credential scanner", () => {
  it("accepts environment-only credential access", () => {
    const source =
      "const apiKey = process.env.OPENAI_API_KEY?.trim();\n" +
      "const header = `Bearer ${apiKey}`;\n";

    expect(scanCredentialText("safe.ts", source)).toEqual([]);
  });

  it("detects an OpenAI-style secret without returning its value", () => {
    const secret = ["sk", "a".repeat(48)].join("-");
    const findings = scanCredentialText(
      "unsafe.ts",
      `const value = "${secret}";`,
    );

    expect(findings).toEqual([
      {
        relativePath: "unsafe.ts",
        line: 1,
        ruleId: "openai-style-secret",
      },
    ]);
    expect(JSON.stringify(findings)).not.toContain(secret);
  });

  it("detects a hard-coded environment fallback on its actual line", () => {
    const fallback = ["local", "x".repeat(32)].join("-");
    const source = [
      "const safe = true;",
      `const token = process.env.SERVICE_TOKEN || "${fallback}";`,
    ].join("\n");

    expect(scanCredentialText("fallback.ts", source)).toContainEqual({
      relativePath: "fallback.ts",
      line: 2,
      ruleId: "environment-secret-fallback",
    });
  });
});
