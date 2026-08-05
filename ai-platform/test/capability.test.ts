import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  ConfigCache,
  ConfigCacheMissError,
  loadConfig,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";
import type { Principal } from "../src/identity";
import { hashManifest, load, type Manifest } from "../src/manifest";
import {
  buildDiscoveryResponse,
  computeDiscoveryEtag,
  createCapabilityRegistry,
  discover,
  resolve,
  setCapabilityRegistry,
  type CapabilityRegistry,
} from "../src/capability";

type ManifestWire = Record<string, unknown>;
type D1Row = Record<string, unknown>;

type ReaderSource =
  | D1Row
  | "miss"
  | Record<string, D1Row | "miss">
  | (() => D1Row | "miss");

type ReaderSpy = D1Reader & {
  read: ReturnType<typeof vi.fn<(key: string) => Promise<D1Row | "miss">>>;
  readCount: () => number;
};

type PrincipalSeed = {
  installationId: string;
  plan?: string;
  allowedCapabilities?: string[];
};

type KillSwitchScope = "global" | "capability" | "installation" | "provider";

type ResolveFixtureOpts = {
  capabilityVersion?: string;
  plan?: string;
  allowedCapabilities?: string[];
  entitlementStatus?: string;
  includeRoutingPolicy?: boolean;
  grantVersion?: string;
  omitKillSwitches?: boolean;
};

const FIXTURE_INSTALLATION_ID = "inst-cap-001";
const FIXTURE_ORG_ID = "org-cap-001";
const FIXTURE_CAPABILITY_ID = "clinic.test";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_PROVIDER_ID = "deepseek";
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";
const FIXTURE_GRANTED_CAPABILITY_ID = "clinic.granted";
const FIXTURE_DEPRECATED_CAPABILITY_ID = "clinic.deprecated";
const FIXTURE_RETIRED_CAPABILITY_ID = "clinic.retired";
const FIXTURE_UNGRANTED_CAPABILITY_ID = "clinic.ungranted";
const FIXTURE_GATED_CAPABILITY_ID = "clinic.gated";
const FIXTURE_ROUTING_POLICY_REF = "routing/standard@v1";

function quotedEtag(raw: string): string {
  return `"${raw}"`;
}

