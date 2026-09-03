/**
 * System-test harness — Wave 1 foundation (plan §3.2 / §3.3).
 */

import { vi } from "vitest";

const { artifactByRef, resolveArtifactMock, resolvePromptVersionMock } =
  vi.hoisted(() => {
    const artifactByRef: Record<string, string> = {
      "clinic.visit_summary/system@v1":
        "You are a clinical documentation assistant.\n",
      "clinic.visit_summary/rules-visit-summary@v1":
        "## Rules\n- Advisory only.\n",
      "clinic.visit_summary/template-visit-summary@v1":
        '<key name="visit.chief_complaint@v1">{{visit.chief_complaint@v1}}</key>\n',
    };

    function fnv1a(content: string): string {
      let hash = 0x811c9dc5;
      for (let index = 0; index < content.length; index += 1) {
        hash ^= content.charCodeAt(index);
        hash = Math.imul(hash, 0x01000193);
      }
      return (hash >>> 0).toString(16).padStart(8, "0");
    }

    return {
      artifactByRef,
      resolveArtifactMock(ref: string): string | undefined {
        return artifactByRef[ref];
      },
      resolvePromptVersionMock(manifest: {
        "Prompt binding": {
          systemInstructionArtifactRef: unknown;
          businessRuleFragmentRefs?: unknown;
          contextRenderingTemplateRef?: unknown;
        };
      }): string {
        const binding = manifest["Prompt binding"];
        const refs = [
          String(binding.systemInstructionArtifactRef),
          ...(Array.isArray(binding.businessRuleFragmentRefs)
            ? binding.businessRuleFragmentRefs.map(String)
            : []),
          ...(binding.contextRenderingTemplateRef != null &&
            String(binding.contextRenderingTemplateRef).length > 0
            ? [String(binding.contextRenderingTemplateRef)]
            : []),
        ];
        const parts = refs
          .map((ref) => artifactByRef[ref])
          .filter((content): content is string => content !== undefined);
        return fnv1a(parts.join("\0"));
      },
    };
  });

vi.mock("../../src/prompt/registry", () => ({
  resolveArtifact: resolveArtifactMock,
  resolvePromptVersion: resolvePromptVersionMock,
}));

import { env, SELF } from "cloudflare:test";
import migrationSql from "../../migrations/20260731120000_platform_schema.sql?raw";
import capabilityGrantLifecycleSql from "../../migrations/20260802100000_capability_grant_lifecycle.sql?raw";
import canaryMigrationSql from "../../migrations/20260803100000_routing_policy_canary.sql?raw";
import tokenContractMigrationSql from "../../migrations/20260803120000_token_contract.sql?raw";
import retentionIndexesSql from "../../migrations/20260805120000_f3_retention_indexes.sql?raw";
import conversationIndexSql from "../../migrations/20260805180000_h3_conversation_index.sql?raw";
import statusMigrationSql from "../../migrations/20260805190000_routing_policy_status.sql?raw";
import killSwitchMigrationSql from "../../migrations/20260807120000_kill_switch.sql?raw";
import graceQueueMigrationSql from "../../migrations/20260821120000_grace_admission_queue.sql?raw";
import entitlementUniqueSql from "../../migrations/20260821130000_entitlement_installation_unique.sql?raw";
import {
  createCapabilityRegistry,
  setCapabilityRegistry,
} from "../../src/capability";
import { VISIT_CHIEF_COMPLAINT_V1 } from "../../src/context";
import { isolateConfigCache } from "../../src/config-cache";
import { load, type Manifest } from "../../src/manifest";

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
  }
}

export const GATEWAY_ORIGIN = "https://ai-gateway.test";
export const OPERATOR_BEARER = "test-operator-bearer-token";
export const OPERATOR_ID = "operator-test-principal";
export const CAPABILITY_ID = "clinic.visit_summary";
export const CAPABILITY_VERSION = "1.0.0";
export const POLICY_ID = "standard";
export const POLICY_VERSION = "1";
export const POLICY_REF = "routing/standard@v1";

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
  "grace_admission_queue",
] as const;

export type SseEvent = { event: string; data: Record<string, unknown> };

export type TestKeypair = {
  publicKey: CryptoKey;
  privateKey: CryptoKey;
  kid: string;
  publicKeyB64: string;
};

export type Scenario = {
  installationId: string;
  orgId: string;
  branchId: string;
  actorId: string;
  kid: string;
  keypair: TestKeypair;
};

