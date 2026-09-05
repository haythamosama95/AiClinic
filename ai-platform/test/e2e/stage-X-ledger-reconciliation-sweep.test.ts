import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  assertSseSequence,
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  count,
  CRON_RETENTION,
  CRON_ROLLUP,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  env,
  gatewayObjectJson,
  getAiRequest,
  getEntitlement,
  getR2Json,
  getRoutingPolicy,
  invokeCron,
  isolateConfigCache,
  mintAat,
  newScenario,
  OPERATOR_ID,
  POLICY_ID,
  POLICY_REF,
  POLICY_VERSION,
  postRequest,
  provisionHappyPath,
  queryAll,
  queryOne,
  resetE2eState,
  seedSql,
  visitSummaryInvokeBody,
  type Scenario,
} from "./harness";

// HARNESS-GAP: runRetentionPurge is not on the frozen barrel; catalog SX-033…035
// inject `now` on the job function (scheduled cron cannot).
import { runRetentionPurge } from "../../src/retention";
// HARNESS-GAP: runRollupAndReconciliation is not on the frozen barrel; catalog
// SX-038 / SX-044 inject `window` (scheduled cron cannot).
import { runRollupAndReconciliation } from "../../src/rollup";
// HARNESS-GAP: FakeAdapter scripting is not on the barrel; SX-037 needs
// per-request token/cost totals that the default fake script does not emit.
import { FakeAdapter } from "../../src/provider/fake";

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
const LEDGER_HORIZON_DAYS = 2555;
const JOURNAL_HORIZON_DAYS = 90;
const EPHEMERAL_HORIZON_MS = 7_200_000;
const FAKE_SUMMARY = "Fake adapter summary.";
/**
 * Pool TTL is 100 ms. Parallel files share isolateConfigCache and call
 * clear(); preload→consult can then miss
 * `active_routing_policy:routing/standard` (ConfigCacheMissError → SSE
 * accepted+failed). Raise TTL and re-stamp the just-promoted policy
 * immediately before POST so the post-accept consult cannot miss.
 */
const SERVE_CACHE_TTL_MS = 30_000;

const ROLLUP_WINDOW_AUG20 = {
  start: "2026-08-20T00:00:00.000Z",
  end: "2026-08-31T23:59:59.999Z",
} as const;

const RECON_WINDOW_SX044 = {
  start: "2026-08-10T00:00:00.000Z",
  end: "2026-09-05T00:00:00.000Z",
} as const;

type FakeModule = typeof import("../../src/provider/fake");

type QuotaInspectState = {
  periodCounters?: { inFlight?: number };
  admittedRequests?: Record<string, unknown>;
  idempotency?: Record<
    string,
    { state?: string; requestId?: string; expiresAt?: number }
  >;
  jtiReplay?: Record<string, { expiresAt?: number }>;
};

type AdmissionJson = {
  kind?: string;
  outcome?: string;
  requestId?: string;
  priorState?: { state?: string; requestId?: string };
};

function daysAgoIso(now: Date, days: number): string {
  return new Date(now.getTime() - days * MS_PER_DAY).toISOString();
}

