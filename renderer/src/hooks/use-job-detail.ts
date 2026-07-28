/**
 * @fileoverview 管理任务详情路由的可取消读取、3 秒自动轮询和手动刷新生命周期。
 *
 * 详情页传入 URL 中的任务 ID，本 Hook 通过类型化任务 API 读取 ViewModel 并返回加载、刷新、错误
 * 与详情状态。副作用包括受认证 HTTP 请求、AbortController 和单个串行定时器；不读取 Token、
 * 不下载参考图或产物。安全与竞态边界：切换任务、手动刷新或卸载时必须中止旧请求并清除定时器，
 * stale result（较早请求晚返回的过期结果）不能覆盖当前路由，终态任务不能继续后台轮询。
 */
import { useCallback, useEffect, useState } from "react";
import { getJobDetail, type PatchTaskDetail } from "../api/index.js";
import { apiErrorMessage } from "../utils/api-error.js";

/** 进行中详情的固定轮询间隔；使用串行 timeout，响应较慢时不会累积并发请求。 */
export const jobDetailPollIntervalMs = 3_000;

/** 任务详情 Hook 对页面公开的只读状态与显式刷新命令。 */
export interface JobDetailQuery {
  detail: PatchTaskDetail | undefined;
  loading: boolean;
  refreshing: boolean;
  errorMessage: string;
  /** 中止当前轮次并立即建立新读取；不会创建第二个并发轮询器。 */
  refresh: () => void;
}

interface JobDetailState {
  detail: PatchTaskDetail | undefined;
  loading: boolean;
  refreshing: boolean;
  errorMessage: string;
}

/**
 * 判断任务是否还会产生进度变化。
 *
 * @param detail 服务端返回的任务详情；queued/running 之外均视为终态。
 * @returns 需要继续自动轮询时为 true；unknown 状态不会由客户端自行发明。
 */
export function isPatchTaskActive(detail: PatchTaskDetail): boolean {
  return detail.status === "queued" || detail.status === "running";
}

/**
 * 读取并轮询一个受保护路由中的任务详情。
 *
 * @param jobId `useParams` 提供的任务 ID；缺失时不发请求并返回错误状态，由页面显示不可用结果。
 * @returns 当前详情、首次加载/后台刷新状态、安全错误文案和手动刷新命令。
 */
export function useJobDetail(jobId: string | undefined): JobDetailQuery {
  const [refreshVersion, setRefreshVersion] = useState(0);
  const [state, setState] = useState<JobDetailState>({
    detail: undefined,
    loading: Boolean(jobId),
    refreshing: false,
    errorMessage: jobId ? "" : "任务地址无效。",
  });

  useEffect(() => {
    if (!jobId) {
      setState({
        detail: undefined,
        loading: false,
        refreshing: false,
        errorMessage: "任务地址无效。",
      });
      return undefined;
    }

    let active = true;
    let timerId: number | undefined;
    let requestController: AbortController | undefined;
    let latestDetail: PatchTaskDetail | undefined;

    setState((current) => ({
      detail: current.detail?.id === jobId ? current.detail : undefined,
      loading: current.detail?.id !== jobId,
      refreshing: current.detail?.id === jobId,
      errorMessage: "",
    }));

    /** 请求完成后才安排下一轮，避免慢网络下多个详情请求重叠。 */
    const scheduleNext = (): void => {
      timerId = window.setTimeout(() => {
        void load(false);
      }, jobDetailPollIntervalMs);
    };

    /**
     * 执行当前生命周期的一轮详情读取。
     *
     * @param initial 当前任务 ID 的首次读取；后续轮次保留已有详情，仅展示轻量刷新状态。
     */
    const load = async (initial: boolean): Promise<void> => {
      requestController = new AbortController();
      if (!initial) {
        setState((current) => ({ ...current, refreshing: true }));
      }
      try {
        const nextDetail = await getJobDetail(jobId, requestController.signal);
        if (!active || requestController.signal.aborted) return;
        latestDetail = nextDetail;
        setState({
          detail: nextDetail,
          loading: false,
          refreshing: false,
          errorMessage: "",
        });
        if (isPatchTaskActive(nextDetail)) scheduleNext();
      } catch (error) {
        if (!active || requestController.signal.aborted) return;
        setState((current) => ({
          ...current,
          loading: false,
          refreshing: false,
          errorMessage: apiErrorMessage(error),
        }));
        // 只有已经证明处于进行中的任务才在瞬时失败后重试；首次 404/403 不制造无限请求。
        if (latestDetail && isPatchTaskActive(latestDetail)) scheduleNext();
      }
    };

    // 第一步：路由或刷新版本变化后立即读取，不等待第一个 3 秒周期。
    void load(true);
    return () => {
      // 第二步：撤销旧生命周期的写入资格，并同时清理网络与定时器所有权。
      active = false;
      requestController?.abort();
      if (timerId !== undefined) window.clearTimeout(timerId);
    };
  }, [jobId, refreshVersion]);

  /** 递增版本让 Effect 先清理旧请求/定时器，再启动唯一的新读取生命周期。 */
  const refresh = useCallback(() => {
    setRefreshVersion((version) => version + 1);
  }, []);

  return { ...state, refresh };
}
