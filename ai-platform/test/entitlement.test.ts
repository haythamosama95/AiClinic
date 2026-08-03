import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  ConfigCache,
  ConfigCacheMissError,
  loadConfig,
  type ConfigEntityKind,
  type D1Reader,
} from "../src/config-cache";

type D1Row = Record<string, unknown>;

/** Mirrors `request-principal.md` — consumed by entitlement stage input. */
type Principal = {
  installationId: string;
  organizationId: string;
  branchId: string;
  actorId: string;
  role: string;
  scopes: readonly string[];
  jti: string;
  iat: number;
  exp: number;
  ver: string;
};

/** Request context for entitlement evaluation (no manifest lookup in B3). */
type EntitlementContext = {
  capabilityId: string;
  capabilityVersion: string;
  minimumPlanTier: string;
  providerId: string;
};

type EntitlementRejectionPath =
  | "ai_disabled"
  | "plan_tier"
  | "capability_not_granted"
  | "kill_switch_global"
  | "kill_switch_capability"
  | "kill_switch_installation"
  | "kill_switch_provider";

type EntitlementResult =
  | { ok: true }
  | {
      ok: false;
      code: "forbidden_capability" | "capability_disabled";
      path: EntitlementRejectionPath;
    };

type ReaderSource =
  | D1Row
  | "miss"
  | Record<string, D1Row | "miss">
  | (() => D1Row | "miss");

type ReaderSpy = D1Reader & {
  read: ReturnType<typeof vi.fn<(key: string) => Promise<D1Row | "miss">>>;
  readCount: () => number;
};

/** A5 `config-cache.test.ts` ReaderSpy substrate (Clarification Q4). */
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

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

const FIXTURE_INSTALLATION_ID = "inst-ent-001";
const FIXTURE_ORG_ID = "org-ent-001";
const FIXTURE_CAPABILITY_ID = "clinic.visit_summary";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_PROVIDER_ID = "deepseek";
const FIXTURE_PLAN = "professional";
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";
const FIXTURE_LATER = "2026-07-31T13:00:00.000Z";

type EntitlementHandlers = {
  evaluateEntitlement: (
    principal: Principal,
    ctx: EntitlementContext,
    cache: ConfigCache,
    reader: D1Reader,
  ) => Promise<EntitlementResult>;
};

type SeedEntitlementOptions = {
  status?: string;
  plan?: string;
  allowedCapabilities?: string[] | string;
};

type SeedGrantOptions = {
  capabilityId?: string;
  capabilityVersion?: string;
  /** D1 `capability_grant.scope` column value. */
  scope?: string;
  revokedAt?: string | null;
  grantId?: string;
};

type KillSwitchScope = "global" | "capability" | "installation" | "provider";

/** Loads entitlement stage from `src/entitlement/` (absent until Phase 3). */
async function loadEntitlementHandlers(): Promise<EntitlementHandlers> {
  return import(/* @vite-ignore */ "../src/entitlement") as Promise<EntitlementHandlers>;
}

function makePrincipal(overrides: Partial<Principal> = {}): Principal {
  return {
    installationId: FIXTURE_INSTALLATION_ID,
    organizationId: FIXTURE_ORG_ID,
    branchId: "branch-ent-001",
    actorId: "actor-ent-001",
    role: "clinician",
    scopes: ["ai.visit_summary"],
    jti: "jti-ent-001",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    ver: "1",
    ...overrides,
  };
}

