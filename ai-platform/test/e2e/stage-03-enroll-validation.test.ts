import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  controlFetch,
  count,
  env,
  GATEWAY_ORIGIN,
  generateTestKeypair,
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
const ORG0 = "7a1b2c3d-4e5f-4a6b-9c8d-0e1f2a3b4c5d";
const K0 = "c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f";
const X0 = "n4bQgYhMfWWaL-qgxVrQ1O91g3Z2Q4u2Zz8v0m5p8xk";

const I2_UPPER = "AA10C4D2-5E6F-4A7B-8C9D-0E1F2A3B4C5D";
const ORG2_UPPER = "8B2C3D4E-5F6A-4B7C-8D9E-0F1A2B3C4D5E";
const KI2_UPPER = "1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D";
// Catalog XI2 is 30 bytes; S03-036 uses generateTestKeypair() (32 bytes).

const I_ORG_DUP = "4a5b6c7d-8e9f-4a0b-bc1d-2e3f4a5b6c7d";
const K_ORG_DUP = "5b6c7d8e-9f0a-4b1c-8d2e-3f4a5b6c7d8e";
const I_KID_DUP = "6c7d8e9f-0a1b-4c2d-9e3f-4a5b6c7d8e9f";
const ORG_KID_DUP = "ad4e5f6a-7b8c-4d9e-ae0f-1a2b3c4d5e6f";

const INSTALLATION_KEY_TTL_DAYS = 365;
const MS_PER_DAY = 24 * 60 * 60 * 1000;
const ISO_8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/;
const CANONICAL_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CANONICAL_ENROLL_BODY = {
  org_id: ORG0,
  display_name: "Verify Clinic",
  region: "eu-central",
  plan: "standard",
  public_key: X0,
  algorithm: "EdDSA",
  kid: K0,
} as const;

// Code: new URL(request.url).origin. Pool origin is GATEWAY_ORIGIN.
const CATALOG_ENROLL_SUCCESS_BODY = {
  platform_base_url: GATEWAY_ORIGIN,
} as const;

const I2_ENROLL_BODY = {
  org_id: ORG2_UPPER,
  display_name: "Boundary Clinic",
  region: "eu-central",
  plan: "starter",
  algorithm: "EdDSA",
  kid: KI2_UPPER,
} as const;

type InstallationRow = {
  installation_id: string;
  org_id: string;
  display_name: string;
  status: string;
  region: string;
  enrolled_at: string;
};

type InstallationKeyRow = {
  key_id: string;
  installation_id: string;
  public_key: string;
  algorithm: string;
  valid_from: string;
  valid_until: string | null;
  revoked_at: string | null;
};

