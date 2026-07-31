import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import {
  ConfigCache,
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
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";

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
  allowedCapabilities?: string[];
};

type KillSwitchScope = "global" | "capability" | "installation" | "provider";

/** Loads entitlement stage from `src/entitlement/` (absent until Phase 3). */
async function loadEntitlementHandlers(): Promise<EntitlementHandlers> {
  return import(/* @vite-ignore */ "../src/entitlement") as Promise<EntitlementHandlers>;
}

function scopeReaderForKind(reader: D1Reader, kind: ConfigEntityKind): D1Reader {
  return {
    read(key: string) {
      return reader.read(`${kind}:${key}`);
    },
  };
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
    plan = "professional",
    allowedCapabilities = [FIXTURE_CAPABILITY_ID],
  } = options;

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
      JSON.stringify(allowedCapabilities),
      0.8,
      status,
    )
    .run();
}

async function seedCapabilityGrant(
  capabilityId: string = FIXTURE_CAPABILITY_ID,
  capabilityVersion: string = FIXTURE_CAPABILITY_VERSION,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO capability_grant (
      grant_id, scope, capability_id, capability_version,
      granted_at, revoked_at, changed_at, changed_by
    ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)`,
  )
    .bind(
      `grant-${capabilityId}`,
      `installation:${FIXTURE_INSTALLATION_ID}`,
      capabilityId,
      capabilityVersion,
      FIXTURE_NOW,
      FIXTURE_NOW,
      "operator-test",
    )
    .run();
}

async function seedKillSwitch(
  scope: KillSwitchScope,
  target: string,
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
      FIXTURE_NOW,
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
            scope === "global"
              ? "kill_switch_global"
              : `kill_switch_${scope}`;
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

async function warmEntitlementCache(
  cache: ConfigCache,
  reader: D1Reader,
  installationId: string = FIXTURE_INSTALLATION_ID,
): Promise<void> {
  const scoped = (kind: ConfigEntityKind) => scopeReaderForKind(reader, kind);

  await loadConfig(
    cache,
    scoped("installations"),
    "installations",
    installationId,
  );
  await loadConfig(
    cache,
    scoped("entitlements"),
    "entitlements",
    installationId,
  );
  await loadConfig(
    cache,
    scoped("grants"),
    "grants",
    `${installationId}/${FIXTURE_CAPABILITY_ID}`,
  );

  for (const scope of [
    "global",
    `capability:${FIXTURE_CAPABILITY_ID}`,
    `installation:${installationId}`,
    `provider:${FIXTURE_PROVIDER_ID}`,
  ] as const) {
    await loadConfig(cache, scoped("kill_switches"), "kill_switches", scope);
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