function timeBucketAt(ms: number): string {
  return `${new Date(ms).toISOString().slice(0, 16)}:00`;
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function enrollOnly(): Promise<Scenario> {
  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  return scenario;
}

async function enrollAndEntitle(): Promise<Scenario> {
  const scenario = await enrollOnly();
  const entitled = await entitleInstallation(scenario, DEFAULT_ENTITLE_PAYLOAD);
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

async function inspectState(
  installationId: string,
  now?: number,
): Promise<QuotaInspectState> {
  const result = await gatewayObjectJson(
    installationId,
    { kind: "inspect" },
    now === undefined ? {} : { now },
  );
  expect(result.status).toBe(200);
  const json = result.json as { kind?: string; state?: QuotaInspectState };
  expect(json.kind).toBe("inspect");
  return json.state ?? {};
}

async function admitRpc(
  scenario: Scenario,
  opts: {
    jti: string;
    idempotencyKey: string;
    requestReference: string;
    now?: number;
  },
): Promise<AdmissionJson> {
  const result = await gatewayObjectJson(
    scenario.installationId,
    {
      kind: "admission",
      jti: opts.jti,
      installationId: scenario.installationId,
      idempotencyKey: opts.idempotencyKey,
      entitlement: await entitlementSnapshot(scenario.installationId),
      requestReference: opts.requestReference,
    },
    opts.now === undefined ? {} : { now: opts.now },
  );
  expect(result.status).toBe(200);
  return result.json as AdmissionJson;
}

async function drainFlushTally(): Promise<void> {
  // In-isolate rejectionTally survives D1 wipe (S00-024). Drain then re-wipe
  // so a later 03:00 tick does not mix leftover flush rows into assertions.
  await invokeCron("* * * * *");
  await resetE2eState();
}

function captureConsole(): { lines: string[]; restore: () => void } {
  const lines: string[] = [];
  const origLog = console.log;
  const origError = console.error;
  const push = (...args: unknown[]) => {
    lines.push(args.map((value) => String(value)).join(" "));
  };
  console.log = (...args: unknown[]) => {
    push(...args);
    origLog.apply(console, args);
  };
  console.error = (...args: unknown[]) => {
    push(...args);
    origError.apply(console, args);
  };
  return {
    lines,
    restore: () => {
      console.log = origLog;
      console.error = origError;
    },
  };
}

function parseLogPayload(
  lines: string[],
  message: string,
): Record<string, unknown> | undefined {
  const line = lines.find(
    (entry) =>
      entry.includes(`] ${message} `) || entry.includes(`] ${message}{`),
  );
  if (!line) {
    return undefined;
  }
  const idx = line.indexOf("{");
  if (idx < 0) {
    return undefined;
  }
  try {
    return JSON.parse(line.slice(idx)) as Record<string, unknown>;
  } catch {
    return undefined;
  }
}

async function seedUsageEvent(opts: {
  id: string;
  installationId: string;
  period: string;
  requestId: string | null;
  tokens: number;
  cost: number;
  recordedAt: string;
}): Promise<void> {
  await seedSql([
    {
      sql: `INSERT INTO usage_event (
              usage_event_id, installation_id, period, request_id,
              quota_weight, tokens, cost, recorded_at
            ) VALUES (?, ?, ?, ?, 1, ?, ?, ?)`,
      params: [
        opts.id,
        opts.installationId,
        opts.period,
        opts.requestId,
        opts.tokens,
        opts.cost,
        opts.recordedAt,
      ],
    },
  ]);
}

async function seedAiRequest(opts: {
  requestId: string;
  requestReference: string;
  installationId: string;
  actorId: string;
  state: string;
  createdAt: string;
  completedAt: string | null;
  terminalErrorCode?: string | null;
}): Promise<void> {
  await seedSql([
    {
      sql: `INSERT INTO ai_request (
              request_id, request_reference, installation_id, actor_id, branch_id,
              capability_id, capability_version, prompt_artifact_hash, idempotency_key,
              trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
              payload_pointer, conversation_id, turn_ordinal
            ) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL)`,
      params: [
        opts.requestId,
        opts.requestReference,
        opts.installationId,
        opts.actorId,
        CAPABILITY_ID,
        CAPABILITY_VERSION,
        "prompt/sx-seed@v1",
        `idem-${opts.requestId}`,
        `trace-${opts.requestId}`,
        opts.state,
        opts.createdAt,
        opts.createdAt,
        opts.completedAt,
        opts.terminalErrorCode ?? null,
      ],
    },
  ]);
}

async function seedAttempt(requestId: string): Promise<void> {
  await seedSql([
    {
      sql: `INSERT INTO ai_attempt (
              attempt_id, request_id, attempt_no, provider, model, outcome,
              latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
            ) VALUES (?, ?, 1, 'fake', 'fake-v1', 'success', 6, 10, 20, 0.005, ?, NULL)`,
      params: [`attempt-${requestId}`, requestId, `prov-${requestId}`],
    },
  ]);
}

async function loadFakeModule(): Promise<FakeModule> {
  return import("../../src/provider/fake");
}

type InvokeOptions = {
  onStreamChunk?: (chunk: {
    sequenceNumber: number;
    kind: string;
    payload: { text: string };
    terminal: boolean;
  }) => void;
};

function spyFakeInputTokens(
  fakeMod: FakeModule,
  original: typeof FakeAdapter,
  inputs: number[],
) {
  const queue = [...inputs];
  return vi.spyOn(fakeMod, "FakeAdapter").mockImplementation(() => {
    const input = queue.shift() ?? 10;
    class Scripted extends original {
      override async invoke(_request: unknown, options?: InvokeOptions) {
        options?.onStreamChunk?.({
          sequenceNumber: 0,
          kind: "text_delta",
          payload: { text: FAKE_SUMMARY },
          terminal: true,
        });
        return {
          kind: "success" as const,
          result: {
            finalContent: { type: "text" as const, text: FAKE_SUMMARY },
            usage: { input, output: 0, cached: 0 },
            providerModel: { provider: "fake", model: "fake-v1" },
            finishReason: "stop" as const,
            providerRequestId: "fake-req-001",
            timing: { queue_ms: 1, provider_ms: 5, total_ms: 6 },
          },
          chunks: [
            {
              sequenceNumber: 0,
              kind: "text_delta" as const,
              payload: { text: FAKE_SUMMARY },
              terminal: true,
            },
          ],
          rawBody: {
            payload: { fake: true, outcome: "success" },
            truncated: false,
          },
        };
      }
    }
    return new Scripted(["success"]) as never;
  });
}

async function waitForUsageEvent(
  requestId: string,
  timeoutMs = 4000,
): Promise<void> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const row = await queryOne(
      "SELECT request_id FROM usage_event WHERE request_id = ?",
      [requestId],
    );
    if (row) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(`timed out waiting for usage_event ${requestId}`);
}

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
  tag: string,
): Promise<{ requestId: string; requestReference: string }> {
  const token = await mintAat(scenario);
  const policyRow = await loadServingPolicyRow(POLICY_VERSION);
  pinServingRoutingPolicy(policyRow, [scenario.installationId]);
  const result = await postRequest(scenario, {
    token,
    idempotencyKey: `${tag}-${crypto.randomUUID()}`,
    traceId: `${tag}-trace`,
    body: visitSummaryInvokeBody(scenario),
  });
  expect(result.status).toBe(200);
  assertSseSequence(result.events, ["accepted", "completed"], "subsequence");
  const ref = String(result.events[0]?.data.request_reference ?? "");
  const row = await getAiRequest(ref);
  expect(row).not.toBeNull();
  expect(row!.state).toBe("Completed");
  return { requestId: String(row!.request_id), requestReference: ref };
}

