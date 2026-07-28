/**
 * @fileoverview 以受控复选列表展示后端职业技能目录及三类门禁状态。
 *
 * 共享风格表单生产 `value` 并处理 `onChange`，本组件只展示和计算选择摘要；不发请求、不从
 * 名称猜测技能或资源映射。目录为空时失败关闭制作范围，未核验技能仍可选择为设计稿但必须
 * 明确标为不可制作。
 */
import { Checkbox, Empty, Input, Segmented, Skeleton, Tag } from "antd";
import { Search } from "lucide-react";
import { useDeferredValue, useState } from "react";
import type { ProfessionSkillSummary } from "../../server/contracts.js";
import styles from "./index.module.scss";

/** 技能范围选择器的受控输入与事件契约。 */
interface SkillScopePickerProps {
  loading?: boolean;
  skills: readonly ProfessionSkillSummary[];
  value?: string[];
  onChange?: (value: string[]) => void;
}

/** 仅影响当前目录可见项的本地筛选，不会修改表单中的技能 ID。 */
type SkillScopeFilter = "all" | "selected" | "build-ready" | "draft-only";

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
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<SkillScopeFilter>("all");
  const deferredQuery = useDeferredValue(query.trim().toLocaleLowerCase());

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
  const visibleSkills = skills.filter((skill) => {
    const matchesQuery =
      deferredQuery.length === 0 ||
      skill.displayName.toLocaleLowerCase().includes(deferredQuery) ||
      skill.id.toLocaleLowerCase().includes(deferredQuery);
    const matchesFilter =
      filter === "all" ||
      (filter === "selected" && value.includes(skill.id)) ||
      (filter === "build-ready" && skill.executionStatus === "build-ready") ||
      (filter === "draft-only" && skill.executionStatus === "draft-only");
    return matchesQuery && matchesFilter;
  });

  /** 根据一次复选事件生成新的稳定 ID 数组并交还父表单。 */
  const toggleSkill = (skillId: string, checked: boolean): void => {
    const next = checked
      ? [...new Set([...value, skillId])]
      : value.filter((item) => item !== skillId);
    onChange?.(next);
  };

  /** 只接受当前分段控件声明的值，未知值不改变目录视图。 */
  const changeFilter = (next: string | number): void => {
    if (
      next === "all" ||
      next === "selected" ||
      next === "build-ready" ||
      next === "draft-only"
    ) {
      setFilter(next);
    }
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

      <div className={styles.tools}>
        <Input
          allowClear
          aria-label="搜索职业技能"
          onChange={(event) => setQuery(event.target.value)}
          placeholder="搜索技能名称或 ID"
          prefix={<Search aria-hidden="true" size={14} />}
          value={query}
        />
        <Segmented
          aria-label="筛选职业技能"
          block
          onChange={changeFilter}
          options={[
            { label: "全部", value: "all" },
            { label: "已选", value: "selected" },
            { label: "可制作", value: "build-ready" },
            { label: "仅设计", value: "draft-only" },
          ]}
          size="small"
          value={filter}
        />
      </div>

      <div className={styles.result}>显示 {visibleSkills.length} 项</div>

      <div className={styles.list} role="list" aria-label="职业技能目录">
        {visibleSkills.map((skill) => {
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
        {visibleSkills.length === 0 ? (
          <div className={styles["filter-empty"]}>没有符合条件的技能</div>
        ) : null}
      </div>

      <p className={styles.note}>
        技能名称和状态来自后端职业目录；AI 不负责发现技能，也不能根据名称猜测
        NPK、IMG 或帧映射。资源未核验的技能只能保存设计稿。
      </p>
    </div>
  );
}
