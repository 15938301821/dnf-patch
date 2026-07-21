import type { ResourceImportJob, ResourceImportOverview } from "./contracts.js";
import { requestData } from "./server.js";

export function getResourceImportOverview(): Promise<ResourceImportOverview> {
  return requestData<ResourceImportOverview>({
    method: "GET",
    url: "/resource-imports/overview",
  });
}

export function createResourceImportJob(): Promise<ResourceImportJob> {
  return requestData<ResourceImportJob>({
    method: "POST",
    url: "/resource-imports/jobs",
  });
}
