import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import retentionIndexesSql from "../migrations/20260805120000_f3_retention_indexes.sql?raw";
import {
  EPHEMERAL_HORIZON_MS,
  admissionRPC,
  type AdmissionRequest,
} from "../src/quota-do";
import {
  COUNTER_HORIZON_DAYS,
  createManifestRetentionClassResolver,
  JOURNAL_HORIZON_DAYS,
  LEDGER_HORIZON_DAYS,
  minPublishedDiagnosticHorizonDays,
  MS_PER_DAY,
  parseDiagnosticHorizonDays,
  purgeByInstallationId,
  runRetentionPurge,
} from "../src/retention";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    DO: DurableObjectNamespace;
  }
}

const FIXTURE_NOW = new Date("2026-08-02T12:00:00.000Z");
const FIXTURE_INSTALLATION_A = "inst-retention-a";
const FIXTURE_INSTALLATION_B = "inst-retention-b";
const FIXTURE_ORG = "org-retention-001";

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function seedInstallation(id: string): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (installation_id, org_id, display_name, status, region, enrolled_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(id, FIXTURE_ORG, `Clinic ${id}`, "active", "us-east-1", FIXTURE_NOW.toISOString())
    .run();
}

async function seedRequestWithEnvelope(
  requestId: string,
  installationId: string,
  capabilityId: string,
  createdAt: string,
): Promise<void> {
  const envelopeKey = `request/${requestId}/envelope`;
  await env.DB.prepare(
    `INSERT INTO ai_request (
      request_id, request_reference, installation_id, actor_id, branch_id,
      capability_id, capability_version, prompt_artifact_hash, idempotency_key,
      trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
      payload_pointer, conversation_id, turn_ordinal
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, NULL, NULL)`,
  )
    .bind(
      requestId,
      `REF-${requestId.slice(-4)}`,
      installationId,
      "actor-001",
      "branch-001",
      capabilityId,
      "1.0.0",
      "prompt/retention@v1",
      `idem-${requestId}`,
      `trace-${requestId}`,
      "Completed",
      createdAt,
      createdAt,
      createdAt,
      envelopeKey,
    )
    .run();
  await env.R2.put(envelopeKey, JSON.stringify({ context: {}, prompt: {}, attempts: [], result: {} }));
}

async function clearTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM usage_event"),
    env.DB.prepare("DELETE FROM usage_rollup"),
    env.DB.prepare("DELETE FROM platform_counter"),
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM capability_grant"),
    env.DB.prepare("DELETE FROM installation_key"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM ai_attempt"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, retentionIndexesSql);
});

beforeEach(async () => {
  await clearTables();
  await seedInstallation(FIXTURE_INSTALLATION_A);
  await seedInstallation(FIXTURE_INSTALLATION_B);
});

describe("retention_expiry_diagnostic", () => {
  it("deletes past-horizon diagnostic envelopes and keeps in-horizon", async () => {
    const oldDate = new Date(FIXTURE_NOW.getTime() - 10 * MS_PER_DAY).toISOString();
    const recentDate = new Date(FIXTURE_NOW.getTime() - 2 * MS_PER_DAY).toISOString();

    await seedRequestWithEnvelope("req-diag-old", FIXTURE_INSTALLATION_A, "cap.short", oldDate);
    await seedRequestWithEnvelope("req-diag-new", FIXTURE_INSTALLATION_A, "cap.short", recentDate);

    const result = await runRetentionPurge({
      db: env.DB,
      r2: env.R2,
      now: FIXTURE_NOW,
      resolveRetentionClass: () => "diagnostic_7d",
    });

    expect(result.diagnosticDeleted).toBe(1);
    const oldRow = await env.DB.prepare(
      "SELECT payload_pointer FROM ai_request WHERE request_id = ?",
    )
      .bind("req-diag-old")
      .first<{ payload_pointer: string | null }>();
    const newRow = await env.DB.prepare(
      "SELECT payload_pointer FROM ai_request WHERE request_id = ?",
    )
      .bind("req-diag-new")
      .first<{ payload_pointer: string | null }>();
    expect(oldRow?.payload_pointer).toBeNull();
    expect(newRow?.payload_pointer).not.toBeNull();
  });
});

