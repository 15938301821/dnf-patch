import type {
  ResourceImportJob,
  ResourceImportOverview,
} from "../server/contracts.js";
import { requestData } from "../server/server.js";

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
