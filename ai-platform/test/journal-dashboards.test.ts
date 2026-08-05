import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  dashboardAvgAttemptLatencyByProvider,
  dashboardCostPerCapabilityPerInstallation,
  dashboardFallbackRateByProvider,
  dashboardQuotaRejectionRate,
  dashboardRepairRateByCapability,
  dashboardValidationFailureByPromptVersion,
  runAllDashboardQueries,
} from "../src/dashboards";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

const FIXTURE_INSTALLATION = "inst-dash-001";
const FIXTURE_ORG = "org-dash-001";

type D1WriteSpy = D1Database & {
  insertCount: () => number;
};

function createD1WriteSpy(realDb: D1Database): D1WriteSpy {
  let inserts = 0;
  const spy: D1WriteSpy = {
    ...realDb,
    prepare(query: string) {
      if (query.trim().toLowerCase().startsWith("insert")) {
        inserts += 1;
      }
      return realDb.prepare(query);
    },
    insertCount() {
      return inserts;
    },
  };
  return spy;
}

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
      "Dashboard Clinic",
      "active",
      "us-east-1",
      "2026-08-01T00:00:00.000Z",
    )
    .run();
}

async function seedDashboardData(): Promise<void> {
  const completedAt = "2026-08-15T12:00:00.000Z";

  await env.DB.prepare(
    `INSERT INTO ai_request (
      request_id, request_reference, installation_id, actor_id, branch_id,
      capability_id, capability_version, prompt_artifact_hash, idempotency_key,
      trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
      payload_pointer, conversation_id, turn_ordinal
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL)`,
  )
    .bind(
      "req-dash-1",
      "REF-D001",
      FIXTURE_INSTALLATION,
      "actor-001",
      "branch-001",
      "clinic.dash-a",
      "1.0.0",
      "prompt/v1@v1",
      "idem-d1",
      "trace-d1",
      "Failed",
      completedAt,
      completedAt,
      completedAt,
      "validation_failed",
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
      "req-dash-2",
      "REF-D002",
      FIXTURE_INSTALLATION,
      "actor-001",
      "branch-001",
      "clinic.dash-a",
      "1.0.0",
      "prompt/v1@v1",
      "idem-d2",
      "trace-d2",
      "Completed",
      completedAt,
      completedAt,
      completedAt,
    )
    .run();

  // Cancelled must not dilute validation-failure denominator (Completed+Failed only).
  await env.DB.prepare(
    `INSERT INTO ai_request (
      request_id, request_reference, installation_id, actor_id, branch_id,
      capability_id, capability_version, prompt_artifact_hash, idempotency_key,
      trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
      payload_pointer, conversation_id, turn_ordinal
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL)`,
  )
    .bind(
      "req-dash-cancelled",
      "REF-D003",
      FIXTURE_INSTALLATION,
      "actor-001",
      "branch-001",
      "clinic.dash-a",
      "1.0.0",
      "prompt/v1@v1",
      "idem-d3",
      "trace-d3",
      "Cancelled",
      completedAt,
      completedAt,
      completedAt,
      "validation_failed",
    )
    .run();

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO ai_attempt (
        attempt_id, request_id, attempt_no, provider, model, outcome,
        latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
    ).bind("att-d1", "req-dash-1", 1, "deepseek", "m1", "failure", 100, 10, 5, 0.001, "p1"),
    env.DB.prepare(
      `INSERT INTO ai_attempt (
        attempt_id, request_id, attempt_no, provider, model, outcome,
        latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
    ).bind("att-d2a", "req-dash-2", 1, "gemini", "m2", "failure", 200, 20, 10, 0.002, "p2"),
    env.DB.prepare(
      `INSERT INTO ai_attempt (
        attempt_id, request_id, attempt_no, provider, model, outcome,
        latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
    ).bind("att-d2b", "req-dash-2", 2, "deepseek", "m1", "success", 150, 30, 15, 0.003, "p3"),
    // Same-provider retry — must NOT count as provider fallback.
    env.DB.prepare(
      `INSERT INTO ai_attempt (
        attempt_id, request_id, attempt_no, provider, model, outcome,
        latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
    ).bind("att-d2c", "req-dash-2", 3, "deepseek", "m1", "success", 50, 5, 2, 0.0005, "p4"),
  ]);

  await env.DB.prepare(
    `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)
     VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(
      "rollup-dash-1",
      JSON.stringify({
        installation_id: FIXTURE_INSTALLATION,
        period: "2026-08",
      }),
      2,
      100,
      0.01,
    )
    .run();

  await env.DB.prepare(
    `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
     VALUES (?, ?, ?, ?)`,
  )
    .bind(
      "counter-quota-1",
      JSON.stringify({ error_code: "quota_exhausted", installation_id: FIXTURE_INSTALLATION }),
      "2026-08-15T12:00:00",
      3,
    )
    .run();
}

async function clearTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM platform_counter"),
    env.DB.prepare("DELETE FROM usage_rollup"),
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
  await seedDashboardData();
});

describe("dashboard_avg_attempt_latency_by_provider", () => {
  it("returns first-attempt average latency by provider (not true TTFT)", async () => {
    const result = await dashboardAvgAttemptLatencyByProvider(env.DB);
    expect(result.deepseek).toBe(100);
    expect(result.gemini).toBe(200);
  });
});

describe("dashboard_validation_failure_by_prompt_version", () => {
  it("returns correct validation-failure rate over Completed+Failed only", async () => {
    const result = await dashboardValidationFailureByPromptVersion(env.DB);
    // Failed (validation) + Completed → 0.5; Cancelled with validation_failed excluded
    expect(result["prompt/v1@v1"]).toBe(0.5);
  });
});

describe("dashboard_repair_rate_by_capability", () => {
  it("returns empty until RepairJournalSink is persisted", async () => {
    const result = await dashboardRepairRateByCapability(env.DB);
    expect(result).toEqual({});
  });
});

describe("dashboard_fallback_rate_by_provider", () => {
  it("counts true provider fallbacks only (not same-provider retries)", async () => {
    const result = await dashboardFallbackRateByProvider(env.DB);
    // deepseek: att-d2b is fallback (gemini→deepseek); att-d1 first + att-d2c same-provider are not
    // 1 fallback / 3 deepseek attempts = 1/3
    expect(result.deepseek).toBeCloseTo(1 / 3, 5);
    expect(result.gemini).toBe(0);
  });
});

describe("dashboard_cost_per_capability_per_installation", () => {
  it("returns cost grouped by capability id, version, and installation", async () => {
    const result = await dashboardCostPerCapabilityPerInstallation(env.DB);
    const entry = result.find(
      (r) =>
        r.capabilityId === "clinic.dash-a" &&
        r.capabilityVersion === "1.0.0" &&
        r.installationId === FIXTURE_INSTALLATION,
    );
    // 0.001 + 0.002 + 0.003 + 0.0005
    expect(entry?.cost).toBeCloseTo(0.0065, 5);
  });
});

describe("dashboard_quota_rejection_rate", () => {
  it("approximates quota_exhausted_count / journaled request_count", async () => {
    const result = await dashboardQuotaRejectionRate(env.DB);
    // 3 quota / 3 requests (Failed+Completed+Cancelled) = 1.0
    expect(result).toBeCloseTo(1.0, 5);
  });
});

describe("dashboard_no_second_metrics_store", () => {
  it("does not write to a second metrics store during dashboard queries", async () => {
    const spy = createD1WriteSpy(env.DB);
    await runAllDashboardQueries(spy);
    expect(spy.insertCount()).toBe(0);
  });
});
