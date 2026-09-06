import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  controlFetch,
  count,
  env,
  generateTestKeypair,
  getAudits,
  getEntitlement,
  OPERATOR_ID,
  queryAll,
  queryOne,
  resetE2eState,
  type HttpResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const I0 = "3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d";
const IUNKNOWN = "00000000-0000-4000-8000-000000000099";
const I2_UPPER = "AA10C4D2-5E6F-4A7B-8C9D-0E1F2A3B4C5D";
const I2_STORED = I2_UPPER.toLowerCase();
const K0 = "c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f";
const K1 = "d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a";
const K2 = "e6f7a8b9-0c1d-4e2f-9a3b-4c5d6e7f8a9b";
const X1 = "Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV";
const X2 = "mZx1QwErTyUiOp9sDfGhJkLzXcVbNm2QeRtYuIoPaSd";
const INSTALLATION_KEY_TTL_DAYS = 365;
const MS_PER_DAY = 24 * 60 * 60 * 1000;
const ISO_8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const CLOCK_SKEW_MS = 15_000;

const CANONICAL_ENROLL_BODY = {
  org_id: "7a1b2c3d-4e5f-4a6b-9c8d-0e1f2a3b4c5d",
  display_name: "Verify Clinic",
  region: "eu-central",
  plan: "standard",
  public_key: "n4bQgYhMfWWaL-qgxVrQ1O91g3Z2Q4u2Zz8v0m5p8xk",
  algorithm: "EdDSA",
  kid: K0,
} as const;

const I2_ENROLL_BODY = {
  org_id: "8B2C3D4E-5F6A-4B7C-8D9E-0F1A2B3C4D5E",
  display_name: "Boundary Clinic",
  region: "eu-central",
  plan: "starter",
  algorithm: "EdDSA",
  kid: "1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D",
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
  keys: Record<string, unknown>[];
  entitlements: Record<string, unknown>[];
  audits: Record<string, unknown>[];
  grants: number;
  r2Keys: string[];
};

function installationActionPath(action: string, id = I0): string {
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

function assertEmptySuccess(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({});
}

async function listR2Keys(): Promise<string[]> {
  const page = await env.R2.list();
  return page.objects.map((object) => object.key).sort();
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
      "SELECT * FROM control_audit ORDER BY recorded_at, audit_id",
    ),
    grants: await count("capability_grant"),
    r2Keys: await listR2Keys(),
  };
}

async function assertLifecycleUnchanged(
  before: LifecycleSnapshot,
): Promise<void> {
  expect(
    await queryAll("SELECT * FROM installation ORDER BY installation_id"),
  ).toEqual(before.installations);
  expect(
    await queryAll("SELECT * FROM installation_key ORDER BY key_id"),
  ).toEqual(before.keys);
  expect(
    await queryAll("SELECT * FROM entitlement ORDER BY entitlement_id"),
  ).toEqual(before.entitlements);
  expect(
    await queryAll(
      "SELECT * FROM control_audit ORDER BY recorded_at, audit_id",
    ),
  ).toEqual(before.audits);
  expect(await count("capability_grant")).toBe(before.grants);
  expect(await listR2Keys()).toEqual(before.r2Keys);
}

async function assertNoLifecycleWrites(): Promise<void> {
  expect(await count("installation")).toBe(0);
  expect(await count("installation_key")).toBe(0);
  expect(await count("entitlement")).toBe(0);
  expect(await count("control_audit")).toBe(0);
  expect(await count("capability_grant")).toBe(0);
  expect(await listR2Keys()).toEqual([]);
}

async function enrollI0(): Promise<void> {
  const result = await controlFetch(installationActionPath("enroll"), {
    body: CANONICAL_ENROLL_BODY,
  });
  expect(result.status).toBe(200);
}

async function enrollI2Uppercase(): Promise<void> {
  const keypair = await generateTestKeypair();
  const result = await controlFetch(installationActionPath("enroll", I2_UPPER), {
    body: {
      ...I2_ENROLL_BODY,
      public_key: keypair.publicKeyB64,
    },
  });
  expect(result.status).toBe(200);
}

