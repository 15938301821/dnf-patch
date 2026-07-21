import { Tag } from "antd";
import type { PublishStatus as Status } from "../../api/contracts.js";

const statusView: Record<Status, { color: string; label: string }> = {
  private: { color: "default", label: "私有" },
  pending: { color: "processing", label: "审核中" },
  published: { color: "success", label: "已发布" },
  rejected: { color: "error", label: "已退回" },
};

interface PublishStatusProps {
  status: Status;
}

export function PublishStatus({
  status,
}: PublishStatusProps): React.JSX.Element {
  const view = statusView[status];
  return <Tag color={view.color}>{view.label}</Tag>;
}
