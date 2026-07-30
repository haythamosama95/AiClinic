import { DurableObject, env } from "cloudflare:workers";

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

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/health") {
      return new Response("Not Found", { status: 404 });
    }

    const runtimeEnv = env as Env;
    return Response.json({
      build: runtimeEnv.BUILD_SHA,
      environment: runtimeEnv.ENVIRONMENT,
    });
  },
};
