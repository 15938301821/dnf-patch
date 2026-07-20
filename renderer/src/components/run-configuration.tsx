import type {
  DesktopState,
  PipelineProvider,
  RunSummary,
} from "../../../server/shared/contracts.js";
import { actionDefinition } from "../config/actions.js";
import type { RunFormState } from "../hooks/use-patch-studio.js";
import { statusLabel } from "../utils/run-format.js";

interface RunConfigurationProps {
  state: DesktopState | undefined;
  form: RunFormState;
  themes: readonly string[];
  summary: RunSummary | undefined;
  error: string;
  running: boolean;
  updateForm: <K extends keyof RunFormState>(
    key: K,
    value: RunFormState[K],
  ) => void;
  clearSourceDesignPath: () => void;
  chooseDesignFile: () => Promise<void>;
  submit: () => Promise<void>;
}

/** 受控 Run 表单；所有字段最终仍由 hook 中的共享 Zod 契约验证。 */
export function RunConfiguration({
  state,
  form,
  themes,
  summary,
  error,
  running,
  updateForm,
  clearSourceDesignPath,
  chooseDesignFile,
  submit,
}: RunConfigurationProps): React.JSX.Element {
  const requiresDesign =
    form.action === "create-profession" || form.action === "create-theme";
  const requiresTheme =
    form.action === "create-theme" || form.action === "generate-patch";
  const isGenerate = form.action === "generate-patch";

  return (
    <div className="panel run-panel">
      <div className="panel-heading">
        <div>
          <p className="kicker">RUN CONFIGURATION</p>
          <h2>{actionDefinition(form.action).title}</h2>
        </div>
        <span className="route-badge">{form.action}</span>
      </div>

      <div className="form-grid">
        <label>
          <span>职业</span>
          <input
            list="profession-options"
            onChange={(event) => updateForm("profession", event.target.value)}
            value={form.profession}
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
              onChange={(event) => updateForm("theme", event.target.value)}
              value={form.theme}
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
            onChange={(event) => updateForm("skills", event.target.value)}
            placeholder="幻影剑舞"
            value={form.skills}
          />
        </label>

        {requiresDesign ? (
          <>
            <label className="wide">
              <span>设计文本</span>
              <textarea
                disabled={Boolean(form.sourceDesignPath)}
                onChange={(event) =>
                  updateForm("designText", event.target.value)
                }
                placeholder="粘贴职业或主题设计说明；它不会获得资源事实权限。"
                value={form.designText}
              />
            </label>
            <div className="file-row wide">
              <button onClick={() => void chooseDesignFile()} type="button">
                选择仓库内设计文件
              </button>
              <span>{form.sourceDesignPath || "未选择文件"}</span>
              {form.sourceDesignPath ? (
                <button
                  className="text-button"
                  onClick={clearSourceDesignPath}
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
              onChange={(event) => updateForm("profileId", event.target.value)}
              value={form.profileId}
            />
          </label>
        ) : null}

        <label>
          <span>输出基础名</span>
          <input
            onChange={(event) =>
              updateForm("outputBaseName", event.target.value)
            }
            value={form.outputBaseName}
          />
        </label>
        <label>
          <span>版本</span>
          <input
            inputMode="decimal"
            onChange={(event) =>
              updateForm("outputVersion", event.target.value)
            }
            value={form.outputVersion}
          />
        </label>
      </div>

      <div className="control-strip">
        <label className="provider-toggle">
          <span>模型提供方</span>
          <select
            onChange={(event) =>
              updateForm("provider", event.target.value as PipelineProvider)
            }
            value={form.provider}
          >
            <option value="mock">Mock · 仅规划</option>
            <option value="openai">OpenAI · 正式证据</option>
          </select>
        </label>
        <label className="check-control">
          <input
            checked={form.allowNetwork}
            onChange={(event) =>
              updateForm("allowNetwork", event.target.checked)
            }
            type="checkbox"
          />
          <span>授权本 Run 联网</span>
        </label>
        <label className="check-control">
          <input
            checked={form.execute}
            onChange={(event) => updateForm("execute", event.target.checked)}
            type="checkbox"
          />
          <span>执行写步骤</span>
        </label>
        {isGenerate ? (
          <label className="check-control">
            <input
              checked={form.generateImageReferences}
              onChange={(event) =>
                updateForm("generateImageReferences", event.target.checked)
              }
              type="checkbox"
            />
            <span>生成不透明参考图</span>
          </label>
        ) : null}
      </div>

      <div className="submit-row">
        <p>
          {form.execute
            ? "写步骤将使用固定工具目录与哈希绑定；仍不会部署到 ImagePacks2。"
            : "当前为规划模式，不提交 Prompt 树、不执行本地写工具。"}
        </p>
        <button
          className="primary-button"
          disabled={running}
          onClick={() => void submit()}
          type="button"
        >
          {running ? "运行中…" : form.execute ? "启动受控执行" : "生成审计计划"}
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
  );
}
