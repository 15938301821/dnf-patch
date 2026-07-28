/**
 * @fileoverview 展示 `/jobs` 制作任务列表，并按需读取、下载 Package V3 三项已验证产物。
 *
 * 受保护路由渲染本页，页面通过任务 API 加载摘要，用户点击后读取 candidate、manifest、validation
 * 三项脱敏元数据；下载时按固定角色临时申请短期 URL，读取为 Blob 后交给浏览器原生下载。页面不接收
 * 对象 key、bucket 或长期凭据，不持久化短期 URL，也不把 Mock 返回描述为真实 Worker 或对象存储已通过。
 */
import { useEffect, useState } from "react";
import {
  Button,
  Empty,
  Modal,
  Progress,
  Skeleton,
  Table,
  Tag,
  message,
} from "antd";
import { Download, FileSearch, RefreshCw } from "lucide-react";
import { useNavigate } from "react-router-dom";
import {
  downloadJobArtifact,
  getJobArtifacts,
  getJobsList,
  type PatchTask,
  type PatchTaskArtifact,
  type PatchTaskStatus,
} from "../../api/index.js";
import { PageHeading } from "../../components/page-heading/index.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import styles from "./index.module.scss";
import { patchTaskStatusView } from "../../config/job-detail-view.js";

/**
 * 渲染任务摘要、手动刷新和产物元数据检查界面。
 *
 * @returns 当前加载、空列表、任务表格与可选元数据弹窗；请求错误保留在页面消息层。
 */
export function JobsPage(): React.JSX.Element {
  const navigate = useNavigate();
  const [messageApi, messageContextHolder] = message.useMessage();
  const [jobs, setJobs] = useState<PatchTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingArtifactId, setLoadingArtifactId] = useState("");
  const [artifactJobId, setArtifactJobId] = useState("");
  const [artifacts, setArtifacts] = useState<PatchTaskArtifact[]>([]);
  const [downloadingRole, setDownloadingRole] = useState<
    PatchTaskArtifact["role"] | ""
  >("");

  /**
   * 重新读取当前用户任务摘要并维护页面加载状态。
   *
   * @returns 请求与状态清理完成后结算；失败时不伪造任务。
   */
  const load = async (): Promise<void> => {
    setLoading(true);
    try {
      setJobs(await getJobsList());
    } catch (error) {
      void messageApi.error(apiErrorMessage(error));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  /**
   * 为列表中的一个任务读取三项固定角色元数据，不获取实际文件。
   *
   * @param job 当前表格行的任务 ViewModel，必须由任务列表 API 生产。
   * @returns 元数据写入或错误提示完成后结算。
   */
  const inspectArtifact = async (job: PatchTask): Promise<void> => {
    setLoadingArtifactId(job.id);
    try {
      const result = await getJobArtifacts(job.id);
      setArtifactJobId(job.id);
      setArtifacts(result);
    } catch (error) {
      void messageApi.error(apiErrorMessage(error));
    } finally {
      setLoadingArtifactId("");
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
    setDownloadingRole(artifact.role);
    try {
      const { artifact: downloadedArtifact, blob } = await downloadJobArtifact(
        artifactJobId,
        artifact.role,
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
      void messageApi.error(apiErrorMessage(error));
    } finally {
      setDownloadingRole("");
    }
  };

  /** 清理当前弹窗数据；短期授权 URL 从未写入 React 状态，无需额外销毁。 */
  const closeArtifacts = (): void => {
    setArtifactJobId("");
    setArtifacts([]);
  };

  return (
    <div className={styles.page}>
      {messageContextHolder}
      <PageHeading
        action={
          <Button icon={<RefreshCw size={16} />} onClick={() => void load()}>
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
            ]}
            dataSource={jobs}
            locale={{ emptyText: <Empty description="暂无制作任务" /> }}
            pagination={false}
            onRow={(job) => ({
              "aria-label": `查看${job.professionName}${job.styleName}任务详情`,
              className: styles["clickable-row"] ?? "",
              onClick: () => void navigate(`/jobs/${job.id}`),
              onKeyDown: (event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  void navigate(`/jobs/${job.id}`);
                }
              },
              role: "link",
              tabIndex: 0,
            })}
            rowKey="id"
            scroll={{ x: 760 }}
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