export type AatClaims = {
  iss: string;
  aud: string;
  sub: string;
  org: string;
  branch: string;
  role: string;
  scopes: string[];
  jti: string;
  iat: number;
  exp: number;
  ver: string;
};

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
  period_start: "2026-07-01T00:00:00.000Z",
  period_end: "2026-09-01T00:00:00.000Z",
  request_quota: 1000,
  token_budget: 500000,
  cost_budget: 50.0,
  soft_threshold: 0.8,
  allowed_capabilities: [CAPABILITY_ID],
  grants: [
    {
      capability_id: CAPABILITY_ID,
      capability_version: CAPABILITY_VERSION,
      scope: "installation",
    },
    {
      capability_id: CAPABILITY_ID,
      capability_version: CAPABILITY_VERSION,
      scope: "plan",
    },
  ],
};

const MIGRATION_SQL = [
  migrationSql,
  capabilityGrantLifecycleSql,
  canaryMigrationSql,
  tokenContractMigrationSql,
  retentionIndexesSql,
  conversationIndexSql,
  statusMigrationSql,
  killSwitchMigrationSql,
  graceQueueMigrationSql,
  entitlementUniqueSql,
];

let migrationsApplied = false;

function base64urlEncode(data: string | Uint8Array): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

function randomUuid(): string {
  return crypto.randomUUID();
}

function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

export async function applySql(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);

  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

export async function applyAllMigrations(db: D1Database): Promise<void> {
  if (migrationsApplied) {
    return;
  }
  for (const sql of MIGRATION_SQL) {
    await applySql(db, sql);
  }
  await db
    .prepare(
      `INSERT OR IGNORE INTO token_contract (ver, added_at, retired_at, changed_by)
       VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed')`,
    )
    .run();
  migrationsApplied = true;
}

export async function resetPlatformState(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM grace_admission_queue"),
    env.DB.prepare("DELETE FROM platform_counter"),
    env.DB.prepare("DELETE FROM usage_rollup"),
    env.DB.prepare("DELETE FROM usage_event"),
    env.DB.prepare("DELETE FROM ai_attempt"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM capability_grant"),
    env.DB.prepare("DELETE FROM routing_policy"),
    env.DB.prepare("DELETE FROM kill_switch"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation_key"),
    env.DB.prepare("DELETE FROM installation"),
    env.DB.prepare("DELETE FROM token_contract"),
  ]);

  await env.DB
    .prepare(
      `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
       VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed')`,
    )
    .run();
}

export function visitSummaryManifest(): Manifest {
  return load({
    Identity: {
      capabilityId: CAPABILITY_ID,
      version: CAPABILITY_VERSION,
      title: "Visit summary",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: "ai.visit_summary",
      minimumPlanTier: "standard",
      allowedStaffRoles: ["administrator", "clinician", "nurse"],
      killSwitchFlag: false,
    },
    Interaction: { interactionMode: "single_shot" },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: null,
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements": [
      {
        key: VISIT_CHIEF_COMPLAINT_V1,
        required: true,
        shapeRef: VISIT_CHIEF_COMPLAINT_V1,
        maxSize: 4_096,
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: "clinic.visit_summary/system@v1",
      businessRuleFragmentRefs: ["clinic.visit_summary/rules-visit-summary@v1"],
      contextRenderingTemplateRef: "clinic.visit_summary/template-visit-summary@v1",
      outputFormatInstructionDerivationRule: "derive_from_output_mode",
    },
    Output: {
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
    },
    Routing: {
      routingPolicyRef: POLICY_REF,
      requiredProviderFeatures: {
        structuredOutput: false,
        contextWindow: 32_000,
        language: "en",
      },
      latencyClass: "standard",
      degradedTierPolicy: "fallback_chain",
    },
    Economics: {
      maxInputTokens: 8_000,
      maxOutputTokens: 1_024,
      perRequestTokenCeiling: 9_024,
      quotaWeight: 1,
    },
    Governance: {
      acceptanceMode: "advisory_display",
      retentionClass: "diagnostic_30d",
      evalSuiteRef: "evals/visit@v1",
    },
  });
}

export function registerVisitSummaryCapability(): void {
  setCapabilityRegistry(createCapabilityRegistry([visitSummaryManifest()]), {
    replace: true,
  });
}

async function generateKeypair(kid: string): Promise<TestKeypair> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const rawPublicKey = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  return {
    publicKey: keyPair.publicKey,
    privateKey: keyPair.privateKey,
    kid,
    publicKeyB64: base64urlEncode(new Uint8Array(rawPublicKey)),
  };
}

