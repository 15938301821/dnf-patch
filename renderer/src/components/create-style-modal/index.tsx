import { Form, Input, Modal, type FormInstance } from "antd";
import type {
  CreateProfessionStyleInput,
  ProfessionSkillSummary,
} from "../../api/contracts.js";
import { SkillScopePicker } from "../skill-scope-picker/index.js";
import styles from "./index.module.scss";

const initialValues: CreateProfessionStyleInput = {
  name: "",
  description: "",
  agent: "",
  prompt: "",
  selectedSkillIds: [],
};

interface CreateStyleModalProps {
  confirmLoading: boolean;
  form: FormInstance<CreateProfessionStyleInput>;
  onCancel: () => void;
  onConfirm: () => void;
  open: boolean;
  skills: readonly ProfessionSkillSummary[];
  skillsLoading: boolean;
}

export function CreateStyleModal({
  confirmLoading,
  form,
  onCancel,
  onConfirm,
  open,
  skills,
  skillsLoading,
}: CreateStyleModalProps): React.JSX.Element {
  return (
    <Modal
      confirmLoading={confirmLoading}
      onCancel={onCancel}
      onOk={onConfirm}
      open={open}
      title="新建职业风格"
      width={720}
    >
      <Form<CreateProfessionStyleInput>
        className={styles.form ?? ""}
        form={form}
        initialValues={initialValues}
        layout="vertical"
        requiredMark={false}
      >
        <div className={styles.basics}>
          <Form.Item
            label="风格名称"
            name="name"
            rules={[{ required: true, message: "请输入风格名称" }]}
          >
            <Input maxLength={100} />
          </Form.Item>
          <Form.Item label="风格描述" name="description">
            <Input.TextArea maxLength={500} rows={3} />
          </Form.Item>
          <Form.Item label="Agent" name="agent">
            <Input.TextArea maxLength={20_000} rows={4} />
          </Form.Item>
          <Form.Item label="Prompt" name="prompt">
            <Input.TextArea maxLength={20_000} rows={4} />
          </Form.Item>
        </div>
        <Form.Item
          extra="技能事实来自后端职业目录；资源尚未核验的技能仍可保存为设计稿。"
          label="技能范围"
          name="selectedSkillIds"
          rules={[
            {
              type: "array",
              min: 1,
              message: "至少选择一个技能",
            },
          ]}
        >
          <SkillScopePicker loading={skillsLoading} skills={skills} />
        </Form.Item>
      </Form>
    </Modal>
  );
}
