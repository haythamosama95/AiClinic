import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import lifecycleMigrationSql from "../migrations/20260802100000_capability_grant_lifecycle.sql?raw";
import canaryMigrationSql from "../migrations/20260803100000_routing_policy_canary.sql?raw";
import statusMigrationSql from "../migrations/20260805190000_routing_policy_status.sql?raw";
import schemaSnapSql from "../schema.snap.sql?raw";
import {
  ConfigCache,
  createD1ConfigReader,
} from "../src/config-cache";
import {
  createCapabilityRegistry,
  discover,
  getGrantedCapabilityVersion,
  resolve,
  setCapabilityRegistry,
} from "../src/capability";
import type { Principal } from "../src/identity";
import { createRequestRow } from "../src/journal";
import { load } from "../src/manifest";
import {
  assertControlAudit,
} from "./helpers/control-audit-assert";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

type ManifestWire = Record<string, unknown>;

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const COHORT_INSTALLATION_ID = "inst-j3-cohort";
const OTHER_INSTALLATION_ID = "inst-j3-other";
const POST_ENROLL_INSTALLATION_ID = "inst-j3-post-enroll";
const FIXTURE_ORG_ID = "org-j3-001";
const FIXTURE_CAPABILITY_ID = "clinic.j3";
const FIXTURE_VERSION_V1 = "1.0.0";
const FIXTURE_VERSION_V2 = "2.0.0";
const FIXTURE_PROMPT_V1 = "prompt/j3-system@v1";
const FIXTURE_PROMPT_V2 = "prompt/j3-system@v2";
const FIXTURE_PLAN = "professional";
const FIXTURE_NOW = "2026-08-03T12:00:00.000Z";
const FAKE_OPERATOR_ID = "operator-j3-test";

const migrationSqlModules = import.meta.glob("../migrations/*.sql", {
  eager: true,
  query: "?raw",
  import: "default",
}) as Record<string, string>;

export type OperatorPrincipal = { operatorId: string };
export type OperatorAuth = {
  resolve(_request: Request): OperatorPrincipal | null;
};

function createFakeOperatorAuth(
  principal: OperatorPrincipal | null = { operatorId: FAKE_OPERATOR_ID },
): OperatorAuth {
  return { resolve() { return principal; } };
}

type CohortControlHandlers = {
  handleCohortActivate: (
    request: Request,
    bindings: { DB: D1Database },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleCohortPromote: (
    request: Request,
    bindings: { DB: D1Database },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
};

async function loadCohortControlHandlers(): Promise<CohortControlHandlers> {
  return import(/* @vite-ignore */ "../src/control") as Promise<CohortControlHandlers>;
}

function validManifest(
  version: string,
  promptRef: string,
): ManifestWire {
  return {
    Identity: {
      capabilityId: FIXTURE_CAPABILITY_ID,
      version,
      title: "J3 fixture",
      lifecycleState: "active",
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: `ai.${FIXTURE_CAPABILITY_ID}`,
      minimumPlanTier: "standard",
      allowedStaffRoles: ["clinician"],
      killSwitchFlag: false,
    },
    Interaction: { interactionMode: "single_shot" },
    Input: {
      userIntentShape: "plain_text",
      priorTurnShape: null,
      sizeLimits: { maxChars: 8_000 },
      allowedLanguages: ["en"],
    },
    "Context requirements": [
      {
        key: "visit.chief_complaint@v1",
        required: true,
        shapeRef: "visit.chief_complaint@v1",
        maxSize: 4_096,
        freshnessHint: "session",
      },
    ],
    "Prompt binding": {
      systemInstructionArtifactRef: promptRef,
      businessRuleFragmentRefs: [],
      contextRenderingTemplateRef: "templates/j3@v1",
      outputFormatInstructionDerivationRule: "derive_from_output_mode",
    },
    Output: {
      mode: "prose",
      outputSchemaRef: null,
      businessValidationRuleRefs: [],
      repairPolicy: { allowed: false, maxAttempts: 0 },
    },
    Routing: {
      routingPolicyRef: "routing/standard@v1",
      requiredProviderFeatures: {
        structuredOutput: false,
        contextWindow: 32_000,
        language: "en",
      },
      latencyClass: "standard",
      degradedTierPolicy: "fallback_chain",
    },
    Economics: {
      maxInputTokens: 8_000,
      maxOutputTokens: 1_024,
      perRequestCostCeiling: 9_024,
      quotaWeight: 1,
    },
    Governance: {
      acceptanceMode: "advisory_display",
      retentionClass: "diagnostic_30d",
      evalSuiteRef: "evals/j3@v1",
    },
  };
}

function buildRegistry(): void {
  const registry = createCapabilityRegistry([
    load(validManifest(FIXTURE_VERSION_V1, FIXTURE_PROMPT_V1)),
    load(validManifest(FIXTURE_VERSION_V2, FIXTURE_PROMPT_V2)),
  ]);
  setCapabilityRegistry(registry, { replace: true });
}

function buildPrincipal(installationId: string): Principal {
  return Object.freeze({
    installationId,
    organizationId: FIXTURE_ORG_ID,
    branchId: "branch-j3-001",
    actorId: "actor-j3-001",
    role: "clinician",
    scopes: Object.freeze([`ai.${FIXTURE_CAPABILITY_ID}`]),
    jti: `jti-${installationId}`,
    iat: 1_700_000_000,
    exp: 1_800_000_000,
  });
}

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);
  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function clearTables(db: D1Database): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM ai_request"),
    db.prepare("DELETE FROM control_audit"),
    db.prepare("DELETE FROM capability_grant"),
    db.prepare("DELETE FROM entitlement"),
    db.prepare("DELETE FROM installation_key"),
    db.prepare("DELETE FROM installation"),
  ]);
}

