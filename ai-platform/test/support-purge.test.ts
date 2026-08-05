import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import { assertControlAudit } from "./helpers/control-audit-assert";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
  }
}

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const FAKE_OPERATOR_ID = "operator-purge-test";
const FIXTURE_NOW = new Date("2026-08-02T12:00:00.000Z");
const FIXTURE_INSTALLATION_A = "inst-purge-a";
const FIXTURE_INSTALLATION_B = "inst-purge-b";
const FIXTURE_ORG = "org-purge-001";

type OperatorAuth = {
  resolve(_request: Request): { operatorId: string } | null;
};

type ControlBindings = { DB: D1Database; R2?: R2Bucket };

type PurgeHandlers = {
  handleInstallationPurge: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  dispatchControlRequest: (
    request: Request,
    bindings: ControlBindings,
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
};

function createFakeOperatorAuth(
  principal: { operatorId: string } | null = { operatorId: FAKE_OPERATOR_ID },
): OperatorAuth {
  return { resolve: () => principal };
}

async function loadPurgeHandlers(): Promise<PurgeHandlers> {
  return import(/* @vite-ignore */ "../src/control") as Promise<PurgeHandlers>;
}

function bindings(overrides: Partial<ControlBindings> = {}): ControlBindings {
  return { DB: env.DB, R2: env.R2, ...overrides };
}

function buildPurgeRequest(installationId: string): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/installations/${installationId}/purge`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${FAKE_OPERATOR_ID}`,
      },
      body: "{}",
    },
  );
}

async function applySql(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);
  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function seedInstallation(id: string): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (installation_id, org_id, display_name, status, region, enrolled_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      id,
      FIXTURE_ORG,
      `Clinic ${id}`,
      "active",
      "us-east-1",
      FIXTURE_NOW.toISOString(),
    )
    .run();
}

async function seedRequestWithEnvelope(
  requestId: string,
  installationId: string,
): Promise<void> {
  const createdAt = FIXTURE_NOW.toISOString();
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
      "cap.purge",
      "1.0.0",
      "prompt/purge@v1",
      `idem-${requestId}`,
      `trace-${requestId}`,
      "Completed",
      createdAt,
      createdAt,
      createdAt,
      envelopeKey,
    )
    .run();
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
      "purge-fixture",
      "success",
      100,
      10,
      5,
      0.001,
      `prov-${requestId}`,
    )
    .run();
  await env.R2.put(envelopeKey, JSON.stringify({ prompt: { system: "purge" } }));
}

async function clearTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM ai_attempt"),
    env.DB.prepare("DELETE FROM usage_event"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM usage_rollup"),
    env.DB.prepare("DELETE FROM platform_counter"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

beforeAll(async () => {
  await applySql(env.DB, migrationSql);
});

beforeEach(async () => {
  await clearTables();
});

describe("installation_purge_non_operator_denied", () => {
  it("rejects non-operator credentials with 401 unauthorized and no D1 writes", async () => {
    await seedInstallation(FIXTURE_INSTALLATION_A);
    await seedRequestWithEnvelope("req-purge-auth", FIXTURE_INSTALLATION_A);

    const { handleInstallationPurge } = await loadPurgeHandlers();
    const auditBefore = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit",
    ).first<{ count: number }>();
    const requestBefore = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM ai_request",
    ).first<{ count: number }>();

    const response = await handleInstallationPurge(
      buildPurgeRequest(FIXTURE_INSTALLATION_A),
      bindings(),
      createFakeOperatorAuth(null),
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });

    const auditAfter = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit",
    ).first<{ count: number }>();
    const requestAfter = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM ai_request",
    ).first<{ count: number }>();
    expect(auditAfter?.count ?? 0).toBe(auditBefore?.count ?? 0);
    expect(requestAfter?.count ?? 0).toBe(requestBefore?.count ?? 0);
  });
});

describe("installation_purge_invalid_route", () => {
  it("rejects when installation id cannot be parsed with 400 invalid_route", async () => {
    const { handleInstallationPurge } = await loadPurgeHandlers();
    const response = await handleInstallationPurge(
      new Request(`${GATEWAY_ORIGIN}/control/not-installations/x/purge`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${FAKE_OPERATOR_ID}`,
        },
        body: "{}",
      }),
      bindings(),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_route" });
  });
});

describe("installation_purge_missing_r2_binding", () => {
  it("returns 500 missing_r2_binding when R2 is absent", async () => {
    const { handleInstallationPurge } = await loadPurgeHandlers();
    const response = await handleInstallationPurge(
      buildPurgeRequest(FIXTURE_INSTALLATION_A),
      { DB: env.DB },
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ error: "missing_r2_binding" });
  });
});

describe("installation_purge_dispatch_wiring", () => {
  it('routes case "purge" through dispatchControlRequest to the handler', async () => {
    await seedInstallation(FIXTURE_INSTALLATION_A);
    await seedRequestWithEnvelope("req-purge-wire", FIXTURE_INSTALLATION_A);

    const { dispatchControlRequest } = await loadPurgeHandlers();
    const response = await dispatchControlRequest(
      buildPurgeRequest(FIXTURE_INSTALLATION_A),
      bindings(),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({});

    const remaining = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM ai_request WHERE installation_id = ?",
    )
      .bind(FIXTURE_INSTALLATION_A)
      .first<{ count: number }>();
    expect(remaining?.count ?? 0).toBe(0);

    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "purge_installation",
      target: FIXTURE_INSTALLATION_A,
    });
  });
});

describe("installation_purge_happy_path_target_only", () => {
  it("deletes target installation data only and audits operator_id", async () => {
    await seedInstallation(FIXTURE_INSTALLATION_A);
    await seedInstallation(FIXTURE_INSTALLATION_B);
    await seedRequestWithEnvelope("req-purge-a", FIXTURE_INSTALLATION_A);
    await seedRequestWithEnvelope("req-purge-b", FIXTURE_INSTALLATION_B);

    await env.DB.prepare(
      `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)
       VALUES (?, ?, ?, ?, ?)`,
    )
      .bind(
        "rollup-purge-a",
        JSON.stringify({
          period: "2026-08",
          installation_id: FIXTURE_INSTALLATION_A,
        }),
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
        JSON.stringify({
          period: "2026-08",
          installation_id: FIXTURE_INSTALLATION_B,
        }),
        1,
        20,
        0.02,
      )
      .run();

    const { handleInstallationPurge } = await loadPurgeHandlers();
    const response = await handleInstallationPurge(
      buildPurgeRequest(FIXTURE_INSTALLATION_A),
      bindings(),
      createFakeOperatorAuth(),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({});

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
    expect(rollupA?.c).toBe(0);
    expect(rollupB?.c).toBe(1);

    const audit = await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "purge_installation",
      target: FIXTURE_INSTALLATION_A,
    });
    expect(audit.operator_id).toBe(FAKE_OPERATOR_ID);
  });
});
