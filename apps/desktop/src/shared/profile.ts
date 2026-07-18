import { z } from "zod";

const relativeTemplatePath = z
  .string()
  .min(1)
  .refine(
    (value) =>
      !value.includes("\\") &&
      !value.includes(":") &&
      !value.startsWith("/") &&
      !value.split("/").includes(".."),
  );

export const executionProfileSchema = z.object({
  schemaVersion: z.literal(1),
  id: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  professionId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  profession: z.string().min(1),
  theme: z.string().min(1),
  scope: z.enum(["single-skill", "manifest-scope"]),
  fullSkillCoverageProven: z.literal(false),
  selectedSkills: z.array(z.string()).min(1),
  promptBindings: z
    .array(
      z.object({
        displayName: z.string().min(1),
        professionPromptPath: relativeTemplatePath,
        themePromptPath: relativeTemplatePath,
      }),
    )
    .min(1),
  themeAgentPath: relativeTemplatePath,
  fallbackPalette: z
    .array(z.string().regex(/^#[0-9A-Fa-f]{6}$/))
    .min(2)
    .max(16),
  control: z.object({
    baseConfigPath: relativeTemplatePath,
    materializedConfigPath: relativeTemplatePath,
    stylePlanPath: relativeTemplatePath,
    outputNpkPath: relativeTemplatePath,
    buildSummaryPath: relativeTemplatePath,
  }),
  steps: z
    .array(
      z.object({
        id: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
        toolId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
        phase: z.enum(["preflight", "inventory", "post-model"]),
        dependsOn: z.array(z.string()),
        mode: z.enum(["read-only", "workspace-write"]),
        arguments: z.record(z.string(), z.json()),
        expectedOutputs: z.array(relativeTemplatePath),
        successPredicates: z.array(z.string()).min(1),
      }),
    )
    .min(1),
  delivery: z.object({
    npkPath: relativeTemplatePath,
    validationSummaryPath: relativeTemplatePath,
    evidencePaths: z.array(relativeTemplatePath),
    clientCompatibilityProven: z.literal(false),
    deploymentAuthorized: z.literal(false),
  }),
});
export type ExecutionProfile = z.infer<typeof executionProfileSchema>;

export const executionProfileIndexSchema = z.object({
  schemaVersion: z.literal(1),
  profiles: z.array(
    z.object({
      id: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
      path: relativeTemplatePath,
      enabled: z.boolean(),
    }),
  ),
});
export type ExecutionProfileIndex = z.infer<typeof executionProfileIndexSchema>;