export async function newScenario(): Promise<Scenario> {
  const installationId = randomUuid();
  const orgId = randomUuid();
  const branchId = randomUuid();
  const actorId = randomUuid();
  const kid = randomUuid();
  const keypair = await generateKeypair(kid);
  return { installationId, orgId, branchId, actorId, kid, keypair };
}

async function ensureInstallationKeyActive(installationId: string): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const key = await queryOne<{ valid_from: string }>(
      "SELECT valid_from FROM installation_key WHERE installation_id = ?",
      [installationId],
    );
    const validFromMs = Date.parse(String(key?.valid_from));
    const verifierNowMs = Math.floor(Date.now() / 1000) * 1000;
    if (!Number.isNaN(validFromMs) && verifierNowMs >= validFromMs) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error("installation key not yet within validity window");
}

export async function mintAat(
  scenario: Scenario,
  overrides: Partial<AatClaims> = {},
): Promise<string> {
  await ensureInstallationKeyActive(scenario.installationId);
  const payload: AatClaims = {
    iss: scenario.installationId,
    aud: "ai-platform",
    sub: scenario.actorId,
    org: scenario.orgId,
    branch: scenario.branchId,
    role: "clinician",
    scopes: ["ai.visit_summary", "ai.access"],
    jti: randomUuid(),
    iat: nowSeconds() - 30,
    exp: nowSeconds() + 300,
    ver: "1",
    ...overrides,
  };
  const header = { alg: "EdDSA", kid: scenario.keypair.kid };
  const headerB64 = base64urlEncode(JSON.stringify(header));
  const payloadB64 = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    scenario.keypair.privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64urlEncode(new Uint8Array(signature))}`;
}

export function enrollPayload(scenario: Scenario): Record<string, unknown> {
  return {
    org_id: scenario.orgId,
    display_name: "System Test Clinic",
    region: "us-east-1",
    plan: "standard",
    public_key: scenario.keypair.publicKeyB64,
    algorithm: "EdDSA",
    kid: scenario.kid,
  };
}

export async function operatorFetchRaw(
  path: string,
  body?: Record<string, unknown>,
  headers: Record<string, string> = {},
): Promise<Response> {
  const requestHeaders: Record<string, string> = {
    ...headers,
  };
  if (body !== undefined) {
    requestHeaders["content-type"] = "application/json";
  }
  if (!requestHeaders.authorization) {
    requestHeaders.authorization = `Bearer ${OPERATOR_BEARER}`;
  }
  return SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}${path}`, {
      method: "POST",
      headers: requestHeaders,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    }),
  );
}

export async function operatorFetch(
  path: string,
  body?: Record<string, unknown>,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const response = await operatorFetchRaw(path, body);
  const text = await response.text();
  const json = text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : {};
  return { status: response.status, json };
}

export function visitSummaryInvokeBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    capability_id: CAPABILITY_ID,
    capability_version: CAPABILITY_VERSION,
    user_intent: "Summarize the visit.",
    context: {
      org: scenario.orgId,
      branch: scenario.branchId,
      [VISIT_CHIEF_COMPLAINT_V1]: {
        visit_id: randomUuid(),
        complaint: "Headache for three days.",
        recorded_at: new Date().toISOString(),
      },
    },
    ...overrides,
  };
}

export async function parseSseEvents(response: Response): Promise<SseEvent[]> {
  const text = await response.text();
  const events: SseEvent[] = [];
  const blocks = text.split("\n\n").filter((block) => block.trim().length > 0);
  for (const block of blocks) {
    const lines = block.split("\n");
    let event = "";
    let data: Record<string, unknown> = {};
    for (const line of lines) {
      if (line.startsWith("event: ")) {
        event = line.slice(7);
      } else if (line.startsWith("data: ")) {
        data = JSON.parse(line.slice(6)) as Record<string, unknown>;
      }
    }
    if (event) {
      events.push({ event, data });
    }
  }
  return events;
}

export async function flushBackgroundWork(): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 150));
}

