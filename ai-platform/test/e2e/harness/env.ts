import { env, SELF } from "cloudflare:test";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    DO: DurableObjectNamespace;
    OPERATOR_BEARER_TOKEN: string;
    OPERATOR_ID: string;
    RATE_LIMITER_INSTALLATION: RateLimit;
    RATE_LIMITER_INSTALLATION_ACTOR: RateLimit;
    RATE_LIMITER_INSTALLATION_CAPABILITY: RateLimit;
    BUILD_SHA: string;
    ENVIRONMENT: string;
    CONFIG_CACHE_TTL_MS?: string;
    LOG_VERBOSITY?: string;
  }
}

export { env, SELF };

/** Origin used by `SELF.fetch` in the workers pool. */
export const GATEWAY_ORIGIN = "https://ai-gateway.test";

/** Must match `vitest.e2e.config.ts` miniflare binding. */
export const OPERATOR_BEARER = "test-operator-bearer-token";

/** Must match wrangler `[env.development.vars]` / e2e miniflare override. */
export const OPERATOR_ID = "platform-operator";

export const WRONG_OPERATOR_BEARER = "op-token-WRONG";

export const CAPABILITY_ID = "clinic.visit_summary";
export const CAPABILITY_VERSION = "1.0.0";
export const POLICY_ID = "standard";
export const POLICY_VERSION = "1";
export const POLICY_REF = "routing/standard";
export const AAT_AUDIENCE = "ai-platform";
export const TOKEN_CONTRACT_VER = "1";

export const QUOTA_DO_RPC_URL = "https://quota-do.internal/rpc";

export const PLATFORM_TABLES = [
  "installation",
  "installation_key",
  "entitlement",
  "capability_grant",
  "routing_policy",
  "kill_switch",
  "token_contract",
  "ai_request",
  "ai_attempt",
  "usage_event",
  "usage_rollup",
  "platform_counter",
  "control_audit",
  "credit_price",
  "grace_admission_queue",
  "invoice",
  "plan",
] as const;

export const TAXONOMY_BODY_KEYS = [
  "code",
  "request_reference",
  "trace_id",
  "retry_safe",
] as const;

export const REQUEST_REFERENCE_PATTERN =
  /^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/;

export const ULID_PATTERN = /^[0-9A-HJKMNPQRSTVWXYZ]{26}$/;

export type HttpResult = {
  status: number;
  headers: Headers;
  text: string;
  json: unknown;
};

export async function readHttpResult(response: Response): Promise<HttpResult> {
  const text = await response.text();
  let json: unknown = null;
  if (text.length > 0) {
    try {
      json = JSON.parse(text) as unknown;
    } catch {
      json = null;
    }
  }
  return {
    status: response.status,
    headers: response.headers,
    text,
    json,
  };
}

export function jsonOf<T = Record<string, unknown>>(
  result: HttpResult,
): T {
  return result.json as T;
}

export async function flushBackgroundWork(ms = 150): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

export function emptyExecutionContext(): ExecutionContext {
  return {
    waitUntil() {},
    passThroughOnException() {},
    props: {},
  } as ExecutionContext;
}
