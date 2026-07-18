import { ActionSelector } from "./components/action-selector.js";
import { EvidencePanel } from "./components/evidence-panel.js";
import { Hero } from "./components/hero.js";
import { RecentRuns } from "./components/recent-runs.js";
import { RunConfiguration } from "./components/run-configuration.js";
import { Topbar } from "./components/topbar.js";
import { usePatchStudio } from "./hooks/use-patch-studio.js";

/** 页面组合层；业务状态和 IPC 副作用集中在 `usePatchStudio()`。 */
export function App(): React.JSX.Element {
  const studio = usePatchStudio();

  return (
    <div className="app-shell">
      <Topbar />
      <main>
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
      </main>
    </div>
  );
}
