import { useCallback, useEffect, useMemo, useState } from "react";
import {
  runRequestSchema,
  type DesktopState,
  type PipelineAction,
  type PipelineEvent,
  type PipelineProvider,
  type RunSummary,
} from "../../../shared/contracts.js";
import { DEFAULT_PROFILE } from "../config/actions.js";
import { errorMessage, newRunId, splitSkills } from "../lib/format.js";

/** renderer 表单的本地可编辑状态；提交前统一进入 Zod 契约。 */
export interface RunFormState {
  action: PipelineAction;
  provider: PipelineProvider;
  profession: string;
  theme: string;
  skills: string;
  designText: string;
  sourceDesignPath: string;
  profileId: string;
  outputBaseName: string;
  outputVersion: string;
  execute: boolean;
  allowNetwork: boolean;
  generateImageReferences: boolean;
}

const INITIAL_FORM: RunFormState = {
  action: "create-theme",
  provider: "mock",
  profession: "剑魂",
  theme: "Vergil（维吉尔）暗蓝幻影主题",
  skills: "幻影剑舞",
  designText: "",
  sourceDesignPath: "",
  profileId: DEFAULT_PROFILE,
  outputBaseName: "weaponmaster-vergil-dark-blue",
  outputVersion: "1",
  execute: false,
  allowNetwork: false,
  generateImageReferences: false,
};

export interface PatchStudioController {
  state: DesktopState | undefined;
  form: RunFormState;
  themes: string[];
  events: PipelineEvent[];
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

/**
 * 集中管理 IPC、副作用、Run 请求构造和界面状态。
 *
 * 组件只渲染受控字段；所有用户输入在越过 preload 边界前都通过共享
 * `runRequestSchema`，部署授权固定为 false，renderer 无法提升该能力。
 */
export function usePatchStudio(): PatchStudioController {
  const [state, setState] = useState<DesktopState>();
  const [form, setForm] = useState<RunFormState>(INITIAL_FORM);
  const [events, setEvents] = useState<PipelineEvent[]>([]);
  const [summary, setSummary] = useState<RunSummary>();
  const [error, setError] = useState("");
  const [running, setRunning] = useState(false);

  const loadState = useCallback(async (): Promise<void> => {
    setState(await window.dnfPatch.getState());
  }, []);

  useEffect(() => {
    const dispose = window.dnfPatch.onRunEvent((event) => {
      // 仅保留最近 100 条展示事件；完整事件仍由主进程持久化。
      setEvents((current) => [...current.slice(-99), event]);
    });
    void loadState().catch((caught: unknown) => {
      setError(errorMessage(caught));
    });
    return dispose;
  }, [loadState]);

  const themes = useMemo(
    () =>
      state?.professions.find((item) => item.name === form.profession)
        ?.themes ?? [],
    [form.profession, state],
  );

  const updateForm = useCallback(
    <K extends keyof RunFormState>(key: K, value: RunFormState[K]): void => {
      setForm((current) => ({ ...current, [key]: value }));
    },
    [],
  );

  const clearSourceDesignPath = useCallback((): void => {
    updateForm("sourceDesignPath", "");
  }, [updateForm]);

  const chooseDesignFile = useCallback(async (): Promise<void> => {
    try {
      const path = await window.dnfPatch.selectDesignFile();
      if (path) {
        setForm((current) => ({
          ...current,
          sourceDesignPath: path,
          designText: "",
        }));
      }
    } catch (caught) {
      setError(errorMessage(caught));
    }
  }, []);

  const submit = useCallback(async (): Promise<void> => {
    setRunning(true);
    setError("");
    setSummary(undefined);
    setEvents([]);
    try {
      const requiresDesign =
        form.action === "create-profession" || form.action === "create-theme";
      const requiresTheme =
        form.action === "create-theme" || form.action === "generate-patch";
      const isGenerate = form.action === "generate-patch";
      const request = runRequestSchema.parse({
        schemaVersion: 1,
        runId: newRunId(),
        action: form.action,
        provider: form.provider,
        profession: form.profession.trim(),
        ...(requiresTheme ? { theme: form.theme.trim() } : {}),
        ...(requiresDesign && form.designText.trim()
          ? { designText: form.designText.trim() }
          : {}),
        ...(requiresDesign && form.sourceDesignPath
          ? { sourceDesignPath: form.sourceDesignPath }
          : {}),
        ...(isGenerate ? { profileId: form.profileId.trim() } : {}),
        selectedSkills: splitSkills(form.skills),
        execute: form.execute,
        resume: false,
        allowNetwork: form.allowNetwork,
        generateImageReferences: isGenerate && form.generateImageReferences,
        outputBaseName: form.outputBaseName.trim(),
        outputVersion: form.outputVersion.trim(),
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
  }, [form, loadState]);

  return {
    state,
    form,
    themes,
    events,
    summary,
    error,
    running,
    updateForm,
    clearSourceDesignPath,
    chooseDesignFile,
    submit,
  };
}
