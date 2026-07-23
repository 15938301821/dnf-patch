/**
 * @fileoverview 把服务端职业/风格发布状态渲染为统一 Ant Design 标签。
 *
 * 列表、编辑器与预览组件传入状态，本组件只做确定性展示映射，不发请求也不改变审核阶段。
 */
import { Tag } from "antd";
import type { PublishStatus as Status } from "../../server/contracts.js";

/** 后端稳定发布状态对应的颜色和中文标签。 */
const statusView: Record<Status, { color: string; label: string }> = {
  private: { color: "default", label: "私有" },
  pending: { color: "processing", label: "审核中" },
  published: { color: "success", label: "已发布" },
  rejected: { color: "error", label: "已退回" },
};

/** 发布状态展示组件的只读输入。 */
interface PublishStatusProps {
  status: Status;
}

/**
 * 渲染一个服务端发布状态标签。
 *
 * @param props 后端 DTO 中的稳定状态值。
 * @returns 对应颜色和文案的标签，不代表客户端执行了审核。
 */
export function PublishStatus({
  status,
}: PublishStatusProps): React.JSX.Element {
  const view = statusView[status];
  return <Tag color={view.color}>{view.label}</Tag>;
}
