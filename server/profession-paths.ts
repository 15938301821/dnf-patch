import { resolveInside } from "./lib/filesystem.js";

export const PROFESSION_ROOT = "jobs";

/** 将职业显示名映射到仓库内唯一的物理职业目录。 */
export function professionRelativePath(profession: string): string {
  if (
    profession.length === 0 ||
    profession.includes("/") ||
    profession.includes("\\")
  ) {
    throw new Error(`Profession must be a safe leaf name: ${profession}`);
  }
  return `${PROFESSION_ROOT}/${profession}`;
}

export function professionAbsolutePath(
  repositoryRoot: string,
  profession: string,
): string {
  return resolveInside(repositoryRoot, professionRelativePath(profession));
}

export function themeRelativePath(profession: string, theme: string): string {
  if (theme.length === 0 || theme.includes("/") || theme.includes("\\")) {
    throw new Error(`Theme must be a safe leaf name: ${theme}`);
  }
  return `${professionRelativePath(profession)}/${theme}`;
}
