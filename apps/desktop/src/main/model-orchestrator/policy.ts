import type { RunRequest, SolTaskGraph } from "../../shared/contracts.js";

/** 任务图必须包含的跨阶段门禁。 */
const REQUIRED_NODE_KINDS = [
  "context-freeze",
  "inventory",
  "engineering-plan",
  "aseprite-adaptation",
  "npk-package",
  "independent-validation",
  "manual-review",
  "bpk-package",
] as const;

/**
 * 验证模型任务图的 Run 绑定、必需阶段、引用完整性和无环性。
 *
 * Zod 负责单节点字段形状，这里负责只有跨节点才能判断的执行安全属性。
 */
export function assertTaskGraphPolicy(
  graph: SolTaskGraph,
  request: RunRequest,
): void {
  if (graph.runId !== request.runId) {
    throw new Error("SOL task graph RunId mismatch.");
  }

  // Map 同时检测重复节点 ID；重复 ID 会让依赖解析产生歧义。
  const nodes = new Map(graph.nodes.map((node) => [node.id, node]));
  if (nodes.size !== graph.nodes.length) {
    throw new Error("SOL task graph contains duplicate node IDs.");
  }

  for (const kind of REQUIRED_NODE_KINDS) {
    if (!graph.nodes.some((node) => node.kind === kind)) {
      throw new Error(`SOL task graph is missing required node kind: ${kind}`);
    }
  }
  if (
    request.generateImageReferences &&
    !graph.nodes.some((node) => node.kind === "image-reference")
  ) {
    throw new Error(
      "SOL task graph is missing the requested image-reference node.",
    );
  }

  // 每条依赖必须指向另一个已声明节点，禁止隐式外部步骤或自引用。
  for (const node of graph.nodes) {
    for (const dependency of node.dependsOn) {
      if (!nodes.has(dependency) || dependency === node.id) {
        throw new Error(
          `SOL task graph has an invalid dependency: ${node.id}/${dependency}`,
        );
      }
    }
  }

  // 三色深度优先遍历检测任意长度的依赖环。
  const visiting = new Set<string>();
  const visited = new Set<string>();
  const visit = (id: string): void => {
    if (visiting.has(id)) {
      throw new Error(`SOL task graph contains a cycle at ${id}.`);
    }
    if (visited.has(id)) {
      return;
    }

    visiting.add(id);
    for (const dependency of nodes.get(id)?.dependsOn ?? []) {
      visit(dependency);
    }
    visiting.delete(id);
    visited.add(id);
  };

  for (const id of nodes.keys()) {
    visit(id);
  }
}