export async function invoke(
  scenario: Scenario,
  opts: {
    token?: string;
    idempotencyKey?: string;
    traceId?: string;
    capabilityVersion?: string;
    body?: Record<string, unknown>;
    signal?: AbortSignal;
  } = {},
): Promise<{
  status: number;
  headers: Headers;
  body: Record<string, unknown> | null;
  events: SseEvent[];
}> {
  const token = opts.token ?? (await mintAat(scenario));
  const headers: Record<string, string> = {
    authorization: `Bearer ${token}`,
    "content-type": "application/json",
    "x-idempotency-key": opts.idempotencyKey ?? randomUuid(),
    "x-capability-version": opts.capabilityVersion ?? CAPABILITY_VERSION,
  };
  if (opts.traceId) {
    headers["x-trace-id"] = opts.traceId;
  }

  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
      method: "POST",
      headers,
      body: JSON.stringify(
        opts.body ?? visitSummaryInvokeBody(scenario),
      ),
      signal: opts.signal,
    }),
  );

  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("text/event-stream")) {
    const events = await parseSseEvents(response);
    await flushBackgroundWork();
    return {
      status: response.status,
      headers: response.headers,
      body: null,
      events,
    };
  }

  const text = await response.text();
  await flushBackgroundWork();
  return {
    status: response.status,
    headers: response.headers,
    body: text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : null,
    events: [],
  };
}

export async function getCapabilities(
  token: string,
  ifNoneMatch?: string,
): Promise<{ status: number; etag: string | null; body: Record<string, unknown> | null }> {
  const headers: Record<string, string> = {
    authorization: `Bearer ${token}`,
  };
  if (ifNoneMatch) {
    headers["if-none-match"] = ifNoneMatch;
  }
  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, { headers }),
  );
  const etag = response.headers.get("ETag");
  if (response.status === 304) {
    return { status: response.status, etag, body: null };
  }
  const text = await response.text();
  return {
    status: response.status,
    etag,
    body: text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : null,
  };
}

