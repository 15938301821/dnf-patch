/**
 * @fileoverview `/jobs/:jobId` 制作任务详情页的请求编排与三图证据审查入口。
 *
 * 受保护路由从 URL 读取任务 ID，useJobDetail 负责可取消详情读取和运行态 3 秒轮询；页面把
 * 服务端 ViewModel 分发给工作流、逐技能和吞吐组件。页面只记录当前审查技能；三项授权、PNG
 * 复核、竞态防护和 Blob URL 清理由 SkillEvidenceComparison 独占。页面副作用仅包括导航和轮询
 * Hook，不保存 Access Token、对象 key、短期 URL 或图片字节，也不声明兼容、部署或全技能覆盖。
 */
import { useState } from "react";
import { Alert, Button, Skeleton, Tag, Tooltip } from "antd";
import { ArrowLeft, RefreshCw } from "lucide-react";
import { useNavigate, useParams } from "react-router-dom";
import { JobSkillProgress } from "../../components/job-skill-progress/index.js";
import { JobThroughput } from "../../components/job-throughput/index.js";
import { JobWorkflow } from "../../components/job-workflow/index.js";
import { PageHeading } from "../../components/page-heading/index.js";
import { SkillEvidenceComparison } from "../../components/skill-evidence-comparison/index.js";
import {
  formatJobDateTime,
  patchTaskStatusView,
  workflowStageLabel,
} from "../../config/job-detail-view.js";
import { useJobDetail } from "../../hooks/use-job-detail.js";
import styles from "./index.module.scss";

/**
 * 渲染单个制作任务的实时观察页。
 *
 * @returns 首次加载骨架、不可用错误或完整任务详情；所有状态均保留返回任务列表的键盘入口。
 */
export function JobDetailPage(): React.JSX.Element {
  const { jobId } = useParams<{ jobId: string }>();
  const navigate = useNavigate();
  const { detail, loading, refreshing, errorMessage, refresh } =
    useJobDetail(jobId);
  const [comparisonSkillId, setComparisonSkillId] = useState("");

  const backButton = (
    <Tooltip title="返回制作任务">
      <Button
        aria-label="返回制作任务"
        icon={<ArrowLeft size={17} />}
        onClick={() => void navigate("/jobs")}
        type="text"
      />
    </Tooltip>
  );

  if (loading && !detail) {
    return (
      <div className={styles.page}>
        <PageHeading
          action={backButton}
          description="正在读取任务审计状态"
          title="制作任务详情"
        />
        <div className={styles.skeleton}>
          <Skeleton active paragraph={{ rows: 14 }} />
        </div>
      </div>
    );
  }

  if (!detail) {
    return (
      <div className={styles.page}>
        <PageHeading
          action={backButton}
          description="当前地址没有可展示的任务记录"
          title="制作任务详情"
        />
        <Alert
          action={
            <Button onClick={refresh} size="small">
              重试
            </Button>
          }
          description={errorMessage || "制作任务不存在或当前用户无权查看。"}
          showIcon
          title="无法读取任务"
          type="error"
        />
      </div>
    );
  }

  const status = patchTaskStatusView[detail.status];
  return (
    <div className={styles.page}>
      <PageHeading
        action={
          <div className={styles.commands}>
            {backButton}
            <Tooltip title="刷新任务详情">
              <Button
                aria-label="刷新任务详情"
                icon={<RefreshCw size={16} />}
                loading={refreshing}
                onClick={refresh}
                type="text"
              />
            </Tooltip>
          </div>
        }
        description={`创建于 ${formatJobDateTime(detail.createdAt)} · 任务 ${detail.id}`}
        title={`${detail.professionName} · ${detail.styleName}`}
      />

      <div className={styles["title-status"]}>
        <Tag color={status.color}>{status.label}</Tag>
        <span>当前阶段：{workflowStageLabel[detail.currentStage]}</span>
      </div>

      {errorMessage ? (
        <Alert
          action={
            <Button onClick={refresh} size="small">
              重试
            </Button>
          }
          className={styles.alert ?? ""}
          description={errorMessage}
          showIcon
          title="本次同步失败，页面保留上一次任务状态。"
          type="warning"
        />
      ) : null}

      <div className={styles.content}>
        <JobWorkflow detail={detail} refreshing={refreshing} />
        <JobSkillProgress
          onCompareEvidence={(skill) => setComparisonSkillId(skill.skillId)}
          skills={detail.skills}
        />
        <JobThroughput throughput={detail.modelThroughput} />
      </div>

      <SkillEvidenceComparison
        jobId={detail.id}
        onClose={() => setComparisonSkillId("")}
        open={comparisonSkillId !== ""}
        skill={detail.skills.find(
          (skill) => skill.skillId === comparisonSkillId,
        )}
      />
    </div>
  );
}
