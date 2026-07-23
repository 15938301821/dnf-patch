/**
 * @fileoverview 以受控复选列表展示后端职业技能目录及三类门禁状态。
 *
 * 共享风格表单生产 `value` 并处理 `onChange`，本组件只展示和计算选择摘要；不发请求、不从
 * 名称猜测技能或资源映射。目录为空时失败关闭制作范围，未核验技能仍可选择为设计稿但必须
 * 明确标为不可制作。
 */
import { Checkbox, Empty, Skeleton, Tag } from "antd";
import type { ProfessionSkillSummary } from "../../server/contracts.js";
import styles from "./index.module.scss";

/** 技能范围选择器的受控输入与事件契约。 */
interface SkillScopePickerProps {
  loading?: boolean;
  skills: readonly ProfessionSkillSummary[];
  value?: string[];
  onChange?: (value: string[]) => void;
}

/** 把职业 Prompt 复核状态映射为标签文案。 */
function promptStatusLabel(
  status: ProfessionSkillSummary["promptStatus"],
): string {
  return status === "reviewed" ? "Prompt 已复核" : "Prompt 候选";
}

/** 把资源映射核验状态映射为标签文案。 */
function mappingStatusLabel(
  status: ProfessionSkillSummary["mappingStatus"],
): string {
  return status === "verified" ? "资源已核验" : "资源待核验";
}

/** 把后端执行状态映射为“可制作”或“仅设计”。 */
function executionStatusLabel(
  status: ProfessionSkillSummary["executionStatus"],
): string {
  return status === "build-ready" ? "可制作" : "仅设计";
}

/**
 * 渲染职业技能目录并回传去重后的稳定 ID 集合。
 *
 * @param props 后端技能摘要、父表单当前选择和可选加载状态/变更回调。
 * @returns 加载、空目录或受控复选列表；不改变后端技能状态。
 */
export function SkillScopePicker({
  loading = false,
  skills,
  value = [],
  onChange,
}: SkillScopePickerProps): React.JSX.Element {
  if (loading) {
    return <Skeleton active paragraph={{ rows: 4 }} title={false} />;
  }

  if (skills.length === 0) {
    return (
      <div className={styles.empty}>
        <Empty
          description="后端暂未返回该职业的技能目录"
          image={Empty.PRESENTED_IMAGE_SIMPLE}
        />
        <p>没有技能事实源时不能创建可制作范围；请先补充职业目录。</p>
      </div>
    );
  }

  const selectedSkills = skills.filter((skill) => value.includes(skill.id));
  const blockedCount = selectedSkills.filter(
    (skill) => skill.executionStatus !== "build-ready",
  ).length;

  /** 根据一次复选事件生成新的稳定 ID 数组并交还父表单。 */
  const toggleSkill = (skillId: string, checked: boolean): void => {
    const next = checked
      ? [...new Set([...value, skillId])]
      : value.filter((item) => item !== skillId);
    onChange?.(next);
  };

  return (
    <div className={styles.picker}>
      <div className={styles.summary}>
        <div>
          <strong>选择要纳入此风格的技能</strong>
          <span>
            已选 {selectedSkills.length} / {skills.length}；AI 只会基于已选
            skillId 生成逐技能草稿。
          </span>
        </div>
        <Tag className={styles.count ?? ""}>
          {selectedSkills.length === 0
            ? "待选择技能"
            : blockedCount > 0
              ? `${String(blockedCount)} 项仅设计`
              : "可进入制作"}
        </Tag>
      </div>

      <div className={styles.list} role="list" aria-label="职业技能目录">
        {skills.map((skill) => {
          const selected = value.includes(skill.id);
          return (
            <label
              className={selected ? styles.itemSelected : styles.item}
              key={skill.id}
            >
              <Checkbox
                checked={selected}
                onChange={(event) =>
                  toggleSkill(skill.id, event.target.checked)
                }
              >
                <span className={styles.name}>{skill.displayName}</span>
              </Checkbox>
              <span className={styles.statuses}>
                <Tag className={styles.tag ?? ""}>
                  {promptStatusLabel(skill.promptStatus)}
                </Tag>
                <Tag className={styles.tag ?? ""}>
                  {mappingStatusLabel(skill.mappingStatus)}
                </Tag>
                <Tag
                  className={
                    skill.executionStatus === "build-ready"
                      ? (styles.ready ?? "")
                      : (styles.draft ?? "")
                  }
                >
                  {executionStatusLabel(skill.executionStatus)}
                </Tag>
              </span>
            </label>
          );
        })}
      </div>

      <p className={styles.note}>
        技能名称和状态来自后端职业目录；AI 不负责发现技能，也不能根据名称猜测
        NPK、IMG 或帧映射。资源未核验的技能只能保存设计稿。
      </p>
    </div>
  );
}
