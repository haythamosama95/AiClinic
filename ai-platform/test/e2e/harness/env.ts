import { env, SELF } from "cloudflare:test";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    DO: DurableObjectNamespace;
    RATE_LIMITER_INSTALLATION: RateLimit;
    RATE_LIMITER_INSTALLATION_ACTOR: RateLimit;
    RATE_LIMITER_INSTALLATION_CAPABILITY: RateLimit;
    BUILD_SHA: string;
    ENVIRONMENT: string;
    CONFIG_CACHE_TTL_MS?: string;
    LOG_VERBOSITY?: string;
    ISSUER_ID?: string;
    ACCESS_TEAM_DOMAIN: string;
    ACCESS_AUD: string;
    WEBAUTHN_RP_ID: string;
    WEBAUTHN_ORIGIN: string;
    VENDOR: {
      registerOperatorCredential(
        args: Record<string, unknown>,
      ): Promise<{
        result: string;
        code: string;
        detail: string;
      }>;
      registerIssuerKey(
        args: Record<string, unknown>,
      ): Promise<{
        result: string;
        code: string;
        detail: string;
      }>;
    };
  }
}

export { env, SELF };

/** Origin used by `SELF.fetch` in the workers pool. */
export const GATEWAY_ORIGIN = "https://ai-gateway.test";

/** @deprecated Former operator bearer; control routes use Access JWT via vendor. */
export const WRONG_OPERATOR_BEARER = "op-token-WRONG";

export const CAPABILITY_ID = "clinic.visit_summary";
export const CAPABILITY_VERSION = "1.0.0";
export const POLICY_ID = "standard";
export const POLICY_VERSION = "1";
export const POLICY_REF = "routing/standard";
export const AAT_AUDIENCE = "ai-platform";
export const TOKEN_CONTRACT_VER = "2";
export const ISSUER_ID =
  (env as { ISSUER_ID?: string }).ISSUER_ID ?? "issuer-test";
export const WEBAUTHN_RP_ID = env.WEBAUTHN_RP_ID;
export const WEBAUTHN_ORIGIN = env.WEBAUTHN_ORIGIN;

export const QUOTA_DO_RPC_URL = "https://quota-do.internal/rpc";

export const PLATFORM_TABLES = [
  "installation",
  "issuer_key",
  "tenant_binding",
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
  "fallback_admission",
  "feed_consumer",
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
