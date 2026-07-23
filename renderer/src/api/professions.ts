import type {
  CreateProfessionInput,
  CreateProfessionStyleInput,
  ProfessionSkillSummary,
  ProfessionStyle,
  ProfessionSummary,
  SaveProfessionStyleInput,
} from "../server/contracts.js";
import { requestData } from "../server/server.js";
import { normalizeProfessionStyle } from "../utils/profession-style.js";

export function getProfessionsList(): Promise<ProfessionSummary[]> {
  return requestData<ProfessionSummary[]>({
    method: "GET",
    url: "/professions",
  });
}

export function createProfession(
  input: CreateProfessionInput,
): Promise<ProfessionSummary> {
  return requestData<ProfessionSummary>({
    method: "POST",
    url: "/professions",
    data: input,
  });
}

export function getProfessionSkills(
  professionId: string,
): Promise<ProfessionSkillSummary[]> {
  return requestData<ProfessionSkillSummary[]>({
    method: "GET",
    url: `/professions/${professionId}/skills`,
  });
}

export function getProfessionStyles(
  professionId: string,
): Promise<ProfessionStyle[]> {
  return requestData<ProfessionStyle[]>({
    method: "GET",
    url: `/professions/${professionId}/styles`,
  }).then((styles) => styles.map(normalizeProfessionStyle));
}

export function createProfessionStyle(
  professionId: string,
  input: CreateProfessionStyleInput,
): Promise<ProfessionStyle> {
  return requestData<ProfessionStyle>({
    method: "POST",
    url: `/professions/${professionId}/styles`,
    data: input,
  });
}

export function saveProfessionStyle(
  professionId: string,
  styleId: string,
  input: SaveProfessionStyleInput,
): Promise<ProfessionStyle> {
  return requestData<ProfessionStyle>({
    method: "PUT",
    url: `/professions/${professionId}/styles/${styleId}`,
    data: input,
  });
}

export function submitStyleForReview(
  professionId: string,
  styleId: string,
): Promise<ProfessionStyle> {
  return requestData<ProfessionStyle>({
    method: "POST",
    url: `/professions/${professionId}/styles/${styleId}/review`,
  });
}