async function suspendI0(): Promise<HttpResult> {
  return controlFetch(installationActionPath("suspend"), { body: {} });
}

async function resumeI0(): Promise<HttpResult> {
  return controlFetch(installationActionPath("resume"), { body: {} });
}

function assertNullPointers(row: Record<string, unknown> | undefined): void {
  expect(row).toBeDefined();
  expect(row?.operator_id).toBe(OPERATOR_ID);
  expect(row?.before_pointer).toBeNull();
  expect(row?.after_pointer).toBeNull();
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

function expectedValidUntil(validFromIso: string): string {
  return new Date(
    Date.parse(validFromIso) + INSTALLATION_KEY_TTL_DAYS * MS_PER_DAY,
  ).toISOString();
}

describe("Stage 03 — lifecycle suspend/resume/rotate (S03-041…S03-060)", () => {
  it("S03-041 — Suspend of unknown installation returns installation_not_found", async () => {
    const result = await controlFetch(
      installationActionPath("suspend", IUNKNOWN),
      { body: {} },
    );

    assertControlError(result, 404, "installation_not_found");
    await assertNoLifecycleWrites();
  });

  it("S03-042 — Suspend happy path freezes an active installation", async () => {
    await enrollI0();
    const keyBefore = await queryOne(
      "SELECT * FROM installation_key WHERE key_id = ?",
      [K0],
    );
    const entitlementBefore = await getEntitlement(I0);

    const result = await suspendI0();

    assertEmptySuccess(result);

    const installation = await queryOne<{ status: string }>(
      "SELECT status FROM installation WHERE installation_id = ?",
      [I0],
    );
    expect(installation?.status).toBe("suspended");

    const suspendAudits = await getAudits("suspend", I0);
    expect(suspendAudits).toHaveLength(1);
    expect(suspendAudits[0]?.action).toBe("suspend");
    expect(suspendAudits[0]?.target).toBe(I0);
    assertNullPointers(suspendAudits[0]);

    const entitlementAfter = await getEntitlement(I0);
    expect(entitlementAfter?.status).toBe("pending");
    expect(entitlementAfter).toEqual(entitlementBefore);

    expect(
      await queryOne("SELECT * FROM installation_key WHERE key_id = ?", [K0]),
    ).toEqual(keyBefore);
    expect(await listR2Keys()).toEqual([]);
  });

  it("S03-043 — Suspend of already-suspended installation returns illegal_lifecycle_transition", async () => {
    await enrollI0();
    assertEmptySuccess(await suspendI0());
    const before = await snapshotLifecycle();

    const result = await suspendI0();

    assertControlError(result, 409, "illegal_lifecycle_transition");
    await assertLifecycleUnchanged(before);
    expect(await getAudits("suspend", I0)).toHaveLength(1);
  });

  it("S03-044 — Resume of unknown installation returns installation_not_found", async () => {
    const result = await controlFetch(
      installationActionPath("resume", IUNKNOWN),
      { body: {} },
    );

    assertControlError(result, 404, "installation_not_found");
    await assertNoLifecycleWrites();
  });

  it("S03-045 — Resume happy path restores suspended installation to active", async () => {
    await enrollI0();
    assertEmptySuccess(await suspendI0());
    const keyBefore = await queryOne(
      "SELECT * FROM installation_key WHERE key_id = ?",
      [K0],
    );
    const entitlementBefore = await getEntitlement(I0);

    const result = await resumeI0();

    assertEmptySuccess(result);

    const installation = await queryOne<{ status: string }>(
      "SELECT status FROM installation WHERE installation_id = ?",
      [I0],
    );
    expect(installation?.status).toBe("active");

    const resumeAudits = await getAudits("resume", I0);
    expect(resumeAudits).toHaveLength(1);
    expect(resumeAudits[0]?.action).toBe("resume");
    expect(resumeAudits[0]?.target).toBe(I0);
    assertNullPointers(resumeAudits[0]);

    expect(await getEntitlement(I0)).toEqual(entitlementBefore);
    expect(
      await queryOne("SELECT * FROM installation_key WHERE key_id = ?", [K0]),
    ).toEqual(keyBefore);
    expect(await listR2Keys()).toEqual([]);
  });

  it("S03-046 — Resume of active installation returns illegal_lifecycle_transition", async () => {
    await enrollI0();
    assertEmptySuccess(await suspendI0());
    assertEmptySuccess(await resumeI0());
    const before = await snapshotLifecycle();

    const result = await resumeI0();

    assertControlError(result, 409, "illegal_lifecycle_transition");
    await assertLifecycleUnchanged(before);
    expect(await getAudits("resume", I0)).toHaveLength(1);
  });

  it("S03-047 — Suspend ignores the request body entirely", async () => {
    await enrollI2Uppercase();

    const result = await controlFetch(
      installationActionPath("suspend", I2_UPPER),
      {
        headers: { "content-type": "text/plain" },
        body: "this is not json at all",
      },
    );

    assertEmptySuccess(result);

    const installation = await queryOne<{ status: string }>(
      "SELECT status FROM installation WHERE installation_id = ?",
      [I2_STORED],
    );
    expect(installation?.status).toBe("suspended");

    const suspendAudits = await getAudits("suspend", I2_STORED);
    expect(suspendAudits).toHaveLength(1);
    expect(suspendAudits[0]?.action).toBe("suspend");
    expect(suspendAudits[0]?.target).toBe(I2_STORED);
    assertNullPointers(suspendAudits[0]);
    expect(await getAudits("suspend", I2_UPPER)).toHaveLength(0);
  });

  it("S03-048 — Rotate rejects a non-JSON body", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(installationActionPath("rotate"), {
      body: "not-json",
    });

    assertControlError(result, 400, "invalid_json");
    await assertLifecycleUnchanged(before);
  });

  it("S03-049 — Rotate rejects a non-object JSON body", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(installationActionPath("rotate"), {
      body: ["kid"],
    });

    assertControlError(result, 400, "invalid_payload");
    await assertLifecycleUnchanged(before);
  });

  it("S03-050 — Rotate rejects a missing kid", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(installationActionPath("rotate"), {
      body: { public_key: X1, algorithm: "EdDSA" },
    });

    assertControlError(result, 400, "invalid_payload");
    await assertLifecycleUnchanged(before);
  });

  it("S03-051 — Rotate rejects a missing public_key", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(installationActionPath("rotate"), {
      body: { kid: K1, algorithm: "EdDSA" },
    });

    assertControlError(result, 400, "invalid_payload");
    await assertLifecycleUnchanged(before);
  });

  it("S03-052 — Rotate rejects a missing algorithm", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(installationActionPath("rotate"), {
      body: { kid: K1, public_key: X1 },
    });

    assertControlError(result, 400, "invalid_payload");
    await assertLifecycleUnchanged(before);
  });

  it("S03-053 — Rotate rejects an unsupported algorithm", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(installationActionPath("rotate"), {
      body: { kid: K1, public_key: X1, algorithm: "ES256" },
    });

    assertControlError(result, 400, "invalid_payload");
    await assertLifecycleUnchanged(before);
  });

  it("S03-054 — Rotate rejects a non-UUID kid", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(installationActionPath("rotate"), {
      body: { kid: "rotate-1", public_key: X1, algorithm: "EdDSA" },
    });

    assertControlError(result, 400, "invalid_payload");
    await assertLifecycleUnchanged(before);
  });

  it("S03-055 — Rotate rejects a public_key of the wrong byte length", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(installationActionPath("rotate"), {
      body: { kid: K1, public_key: "c2hvcnQ", algorithm: "EdDSA" },
    });

    assertControlError(result, 400, "invalid_payload");
    await assertLifecycleUnchanged(before);
  });

  it("S03-056 — Rotate of unknown installation returns installation_not_found", async () => {
    const result = await controlFetch(
      installationActionPath("rotate", IUNKNOWN),
      { body: ROTATE_K1_BODY },
    );

    assertControlError(result, 404, "installation_not_found");
    await assertNoLifecycleWrites();
  });

  it("S03-057 — Rotate with already-registered kid returns duplicate_kid", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(installationActionPath("rotate"), {
      body: { kid: K0, public_key: X1, algorithm: "EdDSA" },
    });

    assertControlError(result, 409, "duplicate_kid");
    await assertLifecycleUnchanged(before);
    expect(await count("installation_key")).toBe(1);
    expect(await getAudits("rotate", I0)).toHaveLength(0);
  });

  it("S03-058 — Rotate happy path adds a second active key", async () => {
    await enrollI0();
    const installationBefore = await queryOne(
      "SELECT * FROM installation WHERE installation_id = ?",
      [I0],
    );
    const entitlementBefore = await getEntitlement(I0);
    const k0Before = await queryOne(
      "SELECT * FROM installation_key WHERE key_id = ?",
      [K0],
    );

    const result = await controlFetch(installationActionPath("rotate"), {
      body: ROTATE_K1_BODY,
    });

    assertEmptySuccess(result);

    expect(await count("installation_key")).toBe(2);
    const k1 = await queryOne<{
      key_id: string;
      installation_id: string;
      public_key: string;
      algorithm: string;
      valid_from: string;
      valid_until: string | null;
      revoked_at: string | null;
    }>("SELECT * FROM installation_key WHERE key_id = ?", [K1]);
    expect(k1).toMatchObject({
      key_id: K1,
      installation_id: I0,
      public_key: X1,
      algorithm: "EdDSA",
      revoked_at: null,
    });
    const validFrom = assertIsoApproxNow(k1?.valid_from);
    expect(k1?.valid_until).toBe(expectedValidUntil(validFrom));

    expect(
      await queryOne("SELECT * FROM installation_key WHERE key_id = ?", [K0]),
    ).toEqual(k0Before);
    expect(k0Before?.revoked_at ?? null).toBeNull();

    const rotateAudits = await getAudits("rotate", I0);
    expect(rotateAudits).toHaveLength(1);
    expect(rotateAudits[0]?.action).toBe("rotate");
    expect(rotateAudits[0]?.target).toBe(I0);
    assertNullPointers(rotateAudits[0]);

    expect(
      await queryOne("SELECT * FROM installation WHERE installation_id = ?", [
        I0,
      ]),
    ).toEqual(installationBefore);
    expect(await getEntitlement(I0)).toEqual(entitlementBefore);
    expect(await listR2Keys()).toEqual([]);
  });

  it("S03-059 — Rotate succeeds on a suspended installation", async () => {
    await enrollI2Uppercase();
    assertEmptySuccess(
      await controlFetch(installationActionPath("suspend", I2_UPPER), {
        body: {},
      }),
    );

    const result = await controlFetch(
      installationActionPath("rotate", I2_UPPER),
      { body: ROTATE_K2_BODY },
    );

    assertEmptySuccess(result);

    const installation = await queryOne<{ status: string }>(
      "SELECT status FROM installation WHERE installation_id = ?",
      [I2_STORED],
    );
    expect(installation?.status).toBe("suspended");

    const k2 = await queryOne<{
      key_id: string;
      installation_id: string;
      public_key: string;
      revoked_at: string | null;
    }>("SELECT * FROM installation_key WHERE key_id = ?", [K2]);
    expect(k2).toMatchObject({
      key_id: K2,
      installation_id: I2_STORED,
      public_key: X2,
      revoked_at: null,
    });

    const rotateAudits = await getAudits("rotate", I2_STORED);
    expect(rotateAudits).toHaveLength(1);
    expect(rotateAudits[0]?.action).toBe("rotate");
    expect(rotateAudits[0]?.target).toBe(I2_STORED);
    assertNullPointers(rotateAudits[0]);
  });

  it("S03-060 — Revoke-key rejects a non-JSON body", async () => {
    await enrollI0();
    const before = await snapshotLifecycle();

    const result = await controlFetch(installationActionPath("revoke-key"), {
      body: "not-json",
    });

    assertControlError(result, 400, "invalid_json");
    await assertLifecycleUnchanged(before);
  });
});
