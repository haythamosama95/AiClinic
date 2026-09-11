/**
 * G3 — Usage summary endpoint (Workers integration).
 * Phase 1: written red before GET /v1/usage handler, rollup SUM, and migration land.
 */
import { env, SELF } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import tokenContractMigrationSql from "../migrations/20260803120000_token_contract.sql?raw";
import killSwitchMigrationSql from "../migrations/20260807120000_kill_switch.sql?raw";
import uniqueEntitlementSql from "../migrations/20260821130000_entitlement_installation_unique.sql?raw";
import planCatalogueMigrationSql from "../migrations/20260911120000_plan_catalogue.sql?raw";
import { isolateConfigCache } from "../src/config-cache";
import { liveHttpStatusForCode } from "../src/errors";
import { runRollup } from "../src/rollup";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    DO: DurableObjectNamespace;
  }
}

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const AUDIENCE = "ai-platform";
const NOW_SECONDS = 1_725_600_450;

const FIXTURE_ORG_ID = "org-usage-001";
const FIXTURE_PERIOD_START = "2026-09-01T00:00:00.000Z";
const FIXTURE_PERIOD_END = "2026-10-01T00:00:00.000Z";
const FIXTURE_CURRENT_PERIOD = "2026-09";
const FIXTURE_PRIOR_PERIOD = "2026-08";
const RPC_URL = "https://quota-do.internal/rpc";

const ROLLUP_WINDOW = {
  start: "2026-08-01T00:00:00.000Z",
  end: "2026-09-30T23:59:59.999Z",
};

// T010 will extract this DDL to migrations/20260911180000_usage_rollup_quota_weight.sql.
const QUOTA_WEIGHT_MIGRATION_SQL =
  "ALTER TABLE usage_rollup ADD COLUMN quota_weight INTEGER NOT NULL DEFAULT 0";

type AatClaims = {
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

type TestKeypair = {
  privateKey: CryptoKey;
  kid: string;
  publicKeyB64: string;
};

type EntitlementSnapshot = {
  plan: string;
  period_bounds: {
    period_start: string;
    period_end: string;
  };
  request_quota: number;
  token_cost_budget: {
    token_budget: number;
    cost_budget: number;
  };
  credit_budget: number;
  allowed_capabilities: string[];
  soft_threshold: number;
  status: string;
};

type AdmissionAdmitted = {
  kind: "admission";
  outcome: "admitted";
  requestId: string;
};

type InspectResponse = {
  kind: "inspect";
  state: {
    periodCounters: {
      creditsUsed: number;
    };
  };
};

type UsageSummaryBody = {
  current_period: {
    period: string;
    credits_used: number;
    credit_budget: number;
  };
  prior_periods: Array<{
    period: string;
    credits_used: number;
  }>;
};

function defaultClaims(installationId: string): AatClaims {
  return {
    iss: installationId,
    aud: AUDIENCE,
    sub: "actor-usage-001",
    org: FIXTURE_ORG_ID,
    branch: "branch-usage-001",
    role: "clinician",
    scopes: ["ai.access"],
    jti: "jti-usage-001",
    iat: NOW_SECONDS - 30,
    exp: NOW_SECONDS + 300,
    ver: "1",
  };
}

function freshInstallationId(): string {
  return crypto.randomUUID();
}

const FORBIDDEN_USAGE_SUMMARY_FIELDS = [
  "tokens",
  "tokens_used",
  "tokensUsed",
  "cost",
  "cost_used",
  "costUsed",
  "provider_price",
  "price_per_credit",
  "price",
];

let fixtureKeypair: TestKeypair;
let jtiCounter = 0;
let idempotencyKeyCounter = 0;
let requestReferenceCounter = 0;

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

async function generateTestKeypair(kid: string): Promise<TestKeypair> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const rawPublicKey = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  return {
    privateKey: keyPair.privateKey,
    kid,
    publicKeyB64: base64urlEncode(new Uint8Array(rawPublicKey)),
  };
}

