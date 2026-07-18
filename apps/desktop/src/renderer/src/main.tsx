import { StrictMode, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  runRequestSchema,
  type DesktopState,
  type PipelineAction,
  type PipelineEvent,
  type PipelineProvider,
  type RunSummary,
} from "../../shared/contracts.js";
import "./styles.css";

const actions: Array<{
  id: PipelineAction;
  eyebrow: string;
  title: string;
  description: string;
}> = [
  {
    id: "create-profession",
    eyebrow: "PROMPT DOMAIN",
    title: "创建职业",
    description: "把设计文本拆分为职业稳定语义与逐技能 Prompt。",
  },
  {
    id: "create-theme",
    eyebrow: "STYLE LAYER",
    title: "创建风格",
    description: "在职业 Prompt 之上创建有序主题增量，不扩张技能范围。",
  },
  {
    id: "generate-patch",
    eyebrow: "AGENTIC BUILD",
    title: "生成补丁",
    description: "按固定 profile 执行 inventory、模型、Aseprite、NPK 与 BPK。",
  },
  {
    id: "validate-only",
    eyebrow: "READ-ONLY GATE",
    title: "验证项目",
    description: "执行 PowerShell 源码与项目总门禁，不写补丁或部署目录。",
  },
];

const defaultProfile = "weaponmaster.vergil.illusionslash.agentic-v1";

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function newRunId(): string {
  const suffix = crypto.randomUUID().replaceAll("-", "").slice(0, 10);
  return `run-${Date.now().toString(36)}-${suffix}`;
}

function splitSkills(value: string): string[] {
  const result: string[] = [];
  const keys = new Set<string>();
  for (const candidate of value.split(/[\n,，]+/u)) {
    const skill = candidate.trim();
    const key = skill.normalize("NFC").toLocaleLowerCase();
    if (skill && !keys.has(key)) {
      keys.add(key);
      result.push(skill);
    }
  }
  return result;
}

function statusLabel(status: RunSummary["status"]): string {
  const labels: Record<RunSummary["status"], string> = {
    planning: "规划中",
    planned: "已规划",
    blocked: "已阻断",
    failed: "失败",
    passed: "通过",
    "committed-with-warnings": "已提交 · 有警告",
    "awaiting-human-review": "等待人工审核",
  };
  return labels[status];
}

