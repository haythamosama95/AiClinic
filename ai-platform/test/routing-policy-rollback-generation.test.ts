import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import canaryMigrationSql from "../migrations/20260803100000_routing_policy_canary.sql?raw";
import statusMigrationSql from "../migrations/20260805190000_routing_policy_status.sql?raw";
import operatorCredentialMigrationSql from "../migrations/20261003120000_operator_credential_and_platform_alert.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
import rm33RoutingIntegritySql from "../migrations/20261021140000_rm33_routing_configuration_integrity.sql?raw";
import rm33ActivationGenerationSql from "../migrations/20261021150000_rm33_routing_activation_generation.sql?raw";
import {
  canaryRoutingPolicyAction,
  promoteRoutingPolicyAction,
  publishRoutingPolicyAction,
  rollbackRoutingPolicyAction,
} from "../src/control/routing-policy";

const OPERATOR = "operator-rm33-activation";
const POLICY_ID = "standard";
const CANARY_INSTALLATION_ID = "inst-rm33-activation";

async function applySchema(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);
  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

function bindings(): { DB: D1Database; R2: R2Bucket } {
  return { DB: env.DB, R2: env.R2 };
}

function policyDocument(version: number, providerId: string): Record<string, unknown> {
  return {
    schema_version: 1,
    policy_id: POLICY_ID,
    policy_version: version,
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules: [
      {
        rule_id: "catch-all",
        match: {},
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: ["en"],
        },
        targets: [
          {
            provider_id: providerId,
            model_id: `${providerId}-chat`,
            features: {
              structured_output: false,
              min_context_window: 128_000,
              languages: ["en"],
              latency_class: "interactive",
              cost_class: "standard",
            },
            max_attempts: 2,
            timeout_ms: 30_000,
          },
        ],
      },
    ],
    overrides: [],
  };
}

async function publish(version: number, providerId: string): Promise<void> {
  const result = await publishRoutingPolicyAction(
    bindings(),
    OPERATOR,
    policyDocument(version, providerId),
  );
  expect(result.ok).toBe(true);
}

async function statusOf(version: string): Promise<string | null> {
  const row = await env.DB
    .prepare(`SELECT status FROM routing_policy WHERE policy_id = ? AND version = ?`)
    .bind(POLICY_ID, version)
    .first<{ status: string }>();
  return row?.status ?? null;
}

async function activeVersion(): Promise<string | null> {
  const row = await env.DB
    .prepare(`SELECT version FROM routing_policy WHERE policy_id = ? AND status = 'active'`)
    .bind(POLICY_ID)
    .first<{ version: string }>();
  return row?.version ?? null;
}

async function generationOf(): Promise<number | null> {
  const row = await env.DB
    .prepare(`SELECT generation FROM routing_policy_activation WHERE policy_id = ?`)
    .bind(POLICY_ID)
    .first<{ generation: number }>();
  return row?.generation ?? null;
}

async function auditCount(action: string, target: string): Promise<number> {
  const row = await env.DB
    .prepare(`SELECT COUNT(*) AS n FROM control_audit WHERE action = ? AND target = ?`)
    .bind(action, target)
    .first<{ n: number }>();
  return row?.n ?? 0;
}