async function seedInstallation(
  db: D1Database,
  installationId: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO installation (
        installation_id, org_id, display_name, status, region, enrolled_at
      ) VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      installationId,
      FIXTURE_ORG_ID,
      `J3 ${installationId}`,
      "active",
      "us-east-1",
      FIXTURE_NOW,
    )
    .run();
}

async function seedEntitlement(
  db: D1Database,
  installationId: string,
  plan: string = FIXTURE_PLAN,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO entitlement (
        entitlement_id, installation_id, plan, period_start, period_end,
        request_quota, token_budget, cost_budget, allowed_capabilities,
        soft_threshold, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      `ent-${installationId}`,
      installationId,
      plan,
      FIXTURE_NOW,
      FIXTURE_NOW,
      1_000,
      1_000_000,
      100,
      JSON.stringify([FIXTURE_CAPABILITY_ID]),
      0.8,
      "active",
    )
    .run();
}

async function seedInstallationGrant(
  db: D1Database,
  installationId: string,
  capabilityVersion: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
    )
    .bind(
      `grant-${installationId}-${capabilityVersion}`,
      `installation:${installationId}`,
      FIXTURE_CAPABILITY_ID,
      capabilityVersion,
      FIXTURE_NOW,
      FIXTURE_NOW,
      FAKE_OPERATOR_ID,
    )
    .run();
}

async function seedPlanGrant(
  db: D1Database,
  plan: string,
  capabilityVersion: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
    )
    .bind(
      `grant-plan-${plan}-${capabilityVersion}`,
      `plan:${plan}`,
      FIXTURE_CAPABILITY_ID,
      capabilityVersion,
      FIXTURE_NOW,
      FIXTURE_NOW,
      FAKE_OPERATOR_ID,
    )
    .run();
}

function buildActivateRequest(
  version: string,
  installationIds: string[],
  cohortName?: string,
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/capabilities/${FIXTURE_CAPABILITY_ID}/versions/${version}/activate`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${FAKE_OPERATOR_ID}`,
      },
      body: JSON.stringify({
        installation_ids: installationIds,
        ...(cohortName ? { cohort_name: cohortName } : {}),
      }),
    },
  );
}

