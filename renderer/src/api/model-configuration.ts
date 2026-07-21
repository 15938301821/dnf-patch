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
    data: input,
  });
}
