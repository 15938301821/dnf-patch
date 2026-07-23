/**
 * @fileoverview 读写当前用户三个固定角色的脱敏模型配置。
 *
 * 设置页通过共享受认证 Axios 客户端调用本模块；读取响应只含 endpoint、模型 ID 与
 * `keyConfigured`（仅表示服务端已有密钥），写入时 API Key 仅在用户主动提供非空值时发送。
 * 本模块不持久化、回显或返回 Key，也不直接调用模型 Provider；请求失败原样交给页面处理。
 */
import type {
  ModelConfiguration,
  SaveModelConfigurationInput,
} from "../server/contracts.js";
import { requestData } from "../server/server.js";

/**
 * 通过 `GET /users/me/model-configuration` 读取当前用户脱敏配置。
 *
 * @returns 三个固定角色的 ViewModel，绝不包含 API Key 明文或加密材料。
 */
export function getModelConfiguration(): Promise<ModelConfiguration> {
  return requestData<ModelConfiguration>({
    method: "GET",
    url: "/users/me/model-configuration",
  });
}

/**
 * 通过 `PUT /users/me/model-configuration` 保存当前用户固定角色配置。
 *
 * @param input 设置表单校验后的写入 DTO，可能短暂包含用户输入的 API Key。
 * @returns 服务端保存后的脱敏 ViewModel；空 Key 会在发送前省略以保留服务端现值。
 */
export function saveModelConfiguration(
  input: SaveModelConfigurationInput,
): Promise<ModelConfiguration> {
  return requestData<ModelConfiguration>({
    method: "PUT",
    url: "/users/me/model-configuration",
    data: omitBlankApiKeys(input),
  });
}

/**
 * 从模型配置写入 DTO 中移除空白 API Key，避免误把“留空保留”解释为清空密钥。
 *
 * @param input 设置表单的三个固定角色值，尚未离开客户端。
 * @returns 新的写入 DTO；非空 Key 保留原值，空白 Key 字段完全省略。
 */
export function omitBlankApiKeys(
  input: SaveModelConfigurationInput,
): SaveModelConfigurationInput {
  return {
    orchestrator: omitBlankApiKey(input.orchestrator),
    spriteProcessor: omitBlankApiKey(input.spriteProcessor),
    referenceGenerator: omitBlankApiKey(input.referenceGenerator),
  };
}

/** 对单个固定角色执行空 Key 省略，并保留 endpoint 与模型 ID。 */
function omitBlankApiKey(
  input: SaveModelConfigurationInput["orchestrator"],
): SaveModelConfigurationInput["orchestrator"] {
  return typeof input.apiKey === "string" && input.apiKey.trim().length > 0
    ? { ...input, apiKey: input.apiKey }
    : { endpoint: input.endpoint, model: input.model };
}
