export const MODEL_IDS = {
  orchestrator: "gpt-5.6-sol",
  engineer: "gpt-5.5",
  artist: "gpt-image-2",
} as const;

export const MODEL_ENV_OVERRIDES = {
  orchestrator: "DNF_PATCH_ORCHESTRATOR_MODEL",
  engineer: "DNF_PATCH_ENGINEER_MODEL",
  artist: "DNF_PATCH_IMAGE_MODEL",
} as const;

export const OPENAI_API_KEY_ENV = "OPENAI_API_KEY";

export function resolveModelId(
  role: keyof typeof MODEL_IDS,
  environment: Readonly<Record<string, string | undefined>> = {},
): string {
  return environment[MODEL_ENV_OVERRIDES[role]]?.trim() || MODEL_IDS[role];
}
