import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertSseSequence,
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  controlFetch,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  env,
  flushBackgroundWork,
  gatewayObjectJson,
  getAiRequest,
  getEntitlement,
  getR2Json,
  getRoutingPolicy,
  isolateConfigCache,
  mintAat,
  newScenario,
  POLICY_ID,
  POLICY_REF,
  postRequest,
  provisionHappyPath,
  queryOne,
  resetE2eState,
  seedSql,
  visitSummaryInvokeBody,
  type EntitlePayload,
  type HttpResult,
  type Scenario,
} from "./harness";
// HARNESS-GAP: dashboards not on frozen barrel; catalog SQL-contract calls the export
import {
  dashboardQuotaRejectionRate,
  dashboardRepairRateByCapability,
} from "../../src/dashboards";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

/** Matches `quota-do/index.ts` `EPHEMERAL_HORIZON_MS`. */
const EPHEMERAL_HORIZON_MS = 7_200_000;
const DASHBOARD_NOW = new Date("2026-09-05T00:00:00.000Z");
const MS_PER_DAY = 24 * 60 * 60 * 1000;

const S12_056_ENTITLE: EntitlePayload = {
  ...DEFAULT_ENTITLE_PAYLOAD,
  period_start: "2026-09-01T00:00:00.000Z",
  period_end: "2026-10-01T00:00:00.000Z",
  request_quota: 1000,
  token_budget: 500000,
  cost_budget: 25.0,
};

const HIGH_QUOTA_ENTITLE: EntitlePayload = {
  ...DEFAULT_ENTITLE_PAYLOAD,
  request_quota: 10_000,
};

const QUOTA_INSPECT_KEYS = [
  "admitted_requests",
  "bound_installation_id",
  "credited_requests",
  "entitlement",
  "idempotency_keys",
  "installation_id",
  "jti_replay_entries",
  "period_bounds",
  "period_counters",
  "remaining",
] as const;

type QuotaInspectBody = {
  installation_id: string;
  bound_installation_id: string | null;
  period_bounds: { period_start: string; period_end: string } | null;
  period_counters: {
    requests_used: number;
    tokens_used: number;
    cost_used: number;
    in_flight: number;
  };
  entitlement: {
    plan: string;
    status: string;
    period_start: string;
    period_end: string;
    request_quota: number;
    token_budget: number;
    cost_budget: number;
  } | null;
  remaining: { requests: number; tokens: number; cost: number } | null;
  idempotency_keys: number;
  jti_replay_entries: number;
  admitted_requests: number;
  credited_requests: number;
  maps?: {
    idempotency: Record<
      string,
      { state?: string; requestId?: string; expiresAt?: number }
    >;
    jti_replay: Record<string, { expiresAt?: number }>;
    admitted_requests: Record<string, unknown>;
    credited_requests: Record<string, { expiresAt?: number }>;
    truncated: boolean;
  };
};

type InspectRpcState = {
  periodCounters?: {
    inFlight?: number;
    requestsUsed?: number;
  };
  admittedRequests?: Record<string, { admittedAt?: number }>;
  idempotency?: Record<
    string,
    { state?: string; requestId?: string; expiresAt?: number }
  >;
};

async function getQuota(
  installationId: string,
  query = "",
): Promise<HttpResult> {
  return controlFetch(
    `/control/installations/${installationId}/quota${query}`,
    { method: "GET", auth: "operator" },
  );
}

function quotaBody(result: HttpResult): QuotaInspectBody {
  return result.json as QuotaInspectBody;
}

