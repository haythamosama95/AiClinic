import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import publishedVisitSummary from "../../manifests/published/clinic.visit_summary@1.0.0.json";
import {
  bootstrapE2e,
  controlFetch,
  count,
  createCapabilityRegistry,
  generateTestKeypair,
  getAudits,
  getEntitlement,
  getGrants,
  loadManifest,
  OPERATOR_ID,
  queryAll,
  queryOne,
  resetE2eState,
  seedSql,
  setCapabilityRegistry,
  type HttpResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const I0 = "0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b";
const I1 = "1b2e5d3f-8c4e-5f6a-ab7c-2d3e4f5a6b7c";
const CAPABILITY_ID = "clinic.visit_summary";
const ISO_8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/;
const CANONICAL_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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

function clonePublishedWire(): Record<string, unknown> {
  return JSON.parse(JSON.stringify(publishedVisitSummary)) as Record<
    string,
    unknown
  >;
}

function visitSummaryV2Wire(): Record<string, unknown> {
  const wire = clonePublishedWire();
  const identity = wire.Identity as Record<string, unknown>;
  wire.Identity = { ...identity, version: "2.0.0" };
  return wire;
}

function restorePublishedRegistry(): void {
  setCapabilityRegistry(
    createCapabilityRegistry([loadManifest(clonePublishedWire())]),
    { replace: true },
  );
}

function installTwoVersionRegistry(): void {
  setCapabilityRegistry(
    createCapabilityRegistry([
      loadManifest(clonePublishedWire()),
      loadManifest(visitSummaryV2Wire()),
    ]),
    { replace: true },
  );
}

async function withTwoVersionRegistry(
  run: () => Promise<void>,
): Promise<void> {
  installTwoVersionRegistry();
  try {
    await run();
  } finally {
    restorePublishedRegistry();
  }
}

function activatePath(version: string): string {
  return `/control/capabilities/${CAPABILITY_ID}/versions/${version}/activate`;
}

function promotePath(version: string): string {
  return `/control/capabilities/${CAPABILITY_ID}/versions/${version}/promote`;
}

function deprecatePath(version: string): string {
  return `/control/capabilities/${CAPABILITY_ID}/versions/${version}/deprecate`;
}

function entitlePath(installationId: string): string {
  return `/control/installations/${installationId}/entitle`;
}

function enrollPath(installationId: string): string {
  return `/control/installations/${installationId}/enroll`;
}

function installationScope(installationId: string): string {
  return `installation:${installationId}`;
}

function assertControlError(
  result: HttpResult,
  status: number,
  error: string,
): void {
  expect(result.status).toBe(status);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({ error });
  expect(result.text).toBe(JSON.stringify({ error }));
}

function assertEmptySuccess(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({});
  expect(result.text).toBe("{}");
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

async function waitForClockTick(): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 15));
}

async function enroll(
  installationId: string,
  plan: "professional" | "standard",
): Promise<void> {
  const keypair = await generateTestKeypair();
  const result = await controlFetch(enrollPath(installationId), {
    body: {
      org_id: crypto.randomUUID(),
      display_name: "Verify Clinic",
      region: "eu-central",
      plan,
      public_key: keypair.publicKeyB64,
      algorithm: "EdDSA",
      kid: keypair.kid,
    },
  });
  expect(result.status).toBe(200);
}

async function entitle(
  installationId: string,
  body: Record<string, unknown> = { ...REF_BODY, grants: [...REF_BODY.grants] },
): Promise<void> {
  const result = await controlFetch(entitlePath(installationId), { body });
  expect(result.status).toBe(200);
  expect(result.json).toEqual({
    installation_id: installationId,
    status: "active",
  });
}

async function enrollAndEntitleI0(): Promise<void> {
  await enroll(I0, "professional");
  await entitle(I0);
}

async function latestGrant(
  scope: string,
): Promise<Record<string, unknown> | null> {
  return queryOne(
    `SELECT * FROM capability_grant WHERE scope = ? ORDER BY changed_at DESC LIMIT 1`,
    [scope],
  );
}

