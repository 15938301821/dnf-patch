import { Form, Input, Tag } from "antd";
import { KeyRound } from "lucide-react";
import type {
  ModelConfiguration,
  SaveModelConfigurationInput,
} from "../../api/contracts.js";
import styles from "./index.module.scss";

type ModelRole = keyof ModelConfiguration;

interface ModelRoleFormProps {
  configuration: ModelConfiguration[ModelRole] | undefined;
  description: string;
  icon: React.ReactNode;
  modelPlaceholder: string;
  name: keyof SaveModelConfigurationInput;
  sequence: string;
  tags: readonly string[];
  title: string;
}

export function ModelRoleForm({
  configuration,
  description,
  icon,
  modelPlaceholder,
  name,
  sequence,
  tags,
  title,
}: ModelRoleFormProps): React.JSX.Element {
  return (
    <section className={styles.role} data-role={name}>
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
          className={styles.field ?? ""}
          label="API 地址"
          name={[name, "endpoint"]}
          rules={[
            { required: true, message: "请输入 API 地址" },
            { type: "url", message: "请输入完整 URL" },
          ]}
        >
          <Input placeholder="https://api.example.com/v1" />
        </Form.Item>
        <Form.Item
          className={styles.field ?? ""}
          label="模型名称"
          name={[name, "model"]}
          rules={[{ required: true, message: "请输入模型名称" }]}
        >
          <Input placeholder={modelPlaceholder} />
        </Form.Item>
        <Form.Item
          className={styles.field ?? ""}
          extra={
            configuration?.keyConfigured
              ? "留空保留已保存的 Key"
              : "首次配置必须填写"
          }
          label="API Key"
          name={[name, "apiKey"]}
          rules={[
            {
              validator: (_, value: unknown) => {
                if (
                  !configuration?.keyConfigured &&
                  (typeof value !== "string" || !value.trim())
                ) {
                  return Promise.reject(new Error("请输入 API Key"));
                }
                return Promise.resolve();
              },
            },
          ]}
        >
          <Input.Password
            autoComplete="new-password"
            placeholder={configuration?.keyConfigured ? "已配置" : "输入 Key"}
            prefix={<KeyRound aria-hidden="true" size={16} />}
          />
        </Form.Item>
      </div>
    </section>
  );
}
