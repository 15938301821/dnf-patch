import { useEffect, useState } from "react";
import { Alert, Button, Form, Skeleton, message } from "antd";
import { ImagePlus, Save, ScanLine, Workflow } from "lucide-react";
import {
  getModelConfiguration,
  saveModelConfiguration,
  type ModelConfiguration,
  type SaveModelConfigurationInput,
} from "../../api/index.js";
import { ModelRoleForm } from "../../components/model-role-form/index.js";
import { PageHeading } from "../../components/page-heading/index.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import styles from "./index.module.scss";

export function SettingsPage(): React.JSX.Element {
  const [form] = Form.useForm<SaveModelConfigurationInput>();
  const [messageApi, messageContext] = message.useMessage();
  const [configuration, setConfiguration] = useState<ModelConfiguration>();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let active = true;
    void getModelConfiguration()
      .then((value) => {
        if (active) {
          setConfiguration(value);
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

  const submit = async (): Promise<void> => {
    setSaving(true);
    try {
      const saved = await saveModelConfiguration(await form.validateFields());
      setConfiguration(saved);
      form.resetFields([
        ["orchestrator", "apiKey"],
        ["spriteProcessor", "apiKey"],
        ["referenceGenerator", "apiKey"],
      ]);
      void messageApi.success("模型配置已保存");
    } catch (error) {
      if (!(error instanceof Error && "errorFields" in error)) {
        void messageApi.error(apiErrorMessage(error));
      }
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className={styles.page}>
      {messageContext}
      <PageHeading
        description="分别配置任务调度、参考图生成与精灵图处理模型。Key 保存后不再返回明文。"
        title="模型设置"
      />

      <div className={styles.layout}>
        <section className={styles.workspace}>
          {loading ? (
            <Skeleton active paragraph={{ rows: 6 }} />
          ) : (
            <Form<SaveModelConfigurationInput>
              form={form}
              initialValues={{
                orchestrator: {
                  endpoint: configuration?.orchestrator.endpoint,
                  model: configuration?.orchestrator.model ?? "gpt-5.6-sol",
                },
                spriteProcessor: {
                  endpoint: configuration?.spriteProcessor.endpoint,
                  model: configuration?.spriteProcessor.model ?? "gpt-5.5",
                },
                referenceGenerator: {
                  endpoint: configuration?.referenceGenerator.endpoint,
                  model:
                    configuration?.referenceGenerator.model ?? "gpt-image-2",
                },
              }}
              layout="vertical"
              onFinish={() => void submit()}
              requiredMark={false}
            >
              <div className={styles.roles}>
                <ModelRoleForm
                  configuration={configuration?.orchestrator}
                  description="读取职业、风格、资源计划与门禁结果，拆分步骤、调度后端任务并汇总状态。"
                  icon={<Workflow aria-hidden="true" size={19} />}
                  modelPlaceholder="gpt-5.6-sol"
                  name="orchestrator"
                  sequence="01 / ORCHESTRATE"
                  tags={["任务规划", "步骤调度", "结果汇总"]}
                  title="总任务调度"
                />
                <ModelRoleForm
                  configuration={configuration?.referenceGenerator}
                  description="组合职业风格、源精灵图与生成模板，输出供目标帧处理使用的参考图。"
                  icon={<ImagePlus aria-hidden="true" size={19} />}
                  modelPlaceholder="gpt-image-2"
                  name="referenceGenerator"
                  sequence="02 / REFERENCE"
                  tags={["风格约束", "源帧语义", "参考图生成"]}
                  title="参考图生成"
                />
                <ModelRoleForm
                  configuration={configuration?.spriteProcessor}
                  description="结合风格、技能源帧、参考图和后端图片工具 CLI 生成目标帧，再精修几何、透明度与细节。"
                  icon={<ScanLine aria-hidden="true" size={19} />}
                  modelPlaceholder="gpt-5.5"
                  name="spriteProcessor"
                  sequence="03 / SPRITE"
                  tags={["目标帧生成", "CLI 精修", "结构适配"]}
                  title="精灵图处理"
                />
              </div>
              <div className={styles.actions}>
                <Button
                  htmlType="submit"
                  icon={<Save size={16} />}
                  loading={saving}
                  type="primary"
                >
                  保存三角色配置
                </Button>
              </div>
            </Form>
          )}
        </section>

        <aside className={styles.policy}>
          <Alert
            description="Access Token 仅保存在内存中，Refresh Token 应由后端设置为 HttpOnly Cookie。"
            showIcon
            title="会话边界"
            type="info"
          />
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
