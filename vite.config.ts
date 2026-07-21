import { resolve } from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  root: resolve("renderer"),
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
  },
  build: {
    outDir: resolve("dist-web"),
    emptyOutDir: true,
    rollupOptions: {
      input: resolve("renderer/index.html"),
    },
  },
});
