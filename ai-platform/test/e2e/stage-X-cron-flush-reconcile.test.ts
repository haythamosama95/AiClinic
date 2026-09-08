import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  bootstrapE2e,
  count,
  CRON_RETENTION,
  CRON_ROLLUP,
  DEFAULT_ENTITLE_PAYLOAD,
  diskIoError,
  env,
  flushBackgroundWork,
  gatewayObjectJson,
  getAiRequest,
  getAttempts,
  getEntitlement,
  getR2Json,
  getRoutingPolicy,
  getUsageEvents,
  isolateConfigCache,
  invokeCron,
  mintAat,
  newScenario,
  POLICY_ID,
  POLICY_REF,
  POLICY_VERSION,
  postRequest,
  provisionHappyPath,
  queryAll,
  queryOne,
  r2Exists,
  resetE2eState,
  seedSql,
  visitSummaryInvokeBody,
  wrapD1,
  wrapDurableObjectNamespace,
  type Scenario,
} from "./harness";

// HARNESS-GAP: recordGuardRejection / flushRejectionCounters are not on the barrel.
import {
  flushRejectionCounters,
  recordGuardRejection,
} from "../../src/rate-limit";
// HARNESS-GAP: runAdmission + attachGraceUsage are not on the barrel; admitUnderGrace is not exported.
import { attachGraceUsage, runAdmission } from "../../src/admission";
// HARNESS-GAP: drainDroppedGraceJournal is not on the barrel.
import { drainDroppedGraceJournal } from "../../src/credit";
// HARNESS-GAP: createD1ConfigReader is not on the barrel; runAdmission needs a D1Reader.
import { createD1ConfigReader } from "../../src/config-cache";
// HARNESS-GAP: dashboardQuotaRejectionRate is not on the barrel (SX-009).
import { dashboardQuotaRejectionRate } from "../../src/dashboards";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

afterEach(() => {
  vi.restoreAllMocks();
});

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const JOURNAL_HORIZON_DAYS = 90;
const PLATFORM_COUNTER_INSERT = /INSERT INTO platform_counter/;

type FakeModule = typeof import("../../src/provider/fake");

type QuotaInspectState = {
  periodCounters?: {
    inFlight?: number;
    requestsUsed?: number;
    tokensUsed?: number;
    costUsed?: number;
  };
  jtiReplay?: Record<string, unknown>;
  admittedRequests?: Record<string, unknown>;
  creditedRequests?: Record<string, unknown>;
  idempotency?: Record<
    string,
    {
      state?: string;
      requestId?: string;
      requestReference?: string;
    }
  >;
};

type GraceQueueRow = {
  grace_request_id: string;
  installation_id: string;
  idempotency_key: string;
  jti: string;
  request_reference: string;
  entitlement_json: string;
  usage_tokens: number | null;
  usage_cost: number | null;
  partial: number | null;
  queued_at: string;
  reconcile_attempts: number;
  reconcile_first_seen_at_ms: number | null;
  status: string;
};

type PlatformCounterRow = {
  counter_id: string;
  dimension_set: string;
  time_bucket: string;
  count: number;
};

type UsageRollupRow = {
  rollup_id: string;
  dimensions: string;
  request_count: number;
  tokens: number;
  cost: number;
};

/**
 * HARNESS-GAP: FakeAdapter scripting is not on the frozen barrel; catalog §1
 * documents vi.spyOn(fakeMod, "FakeAdapter") as the seam.
 */
async function loadFakeModule(): Promise<FakeModule> {
  return import("../../src/provider/fake");
}

function spyFakeAdapterSuccess(fakeMod: FakeModule): void {
  const original = fakeMod.FakeAdapter;
  vi.spyOn(fakeMod, "FakeAdapter").mockImplementation(
    () => new original(["success"]) as never,
  );
}

/** In-isolate rejectionTally survives resetE2eState (D1 wipe only). S00-024. */
async function drainRejectionTally(): Promise<void> {
  await invokeCron("* * * * *");
  await resetE2eState();
}

function captureLogs(): { lines: () => string[] } {
  const lines: string[] = [];
  const push = (...args: unknown[]) => {
    lines.push(args.map((value) => String(value)).join(" "));
  };
  vi.spyOn(console, "log").mockImplementation(push);
  vi.spyOn(console, "error").mockImplementation(push);
  return { lines: () => lines };
}

