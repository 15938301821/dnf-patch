/**
 * @fileoverview 编排 `/settings` 的个人模型配置与后端资源导入状态。
 * 页面并行读取两个领域，模型表单只消费脱敏 ViewModel；表单校验通过后，Key 短暂进入写入
 * DTO，并在请求成功或失败后清空。资源导入仅提交后端任务并轮询权威状态，浏览器不访问目录或执行 Worker。
 */
import { useEffect, useState } from "react";
import { Alert, Button, Form, Skeleton, Tag, message } from "antd";
import { ImagePlus, ScanLine, Workflow } from "lucide-react";
import {
  createResourceImportJob,
  getModelConfiguration,
  getResourceImportOverview,
  saveModelConfiguration,
  type ModelConfiguration,
  type ResourceImportOverview,
  type ResourceImportStatus,
  type SaveModelConfigurationInput,
} from "../../api/index.js";
import { ModelRoleForm } from "../../components/model-role-form/index.js";
import { PageHeading } from "../../components/page-heading/index.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import styles from "./index.module.scss";

const RESOURCE_IMPORT_POLL_INTERVAL_MS = 1_500;

/** 将后端资源导入状态映射为界面文案，不推断任务是否最终成功。 */
function resourceImportStatusText(status: ResourceImportStatus): string {
  switch (status) {
    case "not-configured":
      return "未配置";
    case "idle":
      return "空闲";
    case "queued":
      return "已排队";
    case "running":
      return "导入中";
    case "failed":
      return "导入失败";
  }
}

/** 判断后端任务是否仍可能推进；只有这两个非终态允许页面继续轮询。 */
function isResourceImportPending(
  status: ResourceImportStatus | undefined,
): boolean {
  return status === "queued" || status === "running";
}

/** 将服务端导入来源模式映射为界面文案，不暴露资源路径。 */
function resourceImportModeText(mode: ResourceImportOverview["mode"]): string {
  return mode === "server-mirror" ? "服务器资源镜像" : "上传 Manifest";
}

/**
 * 展示固定模型角色配置和只读资源导入概况，并提供受控保存命令。
 * @returns 加载骨架、脱敏表单与后端任务控制区。
 */
