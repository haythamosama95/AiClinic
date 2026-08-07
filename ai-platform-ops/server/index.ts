import { serve } from "@hono/node-server";
import { Hono } from "hono";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { handleOpsRun } from "./run";
import type { OpsRunBody } from "./types";

const serverDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(serverDir, "..", "..");

const app = new Hono();

app.get("/ops/health", (c) => c.json({ ok: true }));

app.post("/ops/run", async (c) => {
  let body: OpsRunBody;
  try {
    body = await c.req.json<OpsRunBody>();
  } catch {
    return c.json({ error: "Invalid JSON body" }, 400);
  }

  const result = await handleOpsRun(body, repoRoot);
  return c.json(result);
});

app.all("/ops/*", (c) => c.json({ error: "Not found" }, 404));

const port = Number(process.env.OPS_PORT ?? 8788);

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`ai-platform-ops server listening on http://127.0.0.1:${info.port}`);
});
