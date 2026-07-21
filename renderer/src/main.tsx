import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "antd/dist/reset.css";
import "./global.css";

async function bootstrap(): Promise<void> {
  if (import.meta.env.VITE_API_MODE !== "remote") {
    const { configureMockApi } = await import("./api/mock-server.js");
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
