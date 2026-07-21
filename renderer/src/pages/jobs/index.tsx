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

export function JobsPage(): React.JSX.Element {
  const [jobs, setJobs] = useState<PatchTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingArtifactId, setLoadingArtifactId] = useState("");
  const [artifact, setArtifact] = useState<PatchTaskArtifact>();

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
                render: (value: string) =>
                  new Date(value).toLocaleString("zh-CN"),
              },
              {
                title: "产物",
                key: "artifact",
                align: "right",
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
