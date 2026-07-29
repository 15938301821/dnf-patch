/**
 * @fileoverview 展示一个技能当前 attempt 的源帧、模型参考图与模型计划+Aseprite 结果图。
 *
 * 任务详情页只控制打开技能，本组件通过类型化 jobs API 并发读取三个固定角色；每个角色独立
 * 呈现加载、缺失、失败或可审查状态。副作用包括三项短期授权、PNG 下载和 Blob URL 创建；
 * 关闭、切换技能、重试或卸载时必须中止整轮请求并释放全部 URL，过期结果不得覆盖当前技能。
 * 浏览器只提交任务、技能和固定角色，不提交 Artifact ID、对象 key 或本机路径。V2 模型母图
 * 提供 runtime RGB，Engineer 只定位空间映射，Aseprite 恢复官方几何和 Alpha；质量数字来自
 * 独立 Worker 校验。对比结果不证明客户端兼容、部署或全技能覆盖。
 */
import axios from "axios";
import { Alert, Button, Modal, Segmented, Tag, Tooltip } from "antd";
import { CircleHelp, LoaderCircle, RefreshCw } from "lucide-react";
import { useEffect, useState } from "react";
import {
  downloadJobSkillPreview,
  type PatchTaskSkillPreview,
  type PatchTaskSkillPreviewFrame,
  type PatchTaskSkillPreviewRole,
  type PatchTaskSkillProgress,
} from "../../api/index.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import styles from "./index.module.scss";

const previewRoles = [
  "source-frame",
  "reference-image",
  "aseprite-result",
] as const satisfies readonly PatchTaskSkillPreviewRole[];

const previewRoleView: Record<
  PatchTaskSkillPreviewRole,
  {
    order: string;
    title: string;
    shortTitle: string;
    badge: string;
    description: string;
  }
> = {
  "source-frame": {
    order: "01",
    title: "技能源帧",
    shortTitle: "源帧",
    badge: "官方约束",
    description: "已核验资源中的代表帧",
  },
  "reference-image": {
    order: "02",
    title: "模型参考图",
    shortTitle: "模型参考",
    badge: "RGB 母图",
    description: "图片模型生成高分辨率视觉特效，作为 runtime RGB 主来源",
  },
  "aseprite-result": {
    order: "03",
    title: "模型 + Aseprite 结果",
    shortTitle: "Aseprite 结果",
    badge: "约束恢复",
    description: "Engineer 匹配位置，Aseprite 恢复官方尺寸、位置与 Alpha",
  },
};

/** 每个角色独立结算，历史任务缺少新证据时不阻断其他两栏。 */
type PreviewState =
  | { status: "loading" }
  | { status: "missing" }
  | { status: "error"; message: string }
  | { status: "ready"; image: PatchTaskSkillPreview; objectUrl: string };

type PreviewStates = Record<PatchTaskSkillPreviewRole, PreviewState>;

/** 受控弹窗输入；网络与 Blob 生命周期由本组件拥有，父页面不保存图片字节或授权 URL。 */
interface SkillEvidenceComparisonProps {
  jobId: string;
  skill: PatchTaskSkillProgress | undefined;
  open: boolean;
  onClose: () => void;
}

/**
 * 渲染一个技能的三角色证据审查弹窗。
 *
 * @param props 当前任务、技能、开关和关闭命令；skill 来自任务详情脱敏 ViewModel。
 * @returns 桌面三列、窄屏分段切换的证据视图；单项 404 映射为历史缺失，不显示全局错误。
 */