async function mintToken(
  keypair: TestKeypair,
  installationId: string,
  claims: Partial<AatClaims> = {},
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const payload: AatClaims = {
    ...defaultClaims(installationId),
    iat: now - 30,
    exp: now + 300,
    ...claims,
  };
  const header = { alg: "EdDSA", kid: keypair.kid };
  const headerB64 = base64urlEncode(JSON.stringify(header));
  const payloadB64 = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    keypair.privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64urlEncode(new Uint8Array(signature))}`;
}

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);

  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function applyQuotaWeightMigration(db: D1Database): Promise<void> {
  try {
    await applyPlatformSchema(db, QUOTA_WEIGHT_MIGRATION_SQL);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes("duplicate column name")) {
      throw error;
    }
  }
}

function uniqueJti(): string {
  jtiCounter += 1;
  return `f5000000-0000-4000-8000-${String(jtiCounter).padStart(12, "0")}`;
}

function uniqueIdempotencyKey(): string {
  idempotencyKeyCounter += 1;
  return `01USAGESUMM${String(idempotencyKeyCounter).padStart(13, "0")}`;
}

function uniqueRequestReference(): string {
  requestReferenceCounter += 1;
  return `AI-USG-${String(requestReferenceCounter).padStart(5, "0")}`;
}

function buildEntitlementSnapshot(
  overrides: Partial<EntitlementSnapshot> & { credit_budget?: number } = {},
): EntitlementSnapshot {
  const { credit_budget, token_cost_budget, period_bounds, ...rest } = overrides;
  return {
    plan: "professional",
    period_bounds: period_bounds ?? {
      period_start: FIXTURE_PERIOD_START,
      period_end: FIXTURE_PERIOD_END,
    },
    request_quota: 10_000,
    token_cost_budget: token_cost_budget ?? {
      token_budget: 10_000_000,
      cost_budget: 1_000,
    },
    credit_budget: credit_budget ?? 10_000,
    allowed_capabilities: ["ai.access"],
    soft_threshold: 0.8,
    status: "active",
    ...rest,
  };
}

function quotaStub(installationId: string) {
  return env.DO.get(env.DO.idFromName(installationId));
}

async function flushBackgroundWork(): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 150));
}

async function seedQuotaDoCreditsUsed(
  installationId: string,
  creditsUsed: number,
  creditBudget: number = 10_000,
): Promise<void> {
  const entitlement = buildEntitlementSnapshot({ credit_budget: creditBudget });
  const requestReference = uniqueRequestReference();
  const admissionResponse = await quotaStub(installationId).fetch(RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      kind: "admission",
      jti: uniqueJti(),
      installationId,
      idempotencyKey: uniqueIdempotencyKey(),
      requestReference,
      entitlement,
    }),
  });
  const admission = JSON.parse(
    await admissionResponse.text(),
  ) as AdmissionAdmitted;
  expect(admission.outcome).toBe("admitted");

  const creditResponse = await quotaStub(installationId).fetch(RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      kind: "credit",
      installationId,
      requestId: admission.requestId,
      requestReference,
      usage: { tokens: 0, cost: 0 },
      credits: creditsUsed,
      partial: false,
      entitlement,
    }),
  });
  await creditResponse.text();
  await flushBackgroundWork();
}

async function rollupIdFor(installationId: string, period: string): Promise<string> {
  const dims = JSON.stringify({ installation_id: installationId, period });
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(dims),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function seedUsageRollupRow(options: {
  installationId: string;
  period: string;
  quotaWeight: number;
  requestCount?: number;
  tokens?: number;
  cost?: number;
}): Promise<void> {
  const {
    installationId,
    period,
    quotaWeight,
    requestCount = 1,
    tokens = 150,
    cost = 0.01,
  } = options;
  const dimensions = JSON.stringify({
    installation_id: installationId,
    period,
  });
  const rollupId = await rollupIdFor(installationId, period);
  await env.DB.prepare(
    `INSERT INTO usage_rollup (
       rollup_id, dimensions, request_count, tokens, cost, quota_weight
     ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(rollupId, dimensions, requestCount, tokens, cost, quotaWeight)
    .run();
}

