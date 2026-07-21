import type {
  ModelConfiguration,
  SaveModelConfigurationInput,
} from "./contracts.js";
import { requestData } from "./server.js";

export function getModelConfiguration(): Promise<ModelConfiguration> {
  return requestData<ModelConfiguration>({
    method: "GET",
    url: "/users/me/model-configuration",
  });
}

export function saveModelConfiguration(
  input: SaveModelConfigurationInput,
): Promise<ModelConfiguration> {
  return requestData<ModelConfiguration>({
    method: "PUT",
    url: "/users/me/model-configuration",
    data: omitBlankApiKeys(input),
  });
}

export function omitBlankApiKeys(
  input: SaveModelConfigurationInput,
): SaveModelConfigurationInput {
  return {
    orchestrator: omitBlankApiKey(input.orchestrator),
    spriteProcessor: omitBlankApiKey(input.spriteProcessor),
    referenceGenerator: omitBlankApiKey(input.referenceGenerator),
  };
}

function omitBlankApiKey(
  input: SaveModelConfigurationInput["orchestrator"],
): SaveModelConfigurationInput["orchestrator"] {
  return typeof input.apiKey === "string" && input.apiKey.trim().length > 0
    ? { ...input, apiKey: input.apiKey }
    : { endpoint: input.endpoint, model: input.model };
}
