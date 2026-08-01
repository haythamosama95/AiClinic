import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  ConfigCache,
  loadConfig,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";
import type { Principal } from "../src/identity";
import { hashManifest, load } from "../src/manifest";
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

function validManifest(
  capabilityId: string,
  version: string,
  lifecycleState: string = "active",
  minimumPlanTier: string = "standard",
): ManifestWire {
  return {
    Identity: {
      capabilityId,
      version,
      title: `${capabilityId} fixture`,
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
      perRequestCostCeiling: 0.05,
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
  setCapabilityRegistry(registry);
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

function makeReader(source: ReaderSource): ReaderSpy {
  const read = vi.fn(async (key: string): Promise<D1Row | "miss"> => {
    if (source === "miss") {
      return "miss";
    }
    if (typeof source === "function") {
      return source();
    }
    if (key in source) {
      return source[key];
    }
    return source as D1Row;
  });

  return {
    read,
    readCount: () => read.mock.calls.length,
  };
}

function scopeReaderForKind(reader: D1Reader, kind: ConfigEntityKind): D1Reader {
  return {
    read(key: string) {
      return reader.read(`${kind}:${key}`);
    },
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
    allowedCapabilities?: string[];
    installationId?: string;
  } = {},
): Promise<void> {
  const {
    plan = "professional",
    allowedCapabilities = [FIXTURE_GRANTED_CAPABILITY_ID],
    installationId = FIXTURE_INSTALLATION_ID,
  } = options;

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
      JSON.stringify(allowedCapabilities),
      0.8,
      "active",
    )
    .run();
}

async function seedCapabilityGrant(
  db: D1Database,
  capabilityId: string,
  capabilityVersion: string = FIXTURE_CAPABILITY_VERSION,
  installationId: string = FIXTURE_INSTALLATION_ID,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
    )
    .bind(
      `grant-${capabilityId}`,
      `installation:${installationId}`,
      capabilityId,
      capabilityVersion,
      FIXTURE_NOW,
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
            return { active: false, scope, target: auditTarget };
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
  const scoped = (kind: ConfigEntityKind) => scopeReaderForKind(reader, kind);

  for (const scope of [
    "global",
    `capability:${capabilityId}`,
    `installation:${installationId}`,
    `provider:${FIXTURE_PROVIDER_ID}`,
  ] as const) {
    await loadConfig(cache, scoped("kill_switches"), "kill_switches", scope);
  }
}

async function warmDiscoveryCache(
  cache: ConfigCache,
  reader: D1Reader,
  installationId: string,
  capabilityIds: string[],
): Promise<void> {
  const scoped = (kind: ConfigEntityKind) => scopeReaderForKind(reader, kind);

  await loadConfig(cache, scoped("installations"), "installations", installationId);
  await loadConfig(cache, scoped("entitlements"), "entitlements", installationId);

  for (const capabilityId of capabilityIds) {
    await loadConfig(
      cache,
      scoped("grants"),
      "grants",
      `${installationId}/${capabilityId}`,
    );
  }
}

describe("T-C1-01 resolver_exact_pin_resolves", () => {
  it("returns the pinned manifest for an exact version and rejects a different pin", async () => {
    buildRegistry(validManifest(FIXTURE_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION));

    const principal = buildPrincipal({ installationId: FIXTURE_INSTALLATION_ID });
    const cache = new ConfigCache();
    const reader = makeReader(
      makeInactiveKillSwitchRows(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID),
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
      makeInactiveKillSwitchRows(FIXTURE_INSTALLATION_ID, "clinic.unknown"),
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
      makeInactiveKillSwitchRows(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID),
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
      makeInactiveKillSwitchRows(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID),
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
      makeInactiveKillSwitchRows(FIXTURE_INSTALLATION_ID, FIXTURE_CAPABILITY_ID),
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

    const manifest = result.manifest;
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

  it("returns only the granted active manifest", async () => {
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
    await seedCapabilityGrant(db, FIXTURE_GRANTED_CAPABILITY_ID);
    await seedCapabilityGrant(db, FIXTURE_DEPRECATED_CAPABILITY_ID);
    await seedCapabilityGrant(db, FIXTURE_RETIRED_CAPABILITY_ID);

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
  it("returns 304 when If-None-Match matches and 200 when it does not", async () => {
    const manifests = [
      load(validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)),
    ];
    const etag = computeDiscoveryEtag(manifests);

    const stringifySpy = vi.spyOn(JSON, "stringify");

    const matchingRequest = new Request("https://ai.example/discovery", {
      headers: { "If-None-Match": etag },
    });
    const notModified = buildDiscoveryResponse(matchingRequest, manifests, etag);
    expect(notModified.status).toBe(304);
    expect(notModified.headers.get("ETag")).toBe(etag);
    expect(await notModified.text()).toBe("");
    expect(stringifySpy).not.toHaveBeenCalled();

    stringifySpy.mockClear();

    const mismatchedRequest = new Request("https://ai.example/discovery", {
      headers: { "If-None-Match": '"stale-etag"' },
    });
    const ok = buildDiscoveryResponse(mismatchedRequest, manifests, etag);
    expect(ok.status).toBe(200);
    expect(ok.headers.get("ETag")).toBe(etag);
    expect(await ok.json()).toEqual({ manifests });

    stringifySpy.mockRestore();
  });
});

describe("T-C1-09 discovery_etag_changes", () => {
  it("changes the etag when a manifest version changes or a granted manifest is removed", () => {
    const grantedActiveA = load(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION, "active"),
    );
    const grantedActiveB = load(
      validManifest("clinic.secondary", FIXTURE_CAPABILITY_VERSION, "active"),
    );

    const originalEtag = computeDiscoveryEtag([grantedActiveA, grantedActiveB]);

    const versionChanged = load(
      validManifest(FIXTURE_GRANTED_CAPABILITY_ID, "1.1.0", "active"),
    );
    const versionChangedEtag = computeDiscoveryEtag([versionChanged, grantedActiveB]);
    expect(versionChangedEtag).not.toBe(originalEtag);

    const removedFromSetEtag = computeDiscoveryEtag([grantedActiveA]);
    expect(removedFromSetEtag).not.toBe(originalEtag);

    expect(hashManifest(validManifest(FIXTURE_GRANTED_CAPABILITY_ID, "1.1.0"))).not.toBe(
      hashManifest(validManifest(FIXTURE_GRANTED_CAPABILITY_ID, FIXTURE_CAPABILITY_VERSION)),
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
