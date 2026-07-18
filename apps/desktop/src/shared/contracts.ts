import { z } from "zod";

const sha256 = z.string().regex(/^[A-F0-9]{64}$/);
const runId = z
  .string()
  .regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/)
  .min(3)
  .max(64);
const repositoryRelativePath = z
  .string()
  .min(1)
  .refine(
    (value) =>
      !value.includes("\\") &&
      !value.includes(":") &&
      !value.startsWith("/") &&
      !value.split("/").includes(".."),
    "Expected a normalized repository-relative path",
  );
const safeLeafName = z
  .string()
  .trim()
  .min(1)
  .max(120)
  .refine(
    (value) => !/[<>:"/\\|?*]/u.test(value) && !/[ .]$/u.test(value),
    "Expected a Windows-safe leaf name",
  );
const promptDisplayNameCandidate = z
  .string()
  .trim()
  .min(1)
  .max(120)
  .refine((value) => {
    for (const character of value) {
      const code = character.codePointAt(0) ?? 0;
      if (code <= 0x1f || code === 0x7f) {
        return false;
      }
    }
    return value !== "." && value !== "..";
  }, "Expected a single-line prompt display name");
const chineseProse = z
  .string()
  .min(1)
  .max(12_000)
  .refine(
    (value) => /[\u3400-\u9fff]/u.test(value),
    "Expected Chinese stable prose",
  );
const englishPrompt = z
  .string()
  .min(1)
  .max(8_000)
  .refine(
    (value) => /[A-Za-z]/u.test(value) && !/[\u3400-\u9fff]/u.test(value),
    "Expected an English-only composable prompt",
  );

export const modelRoleSchema = z.enum(["orchestrator", "engineer", "artist"]);
export type ModelRole = z.infer<typeof modelRoleSchema>;

export const pipelineActionSchema = z.enum([
  "create-profession",
  "create-theme",
  "generate-patch",
  "validate-only",
  "package-bpk",
]);
export type PipelineAction = z.infer<typeof pipelineActionSchema>;

export const pipelineProviderSchema = z.enum(["mock", "openai"]);
export type PipelineProvider = z.infer<typeof pipelineProviderSchema>;

export const runRequestSchema = z
  .object({
    schemaVersion: z.literal(1),
    runId,
    action: pipelineActionSchema,
    provider: pipelineProviderSchema,
    profession: safeLeafName,
    theme: safeLeafName.optional(),
    designText: z.string().min(1).max(200_000).optional(),
    sourceDesignPath: repositoryRelativePath.optional(),
    workflowPath: repositoryRelativePath.optional(),
    profileId: z
      .string()
      .regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/)
      .optional(),
    selectedSkills: z.array(safeLeafName).max(256).default([]),
    execute: z.boolean().default(false),
    resume: z.boolean().default(false),
    allowNetwork: z.boolean().default(false),
    generateImageReferences: z.boolean().default(false),
    outputBaseName: safeLeafName.default("dnf-patch"),
    outputVersion: z
      .string()
      .regex(/^[0-9]+(?:\.[0-9]+){0,2}$/)
      .default("1"),
    deploymentAuthorized: z.literal(false).default(false),
  })
  .superRefine((value, context) => {
    if (value.provider === "openai" && !value.allowNetwork) {
      context.addIssue({
        code: "custom",
        path: ["allowNetwork"],
        message:
          "OpenAI provider requires explicit run-level network authorization.",
      });
    }
    if (value.resume && !value.execute) {
      context.addIssue({
        code: "custom",
        path: ["resume"],
        message: "Resume requires execute.",
      });
    }
    if (
      (value.action === "create-profession" ||
        value.action === "create-theme") &&
      !value.designText &&
      !value.sourceDesignPath
    ) {
      context.addIssue({
        code: "custom",
        path: ["designText"],
        message:
          "Creation actions require design text or a repository source path.",
      });
    }
    if (value.designText && value.sourceDesignPath) {
      context.addIssue({
        code: "custom",
        path: ["sourceDesignPath"],
        message: "Provide either design text or a source path, not both.",
      });
    }
    if (value.action === "create-theme" && !value.theme) {
      context.addIssue({
        code: "custom",
        path: ["theme"],
        message: "Theme creation requires a theme name.",
      });
    }
    if (value.action === "create-profession" && value.theme) {
      context.addIssue({
        code: "custom",
        path: ["theme"],
        message: "Profession creation cannot include a theme route.",
      });
    }
    if (
      value.execute &&
      (value.action === "create-profession" ||
        value.action === "create-theme") &&
      value.selectedSkills.length === 0
    ) {
      context.addIssue({
        code: "custom",
        path: ["selectedSkills"],
        message:
          "Executing a creation import requires user-frozen selected skills; model-inferred names are planning-only.",
      });
    }
    const selectedSkillKeys = new Set<string>();
    for (const [index, skill] of value.selectedSkills.entries()) {
      const key = skill.normalize("NFC").toLocaleLowerCase();
      if (selectedSkillKeys.has(key)) {
        context.addIssue({
          code: "custom",
          path: ["selectedSkills", index],
          message:
            "Selected skill display names must be unique after Unicode and case normalization.",
        });
      }
      selectedSkillKeys.add(key);
    }
  });
