/**
 * @fileoverview 提供匿名用户登录页与已认证用户的入口重定向。
 *
 * 根路由渲染本页，表单把一次性账号密码交给认证 Hook，成功后 Store 状态驱动跳转；页面不
 * 直接访问 Axios，也不持久化凭据。Mock API 仅是前端替身，不代表真实认证服务可用；提交
 * 期间锁定按钮，失败只展示安全错误且不得伪造会话。
 */
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

/**
 * 渲染受控登录表单并按认证 Store 状态跳转。
 *
 * @returns 匿名状态下的登录界面；已认证时返回替换历史的职业页导航。
 */
export function LoginPage(): React.JSX.Element {
  const [submitting, setSubmitting] = useState(false);
  const status = useAuthStore((state) => state.status);
  const { login } = useAuthCommands();

  if (status === "authenticated") {
    return <Navigate replace to="/professions" />;
  }

  /**
   * 提交 Ant Design 已校验的登录值，并把错误映射为页面消息。
   *
   * @param input 用户本次输入的账号密码，不写入 Store 或浏览器存储。
   * @returns 认证请求与提交状态清理完成后结算。
   */
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
