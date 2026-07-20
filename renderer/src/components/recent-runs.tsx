import type { RunSummary } from "../../../server/shared/contracts.js";
import { statusLabel } from "../utils/run-format.js";

interface RecentRunsProps {
  repositoryRoot: string | undefined;
  runs: readonly RunSummary[];
}

/** 展示本地持久化 Run 摘要，不提供删除或修改审计证据的操作。 */
export function RecentRuns({
  repositoryRoot,
  runs,
}: RecentRunsProps): React.JSX.Element {
  return (
    <section className="panel recent-panel">
      <div className="panel-heading compact">
        <div>
          <p className="kicker">LOCAL AUDIT TRAIL</p>
          <h2>最近 Run</h2>
        </div>
        <span>{repositoryRoot ?? "正在定位仓库…"}</span>
      </div>
      <div className="run-table">
        {runs.length === 0 ? (
          <p className="table-empty">尚无本地 Run 证据。</p>
        ) : (
          runs.map((run) => (
            <div className="run-row" key={run.runId}>
              <strong>{run.runId}</strong>
              <span>{run.action}</span>
              <span>{run.provider}</span>
              <span>{run.currentStage}</span>
              <b className={`status-pill status-${run.status}`}>
                {statusLabel(run.status)}
              </b>
            </div>
          ))
        )}
      </div>
    </section>
  );
}
