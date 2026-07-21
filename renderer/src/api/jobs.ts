import type { CreatePatchTaskInput, PatchTask } from "./contracts.js";
import { requestData } from "./server.js";
import { server } from "./server.js";

export function getJobsList(): Promise<PatchTask[]> {
  return requestData<PatchTask[]>({ method: "GET", url: "/jobs" });
}

export function createPatchTask(
  input: CreatePatchTaskInput,
): Promise<PatchTask> {
  return requestData<PatchTask>({
    method: "POST",
    url: "/jobs",
    data: input,
  });
}

export async function downloadJobArtifact(jobId: string): Promise<Blob> {
  const response = await server.get<Blob>(`/jobs/${jobId}/artifact`, {
    responseType: "blob",
  });
  return response.data;
}