function buildPromoteRequest(version: string): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/capabilities/${FIXTURE_CAPABILITY_ID}/versions/${version}/promote`,
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

async function discoverGrantedVersion(
  installationId: string,
): Promise<string | undefined> {
  const principal = buildPrincipal(installationId);
  const cache = new ConfigCache();
  const reader = createD1ConfigReader(env.DB);
  const result = await discover(principal, cache, reader);
  const manifest = result.manifests.find(
    (m) => m.Identity.capabilityId === FIXTURE_CAPABILITY_ID,
  );
  return typeof manifest?.Identity.version === "string"
    ? manifest.Identity.version
    : undefined;
}

async function grantedVersion(
  installationId: string,
): Promise<string | null> {
  const cache = new ConfigCache();
  const reader = createD1ConfigReader(env.DB);
  return getGrantedCapabilityVersion(
    installationId,
    FIXTURE_CAPABILITY_ID,
    cache,
    reader,
  );
}

async function assertAuditPointersNonNull(
  db: D1Database,
  action: string,
  options: { requireBefore?: boolean; requireAfter?: boolean } = {},
): Promise<void> {
  const requireBefore = options.requireBefore ?? true;
  const requireAfter = options.requireAfter ?? true;
  const row = await db
    .prepare(
      `SELECT before_pointer, after_pointer FROM control_audit
       WHERE action = ? ORDER BY recorded_at DESC LIMIT 1`,
    )
    .bind(action)
    .first<{ before_pointer: string | null; after_pointer: string | null }>();

  expect(row).toBeTruthy();
  if (requireBefore) {
    expect(row!.before_pointer).not.toBeNull();
  }
  if (requireAfter) {
    expect(row!.after_pointer).not.toBeNull();
  }
}

function assertNoPromptActivationPointerModule(): void {
  const modulePaths = Object.keys(
    import.meta.glob("../src/**/*.ts", { eager: false }),
  );
  for (const path of modulePaths) {
    expect(path.toLowerCase()).not.toMatch(/prompt[-_]?activation[-_]?pointer/);
  }
}

function assertNoPromptActivationPointerInSqlArtifacts(): void {
  const sqlBlobs = [schemaSnapSql, ...Object.values(migrationSqlModules)];
  for (const sql of sqlBlobs) {
    expect(sql).not.toMatch(/prompt.?text/i);
    expect(sql).not.toMatch(/activation.?pointer/i);
  }
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, lifecycleMigrationSql);
  await applyPlatformSchema(env.DB, canaryMigrationSql);
  await applyPlatformSchema(env.DB, statusMigrationSql);
});

beforeEach(async () => {
  await clearTables(env.DB);
  vi.setSystemTime(new Date(FIXTURE_NOW));
  buildRegistry();
});

describe("T-J3-01 cohort_receives_new_build_others_previous", () => {
  it("after cohort activate, cohort gets new build and others keep previous", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);
    await seedEntitlement(env.DB, COHORT_INSTALLATION_ID);
    await seedEntitlement(env.DB, OTHER_INSTALLATION_ID);
    await seedInstallationGrant(env.DB, COHORT_INSTALLATION_ID, FIXTURE_VERSION_V1);
    await seedInstallationGrant(env.DB, OTHER_INSTALLATION_ID, FIXTURE_VERSION_V1);

    const operatorAuth = createFakeOperatorAuth();
    const { handleCohortActivate } = await loadCohortControlHandlers();
    const response = await handleCohortActivate(
      buildActivateRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
      { DB: env.DB },
      operatorAuth,
    );
    expect(response.ok).toBe(true);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "cohort_activate",
    });
    await assertAuditPointersNonNull(env.DB, "cohort_activate");

    expect(await discoverGrantedVersion(COHORT_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V2,
    );
    expect(await discoverGrantedVersion(OTHER_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V1,
    );
  });
});

describe("T-J3-02 promotion_moves_all_cohorts", () => {
  it("after promote, all installations receive the activated build", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);
    await seedEntitlement(env.DB, COHORT_INSTALLATION_ID);
    await seedEntitlement(env.DB, OTHER_INSTALLATION_ID);
    await seedInstallationGrant(env.DB, COHORT_INSTALLATION_ID, FIXTURE_VERSION_V1);
    await seedInstallationGrant(env.DB, OTHER_INSTALLATION_ID, FIXTURE_VERSION_V1);

    const operatorAuth = createFakeOperatorAuth();
    const { handleCohortActivate, handleCohortPromote } =
      await loadCohortControlHandlers();

    const activateResponse = await handleCohortActivate(
      buildActivateRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
      { DB: env.DB },
      operatorAuth,
    );
    expect(activateResponse.ok).toBe(true);

    const promoteResponse = await handleCohortPromote(
      buildPromoteRequest(FIXTURE_VERSION_V2),
      { DB: env.DB },
      operatorAuth,
    );
    expect(promoteResponse.ok).toBe(true);
    await assertControlAudit(env.DB, {
      operatorId: FAKE_OPERATOR_ID,
      action: "cohort_promote",
    });
    await assertAuditPointersNonNull(env.DB, "cohort_promote");

    expect(await discoverGrantedVersion(COHORT_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V2,
    );
    expect(await discoverGrantedVersion(OTHER_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V2,
    );
  });
});

describe("T-J3-02b promotion_moves_plan_scoped_installations", () => {
  it("plan-scoped installs stay on plan grant until promote moves them", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);
    await seedEntitlement(env.DB, COHORT_INSTALLATION_ID);
    await seedEntitlement(env.DB, OTHER_INSTALLATION_ID);
    await seedPlanGrant(env.DB, FIXTURE_PLAN, FIXTURE_VERSION_V1);
    await seedInstallationGrant(env.DB, COHORT_INSTALLATION_ID, FIXTURE_VERSION_V1);

    const operatorAuth = createFakeOperatorAuth();
    const { handleCohortActivate, handleCohortPromote } =
      await loadCohortControlHandlers();

    const activateResponse = await handleCohortActivate(
      buildActivateRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
      { DB: env.DB },
      operatorAuth,
    );
    expect(activateResponse.ok).toBe(true);

    expect(await discoverGrantedVersion(COHORT_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V2,
    );
    expect(await grantedVersion(COHORT_INSTALLATION_ID)).toBe(FIXTURE_VERSION_V2);
    expect(await discoverGrantedVersion(OTHER_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V1,
    );
    expect(await grantedVersion(OTHER_INSTALLATION_ID)).toBe(FIXTURE_VERSION_V1);

    const promoteResponse = await handleCohortPromote(
      buildPromoteRequest(FIXTURE_VERSION_V2),
      { DB: env.DB },
      operatorAuth,
    );
    expect(promoteResponse.ok).toBe(true);
    await assertAuditPointersNonNull(env.DB, "cohort_promote");

    expect(await discoverGrantedVersion(COHORT_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V2,
    );
    expect(await discoverGrantedVersion(OTHER_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V2,
    );

    const planGrant = await env.DB.prepare(
      `SELECT capability_version FROM capability_grant
       WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL
       ORDER BY changed_at DESC LIMIT 1`,
    )
      .bind(`plan:${FIXTURE_PLAN}`, FIXTURE_CAPABILITY_ID)
      .first<{ capability_version: string }>();
    expect(planGrant?.capability_version).toBe(FIXTURE_VERSION_V2);
  });
});

describe("T-J3-02c promotion_covers_post_enroll_installation", () => {
  it("new entitled installation without install grant resolves via plan fallback", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);
    await seedEntitlement(env.DB, COHORT_INSTALLATION_ID);
    await seedEntitlement(env.DB, OTHER_INSTALLATION_ID);
    await seedPlanGrant(env.DB, FIXTURE_PLAN, FIXTURE_VERSION_V1);
    await seedInstallationGrant(env.DB, COHORT_INSTALLATION_ID, FIXTURE_VERSION_V1);

    const operatorAuth = createFakeOperatorAuth();
    const { handleCohortActivate, handleCohortPromote } =
      await loadCohortControlHandlers();

    expect(
      (
        await handleCohortActivate(
          buildActivateRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
          { DB: env.DB },
          operatorAuth,
        )
      ).ok,
    ).toBe(true);
    expect(
      (
        await handleCohortPromote(
          buildPromoteRequest(FIXTURE_VERSION_V2),
          { DB: env.DB },
          operatorAuth,
        )
      ).ok,
    ).toBe(true);

    await seedInstallation(env.DB, POST_ENROLL_INSTALLATION_ID);
    await seedEntitlement(env.DB, POST_ENROLL_INSTALLATION_ID);

    expect(await grantedVersion(POST_ENROLL_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V2,
    );
  });
});

describe("T-J3-03 prior_build_restored_without_runtime_prompt_pointer", () => {
  it("re-activating prior build restores serving without prompt activation pointer", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedEntitlement(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallationGrant(env.DB, COHORT_INSTALLATION_ID, FIXTURE_VERSION_V1);

    const operatorAuth = createFakeOperatorAuth();
    const { handleCohortActivate } = await loadCohortControlHandlers();

    const activateV2 = await handleCohortActivate(
      buildActivateRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
      { DB: env.DB },
      operatorAuth,
    );
    expect(activateV2.ok).toBe(true);
    expect(await discoverGrantedVersion(COHORT_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V2,
    );

    const rollbackDeploy = await handleCohortActivate(
      buildActivateRequest(FIXTURE_VERSION_V1, [COHORT_INSTALLATION_ID]),
      { DB: env.DB },
      operatorAuth,
    );
    expect(rollbackDeploy.ok).toBe(true);
    expect(await discoverGrantedVersion(COHORT_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V1,
    );

    assertNoPromptActivationPointerModule();
    assertNoPromptActivationPointerInSqlArtifacts();
  });
});

describe("T-J3-05 journal_records_serving_version_under_cohort_split", () => {
  it("journaled prompt hash and capability version match each cohort build", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    await seedInstallation(env.DB, OTHER_INSTALLATION_ID);
    await seedEntitlement(env.DB, COHORT_INSTALLATION_ID);
    await seedEntitlement(env.DB, OTHER_INSTALLATION_ID);
    await seedInstallationGrant(env.DB, COHORT_INSTALLATION_ID, FIXTURE_VERSION_V1);
    await seedInstallationGrant(env.DB, OTHER_INSTALLATION_ID, FIXTURE_VERSION_V1);

    const operatorAuth = createFakeOperatorAuth();
    const { handleCohortActivate } = await loadCohortControlHandlers();
    const activateResponse = await handleCohortActivate(
      buildActivateRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
      { DB: env.DB },
      operatorAuth,
    );
    expect(activateResponse.ok).toBe(true);

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB);

    for (const [installationId, expectedVersion, expectedPrompt] of [
      [COHORT_INSTALLATION_ID, FIXTURE_VERSION_V2, FIXTURE_PROMPT_V2],
      [OTHER_INSTALLATION_ID, FIXTURE_VERSION_V1, FIXTURE_PROMPT_V1],
    ] as const) {
      const version = await getGrantedCapabilityVersion(
        installationId,
        FIXTURE_CAPABILITY_ID,
        cache,
        reader,
      );
      expect(version).toBe(expectedVersion);

      const resolveResult = await resolve(
        buildPrincipal(installationId),
        FIXTURE_CAPABILITY_ID,
        version!,
        cache,
        reader,
      );
      expect(resolveResult.ok).toBe(true);
      if (!resolveResult.ok) {
        continue;
      }

      const requestId = crypto.randomUUID();
      const createResult = await createRequestRow(
        {
          requestId,
          requestReference: `AI-J3-${installationId}`,
          principal: buildPrincipal(installationId),
          manifest: resolveResult.manifest,
          idempotencyKey: `idem-${installationId}`,
          traceId: "01J3JOURNALTRACE000001",
        },
        env.DB,
      );
      expect(createResult.ok).toBe(true);

      const row = await env.DB.prepare(
        `SELECT capability_version, prompt_artifact_hash
         FROM ai_request WHERE request_id = ?`,
      )
        .bind(requestId)
        .first<{ capability_version: string; prompt_artifact_hash: string }>();

      expect(row?.capability_version).toBe(expectedVersion);
      expect(row?.prompt_artifact_hash).toBe(expectedPrompt);
    }
  });
});

describe("cohort_control_rejection_branches", () => {
  it("rejects non-operator credentials on activate and promote", async () => {
    const { handleCohortActivate, handleCohortPromote } =
      await loadCohortControlHandlers();
    const unauth = createFakeOperatorAuth(null);

    const activate = await handleCohortActivate(
      buildActivateRequest(FIXTURE_VERSION_V2, [COHORT_INSTALLATION_ID]),
      { DB: env.DB },
      unauth,
    );
    expect(activate.status).toBe(401);

    const promote = await handleCohortPromote(
      buildPromoteRequest(FIXTURE_VERSION_V2),
      { DB: env.DB },
      unauth,
    );
    expect(promote.status).toBe(401);

    const auditCount = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM control_audit",
    ).first<{ count: number }>();
    expect(auditCount?.count ?? 0).toBe(0);
  });

  it("rejects empty installation_ids on activate with 400", async () => {
    const { handleCohortActivate } = await loadCohortControlHandlers();
    const response = await handleCohortActivate(
      buildActivateRequest(FIXTURE_VERSION_V2, []),
      { DB: env.DB },
      createFakeOperatorAuth(),
    );
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "missing_installation_ids" });
  });

  it("rejects unknown capability version with 404", async () => {
    await seedInstallation(env.DB, COHORT_INSTALLATION_ID);
    const { handleCohortActivate, handleCohortPromote } =
      await loadCohortControlHandlers();

    const activate = await handleCohortActivate(
      buildActivateRequest("9.9.9", [COHORT_INSTALLATION_ID]),
      { DB: env.DB },
      createFakeOperatorAuth(),
    );
    expect(activate.status).toBe(404);
    expect(await activate.json()).toEqual({ error: "capability_not_found" });

    const promote = await handleCohortPromote(
      buildPromoteRequest("9.9.9"),
      { DB: env.DB },
      createFakeOperatorAuth(),
    );
    expect(promote.status).toBe(404);
    expect(await promote.json()).toEqual({ error: "capability_not_found" });
  });

  it("rejects unknown installation on activate with 404", async () => {
    const { handleCohortActivate } = await loadCohortControlHandlers();
    const response = await handleCohortActivate(
      buildActivateRequest(FIXTURE_VERSION_V2, ["inst-does-not-exist"]),
      { DB: env.DB },
      createFakeOperatorAuth(),
    );
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "installation_not_found" });
  });
});
