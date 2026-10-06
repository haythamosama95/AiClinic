import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  controlFetch,
  count,
  coverClinic,
  dispatchControlRequest,
  env,
  GATEWAY_ORIGIN,
  generateTestKeypair,
  getAudits,
  getEntitlement,
  OPERATOR_BEARER,
  OPERATOR_ID,
  operatorAuthFromEnv,
  queryAll,
  queryOne,
  r2Exists,
  readHttpResult,
  resetE2eState,
  seedSql,
  flushBackgroundWork,
  newClinic,
  newScenario,
  type HttpResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

let I0 = "3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d";
const ORG0 = "7a1b2c3d-4e5f-4a6b-9c8d-0e1f2a3b4c5d";
const K0 = "c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f";
const X0 = "n4bQgYhMfWWaL-qgxVrQ1O91g3Z2Q4u2Zz8v0m5p8xk";

const I2_PATH = "AA10C4D2-5E6F-4A7B-8C9D-0E1F2A3B4C5D";
let I2_STORED = I2_PATH.toLowerCase();
const ORG2 = "8B2C3D4E-5F6A-4B7C-8D9E-0F1A2B3C4D5E";
const KI2_STORED = "1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D";
const KI2_CATALOG = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d";
// Catalog XI2 is 30 bytes; enrollI2 uses generateTestKeypair() (32 bytes).

const K1 = "d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a";
const X1 = "Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV";
const K2 = "e6f7a8b9-0c1d-4e2f-9a3b-4c5d6e7f8a9b";
const X2 = "mZx1QwErTyUiOp9sDfGhJkLzXcVbNm2QeRtYuIoPaSd";

let I3 = "bb20d5e3-6f7a-4b8c-9d0e-1f2a3b4c5d6e";
const ORG3 = "9c3d4e5f-6a7b-4c8d-9e0f-1a2b3c4d5e6f";
const KI3 = "2b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e";
const XI3 = "PqRsTuVwXyZ0123456789aBcDeFgHiJkLmNoPqRsTuV";

const IUNKNOWN = "00000000-0000-4000-8000-000000000099";
const KUNKNOWN = "f7a8b9c0-1d2e-4f3a-ab4c-5d6e7f8a9b0c";

const R1 = "5e6f7a8b-9c0d-4e1f-8a2b-3c4d5e6f7a8b";
const R2_REQ = "6f7a8b9c-0d1e-4f2a-9b3c-4d5e6f7a8b9c";
const R1_ENVELOPE = `request/${R1}/envelope`;
const R2_ENVELOPE = `request/${R2_REQ}/envelope`;

const CANONICAL_ENROLL_BODY = {
  org_id: ORG0,
  display_name: "Verify Clinic",
  region: "eu-central",
  plan: "standard",
  public_key: X0,
  algorithm: "EdDSA",
  kid: K0,
} as const;

const I2_ENROLL_BODY = {
  org_id: ORG2,
  display_name: "Boundary Clinic",
  region: "eu-central",
  plan: "starter",
  algorithm: "EdDSA",
  kid: KI2_STORED,
} as const;

const I3_ENROLL_BODY = {
  org_id: ORG3,
  display_name: "Hasty Clinic",
  region: "eu-central",
  plan: "enterprise",
  public_key: XI3,
  algorithm: "EdDSA",
  kid: KI3,
} as const;

const ROTATE_K1_BODY = {
  kid: K1,
  public_key: X1,
  algorithm: "EdDSA",
} as const;

const ROTATE_K2_BODY = {
  kid: K2,
  public_key: X2,
  algorithm: "EdDSA",
} as const;

type LifecycleSnapshot = {
  installations: Record<string, unknown>[];
  bindings: Record<string, unknown>[];
  audits: Record<string, unknown>[];
};

type ControlAuditRow = {
  audit_id: string;
  operator_id: string;
  action: string;
  target: string;
  before_pointer: string | null;
  after_pointer: string | null;
  recorded_at: string;
};

function actionPath(id: string, action: string): string {
  return `/control/installations/${id}/${action}`;
}

function assertControlError(
  result: HttpResult,
  status: number,
  error: string,
): void {
  expect(result.status).toBe(status);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({ error });
}

function assertOkEmpty(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({});
}

async function snapshotLifecycle(): Promise<LifecycleSnapshot> {
  return {
    installations: await queryAll(
      "SELECT * FROM installation ORDER BY installation_id",
    ),
    bindings: await queryAll("SELECT * FROM tenant_binding ORDER BY installation_id"),
    audits: await queryAll(
      "SELECT * FROM control_audit ORDER BY recorded_at, action, target, audit_id",
    ),
  };
}

async function assertLifecycleUnchanged(
  before: LifecycleSnapshot,
): Promise<void> {
  expect(await snapshotLifecycle()).toEqual(before);
}

async function assertNoLifecycleWrites(): Promise<void> {
  expect(await count("installation")).toBe(0);
  expect(await count("tenant_binding")).toBe(0);
  expect(await count("control_audit")).toBe(0);
}

