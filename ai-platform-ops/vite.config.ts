import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { createOpsMiddleware } from "./server/vite-plugin";

const rootDir = path.dirname(fileURLToPath(import.meta.url));

function opsApiPlugin(): Plugin {
  return {
    name: "ai-platform-ops-api",
    configureServer(server) {
      server.middlewares.use(createOpsMiddleware(rootDir));
    },
  };
}

export default defineConfig({
  plugins: [react(), tailwindcss(), opsApiPlugin()],
  resolve: {
    alias: {
      "@": path.resolve(rootDir, "./src"),
    },
  },
  server: {
    port: 5174,
  },
});