function App(): React.JSX.Element {
  const [state, setState] = useState<DesktopState>();
  const [action, setAction] = useState<PipelineAction>("create-theme");
  const [provider, setProvider] = useState<PipelineProvider>("mock");
  const [profession, setProfession] = useState("剑魂");
  const [theme, setTheme] = useState("Vergil（维吉尔）暗蓝幻影主题");
  const [skills, setSkills] = useState("幻影剑舞");
  const [designText, setDesignText] = useState("");
  const [sourceDesignPath, setSourceDesignPath] = useState("");
  const [profileId, setProfileId] = useState(defaultProfile);
  const [outputBaseName, setOutputBaseName] = useState(
    "weaponmaster-vergil-dark-blue",
  );
  const [outputVersion, setOutputVersion] = useState("1");
  const [execute, setExecute] = useState(false);
  const [allowNetwork, setAllowNetwork] = useState(false);
  const [generateImageReferences, setGenerateImageReferences] = useState(false);
  const [events, setEvents] = useState<PipelineEvent[]>([]);
  const [summary, setSummary] = useState<RunSummary>();
  const [error, setError] = useState("");
  const [running, setRunning] = useState(false);

  async function loadState(): Promise<void> {
    setState(await window.dnfPatch.getState());
  }

  useEffect(() => {
    const dispose = window.dnfPatch.onRunEvent((event) => {
      setEvents((current) => [...current.slice(-99), event]);
    });
    void loadState().catch((caught: unknown) => {
      setError(errorMessage(caught));
    });
    return dispose;
  }, []);

  const themes = useMemo(
    () =>
      state?.professions.find((item) => item.name === profession)?.themes ?? [],
    [profession, state],
  );
  const requiresDesign =
    action === "create-profession" || action === "create-theme";
  const requiresTheme =
    action === "create-theme" || action === "generate-patch";
  const isGenerate = action === "generate-patch";

  async function chooseDesignFile(): Promise<void> {
    try {
      const path = await window.dnfPatch.selectDesignFile();
      if (path) {
        setSourceDesignPath(path);
        setDesignText("");
      }
    } catch (caught) {
      setError(errorMessage(caught));
    }
  }

  async function submit(): Promise<void> {
    setRunning(true);
    setError("");
    setSummary(undefined);
    setEvents([]);
    try {
      const request = runRequestSchema.parse({
        schemaVersion: 1,
        runId: newRunId(),
        action,
        provider,
        profession: profession.trim(),
        ...(requiresTheme ? { theme: theme.trim() } : {}),
        ...(requiresDesign && designText.trim()
          ? { designText: designText.trim() }
          : {}),
        ...(requiresDesign && sourceDesignPath ? { sourceDesignPath } : {}),
        ...(isGenerate ? { profileId: profileId.trim() } : {}),
        selectedSkills: splitSkills(skills),
        execute,
        resume: false,
        allowNetwork,
        generateImageReferences: isGenerate && generateImageReferences,
        outputBaseName: outputBaseName.trim(),
        outputVersion: outputVersion.trim(),
        deploymentAuthorized: false,
      });
      const response = await window.dnfPatch.startRun(request);
      setSummary(response.summary);
      await loadState();
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setRunning(false);
    }
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark">DP</span>
          <span>
            <strong>DNF Patch Studio</strong>
            <small>Agentic production control plane</small>
          </span>
        </div>
        <div className="safety-chip">
          <span className="safety-dot" />
          部署永久禁用 · 证据优先
        </div>
      </header>

      <main>
        <section className="hero">
          <div>
            <p className="kicker">AUDITABLE VISUAL PATCH PIPELINE</p>
            <h1>
              从设计语义到真实 NPK，
              <span>每一步都可追溯。</span>
            </h1>
            <p className="hero-copy">
              SOL 调度、GPT-5.5 工程设计、gpt-image-2
              参考素材与固定本地工具链共享同一冻结上下文。模型不能选择脚本、资源路径或部署状态。
            </p>
          </div>
          <div className="model-rail">
            {(state?.capabilities ?? []).map((capability, index) => (
              <div className="model-node" key={capability.role}>
                <span>{String(index + 1).padStart(2, "0")}</span>
                <div>
                  <small>{capability.role.toUpperCase()}</small>
                  <strong>{capability.requestedModel}</strong>
                </div>
                <i className={capability.available ? "online" : "offline"} />
              </div>
            ))}
          </div>
        </section>

        <section className="action-grid" aria-label="生产动作">
          {actions.map((item) => (
            <button
              className={
                action === item.id ? "action-card active" : "action-card"
              }
              key={item.id}
              onClick={() => setAction(item.id)}
              type="button"
            >
              <small>{item.eyebrow}</small>
              <strong>{item.title}</strong>
              <span>{item.description}</span>
              <b>→</b>
            </button>
          ))}
        </section>

        <section className="workspace-grid">
          <div className="panel run-panel">
            <div className="panel-heading">
              <div>
                <p className="kicker">RUN CONFIGURATION</p>
                <h2>{actions.find((item) => item.id === action)?.title}</h2>
              </div>
              <span className="route-badge">{action}</span>
            </div>

            <div className="form-grid">
              <label>
                <span>职业</span>
                <input
                  list="profession-options"
                  onChange={(event) => setProfession(event.target.value)}
                  value={profession}
                />
                <datalist id="profession-options">
                  {(state?.professions ?? []).map((item) => (
                    <option key={item.name} value={item.name} />
                  ))}
                </datalist>
              </label>

              {requiresTheme ? (
                <label>
                  <span>主题 / 风格</span>
                  <input
                    list="theme-options"
                    onChange={(event) => setTheme(event.target.value)}
                    value={theme}
                  />
                  <datalist id="theme-options">
                    {themes.map((item) => (
                      <option key={item} value={item} />
                    ))}
                  </datalist>
                </label>
              ) : null}

              <label className="wide">
                <span>技能显示名 · 每行一个</span>
                <textarea
                  className="skills-input"
                  onChange={(event) => setSkills(event.target.value)}
                  placeholder="幻影剑舞"
                  value={skills}
                />
              </label>

              {requiresDesign ? (
                <>
                  <label className="wide">
                    <span>设计文本</span>
                    <textarea
                      disabled={Boolean(sourceDesignPath)}
                      onChange={(event) => setDesignText(event.target.value)}
                      placeholder="粘贴职业或主题设计说明；它不会获得资源事实权限。"
                      value={designText}
                    />
                  </label>
                  <div className="file-row wide">
                    <button
                      onClick={() => void chooseDesignFile()}
                      type="button"
                    >
                      选择仓库内设计文件
                    </button>
                    <span>{sourceDesignPath || "未选择文件"}</span>
                    {sourceDesignPath ? (
                      <button
                        className="text-button"
                        onClick={() => setSourceDesignPath("")}
                        type="button"
                      >
                        清除
                      </button>
                    ) : null}
                  </div>
                </>
              ) : null}

              {isGenerate ? (
                <label className="wide">
                  <span>固定执行 Profile</span>
                  <input
                    onChange={(event) => setProfileId(event.target.value)}
                    value={profileId}
                  />
                </label>
              ) : null}

              <label>
                <span>输出基础名</span>
                <input
                  onChange={(event) => setOutputBaseName(event.target.value)}
                  value={outputBaseName}
                />
              </label>
              <label>
                <span>版本</span>
                <input
                  inputMode="decimal"
                  onChange={(event) => setOutputVersion(event.target.value)}
                  value={outputVersion}
                />
              </label>
            </div>

            <div className="control-strip">
              <label className="provider-toggle">
                <span>模型提供方</span>
                <select
                  onChange={(event) =>
                    setProvider(event.target.value as PipelineProvider)
                  }
                  value={provider}
                >
                  <option value="mock">Mock · 仅规划</option>
                  <option value="openai">OpenAI · 正式证据</option>
                </select>
              </label>
              <label className="check-control">
                <input
                  checked={allowNetwork}
                  onChange={(event) => setAllowNetwork(event.target.checked)}
                  type="checkbox"
                />
                <span>授权本 Run 联网</span>
              </label>
              <label className="check-control">
                <input
                  checked={execute}
                  onChange={(event) => setExecute(event.target.checked)}
                  type="checkbox"
                />
                <span>执行写步骤</span>
              </label>
              {isGenerate ? (
                <label className="check-control">
                  <input
                    checked={generateImageReferences}
                    onChange={(event) =>
                      setGenerateImageReferences(event.target.checked)
                    }
                    type="checkbox"
                  />
                  <span>生成不透明参考图</span>
                </label>
              ) : null}
            </div>

            <div className="submit-row">
              <p>
                {execute
                  ? "写步骤将使用固定工具目录与哈希绑定；仍不会部署到 ImagePacks2。"
                  : "当前为规划模式，不提交 Prompt 树、不执行本地写工具。"}
              </p>
              <button
                className="primary-button"
                disabled={running}
                onClick={() => void submit()}
                type="button"
              >
                {running
                  ? "运行中…"
                  : execute
                    ? "启动受控执行"
                    : "生成审计计划"}
              </button>
            </div>

            {error ? <div className="alert error-alert">{error}</div> : null}
            {summary ? (
              <div className={`alert status-${summary.status}`}>
                <strong>{statusLabel(summary.status)}</strong>
                <span>
                  {summary.runId} · {summary.currentStage}
                </span>
                {summary.error ? <p>{summary.error}</p> : null}
              </div>
            ) : null}
          </div>

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
                  <article
                    className={`event ${event.level}`}
                    key={event.sequence}
                  >
                    <div>
                      <span>{String(event.sequence).padStart(3, "0")}</span>
                      <strong>{event.stage}</strong>
                    </div>
                    <p>{event.message}</p>
                    <time>
                      {new Date(event.timestampUtc).toLocaleTimeString()}
                    </time>
                  </article>
                ))
              )}
            </div>
          </aside>
        </section>

        <section className="panel recent-panel">
          <div className="panel-heading compact">
            <div>
              <p className="kicker">LOCAL AUDIT TRAIL</p>
              <h2>最近 Run</h2>
            </div>
            <span>{state?.repositoryRoot ?? "正在定位仓库…"}</span>
          </div>
          <div className="run-table">
            {(state?.recentRuns ?? []).length === 0 ? (
              <p className="table-empty">尚无本地 Run 证据。</p>
            ) : (
              state?.recentRuns.map((run) => (
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
      </main>
    </div>
  );
}

const root = document.getElementById("root");
if (root === null) {
  throw new Error("Renderer root element is missing.");
}
createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
