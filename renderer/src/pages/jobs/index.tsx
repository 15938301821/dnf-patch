import { useEffect, useState } from "react";
import { Button, Empty, Progress, Skeleton, Table, Tag, message } from "antd";
import { Download, RefreshCw } from "lucide-react";
import {
  downloadJobArtifact,
  getJobsList,
  type PatchTask,
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
};

function triggerDownload(blob: Blob, fileName: string): void {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();
  URL.revokeObjectURL(url);
}

export function JobsPage(): React.JSX.Element {
  const [jobs, setJobs] = useState<PatchTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [downloadingId, setDownloadingId] = useState("");

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

  const download = async (job: PatchTask): Promise<void> => {
    setDownloadingId(job.id);
    try {
      triggerDownload(
        await downloadJobArtifact(job.id),
        job.artifactName ?? `${job.id}.bin`,
      );
      void message.success("下载已开始");
    } catch (error) {
      void message.error(apiErrorMessage(error));
    } finally {
      setDownloadingId("");
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
        description="查看服务端制作进度并下载已完成产物；当前阶段由 mock API 返回模拟任务。"
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
          <span>可下载</span>
          <strong>{jobs.filter((job) => job.downloadUrl).length}</strong>
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
                    disabled={!job.downloadUrl}
                    icon={<Download size={16} />}
                    loading={downloadingId === job.id}
                    onClick={() => void download(job)}
                    type="link"
                  >
                    下载
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
    </div>
  );
}
