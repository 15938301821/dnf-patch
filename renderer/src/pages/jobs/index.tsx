/**
 * @fileoverview 展示并自动轮询 `/jobs` 制作任务列表，支持终态任务软归档，并按需读取、下载
 * Package V3 三项已验证产物。
 *
 * 受保护路由渲染本页，useJobsList 串行读取摘要并拥有定时器/取消清理；页面归档终态任务后触发
 * 同一刷新生命周期。用户点击后读取 candidate、manifest、validation 三项脱敏元数据；下载时按固定
 * 角色临时申请短期 URL，读取为 Blob 后交给浏览器原生下载。页面不接收对象 key、bucket 或长期凭据，
 * 不持久化短期 URL，也不把软归档描述为取消执行或物理删除证据。
 */
import { useEffect, useRef, useState } from "react";
import {
  Alert,
  Button,
  Empty,
  Modal,
  Popconfirm,
  Progress,
  Skeleton,
  Table,
  Tag,
  Tooltip,
  message,
} from "antd";
import { Download, FileSearch, RefreshCw, Trash2 } from "lucide-react";
import { useNavigate } from "react-router-dom";
import {
  archiveJob,
  downloadJobArtifact,
  getJobArtifacts,
  type PatchTask,
  type PatchTaskArtifact,
  type PatchTaskStatus,
} from "../../api/index.js";
import { PageHeading } from "../../components/page-heading/index.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import styles from "./index.module.scss";
import { patchTaskStatusView } from "../../config/job-detail-view.js";
import { useJobsList } from "../../hooks/use-jobs-list.js";

/**
 * 渲染任务摘要、手动刷新和产物元数据检查界面。
 *
 * @returns 当前加载、空列表、任务表格与可选元数据弹窗；请求错误保留在页面消息层。
 */
