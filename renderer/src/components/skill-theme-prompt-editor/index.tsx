/**
 * @fileoverview 在已选技能间切换并编辑逐技能主题增量。
 *
 * 共享风格表单提供 Form 实例和后端技能目录，本组件观察所选 ID 与 Prompt 数组并维护当前
 * 标签页；字段值仍由父表单拥有。组件不发请求、不修改职业 Prompt 事实；选择变化时必须把
 * 活动技能收敛到仍存在的首项，避免渲染指向已删除行的索引。
 */
import { Alert, Button, Empty, Form, Input, Tag } from "antd";
import { Check, CircleAlert } from "lucide-react";
import { useEffect, useState } from "react";
import type {
  ProfessionSkillSummary,
  SaveProfessionStyleInput,
  SkillThemePrompt,
} from "../../server/contracts.js";
import styles from "./index.module.scss";

/** 逐技能编辑器从父表单读取值所需的契约。 */
interface SkillThemePromptEditorProps {
  form: ReturnType<typeof Form.useForm<SaveProfessionStyleInput>>[0];
  skills: readonly ProfessionSkillSummary[];
}

/** 判断单个技能的四个主题增量字段是否都已有非空内容。 */
function promptComplete(prompt: SkillThemePrompt | undefined): boolean {
  return Boolean(
    prompt &&
    prompt.themePrompt.trim() &&
    prompt.changes.trim() &&
    prompt.acceptanceCriteria.trim() &&
    prompt.exclusions.trim(),
  );
}

/**
 * 每次展示一个已选技能，同时保留其他技能的表单草稿。
 *
 * @param props 父级 Form 实例与同职业后端技能目录；组件不会更改目录事实。
 * @returns 技能标签页、只读职业 Prompt 与当前技能的受控输入区域。
 */
export function SkillThemePromptEditor({
  form,
  skills,
}: SkillThemePromptEditorProps): React.JSX.Element {
  const selectedSkillIds =
    Form.useWatch<SaveProfessionStyleInput["selectedSkillIds"] | undefined>(
      "selectedSkillIds",
      { form, preserve: true },
    ) ?? [];
  const prompts =
    Form.useWatch<SaveProfessionStyleInput["skillPrompts"] | undefined>(
      "skillPrompts",
      {
        form,
        preserve: true,
      },
    ) ?? [];
  const [activeSkillId, setActiveSkillId] = useState("");

  useEffect(() => {
    // 技能被父表单移除后立即切换，避免旧索引继续编辑另一行或空行。
    if (!selectedSkillIds.includes(activeSkillId)) {
      setActiveSkillId(selectedSkillIds[0] ?? "");
    }
  }, [activeSkillId, selectedSkillIds]);

  if (selectedSkillIds.length === 0) {
    return (
      <Empty
        description="选择技能后编辑主题增量"
        image={Empty.PRESENTED_IMAGE_SIMPLE}
      />
    );
  }

  const selectedSkills = selectedSkillIds
    .map((skillId) => skills.find((skill) => skill.id === skillId))
    .filter((skill): skill is ProfessionSkillSummary => skill !== undefined);
  const activeIndex = prompts.findIndex(
    (prompt) => prompt.skillId === activeSkillId,
  );
  const activeSkill = selectedSkills.find(
    (skill) => skill.id === activeSkillId,
  );

  return (
    <div className={styles.workspace}>
      <div className={styles.skills} role="tablist" aria-label="已选技能">
        {selectedSkills.map((skill) => {
          const prompt = prompts.find((item) => item.skillId === skill.id);
          const complete = promptComplete(prompt);
          return (
            <Button
              aria-selected={skill.id === activeSkillId}
              className={
                skill.id === activeSkillId
                  ? (styles.active ?? "")
                  : (styles.skill ?? "")
              }
              icon={complete ? <Check size={14} /> : <CircleAlert size={14} />}
              key={skill.id}
              onClick={() => setActiveSkillId(skill.id)}
              role="tab"
              type="text"
            >
              <span>{skill.displayName}</span>
              <Tag color={complete ? "success" : "warning"}>
                {complete ? "完整" : "待补充"}
              </Tag>
            </Button>
          );
        })}
      </div>

      <div className={styles.editor} role="tabpanel">
        {activeSkill && activeIndex >= 0 ? (
          <>
            <div className={styles["editor-heading"]}>
              <div>
                <strong>{activeSkill.displayName}</strong>
                <span>职业内容只读，主题仅追加视觉增量。</span>
              </div>
              <Tag>
                {activeSkill.promptStatus === "reviewed"
                  ? "职业 Prompt 已复核"
                  : "职业 Prompt 候选"}
              </Tag>
            </div>

            {activeSkill.professionPrompt ? (
              <div className={styles.profession}>
                <PromptFact
                  label="职业稳定语义"
                  value={activeSkill.professionPrompt.stableSemantics}
                />
                <PromptFact
                  label="职业通用 Prompt"
                  value={activeSkill.professionPrompt.commonPrompt}
                />
                <PromptFact
                  label="源资源约束"
                  value={activeSkill.professionPrompt.sourceConstraints}
                />
                <PromptFact
                  label="阶段验收"
                  value={activeSkill.professionPrompt.stageAcceptance}
                />
              </div>
            ) : (
              <Alert
                description="后端尚未提供该技能的结构化职业 Prompt；当前主题只能作为设计草稿。"
                showIcon
                type="warning"
              />
            )}

            <Form.Item
              label="主题增量 Prompt"
              name={["skillPrompts", activeIndex, "themePrompt"]}
            >
              <Input.TextArea maxLength={8_000} rows={5} showCount />
            </Form.Item>
            <Form.Item
              label="具体变化"
              name={["skillPrompts", activeIndex, "changes"]}
            >
              <Input.TextArea maxLength={8_000} rows={4} showCount />
            </Form.Item>
            <Form.Item
              label="主题验收"
              name={["skillPrompts", activeIndex, "acceptanceCriteria"]}
            >
              <Input.TextArea maxLength={8_000} rows={4} showCount />
            </Form.Item>
            <Form.Item
              label="主题排除"
              name={["skillPrompts", activeIndex, "exclusions"]}
            >
              <Input.TextArea maxLength={8_000} rows={4} showCount />
            </Form.Item>
          </>
        ) : null}
      </div>
    </div>
  );
}

/**
 * 展示一个后端生产的只读职业 Prompt 事实。
 *
 * @param props 字段标签与服务端文本，不接受编辑或产生副作用。
 * @returns 保留换行的事实展示块。
 */
function PromptFact({
  label,
  value,
}: {
  label: string;
  value: string;
}): React.JSX.Element {
  return (
    <div>
      <strong>{label}</strong>
      <p>{value}</p>
    </div>
  );
}