describe("retention_expiry_journal", () => {
  it("deletes past-horizon journal metadata and keeps in-horizon", async () => {
    const oldDate = new Date(
      FIXTURE_NOW.getTime() - (JOURNAL_HORIZON_DAYS + 1) * MS_PER_DAY,
    ).toISOString();
    const recentDate = new Date(FIXTURE_NOW.getTime() - 10 * MS_PER_DAY).toISOString();

    await env.DB.prepare(
      `INSERT INTO ai_request (
        request_id, request_reference, installation_id, actor_id, branch_id,
        capability_id, capability_version, prompt_artifact_hash, idempotency_key,
        trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
        payload_pointer, conversation_id, turn_ordinal
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL)`,
    )
      .bind(
        "req-journal-old",
        "REF-JOLD",
        FIXTURE_INSTALLATION_A,
        "actor",
        "branch",
        "cap",
        "1.0.0",
        "prompt@v1",
        "idem-old",
        "trace-old",
        "Completed",
        oldDate,
        oldDate,
        oldDate,
      )
      .run();

    await env.DB.prepare(
      `INSERT INTO ai_request (
        request_id, request_reference, installation_id, actor_id, branch_id,
        capability_id, capability_version, prompt_artifact_hash, idempotency_key,
        trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
        payload_pointer, conversation_id, turn_ordinal
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL)`,
    )
      .bind(
        "req-journal-new",
        "REF-JNEW",
        FIXTURE_INSTALLATION_A,
        "actor",
        "branch",
        "cap",
        "1.0.0",
        "prompt@v1",
        "idem-new",
        "trace-new",
        "Completed",
        recentDate,
        recentDate,
        recentDate,
      )
      .run();

    await runRetentionPurge({ db: env.DB, r2: env.R2, now: FIXTURE_NOW });

    const oldCount = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request WHERE request_id = ?",
    )
      .bind("req-journal-old")
      .first<{ c: number }>();
    const newCount = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request WHERE request_id = ?",
    )
      .bind("req-journal-new")
      .first<{ c: number }>();

    expect(oldCount?.c).toBe(0);
    expect(newCount?.c).toBe(1);
  });

  it("expires credited journal requests with attempts while retaining nulled usage_event", async () => {
    const oldDate = new Date(
      FIXTURE_NOW.getTime() - (JOURNAL_HORIZON_DAYS + 1) * MS_PER_DAY,
    ).toISOString();

    await env.DB.prepare(
      `INSERT INTO ai_request (
        request_id, request_reference, installation_id, actor_id, branch_id,
        capability_id, capability_version, prompt_artifact_hash, idempotency_key,
        trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
        payload_pointer, conversation_id, turn_ordinal
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL)`,
    )
      .bind(
        "req-journal-credited",
        "REF-JCRD",
        FIXTURE_INSTALLATION_A,
        "actor",
        "branch",
        "cap",
        "1.0.0",
        "prompt@v1",
        "idem-credited",
        "trace-credited",
        "Completed",
        oldDate,
        oldDate,
        oldDate,
      )
      .run();

    await env.DB.prepare(
      `INSERT INTO ai_attempt (
        attempt_id, request_id, attempt_no, provider, model, outcome,
        latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
    )
      .bind(
        "attempt-journal-credited",
        "req-journal-credited",
        1,
        "deepseek",
        "fixture",
        "success",
        100,
        10,
        5,
        0.01,
        "prov-credited",
      )
      .run();

    await env.DB.prepare(
      `INSERT INTO usage_event (
        usage_event_id, installation_id, period, request_id, quota_weight, tokens, cost, recorded_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        "ue-journal-credited",
        FIXTURE_INSTALLATION_A,
        "2026-05",
        "req-journal-credited",
        1,
        15,
        0.01,
        oldDate,
      )
      .run();

    await runRetentionPurge({ db: env.DB, r2: env.R2, now: FIXTURE_NOW });

    const requestCount = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request WHERE request_id = ?",
    )
      .bind("req-journal-credited")
      .first<{ c: number }>();
    const attemptCount = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_attempt WHERE request_id = ?",
    )
      .bind("req-journal-credited")
      .first<{ c: number }>();
    const usageEvent = await env.DB.prepare(
      "SELECT request_id FROM usage_event WHERE usage_event_id = ?",
    )
      .bind("ue-journal-credited")
      .first<{ request_id: string | null }>();

    expect(requestCount?.c).toBe(0);
    expect(attemptCount?.c).toBe(0);
    expect(usageEvent).toBeDefined();
    expect(usageEvent?.request_id).toBeNull();
  });

  it("deletes R2 envelope before dropping a journal-expired request row", async () => {
    const oldDate = new Date(
      FIXTURE_NOW.getTime() - (JOURNAL_HORIZON_DAYS + 1) * MS_PER_DAY,
    ).toISOString();
    const envelopeKey = "request/req-journal-r2/envelope";

    await env.DB.prepare(
      `INSERT INTO ai_request (
        request_id, request_reference, installation_id, actor_id, branch_id,
        capability_id, capability_version, prompt_artifact_hash, idempotency_key,
        trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
        payload_pointer, conversation_id, turn_ordinal
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, NULL, NULL)`,
    )
      .bind(
        "req-journal-r2",
        "REF-JR2",
        FIXTURE_INSTALLATION_A,
        "actor",
        "branch",
        "cap",
        "1.0.0",
        "prompt@v1",
        "idem-jr2",
        "trace-jr2",
        "Completed",
        oldDate,
        oldDate,
        oldDate,
        envelopeKey,
      )
      .run();
    await env.R2.put(envelopeKey, JSON.stringify({ context: {}, prompt: {} }));

    await runRetentionPurge({ db: env.DB, r2: env.R2, now: FIXTURE_NOW });

    expect(await env.R2.get(envelopeKey)).toBeNull();
    const row = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request WHERE request_id = ?",
    )
      .bind("req-journal-r2")
      .first<{ c: number }>();
    expect(row?.c).toBe(0);
  });
});