export function SkillEvidenceComparison({
  jobId,
  skill,
  open,
  onClose,
}: SkillEvidenceComparisonProps): React.JSX.Element {
  const [previews, setPreviews] = useState<PreviewStates>(loadingPreviews);
  const [activeRole, setActiveRole] =
    useState<PatchTaskSkillPreviewRole>("source-frame");
  const [reloadVersion, setReloadVersion] = useState(0);
  const selectedSkillId = skill?.skillId;

  useEffect(() => {
    if (!open || !selectedSkillId) return;
    const controller = new AbortController();
    const objectUrls: string[] = [];
    setActiveRole("source-frame");
    setPreviews(loadingPreviews());

    // 三个角色并发且独立结算；一项缺失不能把已有证据降级为整组失败。
    for (const role of previewRoles) {
      void downloadJobSkillPreview(
        jobId,
        selectedSkillId,
        role,
        controller.signal,
      )
        .then(({ image, blob }) => {
          if (controller.signal.aborted) return;
          const objectUrl = URL.createObjectURL(blob);
          objectUrls.push(objectUrl);
          setPreviews((current) => ({
            ...current,
            [role]: { status: "ready", image, objectUrl },
          }));
        })
        .catch((error: unknown) => {
          if (controller.signal.aborted) return;
          setPreviews((current) => ({
            ...current,
            [role]: isMissingPreview(error)
              ? { status: "missing" }
              : { status: "error", message: apiErrorMessage(error) },
          }));
        });
    }

    return () => {
      // 当前 effect 独占本轮 URL；清理后旧请求和旧图片都不能写回下一技能。
      controller.abort();
      for (const objectUrl of objectUrls) URL.revokeObjectURL(objectUrl);
    };
  }, [jobId, open, reloadVersion, selectedSkillId]);

  const readyCount = previewRoles.filter(
    (role) => previews[role].status === "ready",
  ).length;
  const source = readyPreview(previews["source-frame"]);
  const result = readyPreview(previews["aseprite-result"]);
  const frameMatch =
    source?.image.frame && result?.image.frame
      ? sameFrame(source.image.frame, result.image.frame)
      : undefined;
  const sourceQuality = source?.image.referenceTransferQuality;
  const resultQuality = result?.image.referenceTransferQuality;
  const qualityMismatch =
    sourceQuality !== undefined &&
    resultQuality !== undefined &&
    !sameQuality(sourceQuality, resultQuality);
  const quality = qualityMismatch
    ? undefined
    : (resultQuality ?? sourceQuality);

  return (
    <Modal
      className={styles.modal ?? ""}
      destroyOnHidden
      footer={null}
      onCancel={onClose}
      open={open && skill !== undefined}
      title={
        <div className={styles["modal-title"]}>
          <span>{skill?.displayName ?? "技能"}</span>
          <small>三图证据审查</small>
        </div>
      }
      width={1280}
    >
      {skill ? (
        <div className={styles.workspace}>
          <header className={styles.summary}>
            <div>
              <span className={styles.eyebrow}>EVIDENCE REVIEW</span>
              <strong>{readyCount} / 3 项证据</strong>
              <small>
                {frameMatch === true && source?.image.frame
                  ? `同帧 · ${source.image.frame.internalPath}`
                  : "当前生产 attempt"}
              </small>
            </div>
            <Tooltip title="重新加载三项证据">
              <Button
                aria-label="重新加载三项证据"
                icon={<RefreshCw size={16} />}
                onClick={() => setReloadVersion((version) => version + 1)}
                type="text"
              />
            </Tooltip>
          </header>

          {frameMatch === false ? (
            <Alert
              description="源帧与结果图的帧身份不一致，本次结果不能作为同帧比较证据。"
              showIcon
              title="证据帧不一致"
              type="error"
            />
          ) : null}

          {qualityMismatch ? (
            <Alert
              description="源帧与结果图携带的独立质量摘要不同，本次指标不能作为审查证据。"
              showIcon
              title="质量证据不一致"
              type="error"
            />
          ) : (
            <QualityGate quality={quality} />
          )}

          <Segmented<PatchTaskSkillPreviewRole>
            aria-label="选择证据视图"
            block
            className={styles.switcher}
            onChange={setActiveRole}
            options={previewRoles.map((role) => ({
              label: previewRoleView[role].shortTitle,
              value: role,
            }))}
            value={activeRole}
          />

          <div className={styles.grid}>
            {previewRoles.map((role) => (
              <PreviewPanel
                active={activeRole === role}
                key={role}
                role={role}
                skillName={skill.displayName}
                state={previews[role]}
              />
            ))}
          </div>
        </div>
      ) : null}
    </Modal>
  );
}

