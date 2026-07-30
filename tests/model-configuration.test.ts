/**
 * @fileoverview 验证模型配置请求边界不会发送空白 API Key。
 *
 * 测试只调用纯 DTO 转换函数，保护“留空保留现有密钥”不被误写为空值；没有发 HTTPS 请求、
 * 没有接触真实密钥，也不证明服务端加密、用户隔离或模型 Provider 集成。
 */
import { describe, expect, it } from "vitest";
import type {
  ModelConfiguration,
  SaveModelConfigurationInput,
} from "../renderer/src/server/contracts.js";
import {
  missingModelRoleLabels,
  modelFormValues,
  omitBlankApiKeys,
} from "../renderer/src/api/model-configuration.js";

describe("model configuration request boundary", () => {
  it("omits cleared API keys while preserving non-blank values", () => {
    const input: SaveModelConfigurationInput = {
      orchestrator: role("planner", "", "max"),
      spriteProcessor: role("sprite", "   ", "medium"),
      referenceGenerator: role("image", "temporary-value"),
    };

    expect(omitBlankApiKeys(input)).toEqual({
      orchestrator: role("planner", undefined, "max"),
      spriteProcessor: role("sprite", undefined, "medium"),
      referenceGenerator: role("image", "temporary-value"),
    });
  });

  it("defaults the read-only reference reasoning effort for legacy responses", () => {
    const configuration: ModelConfiguration = {
      orchestrator: configuredRole("planner", "high"),
      spriteProcessor: configuredRole("sprite", "medium"),
      referenceGenerator: {
        ...configuredRole("image", "default"),
        reasoningEffort: undefined as unknown as "default",
      },
    };

    expect(modelFormValues(configuration)).toMatchObject({
      orchestrator: { reasoningEffort: "high" },
      spriteProcessor: { reasoningEffort: "medium" },
      referenceGenerator: { reasoningEffort: "default" },
    });
  });

  it("lists every model role missing a configured key in workflow order", () => {
    const configuration: ModelConfiguration = {
      orchestrator: configuredRole("planner", false),
      referenceGenerator: configuredRole("image", false),
      spriteProcessor: configuredRole("sprite", true),
    };

    expect(missingModelRoleLabels(configuration)).toEqual([
      "总任务调度",
      "参考图生成",
    ]);
  });
});

/**
 * 构造单个固定角色的测试写入 DTO。
 *
 * @param model 用于区分三个角色的测试模型 ID。
 * @param apiKey 可选临时测试值；缺失时字段完全省略。
 * @returns 不含真实凭据的角色配置输入。
 */
function role(
  model: string,
  apiKey?: string,
  reasoningEffort: SaveModelConfigurationInput["orchestrator"]["reasoningEffort"] = "default",
): SaveModelConfigurationInput["orchestrator"] {
  return {
    endpoint: "https://models.example.com/v1",
    model,
    reasoningEffort,
    ...(apiKey === undefined ? {} : { apiKey }),
  };
}

/** 构造不含真实凭据的脱敏读取配置，用于验证读取值到表单值的转换。 */
function configuredRole(
  model: string,
  reasoningEffortOrConfigured:
    ModelConfiguration["orchestrator"]["reasoningEffort"] | boolean,
): ModelConfiguration["orchestrator"] {
  return {
    endpoint: "https://models.example.com/v1",
    model,
    reasoningEffort:
      typeof reasoningEffortOrConfigured === "boolean"
        ? "default"
        : reasoningEffortOrConfigured,
    keyConfigured:
      typeof reasoningEffortOrConfigured === "boolean"
        ? reasoningEffortOrConfigured
        : false,
  };
}