describe("retention_expiry_platform_counter", () => {
  it("purges platform_counter rows past the months-class cutoff", async () => {
    const oldBucket = new Date(
      FIXTURE_NOW.getTime() - (COUNTER_HORIZON_DAYS + 1) * MS_PER_DAY,
    )
      .toISOString()
      .slice(0, 19);
    const recentBucket = FIXTURE_NOW.toISOString().slice(0, 19);

    await env.DB.prepare(
      `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
       VALUES (?, ?, ?, ?)`,
    )
      .bind(
        "counter-old",
        JSON.stringify({ error_code: "quota_exhausted", installation_id: FIXTURE_INSTALLATION_A }),
        oldBucket,
        9,
      )
      .run();
    await env.DB.prepare(
      `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
       VALUES (?, ?, ?, ?)`,
    )
      .bind(
        "counter-new",
        JSON.stringify({ error_code: "quota_exhausted", installation_id: FIXTURE_INSTALLATION_A }),
        recentBucket,
        2,
      )
      .run();

    const result = await runRetentionPurge({
      db: env.DB,
      r2: env.R2,
      now: FIXTURE_NOW,
    });

    expect(result.counterDeleted).toBe(1);
    const oldCount = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM platform_counter WHERE counter_id = ?",
    )
      .bind("counter-old")
      .first<{ c: number }>();
    const newCount = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM platform_counter WHERE counter_id = ?",
    )
      .bind("counter-new")
      .first<{ c: number }>();
    expect(oldCount?.c).toBe(0);
    expect(newCount?.c).toBe(1);
  });
});

describe("retention_diagnostic_prefilter_min_horizon", () => {
  it("scans shorter-than-baseline horizons via min published prefilter", async () => {
    expect(minPublishedDiagnosticHorizonDays()).toBe(1);

    const ageDays = 4;
    const borderlineDate = new Date(
      FIXTURE_NOW.getTime() - ageDays * MS_PER_DAY,
    ).toISOString();

    await seedRequestWithEnvelope(
      "req-3d",
      FIXTURE_INSTALLATION_A,
      "cap.short3",
      borderlineDate,
    );

    await runRetentionPurge({
      db: env.DB,
      r2: env.R2,
      now: FIXTURE_NOW,
      resolveRetentionClass: () => "diagnostic_3d",
    });

    const row = await env.DB.prepare(
      "SELECT payload_pointer FROM ai_request WHERE request_id = ?",
    )
      .bind("req-3d")
      .first<{ payload_pointer: string | null }>();
    expect(row?.payload_pointer).toBeNull();
    expect(await env.R2.get("request/req-3d/envelope")).toBeNull();
  });
});