async function expectControlOk(
  path: string,
  body: unknown = {},
): Promise<HttpResult> {
  const result = await controlFetch(path, { body });
  expect(result.status).toBe(200);
  return result;
}

async function enrollI0(): Promise<void> {
  const scenario = await newScenario();
  await newClinic(scenario);
  I0 = scenario.installationId;
  await coverClinic(scenario);
}

async function enrollI2(): Promise<void> {
  const scenario = await newScenario();
  await newClinic(scenario);
  I2_STORED = scenario.installationId;
  await coverClinic(scenario);
}

async function enrollI3(): Promise<void> {
  const scenario = await newScenario();
  await newClinic(scenario);
  I3 = scenario.installationId;
}

async function rotateI0K1(): Promise<void> {
  const result = await controlFetch(actionPath(I0, "rotate"), ROTATE_K1_BODY);
  expect(result.status).toBe(404);
}

async function revokeI0K0(): Promise<void> {
  const result = await controlFetch(actionPath(I0, "revoke-key"), { kid: K0 });
  expect(result.status).toBe(404);
}

async function suspendI2(): Promise<void> {
  await expectControlOk(actionPath(I2_STORED, "suspend"), {});
  await flushBackgroundWork();
}

async function rotateI2K2(): Promise<void> {
  const result = await controlFetch(actionPath(I2_STORED, "rotate"), ROTATE_K2_BODY);
  expect(result.status).toBe(404);
}

async function deleteInstallation(id: string): Promise<void> {
  const result = await expectControlOk(actionPath(id, "delete"), {});
  expect(result.json).toEqual({});
}

async function prepareDualKeyI0(): Promise<void> {
  await enrollI0();
}

async function prepareDeletedI0(): Promise<void> {
  await enrollI0();
  await deleteInstallation(I0);
}

async function prepareSuspendedI2DualKey(): Promise<void> {
  await enrollI2();
  await suspendI2();
}

async function installationStatus(id: string): Promise<string | null> {
  const row = await queryOne<{ status: string }>(
    "SELECT status FROM installation WHERE installation_id = ?",
    [id],
  );
  return row?.status ?? null;
}

async function installationSuspended(id: string): Promise<boolean> {
  const row = await queryOne<{ suspended: number }>(
    "SELECT suspended FROM coverage_mirror WHERE installation_id = ?",
    [id],
  );
  return row?.suspended === 1;
}

