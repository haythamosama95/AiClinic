import {
  canaryRoutingPolicyAction,
  promoteRoutingPolicyAction,
  publishRoutingPolicyAction,
  rollbackRoutingPolicyAction,
} from "../../../src/control/routing-policy";
import {
  armKillSwitchAction,
  disarmKillSwitchAction,
} from "../../../src/control/kill-switch";
import {
  deprecateCapabilityAction,
  retireCapabilityAction,
} from "../../../src/control/capability-lifecycle";
import {
  beginTokenContractRotationAction,
  retireTokenContractAction,
} from "../../../src/control/token-contract";
import {
  activateCohortAction,
  promoteCohortAction,
} from "../../../src/control/cohort";
import { supportLookup as runSupportLookup } from "../../../src/support";
import { createManifestRetentionClassResolver } from "../../../src/retention";
import type { ControlActionResult, ControlBindings } from "../../../src/control/types";
import { isolateConfigCache } from "../../../src/config-cache";
import {
  env,
  GATEWAY_ORIGIN,
  jsonOf,
  readHttpResult,
  SELF,
  type HttpResult,
} from "./env";
import { getCapabilities } from "./clinic";
import { queryOne } from "./d1";
import { clearE2eIssuerRegistry, ensureE2eIssuerRegistry, mintAat } from "./aat";
import {
  vendorAccessJwtForControlAuth,
  vendorCall,
  vendorEnvelopeToHttp,
} from "./vendor";
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
  clinicToken?: string;
};

const OPERATOR_EMAIL = "operator@clinic.test";