describe("manifest_retention_class_resolver", () => {
  it("returns published diagnostic_30d for clinic.visit_summary@1.0.0", () => {
    const resolve = createManifestRetentionClassResolver();
    expect(resolve("clinic.visit_summary", "1.0.0")).toBe("diagnostic_30d");
    expect(resolve("unknown.capability", "9.9.9")).toBe("diagnostic_7d");
  });
});

describe("retention_expiry_ledger", () => {
  it("deletes past-horizon ledger rows and keeps in-horizon", async () => {
    const oldDate = new Date(
      FIXTURE_NOW.getTime() - (LEDGER_HORIZON_DAYS + 1) * MS_PER_DAY,
    ).toISOString();
    const recentDate = FIXTURE_NOW.toISOString();

    for (const [reqId, ref, recordedAt] of [
      ["req-old", "REF-UOLD", oldDate],
      ["req-new", "REF-UNEW", recentDate],
    ] as const) {
      await env.DB.prepare(
        `INSERT INTO ai_request (
          request_id, request_reference, installation_id, actor_id, branch_id,
          capability_id, capability_version, prompt_artifact_hash, idempotency_key,
          trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
          payload_pointer, conversation_id, turn_ordinal
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL)`,
      )
        .bind(
          reqId,
          ref,
          FIXTURE_INSTALLATION_A,
          "actor",
          "branch",
          "cap",
          "1.0.0",
          "prompt@v1",
          `idem-${reqId}`,
          `trace-${reqId}`,
          "Completed",
          recordedAt,
          recordedAt,
          recordedAt,
        )
        .run();
    }

    await env.DB.prepare(
      `INSERT INTO usage_event (usage_event_id, installation_id, period, request_id, quota_weight, tokens, cost, recorded_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind("ue-old", FIXTURE_INSTALLATION_A, "2019-01", "req-old", 1, 100, 0.01, oldDate)
      .run();
    await env.DB.prepare(
      `INSERT INTO usage_event (usage_event_id, installation_id, period, request_id, quota_weight, tokens, cost, recorded_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind("ue-new", FIXTURE_INSTALLATION_A, "2026-08", "req-new", 1, 200, 0.02, recentDate)
      .run();
    await env.DB.prepare(
      `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)
       VALUES (?, ?, ?, ?, ?)`,
    )
      .bind(
        "rollup-old",
        JSON.stringify({ period: "2019-01", installation_id: FIXTURE_INSTALLATION_A }),
        1,
        100,
        0.01,
      )
      .run();

    await runRetentionPurge({ db: env.DB, r2: env.R2, now: FIXTURE_NOW });

    const oldUe = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM usage_event WHERE usage_event_id = ?",
    )
      .bind("ue-old")
      .first<{ c: number }>();
    const newUe = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM usage_event WHERE usage_event_id = ?",
    )
      .bind("ue-new")
      .first<{ c: number }>();
    const oldRollup = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM usage_rollup WHERE rollup_id = ?",
    )
      .bind("rollup-old")
      .first<{ c: number }>();

    expect(oldUe?.c).toBe(0);
    expect(newUe?.c).toBe(1);
    expect(oldRollup?.c).toBe(0);
  });
});

describe("retention_expiry_ephemeral", () => {
  it("expires jti/idempotency in place inside Quota DO with no D1/R2 prune", async () => {
    const storage = {
      data: new Map<string, unknown>(),
      async get<T>(key: string): Promise<T | undefined> {
        return this.data.get(key) as T | undefined;
      },
      async put(key: string, value: unknown): Promise<void> {
        this.data.set(key, value);
      },
    } as unknown as DurableObjectStorage;

    const blockConcurrencyWhile = async <T>(fn: () => Promise<T>): Promise<T> =>
      fn();

    const admission: AdmissionRequest = {
      kind: "admission",
      jti: "jti-ephemeral-test",
      installationId: FIXTURE_INSTALLATION_A,
      idempotencyKey: "idem-ephemeral-test",
      requestReference: "REF-EPH01",
      entitlement: {
        plan: "starter",
        period_bounds: {
          period_start: "2026-08-01T00:00:00.000Z",
          period_end: "2026-09-01T00:00:00.000Z",
        },
        request_quota: 100,
        token_cost_budget: { token_budget: 10000, cost_budget: 10 },
        allowed_capabilities: ["cap"],
        soft_threshold: 0.8,
        status: "active",
      },
    };

    const admittedAt = FIXTURE_NOW.getTime() - EPHEMERAL_HORIZON_MS - 1000;
    await admissionRPC(storage, blockConcurrencyWhile, admission, admittedAt);

    const replayBefore = await admissionRPC(
      storage,
      blockConcurrencyWhile,
      admission,
      admittedAt + 1000,
    );
    expect(replayBefore.outcome).toBe("replay");

    const afterExpiry = await admissionRPC(
      storage,
      blockConcurrencyWhile,
      admission,
      admittedAt + EPHEMERAL_HORIZON_MS + 1,
    );
    expect(afterExpiry.outcome).toBe("admitted");

    const d1CountBefore = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request",
    ).first<{ c: number }>();
    await runRetentionPurge({ db: env.DB, r2: env.R2, now: FIXTURE_NOW });
    const d1CountAfter = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request",
    ).first<{ c: number }>();
    expect(d1CountAfter?.c).toBe(d1CountBefore?.c);
  });
});

