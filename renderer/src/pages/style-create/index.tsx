/**
 * @fileoverview 编排 `/professions/:professionId/styles/new` 的风格草稿创建流程。
 *
 * 受保护路由提供职业 ID，本页并行读取职业摘要与后端技能目录，再把受控草稿交给共享表单；
 * 提交成功后返回带职业查询参数的列表页。副作用仅经类型化 API 发请求、显示消息和导航；
 * 卸载后的请求结果不得写状态，客户端不发现技能、不读取资源或隐式创建制作任务。
 */
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

/**
 * 加载职业上下文并渲染可保存不完整内容的私有风格草稿表单。
 *
 * @returns 加载骨架或新建表单；请求失败只提示错误，不继续伪造职业或技能数据。
 */
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
    // 第一步：职业名称与技能事实并行读取，二者都成功后才进入可编辑上下文。
    void Promise.all([getProfessionsList(), getProfessionSkills(professionId)])
      .then(([professions, professionSkills]) => {
        const found = professions.find((item) => item.id === professionId);
        if (!found) throw new Error("职业不存在或无权访问。");
        // 第二步：卸载或路由变化后忽略 stale result，避免旧职业覆盖新页面。
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
      // 第三步：清理当前请求的写入资格；API 请求本身仍由共享客户端结算。
      active = false;
    };
  }, [messageApi, professionId]);

  /** 返回职业列表并保留当前职业选择。 */
  const returnToList = (): void => {
    void navigate(
      `/professions?professionId=${encodeURIComponent(professionId)}`,
    );
  };

  /**
   * 先验证表单，再创建私有草稿并返回职业列表。
   *
   * @returns 创建、导航或错误处理完成后结算；校验/请求失败时禁止导航。
   */
  const submit = async (): Promise<void> => {
    setSaving(true);
    try {
      // 表单校验失败不会调用 API；服务端成功后才允许显示成功消息和导航。
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
