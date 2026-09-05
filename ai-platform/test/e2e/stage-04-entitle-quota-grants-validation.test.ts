import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  controlFetch,
  count,
  generateTestKeypair,
  getAudits,
  getEntitlement,
  getGrants,
  queryOne,
  resetE2eState,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const I0 = "0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b";
const INSTALLATION_GRANT_SCOPE = `installation:${I0}`;
const ENTITLE_SUCCESS_BODY = {
  installation_id: I0,
  status: "active",
} as const;
const ALLOW_LIST_JSON = '["clinic.visit_summary"]';
const EMPTY_ALLOW_LIST_JSON = "[]";

/** Catalog Conventions REF-BODY — mutate one field per scenario. */
const REF_BODY = {
  period_start: "2026-08-01T00:00:00.000Z",
  period_end: "2026-09-01T00:00:00.000Z",
  request_quota: 1000,
  token_budget: 500000,
  cost_budget: 50.0,
  soft_threshold: 0.8,
  allowed_capabilities: ["clinic.visit_summary"],
  grants: [
    {
      capability_id: "clinic.visit_summary",
      capability_version: "1.0.0",
      scope: "installation",
    },
  ],
} as const;

type ControlResult = Awaited<ReturnType<typeof controlFetch>>;

function enrollPath(installationId = I0): string {
  return `/control/installations/${installationId}/enroll`;
}

function entitlePath(installationId = I0): string {
  return `/control/installations/${installationId}/entitle`;
}

function refBodyWith(
  field: keyof typeof REF_BODY,
  value: unknown,
): Record<string, unknown> {
  return { ...REF_BODY, [field]: value };
}

function refBodyWithout(
  field: keyof typeof REF_BODY,
): Record<string, unknown> {
  const body: Record<string, unknown> = { ...REF_BODY };
  delete body[field];
  return body;
}

function assertControlError(
  result: ControlResult,
  status: number,
  error: string,
): void {
  expect(result.status).toBe(status);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({ error });
  expect(result.text).toBe(JSON.stringify({ error }));
}

function assertEntitleActivated(result: ControlResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual(ENTITLE_SUCCESS_BODY);
  expect(result.text).toBe(JSON.stringify(ENTITLE_SUCCESS_BODY));
}

async function enrollI0(): Promise<void> {
  const { publicKeyB64 } = await generateTestKeypair();
  const result = await controlFetch(enrollPath(), {
    body: {
      org_id: crypto.randomUUID(),
      display_name: "E2E Clinic",
      region: "us-east-1",
      plan: "professional",
      public_key: publicKeyB64,
      algorithm: "EdDSA",
      kid: crypto.randomUUID(),
    },
  });
  expect(result.status).toBe(200);
}

async function entitleI0(body: unknown): Promise<ControlResult> {
  return controlFetch(entitlePath(), { body });
}

async function assertFailureSideEffects(): Promise<void> {
  const entitlement = await getEntitlement(I0);
  expect(entitlement).not.toBeNull();
  expect(entitlement?.status).toBe("pending");
  expect(entitlement?.plan).toBe("professional");
  expect(entitlement?.request_quota).toBe(0);
  expect(entitlement?.token_budget).toBe(0);
  expect(Number(entitlement?.cost_budget)).toBe(0);
  expect(["[]", []]).toContainEqual(entitlement?.allowed_capabilities);
  expect(Number(entitlement?.soft_threshold)).toBe(0);

  expect(await count("capability_grant")).toBe(0);
  expect(await getGrants(INSTALLATION_GRANT_SCOPE)).toEqual([]);
  expect(await getAudits("entitle", I0)).toEqual([]);
}

async function expectInvalidPayload(body: unknown): Promise<void> {
  await enrollI0();
  const result = await entitleI0(body);
  assertControlError(result, 400, "invalid_payload");
  await assertFailureSideEffects();
}

async function assertActiveEntitlement(overrides: {
  request_quota?: number;
  token_budget?: number;
  cost_budget?: number;
  soft_threshold?: number;
  allowed_capabilities?: string;
}): Promise<void> {
  const entitlement = await getEntitlement(I0);
  expect(entitlement).not.toBeNull();
  expect(entitlement?.installation_id).toBe(I0);
  expect(entitlement?.plan).toBe("professional");
  expect(entitlement?.period_start).toBe(REF_BODY.period_start);
  expect(entitlement?.period_end).toBe(REF_BODY.period_end);
  expect(entitlement?.request_quota).toBe(
    overrides.request_quota ?? REF_BODY.request_quota,
  );
  expect(entitlement?.token_budget).toBe(
    overrides.token_budget ?? REF_BODY.token_budget,
  );
  expect(Number(entitlement?.cost_budget)).toBe(
    overrides.cost_budget ?? REF_BODY.cost_budget,
  );
  expect(entitlement?.allowed_capabilities).toBe(
    overrides.allowed_capabilities ?? ALLOW_LIST_JSON,
  );
  expect(Number(entitlement?.soft_threshold)).toBe(
    overrides.soft_threshold ?? REF_BODY.soft_threshold,
  );
  expect(entitlement?.status).toBe("active");

  const installation = await queryOne<{ status: string }>(
    "SELECT status FROM installation WHERE installation_id = ?",
    [I0],
  );
  expect(installation?.status).toBe("active");
}