describe("retention_per_capability_diagnostic", () => {
  it("purges shorter-horizon capability envelopes while keeping longer", async () => {
    const borderlineDate = new Date(
      FIXTURE_NOW.getTime() - 15 * MS_PER_DAY,
    ).toISOString();

    await seedRequestWithEnvelope("req-short", FIXTURE_INSTALLATION_A, "cap.short", borderlineDate);
    await seedRequestWithEnvelope("req-long", FIXTURE_INSTALLATION_A, "cap.long", borderlineDate);

    await runRetentionPurge({
      db: env.DB,
      r2: env.R2,
      now: FIXTURE_NOW,
      resolveRetentionClass: (capId) =>
        capId === "cap.long" ? "diagnostic_30d" : "diagnostic_7d",
    });

    const shortRow = await env.DB.prepare(
      "SELECT payload_pointer FROM ai_request WHERE request_id = ?",
    )
      .bind("req-short")
      .first<{ payload_pointer: string | null }>();
    const longRow = await env.DB.prepare(
      "SELECT payload_pointer FROM ai_request WHERE request_id = ?",
    )
      .bind("req-long")
      .first<{ payload_pointer: string | null }>();

    expect(shortRow?.payload_pointer).toBeNull();
    expect(longRow?.payload_pointer).not.toBeNull();
    expect(parseDiagnosticHorizonDays("diagnostic_30d")).toBe(30);
  });
});