type EntitlementRow = {
  entitlement_id: string;
  installation_id: string;
  plan: string;
  period_start: string;
  period_end: string;
  request_quota: number;
  token_budget: number;
  cost_budget: number;
  allowed_capabilities: unknown;
  soft_threshold: number;
  status: string;
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

type LifecycleCounts = {
  installation: number;
  installation_key: number;
  entitlement: number;
  control_audit: number;
};

function enrollPath(installationId: string): string {
  return `/control/installations/${installationId}/enroll`;
}

function enrollBodyWithout(
  field: keyof typeof CANONICAL_ENROLL_BODY,
): Record<string, unknown> {
  const body: Record<string, unknown> = { ...CANONICAL_ENROLL_BODY };
  delete body[field];
  return body;
}

function enrollBodyWith(
  field: keyof typeof CANONICAL_ENROLL_BODY,
  value: unknown,
): Record<string, unknown> {
  return { ...CANONICAL_ENROLL_BODY, [field]: value };
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

function assertCatalogEnrollSuccess(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual(CATALOG_ENROLL_SUCCESS_BODY);
  expect(result.text).toBe(JSON.stringify(CATALOG_ENROLL_SUCCESS_BODY));
}

async function assertNoLifecycleWrites(): Promise<void> {
  expect(await count("installation")).toBe(0);
  expect(await count("installation_key")).toBe(0);
  expect(await count("entitlement")).toBe(0);
  expect(await count("control_audit")).toBe(0);
}

async function lifecycleCounts(): Promise<LifecycleCounts> {
  return {
    installation: await count("installation"),
    installation_key: await count("installation_key"),
    entitlement: await count("entitlement"),
    control_audit: await count("control_audit"),
  };
}

async function countR2Objects(): Promise<number> {
  // HARNESS-GAP: frozen API has r2Exists(key) / getR2Json(key) but no list-all.
  // env.R2.list is on the barrel (same pattern as Stage 00).
  let total = 0;
  let cursor: string | undefined;
  do {
    const page = await env.R2.list(cursor ? { cursor } : undefined);
    total += page.objects.length;
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return total;
}

function addDaysIso(iso: string, days: number): string {
  return new Date(Date.parse(iso) + days * MS_PER_DAY).toISOString();
}

function expectIsoTimestamp(value: unknown): string {
  expect(typeof value).toBe("string");
  const iso = String(value);
  expect(iso).toMatch(ISO_8601);
  expect(Number.isNaN(Date.parse(iso))).toBe(false);
  return iso;
}

function expectCanonicalUuid(value: unknown): string {
  expect(typeof value).toBe("string");
  const id = String(value);
  expect(id).toMatch(CANONICAL_UUID_RE);
  return id;
}

async function enrollCanonicalI0(): Promise<HttpResult> {
  const result = await controlFetch(enrollPath(I0), {
    body: { ...CANONICAL_ENROLL_BODY },
  });
  assertCatalogEnrollSuccess(result);
  return result;
}

describe("Stage 03 — enroll validation (S03-021…S03-040)", () => {
  it("S03-021 — Enroll rejects a non-object JSON body", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: [1, 2, 3],
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-022 — Enroll rejects a missing org_id", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWithout("org_id"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-023 — Enroll rejects a blank display_name", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWith("display_name", "   "),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-024 — Enroll rejects a non-string region", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWith("region", 42),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-025 — Enroll rejects a missing plan", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWithout("plan"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-026 — Enroll rejects a missing public_key", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWithout("public_key"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-027 — Enroll rejects a missing algorithm", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWithout("algorithm"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-028 — Enroll rejects a missing kid", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWithout("kid"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-029 — Enroll rejects an unknown plan tier", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWith("plan", "platinum"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-030 — Enroll rejects an unsupported algorithm", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWith("algorithm", "RS256"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-031 — Enroll rejects a non-UUID org_id", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWith("org_id", "x"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-032 — Enroll rejects a non-UUID kid", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWith("kid", "key-1"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-033 — Enroll rejects a non-UUID path installation_id", async () => {
    const result = await controlFetch(
      "/control/installations/not-a-uuid/enroll",
      { body: { ...CANONICAL_ENROLL_BODY } },
    );

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-034 — Enroll rejects a public_key of the wrong byte length", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWith("public_key", "c2hvcnQ"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-035 — Enroll rejects a public_key that is not base64url-decodable", async () => {
    const result = await controlFetch(enrollPath(I0), {
      body: enrollBodyWith("public_key", "!!!not-base64!!!"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoLifecycleWrites();
  });

  it("S03-036 — Enroll accepts uppercase hex UUIDs (boundary)", async () => {
    const { publicKeyB64 } = await generateTestKeypair();
    const result = await controlFetch(enrollPath(I2_UPPER), {
      body: { ...I2_ENROLL_BODY, public_key: publicKeyB64 },
    });

    assertCatalogEnrollSuccess(result);

    const installation = await queryOne<InstallationRow>(
      "SELECT * FROM installation WHERE installation_id = ?",
      [I2_UPPER],
    );
    expect(installation).not.toBeNull();
    expect(installation?.installation_id).toBe(I2_UPPER);
    expect(installation?.org_id).toBe(ORG2_UPPER);
    expect(installation?.display_name).toBe("Boundary Clinic");
    expect(installation?.status).toBe("active");
    expect(installation?.region).toBe("eu-central");

    const key = await queryOne<InstallationKeyRow>(
      "SELECT * FROM installation_key WHERE key_id = ?",
      [KI2_UPPER],
    );
    expect(key).not.toBeNull();
    expect(key?.key_id).toBe(KI2_UPPER);
    expect(key?.installation_id).toBe(I2_UPPER);
    expect(key?.public_key).toBe(publicKeyB64);
    expect(key?.revoked_at).toBeNull();

    const entitlement = await queryOne<EntitlementRow>(
      "SELECT * FROM entitlement WHERE installation_id = ?",
      [I2_UPPER],
    );
    expect(entitlement).not.toBeNull();
    expect(entitlement?.plan).toBe("starter");
    expect(entitlement?.status).toBe("pending");

    const audits = await queryAll<ControlAuditRow>(
      "SELECT * FROM control_audit WHERE action = ? AND target = ?",
      ["enroll", I2_UPPER],
    );
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe("platform-operator");
  });

  it("S03-037 — Enroll happy path registers installation, key, pending entitlement, and audit", async () => {
    // Register 5 #20 (importKey catch after length check) is a note, not an ID
    // skip. This HTTP enroll still sends catalog X0.
    const result = await controlFetch(enrollPath(I0), {
      body: { ...CANONICAL_ENROLL_BODY },
    });

    assertCatalogEnrollSuccess(result);

    const installation = await queryOne<InstallationRow>(
      "SELECT * FROM installation WHERE installation_id = ?",
      [I0],
    );
    expect(installation).not.toBeNull();
    expect(installation?.installation_id).toBe(I0);
    expect(installation?.org_id).toBe(ORG0);
    expect(installation?.display_name).toBe("Verify Clinic");
    expect(installation?.status).toBe("active");
    expect(installation?.region).toBe("eu-central");
    const enrolledAt = expectIsoTimestamp(installation?.enrolled_at);

    const key = await queryOne<InstallationKeyRow>(
      "SELECT * FROM installation_key WHERE key_id = ?",
      [K0],
    );
    expect(key).not.toBeNull();
    expect(key?.key_id).toBe(K0);
    expect(key?.installation_id).toBe(I0);
    expect(key?.public_key).toBe(X0);
    expect(key?.algorithm).toBe("EdDSA");
    expect(key?.valid_from).toBe(enrolledAt);
    expect(key?.valid_until).toBe(
      addDaysIso(enrolledAt, INSTALLATION_KEY_TTL_DAYS),
    );
    expect(key?.revoked_at).toBeNull();

    const entitlement = await queryOne<EntitlementRow>(
      "SELECT * FROM entitlement WHERE installation_id = ?",
      [I0],
    );
    expect(entitlement).not.toBeNull();
    expectCanonicalUuid(entitlement?.entitlement_id);
    expect(entitlement?.installation_id).toBe(I0);
    expect(entitlement?.plan).toBe("standard");
    expect(entitlement?.period_start).toBe(enrolledAt);
    expect(entitlement?.period_end).toBe(enrolledAt);
    expect(entitlement?.request_quota).toBe(0);
    expect(entitlement?.token_budget).toBe(0);
    expect(Number(entitlement?.cost_budget)).toBe(0);
    expect(["[]", []]).toContainEqual(entitlement?.allowed_capabilities);
    expect(Number(entitlement?.soft_threshold)).toBe(0);
    expect(entitlement?.status).toBe("pending");

    const audits = await queryAll<ControlAuditRow>(
      "SELECT * FROM control_audit WHERE action = ? AND target = ?",
      ["enroll", I0],
    );
    expect(audits).toHaveLength(1);
    expectCanonicalUuid(audits[0]?.audit_id);
    expect(audits[0]?.operator_id).toBe("platform-operator");
    expect(audits[0]?.action).toBe("enroll");
    expect(audits[0]?.target).toBe(I0);
    expect(audits[0]?.before_pointer).toBeNull();
    expect(audits[0]?.after_pointer).toBeNull();

    expect(await count("capability_grant")).toBe(0);
    expect(await countR2Objects()).toBe(0);
  });

  it("S03-038 — Re-enroll of the same installation_id returns already_enrolled", async () => {
    await enrollCanonicalI0();
    const before = await lifecycleCounts();
    expect(before).toEqual({
      installation: 1,
      installation_key: 1,
      entitlement: 1,
      control_audit: 1,
    });

    const result = await controlFetch(enrollPath(I0), {
      body: { ...CANONICAL_ENROLL_BODY },
    });

    assertControlError(result, 409, "already_enrolled");
    expect(await lifecycleCounts()).toEqual(before);
  });

  it("S03-039 — Enroll of a new installation_id with an existing org_id returns already_enrolled", async () => {
    await enrollCanonicalI0();

    const result = await controlFetch(enrollPath(I_ORG_DUP), {
      body: {
        ...CANONICAL_ENROLL_BODY,
        display_name: "Verify Clinic DR",
        kid: K_ORG_DUP,
      },
    });

    assertControlError(result, 409, "already_enrolled");
    expect(
      await queryOne(
        "SELECT installation_id FROM installation WHERE installation_id = ?",
        [I_ORG_DUP],
      ),
    ).toBeNull();
    expect(await count("installation")).toBe(1);
    const remaining = await queryOne<InstallationRow>(
      "SELECT * FROM installation WHERE installation_id = ?",
      [I0],
    );
    expect(remaining?.installation_id).toBe(I0);
    expect(remaining?.org_id).toBe(ORG0);
  });

  it("S03-040 — Enroll reusing an existing kid returns duplicate_kid", async () => {
    // Catalog side effects mention S03-036+S03-037 rows; this isolated test
    // rebuilds I0 only. Assert the failed id is absent and I0 remains.
    await enrollCanonicalI0();

    const result = await controlFetch(enrollPath(I_KID_DUP), {
      body: {
        org_id: ORG_KID_DUP,
        display_name: "Other Clinic",
        region: "eu-central",
        plan: "standard",
        public_key: X0,
        algorithm: "EdDSA",
        kid: K0,
      },
    });

    assertControlError(result, 409, "duplicate_kid");
    expect(
      await queryOne(
        "SELECT installation_id FROM installation WHERE installation_id = ?",
        [I_KID_DUP],
      ),
    ).toBeNull();
    expect(await count("installation")).toBe(1);
    expect(await count("installation_key")).toBe(1);
    expect(await count("entitlement")).toBe(1);
    expect(await count("control_audit")).toBe(1);
    const remaining = await queryOne<InstallationRow>(
      "SELECT * FROM installation WHERE installation_id = ?",
      [I0],
    );
    expect(remaining?.installation_id).toBe(I0);
    expect(remaining?.org_id).toBe(ORG0);
    expect(remaining?.status).toBe("active");
  });
});
