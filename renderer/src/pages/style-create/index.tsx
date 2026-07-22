import { useEffect, useState } from "react";
import { Button, Form, Skeleton, Space, message } from "antd";
import { ArrowLeft, Save } from "lucide-react";
import { useNavigate, useParams } from "react-router-dom";
import {
  createProfessionStyle,
  getProfessionSkills,
  getProfessionsList,
  type ProfessionSkillSummary,
  type ProfessionSummary,
  type SaveProfessionStyleInput,
} from "../../api/index.js";
import { PageHeading } from "../../components/page-heading/index.js";
import { ProfessionStyleForm } from "../../components/profession-style-form/index.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import { createEmptyStyleInput } from "../../utils/profession-style.js";
import styles from "./index.module.scss";

export function StyleCreatePage(): React.JSX.Element {
  const [form] = Form.useForm<SaveProfessionStyleInput>();
  const [messageApi, messageContext] = message.useMessage();
  const navigate = useNavigate();
  const { professionId = "" } = useParams();
  const [profession, setProfession] = useState<ProfessionSummary>();
  const [skills, setSkills] = useState<ProfessionSkillSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [draft, setDraft] = useState<SaveProfessionStyleInput>(() =>
    createEmptyStyleInput(),
  );

  useEffect(() => {
    let active = true;
    void Promise.all([getProfessionsList(), getProfessionSkills(professionId)])
      .then(([professions, professionSkills]) => {
        const found = professions.find((item) => item.id === professionId);
        if (!found) throw new Error("职业不存在或无权访问。");
        if (active) {
          setProfession(found);
          setSkills(professionSkills);
        }
      })
      .catch((error: unknown) => {
        void messageApi.error(apiErrorMessage(error));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [messageApi, professionId]);

  const returnToList = (): void => {
    void navigate(
      `/professions?professionId=${encodeURIComponent(professionId)}`,
    );
  };

  const submit = async (): Promise<void> => {
    setSaving(true);
    try {
      await form.validateFields();
      await createProfessionStyle(professionId, draft);
      void messageApi.success("风格草稿已创建");
      returnToList();
    } catch (error: unknown) {
      if (!(
        typeof error === "object" &&
        error !== null &&
        "errorFields" in error
      )) {
        void messageApi.error(apiErrorMessage(error));
      }
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <Skeleton active paragraph={{ rows: 14 }} />;

  return (
    <div className={styles.page}>
      {messageContext}
      <PageHeading
        action={
          <Space wrap>
            <Button icon={<ArrowLeft size={16} />} onClick={returnToList}>
              返回
            </Button>
            <Button
              icon={<Save size={16} />}
              loading={saving}
              onClick={() => void submit()}
              type="primary"
            >
              创建草稿
            </Button>
          </Space>
        }
        description="建立主题公共规则和逐技能视觉增量；资源与职业事实由后端目录提供。"
        title={`新建${profession?.name ?? "职业"}风格`}
      />
      <section className={styles.form}>
        <ProfessionStyleForm
          form={form}
          initialValues={draft}
          onChange={setDraft}
          skills={skills}
        />
      </section>
    </div>
  );
}
