import {
  createSecretOperatorAuth,
  dispatchControlRequest,
  handleCohortActivate,
  handleCohortPromote,
  handleDelete,
  handleDeprecate,
  handleEnroll,
  handleEntitle,
  handleInstallationPurge,
  handleInstallationQuotaGet,
  handleKillSwitchArm,
  handleKillSwitchDisarm,
  handleResume,
  handleRevokeKey,
  handleRotate,
  handleRoutingPolicyCanary,
  handleRoutingPolicyPromote,
  handleRoutingPolicyPublish,
  handleRoutingPolicyRollback,
  handleSupportLookup,
  handleSuspend,
  handleTokenContractBeginRotation,
  handleTokenContractRetire,
  handleRetire,
} from "../../../src/control";
import type { ControlBindings, OperatorAuth } from "../../../src/control/types";
import { isolateConfigCache } from "../../../src/config-cache";
import {
  env,
  GATEWAY_ORIGIN,
  jsonOf,
  OPERATOR_BEARER,
  readHttpResult,
  SELF,
  WRONG_OPERATOR_BEARER,
  type HttpResult,
} from "./env";
import type { Scenario } from "./types";

export type ControlAuth =
  | "operator"
  | "none"
  | "wrong"
  | "empty"
  | "basic"
  | "no-scheme"
  | { bearer: string }
  | { authorization: string | null };

export type ControlFetchOptions = {
  method?: string;
  body?: unknown;
  auth?: ControlAuth;
  headers?: Record<string, string>;
  /** When set, used as the clinic AAT bearer (auth variant `"clinic-aat"`). */
  clinicToken?: string;
};

function authorizationHeader(auth: ControlAuth): string | undefined {
  if (auth === "none") {
    return undefined;
  }
  if (auth === "operator") {
    return `Bearer ${OPERATOR_BEARER}`;
  }
  if (auth === "wrong") {
    return `Bearer ${WRONG_OPERATOR_BEARER}`;
  }
  if (auth === "empty") {
    return "Bearer ";
  }
  if (auth === "basic") {
    return "Basic b3A6cGFzcw==";
  }
  if (auth === "no-scheme") {
    return OPERATOR_BEARER;
  }
  if ("bearer" in auth) {
    return `Bearer ${auth.bearer}`;
  }
  return auth.authorization ?? undefined;
}

function encodeBody(body: unknown): {
  serialized?: string;
  contentType?: string;
} {
  if (body === undefined) {
    return {};
  }
  if (typeof body === "string") {
    return { serialized: body, contentType: "application/json" };
  }
  return {
    serialized: JSON.stringify(body),
    contentType: "application/json",
  };
}

/**
 * HTTP helper for `/control/*`. Default auth is the configured operator bearer.
 * Wrong-bearer variants: `"wrong"`, `"empty"`, `"basic"`, `"no-scheme"`,
 * `{ bearer }`, `{ authorization }`.
 */
