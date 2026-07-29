/**
 * @fileoverview 编排 `/professions` 的职业主列表、所选职业风格、草稿删除和新建职业弹窗。
 * 路由查询参数可指定初始职业；页面先加载职业，再随选择请求风格，并通过类型化 API 创建职业或删除风格。
 * 副作用是受认证请求、导航与消息；请求卸载后必须忽略过期结果，客户端不生成技能或资源事实。
 */
import { useEffect, useState } from "react";
import {
  Button,
  Empty,
  Form,
  Input,
  Modal,
  Popconfirm,
  Skeleton,
  Tooltip,
  Typography,
  message,
} from "antd";
import { ArrowRight, Layers3, Plus, Trash2 } from "lucide-react";
import { useNavigate, useSearchParams } from "react-router-dom";
import {
  createProfession,
  deleteProfession,
  deleteProfessionStyle,
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

/**
 * 渲染职业选择、对应风格列表与新建职业流程。
 * @returns 区分加载、空集合和可操作状态的职业工作区。
 */
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
  const [deletingProfessionId, setDeletingProfessionId] = useState("");
  const [deletingStyleId, setDeletingStyleId] = useState("");

  useEffect(() => {
    let active = true;
    // 第一步：建立主列表和查询参数指定的初始选择；卸载后不接受过期结果。
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
    // 第二步：选择变化后只加载该职业风格；旧选择的迟到结果不得覆盖当前列表。
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

  /**
   * 校验并创建职业，随后用服务端摘要更新主列表并关闭弹窗。
   * @returns 全流程结束后结算；校验或请求失败时禁止关闭弹窗和重置输入。
   */
  const submitProfession = async (): Promise<void> => {
    setSaving(true);
    try {
      // 第三步：创建响应已是完整摘要，成功态不能再被一次冗余列表刷新阻塞。
      const created = await createProfession(
        await professionForm.validateFields(),
      );
      setProfessions((current) => [
        created,
        ...current.filter((item) => item.id !== created.id),
      ]);
      setSelectedId(created.id);
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

  /**
   * 删除服务端确认可撤销的空职业，并把选择移动到相邻职业。
   * @param professionId 用户在职业行确认弹窗中选择的稳定职业 ID。
   * @returns 请求结算后完成；失败时保留职业、选择与右侧风格列表。
   */
  const deleteSelectedProfession = async (
    professionId: string,
  ): Promise<void> => {
    setDeletingProfessionId(professionId);
    try {
      await deleteProfession(professionId);
      const deletedIndex = professions.findIndex(
        (profession) => profession.id === professionId,
      );
      const remaining = professions.filter(
        (profession) => profession.id !== professionId,
      );
      const next = remaining[Math.min(deletedIndex, remaining.length - 1)];
      setProfessions(remaining);
      if (selectedId === professionId) {
        setSelectedId(next?.id ?? "");
        setStylesList([]);
      }
      void messageApi.success("职业已删除");
    } catch (error: unknown) {
      void messageApi.error(apiErrorMessage(error));
    } finally {
      setDeletingProfessionId("");
    }
  };

  /**
   * 删除服务端确认可撤销的风格，并同步当前职业卡片与派生计数。
   * @param styleId 用户在确认弹窗中选择的稳定风格 ID。
   * @returns 请求结算后完成；失败时保留原列表，避免客户端提前隐藏受保护内容。
   */
  const deleteStyle = async (styleId: string): Promise<void> => {
    setDeletingStyleId(styleId);
    try {
      await deleteProfessionStyle(selectedId, styleId);
      setStylesList((current) =>
        current.filter((style) => style.id !== styleId),
      );
      setProfessions((current) =>
        current.map((profession) =>
          profession.id === selectedId
            ? {
                ...profession,
                styleCount: Math.max(0, profession.styleCount - 1),
              }
            : profession,
        ),
      );
      void messageApi.success("职业风格已删除");
    } catch (error: unknown) {
      void messageApi.error(apiErrorMessage(error));
    } finally {
      setDeletingStyleId("");
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
            <div className={styles["profession-list"]} role="list">
              {professions.map((profession) => (
                <div
                  className={
                    profession.id === selectedId
                      ? styles["profession-active"]
                      : styles.profession
                  }
                  key={profession.id}
                  role="listitem"
                >
                  <button
                    aria-label={`选择职业${profession.name}`}
                    className={styles["profession-select"]}
                    onClick={() => setSelectedId(profession.id)}
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
                  {profession.publishStatus === "private" ||
                  profession.publishStatus === "rejected" ? (
                    <Popconfirm
                      cancelText="取消"
                      description="仅空职业可删除；技能目录或风格存在时服务端会拒绝。"
                      okButtonProps={{ danger: true }}
                      okText="删除"
                      onConfirm={() =>
                        void deleteSelectedProfession(profession.id)
                      }
                      title={`删除职业“${profession.name}”？`}
                    >
                      <Button
                        aria-label={`删除职业${profession.name}`}
                        className={styles["profession-delete"] ?? ""}
                        danger
                        icon={<Trash2 size={15} />}
                        loading={deletingProfessionId === profession.id}
                        title="删除职业"
                        type="text"
                      />
                    </Popconfirm>
                  ) : (
                    <Tooltip title="审核中或已发布的职业不可删除">
                      <Button
                        aria-label={`删除职业${profession.name}`}
                        className={styles["profession-delete"] ?? ""}
                        danger
                        disabled
                        icon={<Trash2 size={15} />}
                        type="text"
                      />
                    </Tooltip>
                  )}
                </div>
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
                  <div className={styles["style-actions"]}>
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
                    {style.publishStatus === "private" ||
                    style.publishStatus === "rejected" ? (
                      <Popconfirm
                        cancelText="取消"
                        description="删除后无法恢复；已有生产记录时服务端仍会拒绝。"
                        okButtonProps={{ danger: true }}
                        okText="删除"
                        onConfirm={() => void deleteStyle(style.id)}
                        title={`删除“${style.name}”？`}
                      >
                        <Button
                          aria-label={`删除职业风格${style.name}`}
                          danger
                          icon={<Trash2 size={16} />}
                          loading={deletingStyleId === style.id}
                          title="删除职业风格"
                          type="text"
                        />
                      </Popconfirm>
                    ) : (
                      <Tooltip title="审核中或已发布的风格不可删除">
                        <Button
                          aria-label={`删除职业风格${style.name}`}
                          danger
                          disabled
                          icon={<Trash2 size={16} />}
                          type="text"
                        />
                      </Tooltip>
                    )}
                  </div>
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