beforeAll(async () => {
  await applySchema(env.DB, migrationSql);
  await applySchema(env.DB, canaryMigrationSql);
  await applySchema(env.DB, statusMigrationSql);
  await applySqlStatements(env.DB, operatorCredentialMigrationSql);
  await applySchema(env.DB, rm33RoutingIntegritySql);
  await applySchema(env.DB, rm33ActivationGenerationSql);
});

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM routing_policy_activation"),
    env.DB.prepare("DELETE FROM routing_policy"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
  await env.DB
    .prepare(
      `INSERT INTO installation (
         installation_id, org_id, display_name, status, region, enrolled_at
       ) VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      CANARY_INSTALLATION_ID,
      "org-rm33-activation",
      "RM33 activation",
      "active",
      "us-east-1",
      "2026-10-21T12:00:00.000Z",
    )
    .run();
});

describe("R8-ROLLBACK1: routing activation generation fencing", () => {
  it("R8-ROLLBACK1: rollback of B restores recorded predecessor A, not canary C", async () => {
    await publish(1, "deepseek");
    await publish(2, "gemini");
    await publish(3, "openai");

    expect((await promoteRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "1")).ok).toBe(true);
    expect(
      (await canaryRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "3", [CANARY_INSTALLATION_ID])).ok,
    ).toBe(true);
    expect((await promoteRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "2")).ok).toBe(true);
    expect(await activeVersion()).toBe("2");
    // Promoting B supersedes the canary C; C must not remain a rollback target.
    expect(await statusOf("3")).toBe("superseded");

    const rollback = await rollbackRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "2");
    expect(rollback.ok).toBe(true);
    expect(await activeVersion()).toBe("1");
    expect(await statusOf("2")).toBe("superseded");
    expect(await statusOf("3")).toBe("superseded");
  });

  it("R8-ROLLBACK1: rollback with unknown predecessor returns conflict and changes nothing", async () => {
    await publish(1, "deepseek");
    await publish(2, "gemini");
    expect((await promoteRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "1")).ok).toBe(true);
    expect((await promoteRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "2")).ok).toBe(true);

    // Simulate history whose predecessor cannot be recovered.
    await env.DB
      .prepare(
        `UPDATE routing_policy_activation
         SET predecessor_version = NULL, predecessor_state = 'unknown'
         WHERE policy_id = ?`,
      )
      .bind(POLICY_ID)
      .run();
    const generationBefore = await generationOf();

    const rollback = await rollbackRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "2");
    expect(rollback).toEqual({
      ok: false,
      status: 409,
      error: "rollback_predecessor_unknown",
    });
    expect(await activeVersion()).toBe("2");
    expect(await generationOf()).toBe(generationBefore);
    expect(await auditCount("routing_policy_rollback", `${POLICY_ID}@2`)).toBe(0);
  });

  it("R8-ROLLBACK1: stale generation promote commits nothing", async () => {
    await publish(1, "deepseek");
    await publish(2, "gemini");
    expect((await promoteRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "1")).ok).toBe(true);
    const generationBefore = await generationOf();
    expect(generationBefore).toBe(1);

    const stale = await promoteRoutingPolicyAction(
      bindings(),
      OPERATOR,
      POLICY_ID,
      "2",
      0,
    );
    expect(stale).toEqual({ ok: false, status: 409, error: "generation_conflict" });
    expect(await activeVersion()).toBe("1");
    expect(await statusOf("2")).toBe("published");
    expect(await generationOf()).toBe(generationBefore);
    expect(await auditCount("routing_policy_promote", `${POLICY_ID}@2`)).toBe(0);
  });

  it("R8-ROLLBACK1: second rollback with predecessor none returns a conflict", async () => {
    // A first version promoted with no prior active version records predecessor_state 'none'.
    await publish(1, "deepseek");
    expect((await promoteRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "1")).ok).toBe(true);
    const predecessorState = await env.DB
      .prepare(`SELECT predecessor_state FROM routing_policy_activation WHERE policy_id = ?`)
      .bind(POLICY_ID)
      .first<{ predecessor_state: string }>();
    expect(predecessorState?.predecessor_state).toBe("none");
    const generationBefore = await generationOf();

    const first = await rollbackRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "1");
    expect(first).toEqual({ ok: false, status: 409, error: "illegal_policy_transition" });
    const second = await rollbackRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "1");
    expect(second).toEqual({ ok: false, status: 409, error: "illegal_policy_transition" });

    expect(await activeVersion()).toBe("1");
    expect(await generationOf()).toBe(generationBefore);
    expect(await auditCount("routing_policy_rollback", `${POLICY_ID}@1`)).toBe(0);
  });

  it("R8-ROLLBACK1: promotion records the predecessor and fresh generation", async () => {
    await publish(1, "deepseek");
    await publish(2, "gemini");
    expect((await promoteRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "1")).ok).toBe(true);
    expect((await promoteRoutingPolicyAction(bindings(), OPERATOR, POLICY_ID, "2", 1)).ok).toBe(true);

    const record = await env.DB
      .prepare(
        `SELECT active_version, predecessor_version, predecessor_state, generation
         FROM routing_policy_activation WHERE policy_id = ?`,
      )
      .bind(POLICY_ID)
      .first();
    expect(record).toEqual({
      active_version: "2",
      predecessor_version: "1",
      predecessor_state: "known",
      generation: 2,
    });
  });
});
