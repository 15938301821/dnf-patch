import { ActionSelector } from "../components/action-selector.js";
import { EvidencePanel } from "../components/evidence-panel.js";
import { Hero } from "../components/hero.js";
import { RecentRuns } from "../components/recent-runs.js";
import { RunConfiguration } from "../components/run-configuration.js";
import type { PatchStudioController } from "../hooks/use-patch-studio.js";

interface DashboardPageProps {
  studio: PatchStudioController;
}

/** 默认生产工作台，完整保留已有本地离线 Run 行为。 */
export function DashboardPage({
  studio,
}: DashboardPageProps): React.JSX.Element {
  return (
    <>
      <Hero capabilities={studio.state?.capabilities ?? []} />
      <ActionSelector
        action={studio.form.action}
        onChange={(action) => studio.updateForm("action", action)}
      />
      <section className="workspace-grid">
        <RunConfiguration
          chooseDesignFile={studio.chooseDesignFile}
          clearSourceDesignPath={studio.clearSourceDesignPath}
          error={studio.error}
          form={studio.form}
          running={studio.running}
          state={studio.state}
          submit={studio.submit}
          summary={studio.summary}
          themes={studio.themes}
          updateForm={studio.updateForm}
        />
        <EvidencePanel events={studio.events} />
      </section>
      <RecentRuns
        repositoryRoot={studio.state?.repositoryRoot}
        runs={studio.state?.recentRuns ?? []}
      />
    </>
  );
}
