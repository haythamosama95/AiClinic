import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  controlFetch,
  count,
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
  type HttpResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const I0 = "3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d";
const ORG0 = "7a1b2c3d-4e5f-4a6b-9c8d-0e1f2a3b4c5d";
const K0 = "c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f";
const X0 = "n4bQgYhMfWWaL-qgxVrQ1O91g3Z2Q4u2Zz8v0m5p8xk";

const I2_PATH = "AA10C4D2-5E6F-4A7B-8C9D-0E1F2A3B4C5D";
const I2_STORED = I2_PATH.toLowerCase();
const ORG2 = "8B2C3D4E-5F6A-4B7C-8D9E-0F1A2B3C4D5E";
const KI2_STORED = "1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D";
const KI2_CATALOG = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d";
// Catalog XI2 is 30 bytes; enrollI2 uses generateTestKeypair() (32 bytes).

const K1 = "d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a";
const X1 = "Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV";
const K2 = "e6f7a8b9-0c1d-4e2f-9a3b-4c5d6e7f8a9b";
const X2 = "mZx1QwErTyUiOp9sDfGhJkLzXcVbNm2QeRtYuIoPaSd";

const I3 = "bb20d5e3-6f7a-4b8c-9d0e-1f2a3b4c5d6e";
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

const ISO_8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const CLOCK_SKEW_MS = 15_000;

type LifecycleSnapshot = {
  installations: Record<string, unknown>[];
  keys: Record<string, unknown>[];
  entitlements: Record<string, unknown>[];
  audits: Record<string, unknown>[];
};

type InstallationKeyRow = {
  key_id: string;
  installation_id: string;
  revoked_at: string | null;
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

function assertIsoApproxNow(value: unknown): string {
  expect(typeof value).toBe("string");
  const iso = String(value);
  expect(iso).toMatch(ISO_8601);
  const parsed = Date.parse(iso);
  expect(Number.isNaN(parsed)).toBe(false);
  expect(Math.abs(Date.now() - parsed)).toBeLessThan(CLOCK_SKEW_MS);
  return iso;
}

async function snapshotLifecycle(): Promise<LifecycleSnapshot> {
  return {
    installations: await queryAll(
      "SELECT * FROM installation ORDER BY installation_id",
    ),
    keys: await queryAll("SELECT * FROM installation_key ORDER BY key_id"),
    entitlements: await queryAll(
      "SELECT * FROM entitlement ORDER BY entitlement_id",
    ),
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
  expect(await count("installation_key")).toBe(0);
  expect(await count("entitlement")).toBe(0);
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
  const result = await expectControlOk(
    actionPath(I0, "enroll"),
    CANONICAL_ENROLL_BODY,
  );
  expect(result.json).toEqual({ platform_base_url: GATEWAY_ORIGIN });
}

async function enrollI2(): Promise<void> {
  const { publicKeyB64 } = await generateTestKeypair();
  await expectControlOk(actionPath(I2_PATH, "enroll"), {
    ...I2_ENROLL_BODY,
    public_key: publicKeyB64,
  });
}

async function enrollI3(): Promise<void> {
  await expectControlOk(actionPath(I3, "enroll"), I3_ENROLL_BODY);
}

async function rotateI0K1(): Promise<void> {
  const result = await expectControlOk(actionPath(I0, "rotate"), ROTATE_K1_BODY);
  expect(result.json).toEqual({});
}

async function revokeI0K0(): Promise<void> {
  const result = await expectControlOk(actionPath(I0, "revoke-key"), {
    kid: K0,
  });
  expect(result.json).toEqual({});
}

async function suspendI2(): Promise<void> {
  await expectControlOk(actionPath(I2_PATH, "suspend"), {});
}

async function rotateI2K2(): Promise<void> {
  await expectControlOk(actionPath(I2_PATH, "rotate"), ROTATE_K2_BODY);
}

async function deleteInstallation(id: string): Promise<void> {
  const result = await expectControlOk(actionPath(id, "delete"), {});
  expect(result.json).toEqual({});
}

async function prepareDualKeyI0(): Promise<void> {
  await enrollI0();
  await rotateI0K1();
}

async function prepareDeletedI0(): Promise<void> {
  await prepareDualKeyI0();
  await revokeI0K0();
  await deleteInstallation(I0);
}

async function prepareSuspendedI2DualKey(): Promise<void> {
  await enrollI2();
  await suspendI2();
  await rotateI2K2();
}

async function keyRow(keyId: string): Promise<InstallationKeyRow | null> {
  return queryOne<InstallationKeyRow>(
    `SELECT key_id, installation_id, revoked_at
     FROM installation_key WHERE key_id = ?`,
    [keyId],
  );
}

async function installationStatus(id: string): Promise<string | null> {
  const row = await queryOne<{ status: string }>(
    "SELECT status FROM installation WHERE installation_id = ?",
    [id],
  );
  return row?.status ?? null;
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
      sql: `INSERT INTO grace_admission_queue (
              grace_request_id, installation_id, idempotency_key, jti, request_reference,
              entitlement_json, usage_tokens, usage_cost, partial, queued_at,
              reconcile_attempts, reconcile_first_seen_at_ms, status
            ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, 0, NULL, 'pending')`,
      params: [
        "88888888-8888-4888-8888-888888888888",
        I0,
        `grace-idem-${I0}`,
        "jti-grace-i0",
        "GRCE-0001",
        "{}",
        now,
      ],
    },
  ]);

  await env.R2.put(R1_ENVELOPE, new TextEncoder().encode('{"prompt":"r1"}'));
  await env.R2.put(R2_ENVELOPE, new TextEncoder().encode('{"prompt":"r2"}'));
}