export type RunRequest = z.infer<typeof runRequestSchema>;

export const fileSnapshotSchema = z.object({
  label: z.string().min(1),
  path: repositoryRelativePath,
  length: z.number().int().nonnegative(),
  sha256,
  content: z.string().optional(),
});
export type FileSnapshot = z.infer<typeof fileSnapshotSchema>;

export const contextBundleSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  capturedAtUtc: z.iso.datetime(),
  repositoryRoot: z.string().min(1),
  professionPath: repositoryRelativePath,
  themePath: repositoryRelativePath.optional(),
  rootRules: fileSnapshotSchema,
  patchMakerSkill: fileSnapshotSchema,
  importSkill: fileSnapshotSchema.optional(),
  professionRules: fileSnapshotSchema.optional(),
  manifest: fileSnapshotSchema.optional(),
  professionPromptIndex: fileSnapshotSchema.optional(),
  professionPrompts: z.array(fileSnapshotSchema),
  themeRules: fileSnapshotSchema.optional(),
  themePromptIndex: fileSnapshotSchema.optional(),
  themePrompts: z.array(fileSnapshotSchema),
  workflow: fileSnapshotSchema.optional(),
  executionProfile: fileSnapshotSchema.optional(),
  executionProfileInputs: z.array(fileSnapshotSchema),
  materializedConfig: fileSnapshotSchema.optional(),
  sourceSummary: fileSnapshotSchema.optional(),
  sourceInventory: fileSnapshotSchema.optional(),
  toolCatalog: fileSnapshotSchema,
  missingRequiredFacts: z.array(z.string()),
  fullSkillCoverageProven: z.boolean(),
  deploymentAuthorized: z.literal(false),
});
export type ContextBundle = z.infer<typeof contextBundleSchema>;

export const taskNodeSchema = z.object({
  id: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  role: z.enum(["controller", "engineer", "artist", "adapter", "human-review"]),
  kind: z.enum([
    "context-freeze",
    "import-plan",
    "inventory",
    "engineering-plan",
    "image-reference",
    "aseprite-adaptation",
    "npk-package",
    "independent-validation",
    "manual-review",
    "bpk-package",
  ]),
  dependsOn: z.array(z.string()),
  objective: z.string().min(1).max(2_000),
  requiredEvidence: z.array(z.string()).min(1),
  blocking: z.boolean(),
});

export const solTaskGraphSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  planId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  invokedSkill: z.literal("dnf-patch-maker"),
  objective: z.string().min(1).max(4_000),
  nodes: z.array(taskNodeSchema).min(2).max(64),
  factsFromManifestOnly: z.literal(true),
  arbitraryCodeExecution: z.literal(false),
  fullSkillCoverageProven: z.literal(false),
  deploymentAuthorized: z.literal(false),
});
export type SolTaskGraph = z.infer<typeof solTaskGraphSchema>;

