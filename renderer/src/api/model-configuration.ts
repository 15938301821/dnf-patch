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

const modelRoleLabels = [
  ["orchestrator", "总任务调度"],
  ["referenceGenerator", "参考图生成"],
  ["spriteProcessor", "精灵图处理"],
] as const satisfies ReadonlyArray<readonly [keyof ModelConfiguration, string]>;

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

/**
 * 把脱敏读取 ViewModel 转为不含 API Key 的可编辑表单值。
 *
 * @param configuration 后端返回的三个固定角色配置；兼容参考图旧记录缺少推理强度。
 * @returns 可直接写入设置表单的值；参考图角色始终使用服务端允许的 `default`。
 */
export function modelFormValues(
  configuration: ModelConfiguration,
): SaveModelConfigurationInput {
  return {
    orchestrator: editableRole(configuration.orchestrator),
    spriteProcessor: editableRole(configuration.spriteProcessor),
    referenceGenerator: {
      ...editableRole(configuration.referenceGenerator),
      // 图片角色不接受可选推理参数；固定回填唯一合法值，避免旧响应缺字段时只读控件空白。
      reasoningEffort: "default",
    },
  };
}

/**
 * 列出当前用户尚未配置 API Key 的固定模型角色。
 *
 * @param configuration 服务端返回的脱敏配置，只读取 `keyConfigured`，不接触 Key 明文。
 * @returns 面向用户的缺失角色名称；空数组表示可继续执行客户端任务创建流程。
 */
export function missingModelRoleLabels(
  configuration: ModelConfiguration,
): string[] {
  return modelRoleLabels
    .filter(([role]) => !configuration[role].keyConfigured)
    .map(([, label]) => label);
}

/** 保留单个角色的 endpoint 与模型 ID，刻意不构造 Key 字段。 */
function editableRole(
  configuration: ModelConfiguration[keyof ModelConfiguration],
): SaveModelConfigurationInput[keyof SaveModelConfigurationInput] {
  return {
    endpoint: configuration.endpoint,
    model: configuration.model,
    reasoningEffort: configuration.reasoningEffort,
  };
}

/** 对单个固定角色执行空 Key 省略，并保留 endpoint、模型 ID 与推理强度。 */
function omitBlankApiKey(
  input: SaveModelConfigurationInput["orchestrator"],
): SaveModelConfigurationInput["orchestrator"] {
  return typeof input.apiKey === "string" && input.apiKey.trim().length > 0
    ? { ...input, apiKey: input.apiKey }
    : {
        endpoint: input.endpoint,
        model: input.model,
        reasoningEffort: input.reasoningEffort,
      };
}