function makeCtx(overrides: Partial<EntitlementContext> = {}): EntitlementContext {
  return {
    capabilityId: FIXTURE_CAPABILITY_ID,
    capabilityVersion: FIXTURE_CAPABILITY_VERSION,
    minimumPlanTier: "standard",
    providerId: FIXTURE_PROVIDER_ID,
    ...overrides,
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

async function clearEntitlementTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM capability_grant"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation_key"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

async function seedInstallation(
  installationId: string = FIXTURE_INSTALLATION_ID,
  status: string = "active",
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (
      installation_id, org_id, display_name, status, region, enrolled_at
    ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      installationId,
      FIXTURE_ORG_ID,
      "Entitlement Test Clinic",
      status,
      "us-east-1",
      FIXTURE_NOW,
    )
    .run();
}

async function seedEntitlement(
  options: SeedEntitlementOptions = {},
): Promise<void> {
  const {
    status = "active",
    plan = FIXTURE_PLAN,
    allowedCapabilities = [FIXTURE_CAPABILITY_ID],
  } = options;

  const allowedCapabilitiesValue =
    typeof allowedCapabilities === "string"
      ? allowedCapabilities
      : JSON.stringify(allowedCapabilities);

  await env.DB.prepare(
    `INSERT INTO entitlement (
      entitlement_id, installation_id, plan, period_start, period_end,
      request_quota, token_budget, cost_budget, allowed_capabilities,
      soft_threshold, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      `ent-${FIXTURE_INSTALLATION_ID}`,
      FIXTURE_INSTALLATION_ID,
      plan,
      FIXTURE_NOW,
      FIXTURE_NOW,
      1_000,
      1_000_000,
      100,
      allowedCapabilitiesValue,
      0.8,
      status,
    )
    .run();
}

async function seedCapabilityGrant(
  options: SeedGrantOptions = {},
): Promise<void> {
  const capabilityId = options.capabilityId ?? FIXTURE_CAPABILITY_ID;
  const capabilityVersion =
    options.capabilityVersion ?? FIXTURE_CAPABILITY_VERSION;
  const scope =
    options.scope ?? `installation:${FIXTURE_INSTALLATION_ID}`;
  const revokedAt = options.revokedAt === undefined ? null : options.revokedAt;
  const grantId =
    options.grantId ?? `grant-${scope}-${capabilityId}`.replace(/:/g, "_");

  await env.DB.prepare(
    `INSERT INTO capability_grant (
      grant_id, scope, capability_id, capability_version,
      granted_at, revoked_at, changed_at, changed_by
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      grantId,
      scope,
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
  scope: KillSwitchScope,
  target: string,
  recordedAt: string = FIXTURE_NOW,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO control_audit (
      audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at
    ) VALUES (?, ?, ?, ?, NULL, NULL, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      "operator-test",
      `kill_switch_${scope}`,
      target,
      recordedAt,
    )
    .run();
}

/** Records a lift after a prior activate — harness treats latest lift as inactive. */
async function seedKillSwitchLift(
  scope: KillSwitchScope,
  target: string,
  recordedAt: string = FIXTURE_LATER,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO control_audit (
      audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at
    ) VALUES (?, ?, ?, ?, NULL, NULL, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      "operator-test",
      `lift_kill_switch_${scope}`,
      target,
      recordedAt,
    )
    .run();
}

function killSwitchTarget(scope: KillSwitchScope): string {
  switch (scope) {
    case "global":
      return "global";
    case "capability":
      return FIXTURE_CAPABILITY_ID;
    case "installation":
      return FIXTURE_INSTALLATION_ID;
    case "provider":
      return FIXTURE_PROVIDER_ID;
  }
}

/**
 * Production-shaped D1Reader: `loadConfig` passes prefixed keys `kind:key`.
 * Grant rows are returned even when revoked — evaluateEntitlement decides.
 * Kill-switch absence is `"miss"` (inactive); a later lift yields `{active:false}`.
 */
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
          // Cache keys: `${installationId}/${capabilityId}` or `plan:${plan}/${capabilityId}`.
          let scope: string;
          let capabilityId: string;
          if (key.startsWith("plan:")) {
            const slash = key.lastIndexOf("/");
            if (slash === -1) {
              return "miss";
            }
            scope = key.slice(0, slash);
            capabilityId = key.slice(slash + 1);
          } else {
            const [installationId, capId] = key.split("/", 2);
            if (!installationId || !capId) {
              return "miss";
            }
            scope = `installation:${installationId}`;
            capabilityId = capId;
          }

          const row = await db
            .prepare(
              `SELECT grant_id, scope, capability_id, capability_version,
                      granted_at, revoked_at, changed_at, changed_by
               FROM capability_grant
               WHERE scope = ? AND capability_id = ?
               ORDER BY changed_at DESC LIMIT 1`,
            )
            .bind(scope, capabilityId)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "kill_switches": {
          const [scope, ...rest] = key.split(":");
          const target = rest.length > 0 ? rest.join(":") : scope;
          const activateAction =
            scope === "global"
              ? "kill_switch_global"
              : `kill_switch_${scope}`;
          const liftAction =
            scope === "global"
              ? "lift_kill_switch_global"
              : `lift_kill_switch_${scope}`;
          const auditTarget = scope === "global" ? "global" : target;
          const row = await db
            .prepare(
              `SELECT action, target FROM control_audit
               WHERE target = ? AND action IN (?, ?)
               ORDER BY recorded_at DESC LIMIT 1`,
            )
            .bind(auditTarget, activateAction, liftAction)
            .first<D1Row>();
          if (!row) {
            return "miss";
          }
          if (typeof row.action === "string" && row.action.startsWith("lift_")) {
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

/**
 * Warms cache via bare `loadConfig` — `loadConfig` itself prefixes `kind:key`
 * for the reader (no scopeReaderForKind wrapper).
 * Kill-switch absence is remembered as `{ active: false }` so a warm isolate
 * still pays zero reader I/O (misses are not cached by loadConfig itself).
 */
async function warmEntitlementCache(
  cache: ConfigCache,
  reader: D1Reader,
  installationId: string = FIXTURE_INSTALLATION_ID,
  grantKey: string = `${FIXTURE_INSTALLATION_ID}/${FIXTURE_CAPABILITY_ID}`,
): Promise<void> {
  await loadConfig(cache, reader, "installations", installationId);
  await loadConfig(cache, reader, "entitlements", installationId);
  await loadConfig(cache, reader, "grants", grantKey);

  const now = Date.now();
  for (const scope of [
    "global",
    `capability:${FIXTURE_CAPABILITY_ID}`,
    `installation:${installationId}`,
    `provider:${FIXTURE_PROVIDER_ID}`,
  ] as const) {
    try {
      await loadConfig(cache, reader, "kill_switches", scope);
    } catch (error) {
      if (error instanceof ConfigCacheMissError) {
        cache.remember("kill_switches", scope, { active: false }, now);
        continue;
      }
      throw error;
    }
  }
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
});

beforeEach(async () => {
  await clearEntitlementTables();
});

describe("entitlement_forbidden_capability", () => {
  const cases: Array<{
    name: string;
    path: EntitlementRejectionPath;
    seed: () => Promise<void>;
  }> = [
    {
      name: "entitlement_ai_disabled_installation_rejected",
      path: "ai_disabled",
      seed: async () => {
        await seedInstallation();
        await seedEntitlement({ status: "pending", plan: "professional" });
        await seedCapabilityGrant();
      },
    },
    {
      name: "entitlement_plan_tier_too_low_rejected",
      path: "plan_tier",
      seed: async () => {
        await seedInstallation();
        await seedEntitlement({ status: "active", plan: "starter" });
        await seedCapabilityGrant();
      },
    },
    {
      name: "entitlement_capability_not_granted_rejected",
      path: "capability_not_granted",
      seed: async () => {
        await seedInstallation();
        await seedEntitlement({
          status: "active",
          plan: "professional",
          allowedCapabilities: [],
        });
      },
    },
  ];

  for (const testCase of cases) {
    describe(testCase.name, () => {
      it(`rejects with forbidden_capability via ${testCase.path}`, async () => {
        const { evaluateEntitlement } = await loadEntitlementHandlers();
        await testCase.seed();

        const cache = new ConfigCache();
        const reader = makePlatformD1Reader(env.DB);
        const result = await evaluateEntitlement(
          makePrincipal(),
          makeCtx(),
          cache,
          reader,
        );

        expect(result).toEqual({
          ok: false,
          code: "forbidden_capability",
          path: testCase.path,
        });
      });
    });
  }
});

describe("kill_switch_capability_disabled", () => {
  const cases: Array<{
    name: string;
    scope: KillSwitchScope;
    path: EntitlementRejectionPath;
  }> = [
    {
      name: "kill_switch_global_rejected",
      scope: "global",
      path: "kill_switch_global",
    },
    {
      name: "kill_switch_capability_rejected",
      scope: "capability",
      path: "kill_switch_capability",
    },
    {
      name: "kill_switch_installation_rejected",
      scope: "installation",
      path: "kill_switch_installation",
    },
    {
      name: "kill_switch_provider_rejected",
      scope: "provider",
      path: "kill_switch_provider",
    },
  ];

  for (const testCase of cases) {
    describe(testCase.name, () => {
      it(`rejects with capability_disabled via ${testCase.path}`, async () => {
        const { evaluateEntitlement } = await loadEntitlementHandlers();
        await seedInstallation();
        await seedEntitlement();
        await seedCapabilityGrant();
        await seedKillSwitch(testCase.scope, killSwitchTarget(testCase.scope));

        const cache = new ConfigCache();
        const reader = makePlatformD1Reader(env.DB);
        const result = await evaluateEntitlement(
          makePrincipal(),
          makeCtx(),
          cache,
          reader,
        );

        expect(result).toEqual({
          ok: false,
          code: "capability_disabled",
          path: testCase.path,
        });
      });
    });
  }
});

describe("kill_switch_absent_and_lifted", () => {
  it("kill_switch_absent_passes — miss for all kill-switch scopes is inactive", async () => {
    const { evaluateEntitlement } = await loadEntitlementHandlers();
    await seedInstallation();
    await seedEntitlement();
    await seedCapabilityGrant();

    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);
    const result = await evaluateEntitlement(
      makePrincipal(),
      makeCtx(),
      cache,
      reader,
    );

    expect(result).toEqual({ ok: true });
  });

  it("kill_switch_lifted_passes — explicit {active:false} after a prior activate", async () => {
    const { evaluateEntitlement } = await loadEntitlementHandlers();
    await seedInstallation();
    await seedEntitlement();
    await seedCapabilityGrant();
    await seedKillSwitch("capability", FIXTURE_CAPABILITY_ID, FIXTURE_NOW);
    await seedKillSwitchLift("capability", FIXTURE_CAPABILITY_ID, FIXTURE_LATER);

    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);
    const result = await evaluateEntitlement(
      makePrincipal(),
      makeCtx(),
      cache,
      reader,
    );

    expect(result).toEqual({ ok: true });
  });
});

describe("entitlement_grant_scope_and_revocation", () => {
  it("entitlement_plan_scoped_grant_accepted — plan scope grant with installation miss", async () => {
    const { evaluateEntitlement } = await loadEntitlementHandlers();
    await seedInstallation();
    await seedEntitlement({ plan: FIXTURE_PLAN });
    await seedCapabilityGrant({
      scope: `plan:${FIXTURE_PLAN}`,
      grantId: "grant-plan-scoped",
    });

    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);
    const result = await evaluateEntitlement(
      makePrincipal(),
      makeCtx(),
      cache,
      reader,
    );

    expect(result).toEqual({ ok: true });
  });

  it("entitlement_revoked_grant_rejected — revoked_at set is returned by reader", async () => {
    const { evaluateEntitlement } = await loadEntitlementHandlers();
    await seedInstallation();
    await seedEntitlement();
    await seedCapabilityGrant({
      revokedAt: FIXTURE_NOW,
      grantId: "grant-revoked",
    });

    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);
    const result = await evaluateEntitlement(
      makePrincipal(),
      makeCtx(),
      cache,
      reader,
    );

    expect(result).toEqual({
      ok: false,
      code: "forbidden_capability",
      path: "capability_not_granted",
    });
  });

  it("entitlement_capability_version_mismatch_rejected", async () => {
    const { evaluateEntitlement } = await loadEntitlementHandlers();
    await seedInstallation();
    await seedEntitlement();
    await seedCapabilityGrant({
      capabilityVersion: "1.0.0",
    });

    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);
    const result = await evaluateEntitlement(
      makePrincipal(),
      makeCtx({ capabilityVersion: "2.0.0" }),
      cache,
      reader,
    );

    expect(result).toEqual({
      ok: false,
      code: "forbidden_capability",
      path: "capability_not_granted",
    });
  });
});