async function rebuildSx028EndState(): Promise<{
  scenario: Scenario;
  oldRequestId: string;
  newRequestId: string;
}> {
  const scenario = await provisionHappyPath();
  const oldReq = await completeVisit(scenario, "sx045-old");
  const newReq = await completeVisit(scenario, "sx045-new");
  const aged = daysAgoIso(new Date(), JOURNAL_HORIZON_DAYS + 1);
  await seedSql([
    {
      sql: `UPDATE ai_request
            SET created_at = ?, updated_at = ?, completed_at = ?
            WHERE request_id = ?`,
      params: [aged, aged, aged, oldReq.requestId],
    },
    {
      sql: `UPDATE usage_event SET recorded_at = ?, period = '2026-08' WHERE request_id = ?`,
      params: [aged, oldReq.requestId],
    },
  ]);
  await invokeCron(CRON_RETENTION);
  expect(
    await queryOne("SELECT request_id FROM ai_request WHERE request_id = ?", [
      oldReq.requestId,
    ]),
  ).toBeNull();
  const nulled = await queryOne<{ request_id: string | null; tokens: number }>(
    `SELECT request_id, tokens FROM usage_event
     WHERE request_id IS NULL AND installation_id = ?`,
    [scenario.installationId],
  );
  expect(nulled).not.toBeNull();
  expect(nulled?.request_id).toBeNull();
  const stillNew = await queryOne("SELECT request_id FROM ai_request WHERE request_id = ?", [
    newReq.requestId,
  ]);
  expect(stillNew).not.toBeNull();
  return {
    scenario,
    oldRequestId: oldReq.requestId,
    newRequestId: newReq.requestId,
  };
}

async function rebuildSx046EndState(): Promise<{
  scenario: Scenario;
  t0: number;
  t1: number;
  q0: string;
}> {
  const scenario = await enrollAndEntitle();
  const t0 = Date.now();
  const admitted = await admitRpc(scenario, {
    jti: "sx046-jti",
    idempotencyKey: "sx046-key",
    requestReference: "SX46-0001",
    now: t0,
  });
  expect(admitted.outcome).toBe("admitted");
  const q0 = String(admitted.requestId);
  expect(q0.length).toBeGreaterThan(0);
  const t1 = t0 + EPHEMERAL_HORIZON_MS + 1;
  const probe = await admitRpc(scenario, {
    jti: "sx046-probe-jti",
    idempotencyKey: "sx046-probe",
    requestReference: "SX46-PROB",
    now: t1,
  });
  expect(probe.outcome).toBe("admitted");
  return { scenario, t0, t1, q0 };
}

