import { Form, Input, Tag } from "antd";
import type {
  ModelRoleConfiguration,
  SaveModelConfigurationInput,
} from "../../server/contracts.js";
import styles from "./index.module.scss";

type ModelRole = keyof SaveModelConfigurationInput;

interface ModelRoleFormProps {
  configuration: ModelRoleConfiguration | undefined;
  description: string;
  icon: React.ReactNode;
  role: ModelRole;
  sequence: string;
  tags: readonly string[];
  title: string;
}

export function ModelRoleForm({
  configuration,
  description,
  icon,
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
            configuration?.keyConfigured
              ? "留空则保留当前 Key"
              : "首次配置必须填写"
          }
          label="API Key"
          name={[role, "apiKey"]}
          rules={[
            {
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
