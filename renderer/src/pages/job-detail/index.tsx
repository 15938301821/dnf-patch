/**
 * @fileoverview `/jobs/:jobId` 制作任务详情页的请求编排与参考图预览生命周期入口。
 *
 * 受保护路由从 URL 读取任务 ID，useJobDetail 负责可取消详情读取和运行态 3 秒轮询；页面把
 * 服务端 ViewModel 分发给工作流、逐技能和吞吐展示组件。用户选择参考图时，页面通过类型化 API
 * 申请固定技能授权并创建临时 Object URL。副作用包括导航、轮询 Hook、参考图请求与 Blob URL；
 * 离开路由、关闭预览或发起新预览时必须中止旧请求并释放旧 URL。Access Token、对象 key 和服务端
 * 短期下载 URL 均不进入组件状态，参考图也不代表可直接用于游戏 runtime 或最终补丁。
 */
import { useCallback, useEffect, useRef, useState } from "react";
import { Alert, Button, Modal, Skeleton, Tag, Tooltip, message } from "antd";
import { ArrowLeft, RefreshCw } from "lucide-react";
import { useNavigate, useParams } from "react-router-dom";
import {
  downloadJobReferenceImage,
  type PatchTaskReferenceImage,
  type PatchTaskSkillProgress,
} from "../../api/index.js";
import { JobSkillProgress } from "../../components/job-skill-progress/index.js";
import { JobThroughput } from "../../components/job-throughput/index.js";
import { JobWorkflow } from "../../components/job-workflow/index.js";
import { PageHeading } from "../../components/page-heading/index.js";
import {
  formatJobDateTime,
  patchTaskStatusView,
} from "../../config/job-detail-view.js";
import { useJobDetail } from "../../hooks/use-job-detail.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import styles from "./index.module.scss";

/** 页面状态只保留本地 Object URL 与脱敏元数据，不保存服务端短期授权 URL。 */
interface ReferencePreview {
  skillName: string;
  image: PatchTaskReferenceImage;
  objectUrl: string;
}

/**
 * 渲染单个制作任务的实时观察页。
 *
 * @returns 首次加载骨架、不可用错误或完整任务详情；所有状态均保留返回任务列表的键盘入口。
 */
export function JobDetailPage(): React.JSX.Element {
  const { jobId } = useParams<{ jobId: string }>();
  const navigate = useNavigate();
  const [messageApi, messageContextHolder] = message.useMessage();
  const { detail, loading, refreshing, errorMessage, refresh } =
    useJobDetail(jobId);
  const [previewingSkillId, setPreviewingSkillId] = useState("");
  const [referencePreview, setReferencePreview] = useState<
    ReferencePreview | undefined
  >();
  const previewControllerRef = useRef<AbortController | undefined>(undefined);
  const previewObjectUrlRef = useRef("");

  /**
   * 释放当前参考图预览及尚未完成的授权/下载请求。
   *
   * @returns 无返回值；调用后浏览器不再持有该 Blob URL，关闭弹窗不会保留短期图片字节引用。
   */
  const closeReferencePreview = useCallback((): void => {
    previewControllerRef.current?.abort();
    previewControllerRef.current = undefined;
    setPreviewingSkillId("");
    setReferencePreview(undefined);
    if (previewObjectUrlRef.current) {
      URL.revokeObjectURL(previewObjectUrlRef.current);
      previewObjectUrlRef.current = "";
    }
  }, []);

  useEffect(
    () => () => {
      // 路由卸载是预览生命周期的最终所有者，必须同时撤销网络写入资格和 Blob 引用。
      previewControllerRef.current?.abort();
      previewControllerRef.current = undefined;
      if (previewObjectUrlRef.current) {
        URL.revokeObjectURL(previewObjectUrlRef.current);
        previewObjectUrlRef.current = "";
      }
    },
    [],
  );

  /**
   * 为详情中标记可用的技能读取并展示当前 reference-image-v1 PNG。
   *
   * @param skill 用户点击的当前详情技能 ViewModel；只使用任务与技能 ID，不提交 Artifact ID。
   * @returns 授权、字节复核和 Object URL 状态更新完成后结算；失败或取消时不展示旧/未验证图片。
   */
  const previewReferenceImage = async (
    skill: PatchTaskSkillProgress,
  ): Promise<void> => {
    if (!jobId || !skill.referenceImageAvailable) return;
    // 第一步：新选择中止旧预览请求，但保留已显示图片直到新图片通过全部复核。
    previewControllerRef.current?.abort();
    const controller = new AbortController();
    previewControllerRef.current = controller;
    setPreviewingSkillId(skill.skillId);
    try {
      // 第二步：API 层完成媒体类型、长度和 PNG 签名复核，页面只接收可展示 Blob。
      const { image, blob } = await downloadJobReferenceImage(
        jobId,
        skill.skillId,
        controller.signal,
      );
      if (
        controller.signal.aborted ||
        previewControllerRef.current !== controller
      ) {
        return;
      }
      // 第三步：验证通过后再替换 Object URL，并立即释放上一张预览的浏览器资源。
      const objectUrl = URL.createObjectURL(blob);
      if (previewObjectUrlRef.current) {
        URL.revokeObjectURL(previewObjectUrlRef.current);
      }
      previewObjectUrlRef.current = objectUrl;
      setReferencePreview({ skillName: skill.displayName, image, objectUrl });
    } catch (error) {
      if (!controller.signal.aborted) {
        void messageApi.error(apiErrorMessage(error));
      }
    } finally {
      if (previewControllerRef.current === controller) {
        previewControllerRef.current = undefined;
        setPreviewingSkillId("");
      }
    }
  };

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
        {messageContextHolder}
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
        {messageContextHolder}
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
      {messageContextHolder}
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
        <span>当前阶段：{detail.currentStage}</span>
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
          onPreviewReference={(skill) => void previewReferenceImage(skill)}
          previewingSkillId={previewingSkillId}
          skills={detail.skills}
        />
        <JobThroughput throughput={detail.modelThroughput} />
      </div>

      <Modal
        footer={null}
        onCancel={closeReferencePreview}
        open={referencePreview !== undefined}
        title={
          referencePreview
            ? `${referencePreview.skillName} · 模型参考图`
            : "模型参考图"
        }
        width={940}
      >
        {referencePreview ? (
          <div className={styles.preview}>
            <div className={styles["preview-image"]}>
              <img
                alt={`${referencePreview.skillName}模型参考图`}
                src={referencePreview.objectUrl}
              />
            </div>
            <dl>
              <div>
                <dt>文件</dt>
                <dd>{referencePreview.image.artifactName}</dd>
              </div>
              <div>
                <dt>大小</dt>
                <dd>
                  {referencePreview.image.byteLength.toLocaleString("zh-CN")}{" "}
                  字节
                </dd>
              </div>
              <div>
                <dt>SHA-256</dt>
                <dd title={referencePreview.image.sha256}>
                  {referencePreview.image.sha256}
                </dd>
              </div>
            </dl>
          </div>
        ) : null}
      </Modal>
    </div>
  );
}