/** 展示 Server 复核后的三项固定门禁；历史 V1 无摘要时不推断通过状态。 */
function QualityGate({
  quality,
}: {
  quality: PatchTaskSkillPreview["referenceTransferQuality"];
}): React.JSX.Element {
  if (!quality) {
    return (
      <div className={styles["quality-legacy"]}>
        旧版证据未计算参考 RGB 质量门禁
      </div>
    );
  }
  return (
    <section aria-label="参考图传输质量门禁" className={styles.quality}>
      <div>
        <span>参考覆盖率</span>
        <strong>{percent(quality.referenceCoverage)}</strong>
        <small>门槛 ≥ 80%</small>
      </div>
      <div>
        <span>RGB 相似度</span>
        <strong>{percent(quality.referenceSimilarity)}</strong>
        <small>门槛 ≥ 90%</small>
      </div>
      <div>
        <span>清晰度倍率</span>
        <strong>{quality.edgeEnergyRatio.toFixed(2)}×</strong>
        <small>门槛 ≥ 1.01×</small>
      </div>
      <p>
        {quality.evaluatedFrameCount.toLocaleString("zh-CN")} 帧 ·{" "}
        {quality.evaluatedPixelCount.toLocaleString("zh-CN")} 有效像素
      </p>
    </section>
  );
}

/** 单个固定角色面板；只展示父组件已经结算的状态，不触发额外网络请求。 */
function PreviewPanel({
  active,
  role,
  skillName,
  state,
}: {
  active: boolean;
  role: PatchTaskSkillPreviewRole;
  skillName: string;
  state: PreviewState;
}): React.JSX.Element {
  const view = previewRoleView[role];
  return (
    <article
      className={`${styles.panel ?? ""} ${active ? (styles.active ?? "") : ""}`}
      data-role={role}
    >
      <header className={styles["panel-header"]}>
        <span className={styles.order}>{view.order}</span>
        <div>
          <strong>{view.title}</strong>
          <small>{view.description}</small>
        </div>
        <Tag>{view.badge}</Tag>
      </header>

      <div className={styles["image-stage"]}>
        {state.status === "ready" ? (
          <img
            alt={`${skillName}${view.title}`}
            className={role === "reference-image" ? styles.reference : ""}
            src={state.objectUrl}
          />
        ) : (
          <PreviewPlaceholder state={state} />
        )}
      </div>

      {state.status === "ready" ? (
        <PreviewMetadata image={state.image} />
      ) : (
        <div className={styles["empty-metadata"]}>
          {state.status === "missing"
            ? "当前任务未保存此角色证据"
            : state.status === "error"
              ? "未取得可验证的 PNG"
              : "正在复核角色与图片字节"}
        </div>
      )}
    </article>
  );
}

/** 根据单项加载结果显示稳定占位，不让图片到达顺序改变三列尺寸。 */
function PreviewPlaceholder({
  state,
}: {
  state: Exclude<PreviewState, { status: "ready" }>;
}): React.JSX.Element {
  if (state.status === "loading") {
    return (
      <div className={styles.placeholder} role="status">
        <LoaderCircle aria-hidden className={styles.spin} size={22} />
        <strong>正在复核证据</strong>
      </div>
    );
  }
  if (state.status === "missing") {
    return (
      <div className={styles.placeholder}>
        <CircleHelp aria-hidden size={22} />
        <strong>未生成</strong>
        <span>历史 attempt 可能没有此项预览</span>
      </div>
    );
  }
  return (
    <div className={styles.placeholder}>
      <CircleHelp aria-hidden size={22} />
      <strong>加载失败</strong>
      <span>{state.message}</span>
    </div>
  );
}

