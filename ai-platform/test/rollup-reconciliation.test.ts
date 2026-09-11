import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import retentionIndexesSql from "../migrations/20260805120000_f3_retention_indexes.sql?raw";
import quotaWeightMigrationSql from "../migrations/20260911180000_usage_rollup_quota_weight.sql?raw";
import {
  logReconciliationReport,
  runReconciliation,
  runRollup,
  runRollupAndReconciliation,
} from "../src/rollup";
import { createLogger } from "../src/logger";

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
  options?: {
    state?: string;
    completedAt?: string;
    period?: string;
    recordedAt?: string;
    tokens?: number;
    cost?: number;
  },
): Promise<void> {
  const completedAt = options?.completedAt ?? "2026-08-15T12:00:00.000Z";
  const state = options?.state ?? "Completed";
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
      state,
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
        options?.period ?? "2026-08",
        requestId,
        1,
        options?.tokens ?? 150,
        options?.cost ?? 0.005,
        options?.recordedAt ?? completedAt,
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
  await applyPlatformSchema(env.DB, retentionIndexesSql);
  await applyPlatformSchema(env.DB, quotaWeightMigrationSql);
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

describe("rollup_period_aligned_advanced_window", () => {
  it("keeps full period ledger sums when a later window no longer covers earlier recorded_at", async () => {
    await seedTerminalRequest("req-july", "REF-JUL", true, true, {
      completedAt: "2026-07-15T12:00:00.000Z",
      period: "2026-07",
      recordedAt: "2026-07-15T12:00:00.000Z",
      tokens: 100,
      cost: 0.01,
    });
    await seedTerminalRequest("req-aug", "REF-AUG", true, true, {
      completedAt: "2026-08-15T12:00:00.000Z",
      period: "2026-08",
      recordedAt: "2026-08-15T12:00:00.000Z",
      tokens: 200,
      cost: 0.02,
    });

    const julyFull = await env.DB.prepare(
      `SELECT SUM(tokens) AS tokens, SUM(cost) AS cost, COUNT(*) AS cnt
       FROM usage_event WHERE period = '2026-07'`,
    ).first<{ tokens: number; cost: number; cnt: number }>();

    // Aug window touches Aug period; period-aligned re-read still writes full period sums.
    // Cover July first so a prior July rollup exists to prove Sep does not corrupt it.
    await runRollup({
      db: env.DB,
      window: {
        start: "2026-07-01T00:00:00.000Z",
        end: "2026-08-31T23:59:59.999Z",
      },
    });

    await runRollup({
      db: env.DB,
      window: {
        start: "2026-08-01T00:00:00.000Z",
        end: "2026-08-31T23:59:59.999Z",
      },
    });

    // Sep window no longer covers July recorded_at — must not shrink July rollup.
    await runRollup({
      db: env.DB,
      window: {
        start: "2026-09-01T00:00:00.000Z",
        end: "2026-09-30T23:59:59.999Z",
      },
    });

    const julyAfterSep = await env.DB.prepare(
      `SELECT request_count, tokens, cost FROM usage_rollup
       WHERE dimensions LIKE '%2026-07%'`,
    ).first<{ request_count: number; tokens: number; cost: number }>();

    expect(julyAfterSep?.tokens).toBe(julyFull?.tokens);
    expect(julyAfterSep?.cost).toBe(julyFull?.cost);
    expect(julyAfterSep?.request_count).toBe(julyFull?.cnt);
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

  it("flags Failed requests missing ai_attempt rows as genuine anomalies", async () => {
    await seedTerminalRequest("req-failed-no-attempt", "REF-FA001", false, true, {
      state: "Failed",
    });

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingAttemptRows).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ requestId: "req-failed-no-attempt" }),
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

describe("reconciliation_negative_cases", () => {
  it("does not flag terminal requests that have attempts and usage", async () => {
    await seedTerminalRequest("req-ok", "REF-OK001", true, true);

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingAttemptRows).toEqual([]);
    expect(report.missingUsageCredit).toEqual([]);
  });

  it("does not flag in-flight Accepted requests", async () => {
    await seedTerminalRequest("req-inflight", "REF-IN001", false, false, {
      state: "Accepted",
    });

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingAttemptRows).toEqual([]);
    expect(report.missingUsageCredit).toEqual([]);
  });

  it("does not flag terminal requests outside the window", async () => {
    await seedTerminalRequest("req-outside", "REF-OUT001", false, false, {
      completedAt: "2026-06-15T12:00:00.000Z",
    });

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingAttemptRows).toEqual([]);
    expect(report.missingUsageCredit).toEqual([]);
  });

  it("does not flag AwaitingContext — that state is not expected to have attempt or usage rows", async () => {
    await seedTerminalRequest("req-await", "REF-AW001", false, false, {
      state: "AwaitingContext",
    });

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingAttemptRows).toEqual([]);
    expect(report.missingUsageCredit).toEqual([]);
  });

  it("does not flag Cancelled without attempt rows (abort before first provider attempt is expected)", async () => {
    await seedTerminalRequest("req-cancel-no-attempt", "REF-CN001", false, true, {
      state: "Cancelled",
    });

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingAttemptRows).toEqual([]);
    expect(report.missingUsageCredit).toEqual([]);
  });

  it("flags Cancelled missing the usage_event row that settlement must write", async () => {
    await seedTerminalRequest("req-cancel-no-usage", "REF-CN002", true, false, {
      state: "Cancelled",
    });

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingUsageCredit).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ requestId: "req-cancel-no-usage" }),
      ]),
    );
  });

  it("cannot match usage_event rows whose request_id was nulled by retention", async () => {
    await seedTerminalRequest("req-nulled-usage", "REF-NL001", true, true);
    await env.DB.prepare(
      "UPDATE usage_event SET request_id = NULL WHERE request_id = ?",
    )
      .bind("req-nulled-usage")
      .run();

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingUsageCredit).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ requestId: "req-nulled-usage" }),
      ]),
    );
  });

  it("does not flag Failed that has attempt and usage rows", async () => {
    await seedTerminalRequest("req-failed-ok", "REF-FL001", true, true, {
      state: "Failed",
    });

    const report = await runReconciliation({ db: env.DB, window: WINDOW });

    expect(report.missingAttemptRows).toEqual([]);
    expect(report.missingUsageCredit).toEqual([]);
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

describe("log_reconciliation_report", () => {
  function captureLogger() {
    const lines: Array<{ message: string; data?: Record<string, unknown> }> = [];
    const logger = createLogger({
      file: "rollup/index.ts",
      verbosity: 2,
      sink: {
        write(line) {
          const match = /\[Info\] ([^{]+)/.exec(line);
          if (!match) {
            return;
          }
          const message = match[1]!.trim();
          const jsonStart = line.indexOf("{");
          const data =
            jsonStart >= 0
              ? (JSON.parse(line.slice(jsonStart)) as Record<string, unknown>)
              : undefined;
          lines.push({ message, data });
        },
      },
    });
    return { lines, logger };
  }

  it("emits structured usage_rollup_reconciliation log from runRollupAndReconciliation result", async () => {
    await seedTerminalRequest("req-log", "REF-LOG001", true, true);
    const result = await runRollupAndReconciliation({
      db: env.DB,
      window: WINDOW,
    });

    const { lines, logger } = captureLogger();
    logReconciliationReport(result, logger);

    expect(lines).toHaveLength(1);
    expect(lines[0]?.message).toBe("usage_rollup_reconciliation");
    expect(lines[0]?.data?.rollups_written).toBe(result.rollupsWritten);
    expect(lines[0]?.data?.missing_attempt_rows).toBe(0);
    expect(lines[0]?.data?.missing_usage_credit).toBe(0);
    expect(lines[0]?.data?.window).toEqual(WINDOW);
    expect(lines[0]?.data?.report).toEqual(result.report);
  });

  it("uses noopLogger by default without emitting output", () => {
    const emitted: string[] = [];
    const logger = createLogger({
      file: "rollup/index.ts",
      verbosity: 2,
      sink: { write: (line) => emitted.push(line) },
    });

    logReconciliationReport({
      rollupsWritten: 2,
      report: {
        window: WINDOW,
        missingAttemptRows: [{ requestId: "r1", requestReference: "REF-1" }],
        missingUsageCredit: [],
      },
    });
    expect(emitted).toHaveLength(0);

    logReconciliationReport(
      {
        rollupsWritten: 2,
        report: {
          window: WINDOW,
          missingAttemptRows: [{ requestId: "r1", requestReference: "REF-1" }],
          missingUsageCredit: [],
        },
      },
      logger,
    );
    expect(emitted).toHaveLength(1);
    expect(emitted[0]).toContain("usage_rollup_reconciliation");
    expect(emitted[0]).toContain('"missing_attempt_rows":1');
  });
});
