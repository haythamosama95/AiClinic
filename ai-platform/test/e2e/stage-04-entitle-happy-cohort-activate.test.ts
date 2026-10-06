import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  controlFetch,
  count,
  coverClinic,
  createCapabilityRegistry,
  getGrants,
  loadManifest,
  newClinic,
  newScenario,
  resetE2eState,
  seedSql,
  setCapabilityRegistry,
  VENDOR_OPERATOR_EMAIL,
  type HttpResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

let I0 = "0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b";
const UNKNOWN_INSTALLATION_ID = "00000000-0000-0000-0000-000000000000";
function installationScope(): string {
  return `installation:${I0}`;
}

const CANONICAL_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const ENTITLE_PAYLOAD = {
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
      scope: "installation" as const,
    },
  ],
};

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

function activatePath(capabilityId: string, version: string): string {
  return `/control/capabilities/${capabilityId}/versions/${version}/activate`;
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

function expectCanonicalUuid(value: unknown): string {
  expect(typeof value).toBe("string");
  const id = String(value);
  expect(id).toMatch(CANONICAL_UUID_RE);
  return id;
}

async function enrollAndEntitleI0(): Promise<void> {
  const scenario = await newScenario();
  await newClinic(scenario);
  I0 = scenario.installationId;
  await coverClinic(scenario, {
    capabilities: ENTITLE_PAYLOAD.allowed_capabilities,
    max_allowance_per_month: ENTITLE_PAYLOAD.request_quota,
  });
  await seedSql([
    {
      sql: `INSERT INTO capability_grant (
              grant_id, scope, capability_id, capability_version,
              granted_at, revoked_at, changed_at, changed_by
            ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
      params: [
        crypto.randomUUID(),
        installationScope(),
        "clinic.visit_summary",
        "1.0.0",
        new Date().toISOString(),
        new Date().toISOString(),
        VENDOR_OPERATOR_EMAIL,
      ],
    },
  ]);
}

async function grantBaseline(version = "1.0.0"): Promise<{
  grant: Record<string, unknown>;
  cohortAudits: number;
}> {
  return {
    grant: await assertInstallationGrant(version),
    cohortAudits: await count("control_audit", "action = ?", ["cohort_activate"]),
  };
}

async function assertInstallationGrant(
  version: string = "1.0.0",
): Promise<Record<string, unknown>> {
  const grants = await getGrants(installationScope());
  expect(grants).toHaveLength(1);
  const grant = grants[0];
  expectCanonicalUuid(grant.grant_id);
  expect(grant.scope).toBe(installationScope());
  expect(grant.capability_id).toBe("clinic.visit_summary");
  expect(grant.capability_version).toBe(version);
  expect(grant.revoked_at).toBeNull();
  expect(grant.changed_by).toBe(VENDOR_OPERATOR_EMAIL);
  return grant;
}

async function assertNoCohortActivateSideEffects(
  grantBefore: Record<string, unknown>,
  cohortActivateAuditsBefore: number,
): Promise<void> {
  expect(await getGrants(installationScope())).toEqual([grantBefore]);
  expect(await count("control_audit", "action = ?", ["cohort_activate"])).toBe(
    cohortActivateAuditsBefore,
  );
}

describe("Stage 04 — cohort activate (S04-058…S04-065)", () => {
  it("S04-058 — Cohort activate without operator bearer", async () => {
    installTwoVersionRegistry();
    try {
      await enrollAndEntitleI0();
      const { grant: grantBefore, cohortAudits: cohortAuditsBefore } =
        await grantBaseline("1.0.0");

      const result = await controlFetch(
        activatePath("clinic.visit_summary", "2.0.0"),
        {
          auth: "none",
          body: { installation_ids: [I0] },
        },
      );

      assertControlError(result, 401, "unauthorized");
      await assertNoCohortActivateSideEffects(
        grantBefore,
        cohortAuditsBefore,
      );
    } finally {
      restorePublishedRegistry();
    }
  });

  it("S04-059 — Activate unregistered version 9.9.9", async () => {
    await enrollAndEntitleI0();
    const { grant: grantBefore, cohortAudits: cohortAuditsBefore } =
      await grantBaseline("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "9.9.9"),
      { body: { installation_ids: [I0] } },
    );

    assertControlError(result, 404, "capability_not_found");
    await assertNoCohortActivateSideEffects(grantBefore, cohortAuditsBefore);
  });

  it("S04-060 — Activate unregistered capability id", async () => {
    await enrollAndEntitleI0();
    const { grant: grantBefore, cohortAudits: cohortAuditsBefore } =
      await grantBaseline("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.not_in_registry", "1.0.0"),
      { body: { installation_ids: [I0] } },
    );

    assertControlError(result, 404, "capability_not_found");
    await assertNoCohortActivateSideEffects(grantBefore, cohortAuditsBefore);
  });

  it("S04-062 — Activate missing installation_ids", async () => {
    await enrollAndEntitleI0();
    const { grant: grantBefore, cohortAudits: cohortAuditsBefore } =
      await grantBaseline("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "1.0.0"),
      { body: { cohort_name: "pilot-clinics" } },
    );

    assertControlError(result, 400, "missing_installation_ids");
    await assertNoCohortActivateSideEffects(grantBefore, cohortAuditsBefore);
  });

  it("S04-063 — Activate empty installation_ids", async () => {
    await enrollAndEntitleI0();
    const { grant: grantBefore, cohortAudits: cohortAuditsBefore } =
      await grantBaseline("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "1.0.0"),
      { body: { installation_ids: [] } },
    );

    assertControlError(result, 400, "missing_installation_ids");
    await assertNoCohortActivateSideEffects(grantBefore, cohortAuditsBefore);
  });

  it("S04-064 — Activate installation_ids as string", async () => {
    await enrollAndEntitleI0();
    const { grant: grantBefore, cohortAudits: cohortAuditsBefore } =
      await grantBaseline("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "1.0.0"),
      { body: { installation_ids: I0 } },
    );

    assertControlError(result, 400, "missing_installation_ids");
    await assertNoCohortActivateSideEffects(grantBefore, cohortAuditsBefore);
  });

  it("S04-065 — Activate known plus unknown installation", async () => {
    await enrollAndEntitleI0();
    const { grant: grantBefore, cohortAudits: cohortAuditsBefore } =
      await grantBaseline("1.0.0");

    const result = await controlFetch(
      activatePath("clinic.visit_summary", "1.0.0"),
      {
        body: {
          installation_ids: [I0, UNKNOWN_INSTALLATION_ID],
        },
      },
    );

    assertControlError(result, 404, "installation_not_found");
    await assertNoCohortActivateSideEffects(grantBefore, cohortAuditsBefore);
  });
});
