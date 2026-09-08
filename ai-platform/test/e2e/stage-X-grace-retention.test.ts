/**
 * Stage X — grace reconcile + diagnostic/journal retention (SX-017…SX-032).
 *
 * HARNESS-GAP: `runAdmission` / `attachGraceUsage`, `drainDroppedGraceJournal` /
 * `reconcileGraceUsage`, `runRetentionPurge` / `createManifestRetentionClassResolver`,
 * `recordGuardRejection` are not on the frozen barrel. Catalog requires those
 * seams for DO-down grace inserts, drop-journal drain, no-DB reconcile,
 * injected-now purge, and SX-005-style quota_exhausted tallies (SX-032).
 */
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { attachGraceUsage, runAdmission } from "../../src/admission";
import {
  drainDroppedGraceJournal,
  reconcileGraceUsage,
} from "../../src/credit";
import { recordGuardRejection } from "../../src/rate-limit";
import {
  createManifestRetentionClassResolver,
  runRetentionPurge,
} from "../../src/retention";
// HARNESS-GAP: runRollupAndReconciliation is not on the frozen barrel; SX-031
// asserts the production report (scheduled cron cannot return it).
import { runRollupAndReconciliation } from "../../src/rollup";
import {
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  count,
  CRON_RETENTION,
  CRON_ROLLUP,
  DEFAULT_ENTITLE_PAYLOAD,
  env,
  flushBackgroundWork,
  gatewayObjectJson,
  getAiRequest,
  getAttempts,
  getEntitlement,
  getUsageEvents,
  isolateConfigCache,
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
  wrapDurableObjectNamespace,
  type Scenario,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const GRACE_TTL_MS = 7_200_000;
const GRACE_MAX_ATTEMPTS = 5;
const ISO_INSTANT = /^\d{4}-\d{2}-\d{2}T/;

type QuotaInspectState = {
  periodCounters?: {
    inFlight?: number;
    requestsUsed?: number;
    tokensUsed?: number;
    costUsed?: number;
  };
  admittedRequests?: Record<string, unknown>;
  creditedRequests?: Record<string, unknown>;
  jtiReplay?: Record<string, { expiresAt?: number }>;
  idempotency?: Record<
    string,
    { state?: string; requestId?: string; expiresAt?: number }
  >;
};

type GraceRow = {
  grace_request_id: string;
  installation_id: string;
  idempotency_key: string;
  jti: string;
  request_reference: string;
  status: string;
  reconcile_attempts: number;
  reconcile_first_seen_at_ms: number | null;
  usage_tokens: number | null;
  usage_cost: number | null;
  queued_at: string;
};

const entitlementReader = {
  async read(prefixedKey: string): Promise<Record<string, unknown> | "miss"> {
    if (!prefixedKey.startsWith("entitlements:")) {
      return "miss";
    }
    const installationId = prefixedKey.slice("entitlements:".length);
    const row = await env.DB.prepare(
      "SELECT * FROM entitlement WHERE installation_id = ?",
    )
      .bind(installationId)
      .first<Record<string, unknown>>();
    return row ?? "miss";
  },
};

function crockfordRef(): string {
  const hex = crypto.randomUUID().replace(/-/g, "").toUpperCase().slice(0, 8);
  return `${hex.slice(0, 4)}-${hex.slice(4, 8)}`;
}

function envelopeKey(requestId: string): string {
  return `request/${requestId}/envelope`;
}

function daysAgoIso(days: number, nowMs = Date.now()): string {
  return new Date(nowMs - days * MS_PER_DAY).toISOString();
}

function cronEnvWithDo(namespace: DurableObjectNamespace): typeof env {
  return new Proxy(env, {
    get(target, prop, receiver) {
      if (prop === "DO") {
        return namespace;
      }
      const value = Reflect.get(target, prop, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) as typeof env;
}

function throwingDo(): DurableObjectNamespace {
  return wrapDurableObjectNamespace(env.DO, {
    fetchThrow: new Error("quota DO unavailable"),
  });
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

async function entitlementSnapshot(
  installationId: string,
): Promise<Record<string, unknown>> {
  const row = await getEntitlement(installationId);
  expect(row).not.toBeNull();
  const allowed = row!.allowed_capabilities;
  return {
    plan: row!.plan,
    period_bounds: {
      period_start: row!.period_start,
      period_end: row!.period_end,
    },
    request_quota: row!.request_quota,
    token_cost_budget: {
      token_budget: row!.token_budget,
      cost_budget: row!.cost_budget,
    },
    allowed_capabilities:
      typeof allowed === "string" ? JSON.parse(allowed) : allowed,
    soft_threshold: row!.soft_threshold,
    status: row!.status,
  };
}

function principalFor(scenario: Scenario, jti = crypto.randomUUID()) {
  const nowSec = Math.floor(Date.now() / 1000);
  return {
    installationId: scenario.installationId,
    organizationId: scenario.orgId,
    branchId: scenario.branchId,
    actorId: scenario.actorId,
    role: "clinician",
    scopes: ["ai.visit_summary", "ai.access"] as const,
    jti,
    iat: nowSec,
    exp: nowSec + 330,
    ver: "1",
  };
}

/** HARNESS-GAP: wrapDurableObjectNamespace does not reach SELF.fetch. */
async function graceAdmit(
  scenario: Scenario,
  opts: {
    idempotencyKey?: string;
    requestReference?: string;
    jti?: string;
    namespace?: DurableObjectNamespace;
  } = {},
) {
  return runAdmission(
    {
      principal: principalFor(scenario, opts.jti),
      idempotencyKey: opts.idempotencyKey ?? crypto.randomUUID(),
      requestReference: opts.requestReference ?? crockfordRef(),
      cache: isolateConfigCache,
      reader: entitlementReader,
    },
    { DB: env.DB, DO: opts.namespace ?? throwingDo() },
  );
}

async function getGrace(idOrKey: string): Promise<GraceRow | null> {
  return queryOne<GraceRow>(
    `SELECT grace_request_id, installation_id, idempotency_key, jti,
            request_reference, status, reconcile_attempts,
            reconcile_first_seen_at_ms, usage_tokens, usage_cost, queued_at
     FROM grace_admission_queue
     WHERE grace_request_id = ? OR idempotency_key = ?`,
    [idOrKey, idOrKey],
  );
}

async function settleCompleted(scenario: Scenario): Promise<{
  ref: string;
  requestId: string;
  pointer: string;
}> {
  const token = await mintAat(scenario);
  const result = await postRequest(scenario, {
    token,
    idempotencyKey: crypto.randomUUID(),
    traceId: `sx-${crypto.randomUUID()}`,
    body: visitSummaryInvokeBody(scenario),
  });
  await flushBackgroundWork(200);
  expect(result.status).toBe(200);
  const accepted = result.events.find((event) => event.event === "accepted");
  const ref = String(accepted?.data.request_reference ?? "");
  expect(ref).toMatch(/^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/i);
  const row = await getAiRequest(ref);
  expect(row).not.toBeNull();
  expect(row!.state).toBe("Completed");
  const requestId = String(row!.request_id);
  const pointer = String(row!.payload_pointer ?? envelopeKey(requestId));
  expect(await r2Exists(pointer)).toBe(true);
  return { ref, requestId, pointer };
}

async function backdateRequest(
  requestId: string,
  createdAt: string,
  completedAt: string | null = createdAt,
): Promise<void> {
  await seedSql([
    {
      sql: `UPDATE ai_request
            SET created_at = ?, updated_at = ?, completed_at = ?
            WHERE request_id = ?`,
      params: [createdAt, createdAt, completedAt, requestId],
    },
  ]);
}

async function seedGracePending(opts: {
  graceRequestId: string;
  installationId: string;
  idempotencyKey: string;
  jti: string;
  requestReference: string;
  reconcileAttempts?: number;
  reconcileFirstSeenAtMs?: number | null;
  queuedAt?: string;
  usageTokens?: number | null;
  usageCost?: number | null;
  partial?: number | null;
}): Promise<void> {
  const snapshot = await entitlementSnapshot(opts.installationId);
  await seedSql([
    {
      sql: `INSERT INTO grace_admission_queue (
              grace_request_id, installation_id, idempotency_key, jti,
              request_reference, entitlement_json, usage_tokens, usage_cost,
              partial, queued_at, reconcile_attempts, reconcile_first_seen_at_ms,
              status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')`,
      params: [
        opts.graceRequestId,
        opts.installationId,
        opts.idempotencyKey,
        opts.jti,
        opts.requestReference,
        JSON.stringify(snapshot),
        opts.usageTokens ?? null,
        opts.usageCost ?? null,
        opts.partial ?? null,
        opts.queuedAt ?? new Date().toISOString(),
        opts.reconcileAttempts ?? 0,
        opts.reconcileFirstSeenAtMs === undefined
          ? null
          : opts.reconcileFirstSeenAtMs,
      ],
    },
  ]);
}

async function seedAiRequest(opts: {
  requestId: string;
  requestReference: string;
  scenario: Scenario;
  state: string;
  createdAt: string;
  completedAt?: string | null;
  payloadPointer?: string | null;
  capabilityVersion?: string;
}): Promise<void> {
  await seedSql([
    {
      sql: `INSERT INTO ai_request (
              request_id, request_reference, installation_id, actor_id, branch_id,
              capability_id, capability_version, prompt_artifact_hash,
              idempotency_key, state, created_at, updated_at, completed_at,
              trace_id, payload_pointer
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      params: [
        opts.requestId,
        opts.requestReference,
        opts.scenario.installationId,
        opts.scenario.actorId,
        opts.scenario.branchId,
        CAPABILITY_ID,
        opts.capabilityVersion ?? CAPABILITY_VERSION,
        "sx-seed-prompt-hash",
        `idem-${opts.requestId}`,
        opts.state,
        opts.createdAt,
        opts.createdAt,
        opts.completedAt === undefined ? opts.createdAt : opts.completedAt,
        `trace-${opts.requestId}`,
        opts.payloadPointer === undefined ? null : opts.payloadPointer,
      ],
    },
  ]);
}

async function seedAttemptAndUsage(opts: {
  requestId: string;
  installationId: string;
  recordedAt: string;
  tokens?: number;
  cost?: number;
}): Promise<{ attemptId: string; usageEventId: string }> {
  const attemptId = crypto.randomUUID();
  const usageEventId = crypto.randomUUID();
  const tokens = opts.tokens ?? 30;
  const cost = opts.cost ?? 0.003;
  await seedSql([
    {
      sql: `INSERT INTO ai_attempt (
              attempt_id, request_id, attempt_no, provider, model, outcome,
              latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
            ) VALUES (?, ?, 1, 'fake', 'fake-v1', 'success', 6, 10, 20, ?, NULL, NULL)`,
      params: [attemptId, opts.requestId, cost],
    },
    {
      sql: `INSERT INTO usage_event (
              usage_event_id, installation_id, period, request_id, quota_weight,
              tokens, cost, recorded_at
            ) VALUES (?, ?, ?, ?, 1, ?, ?, ?)`,
      params: [
        usageEventId,
        opts.installationId,
        opts.recordedAt.slice(0, 7),
        opts.requestId,
        tokens,
        cost,
        opts.recordedAt,
      ],
    },
  ]);
  return { attemptId, usageEventId };
}

async function putEnvelope(requestId: string): Promise<string> {
  const pointer = envelopeKey(requestId);
  await env.R2.put(pointer, JSON.stringify({ request_id: requestId }));
  return pointer;
}

async function drainLeftoverTally(): Promise<void> {
  await invokeCron("* * * * *");
  await env.DB.prepare("DELETE FROM platform_counter").run();
}

describe("Stage X — grace reconcile and retention (SX-017…SX-032)", () => {
  it("SX-017 — credit unknown_request drops grace entry", async () => {
    const scenario = await provisionHappyPath();
    const idempotencyKey = `sx017-key-${crypto.randomUUID()}`;
    const jti = `sx017-jti-${crypto.randomUUID()}`;
    const admitted = await graceAdmit(scenario, { idempotencyKey, jti });
    expect(admitted).toMatchObject({ ok: true, outcome: "grace_admitted" });
    const graceId =
      admitted.ok && admitted.outcome === "grace_admitted"
        ? admitted.requestId
        : "";
    expect(graceId).toBeTruthy();

    drainDroppedGraceJournal();
    const scripted = wrapDurableObjectNamespace(env.DO, {
      scriptedFetch: async (request) => {
        const body = (await request.clone().json()) as { kind?: string };
        if (body.kind === "admission") {
          return Response.json({
            kind: "admission",
            outcome: "admitted",
            requestId: crypto.randomUUID(),
          });
        }
        return Response.json({
          kind: "credit",
          ok: false,
          code: "unknown_request",
        });
      },
    });

    await invokeCron(CRON_ROLLUP, cronEnvWithDo(scripted));

    const row = await getGrace(graceId);
    expect(row?.status).toBe("dropped");
    expect(row?.reconcile_attempts).toBe(0);
    const journal = drainDroppedGraceJournal();
    expect(journal).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          reason: "settled_by_another_path_unknown_request",
          graceRequestId: graceId,
          installationId: scenario.installationId,
        }),
      ]),
    );
    expect(await count("usage_event")).toBe(0);
  });

  it("SX-018 — credit unavailable then replay-drop leaks in-flight until sweep", async () => {
    const scenario = await provisionHappyPath();
    const idempotencyKey = "sx018-key";
    const jti = "sx018-jti";
    const admitted = await graceAdmit(scenario, { idempotencyKey, jti });
    expect(admitted).toMatchObject({ ok: true, outcome: "grace_admitted" });
    const graceId =
      admitted.ok && admitted.outcome === "grace_admitted"
        ? admitted.requestId
        : "";
    await attachGraceUsage(env.DB, graceId, { tokens: 10, cost: 0.01 }, false);

    const facade = wrapDurableObjectNamespace(env.DO, {
      scriptedFetch: async (request) => {
        const body = (await request.clone().json()) as {
          kind?: string;
          installationId?: string;
        };
        if (body.kind === "credit") {
          throw new Error("quota DO credit unavailable");
        }
        const stub = env.DO.get(env.DO.idFromName(String(body.installationId)));
        return stub.fetch(request);
      },
    });

    drainDroppedGraceJournal();
    await invokeCron(CRON_ROLLUP, cronEnvWithDo(facade));

    const afterTick1 = await getGrace(graceId);
    expect(afterTick1?.status).toBe("pending");
    expect(afterTick1?.reconcile_attempts).toBe(1);
    const tick1Inspect = await inspectState(scenario.installationId);
    expect(tick1Inspect.periodCounters?.inFlight).toBe(1);
    expect(tick1Inspect.jtiReplay?.[jti]).toBeTruthy();
    expect(tick1Inspect.idempotency?.[idempotencyKey]?.state).toBe("admitted");
    expect(tick1Inspect.periodCounters?.requestsUsed ?? 0).toBe(0);

    await invokeCron(CRON_ROLLUP);
    const tick2Ms = Date.now();
    const afterTick2 = await getGrace(graceId);
    expect(afterTick2?.status).toBe("dropped");
    const journal = drainDroppedGraceJournal();
    expect(journal).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          reason: "settled_by_another_path_replay",
          graceRequestId: graceId,
        }),
      ]),
    );
    const tick2Inspect = await inspectState(scenario.installationId);
    expect(tick2Inspect.periodCounters?.requestsUsed ?? 0).toBe(0);
    expect(tick2Inspect.periodCounters?.inFlight).toBe(1);

    const sweepNow = tick2Ms + GRACE_TTL_MS + 1;
    const swept = await inspectState(scenario.installationId, sweepNow);
    expect(swept.periodCounters?.inFlight).toBe(0);
    expect(swept.idempotency?.[idempotencyKey]?.state).toBe("failed");
    expect(swept.idempotency?.[idempotencyKey]?.expiresAt).toBe(
      sweepNow + GRACE_TTL_MS,
    );

    const snapshot = await entitlementSnapshot(scenario.installationId);
    const probe = await gatewayObjectJson(
      scenario.installationId,
      {
        kind: "admission",
        jti: `sx018-probe-${crypto.randomUUID()}`,
        installationId: scenario.installationId,
        idempotencyKey: "sx018-probe",
        requestReference: crockfordRef(),
        entitlement: snapshot,
      },
      { now: sweepNow },
    );
    expect(probe.status).toBe(200);
    const persisted = await inspectState(scenario.installationId);
    expect(persisted.idempotency?.[idempotencyKey]?.state).toBe("failed");
    expect(persisted.periodCounters?.inFlight).toBe(1);
  });

  it("SX-019 — [SEED] max attempts drops before any RPC", async () => {
    const scenario = await provisionHappyPath();
    const graceRequestId = "grace-sx019";
    const jti = "sx019-jti";
    const idempotencyKey = "sx019-key";
    await seedGracePending({
      graceRequestId,
      installationId: scenario.installationId,
      idempotencyKey,
      jti,
      requestReference: crockfordRef(),
      reconcileAttempts: GRACE_MAX_ATTEMPTS,
    });

    const before = await inspectState(scenario.installationId);
    drainDroppedGraceJournal();
    await invokeCron(CRON_ROLLUP);

    const row = await getGrace(graceRequestId);
    expect(row?.status).toBe("dropped");
    const journal = drainDroppedGraceJournal();
    expect(journal).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          reason: "max_attempts",
          graceRequestId,
        }),
      ]),
    );
    const after = await inspectState(scenario.installationId);
    expect(after.jtiReplay?.[jti]).toBeUndefined();
    expect(after.idempotency?.[idempotencyKey]).toBeUndefined();
    expect(Object.keys(after.jtiReplay ?? {})).toEqual(
      Object.keys(before.jtiReplay ?? {}),
    );
    expect(
      await count(
        "grace_admission_queue",
        "installation_id = ? AND status = 'pending'",
        [scenario.installationId],
      ),
    ).toBe(0);
  });

  it("SX-020 — [SEED] TTL expired vs exactly-at-TTL", async () => {
    const scenario = await provisionHappyPath();
    drainDroppedGraceJournal();
    const tickMs = Date.now();
    await seedGracePending({
      graceRequestId: "grace-sx020a",
      installationId: scenario.installationId,
      idempotencyKey: "sx020a-key",
      jti: `sx020a-jti-${crypto.randomUUID()}`,
      requestReference: crockfordRef(),
      reconcileFirstSeenAtMs: tickMs - GRACE_TTL_MS - 1,
    });
    await seedGracePending({
      graceRequestId: "grace-sx020b",
      installationId: scenario.installationId,
      idempotencyKey: "sx020b-key",
      jti: `sx020b-jti-${crypto.randomUUID()}`,
      requestReference: crockfordRef(),
      reconcileFirstSeenAtMs: tickMs - GRACE_TTL_MS,
    });
    const realNow = Date.now;
    Date.now = () => tickMs;
    try {
      await invokeCron(CRON_ROLLUP);
    } finally {
      Date.now = realNow;
    }

    const expired = await getGrace("grace-sx020a");
    const survivor = await getGrace("grace-sx020b");
    expect(expired?.status).toBe("dropped");
    expect(survivor?.status).toBe("reconciled");
    const journal = drainDroppedGraceJournal();
    expect(journal).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          reason: "expired",
          graceRequestId: "grace-sx020a",
        }),
      ]),
    );
    expect(
      journal.some((entry) => entry.graceRequestId === "grace-sx020b"),
    ).toBe(false);
    expect(
      await count(
        "grace_admission_queue",
        "installation_id = ? AND status = 'pending'",
        [scenario.installationId],
      ),
    ).toBe(0);
  });

  it("SX-021 — [SEED] queued_at age does not fire TTL on first sighting", async () => {
    const scenario = await provisionHappyPath();
    const queuedAt = new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString();
    await seedGracePending({
      graceRequestId: "grace-sx021",
      installationId: scenario.installationId,
      idempotencyKey: "sx021-key",
      jti: "sx021-jti",
      requestReference: crockfordRef(),
      queuedAt,
      reconcileFirstSeenAtMs: null,
    });

    const beforeMs = Date.now();
    await invokeCron(CRON_ROLLUP, cronEnvWithDo(throwingDo()));

    const row = await getGrace("grace-sx021");
    expect(row?.status).toBe("pending");
    expect(row?.reconcile_attempts).toBe(1);
    expect(row?.reconcile_first_seen_at_ms).toBeGreaterThanOrEqual(beforeMs - 50);
    expect(row?.reconcile_first_seen_at_ms).toBeLessThanOrEqual(Date.now() + 50);
    expect(row?.queued_at).toMatch(ISO_INSTANT);
  });

  it("SX-022 — reconciling cap-full queue re-opens grace admission", async () => {
    const scenario = await provisionHappyPath();
    const keys: string[] = [];
    for (let index = 0; index < 5; index += 1) {
      const idempotencyKey = `sx022-key-${index}-${crypto.randomUUID()}`;
      keys.push(idempotencyKey);
      const result = await graceAdmit(scenario, {
        idempotencyKey,
        jti: `sx022-jti-${index}-${crypto.randomUUID()}`,
        requestReference: crockfordRef(),
      });
      expect(result).toMatchObject({ ok: true, outcome: "grace_admitted" });
      if (index < 2 && result.ok && result.outcome === "grace_admitted") {
        await attachGraceUsage(
          env.DB,
          result.requestId,
          { tokens: 10 + index, cost: 0.01 * (index + 1) },
          false,
        );
      }
    }
    expect(
      await count(
        "grace_admission_queue",
        "installation_id = ? AND status = 'pending'",
        [scenario.installationId],
      ),
    ).toBe(5);

    const blocked = await graceAdmit(scenario, {
      idempotencyKey: `sx022-blocked-${crypto.randomUUID()}`,
    });
    expect(blocked).toMatchObject({ ok: false, code: "rate_limited" });

    await invokeCron(CRON_ROLLUP);
    expect(
      await count(
        "grace_admission_queue",
        "installation_id = ? AND status = 'pending'",
        [scenario.installationId],
      ),
    ).toBe(0);
    expect(
      await count(
        "grace_admission_queue",
        "installation_id = ? AND status = 'reconciled'",
        [scenario.installationId],
      ),
    ).toBe(5);

    const reopened = await graceAdmit(scenario, {
      idempotencyKey: `sx022-reopen-${crypto.randomUUID()}`,
      namespace: throwingDo(),
    });
    expect(reopened).toMatchObject({ ok: true, outcome: "grace_admitted" });
    expect(
      await count(
        "grace_admission_queue",
        "installation_id = ? AND status = 'pending'",
        [scenario.installationId],
      ),
    ).toBe(1);
  });

  it("SX-023 — reconcileGraceUsage without DB short-circuits", async () => {
    const result = await reconcileGraceUsage({ DO: env.DO });
    expect(result).toEqual({ reconciled: 0 });
  });

  it("SX-024 — diagnostic purge nulls pointer and deletes envelope", async () => {
    await drainLeftoverTally();
    const scenario = await provisionHappyPath();
    const settled = await settleCompleted(scenario);
    await backdateRequest(settled.requestId, daysAgoIso(31));

    const attemptsBefore = await getAttempts(settled.requestId);
    const usageBefore = await getUsageEvents(settled.requestId);
    expect(attemptsBefore.length).toBeGreaterThan(0);
    expect(usageBefore.length).toBeGreaterThan(0);

    await invokeCron(CRON_RETENTION);

    expect(await r2Exists(settled.pointer)).toBe(false);
    const row = await getAiRequest(settled.ref);
    expect(row).not.toBeNull();
    expect(row!.payload_pointer).toBeNull();
    expect(row!.state).toBe("Completed");
    expect(await getAttempts(settled.requestId)).toHaveLength(
      attemptsBefore.length,
    );
    const usageAfter = await getUsageEvents(settled.requestId);
    expect(usageAfter).toHaveLength(usageBefore.length);
    expect(usageAfter[0]?.request_id).toBe(settled.requestId);
    expect(await count("usage_rollup")).toBe(0);
  });

  it("SX-025 — [SEED] unpublished version falls back to diagnostic_7d", async () => {
    await drainLeftoverTally();
    const scenario = await provisionHappyPath();
    const vs = await settleCompleted(scenario);
    const aged = daysAgoIso(8);
    await backdateRequest(vs.requestId, aged);

    const futId = crypto.randomUUID();
    const futRef = crockfordRef();
    const futPointer = await putEnvelope(futId);
    await seedAiRequest({
      requestId: futId,
      requestReference: futRef,
      scenario,
      state: "Completed",
      createdAt: aged,
      completedAt: aged,
      payloadPointer: futPointer,
      capabilityVersion: "2.0.0",
    });
    await seedAttemptAndUsage({
      requestId: futId,
      installationId: scenario.installationId,
      recordedAt: aged,
    });

    await invokeCron(CRON_RETENTION);

    const vsRow = await getAiRequest(vs.ref);
    expect(vsRow?.payload_pointer).toBe(vs.pointer);
    expect(await r2Exists(vs.pointer)).toBe(true);

    const futRow = await queryOne<Record<string, unknown>>(
      "SELECT * FROM ai_request WHERE request_id = ?",
      [futId],
    );
    expect(futRow).not.toBeNull();
    expect(futRow!.payload_pointer).toBeNull();
    expect(await r2Exists(futPointer)).toBe(false);
    expect(await getUsageEvents(vs.requestId).then((rows) => rows.length)).toBeGreaterThan(
      0,
    );
    expect(await getUsageEvents(futId)).toHaveLength(1);
  });

  it("SX-026 — diagnostic horizon strict greater-than at 30d", async () => {
    const scenario = await provisionHappyPath();
    const now = new Date();
    const nowMs = now.getTime();
    const exact = new Date(nowMs - 30 * MS_PER_DAY).toISOString();
    const over = new Date(nowMs - 30 * MS_PER_DAY - 1).toISOString();

    const edgeId = crypto.randomUUID();
    const overId = crypto.randomUUID();
    const edgePointer = await putEnvelope(edgeId);
    const overPointer = await putEnvelope(overId);
    await seedAiRequest({
      requestId: edgeId,
      requestReference: crockfordRef(),
      scenario,
      state: "Completed",
      createdAt: exact,
      completedAt: exact,
      payloadPointer: edgePointer,
    });
    await seedAiRequest({
      requestId: overId,
      requestReference: crockfordRef(),
      scenario,
      state: "Completed",
      createdAt: over,
      completedAt: over,
      payloadPointer: overPointer,
    });

    const purged = await runRetentionPurge({
      db: env.DB,
      r2: env.R2,
      now,
      resolveRetentionClass: createManifestRetentionClassResolver(),
    });
    expect(purged.diagnosticDeleted).toBe(1);

    const edgeRow = await queryOne<Record<string, unknown>>(
      "SELECT payload_pointer FROM ai_request WHERE request_id = ?",
      [edgeId],
    );
    const overRow = await queryOne<Record<string, unknown>>(
      "SELECT payload_pointer FROM ai_request WHERE request_id = ?",
      [overId],
    );
    expect(edgeRow?.payload_pointer).toBe(edgePointer);
    expect(await r2Exists(edgePointer)).toBe(true);
    expect(overRow?.payload_pointer).toBeNull();
    expect(await r2Exists(overPointer)).toBe(false);
  });

  it("SX-027 — [SEED] NULL pointer Accepted is never diagnostic-scanned", async () => {
    await drainLeftoverTally();
    const scenario = await provisionHappyPath();
    const requestId = crypto.randomUUID();
    const ref = crockfordRef();
    await seedAiRequest({
      requestId,
      requestReference: ref,
      scenario,
      state: "Accepted",
      createdAt: daysAgoIso(40),
      completedAt: null,
      payloadPointer: null,
    });

    await invokeCron(CRON_RETENTION);

    const row = await getAiRequest(ref);
    expect(row).not.toBeNull();
    expect(row!.state).toBe("Accepted");
    expect(row!.payload_pointer).toBeNull();
    expect(await r2Exists(envelopeKey(requestId))).toBe(false);
    expect(await count("ai_request")).toBe(1);
  });

  it("SX-028 — journal purge deletes 91d Completed; money row survives", async () => {
    await drainLeftoverTally();
    const scenario = await provisionHappyPath();
    const aged = await settleCompleted(scenario);
    const fresh = await settleCompleted(scenario);
    await backdateRequest(aged.requestId, daysAgoIso(91));

    const attemptsBefore = await getAttempts(aged.requestId);
    const usageBefore = await getUsageEvents(aged.requestId);
    expect(attemptsBefore).toHaveLength(1);
    const usageEventId = String(usageBefore[0]?.usage_event_id);
    const tokens = Number(usageBefore[0]?.tokens);
    const cost = Number(usageBefore[0]?.cost);

    await invokeCron(CRON_RETENTION);

    expect(await getAiRequest(aged.ref)).toBeNull();
    expect(await getAttempts(aged.requestId)).toHaveLength(0);
    const orphan = await queryOne<Record<string, unknown>>(
      "SELECT * FROM usage_event WHERE usage_event_id = ?",
      [usageEventId],
    );
    expect(orphan).not.toBeNull();
    expect(orphan!.request_id).toBeNull();
    expect(orphan!.tokens).toBe(tokens);
    expect(Number(orphan!.cost)).toBeCloseTo(cost, 6);
    expect(await r2Exists(aged.pointer)).toBe(false);

    const freshRow = await getAiRequest(fresh.ref);
    expect(freshRow).not.toBeNull();
    expect(freshRow!.payload_pointer).toBe(fresh.pointer);
    expect(await r2Exists(fresh.pointer)).toBe(true);
    expect(await getAttempts(fresh.requestId)).toHaveLength(1);
    expect(await getUsageEvents(fresh.requestId)).toHaveLength(1);
    expect(await count("usage_rollup")).toBe(0);
  });

  it("SX-029 — journal horizon strict less-than at 90d", async () => {
    const scenario = await provisionHappyPath();
    const now = new Date();
    const nowMs = now.getTime();
    const exact = new Date(nowMs - 90 * MS_PER_DAY).toISOString();
    const over = new Date(nowMs - 90 * MS_PER_DAY - 1).toISOString();
    const recent = now.toISOString();

    const aId = crypto.randomUUID();
    const bId = crypto.randomUUID();
    const aPointer = await putEnvelope(aId);
    const bPointer = await putEnvelope(bId);
    await seedAiRequest({
      requestId: aId,
      requestReference: crockfordRef(),
      scenario,
      state: "Completed",
      createdAt: exact,
      completedAt: recent,
      payloadPointer: aPointer,
    });
    await seedAiRequest({
      requestId: bId,
      requestReference: crockfordRef(),
      scenario,
      state: "Completed",
      createdAt: over,
      completedAt: recent,
      payloadPointer: bPointer,
    });
    await seedAttemptAndUsage({
      requestId: aId,
      installationId: scenario.installationId,
      recordedAt: recent,
    });
    const bMoney = await seedAttemptAndUsage({
      requestId: bId,
      installationId: scenario.installationId,
      recordedAt: recent,
    });

    const purged = await runRetentionPurge({
      db: env.DB,
      r2: env.R2,
      now,
      resolveRetentionClass: createManifestRetentionClassResolver(),
    });
    expect(purged.journalDeleted).toBe(2);

    const aRow = await queryOne<Record<string, unknown>>(
      "SELECT * FROM ai_request WHERE request_id = ?",
      [aId],
    );
    expect(aRow).not.toBeNull();
    expect(aRow!.payload_pointer).toBe(aPointer);
    expect(await r2Exists(aPointer)).toBe(true);
    expect(await getAttempts(aId)).toHaveLength(1);

    expect(
      await queryOne("SELECT request_id FROM ai_request WHERE request_id = ?", [
        bId,
      ]),
    ).toBeNull();
    expect(await getAttempts(bId)).toHaveLength(0);
    const bUsage = await queryOne<Record<string, unknown>>(
      "SELECT * FROM usage_event WHERE usage_event_id = ?",
      [bMoney.usageEventId],
    );
    expect(bUsage?.request_id).toBeNull();
    expect(await r2Exists(bPointer)).toBe(false);
  });

  it("SX-030 — journal purge of diagnostic-NULLed pointer is a derived-key no-op", async () => {
    await drainLeftoverTally();
    const scenario = await provisionHappyPath();
    const settled = await settleCompleted(scenario);
    await backdateRequest(settled.requestId, daysAgoIso(31));
    await invokeCron(CRON_RETENTION);

    const afterDiag = await getAiRequest(settled.ref);
    expect(afterDiag?.payload_pointer).toBeNull();
    expect(await r2Exists(settled.pointer)).toBe(false);
    const usageBefore = await getUsageEvents(settled.requestId);
    const usageEventId = String(usageBefore[0]?.usage_event_id);

    await backdateRequest(settled.requestId, daysAgoIso(91), daysAgoIso(31));
    await invokeCron(CRON_RETENTION);

    expect(await getAiRequest(settled.ref)).toBeNull();
    expect(await getAttempts(settled.requestId)).toHaveLength(0);
    const orphan = await queryOne<Record<string, unknown>>(
      "SELECT request_id FROM usage_event WHERE usage_event_id = ?",
      [usageEventId],
    );
    expect(orphan?.request_id).toBeNull();
    expect(await r2Exists(envelopeKey(settled.requestId))).toBe(false);
  });

  it("SX-031 — [SEED] aged Accepted and AwaitingContext are journal-purged", async () => {
    await drainLeftoverTally();
    const scenario = await provisionHappyPath();
    const aged = daysAgoIso(91);
    const acceptedId = crypto.randomUUID();
    const awaitingId = crypto.randomUUID();
    const acceptedRef = crockfordRef();
    const awaitingRef = crockfordRef();
    await seedAiRequest({
      requestId: acceptedId,
      requestReference: acceptedRef,
      scenario,
      state: "Accepted",
      createdAt: aged,
      completedAt: null,
      payloadPointer: null,
    });
    await seedAiRequest({
      requestId: awaitingId,
      requestReference: awaitingRef,
      scenario,
      state: "AwaitingContext",
      createdAt: aged,
      completedAt: null,
      payloadPointer: null,
    });

    await invokeCron(CRON_ROLLUP);

    expect(await getAiRequest(acceptedRef)).not.toBeNull();
    expect(await getAiRequest(awaitingRef)).not.toBeNull();
    const report = await runRollupAndReconciliation({ db: env.DB });
    expect(
      report.report.missingAttemptRows.some(
        (row) => row.requestId === acceptedId,
      ),
    ).toBe(false);
    expect(
      report.report.missingAttemptRows.some(
        (row) => row.requestId === awaitingId,
      ),
    ).toBe(false);
    expect(
      report.report.missingUsageCredit.some(
        (row) => row.requestId === acceptedId,
      ),
    ).toBe(false);
    expect(
      report.report.missingUsageCredit.some(
        (row) => row.requestId === awaitingId,
      ),
    ).toBe(false);

    await invokeCron(CRON_RETENTION);
    expect(await getAiRequest(acceptedRef)).toBeNull();
    expect(await getAiRequest(awaitingRef)).toBeNull();
    expect(await count("ai_attempt")).toBe(0);
    expect(await r2Exists(envelopeKey(acceptedId))).toBe(false);
    expect(await r2Exists(envelopeKey(awaitingId))).toBe(false);
  });

  it("SX-032 — non-aged footprint is untouched by the entire purge", async () => {
    await drainLeftoverTally();
    const scenario = await provisionHappyPath(undefined, DEFAULT_ENTITLE_PAYLOAD);
    const settled = await settleCompleted(scenario);
    for (let i = 0; i < 3; i += 1) {
      recordGuardRejection({
        error_code: "quota_exhausted",
        installation_id: scenario.installationId,
      });
    }
    await invokeCron(CRON_ROLLUP);

    expect(await count("platform_counter")).toBeGreaterThan(0);
    expect(await count("usage_rollup")).toBeGreaterThan(0);
    expect(await count("control_audit")).toBeGreaterThan(0);
    expect(await count("capability_grant")).toBeGreaterThan(0);
    expect(await r2Exists(settled.pointer)).toBe(true);

    const before = {
      ai_request: await queryAll(
        "SELECT * FROM ai_request ORDER BY request_id",
      ),
      ai_attempt: await queryAll(
        "SELECT * FROM ai_attempt ORDER BY attempt_id",
      ),
      usage_event: await queryAll(
        "SELECT * FROM usage_event ORDER BY usage_event_id",
      ),
      usage_rollup: await queryAll(
        "SELECT * FROM usage_rollup ORDER BY rollup_id",
      ),
      platform_counter: await queryAll(
        "SELECT * FROM platform_counter ORDER BY counter_id",
      ),
      control_audit: await queryAll(
        "SELECT * FROM control_audit ORDER BY audit_id",
      ),
      capability_grant: await queryAll(
        "SELECT * FROM capability_grant ORDER BY rowid",
      ),
      envelope: await r2Exists(settled.pointer),
    };

    await invokeCron(CRON_RETENTION);

    const after = {
      ai_request: await queryAll(
        "SELECT * FROM ai_request ORDER BY request_id",
      ),
      ai_attempt: await queryAll(
        "SELECT * FROM ai_attempt ORDER BY attempt_id",
      ),
      usage_event: await queryAll(
        "SELECT * FROM usage_event ORDER BY usage_event_id",
      ),
      usage_rollup: await queryAll(
        "SELECT * FROM usage_rollup ORDER BY rollup_id",
      ),
      platform_counter: await queryAll(
        "SELECT * FROM platform_counter ORDER BY counter_id",
      ),
      control_audit: await queryAll(
        "SELECT * FROM control_audit ORDER BY audit_id",
      ),
      capability_grant: await queryAll(
        "SELECT * FROM capability_grant ORDER BY rowid",
      ),
      envelope: await r2Exists(settled.pointer),
    };
    expect(after).toEqual(before);
  });
});
