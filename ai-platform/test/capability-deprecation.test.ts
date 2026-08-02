import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import lifecycleMigrationSql from "../migrations/20260802100000_capability_grant_lifecycle.sql?raw";
import {
  ConfigCache,
  ConfigCacheMissError,
  loadConfig,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";
import type { Principal } from "../src/identity";
import { hashManifest, load } from "../src/manifest";
import {
  createCapabilityRegistry,
  discover,
  resolve,
  setCapabilityRegistry,
} from "../src/capability";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

type ManifestWire = Record<string, unknown>;
type D1Row = Record<string, unknown>;

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const FIXTURE_INSTALLATION_ID = "inst-j1-001";
const FIXTURE_ORG_ID = "org-j1-001";
const FIXTURE_CAPABILITY_ID = "clinic.j1";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_SUCCESSOR_ID = "clinic.j1-successor";
const FIXTURE_NOW = "2026-08-02T12:00:00.000Z";
const FAKE_OPERATOR_ID = "operator-j1-test";

export type OperatorPrincipal = {
  operatorId: string;
};

function createFakeOperatorAuth(
  principal: OperatorPrincipal | null = { operatorId: FAKE_OPERATOR_ID },
): OperatorAuth {
  return {
    resolve() {
      return principal;
    },
  };
}

type ControlHandlers = {
  handleDeprecate: (
    request: Request,
    bindings: { DB: D1Database },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
  handleRetire: (
    request: Request,
    bindings: { DB: D1Database },
    operatorAuth: OperatorAuth,
  ) => Promise<Response>;
};

type OperatorAuth = {
  resolve(_request: Request): OperatorPrincipal | null;
};

async function loadControlHandlers(): Promise<ControlHandlers> {
  return import(/* @vite-ignore */ "../src/control") as Promise<ControlHandlers>;
}

function validManifest(
  capabilityId: string,
  version: string,
  lifecycleState: string = "active",
  successorId: string | null = null,
): ManifestWire {
  return {
    Identity: {
      capabilityId,
      version,
      title: `${capabilityId} fixture`,
      lifecycleState,
      successorId,
    },
    Access: {
      requiredCapabilityScope: `ai.${capabilityId}`,
      minimumPlanTier: "standard",
      allowedStaffRoles: ["clinician", "nurse"],
      killSwitchFlag: false,
    },
    Interaction: {
      interactionMode: "single_shot",
    },
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
      systemInstructionArtifactRef: "prompt/visit-summary-system@v1",
      businessRuleFragmentRefs: ["rules/visit-summary@v1"],
      contextRenderingTemplateRef: "templates/visit-summary@v1",
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
      evalSuiteRef: "evals/visit-summary@v1",
    },
  };
}

function buildRegistry(...manifests: ManifestWire[]): void {
  const loaded = manifests.map((wire) => load(wire));
  const registry = createCapabilityRegistry(loaded);
  setCapabilityRegistry(registry);
}

function buildPrincipal(): Principal {
  return Object.freeze({
    installationId: FIXTURE_INSTALLATION_ID,
    organizationId: FIXTURE_ORG_ID,
    branchId: "branch-j1-001",
    actorId: "actor-j1-001",
    role: "clinician",
    scopes: Object.freeze([`ai.${FIXTURE_CAPABILITY_ID}`]),
    jti: "jti-j1-001",
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
    db.prepare("DELETE FROM control_audit"),
    db.prepare("DELETE FROM capability_grant"),
    db.prepare("DELETE FROM entitlement"),
    db.prepare("DELETE FROM installation_key"),
    db.prepare("DELETE FROM installation"),
  ]);
}

async function seedInstallation(db: D1Database): Promise<void> {
  await db
    .prepare(
      `INSERT INTO installation (
        installation_id, org_id, display_name, status, region, enrolled_at
      ) VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      FIXTURE_INSTALLATION_ID,
      FIXTURE_ORG_ID,
      "J1 Test Clinic",
      "active",
      "us-east-1",
      FIXTURE_NOW,
    )
    .run();
}

async function seedEntitlement(db: D1Database): Promise<void> {
  await db
    .prepare(
      `INSERT INTO entitlement (
        entitlement_id, installation_id, plan, period_start, period_end,
        request_quota, token_budget, cost_budget, allowed_capabilities,
        soft_threshold, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      `ent-${FIXTURE_INSTALLATION_ID}`,
      FIXTURE_INSTALLATION_ID,
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
  capabilityId: string = FIXTURE_CAPABILITY_ID,
  capabilityVersion: string = FIXTURE_CAPABILITY_VERSION,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
    )
    .bind(
      `grant-install-${capabilityId}`,
      `installation:${FIXTURE_INSTALLATION_ID}`,
      capabilityId,
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
            const capabilityId = parts[0];
            const version = parts[1];
            const row = await db
              .prepare(
                `SELECT grant_id, scope, capability_id, capability_version,
                        granted_at, revoked_at, changed_at, changed_by,
                        lifecycle_state, successor_id, deprecated_at, retire_after
                 FROM capability_grant
                 WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
                 ORDER BY changed_at DESC LIMIT 1`,
              )
              .bind(capabilityId, version)
              .first<D1Row>();
            return row ?? "miss";
          }

          const [installationId, capabilityId] = key.split("/", 2);
          const row = await db
            .prepare(
              `SELECT grant_id, scope, capability_id, capability_version,
                      granted_at, revoked_at, changed_at, changed_by
               FROM capability_grant
               WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL`,
            )
            .bind(`installation:${installationId}`, capabilityId)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "kill_switches": {
          return { active: false, scope: "global", target: "global" };
        }
        default:
          return "miss";
      }
    },
  };
}

