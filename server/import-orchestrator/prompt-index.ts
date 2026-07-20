import { basename } from "node:path";
import type { ContextBundle, FileSnapshot } from "../shared/contracts.js";

/** Unicode 与大小写无关的显示名比较键；显示文本本身始终保持原样。 */
export function canonicalPromptName(value: string): string {
  return value.normalize("NFC").toLocaleLowerCase();
}

/** 从既有 Prompt 的唯一 H1 读取显示名。 */
function promptTitle(snapshot: FileSnapshot): string {
  const match = /^#[ \t]+(?<title>.+?)[ \t]*$/mu.exec(snapshot.content ?? "");
  const title = match?.groups?.title?.trim();
  if (!title) {
    throw new Error(`Existing prompt has no single H1 title: ${snapshot.path}`);
  }
  return title;
}

/**
 * 读取索引的“当前文件”节。
 *
 * fenced code 中的列表看起来可能像文件条目，因此显式跟踪围栏状态；只
 * 接受同目录 Markdown 叶文件，路径合法性最终仍由固定规划脚本验证。
 */
function indexFileNames(content: string | undefined): string[] {
  if (!content) {
    return [];
  }

  const lines = content.split(/\r\n|\n|\r/u);
  const result: string[] = [];
  let inCurrentFiles = false;
  let fence: string | undefined;
  for (const line of lines) {
    if (fence) {
      const marker = fence[0] === "`" ? "`" : "~";
      if (
        new RegExp(
          `^[ ]{0,3}${marker}{${String(fence.length)},}[ \\t]*$`,
          "u",
        ).test(line)
      ) {
        fence = undefined;
      }
      continue;
    }

    const fenceMatch = /^[ ]{0,3}(?<fence>`{3,}|~{3,})/u.exec(line);
    if (fenceMatch?.groups?.fence) {
      fence = fenceMatch.groups.fence;
      continue;
    }

    const heading = /^##[ \t]+(?<title>.+?)[ \t]*$/u.exec(line)?.groups?.title;
    if (heading) {
      const normalized = heading
        .replace(/^\s*[\u4e00-\u9fff0-9]+[\u3001.\uff0e]\s*/u, "")
        .trim();
      if (inCurrentFiles) {
        break;
      }
      inCurrentFiles = normalized === "当前文件";
      continue;
    }
    if (!inCurrentFiles) {
      continue;
    }

    const codeEntry = /^\s*[-*+]\s+`(?<path>[^`]+\.md)`\s*$/iu.exec(line)
      ?.groups?.path;
    const linkEntry = /^\s*[-*+]\s+\[[^\]]+\]\((?<path>[^)]+\.md)\)\s*$/iu.exec(
      line,
    )?.groups?.path;
    const entry = codeEntry ?? linkEntry;
    if (entry && !entry.includes("/") && !entry.includes("\\")) {
      result.push(entry);
    }
  }
  return result;
}

/** 按既有索引顺序返回职业 Prompt 显示名，并在末尾补充未索引文件。 */
export function existingProfessionPromptNames(
  context: ContextBundle,
): string[] {
  const snapshots = new Map(
    context.professionPrompts.map((snapshot) => [
      canonicalPromptName(basename(snapshot.path)),
      snapshot,
    ]),
  );
  const ordered: FileSnapshot[] = [];
  const seen = new Set<string>();

  for (const fileName of indexFileNames(
    context.professionPromptIndex?.content,
  )) {
    const key = canonicalPromptName(fileName);
    const snapshot = snapshots.get(key);
    if (!snapshot || seen.has(key)) {
      continue;
    }
    seen.add(key);
    ordered.push(snapshot);
  }
  for (const snapshot of context.professionPrompts) {
    const key = canonicalPromptName(basename(snapshot.path));
    if (!seen.has(key)) {
      seen.add(key);
      ordered.push(snapshot);
    }
  }
  return ordered.map(promptTitle);
}

/** 按主题索引顺序返回显示名，并强制同名职业 Prompt 先存在。 */
export function existingThemePromptNames(context: ContextBundle): string[] {
  const professionByFileName = new Map(
    context.professionPrompts.map((snapshot) => [
      canonicalPromptName(basename(snapshot.path)),
      promptTitle(snapshot),
    ]),
  );
  const themeByFileName = new Map(
    context.themePrompts.map((snapshot) => [
      canonicalPromptName(basename(snapshot.path)),
      snapshot,
    ]),
  );
  const orderedFileNames = [
    ...indexFileNames(context.themePromptIndex?.content),
    ...context.themePrompts.map((snapshot) => basename(snapshot.path)),
  ];
  const result: string[] = [];
  const seen = new Set<string>();

  for (const fileName of orderedFileNames) {
    const key = canonicalPromptName(fileName);
    if (seen.has(key) || !themeByFileName.has(key)) {
      continue;
    }
    const professionName = professionByFileName.get(key);
    if (!professionName) {
      throw new Error(
        `Existing theme Prompt has no same-name profession Prompt: ${fileName}`,
      );
    }
    seen.add(key);
    result.push(professionName);
  }
  return result;
}