export async function getRequest(
  token: string,
  ref: string,
): Promise<{ status: number; body: Record<string, unknown> | null }> {
  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/requests/${ref}`, {
      headers: { authorization: `Bearer ${token}` },
    }),
  );
  const text = await response.text();
  return {
    status: response.status,
    body: text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : null,
  };
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
): Promise<{ status: number; json: Record<string, unknown> }> {
  const result = await operatorFetch(
    `/control/routing-policies/${policyId}/versions/${version}/publish`,
    { document },
  );
  if (result.status === 200) {
    const policy = await getRoutingPolicy(policyId, version);
    if (!policy || policy.status !== "published") {
      throw new Error(
        `publishPolicy: expected D1 row status=published for ${policyId}@${version}`,
      );
    }
    const pointer = String(policy.content_pointer);
    if (!(await r2Exists(pointer))) {
      throw new Error(`publishPolicy: R2 object missing at ${pointer}`);
    }
    const stored = await getR2Json(pointer);
    if (stored.policy_id !== document.policy_id) {
      throw new Error("publishPolicy: R2 round-trip policy_id mismatch");
    }
  }
  if (result.status === 200) {
    clearConfigCache();
  }
  return result;
}

export async function canary(
  policyId: string,
  version: string,
  installationIds: string[],
): Promise<{ status: number; json: Record<string, unknown> }> {
  const result = await operatorFetch(
    `/control/routing-policies/${policyId}/versions/${version}/canary`,
    { installation_ids: installationIds },
  );
  if (result.status === 200) {
    clearConfigCache();
  }
  return result;
}

export async function promote(
  policyId: string,
  version: string,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const result = await operatorFetch(
    `/control/routing-policies/${policyId}/versions/${version}/promote`,
    {},
  );
  if (result.status === 200) {
    clearConfigCache();
  }
  return result;
}

export async function rollback(
  policyId: string,
  version: string,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const result = await operatorFetch(
    `/control/routing-policies/${policyId}/versions/${version}/rollback`,
    {},
  );
  if (result.status === 200) {
    clearConfigCache();
  }
  return result;
}

export async function queryOne<T extends Record<string, unknown>>(
  sql: string,
  params: unknown[] = [],
): Promise<T | null> {
  return env.DB.prepare(sql).bind(...params).first<T>();
}

export async function queryAll<T extends Record<string, unknown>>(
  sql: string,
  params: unknown[] = [],
): Promise<T[]> {
  const result = await env.DB.prepare(sql).bind(...params).all<T>();
  return result.results ?? [];
}

export async function count(
  table: string,
  where?: string,
  params: unknown[] = [],
): Promise<number> {
  const sql = where
    ? `SELECT COUNT(*) AS c FROM ${table} WHERE ${where}`
    : `SELECT COUNT(*) AS c FROM ${table}`;
  const row = await env.DB.prepare(sql).bind(...params).first<{ c: number }>();
  return row?.c ?? 0;
}

export const d1 = {
  queryOne,
  queryAll,
  count,
  getAiRequest,
  getAttempts,
  getUsageEvents,
  getEntitlement,
  getGrants,
  getAudits,
  getRoutingPolicy,
};

export async function getAiRequest(ref: string): Promise<Record<string, unknown> | null> {
  return queryOne(
    "SELECT * FROM ai_request WHERE request_reference = ?",
    [ref],
  );
}

export async function getAttempts(requestId: string): Promise<Record<string, unknown>[]> {
  return queryAll(
    "SELECT * FROM ai_attempt WHERE request_id = ? ORDER BY attempt_no",
    [requestId],
  );
}

export async function getUsageEvents(requestId: string): Promise<Record<string, unknown>[]> {
  return queryAll("SELECT * FROM usage_event WHERE request_id = ?", [requestId]);
}

export async function getEntitlement(
  installationId: string,
): Promise<Record<string, unknown> | null> {
  return queryOne("SELECT * FROM entitlement WHERE installation_id = ?", [
    installationId,
  ]);
}

export async function getGrants(scope: string): Promise<Record<string, unknown>[]> {
  return queryAll(
    "SELECT * FROM capability_grant WHERE scope = ? ORDER BY changed_at",
    [scope],
  );
}

export async function getAudits(
  action: string,
  target: string,
): Promise<Record<string, unknown>[]> {
  return queryAll(
    "SELECT * FROM control_audit WHERE action = ? AND target = ? ORDER BY recorded_at",
    [action, target],
  );
}

export async function getRoutingPolicy(
  policyId: string,
  version: string,
): Promise<Record<string, unknown> | null> {
  return queryOne(
    "SELECT * FROM routing_policy WHERE policy_id = ? AND version = ?",
    [policyId, version],
  );
}

export async function getR2Json(key: string): Promise<Record<string, unknown>> {
  const object = await env.R2.get(key);
  if (!object) {
    throw new Error(`R2 object not found: ${key}`);
  }
  return JSON.parse(await object.text()) as Record<string, unknown>;
}

export async function r2Exists(key: string): Promise<boolean> {
  const object = await env.R2.head(key);
  return object !== null;
}

/**
 * Trigger the worker scheduled handler for a cron expression.
 * `SELF.scheduled` is not exposed by @cloudflare/vitest-pool-workers 0.8.71 in
 * this project — invoke the exported worker module `scheduled()` with pool env.
 */
export async function runScheduled(cron: string): Promise<void> {
  const workerModule = await import("../../src/worker");
  await workerModule.default.scheduled(
    { cron, scheduledTime: Date.now(), noRetry() { } },
    env as never,
    {} as ExecutionContext,
  );
}

export function clearConfigCache(): void {
  isolateConfigCache.clear();
}

export function terminalEventTypes(events: SseEvent[]): string[] {
  const terminals = new Set([
    "completed",
    "failed",
    "cancelled",
    "context_requested",
  ]);
  return events.filter((event) => terminals.has(event.event)).map((e) => e.event);
}

export async function enrollScenario(scenario: Scenario): Promise<{
  status: number;
  json: Record<string, unknown>;
}> {
  const result = await operatorFetch(
    `/control/installations/${scenario.installationId}/enroll`,
    enrollPayload(scenario),
  );
  if (result.status === 200) {
    clearConfigCache();
  }
  return result;
}

export async function entitleScenario(
  scenario: Scenario,
  payload: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const result = await operatorFetch(
    `/control/installations/${scenario.installationId}/entitle`,
    payload as unknown as Record<string, unknown>,
  );
  clearConfigCache();
  return result;
}

export async function setupPromotedFakePolicy(
  scenario: Scenario,
  payload: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<void> {
  const enrolled = await enrollScenario(scenario);
  if (enrolled.status !== 200) {
    throw new Error(`enroll failed: ${enrolled.status}`);
  }
  const entitled = await entitleScenario(scenario, payload);
  if (entitled.status !== 200) {
    throw new Error(`entitle failed: ${entitled.status}`);
  }
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  if (published.status !== 200) {
    throw new Error(`publish failed: ${published.status}`);
  }
  const promoted = await promote(POLICY_ID, POLICY_VERSION);
  if (promoted.status !== 200) {
    throw new Error(`promote failed: ${promoted.status}`);
  }
  clearConfigCache();
}