export function SettingsPage(): React.JSX.Element {
  const [messageApi, messageContext] = message.useMessage();
  const [form] = Form.useForm<SaveModelConfigurationInput>();
  const [configuration, setConfiguration] = useState<ModelConfiguration>();
  const [resourceImport, setResourceImport] =
    useState<ResourceImportOverview>();
  const [loading, setLoading] = useState(true);
  const [importingResources, setImportingResources] = useState(false);
  const [savingConfiguration, setSavingConfiguration] = useState(false);

  useEffect(() => {
    let active = true;
    // 第一步：并行取得脱敏模型配置和资源状态；任一失败都不伪造默认服务端事实。
    void Promise.all([getModelConfiguration(), getResourceImportOverview()])
      .then(([value, importOverview]) => {
        if (active) {
          setConfiguration(value);
          setResourceImport(importOverview);
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
  }, [messageApi]);

  useEffect(() => {
    // 第二步：只把脱敏字段写入表单，读取 DTO 不含也不能恢复 API Key。
    if (!loading && configuration) {
      form.setFieldsValue(modelFormValues(configuration));
    }
  }, [configuration, form, loading]);

  useEffect(() => {
    if (!isResourceImportPending(resourceImport?.status)) {
      return;
    }
    let active = true;
    let timer: ReturnType<typeof setTimeout> | undefined;

    /** 当前任务仍未终结时安排下一次只读查询；请求失败后停止，避免无限错误通知。 */
    const scheduleRefresh = (): void => {
      timer = setTimeout(() => {
        void getResourceImportOverview()
          .then((overview) => {
            if (!active) {
              return;
            }
            setResourceImport(overview);
            if (isResourceImportPending(overview.status)) {
              scheduleRefresh();
            }
          })
          .catch((error: unknown) => {
            if (active) {
              void messageApi.error(apiErrorMessage(error));
            }
          });
      }, RESOURCE_IMPORT_POLL_INTERVAL_MS);
    };

    scheduleRefresh();
    return () => {
      active = false;
      if (timer !== undefined) {
        clearTimeout(timer);
      }
    };
  }, [messageApi, resourceImport?.lastJobId, resourceImport?.status]);

  /**
   * 校验并保存固定角色配置，随后用脱敏响应刷新表单。
   * @returns 校验通过后，保存和敏感输入清理完成时结算；校验失败保留输入供用户修正。
   */
  const saveConfiguration = async (): Promise<void> => {
    const input = await form.validateFields();
    setSavingConfiguration(true);
    try {
      const saved = await saveModelConfiguration(input);
      setConfiguration(saved);
      form.setFieldsValue(modelFormValues(saved));
      void messageApi.success("个人模型配置已安全保存");
    } catch (error) {
      void messageApi.error(apiErrorMessage(error));
    } finally {
      // 第三步：请求成功或失败都清除三个 Key 控件；表单校验失败尚未进入本请求阶段。
      form.resetFields([
        ["orchestrator", "apiKey"],
        ["spriteProcessor", "apiKey"],
        ["referenceGenerator", "apiKey"],
      ]);
      setSavingConfiguration(false);
    }
  };

  /**
   * 请求后端排队资源导入，并在接受后重新读取概况。
   * @returns 提交与刷新结束后结算；失败时客户端不得自行执行导入。
   */
  const startResourceImport = async (): Promise<void> => {
    setImportingResources(true);
    try {
      await createResourceImportJob();
      setResourceImport(await getResourceImportOverview());
      void messageApi.success("资源导入任务已提交给后端 Worker");
    } catch (error) {
      void messageApi.error(apiErrorMessage(error));
    } finally {
      setImportingResources(false);
    }
  };

  const importStatus = resourceImport?.status ?? "not-configured";

  return (
    <div className={styles.page}>
      {messageContext}
      <PageHeading
        description="配置当前账号用于任务调度、参考图生成与精灵图处理的固定角色模型。"
        title="模型设置"
      />

      <div className={styles.layout}>
        <section className={styles.workspace}>
          {loading ? (
            <Skeleton active paragraph={{ rows: 6 }} />
          ) : (
            <Form<SaveModelConfigurationInput>
              className={styles.roles}
              form={form}
              layout="vertical"
              requiredMark={false}
            >
              <ModelRoleForm
                configuration={configuration?.orchestrator}
                description="读取职业、风格、资源计划与门禁结果，拆分步骤、调度后端任务并汇总状态。"
                icon={<Workflow aria-hidden="true" size={19} />}
                role="orchestrator"
                sequence="01 / ORCHESTRATE"
                tags={["任务规划", "步骤调度", "结果汇总"]}
                title="总任务调度"
              />
              <ModelRoleForm
                configuration={configuration?.referenceGenerator}
                description="组合职业风格、源精灵图与生成模板，输出供目标帧处理使用的参考图。"
                icon={<ImagePlus aria-hidden="true" size={19} />}
                role="referenceGenerator"
                sequence="02 / REFERENCE"
                tags={["风格约束", "源帧语义", "参考图生成"]}
                title="参考图生成"
              />
              <ModelRoleForm
                configuration={configuration?.spriteProcessor}
                description="审核固定工具链的适配计划与验证结果，不直接接收或执行浏览器命令。"
                icon={<ScanLine aria-hidden="true" size={19} />}
                role="spriteProcessor"
                sequence="03 / SPRITE"
                tags={["适配计划", "证据复核", "结构约束"]}
                title="精灵图处理"
              />
              <Button
                className={styles["save-models"] ?? ""}
                loading={savingConfiguration}
                onClick={() => void saveConfiguration()}
                type="primary"
              >
                保存模型配置
              </Button>
            </Form>
          )}
        </section>

        <aside className={styles.policy}>
          <Alert
            description="API Key 仅在保存时通过当前登录会话提交，服务端加密后绑定当前用户；读取接口不会返回 Key。"
            showIcon
            title="配置边界"
            type="info"
          />
          <section className={styles["resource-import"]}>
            <div className={styles["resource-import-head"]}>
              <div>
                <span>资源导入</span>
                <strong>后端 Worker</strong>
              </div>
              <Tag className={styles["resource-import-tag"] ?? ""}>
                {resourceImportStatusText(importStatus)}
              </Tag>
            </div>
            <dl className={styles["resource-import-meta"]}>
              <div>
                <dt>导入模式</dt>
                <dd>
                  {resourceImport
                    ? resourceImportModeText(resourceImport.mode)
                    : "等待后端状态"}
                </dd>
              </div>
              <div>
                <dt>资源根</dt>
                <dd>
                  {resourceImport?.resourceRootConfigured ? "已配置" : "未配置"}
                </dd>
              </div>
              <div>
                <dt>资源版本</dt>
                <dd>{resourceImport?.resourceVersion ?? "未导入"}</dd>
              </div>
              <div>
                <dt>最近导入</dt>
                <dd>
                  {resourceImport?.lastImportedAt
                    ? new Date(resourceImport.lastImportedAt).toLocaleString()
                    : "暂无记录"}
                </dd>
              </div>
            </dl>
            <p>{resourceImport?.message ?? "后端尚未返回资源导入状态。"}</p>
            <Button
              block
              disabled={
                importStatus === "not-configured" ||
                isResourceImportPending(importStatus)
              }
              loading={importingResources}
              onClick={() => void startResourceImport()}
            >
              触发后端资源导入
            </Button>
          </section>
          <div className={styles["role-status"]}>
            <span>01 总任务调度</span>
            <strong>
              {configuration?.orchestrator.model ?? "gpt-5.6-sol"}
            </strong>
            <small>
              {configuration?.orchestrator.keyConfigured
                ? "Key 已配置"
                : "Key 未配置"}
            </small>
          </div>
          <div className={styles["role-status"]}>
            <span>02 参考图生成</span>
            <strong>
              {configuration?.referenceGenerator.model ?? "gpt-image-2"}
            </strong>
            <small>
              {configuration?.referenceGenerator.keyConfigured
                ? "Key 已配置"
                : "Key 未配置"}
            </small>
          </div>
          <div className={styles["role-status"]}>
            <span>03 精灵图处理</span>
            <strong>{configuration?.spriteProcessor.model ?? "gpt-5.5"}</strong>
            <small>
              {configuration?.spriteProcessor.keyConfigured
                ? "Key 已配置"
                : "Key 未配置"}
            </small>
          </div>
          <p>
            图片工具 CLI 由后端 Worker
            的受控工具注册表提供，前端不保存本机路径，也不直接执行工具。
          </p>
          <p>
            模型精修不能单独证明产物可用；后端仍须验证帧几何、alpha、格式、结构和未授权差异。
          </p>
        </aside>
      </div>
    </div>
  );
}

/** 把脱敏读取 ViewModel 转为不含 API Key 的可编辑表单值。 */
function modelFormValues(
  configuration: ModelConfiguration,
): SaveModelConfigurationInput {
  return {
    orchestrator: editableRole(configuration.orchestrator),
    spriteProcessor: editableRole(configuration.spriteProcessor),
    referenceGenerator: editableRole(configuration.referenceGenerator),
  };
}

/** 保留单个角色的 endpoint 与模型 ID，刻意不构造 Key 字段。 */
function editableRole(
  configuration: ModelConfiguration[keyof ModelConfiguration],
): SaveModelConfigurationInput[keyof SaveModelConfigurationInput] {
  return {
    endpoint: configuration.endpoint,
    model: configuration.model,
  };
}