async function assertOneInstallationGrant(): Promise<void> {
  const grants = await getGrants(INSTALLATION_GRANT_SCOPE);
  expect(grants).toHaveLength(1);
  expect(grants[0]?.scope).toBe(INSTALLATION_GRANT_SCOPE);
  expect(grants[0]?.capability_id).toBe("clinic.visit_summary");
  expect(grants[0]?.capability_version).toBe("1.0.0");
  expect(grants[0]?.revoked_at).toBeNull();
  expect(grants[0]?.changed_by).toBe("platform-operator");
  expect(await count("capability_grant")).toBe(1);
}

async function assertEntitleAudit(afterPointer: string): Promise<void> {
  const audits = await getAudits("entitle", I0);
  expect(audits).toHaveLength(1);
  expect(audits[0]?.action).toBe("entitle");
  expect(audits[0]?.target).toBe(I0);
  expect(audits[0]?.operator_id).toBe("platform-operator");
  expect(audits[0]?.before_pointer).toBeNull();
  expect(audits[0]?.after_pointer).toBe(afterPointer);
}

describe("Stage 04 — entitle quota/grants validation (S04-021…S04-040)", () => {
  it("S04-021 — Entitle rejects a fractional request_quota", async () => {
    await expectInvalidPayload(refBodyWith("request_quota", 1.5));
  });

  it("S04-022 — Entitle rejects a string request_quota", async () => {
    await expectInvalidPayload(refBodyWith("request_quota", "1000"));
  });

  it("S04-023 — Entitle rejects a negative token_budget", async () => {
    await expectInvalidPayload(refBodyWith("token_budget", -500000));
  });

  it("S04-024 — Entitle rejects a fractional token_budget", async () => {
    await expectInvalidPayload(refBodyWith("token_budget", 500000.5));
  });

  it("S04-025 — Entitle rejects a negative cost_budget", async () => {
    await expectInvalidPayload(refBodyWith("cost_budget", -0.01));
  });

  it("S04-026 — Entitle rejects a string cost_budget", async () => {
    // Register 5 #24 (NaN/Infinity Number.isFinite) is not this ID — JSON
    // cannot encode those values. This string case is automatable over HTTP.
    await expectInvalidPayload(refBodyWith("cost_budget", "50.0"));
  });

  it("S04-027 — Entitle rejects a missing soft_threshold", async () => {
    await expectInvalidPayload(refBodyWithout("soft_threshold"));
  });

  it("S04-028 — Entitle rejects soft_threshold above 1", async () => {
    await expectInvalidPayload(refBodyWith("soft_threshold", 1.5));
  });

  it("S04-029 — Entitle rejects a negative soft_threshold", async () => {
    await expectInvalidPayload(refBodyWith("soft_threshold", -0.1));
  });

  it("S04-030 — Entitle rejects a string soft_threshold", async () => {
    await expectInvalidPayload(refBodyWith("soft_threshold", "0.8"));
  });

  it("S04-031 — Entitle accepts soft_threshold 0", async () => {
    await enrollI0();
    const result = await entitleI0(refBodyWith("soft_threshold", 0));

    assertEntitleActivated(result);
    await assertActiveEntitlement({ soft_threshold: 0 });
    await assertOneInstallationGrant();
    await assertEntitleAudit(ALLOW_LIST_JSON);
  });

  it("S04-032 — Entitle accepts soft_threshold 1", async () => {
    await enrollI0();
    const result = await entitleI0(refBodyWith("soft_threshold", 1));

    assertEntitleActivated(result);
    await assertActiveEntitlement({ soft_threshold: 1 });
    await assertOneInstallationGrant();
    await assertEntitleAudit(ALLOW_LIST_JSON);
  });

  it("S04-033 — Entitle accepts all-zero quotas", async () => {
    await enrollI0();
    const result = await entitleI0({
      ...REF_BODY,
      request_quota: 0,
      token_budget: 0,
      cost_budget: 0,
    });

    assertEntitleActivated(result);
    await assertActiveEntitlement({
      request_quota: 0,
      token_budget: 0,
      cost_budget: 0,
    });
    await assertOneInstallationGrant();
    await assertEntitleAudit(ALLOW_LIST_JSON);
  });

  it("S04-034 — Entitle rejects a missing allowed_capabilities", async () => {
    await expectInvalidPayload(refBodyWithout("allowed_capabilities"));
  });

  it("S04-035 — Entitle rejects a string allowed_capabilities", async () => {
    await expectInvalidPayload(
      refBodyWith("allowed_capabilities", "clinic.visit_summary"),
    );
  });

  it("S04-036 — Entitle rejects non-string entries in allowed_capabilities", async () => {
    await expectInvalidPayload(
      refBodyWith("allowed_capabilities", ["clinic.visit_summary", 1]),
    );
  });

  it("S04-037 — Entitle accepts an empty allowed_capabilities list", async () => {
    await enrollI0();
    const result = await entitleI0(refBodyWith("allowed_capabilities", []));

    assertEntitleActivated(result);
    await assertActiveEntitlement({
      allowed_capabilities: EMPTY_ALLOW_LIST_JSON,
    });
    await assertOneInstallationGrant();
    await assertEntitleAudit(EMPTY_ALLOW_LIST_JSON);
  });

  it("S04-038 — Entitle rejects a missing grants field", async () => {
    await expectInvalidPayload(refBodyWithout("grants"));
  });

  it("S04-039 — Entitle rejects a non-array grants field", async () => {
    await expectInvalidPayload(
      refBodyWith("grants", {
        capability_id: "clinic.visit_summary",
        capability_version: "1.0.0",
      }),
    );
  });

  it("S04-040 — Entitle rejects an empty grants array", async () => {
    await expectInvalidPayload(refBodyWith("grants", []));
  });
});
