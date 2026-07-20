import { CircleCheck, CircleDashed, CircleX } from "lucide-react";

interface JobCardProps {
  title: string;
  stage: string;
  status: "pending" | "running" | "completed" | "failed";
}

const labels: Record<JobCardProps["status"], string> = {
  pending: "等待",
  running: "进行中",
  completed: "完成",
  failed: "失败",
};

/** 可扫描的任务状态行，用于 Monitor 页面汇总本地 Run。 */
export function JobCard({
  title,
  stage,
  status,
}: JobCardProps): React.JSX.Element {
  const Icon =
    status === "completed"
      ? CircleCheck
      : status === "failed"
        ? CircleX
        : CircleDashed;
  return (
    <article className={`job-card job-${status}`}>
      <Icon aria-hidden="true" size={18} />
      <div>
        <strong>{title}</strong>
        <span>{stage}</span>
      </div>
      <small>{labels[status]}</small>
    </article>
  );
}