function validManifest(
  capabilityId: string,
  version: string,
  lifecycleState: string = "active",
  minimumPlanTier: string = "standard",
  title?: string,
): ManifestWire {
  return {
    Identity: {
      capabilityId,
      version,
      title: title ?? `${capabilityId} fixture`,
      lifecycleState,
      successorId: null,
    },
    Access: {
      requiredCapabilityScope: `ai.${capabilityId}`,
      minimumPlanTier,
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
      routingPolicyRef: FIXTURE_ROUTING_POLICY_REF,
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

function buildRegistry(...manifests: ManifestWire[]): CapabilityRegistry {
  const loaded = manifests.map((wire) => load(wire));
  const registry = createCapabilityRegistry(loaded);
  setCapabilityRegistry(registry, { replace: true });
  return registry;
}

function buildPrincipal(seed: PrincipalSeed): Principal {
  return Object.freeze({
    installationId: seed.installationId,
    organizationId: FIXTURE_ORG_ID,
    branchId: "branch-cap-001",
    actorId: "actor-cap-001",
    role: "clinician",
    scopes: Object.freeze(
      (seed.allowedCapabilities ?? [FIXTURE_CAPABILITY_ID]).map(
        (capabilityId) => `ai.${capabilityId}`,
      ),
    ),
    jti: "jti-cap-001",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    ver: "1",
  });
}

/**
 * Absent keys must return `"miss"` — never fabricate the whole source object as a row.
 */
function makeReader(source: ReaderSource): ReaderSpy {
  const read = vi.fn(async (key: string): Promise<D1Row | "miss"> => {
    if (source === "miss") {
      return "miss";
    }
    if (typeof source === "function") {
      return source();
    }
    if (key in source) {
      return (source as Record<string, D1Row | "miss">)[key]!;
    }
    return "miss";
  });

  return {
    read,
    readCount: () => read.mock.calls.length,
  };
}

function makeInactiveKillSwitchRows(
  installationId: string,
  capabilityId: string,
): Record<string, D1Row> {
  return {
    "kill_switches:global": { active: false, scope: "global", target: "global" },
    [`kill_switches:capability:${capabilityId}`]: {
      active: false,
      scope: "capability",
      target: capabilityId,
    },
    [`kill_switches:installation:${installationId}`]: {
      active: false,
      scope: "installation",
      target: installationId,
    },
    [`kill_switches:provider:${FIXTURE_PROVIDER_ID}`]: {
      active: false,
      scope: "provider",
      target: FIXTURE_PROVIDER_ID,
    },
  };
}

/**
 * Seeds reader rows for a successful resolve under the post-C1-fix contract:
 * inactive kill switches, active professional entitlement, matching grant,
 * and (by default) a real routing-policy document (providers in rules[].targets[])
 * that unlocks provider kill-switch evaluation.
 */
function makeResolveFixtures(
  installationId: string,
  capabilityId: string,
  opts: ResolveFixtureOpts = {},
): Record<string, D1Row | "miss"> {
  const capabilityVersion = opts.capabilityVersion ?? FIXTURE_CAPABILITY_VERSION;
  const grantVersion = opts.grantVersion ?? capabilityVersion;
  const plan = opts.plan ?? "professional";
  const allowedCapabilities = opts.allowedCapabilities ?? [capabilityId];
  const entitlementStatus = opts.entitlementStatus ?? "active";
  const includeRoutingPolicy = opts.includeRoutingPolicy ?? true;

  const rows: Record<string, D1Row | "miss"> = {
    [`entitlements:${installationId}`]: {
      entitlement_id: `ent-${installationId}`,
      installation_id: installationId,
      plan,
      period_start: FIXTURE_NOW,
      period_end: FIXTURE_NOW,
      request_quota: 1_000,
      token_budget: 1_000_000,
      cost_budget: 100,
      allowed_capabilities: allowedCapabilities,
      soft_threshold: 0.8,
      status: entitlementStatus,
    },
    [`grants:${installationId}/${capabilityId}`]: {
      grant_id: `grant-${capabilityId}`,
      scope: `installation:${installationId}`,
      capability_id: capabilityId,
      capability_version: grantVersion,
      granted_at: FIXTURE_NOW,
      revoked_at: null,
      changed_at: FIXTURE_NOW,
      changed_by: "operator-test",
    },
  };

  if (!opts.omitKillSwitches) {
    Object.assign(rows, makeInactiveKillSwitchRows(installationId, capabilityId));
  }

  if (includeRoutingPolicy) {
    rows[`active_routing_policy:${FIXTURE_ROUTING_POLICY_REF}`] = {
      policy_id: "routing-standard",
      policy_version: 1,
      content_pointer: "control/routing-policy/routing-standard/1.json",
      active_from: FIXTURE_NOW,
      activated_by: "operator-test",
      document: {
        schema_version: 1,
        policy_id: "routing-standard",
        policy_version: 1,
        defaults: {
          cost_class: "standard",
          max_parallel_attempts: 1,
        },
        rules: [
          {
            rule_id: "catch-all",
            match: {},
            requires: {
              structured_output: false,
              min_context_window: 0,
              languages: [],
            },
            targets: [
              {
                provider_id: FIXTURE_PROVIDER_ID,
                model_id: "fixture-model",
                features: {
                  structured_output: false,
                  min_context_window: 32_000,
                  languages: ["en"],
                  latency_class: "standard",
                  cost_class: "standard",
                },
                max_attempts: 2,
                timeout_ms: 30_000,
              },
            ],
          },
        ],
        overrides: [],
      },
    };
  }

  return rows;
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

async function clearEntitlementTables(db: D1Database): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM control_audit"),
    db.prepare("DELETE FROM capability_grant"),
    db.prepare("DELETE FROM entitlement"),
    db.prepare("DELETE FROM installation_key"),
    db.prepare("DELETE FROM installation"),
  ]);
}

async function seedInstallation(
  db: D1Database,
  installationId: string = FIXTURE_INSTALLATION_ID,
  status: string = "active",
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
      "Capability Test Clinic",
      status,
      "us-east-1",
      FIXTURE_NOW,
    )
    .run();
}

async function seedEntitlement(
  db: D1Database,
  options: {
    plan?: string;
    allowedCapabilities?: string[] | string;
    installationId?: string;
    status?: string;
  } = {},
): Promise<void> {
  const {
    plan = "professional",
    allowedCapabilities = [FIXTURE_GRANTED_CAPABILITY_ID],
    installationId = FIXTURE_INSTALLATION_ID,
    status = "active",
  } = options;

  const allowedValue =
    typeof allowedCapabilities === "string"
      ? allowedCapabilities
      : JSON.stringify(allowedCapabilities);

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
      allowedValue,
      0.8,
      status,
    )
    .run();
}

async function seedCapabilityGrant(
  db: D1Database,
  capabilityId: string,
  capabilityVersion: string = FIXTURE_CAPABILITY_VERSION,
  installationId: string = FIXTURE_INSTALLATION_ID,
  revokedAt: string | null = null,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      `grant-${capabilityId}-${capabilityVersion}`,
      `installation:${installationId}`,
      capabilityId,
      capabilityVersion,
      FIXTURE_NOW,
      revokedAt,
      FIXTURE_NOW,
      "operator-test",
    )
    .run();
}

