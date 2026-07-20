import type { PipelineEvent } from "../../../server/shared/contracts.js";

interface LogStreamProps {
  events: readonly PipelineEvent[];
}

/** 紧凑事件流；完整证据始终留在本地 Run 目录。 */
export function LogStream({ events }: LogStreamProps): React.JSX.Element {
  return (
    <div className="log-stream" aria-live="polite">
      {events.length === 0 ? (
        <p>尚无活动 Run 事件。</p>
      ) : (
        events.slice(-30).map((event) => (
          <div key={event.sequence}>
            <time>{new Date(event.timestampUtc).toLocaleTimeString()}</time>
            <strong>{event.stage}</strong>
            <span>{event.message}</span>
          </div>
        ))
      )}
    </div>
  );
}
