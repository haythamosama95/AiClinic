import type { BuiltRequest } from "../src/catalog/types";
import type { ConnectionConfig, OpsRunResult } from "./types";

const SSE_TIMEOUT_MS = 30_000;
const SAFE_RESPONSE_HEADERS = ["content-type", "x-request-id"] as const;

function pickSafeHeaders(headers: Headers): Record<string, string> {
  const out: Record<string, string> = {};
  for (const name of SAFE_RESPONSE_HEADERS) {
    const value = headers.get(name);
    if (value !== null) {
      out[name] = value;
    }
  }
  return out;
}

async function readResponseBody(
  response: Response,
  contentType: string,
): Promise<string> {
  if (contentType.includes("text/event-stream")) {
    const reader = response.body?.getReader();
    if (!reader) {
      return "";
    }

    const decoder = new TextDecoder();
    let accumulated = "";
    const deadline = Date.now() + SSE_TIMEOUT_MS;

    while (Date.now() < deadline) {
      const remaining = Math.max(1, deadline - Date.now());
      const chunk = await Promise.race([
        reader.read(),
        new Promise<{ done: boolean; value?: Uint8Array }>((resolve) =>
          setTimeout(() => resolve({ done: true, value: undefined }), remaining),
        ),
      ]);

      if (chunk.done) {
        break;
      }
      if (chunk.value) {
        accumulated += decoder.decode(chunk.value, { stream: true });
      }
    }

    try {
      await reader.cancel();
    } catch {
      // ignore cancel errors
    }

    return accumulated;
  }

  return response.text();
}

export async function proxyBuiltRequest(
  request: Extract<BuiltRequest, { mode: "proxy" }>,
  connection: ConnectionConfig,
): Promise<OpsRunResult> {
  const started = Date.now();

  let authorization: string | undefined;
  const forwardHeaders: Record<string, string> = { ...(request.headers ?? {}) };

  if (request.auth === "aat") {
    const override = forwardHeaders["x-ops-aat-override"];
    if (override !== undefined) {
      delete forwardHeaders["x-ops-aat-override"];
      if (!override.trim()) {
        return {
          status: 400,
          contentType: "application/json",
          bodyText: JSON.stringify({
            error: "Missing credential: x-ops-aat-override header is empty",
          }),
          headers: { "content-type": "application/json" },
          durationMs: Date.now() - started,
        };
      }
      authorization = `Bearer ${override}`;
    } else if (!connection.aat.trim()) {
      return {
        status: 400,
        contentType: "application/json",
        bodyText: JSON.stringify({
          error: "Missing credential: aat (connection strip or x-ops-aat-override)",
        }),
        headers: { "content-type": "application/json" },
        durationMs: Date.now() - started,
      };
    } else {
      authorization = `Bearer ${connection.aat}`;
    }
  } else if (request.auth === "operator") {
    if (!connection.operatorBearer.trim()) {
      return {
        status: 400,
        contentType: "application/json",
        bodyText: JSON.stringify({
          error: "Missing credential: operatorBearer",
        }),
        headers: { "content-type": "application/json" },
        durationMs: Date.now() - started,
      };
    }
    authorization = `Bearer ${connection.operatorBearer}`;
  }

  const baseUrl = connection.platformBaseUrl.replace(/\/$/, "");
  const url = `${baseUrl}${request.path}`;

  const headers = new Headers();
  for (const [key, value] of Object.entries(forwardHeaders)) {
    if (key.toLowerCase() === "authorization") {
      continue;
    }
    headers.set(key, value);
  }
  if (authorization !== undefined) {
    headers.set("authorization", authorization);
  }

  try {
    const response = await fetch(url, {
      method: request.method,
      headers,
      body:
        request.method === "GET" || request.method === "HEAD"
          ? undefined
          : request.body,
      signal: AbortSignal.timeout(5_000),
    });

    const contentType = response.headers.get("content-type") ?? "";
    const bodyText = await readResponseBody(response, contentType);

    return {
      status: response.status,
      contentType,
      bodyText,
      headers: pickSafeHeaders(response.headers),
      durationMs: Date.now() - started,
    };
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Upstream request failed";
    return {
      status: 502,
      contentType: "application/json",
      bodyText: JSON.stringify({ error: message }),
      headers: { "content-type": "application/json" },
      durationMs: Date.now() - started,
    };
  }
}
