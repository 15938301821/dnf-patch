import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "antd/dist/reset.css";
import { apiMode } from "./api/mode.js";
import "./global.css";

async function bootstrap(): Promise<void> {
  if (apiMode === "mock") {
    const { configureMockApi } = await import("./mock/index.js");
    configureMockApi();
  }
  const [{ App }, root] = await Promise.all([
    import("./app/index.js"),
    Promise.resolve(document.getElementById("root")),
  ]);
  if (root === null) {
    throw new Error("Renderer root element is missing.");
  }
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}

void bootstrap();
