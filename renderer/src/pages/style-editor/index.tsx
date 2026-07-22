import { useEffect, useState } from "react";
import {
  Alert,
  Button,
  Form,
  Popconfirm,
  Skeleton,
  Space,
  message,
} from "antd";
import { ArrowLeft, Play, Save, Send } from "lucide-react";
import { useNavigate, useParams } from "react-router-dom";
import {
  createPatchTask,
  getProfessionSkills,
  getProfessionStyles,
  saveProfessionStyle,
  submitStyleForReview,
  type ProfessionStyle,
  type ProfessionSkillSummary,
  type SaveProfessionStyleInput,
} from "../../api/index.js";
import { PageHeading } from "../../components/page-heading/index.js";
import { ProfessionStyleForm } from "../../components/profession-style-form/index.js";
import { StylePreview } from "../../components/style-preview/index.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import { createEmptyStyleInput } from "../../utils/profession-style.js";
import {
  evaluateSkillExecution,
  type SkillExecutionGate,
} from "../../utils/skill-gate.js";
import { evaluateStyleCompleteness } from "../../utils/style-completeness.js";
import styles from "./index.module.scss";

function skillGateDescription(gate: SkillExecutionGate): string {
  switch (gate.reason) {
    case "skills-catalog-unavailable":
      return "后端尚未返回该职业的技能目录；当前仅可保存设计稿，不能创建制作任务。";
    case "skills-required":
      return "至少选择一个技能后，才能创建制作任务。";
    case "skill-not-found":
      return "所选技能不属于当前职业目录，请重新选择。";
    case "resources-unverified":
      return "所选技能的资源映射尚未核验；当前只能保存设计稿，不能创建制作任务。";
    case "ready":
      return "所选技能的资源映射已核验，可以创建制作任务。";
  }
}

export function StyleEditorPage(): React.JSX.Element {
  const [form] = Form.useForm<SaveProfessionStyleInput>();
  const [messageApi, messageContext] = message.useMessage();
  const navigate = useNavigate();
  const { professionId = "", styleId = "" } = useParams();
  const [style, setStyle] = useState<ProfessionStyle>();
  const [professionSkills, setProfessionSkills] = useState<
    ProfessionSkillSummary[]
  >([]);
  const [draft, setDraft] = useState<SaveProfessionStyleInput>(() =>
    createEmptyStyleInput(),
  );
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [creatingJob, setCreatingJob] = useState(false);

  useEffect(() => {
    let active = true;
    void Promise.all([
      getProfessionStyles(professionId),
      getProfessionSkills(professionId),
    ])
      .then(([items, skills]) => {
        const found = items.find((item) => item.id === styleId);
        if (!found) {
          throw new Error("职业风格不存在或无权访问。");
        }
        if (active) {
          setProfessionSkills(skills);
          const values: SaveProfessionStyleInput = {
            name: found.name,
            description: found.description,
            themeDefinition: found.themeDefinition,
            selectedSkillIds: found.selectedSkillIds,
            skillPrompts: found.skillPrompts,
          };
          setStyle(found);
          setDraft(values);
          form.setFieldsValue(values);
        }
      })
      .catch((error: unknown) => {
        void messageApi.error(apiErrorMessage(error));
      })
      .finally(() => {
        if (active) {
          setLoading(false);
        }
      });
    return () => {
      active = false;
    };
  }, [form, messageApi, professionId, styleId]);

  const save = async (): Promise<ProfessionStyle | undefined> => {
    setSaving(true);
    try {
      await form.validateFields();
      const saved = await saveProfessionStyle(professionId, styleId, draft);
      setStyle(saved);
      void messageApi.success("风格已保存");
      return saved;
    } catch (error: unknown) {
      if (!(
        typeof error === "object" &&
        error !== null &&
        "errorFields" in error
      )) {
        void messageApi.error(apiErrorMessage(error));
      }
      return undefined;
    } finally {
      setSaving(false);
    }
  };

  const submitReview = async (): Promise<void> => {
    if (!(await save())) {
      return;
    }
    try {
      const submitted = await submitStyleForReview(professionId, styleId);
      setStyle(submitted);
      void messageApi.success("已提交公共模板审核");
    } catch (error) {
      void messageApi.error(apiErrorMessage(error));
    }
  };

  const createJob = async (): Promise<void> => {
    if (!(await save())) {
      return;
    }
    setCreatingJob(true);
    try {
      await createPatchTask({ professionId, styleId });
      void messageApi.success("模拟制作任务已创建");
      void navigate("/jobs");
    } catch (error) {
      void messageApi.error(apiErrorMessage(error));
    } finally {
      setCreatingJob(false);
    }
  };

  const skillGate = evaluateSkillExecution(
    draft.selectedSkillIds,
    professionSkills,
  );
  const contentGate = evaluateStyleCompleteness(draft);

  const preview: ProfessionStyle = {
    id: style?.id ?? styleId,
    professionId,
    publishStatus: style?.publishStatus ?? "private",
    updatedAt: style?.updatedAt ?? new Date(0).toISOString(),
    ...draft,
  };

  if (loading) {
    return <Skeleton active paragraph={{ rows: 12 }} />;
  }

  return (
    <div className={styles.page}>
      {messageContext}
      <PageHeading
        action={
          <Space wrap>
            <Button
              icon={<ArrowLeft size={16} />}
              onClick={() => void navigate("/professions")}
            >
              返回
            </Button>
            <Button
              icon={<Save size={16} />}
              loading={saving}
              onClick={() => void save()}
            >
              保存
            </Button>
            <Popconfirm
              description="送审后仍可查看，修改内容需重新提交。"
              onConfirm={() => void submitReview()}
              title="提交公共模板审核？"
            >
              <Button
                disabled={
                  style?.publishStatus === "pending" || !contentGate.allowed
                }
                icon={<Send size={16} />}
              >
                送审
              </Button>
            </Popconfirm>
            <Button
              disabled={!skillGate.allowed || !contentGate.allowed}
              icon={<Play size={16} />}
              loading={creatingJob}
              onClick={() => void createJob()}
              type="primary"
            >
              创建任务
            </Button>
          </Space>
        }
        description="编辑职业风格的稳定约束与模型 Prompt；右侧仅为前端模拟预览。"
        title={style?.name ?? "风格编辑"}
      />

      <div className={styles.workspace}>
        <section className={styles.editor}>
          <div className={styles["editor-head"]}>
            <span>风格内容</span>
            <small>私有草稿</small>
          </div>
          <ProfessionStyleForm
            form={form}
            initialValues={draft}
            onChange={setDraft}
            skills={professionSkills}
          />
          <Alert
            className={styles["skill-gate"] ?? ""}
            description={
              contentGate.allowed
                ? skillGateDescription(skillGate)
                : "主题公共规则或逐技能主题内容尚未完整；可以保存草稿，但不能送审或创建制作任务。"
            }
            showIcon
            title={
              contentGate.allowed && skillGate.allowed
                ? "制作门禁已满足"
                : "当前仅可保存设计稿"
            }
            type={
              contentGate.allowed && skillGate.allowed ? "success" : "warning"
            }
          />
        </section>
        <StylePreview style={preview} />
      </div>
    </div>
  );
}