function buildDeprecateRequest(
  capabilityId: string = FIXTURE_CAPABILITY_ID,
  version: string = FIXTURE_CAPABILITY_VERSION,
  successorId: string = FIXTURE_SUCCESSOR_ID,
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/capabilities/${capabilityId}/versions/${version}/deprecate`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${FAKE_OPERATOR_ID}`,
      },
      body: JSON.stringify({ successor_id: successorId }),
    },
  );
}

function buildRetireRequest(
  capabilityId: string = FIXTURE_CAPABILITY_ID,
  version: string = FIXTURE_CAPABILITY_VERSION,
): Request {
  return new Request(
    `${GATEWAY_ORIGIN}/control/capabilities/${capabilityId}/versions/${version}/retire`,
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

const LIFECYCLE_MIGRATION_SQL = lifecycleMigrationSql;

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, LIFECYCLE_MIGRATION_SQL);
});

beforeEach(async () => {
  await clearTables(env.DB);
  vi.setSystemTime(new Date(FIXTURE_NOW));
});

describe("T-J1-01 discovery_marks_deprecated_with_successor", () => {
  it("includes deprecated version with successor after deprecate mutation", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));
    await seedInstallation(env.DB);
    await seedEntitlement(env.DB);
    await seedInstallationGrant(env.DB);

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();
    const deprecateResponse = await handleDeprecate(
      buildDeprecateRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(deprecateResponse.ok).toBe(true);

    const principal = buildPrincipal();
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);

    const result = await discover(principal, cache, reader);

    const deprecated = result.manifests.find(
      (m) => m.Identity.capabilityId === FIXTURE_CAPABILITY_ID,
    );
    expect(deprecated).toBeDefined();
    expect(deprecated?.Identity.lifecycleState).toBe("deprecated");
    expect(deprecated?.Identity.successorId).toBe(FIXTURE_SUCCESSOR_ID);
  });
});

describe("T-J1-02 deprecated_serves_inside_overlap_window", () => {
  it("returns manifest when effective lifecycle is deprecated inside overlap window", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));
    await seedInstallation(env.DB);
    await seedEntitlement(env.DB);
    await seedInstallationGrant(env.DB);

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();
    const deprecateResponse = await handleDeprecate(
      buildDeprecateRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(deprecateResponse.ok).toBe(true);

    const principal = buildPrincipal();
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);

    const result = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) {
      return;
    }
    expect(result.manifest.Identity.capabilityId).toBe(FIXTURE_CAPABILITY_ID);
    expect(result.manifest.Identity.version).toBe(FIXTURE_CAPABILITY_VERSION);
  });
});

