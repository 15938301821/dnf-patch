import { useEffect, useState } from "react";
import {
  Button,
  Empty,
  Form,
  Input,
  Modal,
  Skeleton,
  Typography,
  message,
} from "antd";
import { ArrowRight, Layers3, Plus } from "lucide-react";
import { useNavigate, useSearchParams } from "react-router-dom";
import {
  createProfession,
  getProfessionStyles,
  getProfessionsList,
  type CreateProfessionInput,
  type ProfessionStyle,
  type ProfessionSummary,
} from "../../api/index.js";
import { PageHeading } from "../../components/page-heading/index.js";
import { PublishStatus } from "../../components/publish-status/index.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import styles from "./index.module.scss";

export function ProfessionsPage(): React.JSX.Element {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [professionForm] = Form.useForm<CreateProfessionInput>();
  const [messageApi, messageContext] = message.useMessage();
  const [professions, setProfessions] = useState<ProfessionSummary[]>([]);
  const [stylesList, setStylesList] = useState<ProfessionStyle[]>([]);
  const [selectedId, setSelectedId] = useState("");
  const [loading, setLoading] = useState(true);
  const [stylesLoading, setStylesLoading] = useState(false);
  const [professionModalOpen, setProfessionModalOpen] = useState(false);
  const [saving, setSaving] = useState(false);

  const loadProfessions = async (preferredId?: string): Promise<void> => {
    const items = await getProfessionsList();
    setProfessions(items);
    setSelectedId(
      (current) => ((preferredId ?? current) || items[0]?.id) ?? "",
    );
  };

  useEffect(() => {
    let active = true;
    void getProfessionsList()
      .then((items) => {
        if (active) {
          setProfessions(items);
          const preferredId = searchParams.get("professionId") ?? "";
          setSelectedId(
            items.some((item) => item.id === preferredId)
              ? preferredId
              : (items[0]?.id ?? ""),
          );
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
  }, [messageApi, searchParams]);

  useEffect(() => {
    if (!selectedId) {
      setStylesList([]);
      return;
    }
    let active = true;
    setStylesLoading(true);
    void getProfessionStyles(selectedId)
      .then((items) => {
        if (active) {
          setStylesList(items);
        }
      })
      .catch((error: unknown) => {
        void messageApi.error(apiErrorMessage(error));
      })
      .finally(() => {
        if (active) {
          setStylesLoading(false);
        }
      });
    return () => {
      active = false;
    };
  }, [messageApi, selectedId]);

  const submitProfession = async (): Promise<void> => {
    setSaving(true);
    try {
      const created = await createProfession(
        await professionForm.validateFields(),
      );
      await loadProfessions(created.id);
      setProfessionModalOpen(false);
      professionForm.resetFields();
      void messageApi.success("职业已创建");
    } catch (error: unknown) {
      if (
        typeof error === "object" &&
        error !== null &&
        "errorFields" in error
      ) {
        return;
      }
      void messageApi.error(apiErrorMessage(error));
    } finally {
      setSaving(false);
    }
  };

  const selectedProfession = professions.find((item) => item.id === selectedId);

  return (
    <div className={styles.page}>
      {messageContext}
      <PageHeading
        action={
          <Button
            icon={<Plus size={17} />}
            onClick={() => setProfessionModalOpen(true)}
            type="primary"
          >
            新建职业
          </Button>
        }
        description="管理个人职业内容，并将成熟风格提交到公共模板审核。"
        title="职业与风格"
      />

      <div className={styles.layout}>
        <section className={styles.professions}>
          <div className={styles["section-title"]}>
            <span>我的职业</span>
            <strong>{professions.length}</strong>
          </div>
          {loading ? (
            <Skeleton active paragraph={{ rows: 5 }} title={false} />
          ) : professions.length === 0 ? (
            <Empty description="暂无职业" />
          ) : (
            <div role="list">
              {professions.map((profession) => (
                <button
                  className={
                    profession.id === selectedId
                      ? styles["profession-active"]
                      : styles.profession
                  }
                  key={profession.id}
                  onClick={() => setSelectedId(profession.id)}
                  role="listitem"
                  type="button"
                >
                  <span className={styles["profession-mark"]}>
                    {profession.name.slice(0, 1)}
                  </span>
                  <span className={styles["profession-copy"]}>
                    <strong>{profession.name}</strong>
                    <small>{profession.styleCount} 个风格</small>
                  </span>
                  <PublishStatus status={profession.publishStatus} />
                </button>
              ))}
            </div>
          )}
        </section>

        <section className={styles.styles}>
          <div className={styles["styles-head"]}>
            <div>
              <Layers3 aria-hidden="true" size={19} />
              <div>
                <Typography.Title level={2}>
                  {selectedProfession?.name ?? "选择职业"}
                </Typography.Title>
                <span>{selectedProfession?.slug ?? ""}</span>
              </div>
            </div>
            <Button
              disabled={!selectedId}
              icon={<Plus size={16} />}
              onClick={() =>
                void navigate(`/professions/${selectedId}/styles/new`)
              }
            >
              新建风格
            </Button>
          </div>

          {stylesLoading ? (
            <Skeleton active paragraph={{ rows: 6 }} />
          ) : stylesList.length === 0 ? (
            <Empty description="当前职业尚无风格" />
          ) : (
            <div className={styles["style-grid"]}>
              {stylesList.map((style) => (
                <article className={styles["style-item"]} key={style.id}>
                  <div className={styles["style-top"]}>
                    <PublishStatus status={style.publishStatus} />
                    <span>
                      {new Date(style.updatedAt).toLocaleDateString("zh-CN")}
                    </span>
                  </div>
                  <h3>{style.name}</h3>
                  <p>{style.description || "暂无风格描述"}</p>
                  <Button
                    icon={<ArrowRight size={16} />}
                    iconPlacement="end"
                    onClick={() =>
                      void navigate(
                        `/professions/${selectedId}/styles/${style.id}`,
                      )
                    }
                    type="link"
                  >
                    编辑与预览
                  </Button>
                </article>
              ))}
            </div>
          )}
        </section>
      </div>

      <Modal
        confirmLoading={saving}
        onCancel={() => setProfessionModalOpen(false)}
        onOk={() => void submitProfession()}
        open={professionModalOpen}
        title="新建职业"
      >
        <Form form={professionForm} layout="vertical" requiredMark={false}>
          <Form.Item
            label="职业名称"
            name="name"
            rules={[{ required: true, message: "请输入职业名称" }]}
          >
            <Input maxLength={80} />
          </Form.Item>
          <Form.Item
            label="唯一标识"
            name="slug"
            rules={[
              { required: true, message: "请输入唯一标识" },
              {
                pattern: /^[a-z0-9]+(?:-[a-z0-9]+)*$/u,
                message: "仅支持小写字母、数字和连字符",
              },
            ]}
          >
            <Input maxLength={80} placeholder="female-nen-master" />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
}
