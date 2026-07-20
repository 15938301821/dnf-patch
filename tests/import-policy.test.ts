import { describe, expect, it } from "vitest";
import { runRequestSchema } from "../server/shared/contracts.js";
import { classifyPipelineFailure } from "../server/pipeline.js";

function importRequest(overrides: Record<string, unknown> = {}): unknown {
  return {
    schemaVersion: 1,
    runId: "import-policy",
    action: "create-profession",
    provider: "mock",
    profession: "TestProfession",
    sourceDesignPath: "jobs/TestProfession/design.md",
    selectedSkills: [],
    execute: false,
    allowNetwork: false,
    generateImageReferences: false,
    outputBaseName: "test-import",
    outputVersion: "1",
    deploymentAuthorized: false,
    ...overrides,
  };
}

describe("import execution policy", () => {
  it("allows model-inferred names only for planning", () => {
    expect(runRequestSchema.safeParse(importRequest()).success).toBe(true);
    expect(
      runRequestSchema.safeParse(importRequest({ execute: true })).success,
    ).toBe(false);
  });

  it("requires user-frozen names to be unique after normalization", () => {
    const result = runRequestSchema.safeParse(
      importRequest({
        selectedSkills: ["Skill", "Ｓｋｉｌｌ", "SKILL"],
      }),
    );
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(
        result.error.issues.some((issue) => issue.path[0] === "selectedSkills"),
      ).toBe(true);
    }
  });

  it("preserves committed state across later failures", () => {
    expect(classifyPipelineFailure(true, false)).toBe(
      "committed-with-warnings",
    );
    expect(classifyPipelineFailure(true, true)).toBe("committed-with-warnings");
    expect(classifyPipelineFailure(false, true)).toBe("blocked");
    expect(classifyPipelineFailure(false, false)).toBe("failed");
  });
});