async function enrollAndEntitle(
  entitle: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<Scenario> {
  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  const entitled = await entitleInstallation(scenario, entitle);
  expect(entitled.status).toBe(200);
  return scenario;
}

async function entitlementSnapshot(
  installationId: string,
): Promise<Record<string, unknown>> {
  const row = await getEntitlement(installationId);
  expect(row).not.toBeNull();
  const rawAllowed = row!.allowed_capabilities;
  const allowed =
    typeof rawAllowed === "string" ? JSON.parse(rawAllowed) : rawAllowed;
  return {
    plan: String(row!.plan),
    period_bounds: {
      period_start: String(row!.period_start),
      period_end: String(row!.period_end),
    },
    request_quota: Number(row!.request_quota),
    token_cost_budget: {
      token_budget: Number(row!.token_budget),
      cost_budget: Number(row!.cost_budget),
    },
    allowed_capabilities: allowed,
    soft_threshold: Number(row!.soft_threshold),
    status: String(row!.status),
  };
}

async function inspectDo(
  installationId: string,
  now?: number,
): Promise<{ status: number; kind?: string; state: InspectRpcState }> {
  const result = await gatewayObjectJson(
    installationId,
    { kind: "inspect" },
    now === undefined ? {} : { now },
  );
  const json = result.json as { kind?: string; state?: InspectRpcState };
  return {
    status: result.status,
    kind: json.kind,
    state: json.state ?? {},
  };
}

async function admitOnce(
  scenario: Scenario,
  opts: {
    jti: string;
    idempotencyKey: string;
    requestReference: string;
    now?: number;
    entitlement?: Record<string, unknown>;
  },
): Promise<{ status: number; outcome?: string; requestId?: string }> {
  const entitlement =
    opts.entitlement ?? (await entitlementSnapshot(scenario.installationId));
  const result = await gatewayObjectJson(
    scenario.installationId,
    {
      kind: "admission",
      jti: opts.jti,
      installationId: scenario.installationId,
      idempotencyKey: opts.idempotencyKey,
      entitlement,
      requestReference: opts.requestReference,
    },
    opts.now === undefined ? {} : { now: opts.now },
  );
  const json = result.json as { outcome?: string; requestId?: string };
  return {
    status: result.status,
    outcome: json.outcome,
    requestId: json.requestId,
  };
}

/**
 * Pool TTL is 100 ms. Parallel files share isolateConfigCache and call
 * clear(); preload→consult can then miss
 * `active_routing_policy:routing/standard` (ConfigCacheMissError → Failed
 * with routing_decision null). Raise TTL and re-stamp the just-promoted
 * policy immediately before POST so the post-accept consult cannot miss.
 */
const SERVE_CACHE_TTL_MS = 30_000;

async function loadServingPolicyRow(
  policyVersion?: string,
): Promise<Record<string, unknown>> {
  const row = policyVersion
    ? await getRoutingPolicy(POLICY_ID, policyVersion)
    : await queryOne(
        `SELECT * FROM routing_policy
         WHERE policy_id = ? AND status = 'active'
         ORDER BY active_from DESC, rowid DESC LIMIT 1`,
        [POLICY_ID],
      );
  expect(row?.status).toBe("active");
  const pointer = String(row!.content_pointer ?? "");
  const document = await getR2Json(pointer);
  return { ...row!, document };
}

function pinServingRoutingPolicy(
  policyRow: Record<string, unknown>,
  installationIds: readonly string[],
): void {
  isolateConfigCache.setTtlMs(SERVE_CACHE_TTL_MS);
  isolateConfigCache.remember("active_routing_policy", POLICY_REF, policyRow);
  for (const installationId of installationIds) {
    isolateConfigCache.remember(
      "active_routing_policy",
      `${POLICY_REF}/${installationId}`,
      policyRow,
    );
  }
}

async function settleCompleted(): Promise<{
  scenario: Scenario;
  idempotencyKey: string;
  jti: string;
  requestId: string;
  requestReference: string;
}> {
  const scenario = await provisionHappyPath();
  const jti = crypto.randomUUID();
  const idempotencyKey = `idem-s12-057-${crypto.randomUUID()}`;
  const token = await mintAat(scenario, { claims: { jti, ver: "1" } });
  const policyRow = await loadServingPolicyRow();
  pinServingRoutingPolicy(policyRow, [scenario.installationId]);
  const result = await postRequest(scenario, {
    token,
    idempotencyKey,
    traceId: "s12-057-trace",
    body: visitSummaryInvokeBody(scenario),
  });
  await flushBackgroundWork(200);
  expect(result.status).toBe(200);
  assertSseSequence(result.events, ["accepted", "completed"], "subsequence");
  const requestReference = String(result.events[0]?.data.request_reference);
  const row = await getAiRequest(requestReference);
  expect(row).not.toBeNull();
  expect(row!.state).toBe("Completed");
  return {
    scenario,
    idempotencyKey,
    jti,
    requestId: String(row!.request_id),
    requestReference,
  };
}

async function enrollThrowaway(): Promise<Scenario> {
  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  return scenario;
}

function crockfordRef(prefix: string, index: number): string {
  return `${prefix}-${String(index).padStart(4, "0")}`;
}

function aiRequestSeed(opts: {
  requestId: string;
  requestReference: string;
  installationId: string;
  actorId: string;
  state: string;
  createdAt: string;
}): { sql: string; params: unknown[] } {
  return {
    sql: `INSERT INTO ai_request (
            request_id, request_reference, installation_id, actor_id,
            capability_id, capability_version, prompt_artifact_hash,
            idempotency_key, state, created_at, updated_at, trace_id
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    params: [
      opts.requestId,
      opts.requestReference,
      opts.installationId,
      opts.actorId,
      CAPABILITY_ID,
      CAPABILITY_VERSION,
      "deadbeef",
      `idem-${opts.requestId}`,
      opts.state,
      opts.createdAt,
      opts.createdAt,
      `trace-${opts.requestId}`,
    ],
  };
}

function aiAttemptSeed(opts: {
  attemptId: string;
  requestId: string;
  attemptNo: number;
  outcome: string;
}): { sql: string; params: unknown[] } {
  return {
    sql: `INSERT INTO ai_attempt (
            attempt_id, request_id, attempt_no, provider, model, outcome,
            latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
          ) VALUES (?, ?, ?, 'fake', 'fake-v1', ?, 10, 10, 20, 0.005, NULL, NULL)`,
    params: [opts.attemptId, opts.requestId, opts.attemptNo, opts.outcome],
  };
}

function counterSeed(opts: {
  counterId: string;
  dimensionSet: string;
  timeBucket: string;
  count: number;
}): { sql: string; params: unknown[] } {
  return {
    sql: `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
          VALUES (?, ?, ?, ?)`,
    params: [opts.counterId, opts.dimensionSet, opts.timeBucket, opts.count],
  };
}

function assertZeroedDo(body: QuotaInspectBody, installationId: string): void {
  expect(body.installation_id).toBe(installationId);
  expect(body.bound_installation_id).toBeNull();
  expect(body.period_bounds).toBeNull();
  expect(body.period_counters).toEqual({
    requests_used: 0,
    tokens_used: 0,
    cost_used: 0,
    in_flight: 0,
  });
  expect(body.idempotency_keys).toBe(0);
  expect(body.jti_replay_entries).toBe(0);
  expect(body.admitted_requests).toBe(0);
  expect(body.credited_requests).toBe(0);
  expect(body).not.toHaveProperty("maps");
}

describe("Stage 12 — quota inspect and dashboards (S12-056…S12-072)", () => {
  it("S12-056 — Fresh installation, zeroed quota inspect", async () => {
    const scenario = await enrollAndEntitle(S12_056_ENTITLE);
    const result = await getQuota(scenario.installationId);
    expect(result.status).toBe(200);
    const body = quotaBody(result);
    expect(Object.keys(body).sort()).toEqual([...QUOTA_INSPECT_KEYS].sort());
    assertZeroedDo(body, scenario.installationId);
    // entitle does not set plan; enroll payload plan is "standard".
    expect(body.entitlement).toMatchObject({
      plan: "standard",
      status: "active",
      period_start: "2026-09-01T00:00:00.000Z",
      period_end: "2026-10-01T00:00:00.000Z",
      request_quota: 1000,
      token_budget: 500000,
    });
    expect(Number(body.entitlement?.cost_budget)).toBeCloseTo(25, 5);
    expect(body.remaining?.requests).toBe(1000);
    expect(body.remaining?.tokens).toBe(500000);
    expect(Number(body.remaining?.cost)).toBeCloseTo(25, 5);
  });

  it("S12-057 — Quota inspect after Completed settlement", async () => {
    const settled = await settleCompleted();
    const entitlement = await getEntitlement(settled.scenario.installationId);
    expect(entitlement).not.toBeNull();

    const result = await getQuota(settled.scenario.installationId);
    expect(result.status).toBe(200);
    const body = quotaBody(result);
    expect(body).not.toHaveProperty("maps");
    expect(body.installation_id).toBe(settled.scenario.installationId);
    expect(body.bound_installation_id).toBe(settled.scenario.installationId);
    expect(body.period_bounds).toEqual({
      period_start: String(entitlement!.period_start),
      period_end: String(entitlement!.period_end),
    });
    expect(body.period_counters.requests_used).toBe(1);
    expect(body.period_counters.tokens_used).toBe(30);
    expect(Number(body.period_counters.cost_used)).toBeCloseTo(0.005, 6);
    expect(body.period_counters.in_flight).toBe(0);
    expect(body.idempotency_keys).toBe(1);
    expect(body.jti_replay_entries).toBe(1);
    expect(body.admitted_requests).toBe(0);
    expect(body.credited_requests).toBe(1);
    expect(body.remaining?.requests).toBe(Number(entitlement!.request_quota) - 1);
    expect(body.remaining?.tokens).toBe(Number(entitlement!.token_budget) - 30);
    expect(Number(body.remaining?.cost)).toBeCloseTo(
      Number(entitlement!.cost_budget) - 0.005,
      5,
    );
  });

  it("S12-058 — In-flight admission without credit", async () => {
    const scenario = await enrollAndEntitle();
    const admitted = await admitOnce(scenario, {
      jti: "jti-s12-058",
      idempotencyKey: "idem-s12-058",
      requestReference: "5TPX-8RND",
    });
    expect(admitted.status).toBe(200);
    expect(admitted.outcome).toBe("admitted");

    const result = await getQuota(scenario.installationId, "?verbose=true");
    expect(result.status).toBe(200);
    const body = quotaBody(result);
    expect(body.period_counters.in_flight).toBe(1);
    expect(body.period_counters.requests_used).toBe(0);
    expect(body.admitted_requests).toBe(1);
    expect(body.idempotency_keys).toBe(1);
    expect(body.jti_replay_entries).toBe(1);
    expect(body.credited_requests).toBe(0);
    expect(body.maps?.idempotency["idem-s12-058"]?.state).toBe("admitted");
  });

  it("S12-059 — verbose=true includes maps; other verbose values omit them", async () => {
    const settled = await settleCompleted();
    const verbose = await getQuota(
      settled.scenario.installationId,
      "?verbose=true",
    );
    expect(verbose.status).toBe(200);
    const verboseBody = quotaBody(verbose);
    expect(verboseBody.period_counters.requests_used).toBe(1);
    expect(verboseBody.credited_requests).toBe(1);
    expect(verboseBody.maps).toBeDefined();
    expect(Object.keys(verboseBody.maps!).sort()).toEqual(
      [
        "admitted_requests",
        "credited_requests",
        "idempotency",
        "jti_replay",
        "truncated",
      ].sort(),
    );
    expect(verboseBody.maps!.truncated).toBe(false);
    expect(verboseBody.maps!.idempotency[settled.idempotencyKey]?.state).toBe(
      "completed",
    );
    expect(verboseBody.maps!.jti_replay[settled.jti]).toBeDefined();
    expect(verboseBody.maps!.admitted_requests).toEqual({});
    expect(verboseBody.maps!.credited_requests[settled.requestId]).toBeDefined();

    for (const query of ["", "?verbose=1", "?verbose=false"]) {
      const result = await getQuota(settled.scenario.installationId, query);
      expect(result.status).toBe(200);
      expect(quotaBody(result)).not.toHaveProperty("maps");
    }
  });

  it("S12-060 — verbose maps truncate at 500; counts stay 501", async () => {
    // Register 5 #43: slow (501 admissions) but automatable. Do not skip.
    // Admission concurrency cap is 16; credit after each admit so 501
    // idempotency keys persist (credit keeps the map entry).
    const scenario = await enrollAndEntitle(HIGH_QUOTA_ENTITLE);
    const snapshot = await entitlementSnapshot(scenario.installationId);

    for (let index = 0; index < 501; index += 1) {
      const requestReference = crockfordRef("A060", index);
      const admitted = await admitOnce(scenario, {
        jti: `jti-s12-060-${index}`,
        idempotencyKey: `idem-s12-060-${index}`,
        requestReference,
        entitlement: snapshot,
      });
      expect(admitted.status).toBe(200);
      expect(admitted.outcome).toBe("admitted");
      expect(admitted.requestId).toBeTruthy();

      const credited = await gatewayObjectJson(scenario.installationId, {
        kind: "credit",
        installationId: scenario.installationId,
        requestId: admitted.requestId,
        requestReference,
        usage: { tokens: 0, cost: 0 },
        partial: false,
      });
      expect(credited.status).toBe(200);
      const creditBody = credited.json as { ok?: boolean };
      expect(creditBody.ok).toBe(true);
    }

    const verbose = await getQuota(scenario.installationId, "?verbose=true");
    expect(verbose.status).toBe(200);
    const verboseBody = quotaBody(verbose);
    expect(Object.keys(verboseBody.maps?.idempotency ?? {})).toHaveLength(500);
    expect(verboseBody.maps?.truncated).toBe(true);

    const plain = await getQuota(scenario.installationId);
    expect(plain.status).toBe(200);
    const plainBody = quotaBody(plain);
    expect(plainBody).not.toHaveProperty("maps");
    expect(plainBody.idempotency_keys).toBe(501);
  }, 120_000);

  it("S12-061 — [SEED] installation without entitlement returns nulls", async () => {
    const installationId = crypto.randomUUID();
    const orgId = crypto.randomUUID();
    await seedSql([
      {
        sql: `INSERT INTO installation (
                installation_id, org_id, display_name, status, region, enrolled_at
              ) VALUES (?, ?, ?, 'active', 'us-east-1', ?)`,
        params: [
          installationId,
          orgId,
          "S12-061 no entitlement",
          "2026-09-01T00:00:00.000Z",
        ],
      },
    ]);

    const result = await getQuota(installationId);
    expect(result.status).toBe(200);
    const body = quotaBody(result);
    expect(body.entitlement).toBeNull();
    expect(body.remaining).toBeNull();
    assertZeroedDo(body, installationId);
  });

  it("S12-062 — unknown installation returns 404 installation_not_found", async () => {
    const result = await getQuota("11111111-9999-4333-8444-555555555555");
    expect(result.status).toBe(404);
    expect(result.json).toEqual({ error: "installation_not_found" });
  });

  it("S12-063 — missing or clinic AAT bearer returns 401 unauthorized", async () => {
    const scenario = await enrollAndEntitle();
    const path = `/control/installations/${scenario.installationId}/quota`;

    const missing = await controlFetch(path, { method: "GET", auth: "none" });
    expect(missing.status).toBe(401);
    expect(missing.json).toEqual({ error: "unauthorized" });

    const aat = await mintAat(scenario, { claims: { ver: "1" } });
    const clinic = await controlFetch(path, {
      method: "GET",
      auth: { bearer: aat },
    });
    expect(clinic.status).toBe(401);
    expect(clinic.json).toEqual({ error: "unauthorized" });
  });

  it("S12-064 — POST quota inspect returns 405 method_not_allowed", async () => {
    const scenario = await enrollAndEntitle();
    const result = await controlFetch(
      `/control/installations/${scenario.installationId}/quota`,
      { method: "POST", auth: "operator" },
    );
    expect(result.status).toBe(405);
    expect(result.json).toEqual({ error: "method_not_allowed" });
  });

  it("S12-065 — inspectRPC sweeps abandoned admissions in memory only", async () => {
    const scenario = await enrollAndEntitle();
    const t = Date.now();
    const admitted = await admitOnce(scenario, {
      jti: "jti-s12-065",
      idempotencyKey: "idem-s12-065",
      requestReference: "S065-0001",
      now: t,
    });
    expect(admitted.status).toBe(200);
    expect(admitted.outcome).toBe("admitted");
    expect(admitted.requestId).toBeTruthy();

    const atT = await inspectDo(scenario.installationId, t);
    expect(atT.status).toBe(200);
    expect(atT.kind).toBe("inspect");
    expect(atT.state.periodCounters?.inFlight).toBe(1);
    expect(Object.keys(atT.state.admittedRequests ?? {})).toHaveLength(1);
    expect(atT.state.admittedRequests?.[String(admitted.requestId)]).toBeDefined();
    expect(atT.state.idempotency?.["idem-s12-065"]?.state).toBe("admitted");
    const originalExpiry = atT.state.idempotency?.["idem-s12-065"]?.expiresAt;
    expect(originalExpiry).toBe(t + EPHEMERAL_HORIZON_MS);

    const swept = await inspectDo(
      scenario.installationId,
      t + EPHEMERAL_HORIZON_MS + 1,
    );
    expect(swept.status).toBe(200);
    expect(swept.kind).toBe("inspect");
    expect(swept.state.periodCounters?.inFlight).toBe(0);
    expect(swept.state.admittedRequests ?? {}).toEqual({});
    expect(swept.state.idempotency?.["idem-s12-065"]?.state).toBe("failed");
    expect(swept.state.idempotency?.["idem-s12-065"]?.expiresAt).toBe(
      t + EPHEMERAL_HORIZON_MS + 1 + EPHEMERAL_HORIZON_MS,
    );

    // inspectRPC never storage.put — unswept state is still stored.
    const again = await inspectDo(scenario.installationId, t + 1);
    expect(again.status).toBe(200);
    expect(again.kind).toBe("inspect");
    expect(again.state.periodCounters?.inFlight).toBe(1);
    expect(again.state.admittedRequests?.[String(admitted.requestId)]).toBeDefined();
    expect(again.state.idempotency?.["idem-s12-065"]?.state).toBe("admitted");
    expect(again.state.idempotency?.["idem-s12-065"]?.expiresAt).toBe(
      originalExpiry,
    );
  });

  it("S12-066 — dashboardQuotaRejectionRate is 0.75", async () => {
    const scenario = await enrollThrowaway();
    const createdAt = "2026-08-01T00:00:00.000Z";
    const dimensionSet = JSON.stringify({
      error_code: "quota_exhausted",
      installation_id: scenario.installationId,
    });
    await seedSql([
      ...[0, 1, 2, 3].map((index) =>
        aiRequestSeed({
          requestId: crypto.randomUUID(),
          requestReference: crockfordRef("D066", index),
          installationId: scenario.installationId,
          actorId: scenario.actorId,
          state: "Completed",
          createdAt,
        }),
      ),
      counterSeed({
        counterId: crypto.randomUUID(),
        dimensionSet,
        timeBucket: createdAt,
        count: 2,
      }),
      counterSeed({
        counterId: crypto.randomUUID(),
        dimensionSet,
        timeBucket: "2026-09-01T00:00:00.000Z",
        count: 1,
      }),
    ]);

    const rate = await dashboardQuotaRejectionRate(env.DB, DASHBOARD_NOW);
    expect(rate).toBe(0.75);
  });

  it("S12-067 — dashboardQuotaRejectionRate is 0 on an empty window", async () => {
    expect(await dashboardQuotaRejectionRate(env.DB)).toBe(0);

    await seedSql([
      counterSeed({
        counterId: crypto.randomUUID(),
        dimensionSet: '{"error_code":"quota_exhausted"}',
        timeBucket: new Date().toISOString(),
        count: 9,
      }),
    ]);
    expect(await dashboardQuotaRejectionRate(env.DB)).toBe(0);
  });

  it("S12-068 — unflushed tallies make the numerator a lower bound of 0", async () => {
    const scenario = await enrollThrowaway();
    const createdAt = new Date().toISOString();
    await seedSql(
      Array.from({ length: 10 }, (_, index) =>
        aiRequestSeed({
          requestId: crypto.randomUUID(),
          requestReference: crockfordRef("D068", index),
          installationId: scenario.installationId,
          actorId: scenario.actorId,
          state: "Completed",
          createdAt,
        }),
      ),
    );

    expect(await dashboardQuotaRejectionRate(env.DB)).toBe(0);
  });

  it("S12-069 — out-of-window rows are excluded from both sides", async () => {
    const scenario = await enrollThrowaway();
    const inWindow = "2026-08-01T00:00:00.000Z";
    const aged = new Date(DASHBOARD_NOW.getTime() - 91 * MS_PER_DAY).toISOString();
    const dimensionSet = '{"error_code":"quota_exhausted"}';

    await seedSql([
      ...[0, 1].map((index) =>
        aiRequestSeed({
          requestId: crypto.randomUUID(),
          requestReference: crockfordRef("D069", index),
          installationId: scenario.installationId,
          actorId: scenario.actorId,
          state: "Completed",
          createdAt: inWindow,
        }),
      ),
      ...[2, 3, 4, 5, 6].map((index) =>
        aiRequestSeed({
          requestId: crypto.randomUUID(),
          requestReference: crockfordRef("D069", index),
          installationId: scenario.installationId,
          actorId: scenario.actorId,
          state: "Completed",
          createdAt: aged,
        }),
      ),
      counterSeed({
        counterId: crypto.randomUUID(),
        dimensionSet,
        timeBucket: inWindow,
        count: 1,
      }),
      ...[0, 1, 2, 3].map(() =>
        counterSeed({
          counterId: crypto.randomUUID(),
          dimensionSet,
          timeBucket: aged,
          count: 10,
        }),
      ),
    ]);

    const rate = await dashboardQuotaRejectionRate(env.DB, DASHBOARD_NOW);
    expect(rate).toBe(0.5);
  });

  it("S12-070 — repair rate is 0.5 for Completed+repair and Failed with none", async () => {
    const scenario = await enrollThrowaway();
    const createdAt = "2026-09-04T00:00:00.000Z";
    const completedId = crypto.randomUUID();
    const failedId = crypto.randomUUID();
    await seedSql([
      aiRequestSeed({
        requestId: completedId,
        requestReference: "D070-0000",
        installationId: scenario.installationId,
        actorId: scenario.actorId,
        state: "Completed",
        createdAt,
      }),
      aiRequestSeed({
        requestId: failedId,
        requestReference: "D070-0001",
        installationId: scenario.installationId,
        actorId: scenario.actorId,
        state: "Failed",
        createdAt,
      }),
      aiAttemptSeed({
        attemptId: crypto.randomUUID(),
        requestId: completedId,
        attemptNo: 1,
        outcome: "terminal_failure",
      }),
      aiAttemptSeed({
        attemptId: crypto.randomUUID(),
        requestId: completedId,
        attemptNo: 2,
        outcome: "repair",
      }),
    ]);

    const rates = await dashboardRepairRateByCapability(env.DB, DASHBOARD_NOW);
    expect(rates).toEqual({ "clinic.visit_summary": 0.5 });
  });

  it("S12-071 — Cancelled and in-flight requests are excluded from repair rate", async () => {
    const scenario = await enrollThrowaway();
    const createdAt = "2026-09-04T00:00:00.000Z";
    const completedId = crypto.randomUUID();
    const cancelledId = crypto.randomUUID();
    const invokingId = crypto.randomUUID();
    await seedSql([
      aiRequestSeed({
        requestId: completedId,
        requestReference: "D071-0000",
        installationId: scenario.installationId,
        actorId: scenario.actorId,
        state: "Completed",
        createdAt,
      }),
      aiRequestSeed({
        requestId: cancelledId,
        requestReference: "D071-0001",
        installationId: scenario.installationId,
        actorId: scenario.actorId,
        state: "Cancelled",
        createdAt,
      }),
      aiRequestSeed({
        requestId: invokingId,
        requestReference: "D071-0002",
        installationId: scenario.installationId,
        actorId: scenario.actorId,
        state: "Invoking",
        createdAt,
      }),
      aiAttemptSeed({
        attemptId: crypto.randomUUID(),
        requestId: completedId,
        attemptNo: 1,
        outcome: "repair",
      }),
      aiAttemptSeed({
        attemptId: crypto.randomUUID(),
        requestId: cancelledId,
        attemptNo: 1,
        outcome: "repair",
      }),
      aiAttemptSeed({
        attemptId: crypto.randomUUID(),
        requestId: invokingId,
        attemptNo: 1,
        outcome: "repair",
      }),
    ]);

    const rates = await dashboardRepairRateByCapability(env.DB, DASHBOARD_NOW);
    expect(rates).toEqual({ "clinic.visit_summary": 1.0 });
  });

  it("S12-072 — empty repair-rate window returns {}", async () => {
    expect(await dashboardRepairRateByCapability(env.DB, DASHBOARD_NOW)).toEqual(
      {},
    );

    const scenario = await enrollThrowaway();
    const aged = new Date(DASHBOARD_NOW.getTime() - 91 * MS_PER_DAY).toISOString();
    await seedSql([
      aiRequestSeed({
        requestId: crypto.randomUUID(),
        requestReference: "D072-0000",
        installationId: scenario.installationId,
        actorId: scenario.actorId,
        state: "Completed",
        createdAt: aged,
      }),
    ]);
    expect(await dashboardRepairRateByCapability(env.DB, DASHBOARD_NOW)).toEqual(
      {},
    );
  });
});
