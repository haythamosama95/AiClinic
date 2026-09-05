/**
 * Stage X — credit / inspect / retention joinability / GatewayObject RPC
 * (SX-049…SX-063).
 */
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertSseSequence,
  bootstrapE2e,
  controlFetch,
  count,
  CRON_RETENTION,
  CRON_ROLLUP,
  QUOTA_DO_RPC_URL,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  env,
  flushBackgroundWork,
  gatewayObjectJson,
  getAiRequest,
  getEntitlement,
  getRequestByRef,
  invokeCron,
  mintAat,
  newScenario,
  postRequest,
  provisionHappyPath,
  queryAll,
  queryOne,
  r2Exists,
  resetE2eState,
  seedSql,
  visitSummaryInvokeBody,
  type EntitlePayload,
  type Scenario,
} from "./harness";
// HARNESS-GAP: recordGuardRejection is not on the frozen barrel (SX-056).
import { recordGuardRejection } from "../../src/rate-limit";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const EPHEMERAL_HORIZON_MS = 7_200_000;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Catalog P2 window after P1 admissions (SX-051 / SX-052). */
const P2_ENTITLE: EntitlePayload = {
  ...DEFAULT_ENTITLE_PAYLOAD,
  period_start: "2026-09-01T00:00:00.000Z",
  period_end: "2026-10-01T00:00:00.000Z",
};

/**
 * Wall-clock-covering entitle whose `period_start` month is catalog 2026-08
 * (DEFAULT_ENTITLE_PAYLOAD is 2026-01…2027-01; period string would be 2026-01).
 */
const AUGUST_COVERING_NOW: EntitlePayload = {
  ...DEFAULT_ENTITLE_PAYLOAD,
  period_start: "2026-08-01T00:00:00.000Z",
  period_end: "2027-01-01T00:00:00.000Z",
};

type QuotaDoInspectState = {
  periodCounters?: {
    requestsUsed?: number;
    tokensUsed?: number;
    costUsed?: number;
    inFlight?: number;
  };
  periodBounds?: { period_start: string; period_end: string };
  admittedRequests?: Record<string, { admittedAt?: number }>;
  idempotency?: Record<
    string,
    { state?: string; requestId?: string; expiresAt?: number }
  >;
  creditedRequests?: Record<string, { expiresAt?: number }>;
};

type AdmissionRpcJson = {
  kind?: string;
  outcome?: string;
  requestId?: string;
};

type CreditRpcJson = {
  kind?: string;
  ok?: boolean;
  code?: string;
  periodCounters?: QuotaDoInspectState["periodCounters"];
};

type SettledRequest = {
  requestId: string;
  requestReference: string;
  token: string;
};

function envelopeKey(requestId: string): string {
  return `request/${requestId}/envelope`;
}

function costOf(
  row: Record<string, unknown> | undefined,
  key: string,
): number {
  return Number(row?.[key] ?? 0);
}

