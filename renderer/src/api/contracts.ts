export interface SessionUser {
  id: string;
  username: string;
  displayName: string;
}

export interface AuthSession {
  accessToken: string;
  user: SessionUser;
}

export interface LoginInput {
  username: string;
  password: string;
}

export interface ModelRoleConfiguration {
  endpoint: string;
  model: string;
  keyConfigured: boolean;
  keyPreview?: string;
}

export interface SaveModelRoleConfigurationInput {
  endpoint: string;
  model: string;
  apiKey?: string;
}

export interface ModelConfiguration {
  orchestrator: ModelRoleConfiguration;
  spriteProcessor: ModelRoleConfiguration;
  referenceGenerator: ModelRoleConfiguration;
}

export interface SaveModelConfigurationInput {
  orchestrator: SaveModelRoleConfigurationInput;
  spriteProcessor: SaveModelRoleConfigurationInput;
  referenceGenerator: SaveModelRoleConfigurationInput;
}

export type PublishStatus = "private" | "pending" | "published" | "rejected";

export interface ProfessionSummary {
  id: string;
  name: string;
  slug: string;
  styleCount: number;
  publishStatus: PublishStatus;
  updatedAt: string;
}

export interface CreateProfessionInput {
  name: string;
  slug: string;
}

export type SkillPromptStatus = "candidate" | "reviewed";
export type SkillMappingStatus = "unverified" | "verified";
export type SkillExecutionStatus = "draft-only" | "build-ready";

export interface ProfessionSkillSummary {
  id: string;
  professionId: string;
  displayName: string;
  promptStatus: SkillPromptStatus;
  mappingStatus: SkillMappingStatus;
  executionStatus: SkillExecutionStatus;
}

export interface ProfessionStyle {
  id: string;
  professionId: string;
  name: string;
  description: string;
  agent: string;
  prompt: string;
  selectedSkillIds: string[];
  publishStatus: PublishStatus;
  updatedAt: string;
}

export interface SaveProfessionStyleInput {
  name: string;
  description: string;
  agent: string;
  prompt: string;
  selectedSkillIds: string[];
}

export type CreateProfessionStyleInput = SaveProfessionStyleInput;

export type PatchTaskStatus = "queued" | "running" | "passed" | "failed";

export interface PatchTask {
  id: string;
  professionName: string;
  styleName: string;
  status: PatchTaskStatus;
  progress: number;
  createdAt: string;
  artifactName?: string;
  downloadUrl?: string;
}

export interface CreatePatchTaskInput {
  professionId: string;
  styleId: string;
}

export interface ApiEnvelope<T> {
  data: T;
}