export const styleOperationSchema = z.object({
  type: z.enum([
    "palette-map",
    "rim-light",
    "particle-trail",
    "spatial-crack",
    "blade-core",
    "alpha-preserve",
  ]),
  target: z.string().min(1).max(500).optional(),
  color: z
    .string()
    .regex(/^#[0-9A-Fa-f]{6}$/)
    .optional(),
  colorStops: z
    .array(z.string().regex(/^#[0-9A-Fa-f]{6}$/))
    .max(16)
    .optional(),
  intensity: z.number().min(0).max(1).optional(),
  density: z.number().min(0).max(1).optional(),
  direction: z.string().max(120).optional(),
  blend: z
    .enum([
      "source-preserving",
      "additive-reference-only",
      "normal-reference-only",
    ])
    .optional(),
  notes: z.string().max(1_000).optional(),
});

export const promptBindingSchema = z.object({
  geometryPolicy: z.literal("strict-preserve-source-frame-position-size"),
  professionPromptPaths: z.array(repositoryRelativePath),
  themeAgentPath: repositoryRelativePath,
  themePromptPaths: z.array(repositoryRelativePath),
  promptPackageSha256: sha256,
});

export const engineeringStepSchema = z.object({
  id: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  toolId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  dependsOn: z.array(z.string()),
  mode: z.enum(["read-only", "workspace-write"]),
  arguments: z.record(z.string(), z.json()),
  expectedOutputs: z.array(repositoryRelativePath),
  successPredicates: z.array(z.string()).min(1),
  rationale: z.string().min(1).max(2_000),
});

export const engineeringPlanSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  planId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  promptBinding: promptBindingSchema.optional(),
  palette: z
    .array(z.string().regex(/^#[0-9A-Fa-f]{6}$/))
    .min(1)
    .max(16)
    .optional(),
  styleOperations: z.array(styleOperationSchema).max(32).default([]),
  steps: z.array(engineeringStepSchema).max(64),
  unresolvedFacts: z.array(z.string()),
  requiresHumanReview: z.literal(true),
  arbitraryCodeAccepted: z.literal(false),
  resourceFactsFromModel: z.literal(false),
  fullSkillCoverageProven: z.literal(false),
  deploymentAuthorized: z.literal(false),
});
export type EngineeringPlan = z.infer<typeof engineeringPlanSchema>;

export const engineeringDesignSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  phase: z.enum(["brief", "final"]),
  palette: z
    .array(z.string().regex(/^#[0-9A-Fa-f]{6}$/))
    .min(4)
    .max(16),
  styleOperations: z.array(styleOperationSchema).min(1).max(32),
  imagePrompt: z.string().min(1).max(8_000),
  rationale: z.string().min(1).max(4_000),
  risks: z.array(z.string().min(1).max(1_000)).max(32),
  unresolvedFacts: z.array(z.string().min(1).max(1_000)).max(64),
  arbitraryCodeAccepted: z.literal(false),
  resourceFactsFromModel: z.literal(false),
  fullSkillCoverageProven: z.literal(false),
  deploymentAuthorized: z.literal(false),
});
export type EngineeringDesign = z.infer<typeof engineeringDesignSchema>;

export const modelCallRecordSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  callId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  role: modelRoleSchema,
  model: z.string().min(1),
  provider: pipelineProviderSchema,
  status: z.enum(["passed", "failed", "skipped"]),
  startedAtUtc: z.iso.datetime(),
  finishedAtUtc: z.iso.datetime(),
  requestSha256: sha256,
  responseSha256: sha256.optional(),
  responseId: z.string().optional(),
  networkAuthorized: z.boolean(),
  responseStoragePolicy: z.enum([
    "store-false",
    "endpoint-does-not-expose-store-control",
    "mock-local-only",
  ]),
  error: z.string().optional(),
});
export type ModelCallRecord = z.infer<typeof modelCallRecordSchema>;

export const importFileProposalSchema = z.object({
  relativePath: repositoryRelativePath,
  kind: z.enum([
    "profession-agents",
    "profession-index",
    "profession-prompt",
    "theme-agents",
    "theme-index",
    "theme-prompt",
  ]),
  content: z.string().min(1).max(200_000),
});

export const importProposalSchema = z.object({
  schemaVersion: z.literal(1),
  profession: safeLeafName,
  theme: safeLeafName.optional(),
  promptNames: z.array(safeLeafName).min(1).max(256),
  files: z.array(importFileProposalSchema).min(3).max(520),
  rejectedResourceClaims: z.array(z.string()),
  rejectedProcessClaims: z.array(z.string()),
  inventoryPending: z.literal(true),
  manifestCreatedOrModified: z.literal(false),
  npkBuilt: z.literal(false),
  deploymentPerformed: z.literal(false),
});
export type ImportProposal = z.infer<typeof importProposalSchema>;

export const importTaskGraphSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  workflow: z.literal("profession-text-import"),
  orderedSteps: z.tuple([
    z.literal("inspect-source"),
    z.literal("extract-prompt-outline"),
    z.literal("compute-fixed-targets"),
    z.literal("propose-fixed-target-content"),
    z.literal("write-whitelisted-targets"),
    z.literal("validate-prompt-tree"),
    z.literal("rollback-on-failure"),
  ]),
  controls: z.object({
    modelMayChoosePaths: z.literal(false),
    modelMayCreateOrModifyManifest: z.literal(false),
    modelMayBuildNpk: z.literal(false),
    modelMayDeploy: z.literal(false),
    preserveSourceBytes: z.literal(true),
    rollbackTargetBytesOnFailure: z.literal(true),
  }),
});
export type ImportTaskGraph = z.infer<typeof importTaskGraphSchema>;

