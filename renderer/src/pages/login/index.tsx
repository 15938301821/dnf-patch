import { useState } from "react";
import { Button, Form, Input, Typography, message } from "antd";
import { KeyRound, LogIn, UserRound } from "lucide-react";
import { Navigate } from "react-router-dom";
import type { LoginInput } from "../../server/contracts.js";
import { apiMode } from "../../api/mode.js";
import { useAuthCommands } from "../../hooks/use-auth.js";
import { useAuthStore } from "../../stores/auth-store.js";
import { apiErrorMessage } from "../../utils/api-error.js";
import styles from "./index.module.scss";

export function LoginPage(): React.JSX.Element {
  const [submitting, setSubmitting] = useState(false);
  const status = useAuthStore((state) => state.status);
  const { login } = useAuthCommands();

  if (status === "authenticated") {
    return <Navigate replace to="/professions" />;
  }

  const submit = async (input: LoginInput): Promise<void> => {
    setSubmitting(true);
    try {
      await login(input);
    } catch (error) {
      void message.error(apiErrorMessage(error));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className={styles.page}>
      <section className={styles.panel}>
        <div className={styles.brand}>
          <span>DP</span>
          <div>
            <strong>DNF Patch Studio</strong>
            <small>视觉补丁工作台</small>
          </div>
        </div>
        <Typography.Title level={1}>登录</Typography.Title>
        <Form<LoginInput>
          layout="vertical"
          onFinish={(input) => void submit(input)}
          requiredMark={false}
        >
          <Form.Item
            label="账号"
            name="username"
            rules={[{ required: true, message: "请输入账号" }]}
          >
            <Input
              autoComplete="username"
              prefix={<UserRound aria-hidden="true" size={17} />}
              size="large"
            />
          </Form.Item>
          <Form.Item
            label="密码"
            name="password"
            rules={[{ required: true, message: "请输入密码" }]}
          >
            <Input.Password
              autoComplete="current-password"
              prefix={<KeyRound aria-hidden="true" size={17} />}
              size="large"
            />
          </Form.Item>
          <Button
            block
            htmlType="submit"
            icon={<LogIn size={17} />}
            loading={submitting}
            size="large"
            type="primary"
          >
            进入工作台
          </Button>
        </Form>
        <p className={styles.hint}>
          {apiMode === "mock"
            ? "Mock 模式可使用任意非空账号和密码。"
            : "使用服务端账号和密码登录。"}
        </p>
      </section>
      <aside className={styles.context}>
        <span>PATCH CONTROL SURFACE</span>
        <h2>从职业风格到可下载产物，统一在服务端任务中完成。</h2>
        <div className={styles.metrics}>
          <div>
            <strong>01</strong>
            <span>职业内容</span>
          </div>
          <div>
            <strong>02</strong>
            <span>实时预览</span>
          </div>
          <div>
            <strong>03</strong>
            <span>任务下载</span>
          </div>
        </div>
      </aside>
    </main>
  );
}
