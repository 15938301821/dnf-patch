/**
 * @fileoverview 展示制作任务中每个技能当前 attempt 的版本化阶段、V6 帧计数与三图证据入口。
 *
 * 任务详情页传入服务端整理的技能 ViewModel 和预览命令；本组件只展示阶段证据、错误码并回传
 * 用户选择，不发 HTTP 请求、不创建 Blob URL，也不推断未知历史状态。referenceImageAvailable
 * 作为当前三图链已进入可审查阶段的保守门禁，不表示模型参考 PNG 已用于 runtime 像素；V6
 * 帧计数只说明清单与官方源 PNG 的登记进度，不表示目标图、候选 NPK 或部署已经完成。
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
  onCompareEvidence: (skill: PatchTaskSkillProgressView) => void;
}

/**
 * 渲染当前任务的技能生产矩阵。
 *
 * @param props 服务端有序技能列表、当前预览请求 ID 与父页面命令。
 * @returns 技能总览和逐技能四阶段行；空集合不会伪造已完成技能。
 */
export function JobSkillProgress({
  skills,
  onCompareEvidence,
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
                {skill.framePreparation ? (
                  <span className={styles["frame-summary"]}>
                    <strong>
                      源帧 {skill.framePreparation.sourceFrameCount} /{" "}
                      {skill.framePreparation.generationFrameCount}
                    </strong>
                    <small>
                      清单 {skill.framePreparation.targetFrameCount} 帧
                    </small>
                  </span>
                ) : skill.referenceImageAvailable ? (
                  <Button
                    aria-label={`查看${skill.displayName}三图证据对比`}
                    icon={<ImageIcon size={15} />}
                    onClick={() => onCompareEvidence(skill)}
                    title={`查看${skill.displayName}三图证据对比`}
                    type="text"
                  />
                ) : (
                  <span>对比证据未就绪</span>
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
