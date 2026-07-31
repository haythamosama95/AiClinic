import { DurableObject, env } from "cloudflare:workers";
import { handleAdapterRequest } from "./adapter";
import { dispatchControlRequest, isControlRoute } from "./control";
import {
  admissionRPC,
  creditRPC,
  type AdmissionRequest,
  type CreditRequest,
} from "./quota-do/index";

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

export class GatewayObject extends DurableObject {
  async fetch(request: Request): Promise<Response> {
    if (request.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return Response.json({ error: "invalid_json" }, { status: 400 });
    }
    const kind = (body as { kind?: string }).kind;
    if (kind === "admission") {
      const result = await admissionRPC(
        this.ctx.storage,
        (fn) => this.ctx.blockConcurrencyWhile(fn),
        body as AdmissionRequest,
      );
      return Response.json(result);
    }
    if (kind === "credit") {
      const result = await creditRPC(
        this.ctx.storage,
        (fn) => this.ctx.blockConcurrencyWhile(fn),
        body as CreditRequest,
      );
      return Response.json(result);
    }
    return Response.json({ error: "unknown_kind" }, { status: 400 });
  }
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
      return handleAdapterRequest(request);
    }

    if (request.method === "POST" && isControlRoute(url.pathname)) {
      const runtimeEnv = env as Env;
      return dispatchControlRequest(request, { DB: runtimeEnv.DB });
    }

    return new Response("Not Found", { status: 404 });
  },
};
