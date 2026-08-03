import { DurableObject, env } from "cloudflare:workers";
import { handleAdapterRequest } from "./adapter";
import {
  createSecretOperatorAuth,
  dispatchControlRequest,
  isControlRoute,
} from "./control";
import { reconcileGraceUsage } from "./credit";
import { getRequest } from "./journal";
import { normalizeRequestReference } from "./reference";
import { flushRejectionCounters } from "./rate-limit";
import { runRetentionPurge } from "./retention";
import { runRollupAndReconciliation } from "./rollup";
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
  OPERATOR_BEARER_TOKEN: string;
  OPERATOR_ID: string;
  RATE_LIMITER_INSTALLATION: RateLimit;
  RATE_LIMITER_INSTALLATION_ACTOR: RateLimit;
  RATE_LIMITER_INSTALLATION_CAPABILITY: RateLimit;
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
    const injectableNow = (body as { now?: unknown }).now;
    const now =
      typeof injectableNow === "number" && Number.isFinite(injectableNow)
        ? injectableNow
        : undefined;
    try {
      if (kind === "admission") {
        const result = await admissionRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as AdmissionRequest,
          now,
        );
        return Response.json(result);
      }
      if (kind === "credit") {
        const result = await creditRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as CreditRequest,
          now,
        );
        return Response.json(result);
      }
    } catch {
      return Response.json({ error: "bad_request" }, { status: 400 });
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
      // Installation lifecycle, capability deprecate/retire, cohort activate/promote,
      // routing-policy publish/canary/rollback, support lookup, purge.
      const runtimeEnv = env as Env;
      const operatorAuth = createSecretOperatorAuth({
        bearerToken: runtimeEnv.OPERATOR_BEARER_TOKEN ?? "",
        operatorId: runtimeEnv.OPERATOR_ID ?? "",
      });
      return dispatchControlRequest(
        request,
        {
          DB: runtimeEnv.DB,
          R2: runtimeEnv.R2,
        },
        operatorAuth,
      );
    }

    if (
      request.method === "GET" &&
      url.pathname.startsWith("/v1/requests/")
    ) {
      const reference = url.pathname.slice("/v1/requests/".length);
      if (!reference) {
        return new Response(null, { status: 404 });
      }
      const runtimeEnv = env as Env;
      const normalizedRef = normalizeRequestReference(reference);
      const result = await getRequest(normalizedRef, {
        db: runtimeEnv.DB,
        r2: runtimeEnv.R2,
      });

      if (!result.found) {
        return new Response(null, { status: 404 });
      }

      if (result.state === "Completed") {
        return Response.json({ state: "Completed", result: result.result });
      }

      if (result.state === "Failed") {
        return Response.json({
          state: "Failed",
          terminal_error_code: result.terminalErrorCode,
        });
      }

      return Response.json({ state: "Cancelled" });
    }

    return new Response("Not Found", { status: 404 });
  },

  async scheduled(
    controller: ScheduledController,
    runtimeEnv: Env,
    _ctx: ExecutionContext,
  ): Promise<void> {
    // FR-011 — flush in-isolate guard rejection tallies before other jobs.
    await flushRejectionCounters({ DB: runtimeEnv.DB });
    // FR-013 / §15 #3 — reconcile grace admissions once the Quota DO may be reachable.
    await reconcileGraceUsage({ DO: runtimeEnv.DO });

    const cron = controller.cron;
    if (cron === "0 3 * * *") {
      await runRetentionPurge({
        db: runtimeEnv.DB,
        r2: runtimeEnv.R2,
      });
    } else if (cron === "0 4 * * *") {
      await runRollupAndReconciliation({ db: runtimeEnv.DB });
    }
  },
};
