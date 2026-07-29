/**
 * @fileoverview 编辑当前用户一个固定模型角色的 endpoint、模型 ID 与可选新 API Key。
 *
 * 设置页的 Ant Design Form 拥有字段和提交生命周期，本组件只声明嵌套字段及校验；读取配置
 * 始终脱敏，已配置时留空表示保留。组件不持久化、不回显 Key，也不直接调用模型 Provider。
 */
import { Form, Input, Select, Tag } from "antd";
import type {
  ModelRoleConfiguration,
  SaveModelConfigurationInput,
} from "../../server/contracts.js";
import styles from "./index.module.scss";

/** 设置契约允许编辑的三个固定角色键。 */
type ModelRole = keyof SaveModelConfigurationInput;

/** 单个角色表单区块的脱敏配置与展示契约。 */
interface ModelRoleFormProps {
  configuration: ModelRoleConfiguration | undefined;
  description: string;
  icon: React.ReactNode;
  reasoningSupported?: boolean;
  role: ModelRole;
  sequence: string;
  tags: readonly string[];
  title: string;
}

/**
 * 渲染一个固定模型角色的受控表单字段。
 *
 * @param props 父表单提供的角色键、脱敏配置和职责文案。
 * @returns endpoint、模型和密码输入；保存与清理仍由设置页负责。
 */
export function ModelRoleForm({
  configuration,
  description,
  icon,
  reasoningSupported = true,
  role,
  sequence,
  tags,
  title,
}: ModelRoleFormProps): React.JSX.Element {
  return (
    <section className={styles.role} data-role={role}>
      <div className={styles.heading}>
        <div className={styles.icon}>{icon}</div>
        <div className={styles.copy}>
          <span>{sequence}</span>
          <strong>{title}</strong>
          <p>{description}</p>
        </div>
        <div className={styles.tags} aria-label={`${title}职责`}>
          {tags.map((tag) => (
            <Tag className={styles.tag ?? ""} key={tag}>
              {tag}
            </Tag>
          ))}
        </div>
      </div>
      <div className={styles.fields}>
        <Form.Item
          label="API 地址"
          name={[role, "endpoint"]}
          rules={[
            { required: true, message: "请输入 HTTPS 模型 API 地址" },
            { type: "url", message: "请输入有效的模型 API 地址" },
          ]}
        >
          <Input maxLength={500} placeholder="https://provider.example/v1" />
        </Form.Item>
        <Form.Item
          label="模型"
          name={[role, "model"]}
          rules={[{ required: true, message: "请输入模型 ID" }]}
        >
          <Input maxLength={120} />
        </Form.Item>
        <Form.Item
          extra={
            reasoningSupported
              ? "仅影响支持 Responses 推理参数的文本模型"
              : "图片生成接口使用 Provider 默认行为"
          }
          label="推理强度"
          name={[role, "reasoningEffort"]}
          rules={[{ required: true, message: "请选择推理强度" }]}
        >
          <Select
            disabled={!reasoningSupported}
            options={
              reasoningSupported
                ? [
                    { label: "低 · low", value: "low" },
                    { label: "中 · medium", value: "medium" },
                    { label: "高 · high", value: "high" },
                    { label: "超高 · xhigh", value: "xhigh" },
                    { label: "最大 · max", value: "max" },
                    { label: "极致 · ultra", value: "ultra" },
                  ]
                : [{ label: "图片接口不适用", value: "default" }]
            }
            popupMatchSelectWidth
            virtual={false}
          />
        </Form.Item>
        <Form.Item
          extra={
            configuration?.keyConfigured
              ? "留空则保留当前 Key"
              : "首次配置必须填写"
          }
          label="API Key"
          name={[role, "apiKey"]}
          rules={[
            {
              /** 已有服务端密钥时允许留空保留，否则要求本次提供非空新值。 */
              validator: (_, value: unknown) => {
                if (
                  configuration?.keyConfigured ||
                  (typeof value === "string" && value.trim().length > 0)
                ) {
                  return Promise.resolve();
                }
                return Promise.reject(new Error("请输入 API Key"));
              },
            },
          ]}
        >
          <Input.Password
            autoComplete="new-password"
            maxLength={4_096}
            placeholder={
              configuration?.keyConfigured ? "已配置，留空保留" : "输入 API Key"
            }
          />
        </Form.Item>
      </div>
    </section>
  );
}