async function clearUsageSummaryTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM usage_rollup"),
    env.DB.prepare("DELETE FROM usage_event"),
    env.DB.prepare("DELETE FROM ai_attempt"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation_key"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

async function seedInstallationKey(
  keypair: TestKeypair,
  installationId: string,
): Promise<void> {
  const enrolledAt = new Date().toISOString();
  const validFrom = new Date(Date.now() - 3_600_000).toISOString();

  await env.DB.prepare(
    `INSERT INTO installation (
      installation_id, org_id, display_name, status, region, enrolled_at
    ) VALUES (?, ?, ?, 'active', 'us-east-1', ?)`,
  )
    .bind(installationId, FIXTURE_ORG_ID, "Usage Summary Clinic", enrolledAt)
    .run();

  await env.DB.prepare(
    `INSERT INTO installation_key (
      key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at
    ) VALUES (?, ?, ?, 'EdDSA', ?, NULL, NULL)`,
  )
    .bind(keypair.kid, installationId, keypair.publicKeyB64, validFrom)
    .run();
}

async function seedEntitlement(
  installationId: string,
  creditBudget: number = 10_000,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO entitlement (
      entitlement_id, installation_id, plan, period_start, period_end,
      request_quota, token_budget, cost_budget, credit_budget,
      allowed_capabilities, soft_threshold, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      `ent-${installationId}`,
      installationId,
      "professional",
      FIXTURE_PERIOD_START,
      FIXTURE_PERIOD_END,
      10_000,
      10_000_000,
      1_000,
      creditBudget,
      JSON.stringify(["ai.access"]),
      0.8,
      "active",
    )
    .run();
}

async function seedTerminalRequestWithUsage(
  installationId: string,
  requestId: string,
  reference: string,
  quotaWeight: number,
  options?: { period?: string; tokens?: number; cost?: number },
): Promise<void> {
  const completedAt = "2026-08-15T12:00:00.000Z";
  const period = options?.period ?? FIXTURE_PRIOR_PERIOD;
  await env.DB.prepare(
    `INSERT INTO ai_request (
      request_id, request_reference, installation_id, actor_id, branch_id,
      capability_id, capability_version, prompt_artifact_hash, idempotency_key,
      trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
      payload_pointer, conversation_id, turn_ordinal
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL)`,
  )
    .bind(
      requestId,
      reference,
      installationId,
      "actor-usage-001",
      "branch-usage-001",
      "clinic.usage-test",
      "1.0.0",
      "prompt/usage@v1",
      `idem-${requestId}`,
      `trace-${requestId}`,
      "Completed",
      completedAt,
      completedAt,
      completedAt,
    )
    .run();

  await env.DB.prepare(
    `INSERT INTO usage_event (
      usage_event_id, installation_id, period, request_id, quota_weight, tokens, cost, recorded_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      `usage-${requestId}`,
      installationId,
      period,
      requestId,
      quotaWeight,
      options?.tokens ?? 150,
      options?.cost ?? 0.01,
      completedAt,
    )
    .run();
}

function usageSummaryRequest(
  token?: string,
  headers: Record<string, string> = {},
): Request {
  const requestHeaders: Record<string, string> = { ...headers };
  if (token !== undefined) {
    requestHeaders.authorization = `Bearer ${token}`;
  }
  return new Request(`${GATEWAY_ORIGIN}/v1/usage`, {
    method: "GET",
    headers: requestHeaders,
  });
}

function collectForbiddenFields(value: unknown, path = ""): string[] {
  if (value === null || typeof value !== "object") {
    return [];
  }
  if (Array.isArray(value)) {
    return value.flatMap((entry, index) =>
      collectForbiddenFields(entry, `${path}[${index}]`),
    );
  }
  const record = value as Record<string, unknown>;
  const hits: string[] = [];
  for (const [key, nested] of Object.entries(record)) {
    const fullPath = path ? `${path}.${key}` : key;
    if (FORBIDDEN_USAGE_SUMMARY_FIELDS.includes(key)) {
      hits.push(fullPath);
    }
    hits.push(...collectForbiddenFields(nested, fullPath));
  }
  return hits;
}

async function seedAuthenticatedUsageFixture(options: {
  creditsUsed: number;
  creditBudget?: number;
  priorQuotaWeight?: number;
  currentRollupDecoy?: number;
}): Promise<{ token: string; installationId: string }> {
  const installationId = freshInstallationId();
  await seedInstallationKey(fixtureKeypair, installationId);
  await seedEntitlement(installationId, options.creditBudget ?? 10_000);
  await seedQuotaDoCreditsUsed(
    installationId,
    options.creditsUsed,
    options.creditBudget ?? 10_000,
  );
  if (options.priorQuotaWeight !== undefined) {
    await seedUsageRollupRow({
      installationId,
      period: FIXTURE_PRIOR_PERIOD,
      quotaWeight: options.priorQuotaWeight,
    });
  }
  if (options.currentRollupDecoy !== undefined) {
    await seedUsageRollupRow({
      installationId,
      period: FIXTURE_CURRENT_PERIOD,
      quotaWeight: options.currentRollupDecoy,
    });
  }
  const token = await mintToken(fixtureKeypair, installationId);
  return { token, installationId };
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, tokenContractMigrationSql);
  await applyPlatformSchema(env.DB, killSwitchMigrationSql);
  await applyPlatformSchema(env.DB, uniqueEntitlementSql);
  await applyPlatformSchema(env.DB, planCatalogueMigrationSql);
  await applyQuotaWeightMigration(env.DB);
  fixtureKeypair = await generateTestKeypair("kid-usage-001");
});

beforeEach(async () => {
  isolateConfigCache.clear();
  await clearUsageSummaryTables();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("usage_summary_current_period_live_from_quota_do", () => {
  it("returns current-period credits_used and credit_budget from live Quota DO counters", async () => {
    const creditsUsed = 42;
    const creditBudget = 10_000;
    const { token } = await seedAuthenticatedUsageFixture({
      creditsUsed,
      creditBudget,
    });

    const response = await SELF.fetch(usageSummaryRequest(token));

    expect(response.status).toBe(200);
    const body = (await response.json()) as UsageSummaryBody;
    expect(body.current_period.period).toBe(FIXTURE_CURRENT_PERIOD);
    expect(body.current_period.credits_used).toBe(creditsUsed);
    expect(body.current_period.credit_budget).toBe(creditBudget);
  });
});

describe("usage_summary_prior_periods_from_usage_rollup", () => {
  it("answers prior credits_used from usage_rollup.quota_weight without scanning usage_event", async () => {
    const priorQuotaWeight = 800;
    const { token } = await seedAuthenticatedUsageFixture({
      creditsUsed: 12,
      priorQuotaWeight,
    });

    const prepareSpy = vi.spyOn(env.DB, "prepare");

    const response = await SELF.fetch(usageSummaryRequest(token));

    expect(response.status).toBe(200);
    const body = (await response.json()) as UsageSummaryBody;
    expect(body.current_period.period).toBe(FIXTURE_CURRENT_PERIOD);
    expect(body.prior_periods).toEqual([
      { period: FIXTURE_PRIOR_PERIOD, credits_used: priorQuotaWeight },
    ]);

    const sqlStatements = prepareSpy.mock.calls.map(([sql]) => String(sql));
    expect(
      sqlStatements.some((sql) => /\busage_event\b/i.test(sql)),
    ).toBe(false);
  });
});

describe("usage_rollup_carries_quota_weight_aggregate", () => {
  it("stores usage_rollup.quota_weight equal to SUM(usage_event.quota_weight)", async () => {
    const installationId = freshInstallationId();
    await seedInstallationKey(fixtureKeypair, installationId);
    await seedTerminalRequestWithUsage(
      installationId,
      "req-u1",
      "REF-U001",
      3,
    );
    await seedTerminalRequestWithUsage(
      installationId,
      "req-u2",
      "REF-U002",
      5,
    );

    await runRollup({ db: env.DB, window: ROLLUP_WINDOW });

    const ledger = await env.DB.prepare(
      `SELECT SUM(quota_weight) AS quota_weight,
              SUM(tokens) AS tokens,
              SUM(cost) AS cost,
              COUNT(*) AS request_count
       FROM usage_event
       WHERE installation_id = ? AND period = ?`,
    )
      .bind(installationId, FIXTURE_PRIOR_PERIOD)
      .first<{
        quota_weight: number;
        tokens: number;
        cost: number;
        request_count: number;
      }>();

    const rollup = await env.DB.prepare(
      `SELECT quota_weight, tokens, cost, request_count
       FROM usage_rollup
       WHERE dimensions = ?`,
    )
      .bind(
        JSON.stringify({
          installation_id: installationId,
          period: FIXTURE_PRIOR_PERIOD,
        }),
      )
      .first<{
        quota_weight: number;
        tokens: number;
        cost: number;
        request_count: number;
      }>();

    expect(rollup?.quota_weight).toBe(ledger?.quota_weight);
    expect(rollup?.tokens).toBe(ledger?.tokens);
    expect(rollup?.cost).toBe(ledger?.cost);
    expect(rollup?.request_count).toBe(ledger?.request_count);
  });
});

describe("usage_summary_live_and_historical_from_different_sources", () => {
  it("serves live current-period credits from Quota DO and history from usage_rollup only", async () => {
    const liveCreditsUsed = 55;
    const rollupDecoyCurrent = 9_999;
    const priorQuotaWeight = 640;
    const { token, installationId } = await seedAuthenticatedUsageFixture({
      creditsUsed: liveCreditsUsed,
      priorQuotaWeight,
      currentRollupDecoy: rollupDecoyCurrent,
    });

    const doInspectBodies: unknown[] = [];
    const realGet = env.DO.get.bind(env.DO);
    vi.spyOn(env.DO, "get").mockImplementation((id: DurableObjectId) => {
      const stub = realGet(id);
      return {
        fetch: async (url: string, init?: RequestInit) => {
          if (init?.body) {
            const parsed = JSON.parse(String(init.body)) as { kind?: string };
            if (parsed.kind === "inspect") {
              doInspectBodies.push(parsed);
            }
          }
          return stub.fetch(url, init);
        },
      } as DurableObjectStub;
    });

    const prepareSpy = vi.spyOn(env.DB, "prepare");

    const response = await SELF.fetch(usageSummaryRequest(token));

    expect(response.status).toBe(200);
    const body = (await response.json()) as UsageSummaryBody;
    expect(body.current_period.credits_used).toBe(liveCreditsUsed);
    expect(body.current_period.credits_used).not.toBe(rollupDecoyCurrent);
    expect(body.prior_periods).toEqual([
      { period: FIXTURE_PRIOR_PERIOD, credits_used: priorQuotaWeight },
    ]);

    expect(doInspectBodies.length).toBeGreaterThan(0);

    const sqlStatements = prepareSpy.mock.calls.map(([sql]) => String(sql));
    expect(sqlStatements.some((sql) => /\busage_rollup\b/i.test(sql))).toBe(true);
    expect(
      sqlStatements.some((sql) => /\busage_event\b/i.test(sql)),
    ).toBe(false);

    const inspect = await quotaStub(installationId).fetch(RPC_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ kind: "inspect" }),
    });
    const inspectBody = JSON.parse(
      await inspect.text(),
    ) as InspectResponse;
    expect(
      body.prior_periods.every(
        (row) => row.credits_used !== inspectBody.state.periodCounters.creditsUsed,
      ),
    ).toBe(true);
  });
});

describe("usage_summary_unauthenticated_taxonomy_unauthorized", () => {
  it("returns taxonomy unauthenticated without a credits body for missing or invalid auth", async () => {
    const installationId = freshInstallationId();
    await seedInstallationKey(fixtureKeypair, installationId);
    await seedEntitlement(installationId);

    const missing = await SELF.fetch(usageSummaryRequest());
    expect(missing.status).toBe(liveHttpStatusForCode("unauthenticated"));
    const missingBody = (await missing.json()) as { code: string; current_period?: unknown };
    expect(missingBody.code).toBe("unauthenticated");
    expect(missingBody.current_period).toBeUndefined();

    const invalid = await SELF.fetch(usageSummaryRequest("not-a-valid-token"));
    expect(invalid.status).toBe(liveHttpStatusForCode("unauthenticated"));
    const invalidBody = (await invalid.json()) as { code: string; current_period?: unknown };
    expect(invalidBody.code).toBe("unauthenticated");
    expect(invalidBody.current_period).toBeUndefined();

    const nonBearer = await SELF.fetch(
      usageSummaryRequest(undefined, { Authorization: "Basic not-an-aat" }),
    );
    expect(nonBearer.status).toBe(liveHttpStatusForCode("unauthenticated"));
    const nonBearerBody = (await nonBearer.json()) as {
      code: string;
      current_period?: unknown;
    };
    expect(nonBearerBody.code).toBe("unauthenticated");
    expect(nonBearerBody.current_period).toBeUndefined();
  });
});

describe("usage_summary_credits_only_no_prices_tokens_or_cost_actuals", () => {
  it("returns credits-only JSON without provider prices, token fields, or cost actuals", async () => {
    const { token } = await seedAuthenticatedUsageFixture({
      creditsUsed: 18,
      priorQuotaWeight: 220,
    });

    const response = await SELF.fetch(usageSummaryRequest(token));

    expect(response.status).toBe(200);
    const body = (await response.json()) as UsageSummaryBody;
    expect(body).toHaveProperty("current_period");
    expect(body).toHaveProperty("prior_periods");
    expect(collectForbiddenFields(body)).toEqual([]);
  });
});
