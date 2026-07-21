import { useEffect, useState } from "react";
import {
  Alert,
  Button,
  Form,
  Input,
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
import { SkillScopePicker } from "../../components/skill-scope-picker/index.js";
import { StylePreview } from "../../components/style-preview/index.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import {
  evaluateSkillExecution,
  type SkillExecutionGate,
} from "../../utils/skill-gate.js";
import styles from "./index.module.scss";

const emptyValues: SaveProfessionStyleInput = {
  name: "",
  description: "",
  agent: "",
  prompt: "",
  selectedSkillIds: [],
};

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
  const [draft, setDraft] = useState<SaveProfessionStyleInput>(emptyValues);
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
            agent: found.agent,
            prompt: found.prompt,
            selectedSkillIds: found.selectedSkillIds,
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
      const saved = await saveProfessionStyle(
        professionId,
        styleId,
        await form.validateFields(),
      );
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
                disabled={style?.publishStatus === "pending"}
                icon={<Send size={16} />}
              >
                送审
              </Button>
            </Popconfirm>
            <Button
              disabled={!skillGate.allowed}
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
          <Form<SaveProfessionStyleInput>
            form={form}
            layout="vertical"
            onValuesChange={(_, values) =>
              setDraft({ ...emptyValues, ...values })
            }
            requiredMark={false}
          >
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
            <Form.Item
              extra="定义不可变边界、来源约束与审核条件。"
              label="Agent"
              name="agent"
              rules={[{ required: true, message: "请输入 Agent 内容" }]}
            >
              <Input.TextArea className={styles.code ?? ""} rows={10} />
            </Form.Item>
            <Form.Item
              extra="仅描述风格增量，不在这里猜测 NPK、IMG 或帧映射。"
              label="Prompt"
              name="prompt"
              rules={[{ required: true, message: "请输入 Prompt 内容" }]}
            >
              <Input.TextArea className={styles.code ?? ""} rows={10} />
            </Form.Item>
            <Form.Item
              extra="AI 只会基于已选 skillId 生成逐技能草稿，不负责发现技能或推断资源映射。"
              label="技能范围"
              name="selectedSkillIds"
              rules={
                professionSkills.length > 0
                  ? [
                      {
                        type: "array",
                        min: 1,
                        message: "至少选择一个技能",
                      },
                    ]
                  : []
              }
            >
              <SkillScopePicker loading={loading} skills={professionSkills} />
            </Form.Item>
            <Alert
              className={styles["skill-gate"] ?? ""}
              description={skillGateDescription(skillGate)}
              showIcon
              title={
                skillGate.allowed ? "制作门禁已满足" : "当前仅可保存设计稿"
              }
              type={skillGate.allowed ? "success" : "warning"}
            />
          </Form>
        </section>
        <StylePreview style={preview} />
      </div>
    </div>
  );
}
