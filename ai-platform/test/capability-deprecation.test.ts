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
      routingPolicyRef: "routing/standard",
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
      perRequestTokenCeiling: 9_024,
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
  setCapabilityRegistry(registry, { replace: true });
}

/** Default J1 registry: target version plus a registered successor identity. */
function buildJ1Registry(...extra: ManifestWire[]): void {
  buildRegistry(
    validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION),
    validManifest(FIXTURE_SUCCESSOR_ID, "1.0.0"),
    ...extra,
  );
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
    buildJ1Registry();
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
    buildJ1Registry();
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
    buildJ1Registry();
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
    buildJ1Registry();

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
    buildJ1Registry();
    const publishedHash = await hashManifest(manifestWire);

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
      reader,
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
    expect(await hashManifest(manifestWire)).toBe(publishedHash);
    expect(registryManifest.Identity.lifecycleState).toBe("active");
  });
});

describe("T-J1-06 deprecate_rejects_after_retire", () => {
  it("rejects deprecate when latest overlay is retired and does not resurrect", async () => {
    buildJ1Registry();

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate, handleRetire } = await loadControlHandlers();
    expect(
      (await handleDeprecate(buildDeprecateRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const overlay = await env.DB.prepare(
      `SELECT retire_after FROM capability_grant
       WHERE scope = 'global' AND capability_id = ?`,
    )
      .bind(FIXTURE_CAPABILITY_ID)
      .first<{ retire_after: string }>();
    vi.setSystemTime(new Date(overlay!.retire_after));
    expect(
      (await handleRetire(buildRetireRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const beforeCount = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM capability_grant WHERE scope = 'global'`,
    ).first<{ n: number }>();

    const response = await handleDeprecate(
      buildDeprecateRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: "already_retired" });

    const afterCount = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM capability_grant WHERE scope = 'global'`,
    ).first<{ n: number }>();
    expect(afterCount?.n).toBe(beforeCount?.n);

    const latest = await env.DB.prepare(
      `SELECT lifecycle_state FROM capability_grant
       WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
       ORDER BY changed_at DESC LIMIT 1`,
    )
      .bind(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)
      .first<{ lifecycle_state: string }>();
    expect(latest?.lifecycle_state).toBe("retired");
  });
});

describe("T-J1-07 duplicate_deprecate_same_successor_is_idempotent", () => {
  it("returns ok without resetting deprecated_at or retire_after", async () => {
    buildJ1Registry();

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();
    expect(
      (await handleDeprecate(buildDeprecateRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const first = await env.DB.prepare(
      `SELECT grant_id, deprecated_at, retire_after, successor_id FROM capability_grant
       WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
       ORDER BY changed_at DESC LIMIT 1`,
    )
      .bind(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)
      .first<{
        grant_id: string;
        deprecated_at: string;
        retire_after: string;
        successor_id: string;
      }>();

    vi.setSystemTime(new Date("2026-08-03T12:00:00.000Z"));

    const second = await handleDeprecate(
      buildDeprecateRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(second.ok).toBe(true);

    const rows = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM capability_grant WHERE scope = 'global'`,
    ).first<{ n: number }>();
    expect(rows?.n).toBe(1);

    const latest = await env.DB.prepare(
      `SELECT grant_id, deprecated_at, retire_after, successor_id FROM capability_grant
       WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
       ORDER BY changed_at DESC LIMIT 1`,
    )
      .bind(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)
      .first<{
        grant_id: string;
        deprecated_at: string;
        retire_after: string;
        successor_id: string;
      }>();
    expect(latest).toEqual(first);
  });
});

describe("T-J1-08 duplicate_deprecate_different_successor_rejected", () => {
  it("rejects a second deprecate that would change the successor", async () => {
    buildJ1Registry(validManifest("clinic.j1-other-successor", "1.0.0"));

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();
    expect(
      (await handleDeprecate(buildDeprecateRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const response = await handleDeprecate(
      buildDeprecateRequest(
        FIXTURE_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "clinic.j1-other-successor",
      ),
      { DB: env.DB },
      operatorAuth,
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: "already_deprecated" });
  });
});

describe("T-J1-09 unknown_capability_version_rejected", () => {
  it("rejects deprecate and retire for an unregistered id/version before D1 writes", async () => {
    buildJ1Registry();
    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate, handleRetire } = await loadControlHandlers();

    const deprecateResponse = await handleDeprecate(
      buildDeprecateRequest("clinic.missing", "9.9.9"),
      { DB: env.DB },
      operatorAuth,
    );
    expect(deprecateResponse.status).toBe(404);
    expect(await deprecateResponse.json()).toEqual({ error: "capability_not_found" });

    const retireResponse = await handleRetire(
      buildRetireRequest("clinic.missing", "9.9.9"),
      { DB: env.DB },
      operatorAuth,
    );
    expect(retireResponse.status).toBe(404);
    expect(await retireResponse.json()).toEqual({ error: "capability_not_found" });

    const grantCount = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM capability_grant WHERE scope = 'global'`,
    ).first<{ n: number }>();
    expect(grantCount?.n).toBe(0);
  });
});

describe("T-J1-10 unknown_successor_rejected", () => {
  it("rejects deprecate when successor_id is not in the registry", async () => {
    buildJ1Registry();
    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();

    const response = await handleDeprecate(
      buildDeprecateRequest(
        FIXTURE_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "clinic.unknown-successor",
      ),
      { DB: env.DB },
      operatorAuth,
    );
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "unknown_successor" });

    const grantCount = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM capability_grant WHERE scope = 'global'`,
    ).first<{ n: number }>();
    expect(grantCount?.n).toBe(0);
  });
});

describe("T-J1-11 missing_successor_id_rejected", () => {
  it("rejects deprecate when successor_id is absent", async () => {
    buildJ1Registry();
    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();

    const request = new Request(
      `${GATEWAY_ORIGIN}/control/capabilities/${FIXTURE_CAPABILITY_ID}/versions/${FIXTURE_CAPABILITY_VERSION}/deprecate`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${FAKE_OPERATOR_ID}`,
        },
        body: JSON.stringify({}),
      },
    );
    const response = await handleDeprecate(request, { DB: env.DB }, operatorAuth);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "missing_successor_id" });
  });
});

