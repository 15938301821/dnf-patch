/**
 * @fileoverview 展示制作任务中每个技能当前 attempt 的四阶段进度与模型参考图入口。
 *
 * 任务详情页传入服务端整理的技能 ViewModel 和预览命令；本组件只展示阶段证据、错误码并回传
 * 用户选择，不发 HTTP 请求、不创建 Blob URL，也不推断未知历史状态。referenceImageAvailable
 * 仅表示可向服务端申请当前参考图，不表示该 PNG 已直接用于游戏 runtime 或最终补丁。
 */
import { Button, Tag } from "antd";
import {
  Ban,
  Check,
  Circle,
  CircleHelp,
  Image as ImageIcon,
  LoaderCircle,
  X,
} from "lucide-react";
import type {
  PatchTaskSkillProgress as PatchTaskSkillProgressView,
  PatchTaskStepStatus,
} from "../../server/contracts.js";
import {
  patchTaskStepStatusView,
  skillStageLabel,
} from "../../config/job-detail-view.js";
import styles from "./index.module.scss";

/** 逐技能进度组件的受控输入；预览生命周期始终由详情页拥有。 */
interface JobSkillProgressProps {
  skills: PatchTaskSkillProgressView[];
  previewingSkillId: string;
  onPreviewReference: (skill: PatchTaskSkillProgressView) => void;
}

/**
 * 渲染当前任务的技能生产矩阵。
 *
 * @param props 服务端有序技能列表、当前预览请求 ID 与父页面命令。
 * @returns 技能总览和逐技能四阶段行；空集合不会伪造已完成技能。
 */
export function JobSkillProgress({
  skills,
  previewingSkillId,
  onPreviewReference,
}: JobSkillProgressProps): React.JSX.Element {
  return (
    <section
      aria-labelledby="skill-progress-heading"
      className={styles.section}
    >
      <header className={styles.header}>
        <div>
          <span className={styles.eyebrow}>SKILL PIPELINE</span>
          <h2 id="skill-progress-heading">逐技能进度</h2>
        </div>
        <span>{skills.length} 个技能</span>
      </header>

      {skills.length === 0 ? (
        <div className={styles.empty}>当前任务没有可展示的技能生产记录。</div>
      ) : (
        <div className={styles.list}>
          {skills.map((skill, index) => (
            <article className={styles.skill} key={skill.skillId}>
              <div className={styles.identity}>
                <span className={styles.ordinal}>
                  {(index + 1).toString().padStart(2, "0")}
                </span>
                <div>
                  <strong>{skill.displayName}</strong>
                  <Tag color={patchTaskStepStatusView[skill.status].color}>
                    {patchTaskStepStatusView[skill.status].label}
                  </Tag>
                </div>
                {skill.errorCode ? (
                  <code title={skill.errorCode}>{skill.errorCode}</code>
                ) : null}
              </div>

              <ol
                aria-label={`${skill.displayName}制作阶段`}
                className={styles.stages}
              >
                {skill.stages.map((stage) => (
                  <li
                    className={styles[`stage-${stage.status}`] ?? ""}
                    key={stage.key}
                  >
                    <span className={styles["stage-icon"]}>
                      <StatusIcon status={stage.status} />
                    </span>
                    <span>
                      <strong>{skillStageLabel[stage.key]}</strong>
                      <small>
                        {patchTaskStepStatusView[stage.status].label}
                      </small>
                    </span>
                  </li>
                ))}
              </ol>

              <div className={styles.action}>
                {skill.referenceImageAvailable ? (
                  <Button
                    aria-label={`预览${skill.displayName}模型参考图`}
                    icon={<ImageIcon size={15} />}
                    loading={previewingSkillId === skill.skillId}
                    onClick={() => onPreviewReference(skill)}
                    title={`预览${skill.displayName}模型参考图`}
                    type="text"
                  />
                ) : (
                  <span>参考图未就绪</span>
                )}
              </div>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}

/**
 * 为服务端阶段状态选择可识别图标；图标与相邻文本共同表达状态，不能只依赖颜色。
 * @param status 当前阶段的证据状态。
 * @returns 固定尺寸 Lucide 图标，不改变业务状态。
 */
function StatusIcon({
  status,
}: {
  status: PatchTaskStepStatus;
}): React.JSX.Element {
  if (status === "passed") return <Check aria-hidden size={13} />;
  if (status === "running") {
    return <LoaderCircle aria-hidden className={styles.spin} size={13} />;
  }
  if (status === "failed") return <X aria-hidden size={13} />;
  if (status === "blocked") return <Ban aria-hidden size={13} />;
  if (status === "unknown") return <CircleHelp aria-hidden size={13} />;
  return <Circle aria-hidden size={11} />;
}