describe("retention_purge_by_installation_id", () => {
  it("clears D1 and R2 for the target installation only", async () => {
    const recentDate = FIXTURE_NOW.toISOString();
    await seedRequestWithEnvelope("req-purge-a", FIXTURE_INSTALLATION_A, "cap", recentDate);
    await seedRequestWithEnvelope("req-purge-b", FIXTURE_INSTALLATION_B, "cap", recentDate);

    // NULL pointer with derived-key object — must still be deleted.
    const nullPointerKey = "request/req-purge-null/envelope";
    await env.DB.prepare(
      `INSERT INTO ai_request (
        request_id, request_reference, installation_id, actor_id, branch_id,
        capability_id, capability_version, prompt_artifact_hash, idempotency_key,
        trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
        payload_pointer, conversation_id, turn_ordinal
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL)`,
    )
      .bind(
        "req-purge-null",
        "REF-PNUL",
        FIXTURE_INSTALLATION_A,
        "actor",
        "branch",
        "cap",
        "1.0.0",
        "prompt@v1",
        "idem-null",
        "trace-null",
        "Completed",
        recentDate,
        recentDate,
        recentDate,
      )
      .run();
    await env.R2.put(nullPointerKey, JSON.stringify({ orphan: true }));

    await env.DB.prepare(
      `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)
       VALUES (?, ?, ?, ?, ?)`,
    )
      .bind(
        "rollup-purge-a",
        JSON.stringify({ period: "2026-08", installation_id: FIXTURE_INSTALLATION_A }),
        1,
        10,
        0.01,
      )
      .run();
    await env.DB.prepare(
      `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)
       VALUES (?, ?, ?, ?, ?)`,
    )
      .bind(
        "rollup-purge-b",
        JSON.stringify({ period: "2026-08", installation_id: FIXTURE_INSTALLATION_B }),
        1,
        20,
        0.02,
      )
      .run();
    await env.DB.prepare(
      `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
       VALUES (?, ?, ?, ?)`,
    )
      .bind(
        "counter-purge-a",
        JSON.stringify({
          installation_id: FIXTURE_INSTALLATION_A,
          error_code: "quota_exhausted",
        }),
        "2026-08-02T12:00:00.000Z",
        3,
      )
      .run();
    await env.DB.prepare(
      `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
       VALUES (?, ?, ?, ?)`,
    )
      .bind(
        "counter-purge-b",
        JSON.stringify({
          installation_id: FIXTURE_INSTALLATION_B,
          error_code: "quota_exhausted",
        }),
        "2026-08-02T12:00:00.000Z",
        5,
      )
      .run();

    await env.DB.prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version, granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
    )
      .bind(
        "grant-a",
        `installation:${FIXTURE_INSTALLATION_A}`,
        "cap",
        "1.0.0",
        recentDate,
        recentDate,
        "operator-001",
      )
      .run();
    await env.DB.prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version, granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
    )
      .bind(
        "grant-b",
        `installation:${FIXTURE_INSTALLATION_B}`,
        "cap",
        "1.0.0",
        recentDate,
        recentDate,
        "operator-001",
      )
      .run();

    await env.DB.prepare(
      `INSERT INTO installation_key (
        key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at
      ) VALUES (?, ?, ?, ?, ?, NULL, NULL)`,
    )
      .bind("key-a", FIXTURE_INSTALLATION_A, "pk-a", "EdDSA", recentDate)
      .run();
    await env.DB.prepare(
      `INSERT INTO entitlement (
        entitlement_id, installation_id, plan, period_start, period_end,
        request_quota, token_budget, cost_budget, allowed_capabilities, soft_threshold, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        "ent-a",
        FIXTURE_INSTALLATION_A,
        "starter",
        "2026-08-01T00:00:00.000Z",
        "2026-09-01T00:00:00.000Z",
        100,
        10000,
        10,
        "[]",
        0.8,
        "active",
      )
      .run();

    await purgeByInstallationId(FIXTURE_INSTALLATION_A, "operator-001", {
      db: env.DB,
      r2: env.R2,
    });

    const aCount = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_A)
      .first<{ c: number }>();
    const bCount = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_B)
      .first<{ c: number }>();

    expect(aCount?.c).toBe(0);
    expect(bCount?.c).toBe(1);
    expect(await env.R2.get(nullPointerKey)).toBeNull();
    expect(await env.R2.get("request/req-purge-a/envelope")).toBeNull();
    const surviving = await env.R2.get("request/req-purge-b/envelope");
    expect(surviving).not.toBeNull();
    await surviving?.text();

    const rollupA = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM usage_rollup WHERE rollup_id = ?",
    )
      .bind("rollup-purge-a")
      .first<{ c: number }>();
    const rollupB = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM usage_rollup WHERE rollup_id = ?",
    )
      .bind("rollup-purge-b")
      .first<{ c: number }>();
    const counterA = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM platform_counter WHERE counter_id = ?",
    )
      .bind("counter-purge-a")
      .first<{ c: number }>();
    const counterB = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM platform_counter WHERE counter_id = ?",
    )
      .bind("counter-purge-b")
      .first<{ c: number }>();

    expect(rollupA?.c).toBe(0);
    expect(rollupB?.c).toBe(1);
    expect(counterA?.c).toBe(0);
    expect(counterB?.c).toBe(1);

    const grantA = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM capability_grant WHERE grant_id = ?",
    )
      .bind("grant-a")
      .first<{ c: number }>();
    const grantB = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM capability_grant WHERE grant_id = ?",
    )
      .bind("grant-b")
      .first<{ c: number }>();
    expect(grantA?.c).toBe(0);
    expect(grantB?.c).toBe(1);

    const instA = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM installation WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_A)
      .first<{ c: number }>();
    const instB = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM installation WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_B)
      .first<{ c: number }>();
    const keyA = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM installation_key WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_A)
      .first<{ c: number }>();
    const entA = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM entitlement WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_A)
      .first<{ c: number }>();

    expect(instA?.c).toBe(0);
    expect(instB?.c).toBe(1);
    expect(keyA?.c).toBe(0);
    expect(entA?.c).toBe(0);

    const audit = await env.DB.prepare(
      "SELECT action FROM control_audit WHERE target = ?",
    )
      .bind(FIXTURE_INSTALLATION_A)
      .first<{ action: string }>();
    expect(audit?.action).toBe("purge_installation");
  });
});