describe("T-J1-12 overlay_rows_are_not_live_grants", () => {
  it("writes lifecycle overlay rows with revoked_at set", async () => {
    buildJ1Registry();
    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();
    expect(
      (await handleDeprecate(buildDeprecateRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const row = await env.DB.prepare(
      `SELECT granted_at, revoked_at, changed_at, lifecycle_state FROM capability_grant
       WHERE scope = 'global' ORDER BY changed_at DESC LIMIT 1`,
    ).first<{
      granted_at: string;
      revoked_at: string | null;
      changed_at: string;
      lifecycle_state: string;
    }>();
    expect(row?.lifecycle_state).toBe("deprecated");
    expect(row?.revoked_at).toBe(row?.changed_at);
    expect(row?.granted_at).toBe(row?.changed_at);
  });
});

describe("T-J1-13 retire_window_uses_epoch_ms", () => {
  it("parses non-canonical Z retire_after before comparing the window", async () => {
    buildJ1Registry();
    await env.DB.prepare(
      `INSERT INTO capability_grant (
         grant_id, scope, capability_id, capability_version,
         granted_at, revoked_at, changed_at, changed_by,
         lifecycle_state, successor_id, deprecated_at, retire_after
       ) VALUES (?, 'global', ?, ?, ?, ?, ?, ?, 'deprecated', ?, ?, ?)`,
    )
      .bind(
        "grant-overlay-offset",
        FIXTURE_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        FIXTURE_NOW,
        FIXTURE_NOW,
        FIXTURE_NOW,
        FAKE_OPERATOR_ID,
        FIXTURE_SUCCESSOR_ID,
        "2026-05-01T00:00:00.000Z",
        "2026-08-01T12:00:00+00:00",
      )
      .run();

    vi.setSystemTime(new Date("2026-08-02T12:00:00.000Z"));
    const operatorAuth = createFakeOperatorAuth();
    const { handleRetire } = await loadControlHandlers();
    const response = await handleRetire(
      buildRetireRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(response.ok).toBe(true);
  });
});

describe("T-J1-14 deprecate_audit_records_successor", () => {
  it("writes control_audit deprecate with successor in after_pointer", async () => {
    buildJ1Registry();
    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();
    expect(
      (await handleDeprecate(buildDeprecateRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const audit = await env.DB.prepare(
      `SELECT operator_id, action, target, after_pointer FROM control_audit
       WHERE action = 'deprecate' ORDER BY recorded_at DESC LIMIT 1`,
    ).first<{
      operator_id: string;
      action: string;
      target: string;
      after_pointer: string | null;
    }>();

    expect(audit).toMatchObject({
      operator_id: FAKE_OPERATOR_ID,
      action: "deprecate",
      target: `${FIXTURE_CAPABILITY_ID}@${FIXTURE_CAPABILITY_VERSION}`,
      after_pointer: FIXTURE_SUCCESSOR_ID,
    });
  });
});

describe("T-J1-15 unauthenticated_mutations_rejected", () => {
  it("rejects deprecate and retire with 401 and no D1 writes", async () => {
    buildJ1Registry();
    const rejectAuth = createFakeOperatorAuth(null);
    const { handleDeprecate, handleRetire } = await loadControlHandlers();

    const beforeGrants = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM capability_grant`,
    ).first<{ n: number }>();
    const beforeAudit = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM control_audit`,
    ).first<{ n: number }>();

    for (const invoke of [
      () => handleDeprecate(buildDeprecateRequest(), { DB: env.DB }, rejectAuth),
      () => handleRetire(buildRetireRequest(), { DB: env.DB }, rejectAuth),
    ]) {
      const response = await invoke();
      expect(response.status).toBe(401);
      expect(await response.json()).toEqual({ error: "unauthorized" });
    }

    const afterGrants = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM capability_grant`,
    ).first<{ n: number }>();
    const afterAudit = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM control_audit`,
    ).first<{ n: number }>();
    expect(afterGrants?.n).toBe(beforeGrants?.n);
    expect(afterAudit?.n).toBe(beforeAudit?.n);
  });
});

describe("T-J1-16 retire_gates_not_deprecated_and_window_active", () => {
  it("rejects retire without deprecation and while the overlap window is active", async () => {
    buildJ1Registry();
    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate, handleRetire } = await loadControlHandlers();

    const notDeprecated = await handleRetire(
      buildRetireRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(notDeprecated.status).toBe(400);
    expect(await notDeprecated.json()).toEqual({ error: "not_deprecated" });

    expect(
      (await handleDeprecate(buildDeprecateRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const windowActive = await handleRetire(
      buildRetireRequest(),
      { DB: env.DB },
      operatorAuth,
    );
    expect(windowActive.status).toBe(400);
    expect(await windowActive.json()).toEqual({ error: "overlap_window_active" });
  });
});

describe("T-J1-17 discovery_excludes_retired", () => {
  it("omits an effective-retired version from discovery", async () => {
    buildJ1Registry();
    await seedInstallation(env.DB);
    await seedEntitlement(env.DB);
    await seedInstallationGrant(env.DB);

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate, handleRetire } = await loadControlHandlers();
    expect(
      (await handleDeprecate(buildDeprecateRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const overlay = await env.DB.prepare(
      `SELECT retire_after FROM capability_grant
       WHERE scope = 'global' AND capability_id = ?`,
    )
      .bind(FIXTURE_CAPABILITY_ID)
      .first<{ retire_after: string }>();
    vi.setSystemTime(new Date(overlay!.retire_after));
    expect(
      (await handleRetire(buildRetireRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const principal = buildPrincipal();
    const result = await discover(principal, new ConfigCache(), makePlatformD1Reader(env.DB));
    expect(
      result.manifests.find((m) => m.Identity.capabilityId === FIXTURE_CAPABILITY_ID),
    ).toBeUndefined();
  });
});

describe("T-J1-18 etag_invalidates_on_deprecation", () => {
  it("changes discovery etag after deprecate and again after retire", async () => {
    buildJ1Registry();
    await seedInstallation(env.DB);
    await seedEntitlement(env.DB);
    await seedInstallationGrant(env.DB);

    const principal = buildPrincipal();
    const reader = makePlatformD1Reader(env.DB);
    const before = await discover(principal, new ConfigCache(), reader);

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate, handleRetire } = await loadControlHandlers();
    expect(
      (await handleDeprecate(buildDeprecateRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const afterDeprecate = await discover(principal, new ConfigCache(), reader);
    expect(afterDeprecate.etag).not.toBe(before.etag);

    const overlay = await env.DB.prepare(
      `SELECT retire_after FROM capability_grant
       WHERE scope = 'global' AND capability_id = ?`,
    )
      .bind(FIXTURE_CAPABILITY_ID)
      .first<{ retire_after: string }>();
    vi.setSystemTime(new Date(overlay!.retire_after));
    expect(
      (await handleRetire(buildRetireRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const afterRetire = await discover(principal, new ConfigCache(), reader);
    expect(afterRetire.etag).not.toBe(afterDeprecate.etag);
  });
});

describe("T-J1-19 deprecated_serves_after_retire_after_before_operator_retire", () => {
  it("keeps serving a deprecated pin after the window when operator has not retired", async () => {
    buildJ1Registry();
    await seedInstallation(env.DB);
    await seedEntitlement(env.DB);
    await seedInstallationGrant(env.DB);

    const operatorAuth = createFakeOperatorAuth();
    const { handleDeprecate } = await loadControlHandlers();
    expect(
      (await handleDeprecate(buildDeprecateRequest(), { DB: env.DB }, operatorAuth)).ok,
    ).toBe(true);

    const overlay = await env.DB.prepare(
      `SELECT retire_after FROM capability_grant
       WHERE scope = 'global' AND capability_id = ?`,
    )
      .bind(FIXTURE_CAPABILITY_ID)
      .first<{ retire_after: string }>();
    vi.setSystemTime(new Date(new Date(overlay!.retire_after).getTime() + 60_000));

    const result = await resolve(
      buildPrincipal(),
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      new ConfigCache(),
      makePlatformD1Reader(env.DB),
    );
    expect(result.ok).toBe(true);
  });
});

describe("T-J1-20 published_lifecycle_without_overlay", () => {
  it("uses published Identity when no global overlay exists", async () => {
    buildRegistry(
      validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "deprecated", FIXTURE_SUCCESSOR_ID),
      validManifest(FIXTURE_SUCCESSOR_ID, "1.0.0"),
    );
    await seedInstallation(env.DB);
    await seedEntitlement(env.DB);
    await seedInstallationGrant(env.DB);

    const principal = buildPrincipal();
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);

    const resolved = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );
    expect(resolved.ok).toBe(true);

    const discovered = await discover(principal, cache, reader);
    const entry = discovered.manifests.find(
      (m) => m.Identity.capabilityId === FIXTURE_CAPABILITY_ID,
    );
    expect(entry?.Identity.lifecycleState).toBe("deprecated");
    expect(entry?.Identity.successorId).toBe(FIXTURE_SUCCESSOR_ID);

    buildRegistry(
      validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "retired", FIXTURE_SUCCESSOR_ID),
      validManifest(FIXTURE_SUCCESSOR_ID, "1.0.0"),
    );
    const retired = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      new ConfigCache(),
      reader,
    );
    expect(retired).toEqual({ ok: false, code: "capability_retired" });
  });
});
