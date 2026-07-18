import type { PipelineEvent } from "../../../shared/contracts.js";

interface EvidencePanelProps {
  events: readonly PipelineEvent[];
}

/** 按最新优先展示当前 Run 的最近事件；完整历史保存在 Run 目录。 */
export function EvidencePanel({
  events,
}: EvidencePanelProps): React.JSX.Element {
  return (
    <aside className="panel evidence-panel">
      <div className="panel-heading compact">
        <div>
          <p className="kicker">LIVE EVIDENCE</p>
          <h2>Run 事件</h2>
        </div>
        <span>{events.length}</span>
      </div>
      <div className="event-list">
        {events.length === 0 ? (
          <div className="empty-state">
            <span>◇</span>
            <p>启动 Run 后，这里会显示冻结、模型、工具与门禁事件。</p>
          </div>
        ) : (
          [...events].reverse().map((event) => (
            <article className={`event ${event.level}`} key={event.sequence}>
              <div>
                <span>{String(event.sequence).padStart(3, "0")}</span>
                <strong>{event.stage}</strong>
              </div>
              <p>{event.message}</p>
              <time>{new Date(event.timestampUtc).toLocaleTimeString()}</time>
            </article>
          ))
        )}
      </div>
    </aside>
  );
}