async function seedI0PurgeFootprint(): Promise<void> {
  const now = new Date().toISOString();

  // HARNESS-GAP: Stages 8–13 not on this branch; request/R2 footprint seeded
  // to observe purge deletes. Catalog [SEED] only labels rollup/counter/grant/
  // grace; later-stage by-products are inserted directly so R2 + journal
  // deletes can be asserted.
  await seedSql([
    {
      sql: `INSERT INTO ai_request (
              request_id, request_reference, installation_id, actor_id, branch_id,
              capability_id, capability_version, prompt_artifact_hash, idempotency_key,
              trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
              payload_pointer, conversation_id, turn_ordinal
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, NULL, NULL)`,
      params: [
        R1,
        "R1T2-ABCD",
        I0,
        "actor-i0",
        "branch-i0",
        CAPABILITY_ID,
        CAPABILITY_VERSION,
        "prompt/visit_summary@1",
        `idem-${R1}`,
        `trace-${R1}`,
        "Completed",
        now,
        now,
        now,
        R1_ENVELOPE,
      ],
    },
    {
      sql: `INSERT INTO ai_request (
              request_id, request_reference, installation_id, actor_id, branch_id,
              capability_id, capability_version, prompt_artifact_hash, idempotency_key,
              trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
              payload_pointer, conversation_id, turn_ordinal
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL)`,
      params: [
        R2_REQ,
        "R2T3-EFGH",
        I0,
        "actor-i0",
        "branch-i0",
        CAPABILITY_ID,
        CAPABILITY_VERSION,
        "prompt/visit_summary@1",
        `idem-${R2_REQ}`,
        `trace-${R2_REQ}`,
        "Completed",
        now,
        now,
        now,
      ],
    },
    {
      sql: `INSERT INTO ai_attempt (
              attempt_id, request_id, attempt_no, provider, model, outcome,
              latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
            ) VALUES (?, ?, 1, ?, ?, ?, 100, 10, 5, 0.001, ?, NULL)`,
      params: [
        "11111111-1111-4111-8111-111111111111",
        R1,
        "fake",
        "fake-v1",
        "success",
        `prov-${R1}`,
      ],
    },
    {
      sql: `INSERT INTO ai_attempt (
              attempt_id, request_id, attempt_no, provider, model, outcome,
              latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
            ) VALUES (?, ?, 1, ?, ?, ?, 80, 8, 4, 0.001, ?, NULL)`,
      params: [
        "22222222-2222-4222-8222-222222222222",
        R2_REQ,
        "fake",
        "fake-v1",
        "success",
        `prov-${R2_REQ}`,
      ],
    },
    {
      sql: `INSERT INTO usage_event (
              usage_event_id, installation_id, period, request_id,
              quota_weight, tokens, cost, recorded_at
            ) VALUES (?, ?, ?, ?, 1, 15, 0.001, ?)`,
      params: [
        "33333333-3333-4333-8333-333333333333",
        I0,
        "2026-09",
        R1,
        now,
      ],
    },
    {
      sql: `INSERT INTO usage_event (
              usage_event_id, installation_id, period, request_id,
              quota_weight, tokens, cost, recorded_at
            ) VALUES (?, ?, ?, ?, 1, 12, 0.001, ?)`,
      params: [
        "44444444-4444-4444-8444-444444444444",
        I0,
        "2026-09",
        R2_REQ,
        now,
      ],
    },
    {
      sql: `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)
            VALUES (?, ?, 2, 27, 0.002)`,
      params: [
        "55555555-5555-4555-8555-555555555555",
        JSON.stringify({ installation_id: I0, period: "2026-09" }),
      ],
    },
    {
      sql: `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
            VALUES (?, ?, ?, 1)`,
      params: [
        "66666666-6666-4666-8666-666666666666",
        JSON.stringify({ installation_id: I0, kind: "guard_rejection" }),
        "2026-09-01T00:00:00.000Z",
      ],
    },
    {
      sql: `INSERT INTO capability_grant (
              grant_id, scope, capability_id, capability_version,
              granted_at, revoked_at, changed_at, changed_by
            ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
      params: [
        "77777777-7777-4777-8777-777777777777",
        `installation:${I0}`,
        CAPABILITY_ID,
        CAPABILITY_VERSION,
        now,
        now,
        OPERATOR_ID,
      ],
    },
    {
      sql: `INSERT INTO fallback_admission (
              installation_id, idempotency_key, term_id, request_id, weight, admitted_at, state
            ) VALUES (?, ?, ?, ?, ?, ?, 'pending')`,
      params: [
        I0,
        `fallback-idem-${I0}`,
        "term-footprint-i0",
        "88888888-8888-4888-8888-888888888888",
        1,
        now,
      ],
    },
  ]);

  await env.R2.put(R1_ENVELOPE, new TextEncoder().encode('{"prompt":"r1"}'));
  await env.R2.put(R2_ENVELOPE, new TextEncoder().encode('{"prompt":"r2"}'));
}

describe("Stage 03 — revoke/delete/purge (S03-061…S03-083)", () => {










  it("S03-071 — Delete of an unknown installation returns installation_not_found", async () => {
    const result = await controlFetch(actionPath(IUNKNOWN, "delete"), {
      body: {},
    });

    assertControlError(result, 404, "installation_not_found");
    await assertNoLifecycleWrites();
  });

  it("S03-072 — Delete happy path marks an active installation deleted", async () => {
    await prepareDualKeyI0();
    expect(await installationStatus(I0)).toBe("active");
    const keyCountBefore = await count("tenant_binding", "installation_id = ?", [
      I0,
    ]);
    const result = await controlFetch(actionPath(I0, "delete"), { body: {} });

    assertOkEmpty(result);
    expect(await installationStatus(I0)).toBe("deleted");
    expect(
      await count("tenant_binding", "installation_id = ?", [I0]),
    ).toBe(keyCountBefore);

  });

  it("S03-073 — Delete of an already-deleted installation is idempotent", async () => {
    await prepareDeletedI0();

    const result = await controlFetch(actionPath(I0, "delete"), { body: {} });

    assertOkEmpty(result);
    expect(await installationStatus(I0)).toBe("deleted");
  });

  it("S03-076 — Suspend on a deleted installation returns bad_request", async () => {
    await prepareDeletedI0();

    const result = await controlFetch(actionPath(I0, "suspend"), { body: {} });

    assertControlError(result, 400, "coverage_unknown");
  });

  it("S03-077 — Resume on a deleted installation returns bad_request", async () => {
    await prepareDeletedI0();

    const result = await controlFetch(actionPath(I0, "resume"), { body: {} });

    assertControlError(result, 400, "coverage_unknown");
  });

  it("S03-078 — Delete succeeds directly from suspended", async () => {
    await prepareSuspendedI2DualKey();
    const revoke = await controlFetch(actionPath(I2_PATH, "revoke-key"), {
      body: { kid: KI2_STORED },
    });
    expect(revoke.status).toBe(404);
    const keyCountBefore = await count("tenant_binding", "installation_id = ?", [
      I2_STORED,
    ]);
    const result = await controlFetch(actionPath(I2_STORED, "delete"), {
      body: {},
    });

    assertOkEmpty(result);
    expect(await installationStatus(I2_STORED)).toBe("deleted");
    expect(
      await count("tenant_binding", "installation_id = ?", [I2_STORED]),
    ).toBe(keyCountBefore);

  });





});