export function JobsPage(): React.JSX.Element {
  const navigate = useNavigate();
  const [messageApi, messageContextHolder] = message.useMessage();
  const { jobs, loading, refreshing, errorMessage, refresh } = useJobsList();
  const [loadingArtifactId, setLoadingArtifactId] = useState("");
  const [archivingId, setArchivingId] = useState("");
  const [artifactJobId, setArtifactJobId] = useState("");
  const [artifacts, setArtifacts] = useState<PatchTaskArtifact[]>([]);
  const [downloadingRole, setDownloadingRole] = useState<
    PatchTaskArtifact["role"] | ""
  >("");
  const artifactRequestRef = useRef<AbortController | null>(null);
  const downloadRequestRef = useRef<AbortController | null>(null);

  useEffect(() => {
    if (errorMessage) void messageApi.error(errorMessage);
  }, [errorMessage, messageApi]);

  useEffect(
    () => () => {
      artifactRequestRef.current?.abort();
      downloadRequestRef.current?.abort();
    },
    [],
  );

  /**
   * 把一个服务端已确认终态的任务从默认列表软归档。
   *
   * @param job 当前表格行的任务 ViewModel；queued/running 在控件层禁用，服务端仍会再次拒绝竞态状态。
   * @returns 204 后显示成功消息并重启唯一列表读取生命周期；失败时保留当前行和详情证据。
   */
  const archive = async (job: PatchTask): Promise<void> => {
    setArchivingId(job.id);
    try {
      await archiveJob(job.id);
      void messageApi.success("任务已从列表移除");
      if (artifactJobId === job.id) closeArtifacts();
      refresh();
    } catch (error) {
      void messageApi.error(apiErrorMessage(error));
    } finally {
      setArchivingId("");
    }
  };

  /**
   * 为列表中的一个任务读取三项固定角色元数据，不获取实际文件。
   *
   * @param job 当前表格行的任务 ViewModel，必须由任务列表 API 生产。
   * @returns 元数据写入或错误提示完成后结算。
   */
  const inspectArtifact = async (job: PatchTask): Promise<void> => {
    artifactRequestRef.current?.abort();
    const controller = new AbortController();
    artifactRequestRef.current = controller;
    setLoadingArtifactId(job.id);
    try {
      const result = await getJobArtifacts(job.id, controller.signal);
      setArtifactJobId(job.id);
      setArtifacts(result);
    } catch (error) {
      if (!controller.signal.aborted) {
        void messageApi.error(apiErrorMessage(error));
      }
    } finally {
      if (artifactRequestRef.current === controller) {
        artifactRequestRef.current = null;
        setLoadingArtifactId("");
      }
    }
  };

  /**
   * 为一个固定角色申请短期授权并立即交给浏览器下载。
   *
   * @param artifact 当前弹窗中由服务端返回的角色元数据；只使用 role，绝不把 Artifact ID 当下载权限。
   * @returns 授权读取、长度检查与临时 URL 清理安排完成后结算；失败时不导航、不保存 URL，也不伪造成功。
   */
  const downloadArtifact = async (
    artifact: PatchTaskArtifact,
  ): Promise<void> => {
    if (!artifactJobId) return;
    downloadRequestRef.current?.abort();
    const controller = new AbortController();
    downloadRequestRef.current = controller;
    setDownloadingRole(artifact.role);
    try {
      const { artifact: downloadedArtifact, blob } = await downloadJobArtifact(
        artifactJobId,
        artifact.role,
        controller.signal,
      );
      const objectUrl = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = objectUrl;
      anchor.download = downloadedArtifact.artifactName;
      anchor.rel = "noopener";
      document.body.append(anchor);
      anchor.click();
      window.setTimeout(() => {
        anchor.remove();
        URL.revokeObjectURL(objectUrl);
      }, 0);
    } catch (error) {
      if (!controller.signal.aborted) {
        void messageApi.error(apiErrorMessage(error));
      }
    } finally {
      if (downloadRequestRef.current === controller) {
        downloadRequestRef.current = null;
        setDownloadingRole("");
      }
    }
  };

  /** 关闭弹窗并中止其元数据/下载请求；短期授权 URL 从未写入 React 状态。 */
  const closeArtifacts = (): void => {
    artifactRequestRef.current?.abort();
    artifactRequestRef.current = null;
    downloadRequestRef.current?.abort();
    downloadRequestRef.current = null;
    setLoadingArtifactId("");
    setDownloadingRole("");
    setArtifactJobId("");
    setArtifacts([]);
  };

  return (
    <div className={styles.page}>
      {messageContextHolder}
      <PageHeading
        action={
          <Button
            icon={<RefreshCw size={16} />}
            loading={refreshing}
            onClick={refresh}
          >
            刷新
          </Button>
        }
        description="查看服务端制作进度与已验证产物引用；实际字节由受控存储通道提供。"
        title="制作任务"
      />

      <section className={styles.summary}>
        <div>
          <span>全部任务</span>
          <strong>{jobs.length}</strong>
        </div>
        <div>
          <span>进行中</span>
          <strong>
            {jobs.filter((job) => job.status === "running").length}
          </strong>
        </div>
        <div>
          <span>有产物记录</span>
          <strong>{jobs.filter((job) => job.artifactAvailable).length}</strong>
        </div>
      </section>

      <section className={styles.table}>
        {errorMessage && jobs.length === 0 ? (
          <Alert
            className={styles.listError ?? ""}
            description={errorMessage}
            showIcon
            title="任务列表暂时不可用"
            type="error"
          />
        ) : null}
        {loading ? (
          <Skeleton active paragraph={{ rows: 8 }} />
        ) : (
          <Table<PatchTask>
            columns={[
              {
                title: "职业 / 风格",
                key: "subject",
                /** 把任务主题字段组合为主次两行，不改变服务端数据。 */
                render: (_, job) => (
                  <div className={styles.subject}>
                    <strong>{job.professionName}</strong>
                    <span>{job.styleName}</span>
                  </div>
                ),
              },
              {
                title: "状态",
                dataIndex: "status",
                key: "status",
                /** 按稳定状态映射标签颜色和文案。 */
                render: (status: PatchTaskStatus) => (
                  <Tag color={patchTaskStatusView[status].color}>
                    {patchTaskStatusView[status].label}
                  </Tag>
                ),
              },
              {
                title: "进度",
                dataIndex: "progress",
                key: "progress",
                /** 把服务端百分比投影为只读进度条。 */
                render: (progress: number) => (
                  <Progress
                    percent={progress}
                    size="small"
                    status={progress === 100 ? "success" : "active"}
                  />
                ),
              },
              {
                title: "创建时间",
                dataIndex: "createdAt",
                key: "createdAt",
                /** 仅在展示时把 ISO 时间格式化为中文本地时间。 */
                render: (value: string) =>
                  new Date(value).toLocaleString("zh-CN"),
              },
              {
                title: "产物",
                key: "artifact",
                align: "right",
                /** 根据产物可用标记渲染按需查询命令，不直接下载字节。 */
                render: (_, job) => (
                  <Button
                    disabled={!job.artifactAvailable}
                    icon={<FileSearch size={16} />}
                    loading={loadingArtifactId === job.id}
                    onClick={(event) => {
                      // 行本身进入详情，固定角色元数据命令必须阻止事件冒泡以保留用户意图。
                      event.stopPropagation();
                      void inspectArtifact(job);
                    }}
                    type="link"
                  >
                    查看元数据
                  </Button>
                ),
              },
              {
                title: "移除",
                key: "archive",
                align: "right",
                width: 64,
                /** 活动任务仅展示禁用命令；终态任务必须二次确认，服务端仍负责最终竞态判定。 */
                render: (_, job) => {
                  const active = isPatchTaskActive(job);
                  const button = (
                    <Button
                      aria-label={`从列表移除${job.professionName}${job.styleName}任务`}
                      danger
                      disabled={active}
                      icon={<Trash2 size={16} />}
                      loading={archivingId === job.id}
                      onClick={(event) => event.stopPropagation()}
                      title={active ? undefined : "从列表移除"}
                      type="text"
                    />
                  );
                  if (active) {
                    return <Tooltip title="任务完成后可移除">{button}</Tooltip>;
                  }
                  return (
                    <Popconfirm
                      cancelText="取消"
                      description="执行记录、产物与审计证据仍会保留。"
                      okButtonProps={{ danger: true }}
                      okText="移除"
                      onConfirm={() => archive(job)}
                      title="从任务列表移除？"
                    >
                      {button}
                    </Popconfirm>
                  );
                },
              },
            ]}
            dataSource={jobs}
            locale={{ emptyText: <Empty description="暂无制作任务" /> }}
            pagination={false}
            onRow={(job) => ({
              "aria-label": `查看${job.professionName}${job.styleName}任务详情`,
              className: styles["clickable-row"] ?? "",
              onClick: (event) => {
                // Popconfirm 通过 Portal 渲染，但 React 事件仍可能冒泡到行；交互控件永远不能触发详情导航。
                if (isInteractiveEventTarget(event.target)) return;
                void navigate(`/jobs/${job.id}`);
              },
              onKeyDown: (event) => {
                if (isInteractiveEventTarget(event.target)) return;
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  void navigate(`/jobs/${job.id}`);
                }
              },
              role: "link",
              tabIndex: 0,
            })}
            rowKey="id"
            scroll={{ x: 840 }}
          />
        )}
      </section>
      <Modal
        footer={null}
        onCancel={closeArtifacts}
        open={artifactJobId !== ""}
        title="已验证产物"
        width={920}
      >
        <Table<PatchTaskArtifact>
          columns={[
            {
              title: "角色",
              dataIndex: "role",
              key: "role",
              render: (role: PatchTaskArtifact["role"]) => (
                <Tag>{artifactRoleLabel[role]}</Tag>
              ),
            },
            {
              title: "文件",
              key: "file",
              render: (_, artifact) => (
                <div className={styles.artifactFile}>
                  <strong>{artifact.artifactName}</strong>
                  <span>
                    {artifact.mediaType} ·{" "}
                    {artifact.byteLength.toLocaleString("zh-CN")} 字节
                  </span>
                </div>
              ),
            },
            {
              title: "SHA-256",
              dataIndex: "sha256",
              key: "sha256",
              render: (sha256: string) => (
                <span className={styles.hash}>{sha256}</span>
              ),
            },
            {
              title: "下载",
              key: "download",
              align: "right",
              render: (_, artifact) => (
                <Button
                  aria-label={`下载${artifactRoleLabel[artifact.role]}`}
                  icon={<Download size={16} />}
                  loading={downloadingRole === artifact.role}
                  onClick={() => void downloadArtifact(artifact)}
                  title={`下载${artifactRoleLabel[artifact.role]}`}
                  type="text"
                />
              ),
            },
          ]}
          dataSource={artifacts}
          pagination={false}
          rowKey="artifactId"
          scroll={{ x: 800 }}
          size="small"
        />
      </Modal>
    </div>
  );
}

/** 固定角色的界面标签；不根据文件名推断角色或验证结论。 */
const artifactRoleLabel: Record<PatchTaskArtifact["role"], string> = {
  candidate: "候选 NPK",
  manifest: "构建清单",
  validation: "独立验证",
};

/** 活动态只能由服务端状态判断；客户端不根据进度百分比猜测是否允许归档。 */
function isPatchTaskActive(job: PatchTask): boolean {
  return job.status === "queued" || job.status === "running";
}

/**
 * 判断一个冒泡事件是否来自独立交互控件。
 *
 * @param target React 事件的原始 DOM target；Portal 中的确认按钮也会保留该 target。
 * @returns 按钮、链接或表单控件应自行处理用户意图时为 true，表格行不得导航。
 */
function isInteractiveEventTarget(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    target.closest("button, a, input, select, textarea, [role='button']") !==
      null
  );
}
