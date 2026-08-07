import type { BuiltRequest } from "../src/catalog/types";
import { handleLocal } from "./local-handlers";
import { proxyBuiltRequest } from "./proxy";
import { runSubprocess } from "./subprocess";
import type { ConnectionConfig, OpsRunBody, OpsRunResult } from "./types";

export type { OpsRunResult } from "./types";

export async function handleOpsRun(
  body: OpsRunBody,
  repoRoot: string,
): Promise<OpsRunResult> {
  const started = Date.now();
  const { request, connection } = body;

  if (!request || typeof request !== "object" || !("mode" in request)) {
    return {
      status: 400,
      contentType: "application/json",
      bodyText: JSON.stringify({ error: "Invalid request payload" }),
      headers: { "content-type": "application/json" },
      durationMs: Date.now() - started,
    };
  }

  const normalizedConnection = normalizeConnection(connection);

  switch (request.mode) {
    case "proxy":
      return proxyBuiltRequest(request, normalizedConnection);
    case "local":
      return handleLocal(
        request.handler,
        request.input,
        repoRoot,
        normalizedConnection,
      );
    case "subprocess":
      return runSubprocess(request, repoRoot);
    default: {
      const _exhaustive: never = request;
      return {
        status: 400,
        contentType: "application/json",
        bodyText: JSON.stringify({
          error: `Unsupported request mode: ${(_exhaustive as BuiltRequest).mode}`,
        }),
        headers: { "content-type": "application/json" },
        durationMs: Date.now() - started,
      };
    }
  }
}

function normalizeConnection(
  connection: ConnectionConfig | undefined,
): ConnectionConfig {
  return {
    platformBaseUrl:
      typeof connection?.platformBaseUrl === "string"
        ? connection.platformBaseUrl
        : "http://127.0.0.1:8787",
    operatorBearer:
      typeof connection?.operatorBearer === "string"
        ? connection.operatorBearer
        : "",
    aat: typeof connection?.aat === "string" ? connection.aat : "",
  };
}
