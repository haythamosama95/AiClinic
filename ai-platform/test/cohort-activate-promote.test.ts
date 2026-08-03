import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import lifecycleMigrationSql from "../migrations/20260802100000_capability_grant_lifecycle.sql?raw";
import canaryMigrationSql from "../migrations/20260803100000_routing_policy_canary.sql?raw";
import {
  ConfigCache,
  loadConfig,
  type ConfigEntityKind,
  type D1Reader,
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

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

type ManifestWire = Record<string, unknown>;
type D1Row = Record<string, unknown>;

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const COHORT_INSTALLATION_ID = "inst-j3-cohort";
const OTHER_INSTALLATION_ID = "inst-j3-other";
const FIXTURE_ORG_ID = "org-j3-001";
const FIXTURE_CAPABILITY_ID = "clinic.j3";
const FIXTURE_VERSION_V1 = "1.0.0";
const FIXTURE_VERSION_V2 = "2.0.0";
const FIXTURE_PROMPT_V1 = "prompt/j3-system@v1";
const FIXTURE_PROMPT_V2 = "prompt/j3-system@v2";
const FIXTURE_NOW = "2026-08-03T12:00:00.000Z";
const FAKE_OPERATOR_ID = "operator-j3-test";

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
      "professional",
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

function makePlatformD1Reader(db: D1Database): D1Reader {
  return {
    async read(prefixedKey: string): Promise<D1Row | "miss"> {
      const separator = prefixedKey.indexOf(":");
      if (separator === -1) {
        return "miss";
      }
      const kind = prefixedKey.slice(0, separator) as ConfigEntityKind;
      const key = prefixedKey.slice(separator + 1);

      switch (kind) {
        case "entitlements": {
          const row = await db
            .prepare(
              `SELECT entitlement_id, installation_id, plan, period_start, period_end,
                      request_quota, token_budget, cost_budget, allowed_capabilities,
                      soft_threshold, status
               FROM entitlement WHERE installation_id = ?`,
            )
            .bind(key)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "grants": {
          if (key.startsWith("global/")) {
            const parts = key.slice("global/".length).split("/");
            const row = await db
              .prepare(
                `SELECT grant_id, scope, capability_id, capability_version,
                        granted_at, revoked_at, changed_at, changed_by,
                        lifecycle_state, successor_id, deprecated_at, retire_after
                 FROM capability_grant
                 WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
                 ORDER BY changed_at DESC LIMIT 1`,
              )
              .bind(parts[0], parts[1])
              .first<D1Row>();
            return row ?? "miss";
          }
          const [installationId, capabilityId] = key.split("/", 2);
          const row = await db
            .prepare(
              `SELECT grant_id, scope, capability_id, capability_version,
                      granted_at, revoked_at, changed_at, changed_by
               FROM capability_grant
               WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL
               ORDER BY changed_at DESC LIMIT 1`,
            )
            .bind(`installation:${installationId}`, capabilityId)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "kill_switches":
          return { active: false, scope: "global", target: "global" };
        default:
          return "miss";
      }
    },
  };
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
  const reader = makePlatformD1Reader(env.DB);
  const result = await discover(principal, cache, reader);
  const manifest = result.manifests.find(
    (m) => m.Identity.capabilityId === FIXTURE_CAPABILITY_ID,
  );
  return typeof manifest?.Identity.version === "string"
    ? manifest.Identity.version
    : undefined;
}

function assertNoPromptActivationPointerModule(): void {
  const modulePaths = Object.keys(
    import.meta.glob("../src/**/*.ts", { eager: false }),
  );
  for (const path of modulePaths) {
    expect(path.toLowerCase()).not.toMatch(/prompt[-_]?activation[-_]?pointer/);
  }
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, lifecycleMigrationSql);
  await applyPlatformSchema(env.DB, canaryMigrationSql);
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

    expect(await discoverGrantedVersion(COHORT_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V2,
    );
    expect(await discoverGrantedVersion(OTHER_INSTALLATION_ID)).toBe(
      FIXTURE_VERSION_V2,
    );
  });
});

describe("T-J3-03 rollback_by_deploy_restores_previous_build", () => {
  it("deploying the previous build restores prior serving for affected cohorts", async () => {
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
    const reader = makePlatformD1Reader(env.DB);

    for (const [installationId, expectedVersion, expectedPrompt] of [
      [COHORT_INSTALLATION_ID, FIXTURE_VERSION_V2, FIXTURE_PROMPT_V2],
      [OTHER_INSTALLATION_ID, FIXTURE_VERSION_V1, FIXTURE_PROMPT_V1],
    ] as const) {
      const grantedVersion = await getGrantedCapabilityVersion(
        installationId,
        FIXTURE_CAPABILITY_ID,
        cache,
        reader,
      );
      expect(grantedVersion).toBe(expectedVersion);

      const resolveResult = await resolve(
        buildPrincipal(installationId),
        FIXTURE_CAPABILITY_ID,
        grantedVersion!,
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