export async function controlFetch(
  path: string,
  options: ControlFetchOptions = {},
): Promise<HttpResult> {
  const method = options.method ?? "POST";
  const auth = options.auth ?? "operator";
  const { serialized, contentType } = encodeBody(options.body);
  const headers: Record<string, string> = { ...options.headers };
  if (contentType && !headers["content-type"]) {
    headers["content-type"] = contentType;
  }
  const authorization =
    options.clinicToken !== undefined
      ? `Bearer ${options.clinicToken}`
      : authorizationHeader(auth);
  if (authorization !== undefined && !headers.authorization) {
    headers.authorization = authorization;
  }

  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}${path}`, {
      method,
      headers,
      body: serialized,
    }),
  );
  return readHttpResult(response);
}

export function operatorAuthFromEnv(): OperatorAuth {
  return createSecretOperatorAuth({
    bearerToken: env.OPERATOR_BEARER_TOKEN ?? OPERATOR_BEARER,
    operatorId: env.OPERATOR_ID ?? "platform-operator",
  });
}

export function controlBindingsFromEnv(
  overrides: Partial<ControlBindings> = {},
): ControlBindings {
  return {
    DB: overrides.DB ?? env.DB,
    R2: overrides.R2 ?? env.R2,
    DO: overrides.DO ?? env.DO,
  };
}

/**
 * Invoke `dispatchControlRequest` with caller-supplied bindings (Register 5
 * #2, #19, #21). Does not go through `SELF.fetch`.
 */
export async function dispatchControl(
  request: Request,
  bindings: Partial<ControlBindings> = {},
  auth: OperatorAuth = operatorAuthFromEnv(),
): Promise<Response> {
  return dispatchControlRequest(
    request,
    controlBindingsFromEnv(bindings),
    auth,
  );
}

export function enrollPayload(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    org_id: scenario.orgId,
    display_name: "E2E Clinic",
    region: "us-east-1",
    plan: "standard",
    public_key: scenario.keypair.publicKeyB64,
    algorithm: "EdDSA",
    kid: scenario.kid,
    ...overrides,
  };
}

export async function enrollInstallation(
  scenario: Scenario,
  options: ControlFetchOptions & { payload?: Record<string, unknown> } = {},
): Promise<HttpResult> {
  const result = await controlFetch(
    `/control/installations/${scenario.installationId}/enroll`,
    {
      ...options,
      body: options.payload ?? options.body ?? enrollPayload(scenario),
    },
  );
  if (result.status === 200) {
    isolateConfigCache.clear();
  }
  return result;
}

export type EntitlePayload = {
  period_start: string;
  period_end: string;
  request_quota: number;
  token_budget: number;
  cost_budget: number;
  soft_threshold: number;
  allowed_capabilities: string[];
  grants: Array<{
    capability_id: string;
    capability_version: string;
    scope?: "installation" | "plan";
  }>;
};

export const DEFAULT_ENTITLE_PAYLOAD: EntitlePayload = {
  period_start: "2026-01-01T00:00:00.000Z",
  period_end: "2027-01-01T00:00:00.000Z",
  request_quota: 1000,
  token_budget: 500000,
  cost_budget: 50.0,
  soft_threshold: 0.8,
  allowed_capabilities: ["clinic.visit_summary"],
  grants: [
    {
      capability_id: "clinic.visit_summary",
      capability_version: "1.0.0",
      scope: "installation",
    },
    {
      capability_id: "clinic.visit_summary",
      capability_version: "1.0.0",
      scope: "plan",
    },
  ],
};

export async function entitleInstallation(
  scenario: Scenario,
  payload: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
  options: ControlFetchOptions = {},
): Promise<HttpResult> {
  const result = await controlFetch(
    `/control/installations/${scenario.installationId}/entitle`,
    {
      ...options,
      body: payload as unknown as Record<string, unknown>,
    },
  );
  isolateConfigCache.clear();
  return result;
}

export function fakePolicyTarget(
  modelId: string,
  opts: {
    providerId?: string;
    minContextWindow?: number;
    languages?: string[] | string;
    costClass?: string;
    latencyClass?: string;
    structuredOutput?: boolean;
  } = {},
): Record<string, unknown> {
  const languages = opts.languages ?? ["en"];
  return {
    provider_id: opts.providerId ?? "fake",
    model_id: modelId,
    features: {
      structured_output: opts.structuredOutput ?? false,
      min_context_window: opts.minContextWindow ?? 32_000,
      languages,
      latency_class: opts.latencyClass ?? "standard",
      cost_class: opts.costClass ?? "standard",
    },
    max_attempts: 1,
    timeout_ms: 30_000,
  };
}

export function fakePolicyDocument(
  policyId: string,
  version: string | number,
  opts: {
    ruleId?: string;
    targets?: Record<string, unknown>[];
    overrides?: Record<string, unknown>[];
    requires?: Record<string, unknown>;
    canaryRules?: Record<string, unknown>[];
  } = {},
): Record<string, unknown> {
  const requires = opts.requires ?? {
    structured_output: false,
    min_context_window: 0,
    languages: ["en"],
  };
  const targets = opts.targets ?? [fakePolicyTarget("fake-v1")];
  const rules: Record<string, unknown>[] = opts.canaryRules ?? [
    {
      rule_id: opts.ruleId ?? "catch-all",
      match: {},
      requires,
      targets,
    },
  ];
  return {
    schema_version: 1,
    policy_id: policyId,
    policy_version: Number(version),
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules,
    overrides: opts.overrides ?? [],
  };
}

export async function publishPolicy(
  policyId: string,
  version: string,
  document: Record<string, unknown>,
): Promise<HttpResult> {
  const result = await controlFetch("/control/routing-policies/publish", {
    body: { document },
  });
  if (result.status === 200) {
    isolateConfigCache.clear();
  }
  return result;
}

export async function canaryPolicy(
  policyId: string,
  version: string,
  installationIds: string[],
): Promise<HttpResult> {
  const result = await controlFetch(
    `/control/routing-policies/${policyId}/versions/${version}/canary`,
    { body: { installation_ids: installationIds } },
  );
  if (result.status === 200) {
    isolateConfigCache.clear();
  }
  return result;
}

export async function promotePolicy(
  policyId: string,
  version: string,
): Promise<HttpResult> {
  const result = await controlFetch(
    `/control/routing-policies/${policyId}/versions/${version}/promote`,
    { body: {} },
  );
  if (result.status === 200) {
    isolateConfigCache.clear();
  }
  return result;
}

export async function rollbackPolicy(
  policyId: string,
  version: string,
): Promise<HttpResult> {
  const result = await controlFetch(
    `/control/routing-policies/${policyId}/versions/${version}/rollback`,
    { body: {} },
  );
  if (result.status === 200) {
    isolateConfigCache.clear();
  }
  return result;
}

export { jsonOf };

export const controlHandlers = {
  handleEnroll,
  handleRotate,
  handleRevokeKey,
  handleSuspend,
  handleResume,
  handleDelete,
  handleInstallationPurge,
  handleEntitle,
  handleDeprecate,
  handleRetire,
  handleCohortActivate,
  handleCohortPromote,
  handleRoutingPolicyPublish,
  handleRoutingPolicyCanary,
  handleRoutingPolicyPromote,
  handleRoutingPolicyRollback,
  handleTokenContractBeginRotation,
  handleTokenContractRetire,
  handleSupportLookup,
  handleInstallationQuotaGet,
  handleKillSwitchArm,
  handleKillSwitchDisarm,
};