function controlResultToResponse(result: ControlActionResult): Response {
  if (result.ok) {
    return new Response(JSON.stringify(result.body), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }
  return new Response(JSON.stringify({ error: result.error }), {
    status: result.status,
    headers: { "content-type": "application/json" },
  });
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

async function routeControlPathToVendor(
  pathname: string,
  method: string,
  body: unknown,
  auth: ControlAuth,
): Promise<HttpResult | null> {
  const accessJwt = await vendorAccessJwtForControlAuth(auth);
  const parsedBody =
    typeof body === "string"
      ? (JSON.parse(body) as Record<string, unknown>)
      : (body as Record<string, unknown> | undefined);

  const publishRe = /^\/control\/routing-policies\/publish$/u;
  const canaryRe =
    /^\/control\/routing-policies\/([^/]+)\/versions\/([^/]+)\/canary$/u;
  const promoteRe =
    /^\/control\/routing-policies\/([^/]+)\/versions\/([^/]+)\/promote$/u;
  const rollbackRe =
    /^\/control\/routing-policies\/([^/]+)\/versions\/([^/]+)\/rollback$/u;
  const deprecateRe =
    /^\/control\/capabilities\/([^/]+)\/versions\/([^/]+)\/deprecate$/u;
  const retireCapRe =
    /^\/control\/capabilities\/([^/]+)\/versions\/([^/]+)\/retire$/u;
  const activateRe =
    /^\/control\/capabilities\/([^/]+)\/versions\/([^/]+)\/activate$/u;
  const promoteCapRe =
    /^\/control\/capabilities\/([^/]+)\/versions\/([^/]+)\/promote$/u;
  const killArmRe = /^\/control\/kill-switches\/arm$/u;
  const killDisarmRe = /^\/control\/kill-switches\/disarm$/u;
  const tokenBeginRe = /^\/control\/token-contract\/begin-rotation$/u;
  const tokenRetireRe = /^\/control\/token-contract\/retire$/u;
  const supportLookupRe = /^\/control\/support\/lookup$/u;

  if (publishRe.test(pathname) && method === "POST") {
    const envelope = await vendorCall(
      "publishRoutingPolicy",
      { document: parsedBody?.document },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  const canaryMatch = canaryRe.exec(pathname);
  if (canaryMatch && method === "POST") {
    const envelope = await vendorCall(
      "canaryRoutingPolicy",
      {
        policy_id: canaryMatch[1],
        version: canaryMatch[2],
        installation_ids: parsedBody?.installation_ids,
      },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  const promoteMatch = promoteRe.exec(pathname);
  if (promoteMatch && method === "POST") {
    const envelope = await vendorCall(
      "promoteRoutingPolicy",
      { policy_id: promoteMatch[1], version: promoteMatch[2] },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  const rollbackMatch = rollbackRe.exec(pathname);
  if (rollbackMatch && method === "POST") {
    const envelope = await vendorCall(
      "rollbackRoutingPolicy",
      { policy_id: rollbackMatch[1], version: rollbackMatch[2] },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  const deprecateMatch = deprecateRe.exec(pathname);
  if (deprecateMatch && method === "POST") {
    const envelope = await vendorCall(
      "deprecateCapability",
      {
        capability_id: deprecateMatch[1],
        capability_version: deprecateMatch[2],
        successor_id: parsedBody?.successor_id,
      },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  const retireCapMatch = retireCapRe.exec(pathname);
  if (retireCapMatch && method === "POST") {
    const envelope = await vendorCall(
      "retireCapability",
      {
        capability_id: retireCapMatch[1],
        capability_version: retireCapMatch[2],
      },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  const activateMatch = activateRe.exec(pathname);
  if (activateMatch && method === "POST") {
    const envelope = await vendorCall(
      "activateCohort",
      {
        capability_id: activateMatch[1],
        capability_version: activateMatch[2],
        cohort: parsedBody?.cohort,
      },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  const promoteCapMatch = promoteCapRe.exec(pathname);
  if (promoteCapMatch && method === "POST") {
    const envelope = await vendorCall(
      "promoteCohort",
      {
        capability_id: promoteCapMatch[1],
        capability_version: promoteCapMatch[2],
        cohort: parsedBody?.cohort,
      },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  if (killArmRe.test(pathname) && method === "POST") {
    const envelope = await vendorCall(
      "armKillSwitch",
      { scope: parsedBody?.scope, target: parsedBody?.target },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  if (killDisarmRe.test(pathname) && method === "POST") {
    const envelope = await vendorCall(
      "disarmKillSwitch",
      { scope: parsedBody?.scope, target: parsedBody?.target },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  if (tokenBeginRe.test(pathname) && method === "POST") {
    const envelope = await vendorCall("beginTokenContractRotation", {}, { accessJwt });
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  if (tokenRetireRe.test(pathname) && method === "POST") {
    const envelope = await vendorCall(
      "retireTokenContract",
      { ver: parsedBody?.ver },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  if (supportLookupRe.test(pathname)) {
    const url = new URL(`https://x${pathname}${method === "GET" ? "" : ""}`);
    const reference =
      typeof parsedBody?.reference === "string"
        ? parsedBody.reference
        : url.searchParams.get("reference") ?? undefined;
    const envelope = await vendorCall(
      "supportLookup",
      {
        reference,
        subscription_ref: parsedBody?.subscription_ref,
        org_id: parsedBody?.org_id,
      },
      { accessJwt },
    );
    const http = vendorEnvelopeToHttp(envelope);
    return {
      status: http.status,
      headers: new Headers(),
      text: JSON.stringify(http.json),
      json: http.json,
    };
  }

  return null;
}

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
  if (options.clinicToken !== undefined) {
    headers.authorization = `Bearer ${options.clinicToken}`;
  }

  const routed = await routeControlPathToVendor(
    path,
    method,
    options.body,
    auth,
  );
  if (routed !== null) {
    if (routed.status === 200) {
      isolateConfigCache.clear();
    }
    return routed;
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

export function controlBindingsFromEnv(
  overrides: Partial<ControlBindings> = {},
): ControlBindings {
  return {
    DB: overrides.DB ?? env.DB,
    R2: overrides.R2 ?? env.R2,
    DO: overrides.DO ?? env.DO,
  };
}

export async function dispatchControl(
  request: Request,
  bindings: Partial<ControlBindings> = {},
): Promise<Response> {
  return dispatchControlRequest(request, controlBindingsFromEnv(bindings), null);
}

export async function dispatchControlRequest(
  request: Request,
  bindings: ControlBindings,
  _auth: unknown,
): Promise<Response> {
  const url = new URL(request.url);
  const pathname = url.pathname;
  let body: unknown;
  try {
    body = await request.clone().json();
  } catch {
    body = undefined;
  }
  const record = (body ?? {}) as Record<string, unknown>;

  if (pathname === "/control/routing-policies/publish") {
    const result = await publishRoutingPolicyAction(
      bindings,
      OPERATOR_EMAIL,
      record.document as Record<string, unknown>,
    );
    return controlResultToResponse(result);
  }

  const canaryRe =
    /^\/control\/routing-policies\/([^/]+)\/versions\/([^/]+)\/canary$/u.exec(
      pathname,
    );
  if (canaryRe) {
    const result = await canaryRoutingPolicyAction(
      bindings,
      OPERATOR_EMAIL,
      canaryRe[1]!,
      canaryRe[2]!,
      Array.isArray(record.installation_ids)
        ? (record.installation_ids as string[])
        : [],
    );
    return controlResultToResponse(result);
  }

  const promoteRe =
    /^\/control\/routing-policies\/([^/]+)\/versions\/([^/]+)\/promote$/u.exec(
      pathname,
    );
  if (promoteRe) {
    const result = await promoteRoutingPolicyAction(
      bindings,
      OPERATOR_EMAIL,
      promoteRe[1]!,
      promoteRe[2]!,
    );
    return controlResultToResponse(result);
  }

  const rollbackRe =
    /^\/control\/routing-policies\/([^/]+)\/versions\/([^/]+)\/rollback$/u.exec(
      pathname,
    );
  if (rollbackRe) {
    const result = await rollbackRoutingPolicyAction(
      bindings,
      OPERATOR_EMAIL,
      rollbackRe[1]!,
      rollbackRe[2]!,
    );
    return controlResultToResponse(result);
  }

  return new Response(JSON.stringify({ error: "not_found" }), { status: 404 });
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
  isolateConfigCache.clear();
  return ready;
}

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
  _payload: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
  options: ControlFetchOptions = {},
): Promise<HttpResult> {
  const result = await controlFetch(
    `/control/installations/${scenario.installationId}/entitle`,
    { ...options, body: {} },
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
  return controlFetch("/control/routing-policies/publish", {
    body: { document },
  });
}

export async function canaryPolicy(
  policyId: string,
  version: string,
  installationIds: string[],
): Promise<HttpResult> {
  return controlFetch(
    `/control/routing-policies/${policyId}/versions/${version}/canary`,
    { body: { installation_ids: installationIds } },
  );
}

export async function promotePolicy(
  policyId: string,
  version: string,
): Promise<HttpResult> {
  return controlFetch(
    `/control/routing-policies/${policyId}/versions/${version}/promote`,
    { body: {} },
  );
}

export async function rollbackPolicy(
  policyId: string,
  version: string,
): Promise<HttpResult> {
  return controlFetch(
    `/control/routing-policies/${policyId}/versions/${version}/rollback`,
    { body: {} },
  );
}

export { jsonOf };

export const controlHandlers = {
  handleSuspend: async () =>
    new Response(JSON.stringify({ error: "not_found" }), { status: 404 }),
  handleResume: async () =>
    new Response(JSON.stringify({ error: "not_found" }), { status: 404 }),
  handleDelete: async () =>
    new Response(JSON.stringify({ error: "not_found" }), { status: 404 }),
  handleInstallationPurge: async () =>
    new Response(JSON.stringify({ error: "not_found" }), { status: 404 }),
  handleEntitle: async () =>
    new Response(JSON.stringify({ error: "not_found" }), { status: 404 }),
  handleDeprecate: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const body = (await request.json()) as Record<string, unknown>;
    const result = await deprecateCapabilityAction(
      bindings,
      OPERATOR_EMAIL,
      body,
    );
    return controlResultToResponse(result);
  },
  handleRetire: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const body = (await request.json()) as Record<string, unknown>;
    const result = await retireCapabilityAction(bindings, OPERATOR_EMAIL, body);
    return controlResultToResponse(result);
  },
  handleCohortActivate: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const body = (await request.json()) as Record<string, unknown>;
    const result = await activateCohortAction(bindings, OPERATOR_EMAIL, body);
    return controlResultToResponse(result);
  },
  handleCohortPromote: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const body = (await request.json()) as Record<string, unknown>;
    const result = await promoteCohortAction(bindings, OPERATOR_EMAIL, body);
    return controlResultToResponse(result);
  },
  handleRoutingPolicyPublish: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const body = await request.json();
    const result = await publishRoutingPolicyAction(
      bindings,
      OPERATOR_EMAIL,
      (body as { document: Record<string, unknown> }).document,
    );
    return controlResultToResponse(result);
  },
  handleRoutingPolicyCanary: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const url = new URL(request.url);
    const parts = url.pathname.split("/");
    const body = await request.json();
    const result = await canaryRoutingPolicyAction(
      bindings,
      OPERATOR_EMAIL,
      parts[4]!,
      parts[6]!,
      Array.isArray((body as { installation_ids?: unknown }).installation_ids)
        ? ((body as { installation_ids: string[] }).installation_ids)
        : [],
    );
    return controlResultToResponse(result);
  },
  handleRoutingPolicyPromote: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const url = new URL(request.url);
    const parts = url.pathname.split("/");
    const result = await promoteRoutingPolicyAction(
      bindings,
      OPERATOR_EMAIL,
      parts[4]!,
      parts[6]!,
    );
    return controlResultToResponse(result);
  },
  handleRoutingPolicyRollback: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const url = new URL(request.url);
    const parts = url.pathname.split("/");
    const result = await rollbackRoutingPolicyAction(
      bindings,
      OPERATOR_EMAIL,
      parts[4]!,
      parts[6]!,
    );
    return controlResultToResponse(result);
  },
  handleTokenContractBeginRotation: async (
    _request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const result = await beginTokenContractRotationAction(bindings, OPERATOR_EMAIL);
    return controlResultToResponse(result);
  },
  handleTokenContractRetire: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const body = (await request.json()) as Record<string, unknown>;
    const result = await retireTokenContractAction(
      bindings,
      OPERATOR_EMAIL,
      body,
    );
    return controlResultToResponse(result);
  },
  handleSupportLookup: async (request: Request, bindings: ControlBindings) => {
    const url = new URL(request.url);
    const reference = url.searchParams.get("reference");
    const result = await runSupportLookup(
      { reference: reference ?? undefined },
      {
        db: bindings.DB,
        r2: bindings.R2!,
        resolveRetentionClass: createManifestRetentionClassResolver(),
      },
    );
    if (!result.found) {
      return new Response(JSON.stringify({ error: "not_found" }), { status: 404 });
    }
    return new Response(JSON.stringify(result.envelope), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  },
  handleInstallationQuotaGet: async () =>
    new Response(JSON.stringify({ error: "not_found" }), { status: 404 }),
  handleKillSwitchArm: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const body = (await request.json()) as Record<string, unknown>;
    const result = await armKillSwitchAction(bindings, OPERATOR_EMAIL, body);
    return controlResultToResponse(result);
  },
  handleKillSwitchDisarm: async (
    request: Request,
    bindings: ControlBindings,
    _auth: unknown,
  ) => {
    const body = (await request.json()) as Record<string, unknown>;
    const result = await disarmKillSwitchAction(bindings, OPERATOR_EMAIL, body);
    return controlResultToResponse(result);
  },
};

export function operatorAuthFromEnv(): null {
  return null;
}
