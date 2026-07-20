import {
  contextBundleSchema,
  type RunRequest,
  type RunSummary,
} from "../shared/contracts.js";
import { toolCatalogSchema } from "../shared/tool-catalog.js";
import { buildContextBundle } from "../context-builder.js";
import { ImportOrchestrator } from "../import-orchestrator.js";
import { cleanupImportSource, prepareImportSource } from "../import-source.js";
import { ImportTransactionWriter } from "../import-transaction-writer.js";
import type { RunStore } from "../run-store.js";
import { ToolBroker } from "../tool-broker.js";
import { PipelineBlockedError } from "./failure-policy.js";

/** 执行职业/主题文本的规划或受控 Prompt 树事务导入。 */
export async function runPromptImport(
  repositoryRoot: string,
  store: RunStore,
  request: RunRequest,
): Promise<RunSummary> {
  const source = await prepareImportSource(repositoryRoot, request);
  try {
    await store.update(request.runId, {
      currentStage: "import-source-freeze",
    });
    await store.emit(
      request.runId,
      "import-source-freeze",
      "Frozen a repository-local UTF-8 design source without granting it resource authority.",
      "info",
      source.relativePath,
    );
    const context = contextBundleSchema.parse(
      await buildContextBundle(repositoryRoot, request),
    );
    const contextPath = await store.writeEvidence(
      request.runId,
      "context/context-bundle.json",
      context,
    );
    await store.emit(
      request.runId,
      "import-context-freeze",
      "Frozen root rules, import skill, existing prompt tree and tool catalog.",
      "info",
      contextPath,
    );

    if (!context.toolCatalog.content) {
      throw new Error("Frozen import tool catalog content is missing.");
    }
    const catalog = toolCatalogSchema.parse(
      JSON.parse(
        context.toolCatalog.content.replace(/^\uFEFF/u, ""),
      ) as unknown,
    );
    const broker = new ToolBroker(repositoryRoot, store, catalog);
    await store.update(request.runId, {
      currentStage: "import-models",
    });
    const orchestrator = new ImportOrchestrator(
      repositoryRoot,
      store,
      broker,
      request,
    );
    const artifacts = await orchestrator.run(request, context, source);
    await store.emit(
      request.runId,
      "import-models",
      "Stored the SOL import graph, GPT-5.5 outline, fixed target plan and fixed-target semantic design.",
      "info",
      `userData/runs/${request.runId}/models/import-fixed-target-design.json`,
    );

    if (!request.execute) {
      return await store.update(request.runId, {
        status: "planned",
        currentStage: "planned-import",
        finishedAtUtc: new Date().toISOString(),
      });
    }
    if (request.provider !== "openai" || !artifacts.modelEvidenceEligible) {
      throw new PipelineBlockedError(
        "Repository import writes require eligible OpenAI GPT-5.5 store=false evidence; mock output is planning-only.",
      );
    }

    await store.update(request.runId, {
      currentStage: "import-transaction",
    });
    const writer = new ImportTransactionWriter(repositoryRoot, store, broker);
    const transaction = await writer.commit(
      request,
      artifacts.plan,
      artifacts.design,
      source.relativePath,
      artifacts.targetSnapshots,
      artifacts.authoritySnapshots,
    );
    await store.emit(
      request.runId,
      "import-transaction",
      "Committed only fixed import targets and passed the independent Prompt tree gate.",
      transaction.validation.counts.warnings > 0 ? "warning" : "info",
      transaction.receiptPath,
    );
    return await store.update(request.runId, {
      status: "passed",
      currentStage: "prompt-import-passed",
      finishedAtUtc: new Date().toISOString(),
    });
  } finally {
    // 临时来源始终清理；清理函数会先复核其字节未被事务修改。
    await cleanupImportSource(repositoryRoot, source);
  }
}
