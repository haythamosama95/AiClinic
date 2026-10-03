import {
  createSecretOperatorAuth,
  dispatchControlRequest,
  handleCohortActivate,
  handleCohortPromote,
  handleDelete,
  handleDeprecate,
  handleEntitle,
  handleInstallationPurge,
  handleInstallationQuotaGet,
  handleKillSwitchArm,
  handleKillSwitchDisarm,
  handleResume,
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
import { getCapabilities } from "./clinic";
import { queryOne } from "./d1";
import { clearE2eIssuerRegistry, ensureE2eIssuerRegistry, mintAat } from "./aat";
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

const ENTITLE_PATH_RE = /^\/control\/installations\/([^/]+)\/entitle$/;

type EntitleReseedBody = {
  request_quota: number;
  soft_threshold: number;
  allowed_capabilities: string[];
  credit_budget?: number;
};

function parseEntitleReseedBody(body: unknown): EntitleReseedBody | null {
  if (body === undefined || body === null) {
    return null;
  }
  let parsed: unknown = body;
  if (typeof body === "string") {
    try {
      parsed = JSON.parse(body);
    } catch {
      return null;
    }
  }
  if (typeof parsed !== "object" || parsed === null) {
    return null;
  }
  const record = parsed as Record<string, unknown>;
  const requestQuota = record.request_quota;
  if (
    typeof requestQuota !== "number" ||
    !Number.isInteger(requestQuota) ||
    requestQuota < 0
  ) {
    return null;
  }
  const softThreshold = record.soft_threshold;
  if (
    typeof softThreshold !== "number" ||
    !Number.isFinite(softThreshold) ||
    softThreshold < 0 ||
    softThreshold > 1
  ) {
    return null;
  }
  const allowedCapabilities = record.allowed_capabilities;
  if (
    !Array.isArray(allowedCapabilities) ||
    !allowedCapabilities.every((entry) => typeof entry === "string")
  ) {
    return null;
  }
  const creditBudget = record.credit_budget;
  if (
    creditBudget !== undefined &&
    (typeof creditBudget !== "number" || !Number.isInteger(creditBudget))
  ) {
    return null;
  }
  return {
    request_quota: requestQuota,
    soft_threshold: softThreshold,
    allowed_capabilities: allowedCapabilities,
    ...(creditBudget !== undefined ? { credit_budget: creditBudget } : {}),
  };
}

function resolveEntitleReseedCreditBudget(
  raw: Record<string, unknown>,
  parsed: EntitleReseedBody,
): number {
  const creditBudget = raw.credit_budget;
  if (typeof creditBudget === "number" && Number.isInteger(creditBudget)) {
    return creditBudget;
  }
  if (raw.token_budget === 0 || raw.cost_budget === 0) {
    return 0;
  }
  return parsed.request_quota;
}

async function reseedEntitlePlanFromBody(
  db: D1Database,
  installationId: string,
  body: EntitleReseedBody,
  raw: Record<string, unknown>,
): Promise<void> {
  const row = await db
    .prepare("SELECT plan FROM entitlement WHERE installation_id = ?")
    .bind(installationId)
    .first<{ plan: string }>();
  if (!row?.plan) {
    return;
  }
  await db
    .prepare(
      `INSERT OR REPLACE INTO plan (
         name, credit_budget, request_quota, max_cost_class,
         soft_threshold, allowed_capabilities, status
       ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      row.plan,
      resolveEntitleReseedCreditBudget(raw, body),
      body.request_quota,
      "",
      body.soft_threshold,
      JSON.stringify(body.allowed_capabilities),
      "active",
    )
    .run();
}

async function maybeReseedEntitlePlan(
  db: D1Database,
  pathname: string,
  body: unknown,
): Promise<void> {
  const match = ENTITLE_PATH_RE.exec(pathname);
  if (!match) {
    return;
  }
  const parsed = parseEntitleReseedBody(body);
  if (!parsed) {
    return;
  }
  let raw: Record<string, unknown> = {};
  if (typeof body === "object" && body !== null) {
    raw = body as Record<string, unknown>;
  } else if (typeof body === "string") {
    try {
      const decoded = JSON.parse(body) as unknown;
      if (typeof decoded === "object" && decoded !== null) {
        raw = decoded as Record<string, unknown>;
      }
    } catch {
      raw = {};
    }
  }
  await reseedEntitlePlanFromBody(db, match[1], parsed, raw);
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

  await maybeReseedEntitlePlan(env.DB, path, options.body);

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
  const db = bindings.DB ?? env.DB;
  const pathname = new URL(request.url).pathname;
  let body: unknown;
  try {
    body = await request.clone().json();
  } catch {
    body = undefined;
  }
  await maybeReseedEntitlePlan(db, pathname, body);

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

export async function newClinic(scenario?: Scenario): Promise<Scenario> {
  const ready = scenario ?? {
    installationId: crypto.randomUUID(),
    orgId: crypto.randomUUID(),
    branchId: crypto.randomUUID(),
    actorId: crypto.randomUUID(),
    kid: crypto.randomUUID(),
    keypair: await (async () => {
      const { generateTestKeypair } = await import("./crypto");
      return generateTestKeypair(crypto.randomUUID());
    })(),
  };
  const issuer = await ensureE2eIssuerRegistry();
  ready.kid = issuer.kid;
  const token = await mintAat(ready);
  const caps = await getCapabilities(token);
  if (caps.status !== 200) {
    throw new Error(`newClinic capabilities failed (${caps.status})`);
  }
  const binding = await queryOne<{ installation_id: string }>(
    "SELECT installation_id FROM tenant_binding WHERE org_id = ? AND status = 'active'",
    [ready.orgId],
  );
  if (!binding?.installation_id) {
    throw new Error("newClinic: tenant_binding missing");
  }
  ready.installationId = binding.installation_id;
  await ensurePendingEntitlement(ready.installationId, ready.plan ?? "standard");
  isolateConfigCache.clear();
  return ready;
}

/** Enroll used to insert this sentinel so `/control/entitle` can activate it. */
async function ensurePendingEntitlement(
  installationId: string,
  plan: string,
): Promise<void> {
  const existing = await queryOne<{ entitlement_id: string }>(
    "SELECT entitlement_id FROM entitlement WHERE installation_id = ?",
    [installationId],
  );
  if (existing) {
    return;
  }
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO entitlement (
      entitlement_id, installation_id, plan, period_start, period_end,
      request_quota, token_budget, cost_budget, allowed_capabilities,
      soft_threshold, status
    ) VALUES (?, ?, ?, ?, ?, 0, 0, 0, '[]', 0, 'pending')`,
  )
    .bind(crypto.randomUUID(), installationId, plan, now, now)
    .run();
}

/** @deprecated Use `newClinic`. Enroll control route returns 404. */
export async function enrollInstallation(
  scenario: Scenario,
  options: ControlFetchOptions & { payload?: Record<string, unknown> } = {},
): Promise<HttpResult> {
  return controlFetch(
    `/control/installations/${scenario.installationId}/enroll`,
    {
      ...options,
      body: options.payload ?? options.body ?? enrollPayload(scenario),
    },
  );
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