/** 展示脱敏 Artifact 与公开帧元数据；SHA 只显示摘要，完整值保留在 title。 */
function PreviewMetadata({
  image,
}: {
  image: PatchTaskSkillPreview;
}): React.JSX.Element {
  return (
    <dl className={styles.metadata}>
      <div>
        <dt>文件</dt>
        <dd title={image.artifactName}>{image.artifactName}</dd>
      </div>
      {image.frame ? (
        <>
          <div>
            <dt>帧定位</dt>
            <dd>
              Entry {image.frame.entryIndex + 1} · Frame{" "}
              {image.frame.frameIndex}
            </dd>
          </div>
          <div>
            <dt>画面</dt>
            <dd>
              {image.frame.width}×{image.frame.height} · Canvas{" "}
              {image.frame.canvasWidth}×{image.frame.canvasHeight}
            </dd>
          </div>
        </>
      ) : (
        <div>
          <dt>语义</dt>
          <dd>图片模型 RGB 母图，不绑定单一 runtime 帧</dd>
        </div>
      )}
      <div>
        <dt>大小 / SHA-256</dt>
        <dd title={image.sha256}>
          {image.byteLength.toLocaleString("zh-CN")} B ·{" "}
          {shortSha(image.sha256)}
        </dd>
      </div>
    </dl>
  );
}

/** 构造新一轮三角色加载态，避免不同技能复用上一轮可见结果。 */
function loadingPreviews(): PreviewStates {
  return {
    "source-frame": { status: "loading" },
    "reference-image": { status: "loading" },
    "aseprite-result": { status: "loading" },
  };
}

/** 只从 ready 判别分支提取图片，保持主组件的同帧判断可读。 */
function readyPreview(
  state: PreviewState,
): Extract<PreviewState, { status: "ready" }> | undefined {
  return state.status === "ready" ? state : undefined;
}

/** 404 表示固定角色不存在或不可见；界面统一降级，不能据此推断跨用户任务是否存在。 */
function isMissingPreview(error: unknown): boolean {
  return axios.isAxiosError(error) && error.response?.status === 404;
}

/** 比较服务端公开的完整帧身份；任一字段漂移都禁止显示“同帧”结论。 */
function sameFrame(
  left: PatchTaskSkillPreviewFrame,
  right: PatchTaskSkillPreviewFrame,
): boolean {
  return (
    left.entryIndex === right.entryIndex &&
    left.frameIndex === right.frameIndex &&
    left.internalPath === right.internalPath &&
    left.width === right.width &&
    left.height === right.height &&
    left.canvasWidth === right.canvasWidth &&
    left.canvasHeight === right.canvasHeight &&
    left.x === right.x &&
    left.y === right.y
  );
}

/** 逐字段比较源帧和结果图的 finalized 质量摘要，避免只展示单侧漂移值。 */
function sameQuality(
  left: NonNullable<PatchTaskSkillPreview["referenceTransferQuality"]>,
  right: NonNullable<PatchTaskSkillPreview["referenceTransferQuality"]>,
): boolean {
  return (
    left.evaluatedFrameCount === right.evaluatedFrameCount &&
    left.evaluatedPixelCount === right.evaluatedPixelCount &&
    left.referenceCoverage === right.referenceCoverage &&
    left.referenceSimilarity === right.referenceSimilarity &&
    left.sourceEdgeEnergy === right.sourceEdgeEnergy &&
    left.runtimeEdgeEnergy === right.runtimeEdgeEnergy &&
    left.edgeEnergyRatio === right.edgeEnergyRatio
  );
}

/** 生成适合紧凑面板的摘要；完整 SHA 仍由 title 提供。 */
function shortSha(sha256: string): string {
  return `${sha256.slice(0, 8)}…${sha256.slice(-8)}`;
}

/** 把 0..1 的证据比率格式化为一位百分数，不改变服务端阈值判断。 */
function percent(value: number): string {
  return new Intl.NumberFormat("zh-CN", {
    style: "percent",
    maximumFractionDigits: 1,
  }).format(value);
}
