import { DurableObject, env } from "cloudflare:workers";
import { generateRequestReference } from "./reference";
import { createStructuredLogger, resolveTraceId } from "./trace";

interface Env {
  DB: D1Database;
  R2: R2Bucket;
  DO: DurableObjectNamespace;
  BUILD_SHA: string;
  ENVIRONMENT: string;
}

function assertRequiredBindings(runtimeEnv: Env): void {
  if (!runtimeEnv.DB) {
    throw new Error("Missing required binding: DB");
  }
  if (!runtimeEnv.R2) {
    throw new Error("Missing required binding: R2");
  }
  if (!runtimeEnv.DO) {
    throw new Error("Missing required binding: DO");
  }
}

assertRequiredBindings(env as Env);

export class GatewayObject extends DurableObject { }

async function handleCreateRequest(request: Request): Promise<Response> {
  const traceId = resolveTraceId(request.headers.get("x-trace-id"));
  const requestReference = generateRequestReference();

  let bodyText: string;
  try {
    bodyText = await request.text();
  } catch {
    const { logger } = createStructuredLogger({
      traceId,
      requestReference,
      installation: "unknown",
      capability: "unknown",
      promptVersion: "unknown",
    });
    logger.error("request_body_unreadable");
    return new Response(JSON.stringify({ error: "malformed_body" }), {
      status: 422,
      headers: { "content-type": "application/json" },
    });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(bodyText);
  } catch {
    const { logger } = createStructuredLogger({
      traceId,
      requestReference,
      installation: "unknown",
      capability: "unknown",
      promptVersion: "unknown",
    });
    logger.error("request_body_invalid_json");
    return new Response(JSON.stringify({ error: "malformed_body" }), {
      status: 422,
      headers: { "content-type": "application/json" },
    });
  }

  const payload =
    parsed && typeof parsed === "object"
      ? (parsed as Record<string, unknown>)
      : {};

  const installation =
    typeof payload.installation === "string" ? payload.installation : "unknown";
  const capability =
    typeof payload.capability === "string" ? payload.capability : "unknown";
  const promptVersion =
    typeof payload.prompt_version === "string"
      ? payload.prompt_version
      : "unknown";

  const { logger } = createStructuredLogger({
    traceId,
    requestReference,
    installation,
    capability,
    promptVersion,
  });

  logger.info("request_received");

  return new Response(JSON.stringify({ status: "accepted" }), {
    status: 202,
    headers: { "content-type": "application/json" },
  });
}

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      const runtimeEnv = env as Env;
      return Response.json({
        build: runtimeEnv.BUILD_SHA,
        environment: runtimeEnv.ENVIRONMENT,
      });
    }

    if (url.pathname === "/v1/requests" && request.method === "POST") {
      return handleCreateRequest(request);
    }

    return new Response("Not Found", { status: 404 });
  },
};