describe("Stage X — ledger purge, rollup reconciliation, DO sweep (SX-033…SX-048)", () => {
  it("SX-033 — Ledger horizon deletes usage_event older than 2555d [SEED]", async () => {
    const scenario = await enrollOnly();
    const now = new Date();
    await seedUsageEvent({
      id: "ue-sx033-a",
      installationId: scenario.installationId,
      period: "2019-08",
      requestId: null,
      tokens: 10,
      cost: 0.001,
      recordedAt: daysAgoIso(now, LEDGER_HORIZON_DAYS + 1),
    });
    await seedUsageEvent({
      id: "ue-sx033-b",
      installationId: scenario.installationId,
      period: "2019-09",
      requestId: null,
      tokens: 20,
      cost: 0.002,
      recordedAt: daysAgoIso(now, LEDGER_HORIZON_DAYS - 1),
    });

    const result = await runRetentionPurge({
      db: env.DB,
      r2: env.R2,
      now,
    });

    expect(result.ledgerDeleted).toBe(1);
    expect(
      await queryOne("SELECT usage_event_id FROM usage_event WHERE usage_event_id = ?", [
        "ue-sx033-a",
      ]),
    ).toBeNull();
    expect(
      await queryOne("SELECT usage_event_id FROM usage_event WHERE usage_event_id = ?", [
        "ue-sx033-b",
      ]),
    ).not.toBeNull();
  });

  it("SX-034 — Ledger horizon deletes usage_rollup by period string compare [SEED]", async () => {
    const scenario = await enrollOnly();
    const ledgerCutoff = "2019-09-15T12:00:00.000Z";
    const now = new Date(
      Date.parse(ledgerCutoff) + LEDGER_HORIZON_DAYS * MS_PER_DAY,
    );
    expect(new Date(now.getTime() - LEDGER_HORIZON_DAYS * MS_PER_DAY).toISOString().startsWith("2019-09-15")).toBe(
      true,
    );

    await seedSql([
      {
        sql: `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)
              VALUES (?, ?, 1, 10, 0.001)`,
        params: [
          "rollup-sx034-a",
          JSON.stringify({
            installation_id: scenario.installationId,
            period: "2019-08",
          }),
        ],
      },
      {
        sql: `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)
              VALUES (?, ?, 1, 20, 0.002)`,
        params: [
          "rollup-sx034-b",
          JSON.stringify({
            installation_id: scenario.installationId,
            period: "2019-09",
          }),
        ],
      },
    ]);

    const result = await runRetentionPurge({
      db: env.DB,
      r2: env.R2,
      now,
    });

    expect(result.ledgerDeleted).toBe(1);
    expect(
      await queryOne("SELECT rollup_id FROM usage_rollup WHERE rollup_id = ?", [
        "rollup-sx034-a",
      ]),
    ).toBeNull();
    expect(
      await queryOne("SELECT rollup_id FROM usage_rollup WHERE rollup_id = ?", [
        "rollup-sx034-b",
      ]),
    ).not.toBeNull();
  });

  it("SX-035 — Ledger horizon deletes aged audit and grants including retired overlays [SEED]", async () => {
    const scenario = await enrollOnly();
    const now = new Date();
    const agedAt = daysAgoIso(now, LEDGER_HORIZON_DAYS + 1);
    const freshAt = now.toISOString();
    const instScope = `installation:${scenario.installationId}`;
    // CODE: idx_capability_grant_live_installation UNIQUE (scope, capability_id)
    // WHERE revoked_at IS NULL AND scope LIKE 'installation:%'. Catalog wanted
    // aged+fresh live grants on the same capability; seed one aged live grant
    // and put the fresh live control on a different capability_id.
    const freshLiveCapabilityId = "clinic.sx035.fresh";
    const retiredOverlayCapabilityId = "clinic.sx035.retired";

    await seedSql([
      {
        sql: `INSERT INTO control_audit
                (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
              VALUES (?, ?, 'entitle', ?, NULL, NULL, ?)`,
        params: ["audit-sx035-aged", OPERATOR_ID, scenario.installationId, agedAt],
      },
      {
        sql: `INSERT INTO control_audit
                (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
              VALUES (?, ?, 'entitle', ?, NULL, NULL, ?)`,
        params: ["audit-sx035-fresh", OPERATOR_ID, scenario.installationId, freshAt],
      },
      {
        sql: `INSERT INTO capability_grant (
                grant_id, scope, capability_id, capability_version,
                granted_at, revoked_at, changed_at, changed_by, lifecycle_state
              ) VALUES (?, ?, ?, ?, ?, NULL, ?, 'seed', NULL)`,
        params: [
          "grant-sx035-live-aged",
          instScope,
          CAPABILITY_ID,
          CAPABILITY_VERSION,
          agedAt,
          agedAt,
        ],
      },
      {
        sql: `INSERT INTO capability_grant (
                grant_id, scope, capability_id, capability_version,
                granted_at, revoked_at, changed_at, changed_by, lifecycle_state
              ) VALUES (?, ?, ?, ?, ?, NULL, ?, 'seed', NULL)`,
        params: [
          "grant-sx035-live-fresh",
          instScope,
          freshLiveCapabilityId,
          CAPABILITY_VERSION,
          freshAt,
          freshAt,
        ],
      },
      {
        sql: `INSERT INTO capability_grant (
                grant_id, scope, capability_id, capability_version,
                granted_at, revoked_at, changed_at, changed_by, lifecycle_state
              ) VALUES (?, 'global', ?, ?, ?, NULL, ?, 'seed', 'retired')`,
        params: [
          "grant-sx035-retired-aged",
          retiredOverlayCapabilityId,
          CAPABILITY_VERSION,
          agedAt,
          agedAt,
        ],
      },
      {
        sql: `INSERT INTO capability_grant (
                grant_id, scope, capability_id, capability_version,
                granted_at, revoked_at, changed_at, changed_by, lifecycle_state
              ) VALUES (?, 'global', ?, ?, ?, NULL, ?, 'seed', 'retired')`,
        params: [
          "grant-sx035-retired-fresh",
          retiredOverlayCapabilityId,
          CAPABILITY_VERSION,
          freshAt,
          freshAt,
        ],
      },
    ]);

    const result = await runRetentionPurge({
      db: env.DB,
      r2: env.R2,
      now,
    });

    expect(result.ledgerDeleted).toBe(3);
    for (const id of [
      "audit-sx035-aged",
      "grant-sx035-live-aged",
      "grant-sx035-retired-aged",
    ]) {
      const table = id.startsWith("audit") ? "control_audit" : "capability_grant";
      const col = id.startsWith("audit") ? "audit_id" : "grant_id";
      expect(
        await queryOne(`SELECT ${col} FROM ${table} WHERE ${col} = ?`, [id]),
      ).toBeNull();
    }
    for (const id of [
      "audit-sx035-fresh",
      "grant-sx035-live-fresh",
      "grant-sx035-retired-fresh",
    ]) {
      const table = id.startsWith("audit") ? "control_audit" : "capability_grant";
      const col = id.startsWith("audit") ? "audit_id" : "grant_id";
      expect(
        await queryOne(`SELECT ${col} FROM ${table} WHERE ${col} = ?`, [id]),
      ).not.toBeNull();
    }
  });

  it("SX-036 — Counter horizon purges 90d buckets; kill_switch never purged [SEED]", async () => {
    await drainFlushTally();
    const nowMs = Date.now();
    const agedBucket = timeBucketAt(nowMs - (JOURNAL_HORIZON_DAYS + 1) * MS_PER_DAY);
    const freshBucket = timeBucketAt(nowMs);
    const killChanged = daysAgoIso(new Date(nowMs), 365);

    await seedSql([
      {
        sql: `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
              VALUES ('sx036-aged', '{"error_code":"quota_exhausted"}', ?, 3)`,
        params: [agedBucket],
      },
      {
        sql: `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
              VALUES ('sx036-fresh', '{"error_code":"quota_exhausted"}', ?, 1)`,
        params: [freshBucket],
      },
      {
        sql: `INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
              VALUES ('provider', 'deepseek', 1, ?, 'seed')`,
        params: [killChanged],
      },
    ]);

    const logs = captureConsole();
    try {
      await invokeCron(CRON_RETENTION);
      const purged = parseLogPayload(logs.lines, "retention_purge_complete");
      if (purged) {
        expect(purged.counter_deleted).toBe(1);
      }
    } finally {
      logs.restore();
    }

    expect(
      await queryOne("SELECT counter_id FROM platform_counter WHERE counter_id = ?", [
        "sx036-aged",
      ]),
    ).toBeNull();
    expect(
      await queryOne("SELECT counter_id FROM platform_counter WHERE counter_id = ?", [
        "sx036-fresh",
      ]),
    ).not.toBeNull();
    const kill = await queryOne<{ active: number; target: string }>(
      "SELECT active, target FROM kill_switch WHERE scope = ? AND target = ?",
      ["provider", "deepseek"],
    );
    expect(kill).not.toBeNull();
    expect(kill?.active).toBe(1);
    expect(kill?.target).toBe("deepseek");
  });

  it("SX-037 — Rollup aggregates full ledger per (installation, period); re-run upserts", async () => {
    const i0 = await provisionHappyPath();
    const i1 = await enrollAndEntitle();
    const fakeMod = await loadFakeModule();
    const adapterSpy = spyFakeInputTokens(fakeMod, FakeAdapter, [30, 40, 10, 5]);

    try {
      const i0a = await completeVisit(i0, "sx037-i0a");
      const i0b = await completeVisit(i0, "sx037-i0b");
      const i0c = await completeVisit(i0, "sx037-i0c");
      const i1a = await completeVisit(i1, "sx037-i1a");
      // usage_event is waitUntil post-response detail (journal.writePostResponseDetail);
      // SSE Completed / ai_request.state can land before the ledger row, especially
      // I1 which is last and had no follow-on visit to overlap the drain.
      await waitForUsageEvent(i0a.requestId);
      await waitForUsageEvent(i0b.requestId);
      await waitForUsageEvent(i0c.requestId);
      await waitForUsageEvent(i1a.requestId);

      await seedSql([
        {
          sql: `UPDATE usage_event SET period = '2026-08', recorded_at = '2026-08-10T00:00:00.000Z'
                WHERE request_id = ?`,
          params: [i0a.requestId],
        },
        {
          sql: `UPDATE usage_event SET period = '2026-08', recorded_at = '2026-08-20T00:00:00.000Z'
                WHERE request_id = ?`,
          params: [i0b.requestId],
        },
        {
          sql: `UPDATE usage_event SET period = '2026-09', recorded_at = '2026-09-02T00:00:00.000Z'
                WHERE request_id = ?`,
          params: [i0c.requestId],
        },
        {
          sql: `UPDATE usage_event SET period = '2026-08', recorded_at = '2026-08-15T00:00:00.000Z'
                WHERE request_id = ?`,
          params: [i1a.requestId],
        },
      ]);

      const usage = await queryAll<{ tokens: number; cost: number; request_id: string }>(
        "SELECT tokens, cost, request_id FROM usage_event",
      );
      const byId = Object.fromEntries(
        usage.map((row) => [row.request_id, row]),
      );
      expect(byId[i0a.requestId]?.tokens).toBe(30);
      expect(Number(byId[i0a.requestId]?.cost)).toBeCloseTo(0.003, 6);
      expect(byId[i0b.requestId]?.tokens).toBe(40);
      expect(Number(byId[i0b.requestId]?.cost)).toBeCloseTo(0.004, 6);
      expect(byId[i0c.requestId]?.tokens).toBe(10);
      expect(Number(byId[i0c.requestId]?.cost)).toBeCloseTo(0.001, 6);
      expect(byId[i1a.requestId]?.tokens).toBe(5);
      expect(Number(byId[i1a.requestId]?.cost)).toBeCloseTo(0.0005, 6);

      await invokeCron(CRON_ROLLUP);
      const first = await queryAll<{
        rollup_id: string;
        dimensions: string;
        request_count: number;
        tokens: number;
        cost: number;
      }>("SELECT rollup_id, dimensions, request_count, tokens, cost FROM usage_rollup");
      expect(first).toHaveLength(3);

      const expected = [
        {
          installation_id: i0.installationId,
          period: "2026-08",
          request_count: 2,
          tokens: 70,
          cost: 0.007,
        },
        {
          installation_id: i0.installationId,
          period: "2026-09",
          request_count: 1,
          tokens: 10,
          cost: 0.001,
        },
        {
          installation_id: i1.installationId,
          period: "2026-08",
          request_count: 1,
          tokens: 5,
          cost: 0.0005,
        },
      ];
      for (const row of expected) {
        const dims = JSON.stringify({
          installation_id: row.installation_id,
          period: row.period,
        });
        const found = first.find((entry) => entry.dimensions === dims);
        expect(found, dims).toBeDefined();
        expect(found!.request_count).toBe(row.request_count);
        expect(found!.tokens).toBe(row.tokens);
        expect(Number(found!.cost)).toBeCloseTo(row.cost, 6);
        expect(found!.rollup_id).toBe(await sha256Hex(dims));
      }

      await invokeCron(CRON_ROLLUP);
      const second = await queryAll<{
        rollup_id: string;
        dimensions: string;
        request_count: number;
        tokens: number;
        cost: number;
      }>("SELECT rollup_id, dimensions, request_count, tokens, cost FROM usage_rollup");
      expect(second).toHaveLength(3);
      expect(second.map((row) => row.rollup_id).sort()).toEqual(
        first.map((row) => row.rollup_id).sort(),
      );
      for (const prior of first) {
        const again = second.find((row) => row.rollup_id === prior.rollup_id);
        expect(again?.request_count).toBe(prior.request_count);
        expect(again?.tokens).toBe(prior.tokens);
        expect(Number(again?.cost)).toBeCloseTo(Number(prior.cost), 6);
      }
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("SX-038 — Windowed rollup re-aggregates entire touched periods [SEED]", async () => {
    const scenario = await enrollOnly();
    await seedUsageEvent({
      id: "ue-sx038-e1",
      installationId: scenario.installationId,
      period: "2026-08",
      requestId: null,
      tokens: 10,
      cost: 0.001,
      recordedAt: "2026-08-05T00:00:00.000Z",
    });
    await seedUsageEvent({
      id: "ue-sx038-e2",
      installationId: scenario.installationId,
      period: "2026-08",
      requestId: null,
      tokens: 20,
      cost: 0.002,
      recordedAt: "2026-08-25T00:00:00.000Z",
    });

    const result = await runRollupAndReconciliation({
      db: env.DB,
      window: { ...ROLLUP_WINDOW_AUG20 },
    });

    expect(result.rollupsWritten).toBe(1);
    const row = await queryOne<{ request_count: number; tokens: number }>(
      "SELECT request_count, tokens FROM usage_rollup",
    );
    expect(row).not.toBeNull();
    expect(row!.request_count).toBe(2);
    expect(row!.tokens).toBe(30);
  });

  it("SX-039 — Empty ledger: zero rollups, empty reconciliation arrays", async () => {
    await drainFlushTally();
    const logs = captureConsole();
    try {
      await invokeCron(CRON_ROLLUP);
      const payload = parseLogPayload(logs.lines, "usage_rollup_reconciliation");
      if (payload) {
        expect(payload.rollups_written).toBe(0);
        expect(payload.missing_attempt_rows).toBe(0);
        expect(payload.missing_usage_credit).toBe(0);
      }
    } finally {
      logs.restore();
    }

    expect(await count("usage_rollup")).toBe(0);
    const report = await runRollupAndReconciliation({ db: env.DB });
    expect(report.rollupsWritten).toBe(0);
    expect(report.report.missingAttemptRows).toEqual([]);
    expect(report.report.missingUsageCredit).toEqual([]);
  });

  it("SX-040 — Reconciliation flags Completed with no ai_attempt [SEED]", async () => {
    const scenario = await enrollOnly();
    const completedAt = daysAgoIso(new Date(), 1);
    await seedAiRequest({
      requestId: "req-sx040-noatt",
      requestReference: "SX40-NOAT",
      installationId: scenario.installationId,
      actorId: scenario.actorId,
      state: "Completed",
      createdAt: completedAt,
      completedAt,
    });
    await seedUsageEvent({
      id: "ue-sx040",
      installationId: scenario.installationId,
      period: "2026-09",
      requestId: "req-sx040-noatt",
      tokens: 10,
      cost: 0.001,
      recordedAt: completedAt,
    });

    await invokeCron(CRON_ROLLUP);
    const report = await runRollupAndReconciliation({ db: env.DB });
    expect(report.report.missingAttemptRows).toEqual([
      { requestId: "req-sx040-noatt", requestReference: "SX40-NOAT" },
    ]);
    expect(
      report.report.missingUsageCredit.some(
        (row) => row.requestId === "req-sx040-noatt",
      ),
    ).toBe(false);
  });

  it("SX-041 — Reconciliation flags Failed with no attempts; Cancelled excluded [SEED]", async () => {
    const scenario = await enrollOnly();
    const completedAt = daysAgoIso(new Date(), 1);
    await seedAiRequest({
      requestId: "req-sx041-fail",
      requestReference: "SX41-FAIL",
      installationId: scenario.installationId,
      actorId: scenario.actorId,
      state: "Failed",
      createdAt: completedAt,
      completedAt,
      terminalErrorCode: "provider_unavailable",
    });
    await seedAiRequest({
      requestId: "req-sx041-cx",
      requestReference: "SX41-CX00",
      installationId: scenario.installationId,
      actorId: scenario.actorId,
      state: "Cancelled",
      createdAt: completedAt,
      completedAt,
    });

    await invokeCron(CRON_ROLLUP);
    const report = await runRollupAndReconciliation({ db: env.DB });
    expect(report.report.missingAttemptRows).toEqual([
      { requestId: "req-sx041-fail", requestReference: "SX41-FAIL" },
    ]);
    expect(
      report.report.missingAttemptRows.some((row) => row.requestId === "req-sx041-cx"),
    ).toBe(false);
  });

  it("SX-042 — Reconciliation flags Completed/Failed/Cancelled with no usage_event [SEED]", async () => {
    const scenario = await enrollOnly();
    const completedAt = daysAgoIso(new Date(), 1);
    const rows = [
      { requestId: "req-sx042-c", requestReference: "SX42-C000", state: "Completed" },
      { requestId: "req-sx042-f", requestReference: "SX42-F000", state: "Failed" },
      { requestId: "req-sx042-x", requestReference: "SX42-X000", state: "Cancelled" },
    ] as const;
    for (const row of rows) {
      await seedAiRequest({
        requestId: row.requestId,
        requestReference: row.requestReference,
        installationId: scenario.installationId,
        actorId: scenario.actorId,
        state: row.state,
        createdAt: completedAt,
        completedAt,
        terminalErrorCode: row.state === "Failed" ? "provider_unavailable" : null,
      });
      await seedAttempt(row.requestId);
    }

    await invokeCron(CRON_ROLLUP);
    const report = await runRollupAndReconciliation({ db: env.DB });
    expect(report.report.missingUsageCredit).toHaveLength(3);
    expect(
      report.report.missingUsageCredit.map((row) => row.requestId).sort(),
    ).toEqual(["req-sx042-c", "req-sx042-f", "req-sx042-x"].sort());
  });

  it("SX-043 — AwaitingContext is excluded from both reconciliation reports [SEED]", async () => {
    const scenario = await enrollOnly();
    const completedAt = daysAgoIso(new Date(), 1);
    await seedAiRequest({
      requestId: "req-sx043-awc2",
      requestReference: "SX43-AWC2",
      installationId: scenario.installationId,
      actorId: scenario.actorId,
      state: "AwaitingContext",
      createdAt: completedAt,
      completedAt,
    });

    await invokeCron(CRON_ROLLUP);
    const report = await runRollupAndReconciliation({ db: env.DB });
    expect(
      report.report.missingAttemptRows.some(
        (row) => row.requestId === "req-sx043-awc2",
      ),
    ).toBe(false);
    expect(
      report.report.missingUsageCredit.some(
        (row) => row.requestId === "req-sx043-awc2",
      ),
    ).toBe(false);
  });

  it("SX-044 — Reconciliation window inclusive; completed_at NULL excluded [SEED]", async () => {
    const scenario = await enrollOnly();
    const start = RECON_WINDOW_SX044.start;
    const end = RECON_WINDOW_SX044.end;
    const out = new Date(Date.parse(start) - 1).toISOString();
    const createdAt = start;

    await seedAiRequest({
      requestId: "req-sx044-w0",
      requestReference: "SX44-W000",
      installationId: scenario.installationId,
      actorId: scenario.actorId,
      state: "Completed",
      createdAt,
      completedAt: start,
    });
    await seedAiRequest({
      requestId: "req-sx044-w1",
      requestReference: "SX44-W100",
      installationId: scenario.installationId,
      actorId: scenario.actorId,
      state: "Completed",
      createdAt,
      completedAt: end,
    });
    await seedAiRequest({
      requestId: "req-sx044-out",
      requestReference: "SX44-OUT0",
      installationId: scenario.installationId,
      actorId: scenario.actorId,
      state: "Completed",
      createdAt: out,
      completedAt: out,
    });
    await seedAiRequest({
      requestId: "req-sx044-nt",
      requestReference: "SX44-NT00",
      installationId: scenario.installationId,
      actorId: scenario.actorId,
      state: "Accepted",
      createdAt,
      completedAt: null,
    });

    const result = await runRollupAndReconciliation({
      db: env.DB,
      window: { ...RECON_WINDOW_SX044 },
    });
    const ids = result.report.missingAttemptRows.map((row) => row.requestId).sort();
    expect(ids).toEqual(["req-sx044-w0", "req-sx044-w1"].sort());
    expect(ids).not.toContain("req-sx044-out");
    expect(ids).not.toContain("req-sx044-nt");
  });

  it("SX-045 — Aged retention-NULLed usage is never missing credit", async () => {
    const { oldRequestId, newRequestId } = await rebuildSx028EndState();

    await invokeCron(CRON_ROLLUP);
    const report = await runRollupAndReconciliation({ db: env.DB });
    expect(
      report.report.missingUsageCredit.some((row) => row.requestId === oldRequestId),
    ).toBe(false);
    expect(
      report.report.missingUsageCredit.some((row) => row.requestId === newRequestId),
    ).toBe(false);
    const familyMissing = report.report.missingUsageCredit.filter((row) =>
      [oldRequestId, newRequestId].includes(row.requestId),
    );
    expect(familyMissing).toHaveLength(0);
  });

  it("SX-046 — Abandoned-admission sweep drops stale in-flight and marks idempotency failed", async () => {
    const { scenario, t1, q0 } = await rebuildSx046EndState();
    const inspect = await inspectState(scenario.installationId);

    expect(inspect.admittedRequests?.[q0]).toBeUndefined();
    expect(inspect.periodCounters?.inFlight).toBe(1);
    const idem = inspect.idempotency?.["sx046-key"];
    expect(idem?.state).toBe("failed");
    expect(idem?.requestId).toBe(q0);
    expect(idem?.expiresAt).toBe(t1 + EPHEMERAL_HORIZON_MS);
    expect(inspect.idempotency?.["sx046-probe"]?.state).toBe("admitted");
  });

  it("SX-047 — Slid-window replay: failed inside window; fresh admit after expiry", async () => {
    const { scenario, t1, q0 } = await rebuildSx046EndState();

    const inside = await admitRpc(scenario, {
      jti: "sx047-jti-a",
      idempotencyKey: "sx046-key",
      requestReference: "SX47-IN00",
      now: t1 + 3_600_000,
    });
    expect(inside.outcome).toBe("idempotent");
    expect(inside.priorState?.state).toBe("failed");
    expect(inside.priorState?.requestId).toBe(q0);

    const after = await admitRpc(scenario, {
      jti: "sx047-jti-b",
      idempotencyKey: "sx046-key",
      requestReference: "SX47-OUT0",
      now: t1 + EPHEMERAL_HORIZON_MS + 1,
    });
    expect(after.outcome).toBe("admitted");
    expect(after.requestId).toBeTruthy();
    expect(after.requestId).not.toBe(q0);

    const inspect = await inspectState(
      scenario.installationId,
      t1 + EPHEMERAL_HORIZON_MS + 1,
    );
    expect(inspect.idempotency?.["sx046-key"]?.state).toBe("admitted");
    expect(inspect.idempotency?.["sx046-key"]?.requestId).toBe(after.requestId);
    expect(inspect.periodCounters?.inFlight).toBeGreaterThanOrEqual(1);
  });

  it("SX-048 — Expired jtiReplay allows the same jti to admit again", async () => {
    const scenario = await enrollAndEntitle();
    const t0 = Date.now();
    const first = await admitRpc(scenario, {
      jti: "sx048-jti",
      idempotencyKey: "sx048-key-a",
      requestReference: "SX48-A000",
      now: t0,
    });
    expect(first.outcome).toBe("admitted");
    const firstId = String(first.requestId);

    const reused = await admitRpc(scenario, {
      jti: "sx048-jti",
      idempotencyKey: "sx048-key-b",
      requestReference: "SX48-B000",
      now: t0 + EPHEMERAL_HORIZON_MS + 1,
    });
    expect(reused.outcome).toBe("admitted");
    expect(reused.requestId).toBeTruthy();
    expect(reused.requestId).not.toBe(firstId);
  });
});