function logEventNames(lines: string[]): string[] {
  const names: string[] = [];
  for (const line of lines) {
    const match = /\[(?:Error|Info|Debug)\] (.+?)(?: \{|$)/.exec(line);
    if (match) {
      names.push(match[1].trim());
    }
  }
  return names;
}

function expectLogContains(lines: string[], event: string): void {
  const names = logEventNames(lines);
  expect(names.some((name) => name.includes(event))).toBe(true);
}

function expectLogOrder(lines: string[], events: string[]): void {
  const names = logEventNames(lines);
  let from = 0;
  for (const event of events) {
    const idx = names.slice(from).findIndex((name) => name.includes(event));
    expect(idx, `missing log event ${event}`).toBeGreaterThanOrEqual(0);
    from += idx + 1;
  }
}

/** Pool is wrangler development (`LOG_VERBOSITY=2`): payloads are a JSON blob. */
function parseLogPayload(
  lines: string[],
  message: string,
): Record<string, unknown> {
  const line = lines.find(
    (entry) =>
      entry.includes(`] ${message} `) || entry.includes(`] ${message}{`),
  );
  expect(line, `missing log event ${message}`).toBeDefined();
  const idx = line!.indexOf("{");
  expect(idx, `missing JSON payload for ${message}`).toBeGreaterThanOrEqual(0);
  return JSON.parse(line!.slice(idx)) as Record<string, unknown>;
}

function expectTrailing30dWindow(window: unknown): void {
  expect(window).toEqual({
    start: expect.any(String),
    end: expect.any(String),
  });
  const { start, end } = window as { start: string; end: string };
  const startMs = Date.parse(start);
  const endMs = Date.parse(end);
  expect(Number.isNaN(startMs)).toBe(false);
  expect(Number.isNaN(endMs)).toBe(false);
  expect(endMs - startMs).toBe(30 * MS_PER_DAY);
}

function currentTimeBucket(now = new Date()): string {
  const iso = now.toISOString();
  return `${iso.slice(0, 16)}:00`;
}

async function counterIdFor(
  dimensionSet: string,
  timeBucket: string,
): Promise<string> {
  const data = new TextEncoder().encode(`${timeBucket}:${dimensionSet}`);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function principalFor(
  scenario: Scenario,
  jti = crypto.randomUUID(),
): {
  installationId: string;
  organizationId: string;
  branchId: string;
  actorId: string;
  role: string;
  scopes: string[];
  jti: string;
  iat: number;
  exp: number;
  ver: string;
} {
  const iat = Math.floor(Date.now() / 1000) - 30;
  return {
    installationId: scenario.installationId,
    organizationId: scenario.orgId,
    branchId: scenario.branchId,
    actorId: scenario.actorId,
    role: "clinician",
    scopes: ["ai.visit_summary", "ai.access"],
    jti,
    iat,
    exp: iat + 330,
    ver: "1",
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

async function inspectState(
  installationId: string,
): Promise<QuotaInspectState> {
  const result = await gatewayObjectJson(installationId, { kind: "inspect" });
  expect(result.status).toBe(200);
  const json = result.json as { kind?: string; state?: QuotaInspectState };
  expect(json.kind).toBe("inspect");
  return json.state ?? {};
}

function throwingDo(): DurableObjectNamespace {
  return wrapDurableObjectNamespace(env.DO, {
    fetchThrow: diskIoError(),
  });
}

async function admitGracePending(
  scenario: Scenario,
  opts: {
    idempotencyKey?: string;
    jti?: string;
    requestReference?: string;
  } = {},
): Promise<GraceQueueRow> {
  const idempotencyKey = opts.idempotencyKey ?? crypto.randomUUID();
  const jti = opts.jti ?? crypto.randomUUID();
  const requestReference = opts.requestReference ?? "7K2M-9XQD";
  const result = await runAdmission(
    {
      principal: principalFor(scenario, jti),
      idempotencyKey,
      requestReference,
      cache: isolateConfigCache,
      reader: createD1ConfigReader(env.DB, env.R2),
    },
    { DB: env.DB, DO: throwingDo() },
  );
  expect(result.ok).toBe(true);
  if (result.ok) {
    expect(result.outcome).toBe("grace_admitted");
  }
  const row = await queryOne<GraceQueueRow>(
    `SELECT * FROM grace_admission_queue
     WHERE installation_id = ? AND idempotency_key = ?`,
    [scenario.installationId, idempotencyKey],
  );
  expect(row).not.toBeNull();
  expect(row!.status).toBe("pending");
  return row!;
}

async function waitForRequestCompleted(
  ref: string,
  timeoutMs = 8000,
): Promise<Record<string, unknown>> {
  const started = Date.now();
  let row: Record<string, unknown> | null = null;
  while (Date.now() - started < timeoutMs) {
    row = await getAiRequest(ref);
    if (row?.state === "Completed") {
      return row;
    }
    await flushBackgroundWork(50);
  }
  expect(row).not.toBeNull();
  expect(row!.state).toBe("Completed");
  return row!;
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
  policyVersion: string,
): Promise<Record<string, unknown>> {
  const row = await getRoutingPolicy(POLICY_ID, policyVersion);
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

async function completeVisit(
  scenario: Scenario,
  opts: { idempotencyKey?: string; traceId?: string } = {},
): Promise<{ requestId: string; ref: string }> {
  const fakeMod = await loadFakeModule();
  spyFakeAdapterSuccess(fakeMod);
  const token = await mintAat(scenario);
  const policyRow = await loadServingPolicyRow(POLICY_VERSION);
  pinServingRoutingPolicy(policyRow, [scenario.installationId]);
  const result = await postRequest(scenario, {
    token,
    idempotencyKey: opts.idempotencyKey ?? crypto.randomUUID(),
    traceId: opts.traceId,
    body: visitSummaryInvokeBody(scenario),
  });
  expect(result.status).toBe(200);
  const accepted = result.events.find((event) => event.event === "accepted");
  const ref = String(accepted?.data.request_reference ?? "");
  expect(ref.length).toBeGreaterThan(0);
  const row = await waitForRequestCompleted(ref);
  // Drain waitUntil envelope / usage_event after terminal state is visible.
  await flushBackgroundWork(200);
  return { requestId: String(row.request_id), ref };
}

async function backdateRequest(
  requestId: string,
  ageDays: number,
): Promise<string> {
  const aged = new Date(Date.now() - ageDays * MS_PER_DAY).toISOString();
  await seedSql([
    {
      sql: `UPDATE ai_request SET created_at = ?, completed_at = ? WHERE request_id = ?`,
      params: [aged, aged, requestId],
    },
  ]);
  return aged;
}

function envelopeKey(requestId: string): string {
  return `request/${requestId}/envelope`;
}

async function recordQuotaExhausted(installationId: string, times: number): Promise<void> {
  for (let i = 0; i < times; i += 1) {
    recordGuardRejection({
      error_code: "quota_exhausted",
      installation_id: installationId,
    });
  }
}

describe("Stage X — cron flush, grace reconcile, retention (SX-001…SX-016)", () => {
  it("SX-001 — Cron 03:00 flush then grace reconcile then retention", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    recordGuardRejection({
      error_code: "quota_exhausted",
      installation_id: scenario.installationId,
    });
    const grace = await admitGracePending(scenario, {
      idempotencyKey: "sx001-key",
      jti: "sx001-jti",
      requestReference: "7K2M-9XQD",
    });
    await attachGraceUsage(
      env.DB,
      grace.grace_request_id,
      { tokens: 10, cost: 0.01 },
      false,
    );
    const completed = await completeVisit(scenario, {
      idempotencyKey: `sx001-old-${crypto.randomUUID()}`,
    });
    // [SEED] retention backdating — catalog SX-001.
    await backdateRequest(completed.requestId, JOURNAL_HORIZON_DAYS + 1);
    expect(await r2Exists(envelopeKey(completed.requestId))).toBe(true);

    const logs = captureLogs();
    await invokeCron(CRON_RETENTION);
    const lines = logs.lines();

    expectLogOrder(lines, [
      "scheduled_cron_start",
      "Flushing guard rejection counters",
      "grace_reconcile_batch_start",
      "grace_reconcile_batch_end",
      "scheduled_retention_purge_start",
      "retention_purge_complete",
      "scheduled_retention_purge_complete",
      "scheduled_cron_complete",
    ]);
    expect(parseLogPayload(lines, "scheduled_cron_start").cron).toBe(
      CRON_RETENTION,
    );
    expect(parseLogPayload(lines, "scheduled_cron_complete").cron).toBe(
      CRON_RETENTION,
    );

    expect(await count("platform_counter")).toBeGreaterThanOrEqual(1);
    const graceAfter = await queryOne<GraceQueueRow>(
      `SELECT * FROM grace_admission_queue WHERE grace_request_id = ?`,
      [grace.grace_request_id],
    );
    expect(graceAfter?.status).toBe("reconciled");
    expect(await getAiRequest(completed.ref)).toBeNull();
    expect(await getAttempts(completed.requestId)).toHaveLength(0);
    const orphaned = await queryAll<{ request_id: string | null }>(
      `SELECT request_id FROM usage_event WHERE installation_id = ?`,
      [scenario.installationId],
    );
    expect(orphaned.length).toBeGreaterThanOrEqual(1);
    expect(orphaned.every((row) => row.request_id === null)).toBe(true);
    expect(await r2Exists(envelopeKey(completed.requestId))).toBe(false);
    expect(await count("usage_rollup")).toBe(0);
    expect(await count("kill_switch")).toBe(0);
    expect(await count("installation")).toBe(1);
  });

  it("SX-002 — Cron 04:00 flush then reconcile then rollup", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    const completed = await completeVisit(scenario, {
      idempotencyKey: `sx002-${crypto.randomUUID()}`,
    });
    const usage = await getUsageEvents(completed.requestId);
    expect(usage).toHaveLength(1);
    expect(usage[0]?.tokens).toBe(30);
    // Catalog cost 0.003; FakeAdapter fake-v1 prices 10+20 tokens at 0.005.
    expect(Number(usage[0]?.cost)).toBeCloseTo(0.005, 3);
    // [SEED] catalog: backdate usage_event.period if wall-clock/entitlement period is not 2026-08.
    await seedSql([
      {
        sql: `UPDATE usage_event SET period = ? WHERE request_id = ?`,
        params: ["2026-08", completed.requestId],
      },
    ]);

    const logs = captureLogs();
    await invokeCron(CRON_ROLLUP);
    const lines = logs.lines();

    expectLogOrder(lines, [
      "scheduled_cron_start",
      "grace_reconcile_batch_start",
      "scheduled_rollup_start",
      "rollup_start",
      "rollup_complete",
      "reconcile_start",
      "reconcile_complete",
      "usage_rollup_reconciliation",
      "scheduled_cron_complete",
    ]);
    expect(parseLogPayload(lines, "grace_reconcile_batch_start").pending_count).toBe(
      0,
    );
    const recon = parseLogPayload(lines, "usage_rollup_reconciliation");
    expect(recon.rollups_written).toBe(1);
    expect(recon.missing_attempt_rows).toBe(0);
    expect(recon.missing_usage_credit).toBe(0);
    expectTrailing30dWindow(recon.window);
    expect(parseLogPayload(lines, "scheduled_cron_complete").cron).toBe(
      CRON_ROLLUP,
    );

    const rollups = await queryAll<UsageRollupRow>(`SELECT * FROM usage_rollup`);
    expect(rollups).toHaveLength(1);
    expect(JSON.parse(rollups[0]!.dimensions)).toEqual({
      installation_id: scenario.installationId,
      period: "2026-08",
    });
    expect(rollups[0]!.request_count).toBe(1);
    expect(rollups[0]!.tokens).toBe(30);
    expect(Number(rollups[0]!.cost)).toBeCloseTo(0.005, 3);
    expect(await count("platform_counter")).toBe(0);
    expect(await count("ai_request")).toBe(1);
    expect(await count("ai_attempt")).toBe(1);
    expect(await count("usage_event")).toBe(1);
  });

  it("SX-003 — Unknown cron string runs only flush and reconcile", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    recordGuardRejection({
      error_code: "quota_exhausted",
      installation_id: scenario.installationId,
    });
    const completed = await completeVisit(scenario, {
      idempotencyKey: `sx003-${crypto.randomUUID()}`,
    });
    // [SEED] 91-day-old Completed request (would purge on 0 3 * * *).
    await backdateRequest(completed.requestId, JOURNAL_HORIZON_DAYS + 1);

    for (const [index, cron] of (
      ["0 5 * * *", "", "* * * * *"] as const
    ).entries()) {
      const logs = captureLogs();
      await invokeCron(cron);
      const lines = logs.lines();
      expect(parseLogPayload(lines, "scheduled_cron_start").cron).toBe(cron);
      expect(parseLogPayload(lines, "scheduled_cron_complete").cron).toBe(cron);
      expectLogContains(lines, "grace_reconcile_batch_");
      if (index === 0) {
        expectLogContains(lines, "Flushing guard rejection counters");
      }
      const names = logEventNames(lines);
      expect(
        names.some((name) => name.includes("scheduled_retention_purge_start")),
      ).toBe(false);
      expect(
        names.some((name) => name.includes("scheduled_rollup_start")),
      ).toBe(false);
      vi.restoreAllMocks();
    }

    expect(await count("platform_counter")).toBeGreaterThanOrEqual(1);
    expect(await getAiRequest(completed.ref)).not.toBeNull();
    expect(await count("usage_rollup")).toBe(0);
  });

  it("SX-004 — Flush D1 failure does not abort reconcile or retention", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    recordGuardRejection({
      error_code: "quota_exhausted",
      installation_id: scenario.installationId,
    });
    const grace = await admitGracePending(scenario, {
      idempotencyKey: "sx004-key",
      jti: "sx004-jti",
    });
    const completed = await completeVisit(scenario, {
      idempotencyKey: `sx004-old-${crypto.randomUUID()}`,
    });
    // [SEED] 91-day-old Completed request.
    await backdateRequest(completed.requestId, JOURNAL_HORIZON_DAYS + 1);

    const shim = wrapD1(env.DB, {
      runThrow: { match: PLATFORM_COUNTER_INSERT, error: diskIoError() },
    });
    const logs = captureLogs();
    await invokeCron(CRON_RETENTION, { ...env, DB: shim });

    expectLogContains(logs.lines(), "scheduled_flush_failed");
    expect(await count("platform_counter")).toBe(0);
    expect(await getAiRequest(completed.ref)).toBeNull();
    const graceAfter = await queryOne<GraceQueueRow>(
      `SELECT * FROM grace_admission_queue WHERE grace_request_id = ?`,
      [grace.grace_request_id],
    );
    expect(graceAfter).not.toBeNull();
    expect(["reconciled", "pending"]).toContain(graceAfter!.status);
  });

  it("SX-005 — Flush upserts bucketed platform_counter rows", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    recordQuotaExhausted(scenario.installationId, 3);
    recordGuardRejection({
      error_code: "rate_limited",
      installation_id: scenario.installationId,
      composite_key: "installation+actor",
    });
    const bucket = currentTimeBucket();
    const dimA = JSON.stringify({
      error_code: "quota_exhausted",
      installation_id: scenario.installationId,
    });
    const dimB = JSON.stringify({
      error_code: "rate_limited",
      installation_id: scenario.installationId,
      composite_key: "installation+actor",
    });

    const logs = captureLogs();
    await invokeCron(CRON_ROLLUP);
    const flush = parseLogPayload(
      logs.lines(),
      "Flushing guard rejection counters",
    );
    expect(flush.bucket_count).toBe(2);
    expect(flush.rejection_count).toBe(4);
    const rows = await queryAll<PlatformCounterRow>(
      `SELECT * FROM platform_counter ORDER BY dimension_set`,
    );
    expect(rows).toHaveLength(2);
    const quota = rows.find((row) => row.dimension_set === dimA);
    const limited = rows.find((row) => row.dimension_set === dimB);
    expect(quota?.count).toBe(3);
    expect(limited?.count).toBe(1);
    expect(quota?.time_bucket).toBe(bucket);
    expect(limited?.time_bucket).toBe(bucket);
    expect(quota?.time_bucket.endsWith("Z")).toBe(false);
    expect(quota?.counter_id).toBe(await counterIdFor(dimA, bucket));
    expect(limited?.counter_id).toBe(await counterIdFor(dimB, bucket));
  });

  it("SX-006 — Repeat flush into the same minute bucket accumulates", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    recordQuotaExhausted(scenario.installationId, 3);
    recordGuardRejection({
      error_code: "rate_limited",
      installation_id: scenario.installationId,
      composite_key: "installation+actor",
    });
    await invokeCron(CRON_ROLLUP);
    const dimA = JSON.stringify({
      error_code: "quota_exhausted",
      installation_id: scenario.installationId,
    });
    const before = await queryOne<PlatformCounterRow>(
      `SELECT * FROM platform_counter WHERE dimension_set = ?`,
      [dimA],
    );
    expect(before?.count).toBe(3);

    recordQuotaExhausted(scenario.installationId, 2);
    await invokeCron(CRON_ROLLUP);

    const quotaRows = await queryAll<PlatformCounterRow>(
      `SELECT * FROM platform_counter WHERE dimension_set = ?`,
      [dimA],
    );
    expect(quotaRows).toHaveLength(1);
    expect(quotaRows[0]!.count).toBe(5);
    expect(await count("platform_counter")).toBe(2);
  });

  it("SX-007 — Empty tally flush is a complete no-op", async () => {
    await drainRejectionTally();
    const logs = captureLogs();
    await invokeCron(CRON_ROLLUP);
    const names = logEventNames(logs.lines());
    expect(
      names.some((name) => name.includes("Flushing guard rejection counters")),
    ).toBe(false);
    expect(await count("platform_counter")).toBe(0);
  });

  it("SX-008 — Mid-flush D1 failure loses the snapshot", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    recordQuotaExhausted(scenario.installationId, 2);
    const shim = wrapD1(env.DB, {
      runThrow: { match: PLATFORM_COUNTER_INSERT, error: diskIoError() },
    });
    await expect(flushRejectionCounters({ DB: shim })).rejects.toThrow();
    expect(await count("platform_counter")).toBe(0);

    await invokeCron(CRON_ROLLUP);
    expect(await count("platform_counter")).toBe(0);
  });

  it("SX-009 — dashboardQuotaRejectionRate then counter retention", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    for (let i = 0; i < 4; i += 1) {
      await completeVisit(scenario, {
        idempotencyKey: `sx009-${i}-${crypto.randomUUID()}`,
      });
    }
    recordQuotaExhausted(scenario.installationId, 3);
    await invokeCron(CRON_ROLLUP);
    expect(await count("platform_counter")).toBe(1);
    expect(await count("ai_request")).toBe(4);

    // HARNESS-GAP: dashboardQuotaRejectionRate is not on the barrel.
    const rateBefore = await dashboardQuotaRejectionRate(env.DB);
    expect(rateBefore).toBe(0.75);

    const agedBucket = new Date(Date.now() - (JOURNAL_HORIZON_DAYS + 1) * MS_PER_DAY)
      .toISOString()
      .slice(0, 16)
      .concat(":00");
    // [SEED] retention backdating of platform_counter.time_bucket.
    await seedSql([
      {
        sql: `UPDATE platform_counter SET time_bucket = ?`,
        params: [agedBucket],
      },
    ]);

    const logs = captureLogs();
    await invokeCron(CRON_RETENTION);
    const purged = parseLogPayload(logs.lines(), "retention_purge_complete");
    expect(purged.counter_deleted).toBe(1);
    expect(parseLogPayload(logs.lines(), "scheduled_cron_complete").cron).toBe(
      CRON_RETENTION,
    );
    expect(await count("platform_counter")).toBe(0);
    const rateAfter = await dashboardQuotaRejectionRate(env.DB);
    expect(rateAfter).toBe(0);
    expect(await count("ai_request")).toBe(4);
  });

  it("SX-010 — Reconcile with an empty grace queue", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    const before = await inspectState(scenario.installationId);
    const logs = captureLogs();
    await invokeCron(CRON_ROLLUP);
    const lines = logs.lines();
    expect(parseLogPayload(lines, "grace_reconcile_batch_start").pending_count).toBe(
      0,
    );
    const batchEnd = parseLogPayload(lines, "grace_reconcile_batch_end");
    expect(batchEnd.pending_count).toBe(0);
    expect(batchEnd.reconciled).toBe(0);
    const after = await inspectState(scenario.installationId);
    expect(after).toEqual(before);
    expect(await count("grace_admission_queue")).toBe(0);
  });

  it("SX-011 — Pending grace with attached usage reconciles and credits", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    const grace = await admitGracePending(scenario, {
      idempotencyKey: "sx011-key",
      jti: "sx011-jti",
      requestReference: "7K2M-9XQD",
    });
    await attachGraceUsage(
      env.DB,
      grace.grace_request_id,
      { tokens: 10, cost: 0.01 },
      true,
    );
    const logs = captureLogs();
    await invokeCron(CRON_ROLLUP);
    const batchEnd = parseLogPayload(logs.lines(), "grace_reconcile_batch_end");
    expect(batchEnd.pending_count).toBe(1);
    expect(batchEnd.reconciled).toBe(1);

    const after = await queryOne<GraceQueueRow>(
      `SELECT * FROM grace_admission_queue WHERE grace_request_id = ?`,
      [grace.grace_request_id],
    );
    expect(after?.status).toBe("reconciled");
    expect(after?.usage_tokens).toBe(10);
    expect(Number(after?.usage_cost)).toBeCloseTo(0.01, 5);
    expect(after?.partial).toBe(1);

    const inspect = await inspectState(scenario.installationId);
    expect(inspect.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 10,
      inFlight: 0,
    });
    expect(Number(inspect.periodCounters?.costUsed)).toBeCloseTo(0.01, 5);
    expect(inspect.idempotency?.["sx011-key"]?.state).toBe("cancelled");
    expect(Object.keys(inspect.creditedRequests ?? {}).length).toBe(1);
    expect(
      await count(
        "grace_admission_queue",
        "installation_id = ? AND status = 'pending'",
        [scenario.installationId],
      ),
    ).toBe(0);
    expect(await count("usage_event")).toBe(0);
    expect(await count("ai_request")).toBe(0);
  });

  it("SX-012 — Pending grace without usage credits zero tokens", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    const grace = await admitGracePending(scenario, {
      idempotencyKey: "sx012-key",
      jti: "sx012-jti",
    });
    await invokeCron(CRON_ROLLUP);
    const after = await queryOne<GraceQueueRow>(
      `SELECT * FROM grace_admission_queue WHERE grace_request_id = ?`,
      [grace.grace_request_id],
    );
    expect(after?.status).toBe("reconciled");
    const inspect = await inspectState(scenario.installationId);
    expect(inspect.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 0,
      costUsed: 0,
      inFlight: 0,
    });
    expect(inspect.idempotency?.["sx012-key"]?.state).toBe("completed");
    expect(await count("usage_event")).toBe(0);
  });

  it("SX-013 — Wrapped throwing DO stamps retry and stays pending", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    const grace = await admitGracePending(scenario, {
      idempotencyKey: "sx013-key",
      jti: "sx013-jti",
    });
    const wrapped = wrapDurableObjectNamespace(env.DO, {
      fetchThrow: diskIoError(),
    });
    const beforeMs = Date.now();
    const logs = captureLogs();
    await invokeCron(CRON_ROLLUP, { ...env, DO: wrapped });
    const afterMs = Date.now();

    const names = logEventNames(logs.lines());
    expect(names.some((name) => name.includes("grace_reconcile_dropped"))).toBe(
      false,
    );
    const after = await queryOne<GraceQueueRow>(
      `SELECT * FROM grace_admission_queue WHERE grace_request_id = ?`,
      [grace.grace_request_id],
    );
    expect(after?.status).toBe("pending");
    expect(after?.reconcile_attempts).toBe(1);
    expect(after?.reconcile_first_seen_at_ms).toBeTypeOf("number");
    expect(after!.reconcile_first_seen_at_ms!).toBeGreaterThanOrEqual(beforeMs);
    expect(after!.reconcile_first_seen_at_ms!).toBeLessThanOrEqual(afterMs);
  });

  it("SX-014 — Reconcile quota_exhausted retries instead of dropping", async () => {
    await drainRejectionTally();
    const scenario = await provisionHappyPath();
    const grace = await admitGracePending(scenario, {
      idempotencyKey: "sx014-key",
      jti: "sx014-jti",
    });
    const snapshot = JSON.parse(grace.entitlement_json) as {
      request_quota: number;
    };
    snapshot.request_quota = 0;
    // HARNESS-GAP: catalog did not label [SEED]. admitUnderGrace refuses
    // request_quota=0 via isLedgerQuotaExhausted (0 >= 0), so the snapshot
    // cannot be produced by runAdmission; mutate entitlement_json after insert.
    await seedSql([
      {
        sql: `UPDATE grace_admission_queue SET entitlement_json = ? WHERE grace_request_id = ?`,
        params: [JSON.stringify(snapshot), grace.grace_request_id],
      },
    ]);

    const doBefore = await inspectState(scenario.installationId);
    drainDroppedGraceJournal();
    await invokeCron(CRON_ROLLUP);
    const after = await queryOne<GraceQueueRow>(
      `SELECT * FROM grace_admission_queue WHERE grace_request_id = ?`,
      [grace.grace_request_id],
    );
    expect(after?.status).toBe("pending");
    expect(after?.reconcile_attempts).toBe(1);
    expect(after?.reconcile_first_seen_at_ms).toBeTypeOf("number");
    expect(drainDroppedGraceJournal()).toHaveLength(0);
    const doAfter = await inspectState(scenario.installationId);
    expect(doAfter.periodCounters).toEqual(doBefore.periodCounters);
    expect(doAfter.idempotency?.["sx014-key"]).toBeUndefined();
    expect(doAfter.jtiReplay?.["sx014-jti"]).toBeUndefined();
  });

  it("SX-015 — Idempotent admission drops grace without credit", async () => {
    await drainRejectionTally();
    drainDroppedGraceJournal();
    const scenario = await provisionHappyPath();
    const key = "sx015-key";
    const snapshot = await entitlementSnapshot(scenario.installationId);
    const admitted = await gatewayObjectJson(scenario.installationId, {
      kind: "admission",
      jti: crypto.randomUUID(),
      installationId: scenario.installationId,
      idempotencyKey: key,
      entitlement: snapshot,
      requestReference: "7K2M-9XQD",
    });
    expect(admitted.status).toBe(200);
    const body = admitted.json as { outcome?: string };
    expect(body.outcome).toBe("admitted");
    const inspectBefore = await inspectState(scenario.installationId);

    const grace = await admitGracePending(scenario, {
      idempotencyKey: key,
      jti: crypto.randomUUID(),
      requestReference: "7K2M-9XQE",
    });
    await attachGraceUsage(
      env.DB,
      grace.grace_request_id,
      { tokens: 10, cost: 0.01 },
      false,
    );

    await invokeCron(CRON_ROLLUP);
    const after = await queryOne<GraceQueueRow>(
      `SELECT * FROM grace_admission_queue WHERE grace_request_id = ?`,
      [grace.grace_request_id],
    );
    expect(after?.status).toBe("dropped");
    const journal = drainDroppedGraceJournal();
    expect(journal).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          reason: "settled_by_another_path_idempotent",
          graceRequestId: grace.grace_request_id,
        }),
      ]),
    );
    const inspectAfter = await inspectState(scenario.installationId);
    expect(inspectAfter.periodCounters).toEqual(inspectBefore.periodCounters);
    expect(await count("usage_event")).toBe(0);
  });

  it("SX-016 — Replay admission drops grace without credit", async () => {
    await drainRejectionTally();
    drainDroppedGraceJournal();
    const scenario = await provisionHappyPath();
    const jti = "sx016-jti";
    const snapshot = await entitlementSnapshot(scenario.installationId);
    const admitted = await gatewayObjectJson(scenario.installationId, {
      kind: "admission",
      jti,
      installationId: scenario.installationId,
      idempotencyKey: "sx016-original-key",
      entitlement: snapshot,
      requestReference: "7K2M-9XQD",
    });
    expect(admitted.status).toBe(200);
    const body = admitted.json as { outcome?: string };
    expect(body.outcome).toBe("admitted");
    const inspectBefore = await inspectState(scenario.installationId);

    const grace = await admitGracePending(scenario, {
      idempotencyKey: "sx016-other-key",
      jti,
      requestReference: "7K2M-9XQE",
    });

    await invokeCron(CRON_ROLLUP);
    const after = await queryOne<GraceQueueRow>(
      `SELECT * FROM grace_admission_queue WHERE grace_request_id = ?`,
      [grace.grace_request_id],
    );
    expect(after?.status).toBe("dropped");
    const journal = drainDroppedGraceJournal();
    expect(journal).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          reason: "settled_by_another_path_replay",
          graceRequestId: grace.grace_request_id,
        }),
      ]),
    );
    const inspectAfter = await inspectState(scenario.installationId);
    expect(inspectAfter.periodCounters).toEqual(inspectBefore.periodCounters);
    expect(await count("usage_event")).toBe(0);
  });
});
