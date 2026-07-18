import { access } from "node:fs/promises";
import { dirname, resolve } from "node:path";

async function isRepositoryRoot(candidate: string): Promise<boolean> {
  try {
    await Promise.all([
      access(resolve(candidate, "AGENTS.md")),
      access(resolve(candidate, "tools", "Test-DnfProjectGate.ps1")),
      access(
        resolve(candidate, ".github", "skills", "dnf-patch-maker", "SKILL.md"),
      ),
    ]);
    return true;
  } catch {
    return false;
  }
}

export async function findRepositoryRoot(
  startDirectories: string[],
): Promise<string> {
  const visited = new Set<string>();
  for (const startDirectory of startDirectories) {
    let candidate = resolve(startDirectory);
    while (!visited.has(candidate)) {
      visited.add(candidate);
      if (await isRepositoryRoot(candidate)) {
        return candidate;
      }
      const parent = dirname(candidate);
      if (parent === candidate) {
        break;
      }
      candidate = parent;
    }
  }
  throw new Error("Could not locate the DNF patch repository root.");
}
