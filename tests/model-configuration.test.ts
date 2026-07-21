import { describe, expect, it } from "vitest";
import type { SaveModelConfigurationInput } from "../renderer/src/api/contracts.js";
import { omitBlankApiKeys } from "../renderer/src/api/model-configuration.js";

describe("model configuration request boundary", () => {
  it("omits cleared API keys while preserving non-blank values", () => {
    const input: SaveModelConfigurationInput = {
      orchestrator: role("planner", ""),
      spriteProcessor: role("sprite", "   "),
      referenceGenerator: role("image", "temporary-value"),
    };

    expect(omitBlankApiKeys(input)).toEqual({
      orchestrator: role("planner"),
      spriteProcessor: role("sprite"),
      referenceGenerator: role("image", "temporary-value"),
    });
  });
});

function role(
  model: string,
  apiKey?: string,
): SaveModelConfigurationInput["orchestrator"] {
  return {
    endpoint: "https://models.example.com/v1",
    model,
    ...(apiKey === undefined ? {} : { apiKey }),
  };
}
