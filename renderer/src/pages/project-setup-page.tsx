import { RefreshCw } from "lucide-react";
import { FrameCompare } from "../components/frame-compare.js";
import type { PatchStudioController } from "../hooks/use-patch-studio.js";
import type { ServerConnectionController } from "../hooks/use-server-connection.js";

interface ProjectSetupPageProps {
  studio: PatchStudioController;
  server: ServerConnectionController;
}

/** 对照本地职业事实源和服务端项目元数据，不上传或改写领域资产。 */
export function ProjectSetupPage({
  studio,
  server,
}: ProjectSetupPageProps): React.JSX.Element {
  return (
    <section className="page-stack">
      <header className="page-heading">
        <div>
          <p className="kicker">PROJECT SETUP</p>
          <h1>项目与事实源</h1>
          <p>
            职业规则、manifest 与 Prompt
            保持在本地仓库；服务端只登记元数据、哈希和运行状态。
          </p>
        </div>
        <button
          className="icon-command"
          disabled={server.state?.mode !== "connected"}
          onClick={() => void server.refreshProjects()}
          title="刷新服务端项目"
          type="button"
        >
          <RefreshCw aria-hidden="true" size={17} />
          <span>刷新</span>
        </button>
      </header>

      <div className="summary-band">
        <div>
          <span>本地职业</span>
          <strong>{studio.state?.professions.length ?? 0}</strong>
        </div>
        <div>
          <span>服务项目</span>
          <strong>{server.projects.length}</strong>
        </div>
        <div>
          <span>仓库状态</span>
          <strong>{studio.state ? "已定位" : "加载中"}</strong>
        </div>
        <div>
          <span>部署权限</span>
          <strong>永久禁用</strong>
        </div>
      </div>

      <div className="project-layout">
        <section className="panel data-panel">
          <div className="panel-heading compact">
            <div>
              <p className="kicker">LOCAL DOMAIN SOURCES</p>
              <h2>职业清单</h2>
            </div>
          </div>
          <div className="entity-list">
            {(studio.state?.professions ?? []).map((profession) => (
              <article key={profession.name}>
                <div>
                  <strong>{profession.name}</strong>
                  <span>{profession.themes.length} 个主题</span>
                </div>
                <small>
                  {profession.hasManifest ? "manifest 已登记" : "缺少 manifest"}
                </small>
              </article>
            ))}
          </div>
        </section>

        <section className="panel data-panel">
          <div className="panel-heading compact">
            <div>
              <p className="kicker">SERVER METADATA</p>
              <h2>项目注册</h2>
            </div>
            <span>{server.state?.mode ?? "offline"}</span>
          </div>
          <div className="entity-list">
            {server.projects.length === 0 ? (
              <p className="table-empty">当前没有可读取的服务端项目。</p>
            ) : (
              server.projects.map((project) => (
                <article key={project.id}>
                  <div>
                    <strong>{project.displayName}</strong>
                    <span>v{project.version}</span>
                  </div>
                  <small>
                    {project.archived ? "已归档" : project.canonicalName}
                  </small>
                </article>
              ))
            )}
          </div>
          {server.error ? <p className="inline-error">{server.error}</p> : null}
        </section>
      </div>

      <section className="panel compare-panel">
        <div className="panel-heading compact">
          <div>
            <p className="kicker">FRAME EVIDENCE</p>
            <h2>帧对照槽位</h2>
          </div>
          <span>只读</span>
        </div>
        <FrameCompare sourceLabel="尚未选择源帧" outputLabel="尚无运行帧证据" />
      </section>
    </section>
  );
}
