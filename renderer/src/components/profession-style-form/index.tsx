import { Form, Input, Modal, Tabs, type FormInstance } from "antd";
import type {
  ProfessionSkillSummary,
  SaveProfessionStyleInput,
  SkillThemePrompt,
} from "../../server/contracts.js";
import {
  hasSkillPromptContent,
  reconcileSkillPrompts,
} from "../../utils/profession-style.js";
import { SkillScopePicker } from "../skill-scope-picker/index.js";
import { SkillThemePromptEditor } from "../skill-theme-prompt-editor/index.js";
import { ThemeColorAnchors } from "../theme-color-anchors/index.js";
import styles from "./index.module.scss";

interface ProfessionStyleFormProps {
  form: FormInstance<SaveProfessionStyleInput>;
  initialValues: SaveProfessionStyleInput;
  onChange?: (values: SaveProfessionStyleInput) => void;
  skills: readonly ProfessionSkillSummary[];
  skillsLoading?: boolean;
}

type StyleFormValues = Partial<
  Omit<SaveProfessionStyleInput, "themeDefinition" | "skillPrompts">
> & {
  themeDefinition?: Partial<SaveProfessionStyleInput["themeDefinition"]>;
  skillPrompts?: Array<Partial<SkillThemePrompt>>;
};

/** Renders the shared structured form used by style creation and editing. */
export function ProfessionStyleForm({
  form,
  initialValues,
  onChange,
  skills,
  skillsLoading = false,
}: ProfessionStyleFormProps): React.JSX.Element {
  const [modal, modalContext] = Modal.useModal();
  const watchedValues = Form.useWatch<SaveProfessionStyleInput | undefined>(
    [],
    { form, preserve: true },
  );

  const updateSkills = (selectedSkillIds: string[]): void => {
    const current: SkillThemePrompt[] =
      watchedValues?.skillPrompts ?? initialValues.skillPrompts;
    const removedWithContent = current.filter(
      (prompt) =>
        !selectedSkillIds.includes(prompt.skillId) &&
        hasSkillPromptContent(prompt),
    );
    const apply = (): void => {
      const skillPrompts = reconcileSkillPrompts(selectedSkillIds, current);
      form.setFieldsValue({ selectedSkillIds, skillPrompts });
      onChange?.({
        ...mergeStyleFormValues(initialValues, watchedValues),
        selectedSkillIds,
        skillPrompts,
      });
    };
    if (removedWithContent.length === 0) {
      apply();
      return;
    }
    modal.confirm({
      title: "移除已有主题内容的技能？",
      content: "移除后，该技能的主题增量内容不会随风格保存。",
      okText: "确认移除",
      cancelText: "保留技能",
      onOk: apply,
    });
  };

  return (
    <>
      {modalContext}
      <Form<SaveProfessionStyleInput>
        form={form}
        initialValues={initialValues}
        layout="vertical"
        onValuesChange={(_, values) =>
          onChange?.(
            mergeStyleFormValues(
              mergeStyleFormValues(initialValues, watchedValues),
              values,
            ),
          )
        }
        requiredMark={false}
      >
        <Tabs
          items={[
            {
              key: "theme",
              label: "主题定义",
              children: <ThemeFields />,
            },
            {
              key: "skills",
              label: "技能编排",
              children: (
                <div className={styles.skills}>
                  <Form.Item label="技能范围">
                    <SkillScopePicker
                      loading={skillsLoading}
                      onChange={updateSkills}
                      skills={skills}
                      value={watchedValues?.selectedSkillIds ?? []}
                    />
                  </Form.Item>
                  <SkillThemePromptEditor form={form} skills={skills} />
                </div>
              ),
            },
          ]}
        />
      </Form>
    </>
  );
}

function mergeStyleFormValues(
  current: SaveProfessionStyleInput,
  values: StyleFormValues | undefined,
): SaveProfessionStyleInput {
  const selectedSkillIds = values?.selectedSkillIds ?? current.selectedSkillIds;
  const currentSkillPrompts = reconcileSkillPrompts(
    selectedSkillIds,
    current.skillPrompts,
  );
  return {
    name: values?.name ?? current.name,
    description: values?.description ?? current.description,
    themeDefinition: {
      ...current.themeDefinition,
      ...values?.themeDefinition,
      colorAnchors:
        values?.themeDefinition?.colorAnchors ??
        current.themeDefinition.colorAnchors,
    },
    selectedSkillIds,
    skillPrompts: currentSkillPrompts.map((prompt, index) => {
      const value = values?.skillPrompts?.[index];
      return {
        skillId: prompt.skillId,
        themePrompt: value?.themePrompt ?? prompt.themePrompt,
        changes: value?.changes ?? prompt.changes,
        acceptanceCriteria:
          value?.acceptanceCriteria ?? prompt.acceptanceCriteria,
        exclusions: value?.exclusions ?? prompt.exclusions,
      };
    }),
  };
}

function ThemeFields(): React.JSX.Element {
  return (
    <div className={styles.theme}>
      <div className={styles.basics}>
        <Form.Item
          label="风格名称"
          name="name"
          rules={[{ required: true, message: "请输入风格名称" }]}
        >
          <Input maxLength={100} showCount />
        </Form.Item>
        <Form.Item label="风格描述" name="description">
          <Input.TextArea maxLength={500} rows={3} showCount />
        </Form.Item>
      </div>

      <Form.Item label="主题目标" name={["themeDefinition", "goal"]}>
        <Input.TextArea maxLength={8_000} rows={3} showCount />
      </Form.Item>
      <Form.Item label="共同视觉基线" name={["themeDefinition", "baseStyle"]}>
        <Input.TextArea
          className={styles.code ?? ""}
          maxLength={8_000}
          rows={5}
          showCount
        />
      </Form.Item>
      <ThemeColorAnchors />

      <div className={styles.grid}>
        <Form.Item label="材质规则" name={["themeDefinition", "materialRules"]}>
          <Input.TextArea maxLength={8_000} rows={4} showCount />
        </Form.Item>
        <Form.Item label="粒子规则" name={["themeDefinition", "particleRules"]}>
          <Input.TextArea maxLength={8_000} rows={4} showCount />
        </Form.Item>
        <Form.Item label="视觉层次" name={["themeDefinition", "layeringRules"]}>
          <Input.TextArea maxLength={8_000} rows={4} showCount />
        </Form.Item>
        <Form.Item label="不可变约束" name={["themeDefinition", "constraints"]}>
          <Input.TextArea maxLength={8_000} rows={4} showCount />
        </Form.Item>
        <Form.Item
          label="公共验收"
          name={["themeDefinition", "acceptanceCriteria"]}
        >
          <Input.TextArea maxLength={8_000} rows={4} showCount />
        </Form.Item>
        <Form.Item label="公共排除" name={["themeDefinition", "exclusions"]}>
          <Input.TextArea maxLength={8_000} rows={4} showCount />
        </Form.Item>
      </div>
    </div>
  );
}
