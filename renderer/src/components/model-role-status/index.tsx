/**
 * @fileoverview 只读展示一个固定模型角色的脱敏配置与职责标签。
 *
 * 父页面提供服务端 ViewModel，本组件不提供写入入口、不读取或恢复 API Key，也不直接调用
 * 模型 Provider。`keyConfigured` 只表示服务端已有密钥，不代表浏览器持有密钥明文。
 */
import { Tag } from "antd";
import type { ModelRoleConfiguration } from "../../server/contracts.js";
import styles from "./index.module.scss";

/** 固定模型角色只读展示所需的脱敏输入。 */
interface ModelRoleStatusProps {
  configuration: ModelRoleConfiguration | undefined;
  description: string;
  icon: React.ReactNode;
  role: "orchestrator" | "referenceGenerator" | "spriteProcessor";
  sequence: string;
  tags: readonly string[];
  title: string;
}

/**
 * 展示服务端托管的固定模型角色，不提供浏览器写配置入口。
 *
 * @param props 脱敏配置、展示职责与固定角色标识。
 * @returns endpoint、模型 ID 和密钥存在状态的只读区块。
 */
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