export const importOutlineSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  profession: safeLeafName,
  theme: safeLeafName.optional(),
  promptDisplayNames: z.array(promptDisplayNameCandidate).min(1).max(256),
  themePromptDisplayNames: z.array(promptDisplayNameCandidate).max(256),
  classificationSummary: z.object({
    professionStableSemantics: z.array(z.string().min(1).max(2_000)).max(256),
    themeVisualIncrements: z.array(z.string().min(1).max(2_000)).max(256),
    rejectedResourceOrCoverageClaims: z
      .array(z.string().min(1).max(2_000))
      .max(128),
  }),
  requiresTheme: z.boolean(),
  unresolvedConflicts: z.array(z.string().min(1).max(2_000)).max(128),
});
export type ImportOutline = z.infer<typeof importOutlineSchema>;

export const importPromptSemanticSchema = z.object({
  displayName: promptDisplayNameCandidate,
  professionStableSemantics: chineseProse,
  professionEnglishPrompt: englishPrompt,
  sourceConstraints: chineseProse,
  phaseAcceptance: chineseProse,
  theme: z
    .object({
      englishIncrement: englishPrompt,
      changes: chineseProse,
      acceptance: chineseProse,
      exclusions: chineseProse,
    })
    .optional(),
});

export const importDesignSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  profession: safeLeafName,
  theme: safeLeafName.optional(),
  professionRules: z.object({
    responsibilitiesAndBoundaries: chineseProse,
    resourceFactAuthority: chineseProse,
    promptLayering: chineseProse,
    characterEffectWeaponCutinBoundary: chineseProse,
    acceptanceAndRegression: chineseProse,
    coverageStatus: chineseProse,
  }),
  themeRules: z
    .object({
      objective: chineseProse,
      paletteMaterialsAndStyle: chineseProse,
      promptRouting: chineseProse,
      modificationScopeAndBoundaries: chineseProse,
      acceptanceAndRegression: chineseProse,
    })
    .optional(),
  prompts: z.array(importPromptSemanticSchema).min(1).max(256),
  rejectedResourceClaims: z.array(z.string().min(1).max(2_000)).max(128),
  rejectedProcessClaims: z.array(z.string().min(1).max(2_000)).max(128),
  inventoryPending: z.literal(true),
  manifestCreatedOrModified: z.literal(false),
  npkBuilt: z.literal(false),
  deploymentPerformed: z.literal(false),
});
export type ImportDesign = z.infer<typeof importDesignSchema>;

const importIssueSchema = z.object({
  code: z.string().min(1),
  path: z.string(),
  message: z.string().min(1),
});

const importBaselineChangeSchema = z.object({
  status: z.string().length(2),
  relativePath: repositoryRelativePath,
  exists: z.boolean(),
  sha256: sha256.nullable(),
});

