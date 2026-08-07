import type { IncomingMessage, ServerResponse } from "node:http";
import path from "node:path";
import { handleOpsRun } from "./run";
import type { OpsRunBody } from "./types";

export type NextHandleFunction = (
  req: IncomingMessage,
  res: ServerResponse,
  next: (err?: unknown) => void,
) => void;

function readJsonBody(req: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      if (!raw.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.statusCode = status;
  res.setHeader("content-type", "application/json");
  res.end(payload);
}

export function createOpsMiddleware(opsRootDir: string): NextHandleFunction {
  const repoRoot = path.join(opsRootDir, "..");

  return (req, res, next) => {
    const url = req.url ?? "";
    const pathname = url.split("?")[0] ?? "";

    if (!pathname.startsWith("/ops/")) {
      next();
      return;
    }

    if (req.method === "GET" && pathname === "/ops/health") {
      sendJson(res, 200, { ok: true });
      return;
    }

    if (req.method === "POST" && pathname === "/ops/run") {
      void (async () => {
        try {
          const body = (await readJsonBody(req)) as OpsRunBody;
          const result = await handleOpsRun(body, repoRoot);
          sendJson(res, 200, result);
        } catch (error) {
          const message =
            error instanceof Error ? error.message : "Invalid JSON body";
          sendJson(res, 400, { error: message });
        }
      })();
      return;
    }

    sendJson(res, 404, { error: "Not found" });
  };
}
