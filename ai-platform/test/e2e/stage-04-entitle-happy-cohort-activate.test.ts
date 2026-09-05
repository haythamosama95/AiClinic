import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  controlFetch,
  count,
  createCapabilityRegistry,
  dispatchControl,
  diskIoError,
  env,
  GATEWAY_ORIGIN,
  generateTestKeypair,
  getAudits,
  getEntitlement,
  getGrants,
  loadManifest,
  OPERATOR_BEARER,
  OPERATOR_ID,
  queryOne,
  readHttpResult,
  resetE2eState,
  seedSql,
  setCapabilityRegistry,
  wrapD1,
  type HttpResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const I0 = "0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b";
const UNKNOWN_INSTALLATION_ID = "00000000-0000-0000-0000-000000000000";
const INSTALLATION_SCOPE = `installation:${I0}`;
const PLAN_SCOPE = "plan:professional";

const ISO_8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const CLOCK_SKEW_MS = 15_000;
const CANONICAL_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Catalog REF-BODY (doc §6 visit-summary entitle body). */
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

const ENTITLE_SUCCESS_BODY = {
  installation_id: I0,
  status: "active",
} as const;

const PUBLISHED_VISIT_SUMMARY_JSON: Record<string, unknown> = {
  Identity: {
    capabilityId: "clinic.visit_summary",
    version: "1.0.0",
    title: "Visit summary",
    lifecycleState: "active",
    successorId: null,
  },
  Access: {
    requiredCapabilityScope: "ai.visit_summary",
    minimumPlanTier: "standard",
    allowedStaffRoles: ["administrator", "clinician", "nurse"],
    killSwitchFlag: false,
  },
  Interaction: {
    interactionMode: "single_shot",
  },
  Input: {
    userIntentShape: "plain_text",
    priorTurnShape: null,
    sizeLimits: {
      maxChars: 8000,
    },
    allowedLanguages: ["en"],
  },
  "Context requirements": [
    {
      key: "visit.chief_complaint@v1",
      required: true,
      shapeRef: "visit.chief_complaint@v1",
      maxSize: 4096,
    },
  ],
  "Prompt binding": {
    systemInstructionArtifactRef: "clinic.visit_summary/system@v1",
    businessRuleFragmentRefs: ["clinic.visit_summary/rules-visit-summary@v1"],
    contextRenderingTemplateRef:
      "clinic.visit_summary/template-visit-summary@v1",
    outputFormatInstructionDerivationRule: "derive_from_output_mode",
  },
  Output: {
    mode: "prose",
    outputSchemaRef: null,
    businessValidationRuleRefs: [],
    repairPolicy: {
      allowed: false,
      maxAttempts: 0,
    },
  },
  Routing: {
    routingPolicyRef: "routing/standard",
    requiredProviderFeatures: {
      structuredOutput: false,
      contextWindow: 32000,
      language: "en",
    },
    latencyClass: "standard",
    degradedTierPolicy: "fallback_chain",
  },
  Economics: {
    maxInputTokens: 8000,
    maxOutputTokens: 1024,
    perRequestTokenCeiling: 9024,
    quotaWeight: 1,
  },
  Governance: {
    acceptanceMode: "advisory_display",
    retentionClass: "diagnostic_30d",
    evalSuiteRef: "evals/visit-summary@v1",
  },
};

function publishedVisitSummaryWire(): Record<string, unknown> {
  return structuredClone(PUBLISHED_VISIT_SUMMARY_JSON);
}

function visitSummaryV2Wire(): Record<string, unknown> {
  const wire = publishedVisitSummaryWire();
  wire.Identity = {
    ...(wire.Identity as Record<string, unknown>),
    version: "2.0.0",
  };
  return wire;
}

function restorePublishedRegistry(): void {
  setCapabilityRegistry(
    createCapabilityRegistry([loadManifest(publishedVisitSummaryWire())]),
    { replace: true },
  );
}

function installTwoVersionRegistry(): void {
  setCapabilityRegistry(
    createCapabilityRegistry([
      loadManifest(publishedVisitSummaryWire()),
      loadManifest(visitSummaryV2Wire()),
    ]),
    { replace: true },
  );
}