async function seedKillSwitch(
  db: D1Database,
  scope: KillSwitchScope,
  target: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO control_audit (
        audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at
      ) VALUES (?, ?, ?, ?, NULL, NULL, ?)`,
    )
    .bind(
      crypto.randomUUID(),
      "operator-test",
      `kill_switch_${scope}`,
      target,
      FIXTURE_NOW,
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
        case "installations": {
          const row = await db
            .prepare(
              "SELECT installation_id, org_id, display_name, status, region, enrolled_at FROM installation WHERE installation_id = ?",
            )
            .bind(key)
            .first<D1Row>();
          return row ?? "miss";
        }
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
          const [installationId, capabilityId] = key.split("/", 2);
          // Return revoked rows too — discover()/resolve() enforce revoked_at.
          const row = await db
            .prepare(
              `SELECT grant_id, scope, capability_id, capability_version,
                      granted_at, revoked_at, changed_at, changed_by
               FROM capability_grant
               WHERE scope = ? AND capability_id = ?
               ORDER BY CASE WHEN revoked_at IS NULL THEN 0 ELSE 1 END, granted_at DESC
               LIMIT 1`,
            )
            .bind(`installation:${installationId}`, capabilityId)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "kill_switches": {
          const [scope, ...rest] = key.split(":");
          const target = rest.length > 0 ? rest.join(":") : scope;
          const action =
            scope === "global" ? "kill_switch_global" : `kill_switch_${scope}`;
          const auditTarget = scope === "global" ? "global" : target;
          const row = await db
            .prepare(
              `SELECT action, target FROM control_audit
               WHERE action = ? AND target = ?
               ORDER BY recorded_at DESC LIMIT 1`,
            )
            .bind(action, auditTarget)
            .first<D1Row>();
          if (!row) {
            return "miss";
          }
          return { active: true, scope, target: auditTarget, action: row.action };
        }
        default:
          return "miss";
      }
    },
  };
}

async function warmResolveCache(
  cache: ConfigCache,
  reader: D1Reader,
  installationId: string,
  capabilityId: string,
): Promise<void> {
  try {
    await loadConfig(cache, reader, "entitlements", installationId);
  } catch (error) {
    if (!(error instanceof ConfigCacheMissError)) {
      throw error;
    }
  }

  try {
    await loadConfig(
      cache,
      reader,
      "grants",
      `${installationId}/${capabilityId}`,
    );
  } catch (error) {
    if (!(error instanceof ConfigCacheMissError)) {
      throw error;
    }
  }

  try {
    await loadConfig(
      cache,
      reader,
      "active_routing_policy",
      FIXTURE_ROUTING_POLICY_REF,
    );
  } catch (error) {
    if (!(error instanceof ConfigCacheMissError)) {
      throw error;
    }
  }

  for (const scope of [
    "global",
    `capability:${capabilityId}`,
    `installation:${installationId}`,
    `provider:${FIXTURE_PROVIDER_ID}`,
  ] as const) {
    try {
      await loadConfig(cache, reader, "kill_switches", scope);
    } catch (error) {
      if (!(error instanceof ConfigCacheMissError)) {
        throw error;
      }
    }
  }
}

async function warmDiscoveryCache(
  cache: ConfigCache,
  reader: D1Reader,
  installationId: string,
  capabilityIds: string[],
): Promise<void> {
  await loadConfig(cache, reader, "installations", installationId);
  try {
    await loadConfig(cache, reader, "entitlements", installationId);
  } catch (error) {
    if (!(error instanceof ConfigCacheMissError)) {
      throw error;
    }
  }

  for (const capabilityId of capabilityIds) {
    try {
      await loadConfig(
        cache,
        reader,
        "grants",
        `${installationId}/${capabilityId}`,
      );
    } catch (error) {
      if (!(error instanceof ConfigCacheMissError)) {
        throw error;
      }
    }
  }
}

function assertManifestImmutable(manifest: Manifest): void {
  const originalTitle = manifest.Identity.title;
  const originalRequirements = manifest["Context requirements"];

  let identityWriteThrew = false;
  try {
    (manifest.Identity as { title: string }).title = "mutated title";
  } catch {
    identityWriteThrew = true;
  }

  let requirementsWriteThrew = false;
  try {
    (manifest as Record<string, unknown>)["Context requirements"] = [];
  } catch {
    requirementsWriteThrew = true;
  }

  expect(identityWriteThrew || manifest.Identity.title === originalTitle).toBe(true);
  expect(
    requirementsWriteThrew ||
      manifest["Context requirements"] === originalRequirements,
  ).toBe(true);
  expect(manifest.Identity.title).toBe(originalTitle);
  expect(manifest["Context requirements"]).toEqual(originalRequirements);
}

describe("T-C1-01 resolver_exact_pin_resolves", () => {
  it("returns the pinned manifest for an exact version and rejects a different pin", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(
      makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID),
    );

    const exact = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );
    expect(exact).toEqual({
      ok: true,
      manifest: expect.objectContaining({
        Identity: expect.objectContaining({ version: FIXTURE_CAPABILITY_VERSION }),
      }),
    });

    const mismatched = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      "1.2.0",
      cache,
      reader,
    );
    expect(mismatched).toEqual({ ok: false, code: "capability_unknown" });
  });
});

describe("T-C1-02 resolver_unknown_capability", () => {
  it("returns capability_unknown for a capability id not in the registry", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(
      makeResolveFixtures(FIXTURE_INSTALLATION_ID, "clinic.unknown"),
    );

    const result = await resolve(
      principal,
      "clinic.unknown",
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );

    expect(result).toEqual({ ok: false, code: "capability_unknown" });
  });
});

describe("T-C1-03 resolver_retired_rejected", () => {
  it("returns capability_retired when the manifest lifecycle is retired", async () => {
    buildRegistry(
      validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "retired"),
    );

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(
      makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID),
    );

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

describe("T-C1-04 resolver_killed_capability_disabled", () => {
  let db: D1Database;

  beforeAll(async () => {
    const workers = await import("cloudflare:test");
    db = workers.env.DB;
    await applyPlatformSchema(db, migrationSql);
  });

  beforeEach(async () => {
    await clearEntitlementTables(db);
  });

  it("returns capability_disabled when a capability kill switch is active", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    await seedInstallation(db);
    await seedEntitlement(db, { allowedCapabilities: [FIXTURE_CAPABILITY_ID] });
    await seedCapabilityGrant(db, FIXTURE_CAPABILITY_ID);
    await seedKillSwitch(db, "capability", FIXTURE_CAPABILITY_ID);

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(db);
    await warmResolveCache(cache, reader, FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID);

    const result = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );

    expect(result).toEqual({ ok: false, code: "capability_disabled" });
  });
});

describe("T-C1-05 resolver_deprecated_serves", () => {
  it("serves a deprecated manifest instead of rejecting it", async () => {
    buildRegistry(
      validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "deprecated"),
    );

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(
      makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID),
    );

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
    expect(result.manifest.Identity.lifecycleState).toBe("deprecated");
    expect(result.manifest.Identity.version).toBe(FIXTURE_CAPABILITY_VERSION);
  });
});

describe("T-C1-06 resolver_manifest_immutable", () => {
  it("does not allow mutation of the manifest returned by resolve", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(
      makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID),
    );

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

    assertManifestImmutable(result.manifest);
  });
});

describe("T-C1-07 discovery_only_granted_active", () => {
  let db: D1Database;

  beforeAll(async () => {
    const workers = await import("cloudflare:test");
    db = workers.env.DB;
    await applyPlatformSchema(db, migrationSql);
  });

  beforeEach(async () => {
    await clearEntitlementTables(db);
  });

  it("returns only the granted active manifest (deprecated/retired ungranted)", async () => {
    buildRegistry(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "active"),
      validManifest(
        FIXTURE_DEPRECATED_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "deprecated",
      ),
      validManifest(FIXTURE_RETIRED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "retired"),
      validManifest(
        FIXTURE_UNGRANTED_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "active",
      ),
    );

    await seedInstallation(db);
    await seedEntitlement(db, { allowedCapabilities: [FIXTURE_GRANTED_CAPABILITY_ID] });
    // Grant only the active capability — published-deprecated visibility is covered
    // by discovery_published_deprecated_included (Bug 6).
    await seedCapabilityGrant(db, FIXTURE_GRANTED_CAPABILITY_ID);

    const principal = buildPrincipal({
      installationId: FIXTURE_INSTALLATION_ID,
      allowedCapabilities: [FIXTURE_GRANTED_CAPABILITY_ID],
    });
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(db);
    await warmDiscoveryCache(cache, reader, FIXTURE_INSTALLATION_ID, [
      FIXTURE_GRANTED_CAPABILITY_ID,
      FIXTURE_DEPRECATED_CAPABILITY_ID,
      FIXTURE_RETIRED_CAPABILITY_ID,
      FIXTURE_UNGRANTED_CAPABILITY_ID,
    ]);

    const result = await discover(principal, cache, reader);

    expect(result.manifests).toHaveLength(1);
    expect(result.manifests[0]?.Identity.capabilityId).toBe(FIXTURE_GRANTED_CAPABILITY_ID);
    expect(result.manifests[0]?.Identity.lifecycleState).toBe("active");
  });
});

describe("T-C1-08 discovery_etag_not_modified", () => {
  it("returns 304 when quoted If-None-Match matches and 200 when it does not", async () => {
    const manifests = [
      load(validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)),
    ];
    const rawEtag = await computeDiscoveryEtag(manifests);
    const wireEtag = quotedEtag(rawEtag);

    const stringifySpy = vi.spyOn(JSON, "stringify");

    const matchingRequest = new Request("https://ai.example/discovery", {
      headers: { "If-None-Match": wireEtag },
    });
    const notModified = buildDiscoveryResponse(matchingRequest, manifests, rawEtag);
    expect(notModified.status).toBe(304);
    expect(notModified.headers.get("ETag")).toBe(wireEtag);
    expect(notModified.headers.get("Cache-Control")).toBe("private, must-revalidate");
    expect(await notModified.text()).toBe("");
    expect(stringifySpy).not.toHaveBeenCalled();

    stringifySpy.mockClear();

    const mismatchedRequest = new Request("https://ai.example/discovery", {
      headers: { "If-None-Match": '"stale-etag"' },
    });
    const ok = buildDiscoveryResponse(mismatchedRequest, manifests, rawEtag);
    expect(ok.status).toBe(200);
    expect(ok.headers.get("ETag")).toBe(wireEtag);
    expect(ok.headers.get("Cache-Control")).toBe("private, must-revalidate");
    expect(await ok.json()).toEqual({ manifests });

    stringifySpy.mockRestore();
  });
});

describe("T-C1-09 discovery_etag_changes", () => {
  it("changes the etag when a manifest version changes or a granted manifest is removed", async () => {
    const grantedActiveA = load(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "active"),
    );
    const grantedActiveB = load(
      validManifest("clinic.secondary", FIXTURE_CAPABILITY_VERSION, "active"),
    );

    const originalEtag = await computeDiscoveryEtag([grantedActiveA, grantedActiveB]);

    const versionChanged = load(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, "1.1.0", "active"),
    );
    const versionChangedEtag = await computeDiscoveryEtag([versionChanged, grantedActiveB]);
    expect(versionChangedEtag).not.toBe(originalEtag);

    const removedFromSetEtag = await computeDiscoveryEtag([grantedActiveA]);
    expect(removedFromSetEtag).not.toBe(originalEtag);

    expect(await hashManifest(validManifest(FIXTURE_GRANTED_CAPABILITY_ID, "1.1.0"))).not.toBe(
      await hashManifest(validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)),
    );
  });
});

describe("T-C1-10 discovery_entitlement_gated_absent", () => {
  let db: D1Database;

  beforeAll(async () => {
    const workers = await import("cloudflare:test");
    db = workers.env.DB;
    await applyPlatformSchema(db, migrationSql);
  });

  beforeEach(async () => {
    await clearEntitlementTables(db);
  });

  it("filters out a capability when allowed_capabilities omits it", async () => {
    buildRegistry(
      validManifest(FIXTURE_GATED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "active"),
    );

    await seedInstallation(db);
    await seedEntitlement(db, { allowedCapabilities: [] });

    const principal = buildPrincipal({
      installationId: FIXTURE_INSTALLATION_ID,
      allowedCapabilities: [],
    });
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(db);
    await warmDiscoveryCache(cache, reader, FIXTURE_INSTALLATION_ID, [
      FIXTURE_GATED_CAPABILITY_ID,
    ]);

    const result = await discover(principal, cache, reader);

    expect(result.manifests).toHaveLength(0);
    expect(
      result.manifests.some(
        (manifest) => manifest.Identity.capabilityId === FIXTURE_GATED_CAPABILITY_ID,
      ),
    ).toBe(false);
  });

  it("filters out a capability when the entitlement plan is below minimumPlanTier", async () => {
    buildRegistry(
      validManifest(
        FIXTURE_GATED_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "active",
        "standard",
      ),
    );

    await seedInstallation(db);
    await seedEntitlement(db, {
      plan: "starter",
      allowedCapabilities: [FIXTURE_GATED_CAPABILITY_ID],
    });
    await seedCapabilityGrant(db, FIXTURE_GATED_CAPABILITY_ID);

    const principal = buildPrincipal({
      installationId: FIXTURE_INSTALLATION_ID,
      allowedCapabilities: [FIXTURE_GATED_CAPABILITY_ID],
    });
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(db);
    await warmDiscoveryCache(cache, reader, FIXTURE_INSTALLATION_ID, [
      FIXTURE_GATED_CAPABILITY_ID,
    ]);

    const result = await discover(principal, cache, reader);

    expect(result.manifests).toHaveLength(0);
    expect(
      result.manifests.some(
        (manifest) => manifest.Identity.capabilityId === FIXTURE_GATED_CAPABILITY_ID,
      ),
    ).toBe(false);
  });
});

describe("resolver_grant_version_mismatch_forbidden", () => {
  it("returns forbidden_capability when the pin does not match the granted version", async () => {
    buildRegistry(
      validManifest(FIXTURE_CAPABILITY_ID, "1.0.0"),
      validManifest(FIXTURE_CAPABILITY_ID, "2.0.0"),
    );

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(
      makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID, {
        capabilityVersion: "2.0.0",
        grantVersion: "1.0.0",
      }),
    );

    const result = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      "2.0.0",
      cache,
      reader,
    );

    expect(result).toEqual({ ok: false, code: "forbidden_capability" });
  });
});

describe("resolver_not_allowed_forbidden", () => {
  it("returns forbidden_capability when the capability is absent from allowed_capabilities", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(
      makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID, {
        allowedCapabilities: ["clinic.other"],
      }),
    );

    const result = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );

    expect(result).toEqual({ ok: false, code: "forbidden_capability" });
  });
});

describe("resolver_plan_tier_forbidden", () => {
  it("returns forbidden_capability when the plan is below minimumPlanTier", async () => {
    buildRegistry(
      validManifest(
        FIXTURE_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "active",
        "professional",
      ),
    );

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(
      makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID, {
        plan: "starter",
      }),
    );

    const result = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );

    expect(result).toEqual({ ok: false, code: "forbidden_capability" });
  });
});

describe("resolver_kill_switch_global_active", () => {
  it("returns capability_disabled when the global kill switch is active", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const rows = makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID);
    rows["kill_switches:global"] = {
      active: true,
      scope: "global",
      target: "global",
    };

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(rows);

    const result = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );

    expect(result).toEqual({ ok: false, code: "capability_disabled" });
  });
});

describe("resolver_kill_switch_installation_active", () => {
  it("returns capability_disabled when the installation kill switch is active", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const rows = makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID);
    rows[`kill_switches:installation:${FIXTURE_INSTALLATION_ID}`] = {
      active: true,
      scope: "installation",
      target: FIXTURE_INSTALLATION_ID,
    };

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(rows);

    const result = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );

    expect(result).toEqual({ ok: false, code: "capability_disabled" });
  });
});

describe("resolver_kill_switch_provider_active", () => {
  it("returns capability_disabled when the provider kill switch is active", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const rows = makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID);
    rows[`kill_switches:provider:${FIXTURE_PROVIDER_ID}`] = {
      active: true,
      scope: "provider",
      target: FIXTURE_PROVIDER_ID,
    };

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(rows);

    const result = await resolve(
      principal,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      cache,
      reader,
    );

    expect(result).toEqual({ ok: false, code: "capability_disabled" });
  });
});

describe("resolver_provider_policy_miss_skips_provider_switch", () => {
  it("does not evaluate the provider kill switch when routing policy is missing", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const rows = makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID, {
      includeRoutingPolicy: false,
    });
    rows[`kill_switches:provider:${FIXTURE_PROVIDER_ID}`] = {
      active: true,
      scope: "provider",
      target: FIXTURE_PROVIDER_ID,
    };

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(rows);

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
  });
});

describe("resolver_retired_short_circuits_before_kill", () => {
  it("returns capability_retired even when a kill switch is also active", async () => {
    buildRegistry(
      validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "retired"),
    );

    const rows = makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID);
    rows[`kill_switches:capability:${FIXTURE_CAPABILITY_ID}`] = {
      active: true,
      scope: "capability",
      target: FIXTURE_CAPABILITY_ID,
    };

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(rows);

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

describe("resolver_kill_switch_miss_inactive", () => {
  it("treats missing kill-switch rows as inactive and still serves", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(
      makeResolveFixtures(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID, {
        omitKillSwitches: true,
      }),
    );

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
    expect(result.manifest.Identity.version).toBe(FIXTURE_CAPABILITY_VERSION);
  });
});

describe("discovery_revoked_grant_excluded", () => {
  let db: D1Database;

  beforeAll(async () => {
    const workers = await import("cloudflare:test");
    db = workers.env.DB;
    await applyPlatformSchema(db, migrationSql);
  });

  beforeEach(async () => {
    await clearEntitlementTables(db);
  });

  it("excludes a capability whose grant has revoked_at set", async () => {
    buildRegistry(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "active"),
    );

    await seedInstallation(db);
    await seedEntitlement(db, {
      allowedCapabilities: [FIXTURE_GRANTED_CAPABILITY_ID],
    });
    await seedCapabilityGrant(
      db,
      FIXTURE_GRANTED_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      FIXTURE_INSTALLATION_ID,
      FIXTURE_NOW,
    );

    const principal = buildPrincipal({
      installationId: FIXTURE_INSTALLATION_ID,
      allowedCapabilities: [FIXTURE_GRANTED_CAPABILITY_ID],
    });
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(db);
    await warmDiscoveryCache(cache, reader, FIXTURE_INSTALLATION_ID, [
      FIXTURE_GRANTED_CAPABILITY_ID,
    ]);

    const result = await discover(principal, cache, reader);

    expect(result.manifests).toHaveLength(0);
  });
});

describe("discovery_granted_version_mismatch_excluded", () => {
  let db: D1Database;

  beforeAll(async () => {
    const workers = await import("cloudflare:test");
    db = workers.env.DB;
    await applyPlatformSchema(db, migrationSql);
  });

  beforeEach(async () => {
    await clearEntitlementTables(db);
  });

  it("returns only the granted version when multiple versions are registered", async () => {
    buildRegistry(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, "1.0.0", "active"),
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, "2.0.0", "active"),
    );

    await seedInstallation(db);
    await seedEntitlement(db, {
      allowedCapabilities: [FIXTURE_GRANTED_CAPABILITY_ID],
    });
    await seedCapabilityGrant(db, FIXTURE_GRANTED_CAPABILITY_ID, "1.0.0");

    const principal = buildPrincipal({
      installationId: FIXTURE_INSTALLATION_ID,
      allowedCapabilities: [FIXTURE_GRANTED_CAPABILITY_ID],
    });
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(db);
    await warmDiscoveryCache(cache, reader, FIXTURE_INSTALLATION_ID, [
      FIXTURE_GRANTED_CAPABILITY_ID,
    ]);

    const result = await discover(principal, cache, reader);

    expect(result.manifests).toHaveLength(1);
    expect(result.manifests[0]?.Identity.capabilityId).toBe(FIXTURE_GRANTED_CAPABILITY_ID);
    expect(result.manifests[0]?.Identity.version).toBe("1.0.0");
  });
});

describe("discovery_entitlement_missing_empty", () => {
  it("returns an empty set and the empty-set etag when entitlement is missing", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader({});
    const emptyEtag = await computeDiscoveryEtag([]);

    const result = await discover(principal, cache, reader);

    expect(result.manifests).toHaveLength(0);
    expect(result.etag).toBe(emptyEtag);
  });
});

describe("discovery_entitlement_inactive_empty", () => {
  it("returns an empty set and the empty-set etag when entitlement is inactive", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader({
      [`entitlements:${FIXTURE_INSTALLATION_ID}`]: {
        entitlement_id: `ent-${FIXTURE_INSTALLATION_ID}`,
        installation_id: FIXTURE_INSTALLATION_ID,
        plan: "professional",
        allowed_capabilities: [FIXTURE_CAPABILITY_ID],
        status: "inactive",
      },
    });
    const emptyEtag = await computeDiscoveryEtag([]);

    const result = await discover(principal, cache, reader);

    expect(result.manifests).toHaveLength(0);
    expect(result.etag).toBe(emptyEtag);
  });
});

describe("discovery_entitlement_non_string_plan_empty", () => {
  it("returns an empty set and the empty-set etag when plan is not a string", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader({
      [`entitlements:${FIXTURE_INSTALLATION_ID}`]: {
        entitlement_id: `ent-${FIXTURE_INSTALLATION_ID}`,
        installation_id: FIXTURE_INSTALLATION_ID,
        plan: 42,
        allowed_capabilities: [FIXTURE_CAPABILITY_ID],
        status: "active",
      },
    });
    const emptyEtag = await computeDiscoveryEtag([]);

    const result = await discover(principal, cache, reader);

    expect(result.manifests).toHaveLength(0);
    expect(result.etag).toBe(emptyEtag);
  });
});

describe("discovery_malformed_allowed_capabilities_empty", () => {
  it("fail-closes to an empty discovery set when allowed_capabilities is malformed", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader({
      [`entitlements:${FIXTURE_INSTALLATION_ID}`]: {
        entitlement_id: `ent-${FIXTURE_INSTALLATION_ID}`,
        installation_id: FIXTURE_INSTALLATION_ID,
        plan: "professional",
        allowed_capabilities: "{not-json",
        status: "active",
      },
      [`grants:${FIXTURE_INSTALLATION_ID}/${FIXTURE_CAPABILITY_ID}`]: {
        grant_id: `grant-${FIXTURE_CAPABILITY_ID}`,
        scope: `installation:${FIXTURE_INSTALLATION_ID}`,
        capability_id: FIXTURE_CAPABILITY_ID,
        capability_version: FIXTURE_CAPABILITY_VERSION,
        granted_at: FIXTURE_NOW,
        revoked_at: null,
      },
    });
    const emptyEtag = await computeDiscoveryEtag([]);

    const result = await discover(principal, cache, reader);

    expect(result.manifests).toHaveLength(0);
    expect(result.etag).toBe(emptyEtag);
  });
});

describe("discovery_caller_manifest_immutable", () => {
  let db: D1Database;

  beforeAll(async () => {
    const workers = await import("cloudflare:test");
    db = workers.env.DB;
    await applyPlatformSchema(db, migrationSql);
  });

  beforeEach(async () => {
    await clearEntitlementTables(db);
  });

  it("does not allow mutation of manifests returned by discover", async () => {
    buildRegistry(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "active"),
    );

    await seedInstallation(db);
    await seedEntitlement(db, {
      allowedCapabilities: [FIXTURE_GRANTED_CAPABILITY_ID],
    });
    await seedCapabilityGrant(db, FIXTURE_GRANTED_CAPABILITY_ID);

    const principal = buildPrincipal({
      installationId: FIXTURE_INSTALLATION_ID,
      allowedCapabilities: [FIXTURE_GRANTED_CAPABILITY_ID],
    });
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(db);
    await warmDiscoveryCache(cache, reader, FIXTURE_INSTALLATION_ID, [
      FIXTURE_GRANTED_CAPABILITY_ID,
    ]);

    const result = await discover(principal, cache, reader);
    expect(result.manifests).toHaveLength(1);
    assertManifestImmutable(result.manifests[0]!);
  });
});

describe("discovery_published_deprecated_included", () => {
  let db: D1Database;

  beforeAll(async () => {
    const workers = await import("cloudflare:test");
    db = workers.env.DB;
    await applyPlatformSchema(db, migrationSql);
  });

  beforeEach(async () => {
    await clearEntitlementTables(db);
  });

  it("includes a published-deprecated manifest with a matching grant and no overlay", async () => {
    buildRegistry(
      validManifest(
        FIXTURE_DEPRECATED_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "deprecated",
      ),
    );

    await seedInstallation(db);
    await seedEntitlement(db, {
      allowedCapabilities: [FIXTURE_DEPRECATED_CAPABILITY_ID],
    });
    await seedCapabilityGrant(db, FIXTURE_DEPRECATED_CAPABILITY_ID);

    const principal = buildPrincipal({
      installationId: FIXTURE_INSTALLATION_ID,
      allowedCapabilities: [FIXTURE_DEPRECATED_CAPABILITY_ID],
    });
    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(db);
    await warmDiscoveryCache(cache, reader, FIXTURE_INSTALLATION_ID, [
      FIXTURE_DEPRECATED_CAPABILITY_ID,
    ]);

    const result = await discover(principal, cache, reader);

    expect(result.manifests).toHaveLength(1);
    expect(result.manifests[0]?.Identity.capabilityId).toBe(
      FIXTURE_DEPRECATED_CAPABILITY_ID,
    );
    expect(result.manifests[0]?.Identity.lifecycleState).toBe("deprecated");
  });
});

describe("discovery_etag_order_independent", () => {
  it("yields the same etag for the same set regardless of input order", async () => {
    const first = load(validManifest("clinic.alpha", FIXTURE_CAPABILITY_VERSION));
    const second = load(validManifest("clinic.beta", FIXTURE_CAPABILITY_VERSION));

    const forward = await computeDiscoveryEtag([first, second]);
    const reverse = await computeDiscoveryEtag([second, first]);

    expect(forward).toBe(reverse);
  });
});

describe("discovery_etag_content_only_change", () => {
  it("changes the etag when only non-key content (title) changes", async () => {
    const original = load(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION),
    );
    const retitled = load(
      validManifest(
        FIXTURE_GRANTED_CAPABILITY_ID,
        FIXTURE_CAPABILITY_VERSION,
        "active",
        "standard",
        "retitled fixture",
      ),
    );

    const originalEtag = await computeDiscoveryEtag([original]);
    const retitledEtag = await computeDiscoveryEtag([retitled]);

    expect(retitledEtag).not.toBe(originalEtag);
  });
});

describe("discovery_if_none_match_absent_200", () => {
  it("returns 200 with quoted ETag and Cache-Control when If-None-Match is absent", async () => {
    const manifests = [
      load(validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)),
    ];
    const rawEtag = await computeDiscoveryEtag(manifests);
    const wireEtag = quotedEtag(rawEtag);

    const response = buildDiscoveryResponse(
      new Request("https://ai.example/discovery"),
      manifests,
      rawEtag,
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("ETag")).toBe(wireEtag);
    expect(response.headers.get("Cache-Control")).toBe("private, must-revalidate");
    expect(await response.json()).toEqual({ manifests });
  });
});

describe("discovery_if_none_match_star_304", () => {
  it("returns 304 when If-None-Match is *", async () => {
    const manifests = [
      load(validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)),
    ];
    const rawEtag = await computeDiscoveryEtag(manifests);
    const wireEtag = quotedEtag(rawEtag);

    const response = buildDiscoveryResponse(
      new Request("https://ai.example/discovery", {
        headers: { "If-None-Match": "*" },
      }),
      manifests,
      rawEtag,
    );

    expect(response.status).toBe(304);
    expect(response.headers.get("ETag")).toBe(wireEtag);
    expect(response.headers.get("Cache-Control")).toBe("private, must-revalidate");
  });
});

describe("discovery_if_none_match_list_with_match_304", () => {
  it("returns 304 when a quoted etag list contains the current etag", async () => {
    const manifests = [
      load(validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)),
    ];
    const rawEtag = await computeDiscoveryEtag(manifests);
    const wireEtag = quotedEtag(rawEtag);

    const response = buildDiscoveryResponse(
      new Request("https://ai.example/discovery", {
        headers: { "If-None-Match": `"stale-a", ${wireEtag}, "stale-b"` },
      }),
      manifests,
      rawEtag,
    );

    expect(response.status).toBe(304);
    expect(response.headers.get("ETag")).toBe(wireEtag);
    expect(response.headers.get("Cache-Control")).toBe("private, must-revalidate");
  });
});

describe("discovery_if_none_match_weak_304", () => {
  it("returns 304 when If-None-Match carries a weak validator for the current etag", async () => {
    const manifests = [
      load(validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)),
    ];
    const rawEtag = await computeDiscoveryEtag(manifests);
    const wireEtag = quotedEtag(rawEtag);

    const response = buildDiscoveryResponse(
      new Request("https://ai.example/discovery", {
        headers: { "If-None-Match": `W/${wireEtag}` },
      }),
      manifests,
      rawEtag,
    );

    expect(response.status).toBe(304);
    expect(response.headers.get("ETag")).toBe(wireEtag);
    expect(response.headers.get("Cache-Control")).toBe("private, must-revalidate");
  });
});

describe("registry_rejects_non_string_identity", () => {
  it("throws when capabilityId or version is not a string", () => {
    const base = load(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));
    const badId = {
      ...base,
      Identity: { ...base.Identity, capabilityId: 123 },
    } as unknown as Manifest;
    const badVersion = {
      ...base,
      Identity: { ...base.Identity, version: 1 },
    } as unknown as Manifest;

    expect(() => createCapabilityRegistry([badId])).toThrow();
    expect(() => createCapabilityRegistry([badVersion])).toThrow();
  });
});

describe("registry_map_unmodifiable", () => {
  it("rejects set, delete, and clear on the registry Map", () => {
    const registry = createCapabilityRegistry([
      load(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)),
    ]);
    const sample = load(validManifest("clinic.other", FIXTURE_CAPABILITY_VERSION));

    expect(() => registry.set("clinic.other@1.0.0", sample)).toThrow();
    expect(() =>
      registry.delete(`${FIXTURE_CAPABILITY_ID}@${FIXTURE_CAPABILITY_VERSION}`),
    ).toThrow();
    expect(() => registry.clear()).toThrow();
  });
});

describe("set_capability_registry_install_once", () => {
  it("rejects a second install unless replace is true", () => {
    const first = createCapabilityRegistry([
      load(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)),
    ]);
    setCapabilityRegistry(first, { replace: true });

    const second = createCapabilityRegistry([
      load(validManifest(FIXTURE_CAPABILITY_ID, "2.0.0")),
    ]);

    expect(() => setCapabilityRegistry(second)).toThrow();
    expect(() => setCapabilityRegistry(second, { replace: true })).not.toThrow();
  });
});
