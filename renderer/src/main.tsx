import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app.js";
import "./styles.css";

// 入口只负责验证宿主节点并挂载页面，业务逻辑由 App 与 hooks 管理。
const root = document.getElementById("root");
if (root === null) {
  throw new Error("Renderer root element is missing.");
}

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