export const importPlanSchema = z.object({
  schemaVersion: z.literal(1),
  status: z.enum(["passed", "failed"]),
  source: z.object({ path: z.string().min(1), sha256 }),
  route: z.object({
    profession: safeLeafName,
    professionPath: z.string().min(1),
    theme: safeLeafName.nullable(),
    themePath: z.string().nullable(),
  }),
  prompts: z
    .array(
      z.object({
        displayName: promptDisplayNameCandidate,
        safeName: safeLeafName,
        fileName: z.string().min(4).endsWith(".md"),
      }),
    )
    .min(1)
    .max(256),
  themePrompts: z
    .array(
      z.object({
        displayName: promptDisplayNameCandidate,
        safeName: safeLeafName,
        fileName: z.string().min(4).endsWith(".md"),
      }),
    )
    .max(256),
  targets: z
    .array(
      z.object({
        kind: z.enum([
          "profession-agents",
          "profession-index",
          "profession-prompt",
          "theme-agents",
          "theme-index",
          "theme-prompt",
        ]),
        path: z.string().min(1),
        relativePath: repositoryRelativePath,
        state: z.enum(["existing-file", "missing"]),
      }),
    )
    .min(3)
    .max(520),
  baselineChanges: z.array(importBaselineChangeSchema).max(10_000),
  errors: z.array(importIssueSchema),
  warnings: z.array(importIssueSchema),
});
export type ImportPlan = z.infer<typeof importPlanSchema>;

export const promptTreeResultSchema = z.object({
  schemaVersion: z.literal(1),
  status: z.enum(["passed", "failed"]),
  professionPath: z.string().min(1),
  themePath: z.string().nullable(),
  source: z.object({ path: z.string().min(1), sha256 }).nullable(),
  changes: z.array(importBaselineChangeSchema).max(10_000),
  counts: z.object({
    professionPrompts: z.number().int().nonnegative(),
    themePrompts: z.number().int().nonnegative(),
    checkedFiles: z.number().int().nonnegative(),
    errors: z.number().int().nonnegative(),
    warnings: z.number().int().nonnegative(),
  }),
  errors: z.array(importIssueSchema),
  warnings: z.array(importIssueSchema),
});
export type PromptTreeResult = z.infer<typeof promptTreeResultSchema>;

export const importTransactionReceiptSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  status: z.literal("passed"),
  source: z.object({
    relativePath: repositoryRelativePath,
    sha256,
    bytesPreserved: z.literal(true),
  }),
  route: z.object({
    profession: safeLeafName,
    theme: safeLeafName.optional(),
  }),
  targets: z.array(
    z.object({
      kind: z.enum([
        "profession-agents",
        "profession-index",
        "profession-prompt",
        "theme-agents",
        "theme-index",
        "theme-prompt",
      ]),
      relativePath: repositoryRelativePath,
      operation: z.enum(["created", "updated-index", "preserved-existing"]),
      beforeSha256: sha256.nullable(),
      afterSha256: sha256,
    }),
  ),
  validationPath: repositoryRelativePath,
  warningCount: z.number().int().nonnegative(),
  authoritySnapshots: z.array(fileSnapshotSchema),
  inventoryPending: z.literal(true),
  fullSkillCoverageProven: z.literal(false),
  manifestCreatedOrModified: z.literal(false),
  npkBuilt: z.literal(false),
  deploymentAuthorized: z.literal(false),
  deploymentPerformed: z.literal(false),
});
export type ImportTransactionReceipt = z.infer<
  typeof importTransactionReceiptSchema
>;

export const imageAttemptSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  attemptId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  model: z.literal("gpt-image-2"),
  promptSha256: sha256,
  inputSnapshots: z.array(fileSnapshotSchema.omit({ content: true })),
  outputPath: repositoryRelativePath.optional(),
  outputSha256: sha256.optional(),
  backgroundPolicy: z.literal("opaque-reference-material-only"),
  directRuntimeUseAllowed: z.literal(false),
  status: z.enum(["generated", "failed", "skipped"]),
  error: z.string().optional(),
});
export type ImageAttempt = z.infer<typeof imageAttemptSchema>;

