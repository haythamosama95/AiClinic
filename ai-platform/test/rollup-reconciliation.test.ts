import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  runReconciliation,
  runRollup,
  runRollupAndReconciliation,
} from "../src/rollup";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

const FIXTURE_INSTALLATION = "inst-rollup-001";
const FIXTURE_ORG = "org-rollup-001";
const WINDOW_START = "2026-08-01T00:00:00.000Z";
const WINDOW_END = "2026-08-31T23:59:59.999Z";
const WINDOW = { start: WINDOW_START, end: WINDOW_END };

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

async function seedInstallation(): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (installation_id, org_id, display_name, status, region, enrolled_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      FIXTURE_INSTALLATION,
      FIXTURE_ORG,
      "Rollup Clinic",
      "active",
      "us-east-1",
      "2026-08-01T00:00:00.000Z",
    )
    .run();
}

async function seedTerminalRequest(
  requestId: string,
  reference: string,
  withAttempt: boolean,
  withUsage: boolean,
): Promise<void> {
  const completedAt = "2026-08-15T12:00:00.000Z";
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
      FIXTURE_INSTALLATION,
      "actor-001",
      "branch-001",
      "clinic.rollup-test",
      "1.0.0",
      "prompt/rollup@v1",
      `idem-${requestId}`,
      `trace-${requestId}`,
      "Completed",
      completedAt,
      completedAt,
      completedAt,
    )
    .run();

  if (withAttempt) {
    await env.DB.prepare(
      `INSERT INTO ai_attempt (
        attempt_id, request_id, attempt_no, provider, model, outcome,
        latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
    )
      .bind(
        `attempt-${requestId}`,
        requestId,
        1,
        "deepseek",
        "rollup-fixture",
        "success",
        200,
        100,
        50,
        0.005,
        `prov-${requestId}`,
      )
      .run();
  }

  if (withUsage) {
    await env.DB.prepare(
      `INSERT INTO usage_event (
        usage_event_id, installation_id, period, request_id, quota_weight, tokens, cost, recorded_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        `usage-${requestId}`,
        FIXTURE_INSTALLATION,
        "2026-08",
        requestId,
        1,
        150,
        0.005,
        completedAt,
      )
      .run();
  }
}

async function clearTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM usage_rollup"),
    env.DB.prepare("DELETE FROM usage_event"),
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
  await seedInstallation();
});

describe("rollup_totals_equal_ledger", () => {
  it("produces usage_rollup totals equal to usage_event ledger sums", async () => {
    await seedTerminalRequest("req-r1", "REF-R001", true, true);
    await seedTerminalRequest("req-r2", "REF-R002", true, true);

    await runRollup({ db: env.DB, window: WINDOW });

    const ledger = await env.DB.prepare(
      `SELECT SUM(tokens) AS tokens, SUM(cost) AS cost, COUNT(*) AS cnt
       FROM usage_event WHERE recorded_at >= ? AND recorded_at <= ?`,
    )
      .bind(WINDOW.start, WINDOW.end)
      .first<{ tokens: number; cost: number; cnt: number }>();

    const rollup = await env.DB.prepare(
      `SELECT SUM(tokens) AS tokens, SUM(cost) AS cost, SUM(request_count) AS cnt
       FROM usage_rollup`,
    ).first<{ tokens: number; cost: number; cnt: number }>();

    expect(rollup?.tokens).toBe(ledger?.tokens);
    expect(rollup?.cost).toBe(ledger?.cost);
    expect(rollup?.cnt).toBe(ledger?.cnt);
  });
});

describe("reconciliation_missing_attempt_rows", () => {
  it("flags terminal requests with no ai_attempt rows", async () => {
    await seedTerminalRequest("req-no-attempt", "REF-NA001", false, true);

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingAttemptRows).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ requestId: "req-no-attempt" }),
      ]),
    );
  });
});

describe("reconciliation_missing_usage_credit", () => {
  it("flags terminal requests missing usage_event settlement", async () => {
    await seedTerminalRequest("req-no-usage", "REF-NU001", true, false);

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingUsageCredit).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ requestId: "req-no-usage" }),
      ]),
    );
  });
});

describe("rollup_rerun_idempotent", () => {
  it("does not duplicate rollup totals on re-run", async () => {
    await seedTerminalRequest("req-idem", "REF-ID001", true, true);

    await runRollupAndReconciliation({ db: env.DB, window: WINDOW });
    const firstRollup = await env.DB.prepare(
      "SELECT SUM(tokens) AS tokens, COUNT(*) AS cnt FROM usage_rollup",
    ).first<{ tokens: number; cnt: number }>();

    await runRollupAndReconciliation({ db: env.DB, window: WINDOW });
    const secondRollup = await env.DB.prepare(
      "SELECT SUM(tokens) AS tokens, COUNT(*) AS cnt FROM usage_rollup",
    ).first<{ tokens: number; cnt: number }>();

    const rollupRowCount = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM usage_rollup",
    ).first<{ c: number }>();

    expect(secondRollup?.tokens).toBe(firstRollup?.tokens);
    expect(secondRollup?.cnt).toBe(firstRollup?.cnt);
    expect(rollupRowCount?.c).toBe(1);
  });
});
