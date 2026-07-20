export type AppPage = "dashboard" | "project-setup" | "monitor" | "settings";

export interface NavigationItem {
  id: AppPage;
  label: string;
  description: string;
}
