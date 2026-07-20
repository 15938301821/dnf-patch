import { z } from "zod";

const relativePath = z
  .string()
  .min(1)
  .refine(
    (value) =>
      !value.includes("\\") &&
      !value.includes(":") &&
      !value.startsWith("/") &&
      !value.split("/").includes(".."),
  );

export const toolCatalogEntrySchema = z
  .object({
    id: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
    label: z.string().min(1),
    description: z.string().min(1),
    notes: z.array(z.string()),
    responsibility: z.enum([
      "resource",
      "prompt",
      "image",
      "package",
      "validation",
      "workflow",
      "release",
    ]),
    capability: z.enum([
      "inspect",
      "plan",
      "generate",
      "render",
      "encode",
      "package",
      "validate",
      "orchestrate",
    ]),
    scope: z.enum(["common", "profession-specific"]),
    visibility: z.enum(["public", "private"]),
    professionId: z.string().optional(),
    script: relativePath,
    host: z.enum(["windows-powershell-x64", "windows-powershell-x86"]),
    mode: z.enum(["read-only", "workspace-write"]),
    network: z.enum(["forbidden", "explicit-authorization-required"]),
    outputFormat: z.enum(["json", "key-value", "text"]),
    allowedParameters: z.array(z.string()),
    requiredParameters: z.array(z.string()),
    pathParameters: z.array(z.string()),
    writePathParameters: z.array(z.string()),
    forcedParameters: z.record(z.string(), z.json()),
    allowedWriteRoots: z.array(relativePath),
    modelRoles: z.array(z.enum(["orchestrator", "engineer"])),
    defaultGenerationEligible: z.boolean(),
    brokerExecutable: z.boolean(),
  })
  .superRefine((value, context) => {
    for (const name of [
      ...value.requiredParameters,
      ...value.pathParameters,
      ...value.writePathParameters,
      ...Object.keys(value.forcedParameters),
    ]) {
      if (!value.allowedParameters.includes(name)) {
        context.addIssue({
          code: "custom",
          message: `Parameter ${name} is not allowlisted.`,
        });
      }
    }
    if (value.mode === "read-only" && value.writePathParameters.length > 0) {
      context.addIssue({
        code: "custom",
        message: "Read-only tools cannot declare write paths.",
      });
    }
    if (value.scope === "profession-specific" && !value.professionId) {
      context.addIssue({
        code: "custom",
        message: "Profession-specific tools require professionId.",
      });
    }
  });

export const toolCatalogSchema = z.object({
  schemaVersion: z.literal(1),
  policy: z.object({
    arbitraryScriptExecution: z.literal(false),
    modelChoosesScriptPath: z.literal(false),
    networkDefault: z.literal("forbidden"),
    deployment: z.literal("forbidden"),
    imagePacks2Write: z.literal("forbidden"),
  }),
  tools: z.array(toolCatalogEntrySchema),
});
export type ToolCatalog = z.infer<typeof toolCatalogSchema>;
export type ToolCatalogEntry = z.infer<typeof toolCatalogEntrySchema>;
