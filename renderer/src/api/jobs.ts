import type {
  CreatePatchTaskInput,
  PatchTask,
  PatchTaskArtifact,
} from "./contracts.js";
import { requestData } from "./server.js";

export function getJobsList(): Promise<PatchTask[]> {
  return requestData<PatchTask[]>({ method: "GET", url: "/jobs" });
}

export function createPatchTask(
  input: CreatePatchTaskInput,
  idempotencyKey = `patch.${crypto.randomUUID()}`,
): Promise<PatchTask> {
  return requestData<PatchTask>({
    method: "POST",
    url: "/jobs",
    data: input,
    headers: { "Idempotency-Key": idempotencyKey },
  });
}

export function getJobArtifactMetadata(
  jobId: string,
): Promise<PatchTaskArtifact> {
  return requestData<PatchTaskArtifact>({
    method: "GET",
    url: `/jobs/${jobId}/artifact`,
  });
}
