/**
 * @fileoverview 验证模型配置请求边界不会发送空白 API Key。
 *
 * 测试只调用纯 DTO 转换函数，保护“留空保留现有密钥”不被误写为空值；没有发 HTTPS 请求、
 * 没有接触真实密钥，也不证明服务端加密、用户隔离或模型 Provider 集成。
 */
import { describe, expect, it } from "vitest";
import type { SaveModelConfigurationInput } from "../renderer/src/server/contracts.js";
import { omitBlankApiKeys } from "../renderer/src/api/model-configuration.js";

describe("model configuration request boundary", () => {
  it("omits cleared API keys while preserving non-blank values", () => {
    const input: SaveModelConfigurationInput = {
      orchestrator: role("planner", ""),
      spriteProcessor: role("sprite", "   "),
      referenceGenerator: role("image", "temporary-value"),
    };

    expect(omitBlankApiKeys(input)).toEqual({
      orchestrator: role("planner"),
      spriteProcessor: role("sprite"),
      referenceGenerator: role("image", "temporary-value"),
    });
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
): SaveModelConfigurationInput["orchestrator"] {
  return {
    endpoint: "https://models.example.com/v1",
    model,
    ...(apiKey === undefined ? {} : { apiKey }),
  };
}
