import { Tag } from "antd";
import type { ModelRoleConfiguration } from "../../api/contracts.js";
import styles from "./index.module.scss";

interface ModelRoleStatusProps {
  configuration: ModelRoleConfiguration | undefined;
  description: string;
  icon: React.ReactNode;
  role: "orchestrator" | "referenceGenerator" | "spriteProcessor";
  sequence: string;
  tags: readonly string[];
  title: string;
}

/** 展示服务端环境托管的固定模型角色，不提供浏览器写配置入口。 */
export function ModelRoleStatus({
  configuration,
  description,
  icon,
  role,
  sequence,
  tags,
  title,
}: ModelRoleStatusProps): React.JSX.Element {
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
      <dl className={styles.details}>
        <div>
          <dt>API 地址</dt>
          <dd>{configuration?.endpoint ?? "等待服务端状态"}</dd>
        </div>
        <div>
          <dt>模型</dt>
          <dd>{configuration?.model ?? "未配置"}</dd>
        </div>
        <div>
          <dt>凭据</dt>
          <dd>{configuration?.keyConfigured ? "已配置" : "未配置"}</dd>
        </div>
      </dl>
    </section>
  );
}
