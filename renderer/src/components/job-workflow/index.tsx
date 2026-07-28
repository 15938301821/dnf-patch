/**
 * @fileoverview 展示任务详情的当前状态、总进度、四阶段工作流和关键时间/产物摘要。
 *
 * 详情页传入服务端 ViewModel 与后台刷新标记；组件只格式化和展示，不发请求、不启动轮询，
 * 也不根据进度百分比推断阶段。unknown 继续显示为证据不足，Artifact 可用只表示存在已验证引用，
 * 不表示文件已下载、部署或兼容当前客户端。
 */
import { Progress, Tag } from "antd";
import { Ban, Check, Circle, CircleHelp, LoaderCircle, X } from "lucide-react";
import type {
  PatchTaskDetail,
  PatchTaskStepStatus,
} from "../../server/contracts.js";
import {
  formatJobDateTime,
  patchTaskStatusView,
  patchTaskStepStatusView,
  workflowStageLabel,
} from "../../config/job-detail-view.js";
import styles from "./index.module.scss";

/** 任务工作流总览的受控输入。 */
interface JobWorkflowProps {
  detail: PatchTaskDetail;
  refreshing: boolean;
}

/**
 * 渲染任务当前工作流与审计摘要。
 * @param props 当前详情响应和后台刷新状态；refreshing 只影响可见状态点，不改变领域数据。
 * @returns 四阶段进度带和四项关键指标；无网络、定时器或路由副作用。
 */
export function JobWorkflow({
  detail,
  refreshing,
}: JobWorkflowProps): React.JSX.Element {
  const status = patchTaskStatusView[detail.status];
  return (
    <section aria-labelledby="workflow-heading" className={styles.section}>
      <header className={styles.header}>
        <div>
          <span className={styles.eyebrow}>RUN OVERVIEW</span>
          <h2 id="workflow-heading">任务工作流</h2>
        </div>
        <div className={styles.status}>
          <span className={refreshing ? styles.refreshing : ""}>
            {refreshing ? "正在同步" : "状态已同步"}
          </span>
          <Tag color={status.color}>{status.label}</Tag>
        </div>
      </header>

      <div className={styles.progress}>
        <div className={styles["progress-copy"]}>
          <span>整体进度</span>
          <strong>{detail.progress}%</strong>
        </div>
        <Progress
          aria-label={`任务整体进度 ${String(detail.progress)}%`}
          percent={detail.progress}
          showInfo={false}
          {...(detail.status === "failed"
            ? { status: "exception" as const }
            : {})}
          strokeColor={detail.status === "blocked" ? "#b8662e" : "#176448"}
        />
      </div>

      <ol className={styles.workflow}>
        {detail.workflow.map((stage) => (
          <li
            className={styles[`workflow-${stage.status}`] ?? ""}
            key={stage.key}
          >
            <span className={styles.node}>
              <WorkflowIcon status={stage.status} />
            </span>
            <span>
              <strong>{workflowStageLabel[stage.key]}</strong>
              <small>{patchTaskStepStatusView[stage.status].label}</small>
            </span>
          </li>
        ))}
      </ol>

      <dl className={styles.facts}>
        <div>
          <dt>技能通过</dt>
          <dd>
            {detail.passedSkills} / {detail.totalSkills}
          </dd>
        </div>
        <div>
          <dt>封包状态</dt>
          <dd>{packageStatusLabel[detail.packageStatus]}</dd>
        </div>
        <div>
          <dt>最近更新</dt>
          <dd>{formatJobDateTime(detail.updatedAt)}</dd>
        </div>
        <div>
          <dt>产物引用</dt>
          <dd>
            {detail.artifactAvailable
              ? (detail.artifactName ?? "已就绪")
              : "尚未生成"}
          </dd>
        </div>
      </dl>
    </section>
  );
}

/**
 * 为工作流阶段选择带文本冗余的状态图标，避免只用颜色表达。
 * @param status 服务端映射的阶段状态。
 * @returns 固定尺寸图标；不会推断或修改阶段。
 */
function WorkflowIcon({
  status,
}: {
  status: PatchTaskStepStatus;
}): React.JSX.Element {
  if (status === "passed") return <Check aria-hidden size={15} />;
  if (status === "running") {
    return <LoaderCircle aria-hidden className={styles.spin} size={15} />;
  }
  if (status === "failed") return <X aria-hidden size={15} />;
  if (status === "blocked") return <Ban aria-hidden size={15} />;
  if (status === "unknown") return <CircleHelp aria-hidden size={15} />;
  return <Circle aria-hidden size={12} />;
}

/** Package V3 的服务端状态标签，不用于推断最终 Artifact 可用性。 */
const packageStatusLabel: Record<PatchTaskDetail["packageStatus"], string> = {
  queued: "等待封包",
  building: "封包验证中",
  passed: "验证通过",
  failed: "验证失败",
  blocked: "已阻断",
};
