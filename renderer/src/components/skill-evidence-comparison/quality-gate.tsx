/**
 * @fileoverview 展示 Server 已 finalized 的三图质量摘要，不在浏览器自行判定通过或失败。
 *
 * 流程位置：SkillEvidenceComparison 完成源帧/结果图同版本、同值检查后渲染本组件；本组件
 * 调用 quality-evidence 将 schema 1 历史参考 RGB、schema 2/3 历史 V5 四/六指标或 schema 4
 * 当前 V5 八指标转换为只读界面。输入来自 Props，输出为审计摘要，无请求、状态写入或其他
 * 副作用。安全边界：门槛文本是 Server 规则说明，不能替代 Worker 的 finalized 判定。
 */
import type { PatchTaskSkillPreview } from "../../api/index.js";
import styles from "./index.module.scss";
import { createQualityEvidenceModel } from "./quality-evidence.js";

/**
 * 展示一份已经完成双侧一致性检查的版本化质量摘要。
 *
 * @param props quality 来自当前 attempt 的公开预览 DTO；缺失时只显示历史降级说明。
 * @returns V1 三项、V2 四项、V3 六项或 V4 八项 finalized 指标，不产生客户端通过结论。
 */
export function QualityGate({
  quality,
}: {
  quality: PatchTaskSkillPreview["referenceTransferQuality"];
}): React.JSX.Element {
  if (!quality) {
    return (
      <div className={styles["quality-legacy"]}>
        旧版证据未提供 finalized 质量摘要
      </div>
    );
  }

  const model = createQualityEvidenceModel(quality);
  return (
    <section
      aria-label={model.ariaLabel}
      className={styles.quality}
      data-schema-version={model.schemaVersion}
    >
      {model.items.map((item) => (
        <div key={item.label}>
          <span>{item.label}</span>
          <strong>{item.value}</strong>
          <small>{item.threshold}</small>
        </div>
      ))}
      <p>{model.summary}</p>
    </section>
  );
}