describe("entitlement_malformed_allowed_capabilities_rejected", () => {
  it("rejects forbidden_capability when allowed_capabilities is not valid JSON", async () => {
    const { evaluateEntitlement } = await loadEntitlementHandlers();
    await seedInstallation();
    await seedEntitlement({
      allowedCapabilities: "{not-json",
    });
    await seedCapabilityGrant();

    const cache = new ConfigCache();
    const reader = makePlatformD1Reader(env.DB);
    const result = await evaluateEntitlement(
      makePrincipal(),
      makeCtx(),
      cache,
      reader,
    );

    expect(result).toEqual({
      ok: false,
      code: "forbidden_capability",
      path: "capability_not_granted",
    });
  });
});

describe("entitlement_warm_isolate_no_d1_read", () => {
  it("performs zero reader.read for entitlement and all four kill-switch scopes", async () => {
    const { evaluateEntitlement } = await loadEntitlementHandlers();

    const rows: Record<string, D1Row> = {
      [`installations:${FIXTURE_INSTALLATION_ID}`]: {
        installation_id: FIXTURE_INSTALLATION_ID,
        status: "active",
      },
      [`entitlements:${FIXTURE_INSTALLATION_ID}`]: {
        installation_id: FIXTURE_INSTALLATION_ID,
        status: "active",
        plan: "professional",
        allowed_capabilities: JSON.stringify([FIXTURE_CAPABILITY_ID]),
      },
      [`grants:${FIXTURE_INSTALLATION_ID}/${FIXTURE_CAPABILITY_ID}`]: {
        scope: `installation:${FIXTURE_INSTALLATION_ID}`,
        capability_id: FIXTURE_CAPABILITY_ID,
        capability_version: FIXTURE_CAPABILITY_VERSION,
        revoked_at: null,
      },
      // Explicit inactive rows (warm path); absent path is covered by miss tests.
      "kill_switches:global": { active: false, scope: "global", target: "global" },
      [`kill_switches:capability:${FIXTURE_CAPABILITY_ID}`]: {
        active: false,
        scope: "capability",
        target: FIXTURE_CAPABILITY_ID,
      },
      [`kill_switches:installation:${FIXTURE_INSTALLATION_ID}`]: {
        active: false,
        scope: "installation",
        target: FIXTURE_INSTALLATION_ID,
      },
      [`kill_switches:provider:${FIXTURE_PROVIDER_ID}`]: {
        active: false,
        scope: "provider",
        target: FIXTURE_PROVIDER_ID,
      },
    };

    const reader = makeReader(rows);
    const cache = new ConfigCache();
    await warmEntitlementCache(cache, reader);
    reader.read.mockClear();

    const result = await evaluateEntitlement(
      makePrincipal(),
      makeCtx(),
      cache,
      reader,
    );

    expect(result).toEqual({ ok: true });
    expect(reader.readCount()).toBe(0);
  });
});