function p1SnapshotFromDefault(): Record<string, unknown> {
  return {
    plan: "standard",
    period_bounds: {
      period_start: DEFAULT_ENTITLE_PAYLOAD.period_start,
      period_end: DEFAULT_ENTITLE_PAYLOAD.period_end,
    },
    request_quota: DEFAULT_ENTITLE_PAYLOAD.request_quota,
    token_cost_budget: {
      token_budget: DEFAULT_ENTITLE_PAYLOAD.token_budget,
      cost_budget: DEFAULT_ENTITLE_PAYLOAD.cost_budget,
    },
    allowed_capabilities: [...DEFAULT_ENTITLE_PAYLOAD.allowed_capabilities],
    soft_threshold: DEFAULT_ENTITLE_PAYLOAD.soft_threshold,
    status: "active",
  };
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

async function enrollOnly(): Promise<Scenario> {
  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  return scenario;
}

async function enrollAndEntitle(
  entitle: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<Scenario> {
  const scenario = await enrollOnly();
  const entitled = await entitleInstallation(scenario, entitle);
  expect(entitled.status).toBe(200);
  return scenario;
}

async function inspectDo(
  installationId: string,
  now?: number,
): Promise<QuotaDoInspectState> {
  const result = await gatewayObjectJson(
    installationId,
    { kind: "inspect" },
    now === undefined ? {} : { now },
  );
  expect(result.status).toBe(200);
  const json = result.json as { kind?: string; state?: QuotaDoInspectState };
  expect(json.kind).toBe("inspect");
  return json.state ?? {};
}

async function admitRpc(
  installationId: string,
  opts: {
    jti: string;
    idempotencyKey: string;
    requestReference: string;
    entitlement: Record<string, unknown>;
    now?: number;
  },
): Promise<AdmissionRpcJson> {
  const result = await gatewayObjectJson(
    installationId,
    {
      kind: "admission",
      jti: opts.jti,
      installationId,
      idempotencyKey: opts.idempotencyKey,
      entitlement: opts.entitlement,
      requestReference: opts.requestReference,
    },
    opts.now === undefined ? {} : { now: opts.now },
  );
  expect(result.status).toBe(200);
  return result.json as AdmissionRpcJson;
}

async function creditRpc(
  installationId: string,
  opts: {
    requestId: string;
    requestReference: string;
    usage: { tokens: number; cost: number };
    partial?: boolean;
    entitlement?: Record<string, unknown>;
    now?: number;
  },
): Promise<{ status: number; json: CreditRpcJson }> {
  const body: Record<string, unknown> = {
    kind: "credit",
    installationId,
    requestId: opts.requestId,
    requestReference: opts.requestReference,
    usage: opts.usage,
    partial: opts.partial ?? false,
  };
  if (opts.entitlement !== undefined) {
    body.entitlement = opts.entitlement;
  }
  const result = await gatewayObjectJson(
    installationId,
    body,
    opts.now === undefined ? {} : { now: opts.now },
  );
  return { status: result.status, json: result.json as CreditRpcJson };
}

async function settleCompleted(
  scenario: Scenario,
  idempotencyKey: string,
): Promise<SettledRequest> {
  const token = await mintAat(scenario);
  const posted = await postRequest(scenario, {
    token,
    idempotencyKey,
    body: visitSummaryInvokeBody(scenario),
  });
  await flushBackgroundWork(200);
  expect(posted.status).toBe(200);
  assertSseSequence(posted.events, ["accepted", "completed"], "subsequence");
  const requestReference = String(posted.events[0]?.data.request_reference);
  const row = await getAiRequest(requestReference);
  expect(row).not.toBeNull();
  expect(row!.state).toBe("Completed");
  return {
    requestId: String(row!.request_id),
    requestReference,
    token,
  };
}

/** Isolate tally survives D1 reset (S00-024). Flush then wipe so cron tests start clean. */
async function drainRejectionTally(): Promise<void> {
  await invokeCron("* * * * *");
  await resetE2eState();
}

type Sx028State = {
  scenario: Scenario;
  token: string;
  oldRef: string;
  oldId: string;
  newRef: string;
  newId: string;
};

/** Rebuild SX-028: two Completed settlements; [SEED] age R-old 91d; 03:00 journal purge. */
async function rebuildSx028(): Promise<Sx028State> {
  await drainRejectionTally();
  const scenario = await provisionHappyPath(undefined, AUGUST_COVERING_NOW);
  const oldSettled = await settleCompleted(scenario, `idem-sx028-old-${crypto.randomUUID()}`);
  const newSettled = await settleCompleted(scenario, `idem-sx028-new-${crypto.randomUUID()}`);

  const aged = new Date(Date.now() - 91 * MS_PER_DAY).toISOString();
  // [SEED] journal-horizon backdating (SX-028).
  await seedSql([
    {
      sql: `UPDATE ai_request SET created_at = ?, completed_at = ? WHERE request_reference = ?`,
      params: [aged, aged, oldSettled.requestReference],
    },
  ]);

  await invokeCron(CRON_RETENTION);

  expect(await getAiRequest(oldSettled.requestReference)).toBeNull();
  expect(
    await r2Exists(envelopeKey(oldSettled.requestId)),
  ).toBe(false);
  const orphan = await queryOne<{ request_id: string | null; tokens: number; cost: number; period: string }>(
    `SELECT request_id, tokens, cost, period FROM usage_event
     WHERE installation_id = ? AND request_id IS NULL
     ORDER BY recorded_at ASC LIMIT 1`,
    [scenario.installationId],
  );
  expect(orphan).not.toBeNull();
  expect(orphan!.request_id).toBeNull();
  expect(Number(orphan!.tokens)).toBe(30);
  expect(costOf(orphan as unknown as Record<string, unknown>, "cost")).toBeCloseTo(
    0.005,
    5,
  );

  const fresh = await getAiRequest(newSettled.requestReference);
  expect(fresh).not.toBeNull();
  expect(fresh!.payload_pointer).toBe(envelopeKey(newSettled.requestId));
  expect(await r2Exists(envelopeKey(newSettled.requestId))).toBe(true);

  return {
    scenario,
    token: oldSettled.token,
    oldRef: oldSettled.requestReference,
    oldId: oldSettled.requestId,
    newRef: newSettled.requestReference,
    newId: newSettled.requestId,
  };
}

type Sx024State = {
  scenario: Scenario;
  token: string;
  diagRef: string;
  diagId: string;
};

/** Rebuild SX-024: Completed visit-summary; [SEED] age 31d; 03:00 diagnostic purge. */
async function rebuildSx024(): Promise<Sx024State> {
  await drainRejectionTally();
  const scenario = await provisionHappyPath(undefined, DEFAULT_ENTITLE_PAYLOAD);
  const settled = await settleCompleted(scenario, `idem-sx024-${crypto.randomUUID()}`);

  const aged = new Date(Date.now() - 31 * MS_PER_DAY).toISOString();
  // [SEED] diagnostic-horizon backdating (SX-024).
  await seedSql([
    {
      sql: `UPDATE ai_request SET created_at = ?, completed_at = ? WHERE request_reference = ?`,
      params: [aged, aged, settled.requestReference],
    },
  ]);

  await invokeCron(CRON_RETENTION);

  const row = await getAiRequest(settled.requestReference);
  expect(row).not.toBeNull();
  expect(row!.state).toBe("Completed");
  expect(row!.payload_pointer).toBeNull();
  expect(await r2Exists(envelopeKey(settled.requestId))).toBe(false);

  return {
    scenario,
    token: settled.token,
    diagRef: settled.requestReference,
    diagId: settled.requestId,
  };
}

describe("Stage X — credit, inspect, retention joinability, GatewayObject RPC (SX-049…SX-063)", () => {
  it("SX-049 — creditedRequests blocks double-credit inside and after the window", async () => {
    const scenario = await enrollAndEntitle();
    const entitlement = await entitlementSnapshot(scenario.installationId);
    const t0 = Date.now();
    const requestReference = "SX49-0001";

    const admitted = await admitRpc(scenario.installationId, {
      jti: "jti-sx049",
      idempotencyKey: "idem-sx049",
      requestReference,
      entitlement,
      now: t0,
    });
    expect(admitted.outcome).toBe("admitted");
    const q9 = String(admitted.requestId);

    const credited = await creditRpc(scenario.installationId, {
      requestId: q9,
      requestReference,
      usage: { tokens: 10, cost: 0.001 },
      now: t0,
    });
    expect(credited.status).toBe(200);
    expect(credited.json).toMatchObject({
      kind: "credit",
      ok: true,
      periodCounters: { requestsUsed: 1, tokensUsed: 10, inFlight: 0 },
    });
    expect(costOf(credited.json.periodCounters as Record<string, unknown>, "costUsed")).toBeCloseTo(
      0.001,
      6,
    );

    const afterCredit = await inspectDo(scenario.installationId, t0);
    expect(afterCredit.creditedRequests?.[q9]).toBeDefined();
    expect(afterCredit.admittedRequests?.[q9]).toBeUndefined();

    const inside = await creditRpc(scenario.installationId, {
      requestId: q9,
      requestReference,
      usage: { tokens: 99, cost: 0.099 },
      now: t0 + 3_600_000,
    });
    expect(inside.status).toBe(200);
    expect(inside.json).toEqual({
      kind: "credit",
      ok: false,
      code: "unknown_request",
    });

    const afterInside = await inspectDo(scenario.installationId, t0 + 3_600_000);
    expect(afterInside.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 10,
      inFlight: 0,
    });
    expect(
      costOf(afterInside.periodCounters as Record<string, unknown>, "costUsed"),
    ).toBeCloseTo(0.001, 6);

    const afterExpiry = await creditRpc(scenario.installationId, {
      requestId: q9,
      requestReference,
      usage: { tokens: 99, cost: 0.099 },
      now: t0 + 7_200_001,
    });
    expect(afterExpiry.status).toBe(200);
    expect(afterExpiry.json).toEqual({
      kind: "credit",
      ok: false,
      code: "unknown_request",
    });

    const afterSweep = await inspectDo(scenario.installationId, t0 + 7_200_001);
    expect(afterSweep.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 10,
      inFlight: 0,
    });
    expect(
      costOf(afterSweep.periodCounters as Record<string, unknown>, "costUsed"),
    ).toBeCloseTo(0.001, 6);
  });

  it("SX-050 — inspect sweeps in memory only — persisted DO state is unchanged", async () => {
    const scenario = await enrollAndEntitle();
    const entitlement = await entitlementSnapshot(scenario.installationId);
    const t0 = Date.now();
    const idempotencyKey = "idem-sx050";

    const admitted = await admitRpc(scenario.installationId, {
      jti: "jti-sx050",
      idempotencyKey,
      requestReference: "SX50-0001",
      entitlement,
      now: t0,
    });
    expect(admitted.outcome).toBe("admitted");
    const q0 = String(admitted.requestId);

    const swept = await inspectDo(scenario.installationId, t0 + 7_200_001);
    expect(swept.periodCounters?.inFlight).toBe(0);
    expect(swept.admittedRequests ?? {}).toEqual({});
    expect(swept.idempotency?.[idempotencyKey]?.state).toBe("failed");
    expect(swept.idempotency?.[idempotencyKey]?.requestId).toBe(q0);

    const early = await inspectDo(scenario.installationId, t0 + 60_000);
    expect(early.periodCounters?.inFlight).toBe(1);
    expect(early.admittedRequests?.[q0]).toBeDefined();
    expect(early.idempotency?.[idempotencyKey]?.state).toBe("admitted");
  });

  it("SX-051 — period rollover on admission resets counters and preserves inFlight", async () => {
    const scenario = await enrollOnly();
    const p1 = p1SnapshotFromDefault();
    const t0 = Date.now();

    const first = await admitRpc(scenario.installationId, {
      jti: "jti-sx051-a",
      idempotencyKey: "idem-sx051-a",
      requestReference: "SX51-0001",
      entitlement: p1,
      now: t0,
    });
    expect(first.outcome).toBe("admitted");
    const credited = await creditRpc(scenario.installationId, {
      requestId: String(first.requestId),
      requestReference: "SX51-0001",
      usage: { tokens: 10, cost: 0.001 },
      now: t0,
    });
    expect(credited.json.ok).toBe(true);

    const uncredited = await admitRpc(scenario.installationId, {
      jti: "jti-sx051-b",
      idempotencyKey: "idem-sx051-b",
      requestReference: "SX51-0002",
      entitlement: p1,
      now: t0 + 1,
    });
    expect(uncredited.outcome).toBe("admitted");

    const beforeRoll = await inspectDo(scenario.installationId, t0 + 1);
    expect(beforeRoll.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 10,
      inFlight: 1,
    });

    const entitled = await entitleInstallation(scenario, P2_ENTITLE);
    expect(entitled.status).toBe(200);
    const p2 = await entitlementSnapshot(scenario.installationId);
    expect(
      (p2.period_bounds as { period_start: string; period_end: string }).period_start,
    ).toBe(P2_ENTITLE.period_start);

    const rolled = await admitRpc(scenario.installationId, {
      jti: "jti-sx051-c",
      idempotencyKey: "idem-sx051-c",
      requestReference: "SX51-0003",
      entitlement: p2,
      now: t0 + 2,
    });
    expect(rolled.outcome).toBe("admitted");

    const after = await inspectDo(scenario.installationId, t0 + 2);
    expect(after.periodCounters).toMatchObject({
      requestsUsed: 0,
      tokensUsed: 0,
      costUsed: 0,
      inFlight: 2,
    });
    expect(after.periodBounds).toEqual({
      period_start: P2_ENTITLE.period_start,
      period_end: P2_ENTITLE.period_end,
    });
  });

  it("SX-052 — period rollover on credit lands usage in the new period", async () => {
    const scenario = await enrollOnly();
    const p1 = p1SnapshotFromDefault();
    const t0 = Date.now();

    const prior = await admitRpc(scenario.installationId, {
      jti: "jti-sx052-a",
      idempotencyKey: "idem-sx052-a",
      requestReference: "SX52-0001",
      entitlement: p1,
      now: t0,
    });
    expect(prior.outcome).toBe("admitted");
    const priorCredit = await creditRpc(scenario.installationId, {
      requestId: String(prior.requestId),
      requestReference: "SX52-0001",
      usage: { tokens: 10, cost: 0.001 },
      now: t0,
    });
    expect(priorCredit.json.ok).toBe(true);

    const hanging = await admitRpc(scenario.installationId, {
      jti: "jti-sx052-b",
      idempotencyKey: "idem-sx052-b",
      requestReference: "SX52-0002",
      entitlement: p1,
      now: t0 + 1,
    });
    expect(hanging.outcome).toBe("admitted");
    const hangingId = String(hanging.requestId);

    const before = await inspectDo(scenario.installationId, t0 + 1);
    expect(before.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 10,
      inFlight: 1,
    });
    expect(
      costOf(before.periodCounters as Record<string, unknown>, "costUsed"),
    ).toBeCloseTo(0.001, 6);

    const entitled = await entitleInstallation(scenario, P2_ENTITLE);
    expect(entitled.status).toBe(200);
    const p2 = await entitlementSnapshot(scenario.installationId);

    const rolled = await creditRpc(scenario.installationId, {
      requestId: hangingId,
      requestReference: "SX52-0002",
      usage: { tokens: 5, cost: 0.0005 },
      entitlement: p2,
      now: t0 + 2,
    });
    expect(rolled.status).toBe(200);
    expect(rolled.json.ok).toBe(true);
    expect(rolled.json.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 5,
      inFlight: 0,
    });
    expect(
      costOf(rolled.json.periodCounters as Record<string, unknown>, "costUsed"),
    ).toBeCloseTo(0.0005, 6);

    const after = await inspectDo(scenario.installationId, t0 + 2);
    expect(after.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 5,
      inFlight: 0,
    });
    expect(
      costOf(after.periodCounters as Record<string, unknown>, "costUsed"),
    ).toBeCloseTo(0.0005, 6);
    expect(after.periodBounds).toEqual({
      period_start: P2_ENTITLE.period_start,
      period_end: P2_ENTITLE.period_end,
    });
  });

  it("SX-053 — journal-purged money still rolls up; missing_usage_credit stays 0", async () => {
    const rebuilt = await rebuildSx028();

    await invokeCron(CRON_ROLLUP);

    const rollups = await queryAll<{
      dimensions: string;
      request_count: number;
      tokens: number;
      cost: number;
    }>("SELECT dimensions, request_count, tokens, cost FROM usage_rollup");
    expect(rollups).toHaveLength(1);
    const dims = JSON.parse(rollups[0]!.dimensions) as {
      installation_id: string;
      period: string;
    };
    expect(dims).toEqual({
      installation_id: rebuilt.scenario.installationId,
      period: "2026-08",
    });
    expect(Number(rollups[0]!.request_count)).toBe(2);
    // Catalog 70 / 0.007 (30+40 / 0.003+0.004). Fake adapter credits 30 / 0.005 each.
    expect(Number(rollups[0]!.tokens)).toBe(60);
    expect(costOf(rollups[0] as unknown as Record<string, unknown>, "cost")).toBeCloseTo(
      0.01,
      5,
    );

    const windowStart = new Date(Date.now() - 30 * MS_PER_DAY).toISOString();
    const windowEnd = new Date().toISOString();
    const missing = await queryOne<{ n: number }>(
      `SELECT COUNT(*) AS n
       FROM ai_request r
       LEFT JOIN usage_event u ON u.request_id = r.request_id
       WHERE r.state IN ('Completed', 'Failed', 'Cancelled')
         AND r.completed_at >= ? AND r.completed_at <= ?
         AND u.usage_event_id IS NULL`,
      [windowStart, windowEnd],
    );
    expect(Number(missing?.n ?? -1)).toBe(0);
  });

  it("SX-054 — journal-purged reference 404s for clinic GET and support lookup", async () => {
    const rebuilt = await rebuildSx028();
    const token = await mintAat(rebuilt.scenario);

    const clinic = await getRequestByRef(token, rebuilt.oldRef);
    expect(clinic.status).toBe(404);
    expect(clinic.text).toBe("");
    expect(clinic.json).toBeNull();

    const lookup = await controlFetch(
      `/control/support/lookup?reference=${encodeURIComponent(rebuilt.oldRef)}`,
      { method: "POST", auth: "operator" },
    );
    expect(lookup.status).toBe(404);
    expect(lookup.json).toEqual({ error: "not_found" });
  });

  it("SX-055 — diagnostic-purged Completed GET omits result; support envelope is null", async () => {
    const rebuilt = await rebuildSx024();
    const token = await mintAat(rebuilt.scenario);

    const clinic = await getRequestByRef(token, rebuilt.diagRef);
    expect(clinic.status).toBe(200);
    expect(clinic.json).toEqual({ state: "Completed" });
    expect(clinic.json as Record<string, unknown>).not.toHaveProperty("result");

    const lookup = await controlFetch(
      `/control/support/lookup?reference=${encodeURIComponent(rebuilt.diagRef)}`,
      { method: "POST", auth: "operator" },
    );
    expect(lookup.status).toBe(200);
    const body = lookup.json as { envelope?: unknown; request?: { state?: string } };
    expect(body.request?.state).toBe("Completed");
    expect(body.envelope).toBeNull();
  });

  it("SX-056 — one 03:00 tick flushes, reconciles grace, and purges both horizons", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath(undefined, AUGUST_COVERING_NOW);

    recordGuardRejection({
      error_code: "quota_exhausted",
      installation_id: scenario.installationId,
    });
    recordGuardRejection({
      error_code: "quota_exhausted",
      installation_id: scenario.installationId,
    });

    const snapshot = await entitlementSnapshot(scenario.installationId);
    // Register 5 #28: SELF.fetch cannot take a throwing DO. Catalog SX-001
    // inserts via admitUnderGrace against a stub — not on the barrel.
    // Catalog usage 7 / 0.007 is not the fake-adapter 30 / 0.005.
    await seedSql([
      {
        sql: `INSERT INTO grace_admission_queue (
                grace_request_id, installation_id, idempotency_key, jti,
                request_reference, entitlement_json, usage_tokens, usage_cost,
                partial, queued_at, reconcile_attempts, reconcile_first_seen_at_ms,
                status
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, 'pending')`,
        params: [
          "grace-sx056",
          scenario.installationId,
          "idem-sx056-grace",
          "jti-sx056-grace",
          "SX56-GRCE",
          JSON.stringify(snapshot),
          7,
          0.007,
          0,
          new Date().toISOString(),
        ],
      },
    ]);

    const oldSettled = await settleCompleted(
      scenario,
      `idem-sx056-old-${crypto.randomUUID()}`,
    );
    const diagSettled = await settleCompleted(
      scenario,
      `idem-sx056-diag-${crypto.randomUUID()}`,
    );
    const newSettled = await settleCompleted(
      scenario,
      `idem-sx056-new-${crypto.randomUUID()}`,
    );

    const oldAged = new Date(Date.now() - 91 * MS_PER_DAY).toISOString();
    const diagAged = new Date(Date.now() - 31 * MS_PER_DAY).toISOString();
    // [SEED] aged requests (SX-056).
    await seedSql([
      {
        sql: `UPDATE ai_request SET created_at = ?, completed_at = ? WHERE request_reference = ?`,
        params: [oldAged, oldAged, oldSettled.requestReference],
      },
      {
        sql: `UPDATE ai_request SET created_at = ?, completed_at = ? WHERE request_reference = ?`,
        params: [diagAged, diagAged, diagSettled.requestReference],
      },
    ]);

    await invokeCron(CRON_RETENTION);

    const counters = await queryAll<{
      dimension_set: string;
      count: number;
    }>("SELECT dimension_set, count FROM platform_counter");
    expect(counters).toHaveLength(1);
    expect(JSON.parse(counters[0]!.dimension_set)).toEqual({
      error_code: "quota_exhausted",
      installation_id: scenario.installationId,
    });
    expect(Number(counters[0]!.count)).toBe(2);

    const grace = await queryOne<{ status: string }>(
      `SELECT status FROM grace_admission_queue WHERE grace_request_id = ?`,
      ["grace-sx056"],
    );
    expect(grace?.status).toBe("reconciled");

    const doState = await inspectDo(scenario.installationId);
    // Catalog {1, 7, 0.007}: grace only. Code also credits the three
    // settlements (fake adapter 30 / 0.005 each) on the same Quota DO.
    expect(doState.periodCounters).toMatchObject({
      requestsUsed: 4,
      tokensUsed: 97,
      inFlight: 0,
    });
    expect(
      costOf(doState.periodCounters as Record<string, unknown>, "costUsed"),
    ).toBeCloseTo(0.022, 5);

    expect(await getAiRequest(oldSettled.requestReference)).toBeNull();
    expect(await r2Exists(envelopeKey(oldSettled.requestId))).toBe(false);
    const orphan = await queryOne<{ request_id: string | null }>(
      `SELECT request_id FROM usage_event
       WHERE installation_id = ? AND request_id IS NULL LIMIT 1`,
      [scenario.installationId],
    );
    expect(orphan?.request_id).toBeNull();

    const diagRow = await getAiRequest(diagSettled.requestReference);
    expect(diagRow).not.toBeNull();
    expect(diagRow!.payload_pointer).toBeNull();
    expect(await r2Exists(envelopeKey(diagSettled.requestId))).toBe(false);

    const fresh = await getAiRequest(newSettled.requestReference);
    expect(fresh).not.toBeNull();
    expect(fresh!.payload_pointer).toBe(envelopeKey(newSettled.requestId));
    expect(await r2Exists(envelopeKey(newSettled.requestId))).toBe(true);

    expect(await count("usage_rollup")).toBe(0);
  });

  it("SX-057 — GatewayObject GET returns 405 Method Not Allowed", async () => {
    const scenario = await newScenario();
    // HARNESS-GAP: gatewayObjectRpc always attaches a body; GET must use stub.fetch with no body.
    const id = env.DO.idFromName(scenario.installationId);
    const response = await env.DO.get(id).fetch(
      new Request(QUOTA_DO_RPC_URL, { method: "GET" }),
    );
    expect(response.status).toBe(405);
    expect(await response.text()).toBe("Method Not Allowed");
  });

  it("SX-058 — GatewayObject truncated JSON returns 400 invalid_json", async () => {
    const scenario = await newScenario();
    const result = await gatewayObjectJson(
      scenario.installationId,
      {},
      { rawBody: '{"kind":"admission","installationId":' },
    );
    expect(result.status).toBe(400);
    expect(result.json).toEqual({ error: "invalid_json" });
  });

  it("SX-059 — GatewayObject unknown kind returns 400 unknown_kind", async () => {
    const scenario = await newScenario();
    const result = await gatewayObjectJson(scenario.installationId, {
      kind: "obliterate",
      installationId: scenario.installationId,
      now: 1_757_000_000_000,
    });
    expect(result.status).toBe(400);
    expect(result.json).toEqual({ error: "unknown_kind" });
  });

  it("SX-060 — real DO admission missing args returns 400 bad_request", async () => {
    const scenario = await newScenario();
    const result = await gatewayObjectJson(scenario.installationId, {
      kind: "admission",
      installationId: scenario.installationId,
      requestReference: "AAAA-AAAA",
    });
    expect(result.status).toBe(400);
    expect(result.json).toEqual({ error: "bad_request" });

    const inspect = await inspectDo(scenario.installationId);
    expect(inspect.admittedRequests ?? {}).toEqual({});
    expect(inspect.idempotency ?? {}).toEqual({});
  });

  it("SX-061 — real DO credit wrong-typed args returns 400 bad_request", async () => {
    const scenario = await newScenario();
    const requestId = crypto.randomUUID();
    const base: Record<string, unknown> = {
      kind: "credit",
      installationId: scenario.installationId,
      requestId,
      requestReference: "AAAA-AAAA",
      usage: { tokens: 10, cost: 0.001 },
    };

    const partial = await gatewayObjectJson(scenario.installationId, {
      ...base,
      partial: "yes",
    });
    expect(partial.status).toBe(400);
    expect(partial.json).toEqual({ error: "bad_request" });

    const exploded = await gatewayObjectJson(scenario.installationId, {
      ...base,
      partial: false,
      idempotencyState: "exploded",
    });
    expect(exploded.status).toBe(400);
    expect(exploded.json).toEqual({ error: "bad_request" });
  });

  it("SX-062 — real DO release missing args returns 400 bad_request", async () => {
    const scenario = await newScenario();
    const result = await gatewayObjectJson(scenario.installationId, {
      kind: "release",
      installationId: scenario.installationId,
      requestId: crypto.randomUUID(),
    });
    expect(result.status).toBe(400);
    expect(result.json).toEqual({ error: "bad_request" });
  });

  it.skip(
    "SX-063 — Register 5 #45: in-pool GatewayObject cannot take injected storage; wrapDoStorage only reaches admissionRPC/creditRPC",
  );
});
