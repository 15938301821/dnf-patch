/**
 * @fileoverview 展示 `/jobs` 制作任务列表并按需读取已验证产物元数据。
 *
 * 受保护路由渲染本页，页面通过任务 API 加载摘要，用户点击后再请求单个产物引用；输出是
 * 表格、进度与元数据弹窗。副作用只有受认证请求和消息提示，不下载字节、不访问对象存储，
 * 也不把 Mock 返回描述为真实 Worker 或存储集成已通过。
 */
import { useEffect, useState } from "react";
import {
  Button,
  Descriptions,
  Empty,
  Modal,
  Progress,
  Skeleton,
  Table,
  Tag,
  message,
} from "antd";
import { FileSearch, RefreshCw } from "lucide-react";
import {
  getJobArtifactMetadata,
  getJobsList,
  type PatchTask,
  type PatchTaskArtifact,
  type PatchTaskStatus,
} from "../../api/index.js";
import { PageHeading } from "../../components/page-heading/index.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import styles from "./index.module.scss";

const statusView: Record<PatchTaskStatus, { color: string; label: string }> = {
  queued: { color: "default", label: "排队中" },
  running: { color: "processing", label: "制作中" },
  passed: { color: "success", label: "已完成" },
  failed: { color: "error", label: "失败" },
  blocked: { color: "warning", label: "已阻断" },
};

/**
 * 渲染任务摘要、手动刷新和产物元数据检查界面。
 *
 * @returns 当前加载、空列表、任务表格与可选元数据弹窗；请求错误保留在页面消息层。
 */
export function JobsPage(): React.JSX.Element {
  const [jobs, setJobs] = useState<PatchTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingArtifactId, setLoadingArtifactId] = useState("");
  const [artifact, setArtifact] = useState<PatchTaskArtifact>();

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
      void message.error(apiErrorMessage(error));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  /**
   * 为列表中的一个任务读取产物元数据，不获取实际文件。
   *
   * @param job 当前表格行的任务 ViewModel，必须由任务列表 API 生产。
   * @returns 元数据写入或错误提示完成后结算。
   */
  const inspectArtifact = async (job: PatchTask): Promise<void> => {
    setLoadingArtifactId(job.id);
    try {
      setArtifact(await getJobArtifactMetadata(job.id));
    } catch (error) {
      void message.error(apiErrorMessage(error));
    } finally {
      setLoadingArtifactId("");
    }
  };

  return (
    <div className={styles.page}>
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
                  <Tag color={statusView[status].color}>
                    {statusView[status].label}
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
                    onClick={() => void inspectArtifact(job)}
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
            rowKey="id"
            scroll={{ x: 760 }}
          />
        )}
      </section>
      <Modal
        footer={null}
        onCancel={() => setArtifact(undefined)}
        open={artifact !== undefined}
        title="产物元数据"
      >
        {artifact ? (
          <Descriptions column={1} size="small">
            <Descriptions.Item label="名称">
              {artifact.artifactName}
            </Descriptions.Item>
            <Descriptions.Item label="媒体类型">
              {artifact.mediaType}
            </Descriptions.Item>
            <Descriptions.Item label="字节数">
              {artifact.byteLength.toLocaleString("zh-CN")}
            </Descriptions.Item>
            <Descriptions.Item label="SHA-256">
              <span className={styles.hash}>{artifact.sha256}</span>
            </Descriptions.Item>
            <Descriptions.Item label="存储引用">
              <span className={styles.hash}>{artifact.storageKey}</span>
            </Descriptions.Item>
          </Descriptions>
        ) : null}
      </Modal>
    </div>
  );
}