describe("Stage 04 — cohort activate/promote and deprecate failures (S04-066…S04-085)", () => {
  it("S04-066 — Activate updates existing live grant", async () => {
    await enrollAndEntitleI0();
    const beforeGrant = await latestGrant(installationScope(I0));
    expect(beforeGrant).not.toBeNull();
    expect(beforeGrant?.capability_version).toBe("1.0.0");
    expect(beforeGrant?.revoked_at).toBeNull();
    const grantId = String(beforeGrant?.grant_id);
    const entitlementBefore = await getEntitlement(I0);
    const grantCountBefore = await count("capability_grant");

    await withTwoVersionRegistry(async () => {
      await waitForClockTick();
      const result = await controlFetch(activatePath("2.0.0"), {
        body: { installation_ids: [I0] },
      });
      assertEmptySuccess(result);

      const afterGrant = await queryOne(
        "SELECT * FROM capability_grant WHERE grant_id = ?",
        [grantId],
      );
      expect(afterGrant).not.toBeNull();
      expect(afterGrant?.grant_id).toBe(grantId);
      expect(afterGrant?.capability_version).toBe("2.0.0");
      expect(afterGrant?.changed_by).toBe(OPERATOR_ID);
      expect(afterGrant?.revoked_at).toBeNull();
      expectIsoTimestamp(afterGrant?.changed_at);
      expect(Date.parse(String(afterGrant?.changed_at))).toBeGreaterThan(
        Date.parse(String(beforeGrant?.changed_at)),
      );
      expect(await count("capability_grant")).toBe(grantCountBefore);

      const audits = await getAudits(
        "cohort_activate",
        "clinic.visit_summary@2.0.0",
      );
      expect(audits).toHaveLength(1);
      expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
      expect(audits[0]?.before_pointer).toBe(JSON.stringify({ [I0]: "1.0.0" }));
      expect(audits[0]?.after_pointer).toBe("2.0.0");

      expect(await getEntitlement(I0)).toEqual(entitlementBefore);
    });
  });

  it("S04-067 — Activate records cohort_name on audit target", async () => {
    await enrollAndEntitleI0();
    const beforeGrant = await latestGrant(installationScope(I0));
    expect(beforeGrant?.capability_version).toBe("1.0.0");

    await waitForClockTick();
    const result = await controlFetch(activatePath("1.0.0"), {
      body: { installation_ids: [I0], cohort_name: "pilot-clinics" },
    });
    assertEmptySuccess(result);

    const afterGrant = await queryOne(
      "SELECT * FROM capability_grant WHERE grant_id = ?",
      [String(beforeGrant?.grant_id)],
    );
    expect(afterGrant?.grant_id).toBe(beforeGrant?.grant_id);
    expect(afterGrant?.capability_version).toBe("1.0.0");
    expect(afterGrant?.changed_by).toBe(OPERATOR_ID);
    expectIsoTimestamp(afterGrant?.changed_at);
    expect(Date.parse(String(afterGrant?.changed_at))).toBeGreaterThan(
      Date.parse(String(beforeGrant?.changed_at)),
    );

    const audits = await getAudits(
      "cohort_activate",
      "clinic.visit_summary@1.0.0:pilot-clinics",
    );
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.after_pointer).toBe("1.0.0");
  });

  it("S04-068 — Activate inserts grant when none is live", async () => {
    await enroll(I1, "standard");
    const entitlementBefore = await getEntitlement(I1);
    expect(entitlementBefore?.status).toBe("pending");
    expect(await count("capability_grant")).toBe(0);

    const result = await controlFetch(activatePath("1.0.0"), {
      body: { installation_ids: [I1] },
    });
    assertEmptySuccess(result);

    const grants = await getGrants(installationScope(I1));
    expect(grants).toHaveLength(1);
    expect(grants[0]?.scope).toBe(installationScope(I1));
    expect(grants[0]?.capability_id).toBe(CAPABILITY_ID);
    expect(grants[0]?.capability_version).toBe("1.0.0");
    expect(grants[0]?.revoked_at).toBeNull();
    expect(grants[0]?.changed_by).toBe(OPERATOR_ID);
    expectCanonicalUuid(grants[0]?.grant_id);
    expectIsoTimestamp(grants[0]?.granted_at);
    expectIsoTimestamp(grants[0]?.changed_at);

    const audits = await getAudits(
      "cohort_activate",
      "clinic.visit_summary@1.0.0",
    );
    expect(audits).toHaveLength(1);
    expect(audits[0]?.before_pointer).toBeNull();
    expect(audits[0]?.after_pointer).toBe("1.0.0");
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);

    const entitlementAfter = await getEntitlement(I1);
    expect(entitlementAfter?.status).toBe("pending");
    expect(entitlementAfter).toEqual(entitlementBefore);
  });

  it("S04-069 — Activate mixed cohort update and insert", async () => {
    await enrollAndEntitleI0();
    await enroll(I1, "standard");
    const i0GrantBefore = await latestGrant(installationScope(I0));
    expect(i0GrantBefore?.capability_version).toBe("1.0.0");
    expect(await getGrants(installationScope(I1))).toEqual([]);
    const i1EntitlementBefore = await getEntitlement(I1);
    expect(i1EntitlementBefore?.status).toBe("pending");

    await withTwoVersionRegistry(async () => {
      const result = await controlFetch(activatePath("2.0.0"), {
        body: {
          installation_ids: [I0, I1],
          cohort_name: "pilot-clinics",
        },
      });
      assertEmptySuccess(result);

      const i0GrantAfter = await queryOne(
        "SELECT * FROM capability_grant WHERE grant_id = ?",
        [String(i0GrantBefore?.grant_id)],
      );
      expect(i0GrantAfter?.capability_version).toBe("2.0.0");
      expect(i0GrantAfter?.grant_id).toBe(i0GrantBefore?.grant_id);

      const i1Grants = await getGrants(installationScope(I1));
      expect(i1Grants).toHaveLength(1);
      expect(i1Grants[0]?.capability_version).toBe("2.0.0");
      expect(i1Grants[0]?.revoked_at).toBeNull();
      expect(i1Grants[0]?.scope).toBe(installationScope(I1));

      const audits = await getAudits(
        "cohort_activate",
        "clinic.visit_summary@2.0.0:pilot-clinics",
      );
      expect(audits).toHaveLength(1);
      expect(audits[0]?.before_pointer).toBe(
        JSON.stringify({ [I0]: "1.0.0", [I1]: null }),
      );
      expect(audits[0]?.after_pointer).toBe("2.0.0");
      expect(audits[0]?.operator_id).toBe(OPERATOR_ID);

      expect(await getEntitlement(I1)).toEqual(i1EntitlementBefore);
    });
  });

  it("S04-070 — Activate dedupes duplicate installation ids", async () => {
    await enroll(I1, "standard");
    expect(await count("capability_grant")).toBe(0);

    const result = await controlFetch(activatePath("1.0.0"), {
      body: { installation_ids: [I1, I1] },
    });
    assertEmptySuccess(result);

    const grants = await getGrants(installationScope(I1));
    expect(grants).toHaveLength(1);
    expect(grants[0]?.capability_version).toBe("1.0.0");
    expect(grants[0]?.revoked_at).toBeNull();
    expect(await count("capability_grant")).toBe(1);

    const audits = await getAudits(
      "cohort_activate",
      "clinic.visit_summary@1.0.0",
    );
    expect(audits).toHaveLength(1);
    expect(audits[0]?.before_pointer).toBeNull();
    expect(audits[0]?.after_pointer).toBe("1.0.0");
  });

  it("S04-071 — Activate already-current version re-stamps grant", async () => {
    await enrollAndEntitleI0();
    const beforeGrant = await latestGrant(installationScope(I0));
    expect(beforeGrant?.capability_version).toBe("1.0.0");
    const grantCountBefore = await count("capability_grant");

    await waitForClockTick();
    const result = await controlFetch(activatePath("1.0.0"), {
      body: { installation_ids: [I0] },
    });
    assertEmptySuccess(result);

    const afterGrant = await queryOne(
      "SELECT * FROM capability_grant WHERE grant_id = ?",
      [String(beforeGrant?.grant_id)],
    );
    expect(afterGrant?.grant_id).toBe(beforeGrant?.grant_id);
    expect(afterGrant?.capability_version).toBe("1.0.0");
    expect(afterGrant?.changed_by).toBe(OPERATOR_ID);
    expectIsoTimestamp(afterGrant?.changed_at);
    expect(Date.parse(String(afterGrant?.changed_at))).toBeGreaterThan(
      Date.parse(String(beforeGrant?.changed_at)),
    );
    expect(await count("capability_grant")).toBe(grantCountBefore);

    const audits = await getAudits(
      "cohort_activate",
      "clinic.visit_summary@1.0.0",
    );
    expect(audits).toHaveLength(1);
    expect(audits[0]?.before_pointer).toBe(JSON.stringify({ [I0]: "1.0.0" }));
    expect(audits[0]?.after_pointer).toBe("1.0.0");
  });

  it("S04-072 — Promote rejects missing operator bearer", async () => {
    await enrollAndEntitleI0();
    const grantsBefore = await queryAll(
      "SELECT * FROM capability_grant ORDER BY grant_id",
    );
    const promoteAuditsBefore = await count(
      "control_audit",
      "action = ?",
      ["cohort_promote"],
    );

    const result = await controlFetch(promotePath("1.0.0"), {
      auth: "none",
      body: {},
    });
    assertControlError(result, 401, "unauthorized");

    expect(
      await queryAll("SELECT * FROM capability_grant ORDER BY grant_id"),
    ).toEqual(grantsBefore);
    expect(await count("control_audit", "action = ?", ["cohort_promote"])).toBe(
      promoteAuditsBefore,
    );
  });

  it("S04-073 — Promote rejects unregistered capability version", async () => {
    await enrollAndEntitleI0();
    const grantsBefore = await queryAll(
      "SELECT * FROM capability_grant ORDER BY grant_id",
    );
    const auditCountBefore = await count("control_audit");

    const result = await controlFetch(promotePath("9.9.9"), {
      body: {},
    });
    assertControlError(result, 404, "capability_not_found");

    expect(
      await queryAll("SELECT * FROM capability_grant ORDER BY grant_id"),
    ).toEqual(grantsBefore);
    expect(await count("control_audit")).toBe(auditCountBefore);
  });

  it("S04-074 — Promote happy path ends cohort split", async () => {
    await enrollAndEntitleI0();
    await enroll(I1, "professional");

    await withTwoVersionRegistry(async () => {
      await entitle(I1, {
        ...REF_BODY,
        grants: [
          {
            capability_id: CAPABILITY_ID,
            capability_version: "2.0.0",
            scope: "plan",
          },
        ],
      });

      const i0GrantBefore = await latestGrant(installationScope(I0));
      expect(i0GrantBefore?.capability_version).toBe("1.0.0");
      const planGrantBefore = await latestGrant("plan:professional");
      expect(planGrantBefore?.capability_version).toBe("2.0.0");
      expect(planGrantBefore?.revoked_at).toBeNull();
      expect(await getGrants(installationScope(I1))).toEqual([]);

      const i0EntitlementBefore = await getEntitlement(I0);
      const i1EntitlementBefore = await getEntitlement(I1);
      expect(i0EntitlementBefore?.status).toBe("active");
      expect(i1EntitlementBefore?.status).toBe("active");

      const result = await controlFetch(promotePath("2.0.0"), { body: {} });
      assertEmptySuccess(result);

      const i0GrantAfter = await queryOne(
        "SELECT * FROM capability_grant WHERE grant_id = ?",
        [String(i0GrantBefore?.grant_id)],
      );
      expect(i0GrantAfter?.capability_version).toBe("2.0.0");
      expect(i0GrantAfter?.changed_by).toBe(OPERATOR_ID);
      expectIsoTimestamp(i0GrantAfter?.changed_at);

      const planGrantAfter = await queryOne(
        "SELECT * FROM capability_grant WHERE grant_id = ?",
        [String(planGrantBefore?.grant_id)],
      );
      expect(planGrantAfter?.capability_version).toBe("2.0.0");
      expect(planGrantAfter?.changed_by).toBe(OPERATOR_ID);

      const i1InstallationGrants = await getGrants(installationScope(I1));
      const liveI1 = i1InstallationGrants.filter((row) => row.revoked_at == null);
      expect(liveI1).toHaveLength(1);
      expect(liveI1[0]?.capability_version).toBe("2.0.0");
      expect(liveI1[0]?.changed_by).toBe(OPERATOR_ID);

      const liveGrants = await queryAll(
        `SELECT scope, capability_version FROM capability_grant
         WHERE capability_id = ? AND revoked_at IS NULL
           AND (scope LIKE 'installation:%' OR scope LIKE 'plan:%')`,
        [CAPABILITY_ID],
      );
      expect(liveGrants.length).toBeGreaterThan(0);
      for (const grant of liveGrants) {
        expect(grant.capability_version).toBe("2.0.0");
      }

      const audits = await getAudits(
        "cohort_promote",
        "clinic.visit_summary@2.0.0",
      );
      expect(audits).toHaveLength(1);
      expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
      expect(audits[0]?.after_pointer).toBe("2.0.0");
      const beforePointer = JSON.parse(String(audits[0]?.before_pointer)) as {
        installation: Array<{ scope: string; version: string }>;
        plan: Array<{ scope: string; version: string }>;
      };
      expect(beforePointer.installation).toEqual(
        expect.arrayContaining([
          { scope: installationScope(I0), version: "1.0.0" },
        ]),
      );
      expect(beforePointer.plan).toEqual(
        expect.arrayContaining([
          { scope: "plan:professional", version: "2.0.0" },
        ]),
      );

      expect(await getEntitlement(I0)).toEqual(i0EntitlementBefore);
      expect(await getEntitlement(I1)).toEqual(i1EntitlementBefore);
      expect(
        await count("entitlement", "status = ?", ["pending"]),
      ).toBe(0);
    });
  });

  it("S04-075 — Promote with empty fleet writes only audit", async () => {
    expect(await count("installation")).toBe(0);
    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit")).toBe(0);

    const result = await controlFetch(promotePath("1.0.0"), { body: {} });
    assertEmptySuccess(result);

    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit")).toBe(1);

    const audits = await getAudits(
      "cohort_promote",
      "clinic.visit_summary@1.0.0",
    );
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.before_pointer).toBe(
      JSON.stringify({ installation: [], plan: [] }),
    );
    expect(audits[0]?.after_pointer).toBe("1.0.0");
  });

  it("S04-076 — Promote skips entitlements lacking capability", async () => {
    await enroll(I0, "professional");
    await entitle(I0, { ...REF_BODY, allowed_capabilities: [] });

    const entitlementBefore = await getEntitlement(I0);
    expect(entitlementBefore?.status).toBe("active");
    const allowList = entitlementBefore?.allowed_capabilities;
    if (typeof allowList === "string") {
      expect(JSON.parse(allowList)).toEqual([]);
    } else {
      expect(allowList).toEqual([]);
    }

    const grantBefore = await latestGrant(installationScope(I0));
    expect(grantBefore?.capability_version).toBe("1.0.0");
    expect(await count("capability_grant", "scope LIKE 'plan:%'")).toBe(0);

    await withTwoVersionRegistry(async () => {
      const result = await controlFetch(promotePath("2.0.0"), { body: {} });
      assertEmptySuccess(result);

      const grantAfter = await queryOne(
        "SELECT * FROM capability_grant WHERE grant_id = ?",
        [String(grantBefore?.grant_id)],
      );
      expect(grantAfter?.capability_version).toBe("2.0.0");
      expect(grantAfter?.grant_id).toBe(grantBefore?.grant_id);

      expect(await count("capability_grant", "scope LIKE 'plan:%'")).toBe(0);
      expect(await count("capability_grant", "scope = ?", ["plan:professional"])).toBe(
        0,
      );
      expect(await getGrants(installationScope(I0))).toHaveLength(1);
      expect(await getEntitlement(I0)).toEqual(entitlementBefore);
    });
  });

  it("S04-077 — Promote skips pending entitlements", async () => {
    await enroll(I1, "standard");
    await enrollAndEntitleI0();
    const i1EntitlementBefore = await getEntitlement(I1);
    expect(i1EntitlementBefore?.status).toBe("pending");
    expect(await getGrants(installationScope(I1))).toEqual([]);

    const i0GrantBefore = await latestGrant(installationScope(I0));
    expect(i0GrantBefore?.capability_version).toBe("1.0.0");

    await withTwoVersionRegistry(async () => {
      const result = await controlFetch(promotePath("2.0.0"), { body: {} });
      assertEmptySuccess(result);

      const i0GrantAfter = await queryOne(
        "SELECT * FROM capability_grant WHERE grant_id = ?",
        [String(i0GrantBefore?.grant_id)],
      );
      expect(i0GrantAfter?.capability_version).toBe("2.0.0");

      expect(await getGrants(installationScope(I1))).toEqual([]);
      expect(
        await count("capability_grant", "scope = ?", [installationScope(I1)]),
      ).toBe(0);
      expect(await getEntitlement(I1)).toEqual(i1EntitlementBefore);
    });
  });

  it("S04-078 — Promote ignores revoked grants", async () => {
    await enrollAndEntitleI0();
    await seedSql([
      {
        sql: `UPDATE capability_grant SET revoked_at = '2026-08-15T00:00:00.000Z' WHERE scope = 'installation:${I0}'`,
      },
    ]);

    const revokedBefore = await latestGrant(installationScope(I0));
    expect(revokedBefore?.capability_version).toBe("1.0.0");
    expect(revokedBefore?.revoked_at).toBe("2026-08-15T00:00:00.000Z");
    const revokedGrantId = String(revokedBefore?.grant_id);

    await withTwoVersionRegistry(async () => {
      const result = await controlFetch(promotePath("2.0.0"), { body: {} });
      assertEmptySuccess(result);

      const revokedAfter = await queryOne(
        "SELECT * FROM capability_grant WHERE grant_id = ?",
        [revokedGrantId],
      );
      expect(revokedAfter?.capability_version).toBe("1.0.0");
      expect(revokedAfter?.revoked_at).toBe("2026-08-15T00:00:00.000Z");
      expect(revokedAfter?.grant_id).toBe(revokedGrantId);

      const liveInstallation = await queryAll(
        `SELECT * FROM capability_grant
         WHERE scope = ? AND revoked_at IS NULL`,
        [installationScope(I0)],
      );
      expect(liveInstallation).toHaveLength(1);
      expect(liveInstallation[0]?.grant_id).not.toBe(revokedGrantId);
      expect(liveInstallation[0]?.capability_version).toBe("2.0.0");
      expect(liveInstallation[0]?.capability_id).toBe(CAPABILITY_ID);
      expect(liveInstallation[0]?.changed_by).toBe(OPERATOR_ID);
      expect(liveInstallation[0]?.revoked_at).toBeNull();
    });
  });

  it("S04-079 — Promote ignores the request body", async () => {
    await enrollAndEntitleI0();
    const grantBefore = await latestGrant(installationScope(I0));
    expect(grantBefore?.capability_version).toBe("1.0.0");

    await waitForClockTick();
    const result = await controlFetch(promotePath("1.0.0"), {
      body: "not json{",
    });
    assertEmptySuccess(result);

    const grantAfter = await queryOne(
      "SELECT * FROM capability_grant WHERE grant_id = ?",
      [String(grantBefore?.grant_id)],
    );
    expect(grantAfter?.grant_id).toBe(grantBefore?.grant_id);
    expect(grantAfter?.capability_version).toBe("1.0.0");
    expect(grantAfter?.changed_by).toBe(OPERATOR_ID);
    expectIsoTimestamp(grantAfter?.changed_at);
    expect(Date.parse(String(grantAfter?.changed_at))).toBeGreaterThan(
      Date.parse(String(grantBefore?.changed_at)),
    );

    const audits = await getAudits(
      "cohort_promote",
      "clinic.visit_summary@1.0.0",
    );
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.after_pointer).toBe("1.0.0");
  });

  it("S04-080 — Deprecate rejects missing operator bearer", async () => {
    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit", "action = ?", ["deprecate"])).toBe(0);

    const result = await controlFetch(deprecatePath("1.0.0"), {
      auth: "none",
      body: { successor_id: "clinic.visit_summary" },
    });
    assertControlError(result, 401, "unauthorized");

    expect(await count("capability_grant")).toBe(0);
    expect(await count("capability_grant", "scope = ?", ["global"])).toBe(0);
    expect(await count("control_audit", "action = ?", ["deprecate"])).toBe(0);
  });

  it("S04-081 — Deprecate rejects unregistered capability version", async () => {
    const grantCountBefore = await count("capability_grant");
    const auditCountBefore = await count("control_audit");

    const result = await controlFetch(deprecatePath("9.9.9"), {
      body: { successor_id: "clinic.visit_summary" },
    });
    assertControlError(result, 404, "capability_not_found");

    expect(await count("capability_grant")).toBe(grantCountBefore);
    expect(await count("control_audit")).toBe(auditCountBefore);
    expect(await count("control_audit", "action = ?", ["deprecate"])).toBe(0);
  });

  it("S04-082 — Deprecate rejects a non-JSON body", async () => {
    const result = await controlFetch(deprecatePath("1.0.0"), {
      body: '{"successor_id":',
    });
    assertControlError(result, 400, "invalid_json");

    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit", "action = ?", ["deprecate"])).toBe(0);
  });

  it("S04-083 — Deprecate rejects a missing successor_id", async () => {
    const result = await controlFetch(deprecatePath("1.0.0"), {
      body: {},
    });
    assertControlError(result, 400, "missing_successor_id");

    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit", "action = ?", ["deprecate"])).toBe(0);
  });

  it("S04-084 — Deprecate rejects an empty-string successor_id", async () => {
    const result = await controlFetch(deprecatePath("1.0.0"), {
      body: { successor_id: "" },
    });
    assertControlError(result, 400, "missing_successor_id");

    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit", "action = ?", ["deprecate"])).toBe(0);
  });

  it("S04-085 — Deprecate rejects an unknown successor", async () => {
    const result = await controlFetch(deprecatePath("1.0.0"), {
      body: { successor_id: "clinic.not_in_registry" },
    });
    assertControlError(result, 400, "unknown_successor");

    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit", "action = ?", ["deprecate"])).toBe(0);
  });
});
