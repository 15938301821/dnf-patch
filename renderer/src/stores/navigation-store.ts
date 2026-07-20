import { useCallback, useState } from "react";
import type { AppPage } from "../types/navigation.js";

export interface NavigationStore {
  page: AppPage;
  navigate: (page: AppPage) => void;
}

/** 桌面应用采用受控视图切换，不将内部页面状态暴露到 URL。 */
export function useNavigationStore(): NavigationStore {
  const [page, setPage] = useState<AppPage>("dashboard");
  const navigate = useCallback((nextPage: AppPage): void => {
    setPage(nextPage);
  }, []);
  return { page, navigate };
}
