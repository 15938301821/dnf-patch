/**
 * @fileoverview 管理制作任务列表的可取消读取、3 秒串行轮询和手动刷新生命周期。
 *
 * 流程位置：受保护的 JobsPage 调用本 Hook；Hook 通过类型化任务 API 读取当前用户可见的
 * PatchTask ViewModel，并把任务、加载、刷新和错误状态返回页面。
 * 输入输出：无调用参数；输出只含 API 返回的任务摘要和显式 refresh 命令，不保存认证凭据。
 * 副作用：发起受认证 GET 请求、创建 AbortController 与单个 timeout；不删除任务、不下载产物。
 * 安全边界：请求必须串行，手动刷新或卸载必须同时中止旧请求并清除定时器，stale result（旧请求
 * 晚返回的过期结果）不能覆盖新生命周期；服务端仍是状态、所有权和归档规则的事实源。
 */
import { useCallback, useEffect, useState } from "react";
import { getJobsList, type PatchTask } from "../api/index.js";
import { apiErrorMessage } from "../utils/api-error.js";

/** 列表固定轮询间隔；下一轮只在当前请求结算后安排，慢网络下不会累积并发请求。 */
export const jobsListPollIntervalMs = 3_000;

/** 任务列表 Hook 对页面公开的只读状态与唯一手动刷新命令。 */
export interface JobsListQuery {
  jobs: PatchTask[];
  loading: boolean;
  refreshing: boolean;
  errorMessage: string;
  /** 中止当前请求、清除旧 timer 并立即建立一套新轮询生命周期。 */
  refresh: () => void;
}

interface JobsListState {
  jobs: PatchTask[];
  loading: boolean;
  refreshing: boolean;
  errorMessage: string;
}

/**
 * 持续读取当前用户可见的制作任务列表。
 *
 * @returns 任务摘要、首次加载/后台刷新状态、当前错误文案与显式刷新命令；瞬时失败保留旧列表并在
 * 下一周期重试，调用方无需创建第二个定时器。
 */
export function useJobsList(): JobsListQuery {
  const [refreshVersion, setRefreshVersion] = useState(0);
  const [state, setState] = useState<JobsListState>({
    jobs: [],
    loading: true,
    refreshing: false,
    errorMessage: "",
  });

  useEffect(() => {
    let active = true;
    let timerId: number | undefined;
    let requestController: AbortController | undefined;

    setState((current) => ({
      ...current,
      loading: current.jobs.length === 0,
      refreshing: current.jobs.length > 0,
      errorMessage: "",
    }));

    /** 当前请求结算后才创建下一轮 timeout，保证全生命周期最多一个列表请求在途。 */
    const scheduleNext = (): void => {
      timerId = window.setTimeout(() => {
        void load(false);
      }, jobsListPollIntervalMs);
    };

    /**
     * 执行当前生命周期的一轮列表读取。
     *
     * @param initial 当前生命周期的首次请求；后台轮次保留已有任务，避免表格闪回 Skeleton。
     */
    const load = async (initial: boolean): Promise<void> => {
      requestController = new AbortController();
      if (!initial) {
        setState((current) => ({ ...current, refreshing: true }));
      }
      try {
        const jobs = await getJobsList(requestController.signal);
        if (!active || requestController.signal.aborted) return;
        setState({
          jobs,
          loading: false,
          refreshing: false,
          errorMessage: "",
        });
      } catch (error) {
        if (!active || requestController.signal.aborted) return;
        setState((current) => ({
          ...current,
          loading: false,
          refreshing: false,
          errorMessage: apiErrorMessage(error),
        }));
      }
      // try/catch 两条路径都已在写状态前通过 active/aborted guard，此处可直接安排唯一下一轮。
      scheduleNext();
    };

    // 第一步：挂载或刷新版本变化时立即读取，不等待首个 3 秒周期。
    void load(true);
    return () => {
      // 第二步：先撤销旧生命周期写入资格，再清理网络和 timer，阻止过期结果覆盖新列表。
      active = false;
      requestController?.abort();
      if (timerId !== undefined) window.clearTimeout(timerId);
    };
  }, [refreshVersion]);

  /** 递增版本让 Effect 完整清理旧生命周期后，再立即执行一次新读取。 */
  const refresh = useCallback(() => {
    setRefreshVersion((version) => version + 1);
  }, []);

  return { ...state, refresh };
}
