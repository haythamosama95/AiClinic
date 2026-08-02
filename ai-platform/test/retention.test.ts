import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  EPHEMERAL_HORIZON_MS,
  admissionRPC,
  type AdmissionRequest,
} from "../src/quota-do";
import {
  JOURNAL_HORIZON_DAYS,
  LEDGER_HORIZON_DAYS,
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
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM capability_grant"),
    env.DB.prepare("DELETE FROM ai_attempt"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
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

    const audit = await env.DB.prepare(
      "SELECT action FROM control_audit WHERE target = ?",
    )
      .bind(FIXTURE_INSTALLATION_A)
      .first<{ action: string }>();
    expect(audit?.action).toBe("purge_installation");
  });
});
