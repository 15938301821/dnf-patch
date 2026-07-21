import type {
  ModelConfiguration,
  ModelRoleConfiguration,
  SaveModelConfigurationInput,
  SaveModelRoleConfigurationInput,
} from "./contracts.js";

export const initialMockModelConfiguration: ModelConfiguration = {
  orchestrator: {
    endpoint: "https://api.example.com/v1",
    model: "gpt-5.6-sol",
    keyConfigured: false,
  },
  spriteProcessor: {
    endpoint: "https://api.example.com/v1",
    model: "gpt-5.5",
    keyConfigured: false,
  },
  referenceGenerator: {
    endpoint: "https://api.example.com/v1",
    model: "gpt-image-2",
    keyConfigured: false,
  },
};

function saveModelRole(
  input: SaveModelRoleConfigurationInput,
  current: ModelRoleConfiguration,
): ModelRoleConfiguration {
  const apiKey = input.apiKey?.trim();
  return {
    endpoint: input.endpoint.trim(),
    model: input.model.trim(),
    keyConfigured: Boolean(apiKey) || current.keyConfigured,
    ...(apiKey
      ? { keyPreview: "••••••••" }
      : current.keyPreview
        ? { keyPreview: current.keyPreview }
        : {}),
  };
}

export function saveMockModelConfiguration(
  input: SaveModelConfigurationInput,
  current: ModelConfiguration,
): ModelConfiguration {
  return {
    orchestrator: saveModelRole(input.orchestrator, current.orchestrator),
    spriteProcessor: saveModelRole(
      input.spriteProcessor,
      current.spriteProcessor,
    ),
    referenceGenerator: saveModelRole(
      input.referenceGenerator,
      current.referenceGenerator,
    ),
  };
}