describe("T-J1-03 retired_pin_returns_capability_retired", () => {
  it("returns capability_retired after retire mutation", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));
    await seedInstallation(env.DB);
    await seedEntitlement(env.DB);
    await seedInstallationGrant(env.DB);

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();
    const deprecateResponse = await handleDeprecate(
      buildDeprecateRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(deprecateResponse.ok).toBe(true);

    const overlay = await env.DB.prepare(
      `SELECT retire_after FROM capability_grant
       WHERE scope = 'global' AND capability_id = ?`,
    )
      .bind(FIXTURE_CAPABILITY_ID)
      .first<{ retire_after: string }>();
    expect(overlay?.retire_after).toBeTruthy();
    vi.setSystemTime(new Date(overlay!.retire_after));

    const { handleRetire } = await loadControlHandlers();
    const retireResponse = await handleRetire(
      buildRetireRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(retireResponse.ok).toBe(true);

    const principal = buildPrincipal();
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);

    const result = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );

    expect(result).toEqual({ ok: false, code: "capability_retired" });
  });
});

describe("T-J1-04 retire_journaled_with_operator_identity", () => {
  it("writes control_audit row with operator id and retire action", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();
    const deprecateResponse = await handleDeprecate(
      buildDeprecateRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(deprecateResponse.ok).toBe(true);

    const overlay = await env.DB.prepare(
      `SELECT retire_after FROM capability_grant
       WHERE scope = 'global' AND capability_id = ?`,
    )
      .bind(FIXTURE_CAPABILITY_ID)
      .first<{ retire_after: string }>();
    vi.setSystemTime(new Date(overlay!.retire_after));

    const { handleRetire } = await loadControlHandlers();
    const retireResponse = await handleRetire(
      buildRetireRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(retireResponse.ok).toBe(true);

    const audit = await env.DB.prepare(
      `SELECT operator_id, action, target FROM control_audit
       WHERE action = 'retire' ORDER BY recorded_at DESC LIMIT 1`,
    ).first<{ operator_id: string; action: string; target: string }>();

    expect(audit).toMatchObject({
      operator_id: FAKE_OPERATOR_ID,
      action: "retire",
      target: `${FIXTURE_CAPABILITY_ID}@${FIXTURE_CAPABILITY_VERSION}`,
    });
  });
});

describe("T-J1-05 lifecycle_survives_cold_isolate_manifest_unchanged", () => {
  it("reconstructs lifecycle via cold ConfigCache and preserves manifest hash", async () => {
    const manifestWire = validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION);
    buildRegistry(manifestWire);
    const publishedHash = hashManifest(manifestWire);

    await seedInstallation(env.DB);
    await seedEntitlement(env.DB);
    await seedInstallationGrant(env.DB);

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();
    const deprecateResponse = await handleDeprecate(
      buildDeprecateRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(deprecateResponse.ok).toBe(true);

    const coldCache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);
    const overlayRow = await loadConfig(
      coldCache,
      {
        read(key: string) {
          return reader.read(`grants:${key}`);
        },
      },
      "grants",
      `global/${FIXTURE_CAPABILITY_ID}/${FIXTURE_CAPABILITY_VERSION}`,
    );
    expect(overlayRow.lifecycle_state).toBe("deprecated");

    const principal = buildPrincipal();
    const resolveResult = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      coldCache,
      reader,
    );
    expect(resolveResult.ok).toBe(true);

    const discoveryResult = await discover(principal, coldCache, reader);
    const discovered = discoveryResult.manifests.find(
      (m) => m.Identity.capabilityId === FIXTURE_CAPABILITY_ID,
    );
    expect(discovered?.Identity.lifecycleState).toBe("deprecated");
    expect(discovered?.Identity.successorId).toBe(FIXTURE_SUCCESSOR_ID);

    const registryManifest = load(manifestWire);
    expect(hashManifest(manifestWire)).toBe(publishedHash);
    expect(registryManifest.Identity.lifecycleState).toBe("active");
  });
});
