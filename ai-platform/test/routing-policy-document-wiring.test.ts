import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import canaryMigrationSql from "../migrations/20260803100000_routing_policy_canary.sql?raw";
import statusMigrationSql from "../migrations/20260805190000_routing_policy_status.sql?raw";
import rm33RoutingIntegritySql from "../migrations/20261021140000_rm33_routing_configuration_integrity.sql?raw";
import { createD1ConfigReader } from "../src/config-cache";
import {
  promoteRoutingPolicyAction,
  publishRoutingPolicyAction,
} from "../src/control/routing-policy";
import { sha256HexOfBytes } from "../src/router/policy-document";

const OPERATOR = "operator-rm33-wiring";
const CONTENT_PREFIX = "control/routing-policy/";

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

function policyDocument(policyId: string, version: number, providerId: string): Record<string, unknown> {
  return {
    schema_version: 1,
    policy_id: policyId,
    policy_version: version,
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules: [
      {
        rule_id: "catch-all",
        match: {},
        requires: { structured_output: false, min_context_window: 0, languages: ["en"] },
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

function identityOnly(policyId: string, version: number): Record<string, unknown> {
  return { schema_version: 1, policy_id: policyId, policy_version: version };
}

async function routingRow(
  policyId: string,
  version: string,
): Promise<{ status: string; content_pointer: string; content_sha256: string | null } | null> {
  return env.DB.prepare(
    `SELECT status, content_pointer, content_sha256 FROM routing_policy
     WHERE policy_id = ? AND version = ?`,
  )
    .bind(policyId, version)
    .first<{ status: string; content_pointer: string; content_sha256: string | null }>();
}

async function insertRawRow(
  policyId: string,
  version: string,
  pointer: string,
  status: string,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO routing_policy (
       policy_id, version, content_pointer, active_from, activated_by, status
     ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(policyId, version, pointer, "2026-10-01T00:00:00.000Z", OPERATOR, status)
    .run();
}

beforeAll(async () => {
  await applySchema(env.DB, migrationSql);
  await applySchema(env.DB, canaryMigrationSql);
  await applySchema(env.DB, statusMigrationSql);
  await applySchema(env.DB, rm33RoutingIntegritySql);
});

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM routing_policy"),
  ]);
});

describe("routing policy document wiring (RM33)", () => {
  it("R8-ROUTE1: identity-only publish returns invalid_policy_document and writes nothing", async () => {
    const policyId = "wiring-identity-only";
    const result = await publishRoutingPolicyAction(
      bindings(),
      OPERATOR,
      identityOnly(policyId, 1),
    );

    expect(result).toEqual({
      ok: false,
      status: 422,
      error: "invalid_policy_document",
    });
    expect(await routingRow(policyId, "1")).toBeNull();
    const objects = await env.R2.list({ prefix: `${CONTENT_PREFIX}${policyId}/` });
    expect(objects.objects).toHaveLength(0);
    const audits = await env.DB
      .prepare("SELECT COUNT(*) AS count FROM control_audit")
      .first<{ count: number }>();
    expect(audits?.count ?? 0).toBe(0);
  });

  it("R8-ROUTE1: promote of invalid stored bytes leaves serving unchanged", async () => {
    const policyId = "wiring-promote-invalid";
    const valid = await publishRoutingPolicyAction(bindings(), OPERATOR, policyDocument(policyId, 1, "deepseek"));
    expect(valid.ok).toBe(true);
    expect((await promoteRoutingPolicyAction(bindings(), OPERATOR, policyId, "1")).ok).toBe(true);

    // Historical malformed row: identity-only bytes stored under a published row.
    const brokenPointer = `${CONTENT_PREFIX}${policyId}/2/legacy-broken.json`;
    await env.R2.put(brokenPointer, JSON.stringify(identityOnly(policyId, 2)));
    await insertRawRow(policyId, "2", brokenPointer, "published");

    const promoted = await promoteRoutingPolicyAction(bindings(), OPERATOR, policyId, "2");
    expect(promoted).toEqual({
      ok: false,
      status: 422,
      error: "invalid_policy_document",
    });
    expect((await routingRow(policyId, "1"))?.status).toBe("active");
    expect((await routingRow(policyId, "2"))?.status).toBe("published");
  });

  it("R8-PUB1: two different publications of the same policy/version produce different digest keys and the winner's bytes are unchanged", async () => {
    const policyId = "wiring-two-publications";
    const winner = policyDocument(policyId, 1, "deepseek");
    const loser = policyDocument(policyId, 1, "gemini");

    expect((await publishRoutingPolicyAction(bindings(), OPERATOR, winner)).ok).toBe(true);
    const winnerRow = await routingRow(policyId, "1");
    expect(winnerRow).not.toBeNull();

    const winnerBytes = new TextEncoder().encode(JSON.stringify(winner));
    const loserBytes = new TextEncoder().encode(JSON.stringify(loser));
    const winnerDigest = await sha256HexOfBytes(winnerBytes);
    const loserDigest = await sha256HexOfBytes(loserBytes);
    expect(winnerDigest).not.toBe(loserDigest);
    expect(winnerRow!.content_pointer).toBe(
      `${CONTENT_PREFIX}${policyId}/1/sha256-${winnerDigest}.json`,
    );
    expect(winnerRow!.content_sha256).toBe(winnerDigest);

    const rejected = await publishRoutingPolicyAction(bindings(), OPERATOR, loser);
    expect(rejected).toEqual({ ok: false, status: 409, error: "already_published" });

    // The loser's digest-keyed object is never written under the winner's key,
    // and the winner's stored bytes are exactly what was accepted.
    const stored = await env.R2.get(winnerRow!.content_pointer);
    expect(stored).not.toBeNull();
    expect(new Uint8Array(await stored!.arrayBuffer())).toEqual(winnerBytes);
    expect(await routingRow(policyId, "1")).toEqual(winnerRow);
  });

  it("R8-PUB1: digest mismatch on load fails explicitly", async () => {
    const policyId = "wiring-digest-mismatch";
    const document = policyDocument(policyId, 1, "deepseek");
    expect((await publishRoutingPolicyAction(bindings(), OPERATOR, document)).ok).toBe(true);
    expect((await promoteRoutingPolicyAction(bindings(), OPERATOR, policyId, "1")).ok).toBe(true);

    const reader = createD1ConfigReader(env.DB, env.R2);
    const key = `active_routing_policy:routing/${policyId}`;
    const before = await reader.read(key);
    expect(before).not.toBe("miss");

    const row = await routingRow(policyId, "1");
    const tampered = { ...document, rules: [] };
    await env.R2.put(row!.content_pointer, JSON.stringify(tampered));

    expect(await reader.read(key)).toBe("miss");
  });
});
