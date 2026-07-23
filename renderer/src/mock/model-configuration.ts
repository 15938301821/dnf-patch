import type { ModelConfiguration } from "../server/contracts.js";

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