describe("Stage 03 — revoke/delete/purge (S03-061…S03-083)", () => {
  it("S03-061 — Revoke-key rejects a non-object JSON body", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "revoke-key"), {
      body: [K0],
    });

    assertControlError(result, 400, "invalid_payload");
    await assertLifecycleUnchanged(before);
  });

  it("S03-062 — Revoke-key rejects a missing or empty kid", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "revoke-key"), {
      body: {},
    });

    assertControlError(result, 400, "invalid_payload");
    await assertLifecycleUnchanged(before);
  });

  it("S03-063 — Revoke-key rejects a non-UUID kid", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "revoke-key"), {
      body: { kid: "old-key" },
    });

    assertControlError(result, 400, "invalid_payload");
    await assertLifecycleUnchanged(before);
  });

  it("S03-064 — Revoke-key on an unknown installation returns installation_not_found", async () => {
    const result = await controlFetch(actionPath(IUNKNOWN, "revoke-key"), {
      body: { kid: K0 },
    });

    assertControlError(result, 404, "installation_not_found");
    await assertNoLifecycleWrites();
  });

  it("S03-065 — Revoke-key of a well-formed but unknown kid returns key_not_found", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "revoke-key"), {
      body: { kid: KUNKNOWN },
    });

    assertControlError(result, 404, "key_not_found");
    await assertLifecycleUnchanged(before);
  });

  it("S03-066 — Revoke-key of a kid owned by a different installation returns key_not_found", async () => {
    await enrollI2();
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "revoke-key"), {
      body: { kid: KI2_CATALOG },
    });

    assertControlError(result, 404, "key_not_found");
    await assertLifecycleUnchanged(before);

    const ki2 = await keyRow(KI2_CATALOG);
    expect(ki2).not.toBeNull();
    expect(ki2?.installation_id).toBe(I2_STORED);
    expect(ki2?.revoked_at).toBeNull();
  });

  it("S03-067 — Revoke-key happy path retires one key while another stays active", async () => {
    await prepareDualKeyI0();
    const beforeInstallations = await queryAll(
      "SELECT * FROM installation ORDER BY installation_id",
    );
    const beforeEntitlements = await queryAll(
      "SELECT * FROM entitlement ORDER BY entitlement_id",
    );
    const auditCountBefore = await count("control_audit");

    const result = await controlFetch(actionPath(I0, "revoke-key"), {
      body: { kid: K0 },
    });

    assertOkEmpty(result);

    const k0 = await keyRow(K0);
    expect(k0).not.toBeNull();
    assertIsoApproxNow(k0?.revoked_at);

    const k1 = await keyRow(K1);
    expect(k1).not.toBeNull();
    expect(k1?.revoked_at).toBeNull();
    expect(k1?.installation_id).toBe(I0);

    const revokeAudits = await getAudits("revoke-key", I0);
    expect(revokeAudits).toHaveLength(1);
    const audit = revokeAudits[0] as ControlAuditRow;
    expect(audit.operator_id).toBe(OPERATOR_ID);
    expect(audit.before_pointer).toBeNull();
    expect(audit.after_pointer).toBe(K0);
    assertIsoApproxNow(audit.recorded_at);

    expect(await count("control_audit")).toBe(auditCountBefore + 1);
    expect(
      await queryAll("SELECT * FROM installation ORDER BY installation_id"),
    ).toEqual(beforeInstallations);
    expect(
      await queryAll("SELECT * FROM entitlement ORDER BY entitlement_id"),
    ).toEqual(beforeEntitlements);
  });

  it("S03-068 — Revoke-key of an already-revoked key returns key_already_revoked", async () => {
    await prepareDualKeyI0();
    await revokeI0K0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "revoke-key"), {
      body: { kid: K0 },
    });

    assertControlError(result, 409, "key_already_revoked");
    await assertLifecycleUnchanged(before);
  });

  it("S03-069 — Revoke-key of the sole remaining active key returns cannot_revoke_last_active_key", async () => {
    await prepareDualKeyI0();
    await revokeI0K0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "revoke-key"), {
      body: { kid: K1 },
    });

    assertControlError(result, 409, "cannot_revoke_last_active_key");
    await assertLifecycleUnchanged(before);

    const k1 = await keyRow(K1);
    expect(k1?.revoked_at).toBeNull();
  });

  it("S03-070 — Revoke-key succeeds on a suspended installation", async () => {
    await prepareSuspendedI2DualKey();
    expect(await installationStatus(I2_STORED)).toBe("suspended");

    // Catalog Action: lowercase KI2 against an uppercase-enrolled kid.
    // Enroll/rotate persist canonical lowercase, so the revoke matches.
    const result = await controlFetch(actionPath(I2_PATH, "revoke-key"), {
      body: { kid: KI2_CATALOG },
    });

    assertOkEmpty(result);

    const ki2 = await keyRow(KI2_CATALOG);
    expect(ki2).not.toBeNull();
    assertIsoApproxNow(ki2?.revoked_at);

    const k2 = await keyRow(K2);
    expect(k2).not.toBeNull();
    expect(k2?.revoked_at).toBeNull();
    expect(await installationStatus(I2_STORED)).toBe("suspended");

    const revokeAudits = await queryAll<ControlAuditRow>(
      `SELECT audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at
       FROM control_audit WHERE action = 'revoke-key' AND target = ?`,
      [I2_STORED],
    );
    expect(revokeAudits).toHaveLength(1);
    expect(revokeAudits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(revokeAudits[0]?.before_pointer).toBeNull();
    expect(revokeAudits[0]?.after_pointer).toBe(KI2_CATALOG);
  });

  it("S03-071 — Delete of an unknown installation returns installation_not_found", async () => {
    const result = await controlFetch(actionPath(IUNKNOWN, "delete"), {
      body: {},
    });

    assertControlError(result, 404, "installation_not_found");
    await assertNoLifecycleWrites();
  });

  it("S03-072 — Delete happy path marks an active installation deleted", async () => {
    await prepareDualKeyI0();
    await revokeI0K0();
    expect(await installationStatus(I0)).toBe("active");
    const keyCountBefore = await count("installation_key", "installation_id = ?", [
      I0,
    ]);
    const entitlementBefore = await getEntitlement(I0);
    expect(entitlementBefore).not.toBeNull();

    const result = await controlFetch(actionPath(I0, "delete"), { body: {} });

    assertOkEmpty(result);
    expect(await installationStatus(I0)).toBe("deleted");
    expect(
      await count("installation_key", "installation_id = ?", [I0]),
    ).toBe(keyCountBefore);
    expect(await getEntitlement(I0)).toEqual(entitlementBefore);

    const deleteAudits = await getAudits("delete", I0);
    expect(deleteAudits).toHaveLength(1);
    expect(deleteAudits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(deleteAudits[0]?.before_pointer).toBeNull();
    expect(deleteAudits[0]?.after_pointer).toBeNull();
  });

  it("S03-073 — Delete of an already-deleted installation returns illegal_lifecycle_transition", async () => {
    await prepareDeletedI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "delete"), { body: {} });

    assertControlError(result, 409, "illegal_lifecycle_transition");
    await assertLifecycleUnchanged(before);
  });

  it("S03-074 — Rotate on a deleted installation returns illegal_lifecycle_transition", async () => {
    await prepareDeletedI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "rotate"), {
      body: {
        kid: "7d8e9f0a-1b2c-4d3e-8f4a-5b6c7d8e9f0a",
        public_key: X1,
        algorithm: "EdDSA",
      },
    });

    assertControlError(result, 409, "illegal_lifecycle_transition");
    await assertLifecycleUnchanged(before);
  });

  it("S03-075 — Revoke-key on a deleted installation returns illegal_lifecycle_transition", async () => {
    await prepareDeletedI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "revoke-key"), {
      body: { kid: K1 },
    });

    assertControlError(result, 409, "illegal_lifecycle_transition");
    await assertLifecycleUnchanged(before);
  });

  it("S03-076 — Suspend on a deleted installation returns illegal_lifecycle_transition", async () => {
    await prepareDeletedI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "suspend"), { body: {} });

    assertControlError(result, 409, "illegal_lifecycle_transition");
    await assertLifecycleUnchanged(before);
  });

  it("S03-077 — Resume on a deleted installation returns illegal_lifecycle_transition", async () => {
    await prepareDeletedI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I0, "resume"), { body: {} });

    assertControlError(result, 409, "illegal_lifecycle_transition");
    await assertLifecycleUnchanged(before);
  });

  it("S03-078 — Delete succeeds directly from suspended", async () => {
    await prepareSuspendedI2DualKey();
    const revoke = await controlFetch(actionPath(I2_PATH, "revoke-key"), {
      body: { kid: KI2_STORED },
    });
    expect(revoke.status).toBe(200);
    expect(await installationStatus(I2_STORED)).toBe("suspended");
    const keyCountBefore = await count("installation_key", "installation_id = ?", [
      I2_STORED,
    ]);
    const entitlementBefore = await getEntitlement(I2_STORED);

    const result = await controlFetch(actionPath(I2_PATH, "delete"), {
      body: {},
    });

    assertOkEmpty(result);
    expect(await installationStatus(I2_STORED)).toBe("deleted");
    expect(
      await count("installation_key", "installation_id = ?", [I2_STORED]),
    ).toBe(keyCountBefore);
    expect(await getEntitlement(I2_STORED)).toEqual(entitlementBefore);

    const deleteAudits = await getAudits("delete", I2_STORED);
    expect(deleteAudits).toHaveLength(1);
    expect(deleteAudits[0]?.operator_id).toBe(OPERATOR_ID);
  });

  it("S03-079 — Purge happy path removes the full installation footprint from D1 and R2", async () => {
    await prepareDeletedI0();
    await enrollI2();
    await seedI0PurgeFootprint();

    expect(await r2Exists(R1_ENVELOPE)).toBe(true);
    expect(await r2Exists(R2_ENVELOPE)).toBe(true);
    const historyBefore = await queryAll<ControlAuditRow>(
      `SELECT audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at
       FROM control_audit WHERE target = ? AND action != 'purge_installation'
       ORDER BY recorded_at, action, audit_id`,
      [I0],
    );
    expect(historyBefore.length).toBeGreaterThan(0);
    const i2Before = await queryOne("SELECT * FROM installation WHERE installation_id = ?", [
      I2_STORED,
    ]);
    expect(i2Before).not.toBeNull();

    const i2KeysBefore = await queryAll(
      "SELECT * FROM installation_key WHERE installation_id = ? ORDER BY key_id",
      [I2_STORED],
    );
    const i2EntitlementBefore = await queryOne(
      "SELECT * FROM entitlement WHERE installation_id = ?",
      [I2_STORED],
    );
    expect(i2KeysBefore.length).toBeGreaterThan(0);
    expect(i2EntitlementBefore).not.toBeNull();

    const footprintBefore = {
      ai_attempt: await count("ai_attempt", "request_id IN (?, ?)", [R1, R2_REQ]),
      usage_event: await count("usage_event", "installation_id = ?", [I0]),
      ai_request: await count("ai_request", "installation_id = ?", [I0]),
      usage_rollup: await count(
        "usage_rollup",
        "json_extract(dimensions, '$.installation_id') = ?",
        [I0],
      ),
      platform_counter: await count(
        "platform_counter",
        "json_extract(dimension_set, '$.installation_id') = ?",
        [I0],
      ),
      capability_grant: await count("capability_grant", "scope = ?", [
        `installation:${I0}`,
      ]),
      installation_key: await count("installation_key", "installation_id = ?", [
        I0,
      ]),
      entitlement: await count("entitlement", "installation_id = ?", [I0]),
      grace_admission_queue: await count(
        "grace_admission_queue",
        "installation_id = ?",
        [I0],
      ),
      installation: await count("installation", "installation_id = ?", [I0]),
    };
    expect(footprintBefore.ai_attempt).toBeGreaterThan(0);
    expect(footprintBefore.usage_event).toBeGreaterThan(0);
    expect(footprintBefore.ai_request).toBeGreaterThan(0);
    expect(footprintBefore.usage_rollup).toBeGreaterThan(0);
    expect(footprintBefore.platform_counter).toBeGreaterThan(0);
    expect(footprintBefore.capability_grant).toBeGreaterThan(0);
    expect(footprintBefore.installation_key).toBeGreaterThan(0);
    expect(footprintBefore.entitlement).toBeGreaterThan(0);
    expect(footprintBefore.grace_admission_queue).toBeGreaterThan(0);
    expect(footprintBefore.installation).toBeGreaterThan(0);

    const result = await controlFetch(actionPath(I0, "purge"), { body: {} });

    assertOkEmpty(result);

    const purgeAudits = await getAudits("purge_installation", I0);
    expect(purgeAudits).toHaveLength(2);
    for (const row of purgeAudits) {
      expect(row.operator_id).toBe(OPERATOR_ID);
      expect(row.target).toBe(I0);
      expect(row.before_pointer).toBeNull();
      expect(row.after_pointer).toBeNull();
    }

    expect(await r2Exists(R1_ENVELOPE)).toBe(false);
    expect(await r2Exists(R2_ENVELOPE)).toBe(false);

    expect(await count("ai_attempt", "request_id IN (?, ?)", [R1, R2_REQ])).toBe(
      0,
    );
    expect(await count("usage_event", "installation_id = ?", [I0])).toBe(0);
    expect(await count("ai_request", "installation_id = ?", [I0])).toBe(0);
    expect(
      await count(
        "usage_rollup",
        "json_extract(dimensions, '$.installation_id') = ?",
        [I0],
      ),
    ).toBe(0);
    expect(
      await count(
        "platform_counter",
        "json_extract(dimension_set, '$.installation_id') = ?",
        [I0],
      ),
    ).toBe(0);
    expect(
      await count("capability_grant", "scope = ?", [`installation:${I0}`]),
    ).toBe(0);
    expect(await count("installation_key", "installation_id = ?", [I0])).toBe(0);
    expect(await count("entitlement", "installation_id = ?", [I0])).toBe(0);
    expect(
      await count("grace_admission_queue", "installation_id = ?", [I0]),
    ).toBe(0);
    expect(await count("installation", "installation_id = ?", [I0])).toBe(0);

    const historyAfter = await queryAll<ControlAuditRow>(
      `SELECT audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at
       FROM control_audit WHERE target = ? AND action != 'purge_installation'
       ORDER BY recorded_at, action, audit_id`,
      [I0],
    );
    expect(historyAfter).toEqual(historyBefore);
    expect(await count("control_audit", "action = ? AND target = ?", ["enroll", I0])).toBe(
      1,
    );
    expect(await count("control_audit", "action = ? AND target = ?", ["delete", I0])).toBe(
      1,
    );

    expect(
      await queryOne("SELECT * FROM installation WHERE installation_id = ?", [
        I2_STORED,
      ]),
    ).toEqual(i2Before);
    expect(
      await queryAll(
        "SELECT * FROM installation_key WHERE installation_id = ? ORDER BY key_id",
        [I2_STORED],
      ),
    ).toEqual(i2KeysBefore);
    expect(
      await queryOne("SELECT * FROM entitlement WHERE installation_id = ?", [
        I2_STORED,
      ]),
    ).toEqual(i2EntitlementBefore);
  });

  it("S03-080 — Purge rejects a non-deleted installation", async () => {
    await enrollI3();
    const before = await snapshotLifecycle();

    const result = await controlFetch(actionPath(I3, "purge"), { body: {} });

    assertControlError(result, 409, "illegal_lifecycle_transition");
    await assertLifecycleUnchanged(before);
    expect(
      await count("control_audit", "action = ?", ["purge_installation"]),
    ).toBe(0);
    expect(await count("installation", "installation_id = ?", [I3])).toBe(1);
    expect(await count("installation_key", "installation_id = ?", [I3])).toBe(1);
    expect(await count("entitlement", "installation_id = ?", [I3])).toBe(1);
  });

  it("S03-081 — Purge of a never-enrolled installation id returns 200 with audit-only writes", async () => {
    const sentinelKey = "unrelated/sentinel";
    await env.R2.put(sentinelKey, new TextEncoder().encode("keep"));
    const dataBefore = {
      installation: await count("installation"),
      installation_key: await count("installation_key"),
      entitlement: await count("entitlement"),
      ai_request: await count("ai_request"),
      ai_attempt: await count("ai_attempt"),
      usage_event: await count("usage_event"),
      usage_rollup: await count("usage_rollup"),
      platform_counter: await count("platform_counter"),
      capability_grant: await count("capability_grant"),
      grace_admission_queue: await count("grace_admission_queue"),
    };

    const result = await controlFetch(actionPath(IUNKNOWN, "purge"), {
      body: {},
    });

    assertOkEmpty(result);
    expect(await count("installation")).toBe(dataBefore.installation);
    expect(await count("installation_key")).toBe(dataBefore.installation_key);
    expect(await count("entitlement")).toBe(dataBefore.entitlement);
    expect(await count("ai_request")).toBe(dataBefore.ai_request);
    expect(await count("ai_attempt")).toBe(dataBefore.ai_attempt);
    expect(await count("usage_event")).toBe(dataBefore.usage_event);
    expect(await count("usage_rollup")).toBe(dataBefore.usage_rollup);
    expect(await count("platform_counter")).toBe(dataBefore.platform_counter);
    expect(await count("capability_grant")).toBe(dataBefore.capability_grant);
    expect(await count("grace_admission_queue")).toBe(
      dataBefore.grace_admission_queue,
    );
    expect(await r2Exists(sentinelKey)).toBe(true);

    const purges = await getAudits("purge_installation", IUNKNOWN);
    expect(purges).toHaveLength(2);
    for (const row of purges) {
      expect(row.operator_id).toBe(OPERATOR_ID);
      expect(row.target).toBe(IUNKNOWN);
    }
    expect(await count("control_audit")).toBe(2);
  });

  it("S03-082 — Purge accepts a non-UUID path id without validation", async () => {
    const sentinelKey = "unrelated/sentinel-non-uuid";
    await env.R2.put(sentinelKey, new TextEncoder().encode("keep"));

    const result = await controlFetch(
      "/control/installations/not-a-uuid/purge",
      { body: {} },
    );

    assertOkEmpty(result);
    expect(await count("installation")).toBe(0);
    expect(await count("installation_key")).toBe(0);
    expect(await count("entitlement")).toBe(0);
    expect(await count("ai_request")).toBe(0);
    expect(await r2Exists(sentinelKey)).toBe(true);

    const purges = await getAudits("purge_installation", "not-a-uuid");
    expect(purges).toHaveLength(2);
    for (const row of purges) {
      expect(row.operator_id).toBe(OPERATOR_ID);
      expect(row.target).toBe("not-a-uuid");
    }
  });

  it("S03-083 — Purge without an R2 binding returns missing_r2_binding", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    // Register 5 #2: missing R2 is not expressible via SELF.fetch / dispatchControl
    // (controlBindingsFromEnv fills R2 from pool env). Call dispatchControlRequest
    // with { DB } only so the handler sees a missing R2 binding.
    const response = await dispatchControlRequest(
      new Request(`${GATEWAY_ORIGIN}/control/installations/${I0}/purge`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${OPERATOR_BEARER}`,
        },
        body: "{}",
      }),
      { DB: env.DB },
      operatorAuthFromEnv(),
    );
    const result = await readHttpResult(response);

    assertControlError(result, 500, "missing_r2_binding");
    await assertLifecycleUnchanged(before);
    expect(
      await count("control_audit", "action = ?", ["purge_installation"]),
    ).toBe(0);
    expect(await count("installation", "installation_id = ?", [I0])).toBe(1);
    expect(await count("installation_key", "installation_id = ?", [I0])).toBe(1);
    expect(await count("entitlement", "installation_id = ?", [I0])).toBe(1);
  });
});