function entitlePath(installationId: string = I0): string {
  return `/control/installations/${installationId}/entitle`;
}

function activatePath(capabilityId: string, version: string): string {
  return `/control/capabilities/${capabilityId}/versions/${version}/activate`;
}

function refBodyWith(overrides: Record<string, unknown>): Record<string, unknown> {
  return { ...REF_BODY, ...overrides };
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

function assertEntitleSuccess(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual(ENTITLE_SUCCESS_BODY);
  expect(result.text).toBe(JSON.stringify(ENTITLE_SUCCESS_BODY));
}

function expectIsoApproxNow(value: unknown): string {
  expect(typeof value).toBe("string");
  const iso = String(value);
  expect(iso).toMatch(ISO_8601);
  const parsed = Date.parse(iso);
  expect(Number.isNaN(parsed)).toBe(false);
  expect(Math.abs(Date.now() - parsed)).toBeLessThan(CLOCK_SKEW_MS);
  return iso;
}

function expectCanonicalUuid(value: unknown): string {
  expect(typeof value).toBe("string");
  const id = String(value);
  expect(id).toMatch(CANONICAL_UUID_RE);
  return id;
}

function jsonText(value: unknown): string {
  return typeof value === "string" ? value : JSON.stringify(value);
}

async function enrollI0(): Promise<void> {
  const keypair = await generateTestKeypair();
  const result = await controlFetch(`/control/installations/${I0}/enroll`, {
    body: {
      org_id: crypto.randomUUID(),
      display_name: "Verify Clinic",
      region: "eu-central",
      plan: "professional",
      public_key: keypair.publicKeyB64,
      algorithm: "EdDSA",
      kid: keypair.kid,
    },
  });
  expect(result.status).toBe(200);
}

async function entitleI0(
  body: Record<string, unknown> = REF_BODY,
): Promise<HttpResult> {
  return controlFetch(entitlePath(), { body });
}

async function enrollAndEntitleI0(): Promise<void> {
  await enrollI0();
  assertEntitleSuccess(await entitleI0());
}

async function installationStatus(): Promise<string | null> {
  const row = await queryOne<{ status: string }>(
    "SELECT status FROM installation WHERE installation_id = ?",
    [I0],
  );
  return row?.status ?? null;
}

async function assertPendingEntitleRejected(): Promise<void> {
  const entitlement = await getEntitlement(I0);
  expect(entitlement).not.toBeNull();
  expect(entitlement?.status).toBe("pending");
  expect(entitlement?.plan).toBe("professional");
  expect(Number(entitlement?.request_quota)).toBe(0);
  expect(Number(entitlement?.token_budget)).toBe(0);
  expect(Number(entitlement?.cost_budget)).toBe(0);
  expect(jsonText(entitlement?.allowed_capabilities)).toBe("[]");
  expect(Number(entitlement?.soft_threshold)).toBe(0);
  expect(await count("capability_grant")).toBe(0);
  expect(await count("control_audit", "action = ?", ["entitle"])).toBe(0);
}

async function assertActiveEntitlementFromRefBody(): Promise<Record<string, unknown>> {
  const entitlement = await getEntitlement(I0);
  expect(entitlement).not.toBeNull();
  expect(entitlement?.installation_id).toBe(I0);
  expect(entitlement?.plan).toBe("professional");
  expect(entitlement?.period_start).toBe(REF_BODY.period_start);
  expect(entitlement?.period_end).toBe(REF_BODY.period_end);
  expect(Number(entitlement?.request_quota)).toBe(1000);
  expect(Number(entitlement?.token_budget)).toBe(500000);
  expect(Number(entitlement?.cost_budget)).toBe(50);
  expect(jsonText(entitlement?.allowed_capabilities)).toBe(
    '["clinic.visit_summary"]',
  );
  expect(Number(entitlement?.soft_threshold)).toBe(0.8);
  expect(entitlement?.status).toBe("active");
  return entitlement!;
}

async function assertEntitleAuditRow(): Promise<Record<string, unknown>> {
  const audits = await getAudits("entitle", I0);
  expect(audits).toHaveLength(1);
  const audit = audits[0];
  expectCanonicalUuid(audit.audit_id);
  expect(audit.operator_id).toBe(OPERATOR_ID);
  expect(audit.action).toBe("entitle");
  expect(audit.target).toBe(I0);
  expect(audit.before_pointer).toBeNull();
  expect(jsonText(audit.after_pointer)).toBe('["clinic.visit_summary"]');
  expectIsoApproxNow(audit.recorded_at);
  return audit;
}

async function assertInstallationGrant(
  version: string = "1.0.0",
): Promise<Record<string, unknown>> {
  const grants = await getGrants(INSTALLATION_SCOPE);
  expect(grants).toHaveLength(1);
  const grant = grants[0];
  expectCanonicalUuid(grant.grant_id);
  expect(grant.scope).toBe(INSTALLATION_SCOPE);
  expect(grant.capability_id).toBe("clinic.visit_summary");
  expect(grant.capability_version).toBe(version);
  expectIsoApproxNow(grant.granted_at);
  expect(grant.revoked_at).toBeNull();
  expectIsoApproxNow(grant.changed_at);
  expect(grant.granted_at).toBe(grant.changed_at);
  expect(grant.changed_by).toBe(OPERATOR_ID);
  expect(grant.lifecycle_state).toBeNull();
  expect(grant.successor_id).toBeNull();
  expect(grant.deprecated_at).toBeNull();
  expect(grant.retire_after).toBeNull();
  return grant;
}

async function assertNoCohortActivateSideEffects(
  grantBefore: Record<string, unknown>,
): Promise<void> {
  expect(await getGrants(INSTALLATION_SCOPE)).toEqual([grantBefore]);
  expect(await count("control_audit", "action = ?", ["cohort_activate"])).toBe(
    0,
  );
}

describe("Stage 04 — entitle happy path and cohort activate (S04-041…S04-065)", () => {
  it("S04-041 — Grant missing capability_id", async () => {
    await enrollI0();

    const result = await entitleI0(
      refBodyWith({
        grants: [{ capability_version: "1.0.0" }],
      }),
    );

    assertControlError(result, 400, "invalid_payload");
    await assertPendingEntitleRejected();
  });

  it("S04-042 — Whitespace-only capability_id", async () => {
    await enrollI0();

    const result = await entitleI0(
      refBodyWith({
        grants: [{ capability_id: "   ", capability_version: "1.0.0" }],
      }),
    );

    assertControlError(result, 400, "invalid_payload");
    await assertPendingEntitleRejected();
  });

  it("S04-043 — Non-string capability_version", async () => {
    await enrollI0();

    const result = await entitleI0(
      refBodyWith({
        grants: [
          {
            capability_id: "clinic.visit_summary",
            capability_version: 1.0,
          },
        ],
      }),
    );

    assertControlError(result, 400, "invalid_payload");
    await assertPendingEntitleRejected();
  });

  it("S04-044 — Grant scope global", async () => {
    await enrollI0();

    const result = await entitleI0(
      refBodyWith({
        grants: [
          {
            capability_id: "clinic.visit_summary",
            capability_version: "1.0.0",
            scope: "global",
          },
        ],
      }),
    );

    assertControlError(result, 400, "invalid_payload");
    await assertPendingEntitleRejected();
  });

  it("S04-045 — Mis-cased grant scope Plan", async () => {
    await enrollI0();

    const result = await entitleI0(
      refBodyWith({
        grants: [
          {
            capability_id: "clinic.visit_summary",
            capability_version: "1.0.0",
            scope: "Plan",
          },
        ],
      }),
    );

    assertControlError(result, 400, "invalid_payload");
    await assertPendingEntitleRejected();
  });

  it("S04-046 — Multi-grant one invalid inserts zero grants", async () => {
    await enrollI0();

    const result = await entitleI0(
      refBodyWith({
        grants: [
          {
            capability_id: "clinic.visit_summary",
            capability_version: "1.0.0",
          },
          { capability_id: "clinic.chat_assistant" },
        ],
      }),
    );

    assertControlError(result, 400, "invalid_payload");
    await assertPendingEntitleRejected();
    expect(
      await count("capability_grant", "capability_id = ?", [
        "clinic.visit_summary",
      ]),
    ).toBe(0);
  });

  it("S04-047 — Unknown installation id", async () => {
    await enrollI0();
    const entitlementBefore = await getEntitlement(I0);

    const result = await controlFetch(entitlePath(UNKNOWN_INSTALLATION_ID), {
      body: REF_BODY,
    });

    assertControlError(result, 404, "installation_not_found");
    expect(await getEntitlement(I0)).toEqual(entitlementBefore);
    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit", "action = ?", ["entitle"])).toBe(0);
  });

  it("S04-048 — Missing entitlement row", async () => {
    await enrollI0();
    await seedSql([
      {
        sql: "DELETE FROM entitlement WHERE installation_id = ?",
        params: [I0],
      },
    ]);

    const result = await entitleI0();

    assertControlError(result, 404, "entitlement_not_found");
    expect(await getEntitlement(I0)).toBeNull();
    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit", "action = ?", ["entitle"])).toBe(0);
    expect(await count("installation", "installation_id = ?", [I0])).toBe(1);
  });

  it("S04-049 — Suspended entitlement is not_pending", async () => {
    await enrollI0();
    await seedSql([
      {
        sql: "UPDATE entitlement SET status = 'suspended' WHERE installation_id = ?",
        params: [I0],
      },
    ]);
    const entitlementBefore = await getEntitlement(I0);

    const result = await entitleI0();

    assertControlError(result, 409, "not_pending");
    expect(await getEntitlement(I0)).toEqual(entitlementBefore);
    expect(entitlementBefore?.status).toBe("suspended");
    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit", "action = ?", ["entitle"])).toBe(0);
  });

  it("S04-050 — Entitle happy path REF-BODY", async () => {
    await enrollI0();
    expect(await installationStatus()).toBe("active");

    const result = await entitleI0(REF_BODY);

    assertEntitleSuccess(result);
    await assertActiveEntitlementFromRefBody();
    await assertInstallationGrant("1.0.0");
    await assertEntitleAuditRow();
    expect(await count("capability_grant")).toBe(1);
    expect(await installationStatus()).toBe("active");
    expect(await count("routing_policy")).toBe(0);
  });

  it("S04-051 — Re-entitle after active is not_pending", async () => {
    await enrollAndEntitleI0();
    const entitlementBefore = await getEntitlement(I0);
    const grantsBefore = await getGrants(INSTALLATION_SCOPE);
    const auditsBefore = await getAudits("entitle", I0);
    expect(grantsBefore).toHaveLength(1);
    expect(auditsBefore).toHaveLength(1);

    const result = await entitleI0(REF_BODY);

    assertControlError(result, 409, "not_pending");
    expect(await getEntitlement(I0)).toEqual(entitlementBefore);
    expect(entitlementBefore?.status).toBe("active");
    expect(await getGrants(INSTALLATION_SCOPE)).toEqual(grantsBefore);
    expect(await getAudits("entitle", I0)).toEqual(auditsBefore);
    expect(await count("capability_grant")).toBe(1);
  });

  it("S04-052 — Entitle while installation is suspended", async () => {
    await enrollI0();
    const suspend = await controlFetch(`/control/installations/${I0}/suspend`, {
      body: {},
    });
    expect(suspend.status).toBe(200);
    expect(await installationStatus()).toBe("suspended");
    const entitlementBefore = await getEntitlement(I0);
    expect(entitlementBefore?.status).toBe("pending");

    const result = await entitleI0(REF_BODY);

    assertEntitleSuccess(result);
    await assertActiveEntitlementFromRefBody();
    await assertInstallationGrant("1.0.0");
    await assertEntitleAuditRow();
    expect(await installationStatus()).toBe("suspended");
    expect(await count("routing_policy")).toBe(0);
  });

  it("S04-053 — Plan-scope grant writes plan:professional", async () => {
    await enrollI0();

    const result = await entitleI0(
      refBodyWith({
        grants: [
          {
            capability_id: "clinic.visit_summary",
            capability_version: "1.0.0",
            scope: "plan",
          },
        ],
      }),
    );

    assertEntitleSuccess(result);
    await assertActiveEntitlementFromRefBody();
    expect(await getGrants(INSTALLATION_SCOPE)).toEqual([]);
    const planGrants = await getGrants(PLAN_SCOPE);
    expect(planGrants).toHaveLength(1);
    const grant = planGrants[0];
    expectCanonicalUuid(grant.grant_id);
    expect(grant.scope).toBe(PLAN_SCOPE);
    expect(grant.capability_id).toBe("clinic.visit_summary");
    expect(grant.capability_version).toBe("1.0.0");
    expectIsoApproxNow(grant.granted_at);
    expect(grant.revoked_at).toBeNull();
    expect(grant.changed_by).toBe(OPERATOR_ID);
    await assertEntitleAuditRow();
    expect(await count("capability_grant")).toBe(1);
  });

  it("S04-054 — Live plan grant is not duplicated", async () => {
    await enrollI0();
    await seedSql([
      {
        sql: `INSERT INTO capability_grant (
                grant_id, scope, capability_id, capability_version,
                granted_at, revoked_at, changed_at, changed_by
              ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
        params: [
          "seed-plan-grant-1",
          PLAN_SCOPE,
          "clinic.visit_summary",
          "1.0.0",
          "2026-07-01T00:00:00.000Z",
          "2026-07-01T00:00:00.000Z",
          "seed",
        ],
      },
    ]);
    const seeded = (await getGrants(PLAN_SCOPE))[0];

    const result = await entitleI0(
      refBodyWith({
        grants: [
          {
            capability_id: "clinic.visit_summary",
            capability_version: "1.0.0",
            scope: "plan",
          },
        ],
      }),
    );

    assertEntitleSuccess(result);
    await assertActiveEntitlementFromRefBody();
    const planGrants = await getGrants(PLAN_SCOPE);
    expect(planGrants).toHaveLength(1);
    expect(planGrants[0]).toEqual(seeded);
    expect(planGrants[0].grant_id).toBe("seed-plan-grant-1");
    expect(planGrants[0].changed_by).toBe("seed");
    expect(await getGrants(INSTALLATION_SCOPE)).toEqual([]);
    expect(await count("capability_grant")).toBe(1);
    await assertEntitleAuditRow();
  });

  it("S04-055 — Mixed installation and plan grants", async () => {
    installTwoVersionRegistry();
    try {
      await enrollI0();

      const result = await entitleI0(
        refBodyWith({
          grants: [
            {
              capability_id: "clinic.visit_summary",
              capability_version: "1.0.0",
              scope: "installation",
            },
            {
              capability_id: "clinic.visit_summary",
              capability_version: "2.0.0",
              scope: "plan",
            },
          ],
        }),
      );

      assertEntitleSuccess(result);
      await assertActiveEntitlementFromRefBody();
      await assertInstallationGrant("1.0.0");
      const planGrants = await getGrants(PLAN_SCOPE);
      expect(planGrants).toHaveLength(1);
      expect(planGrants[0].scope).toBe(PLAN_SCOPE);
      expect(planGrants[0].capability_id).toBe("clinic.visit_summary");
      expect(planGrants[0].capability_version).toBe("2.0.0");
      expect(planGrants[0].revoked_at).toBeNull();
      expect(planGrants[0].changed_by).toBe(OPERATOR_ID);
      expect(await count("capability_grant")).toBe(2);
      await assertEntitleAuditRow();
    } finally {
      restorePublishedRegistry();
    }
  });

  it("S04-056 — Second entitlement row violates UNIQUE(installation_id)", async () => {
    await enrollAndEntitleI0();
    expect(await count("entitlement", "installation_id = ?", [I0])).toBe(1);

    // [SEED-probe]: no HTTP route inserts a second entitlement; catch the D1
    // UNIQUE violation on idx_entitlement_installation_id directly.
    let thrown: unknown;
    try {
      await env.DB.prepare(
        `INSERT INTO entitlement (
           entitlement_id, installation_id, plan, period_start, period_end,
           request_quota, token_budget, cost_budget, allowed_capabilities,
           soft_threshold, status
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
        .bind(
          "probe-dup-entitlement",
          I0,
          "professional",
          "2026-08-01T00:00:00.000Z",
          "2026-09-01T00:00:00.000Z",
          0,
          0,
          0,
          "[]",
          0,
          "pending",
        )
        .run();
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeDefined();
    const message = thrown instanceof Error ? thrown.message : String(thrown);
    expect(message).toMatch(/UNIQUE constraint failed/i);
    expect(message).toMatch(/idx_entitlement_installation_id|installation_id/i);
    expect(await count("entitlement", "installation_id = ?", [I0])).toBe(1);
    expect(await count("entitlement")).toBe(1);
  });

  it("S04-057 — Entitle batch failure returns storage_error", async () => {
    await enrollI0();

    // Register 5 #19: real D1 does not fail on demand. wrapD1 batchThrow is
    // the documented seam. SELF.fetch cannot swap DB; dispatchControl injects
    // the wrapped binding (worker.fetch ignores its _bindings argument).
    const db = wrapD1(env.DB, { batchThrow: diskIoError() });
    const response = await dispatchControl(
      new Request(`${GATEWAY_ORIGIN}/control/installations/${I0}/entitle`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${OPERATOR_BEARER}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(REF_BODY),
      }),
      { DB: db },
    );
    const result = await readHttpResult(response);

    assertControlError(result, 500, "storage_error");
    await assertPendingEntitleRejected();
  });

  it("S04-058 — Cohort activate without operator bearer", async () => {
    installTwoVersionRegistry();
    try {
      await enrollAndEntitleI0();
      const grantBefore = await assertInstallationGrant("1.0.0");

      const result = await controlFetch(
        activatePath("clinic.visit_summary", "2.0.0"),
        {
          auth: "none",
          body: { installation_ids: [I0] },
        },
      );

      assertControlError(result, 401, "unauthorized");
      await assertNoCohortActivateSideEffects(grantBefore);
    } finally {
      restorePublishedRegistry();
    }
  });

  it("S04-059 — Activate unregistered version 9.9.9", async () => {
    await enrollAndEntitleI0();
    const grantBefore = await assertInstallationGrant("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "9.9.9"),
      { body: { installation_ids: [I0] } },
    );

    assertControlError(result, 404, "capability_not_found");
    await assertNoCohortActivateSideEffects(grantBefore);
  });

  it("S04-060 — Activate unregistered capability id", async () => {
    await enrollAndEntitleI0();
    const grantBefore = await assertInstallationGrant("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.not_in_registry", "1.0.0"),
      { body: { installation_ids: [I0] } },
    );

    assertControlError(result, 404, "capability_not_found");
    await assertNoCohortActivateSideEffects(grantBefore);
  });

  it("S04-061 — Activate non-JSON body", async () => {
    await enrollAndEntitleI0();
    const grantBefore = await assertInstallationGrant("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "1.0.0"),
      { body: '{"installation_ids":' },
    );

    assertControlError(result, 400, "invalid_json");
    await assertNoCohortActivateSideEffects(grantBefore);
  });

  it("S04-062 — Activate missing installation_ids", async () => {
    await enrollAndEntitleI0();
    const grantBefore = await assertInstallationGrant("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "1.0.0"),
      { body: { cohort_name: "pilot-clinics" } },
    );

    assertControlError(result, 400, "missing_installation_ids");
    await assertNoCohortActivateSideEffects(grantBefore);
  });

  it("S04-063 — Activate empty installation_ids", async () => {
    await enrollAndEntitleI0();
    const grantBefore = await assertInstallationGrant("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "1.0.0"),
      { body: { installation_ids: [] } },
    );

    assertControlError(result, 400, "missing_installation_ids");
    await assertNoCohortActivateSideEffects(grantBefore);
  });

  it("S04-064 — Activate installation_ids as string", async () => {
    await enrollAndEntitleI0();
    const grantBefore = await assertInstallationGrant("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "1.0.0"),
      { body: { installation_ids: I0 } },
    );

    assertControlError(result, 400, "missing_installation_ids");
    await assertNoCohortActivateSideEffects(grantBefore);
  });

  it("S04-065 — Activate known plus unknown installation", async () => {
    await enrollAndEntitleI0();
    const grantBefore = await assertInstallationGrant("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "1.0.0"),
      {
        body: {
          installation_ids: [I0, UNKNOWN_INSTALLATION_ID],
        },
      },
    );

    assertControlError(result, 404, "installation_not_found");
    await assertNoCohortActivateSideEffects(grantBefore);
  });
});