export const toolInvocationSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  callId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  toolId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  arguments: z.record(z.string(), z.json()),
  allowNetwork: z.boolean(),
  execute: z.boolean(),
});
export type ToolInvocation = z.infer<typeof toolInvocationSchema>;

export const toolResultSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  callId: z.string(),
  toolId: z.string(),
  status: z.enum(["passed", "failed", "blocked"]),
  startedAtUtc: z.iso.datetime(),
  finishedAtUtc: z.iso.datetime(),
  exitCode: z.number().int().nullable(),
  stdout: z.string(),
  stderr: z.string(),
  parametersSha256: sha256,
  scriptSha256: sha256,
  outputs: z.array(fileSnapshotSchema.omit({ content: true })),
  deploymentAuthorized: z.literal(false),
  error: z.string().optional(),
});
export type ToolResult = z.infer<typeof toolResultSchema>;

export const bpkEntrySchema = z.object({
  archivePath: z
    .string()
    .min(1)
    .refine(
      (value) => !value.startsWith("/") && !value.split("/").includes(".."),
    ),
  sourcePath: repositoryRelativePath,
  length: z.number().int().nonnegative(),
  sha256,
  role: z.enum([
    "npk",
    "manifest",
    "final-summary",
    "validation-evidence",
    "run-evidence",
  ]),
});

export const bpkManifestSchema = z.object({
  schemaVersion: z.literal(1),
  format: z.literal("dnf-patch-bpk-v1"),
  packageId: z.string().regex(/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/),
  profession: safeLeafName,
  theme: safeLeafName,
  version: z.string().regex(/^[0-9]+(?:\.[0-9]+){0,2}$/),
  createdAtUtc: z.iso.datetime(),
  entries: z.array(bpkEntrySchema).min(2),
  offlineValidationPassed: z.boolean(),
  fullSkillCoverageProven: z.boolean(),
  clientCompatibilityProven: z.literal(false),
  deploymentAuthorized: z.literal(false),
  deploymentPerformed: z.literal(false),
  note: z.literal(
    "BPK is an application delivery container, not a native DNF package. The native payload is the included NPK.",
  ),
});
export type BpkManifest = z.infer<typeof bpkManifestSchema>;

export const pipelineEventSchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  sequence: z.number().int().nonnegative(),
  timestampUtc: z.iso.datetime(),
  level: z.enum(["info", "warning", "error"]),
  stage: z.string().min(1),
  message: z.string().min(1),
  evidencePath: repositoryRelativePath.optional(),
});
export type PipelineEvent = z.infer<typeof pipelineEventSchema>;

export const runSummarySchema = z.object({
  schemaVersion: z.literal(1),
  runId,
  status: z.enum([
    "planning",
    "planned",
    "blocked",
    "failed",
    "passed",
    "committed-with-warnings",
    "awaiting-human-review",
  ]),
  action: pipelineActionSchema,
  provider: pipelineProviderSchema,
  startedAtUtc: z.iso.datetime(),
  finishedAtUtc: z.iso.datetime().optional(),
  currentStage: z.string(),
  outputBpk: repositoryRelativePath.optional(),
  error: z.string().optional(),
  deploymentAuthorized: z.literal(false),
  deploymentPerformed: z.literal(false),
});
export type RunSummary = z.infer<typeof runSummarySchema>;

export const modelCapabilitySchema = z.object({
  role: modelRoleSchema,
  requestedModel: z.string().min(1),
  provider: pipelineProviderSchema,
  available: z.boolean(),
  checkedAtUtc: z.iso.datetime(),
  detail: z.string(),
});
export type ModelCapability = z.infer<typeof modelCapabilitySchema>;

export const desktopStateSchema = z.object({
  repositoryRoot: z.string(),
  professions: z.array(
    z.object({
      name: z.string(),
      themes: z.array(z.string()),
      hasManifest: z.boolean(),
    }),
  ),
  capabilities: z.array(modelCapabilitySchema),
  recentRuns: z.array(runSummarySchema),
});
export type DesktopState = z.infer<typeof desktopStateSchema>;

export const startRunResponseSchema = z.object({
  accepted: z.boolean(),
  runId,
  summary: runSummarySchema,
});
export type StartRunResponse = z.infer<typeof startRunResponseSchema>;
