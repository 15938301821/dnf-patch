import { JobCard } from "../components/job-card.js";
import { LogStream } from "../components/log-stream.js";
import { ProgressRing } from "../components/progress-ring.js";
import type { PatchStudioController } from "../hooks/use-patch-studio.js";
import { toJobDisplayStatus } from "../utils/run-format.js";

interface MonitorPageProps {
  studio: PatchStudioController;
}

/** 汇总真实本地 Run 与当前会话事件，不从事件数量推断发布或覆盖完成。 */
export function MonitorPage({ studio }: MonitorPageProps): React.JSX.Element {
  const runs = studio.state?.recentRuns ?? [];
  const completed = runs.filter((run) =>
    ["passed", "committed-with-warnings"].includes(run.status),
  ).length;
  const completion = runs.length === 0 ? 0 : (completed / runs.length) * 100;

  return (
    <section className="page-stack">
      <header className="page-heading">
        <div>
          <p className="kicker">RUN MONITOR</p>
          <h1>运行监控</h1>
          <p>
            本地 Run
            证据是离线工作流事实源；服务端通知不替代事件持久化和发布门禁。
          </p>
        </div>
        <ProgressRing label="近期完成" value={completion} />
      </header>

      <div className="monitor-layout">
        <section className="panel data-panel">
          <div className="panel-heading compact">
            <div>
              <p className="kicker">RECENT JOBS</p>
              <h2>Run 队列</h2>
            </div>
            <span>{runs.length}</span>
          </div>
          <div className="job-list">
            {runs.length === 0 ? (
              <p className="table-empty">尚无本地 Run。</p>
            ) : (
              runs.map((run) => (
                <JobCard
                  key={run.runId}
                  stage={run.currentStage}
                  status={toJobDisplayStatus(run.status)}
                  title={run.runId}
                />
              ))
            )}
          </div>
        </section>

        <section className="panel data-panel log-panel">
          <div className="panel-heading compact">
            <div>
              <p className="kicker">LIVE LOG</p>
              <h2>当前事件流</h2>
            </div>
            <span>{studio.events.length}</span>
          </div>
          <LogStream events={studio.events} />
        </section>
      </div>
    </section>
  );
}
