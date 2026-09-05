import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  controlFetch,
  count,
  createSecretOperatorAuth,
  dispatchControl,
  GATEWAY_ORIGIN,
  generateTestKeypair,
  getAudits,
  getEntitlement,
  getGrants,
  mintAat,
  OPERATOR_BEARER,
  OPERATOR_ID,
  readHttpResult,
  resetE2eState,
  type HttpResult,
  type Scenario,
  type TestKeypair,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const I0 = "0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b";
const INSTALLATION_SCOPE = `installation:${I0}`;

/** Catalog REF-BODY (Conventions). Periods 2026-08-01…2026-09-01. */
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
};

type EnrolledI0 = {
  orgId: string;
  kid: string;
  keypair: TestKeypair;
};

function entitlePath(id = I0): string {
  return `/control/installations/${id}/entitle`;
}

function refBodyWith(
  patch: Record<string, unknown>,
): Record<string, unknown> {
  return { ...REF_BODY, ...patch };
}

function refBodyWithout(
  field: keyof typeof REF_BODY,
): Record<string, unknown> {
  const body: Record<string, unknown> = { ...REF_BODY };
  delete body[field];
  return body;
}

function assertUnauthorized(result: HttpResult): void {
  expect(result.status).toBe(401);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({ error: "unauthorized" });
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

async function enrollPendingI0(): Promise<EnrolledI0> {
  const orgId = crypto.randomUUID();
  const kid = crypto.randomUUID();
  const keypair = await generateTestKeypair(kid);
  const result = await controlFetch(`/control/installations/${I0}/enroll`, {
    body: {
      org_id: orgId,
      display_name: "E2E Clinic",
      region: "us-east-1",
      plan: "professional",
      public_key: keypair.publicKeyB64,
      algorithm: "EdDSA",
      kid,
    },
  });
  expect(result.status).toBe(200);
  return { orgId, kid, keypair };
}

async function assertNoEntitleSideEffects(
  entitlementBefore: Record<string, unknown> | null,
): Promise<void> {
  expect(entitlementBefore).not.toBeNull();
  expect(entitlementBefore?.status).toBe("pending");
  expect(entitlementBefore?.request_quota).toBe(0);
  expect(entitlementBefore?.token_budget).toBe(0);
  expect(Number(entitlementBefore?.cost_budget)).toBe(0);
  expect(["[]", []]).toContainEqual(entitlementBefore?.allowed_capabilities);
  expect(await getEntitlement(I0)).toEqual(entitlementBefore);
  expect(await getGrants(INSTALLATION_SCOPE)).toEqual([]);
  expect(await count("capability_grant")).toBe(0);
  expect(await getAudits("entitle", I0)).toEqual([]);
}

describe("Stage 04 — entitle auth and period validation (S04-001…S04-020)", () => {
  it("S04-001 — Entitle rejects a request with no Authorization header", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      auth: "none",
      body: REF_BODY,
    });

    assertUnauthorized(result);
    await assertNoEntitleSideEffects(before);
  });

  it("S04-002 — Entitle rejects a wrong operator bearer token", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      auth: "wrong",
      body: REF_BODY,
    });

    assertUnauthorized(result);
    await assertNoEntitleSideEffects(before);
  });

  it("S04-003 — Entitle rejects a clinic AAT presented as bearer", async () => {
    const enrolled = await enrollPendingI0();
    const scenario: Scenario = {
      installationId: I0,
      orgId: enrolled.orgId,
      branchId: crypto.randomUUID(),
      actorId: crypto.randomUUID(),
      kid: enrolled.kid,
      keypair: enrolled.keypair,
    };
    const aat = await mintAat(scenario, {
      claims: { role: "doctor" },
    });
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      auth: { bearer: aat },
      body: REF_BODY,
    });

    assertUnauthorized(result);
    await assertNoEntitleSideEffects(before);
  });

  it("S04-004 — Entitle rejects malformed Authorization schemes", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const basic = await controlFetch(entitlePath(), {
      auth: "basic",
      body: REF_BODY,
    });
    const empty = await controlFetch(entitlePath(), {
      auth: "empty",
      body: REF_BODY,
    });
    const whitespace = await controlFetch(entitlePath(), {
      auth: { authorization: "Bearer    " },
      body: REF_BODY,
    });

    for (const result of [basic, empty, whitespace]) {
      assertUnauthorized(result);
    }
    await assertNoEntitleSideEffects(before);
  });

  it("S04-005 — Entitle rejects every caller when the operator secret is unconfigured", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const request = new Request(`${GATEWAY_ORIGIN}${entitlePath()}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${OPERATOR_BEARER}`,
      },
      body: JSON.stringify(REF_BODY),
    });
    const response = await dispatchControl(
      request,
      {},
      createSecretOperatorAuth({
        bearerToken: "",
        operatorId: OPERATOR_ID,
      }),
    );
    const result = await readHttpResult(response);

    assertUnauthorized(result);
    await assertNoEntitleSideEffects(before);
  });

  it("S04-006 — Entitle rejects a non-JSON body", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: "not json at all{",
    });

    assertControlError(result, 400, "invalid_json");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-007 — Entitle rejects a JSON null body", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: null,
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-008 — Entitle rejects a JSON array body", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: [{ period_start: "2026-08-01T00:00:00.000Z" }],
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-009 — Entitle rejects a JSON scalar body", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: JSON.stringify("entitle please"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-010 — Entitle rejects a missing period_start", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: refBodyWithout("period_start"),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-011 — Entitle rejects an empty-string period_end", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: refBodyWith({ period_end: "" }),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-012 — Entitle rejects a non-string period_start", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: refBodyWith({ period_start: 1785513600000 }),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-013 — Entitle rejects a date-only period_start", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: refBodyWith({ period_start: "2026-08-01" }),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-014 — Entitle rejects a period with a numeric timezone offset", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: refBodyWith({ period_start: "2026-08-01T02:00:00+02:00" }),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-015 — Entitle rejects a lowercase-z period", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: refBodyWith({ period_end: "2026-09-01t00:00:00.000z" }),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-016 — Entitle rejects a regex-passing but impossible date", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: refBodyWith({ period_start: "2026-13-01T00:00:00.000Z" }),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-017 — Entitle rejects period_start equal to period_end", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: refBodyWith({
        period_start: "2026-08-01T00:00:00.000Z",
        period_end: "2026-08-01T00:00:00.000Z",
      }),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-018 — Entitle rejects period_start after period_end", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: refBodyWith({
        period_start: "2026-09-01T00:00:00.000Z",
        period_end: "2026-08-01T00:00:00.000Z",
      }),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });

  it("S04-019 — Entitle accepts instants without millisecond precision", async () => {
    await enrollPendingI0();

    const result = await controlFetch(entitlePath(), {
      body: refBodyWith({
        period_start: "2026-08-01T00:00:00Z",
        period_end: "2026-09-01T00:00:00Z",
      }),
    });

    const successBody = { installation_id: I0, status: "active" };
    expect(result.status).toBe(200);
    expect(result.headers.get("content-type")).toContain("application/json");
    expect(result.json).toEqual(successBody);
    expect(result.text).toBe(JSON.stringify(successBody));

    const entitlement = await getEntitlement(I0);
    expect(entitlement).not.toBeNull();
    expect(entitlement?.period_start).toBe("2026-08-01T00:00:00Z");
    expect(entitlement?.period_end).toBe("2026-09-01T00:00:00Z");
    expect(entitlement?.request_quota).toBe(REF_BODY.request_quota);
    expect(entitlement?.token_budget).toBe(REF_BODY.token_budget);
    expect(Number(entitlement?.cost_budget)).toBe(REF_BODY.cost_budget);
    expect(Number(entitlement?.soft_threshold)).toBe(REF_BODY.soft_threshold);
    expect(entitlement?.allowed_capabilities).toBe(
      JSON.stringify(REF_BODY.allowed_capabilities),
    );
    expect(entitlement?.status).toBe("active");
    expect(entitlement?.plan).toBe("professional");

    const grants = await getGrants(INSTALLATION_SCOPE);
    expect(grants).toHaveLength(1);
    expect(grants[0]?.scope).toBe(INSTALLATION_SCOPE);
    expect(grants[0]?.capability_id).toBe("clinic.visit_summary");
    expect(grants[0]?.capability_version).toBe("1.0.0");
    expect(grants[0]?.revoked_at).toBeNull();
    expect(await count("capability_grant")).toBe(1);

    const audits = await getAudits("entitle", I0);
    expect(audits).toHaveLength(1);
    expect(audits[0]?.action).toBe("entitle");
    expect(audits[0]?.target).toBe(I0);
  });

  it("S04-020 — Entitle rejects a negative request_quota", async () => {
    await enrollPendingI0();
    const before = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(), {
      body: refBodyWith({ request_quota: -1 }),
    });

    assertControlError(result, 400, "invalid_payload");
    await assertNoEntitleSideEffects(before);
  });
});
