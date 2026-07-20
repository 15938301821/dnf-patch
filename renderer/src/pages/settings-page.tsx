import { RefreshCw, Server, ShieldCheck } from "lucide-react";
import type { PatchStudioController } from "../hooks/use-patch-studio.js";
import type { ServerConnectionController } from "../hooks/use-server-connection.js";

interface SettingsPageProps {
  studio: PatchStudioController;
  server: ServerConnectionController;
}

/** 只读显示主进程解析后的身份与能力，不显示 URL 凭据、令牌或 API Key。 */
export function SettingsPage({
  studio,
  server,
}: SettingsPageProps): React.JSX.Element {
  return (
    <section className="page-stack">
      <header className="page-heading">
        <div>
          <p className="kicker">CONTROL PLANE SETTINGS</p>
          <h1>连接与模型</h1>
          <p>
            连接凭据由 Electron 主进程持有；renderer
            只能探测经过契约裁剪的服务状态。
          </p>
        </div>
        <button
          className="icon-command"
          disabled={server.probing}
          onClick={() => void server.probe()}
          type="button"
        >
          <RefreshCw aria-hidden="true" size={17} />
          <span>{server.probing ? "探测中" : "重新探测"}</span>
        </button>
      </header>

      <div className="settings-layout">
        <section className="panel settings-section">
          <div className="settings-title">
            <Server aria-hidden="true" size={19} />
            <div>
              <strong>后端服务</strong>
              <span>版本化 REST 与 Run 事件通道</span>
            </div>
          </div>
          <dl>
            <div>
              <dt>模式</dt>
              <dd>{server.state?.mode ?? "未探测"}</dd>
            </div>
            <div>
              <dt>端点身份</dt>
              <dd>{server.state?.endpointIdentity ?? "未解析"}</dd>
            </div>
            <div>
              <dt>MySQL</dt>
              <dd>{server.state?.health?.database ?? "未知"}</dd>
            </div>
            <div>
              <dt>认证</dt>
              <dd>{server.state?.configured ? "主进程已配置" : "未配置"}</dd>
            </div>
          </dl>
          <p className="settings-detail">
            {server.state?.detail ?? "等待主进程状态。"}
          </p>
          {server.error ? <p className="inline-error">{server.error}</p> : null}
        </section>

        <section className="panel settings-section">
          <div className="settings-title">
            <ShieldCheck aria-hidden="true" size={19} />
            <div>
              <strong>固定模型职责</strong>
              <span>运行时不可由表单改写</span>
            </div>
          </div>
          <div className="model-settings">
            {(studio.state?.capabilities ?? []).map((capability) => (
              <article key={capability.role}>
                <div>
                  <span>{capability.role}</span>
                  <strong>{capability.requestedModel}</strong>
                </div>
                <small>
                  {capability.available ? "已配置" : "本地 Mock 可用"}
                </small>
              </article>
            ))}
          </div>
        </section>
      </div>

      <section className="policy-strip">
        <strong>不可提升边界</strong>
        <span>部署授权 false</span>
        <span>官方 NPK 只读</span>
        <span>模型不能选择工具</span>
        <span>服务离线保留本地模式</span>
      </section>
    </section>
  );
}
