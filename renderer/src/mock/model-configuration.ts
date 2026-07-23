/**
 * @fileoverview 提供 Mock 模式重置时使用的脱敏模型配置种子。
 *
 * Mock Server 克隆并更新这些固定角色值，设置页只读取 endpoint、模型 ID 和
 * `keyConfigured`；示例不保存真实 API Key，也不代表对应 Provider 可连接。
 */
import type { ModelConfiguration } from "../server/contracts.js";

/** 三个固定角色的初始 Mock ViewModel，所有密钥状态均为未配置。 */
export const initialMockModelConfiguration: ModelConfiguration = {
  orchestrator: {
    endpoint: "https://api.example.com/v1",
    model: "gpt-5.6-sol",
    keyConfigured: false,
  },
  spriteProcessor: {
    endpoint: "https://api.example.com/v1",
    model: "gpt-5.5",
    keyConfigured: false,
  },
  referenceGenerator: {
    endpoint: "https://api.example.com/v1",
    model: "gpt-image-2",
    keyConfigured: false,
  },
};
