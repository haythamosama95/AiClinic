import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import lifecycleMigrationSql from "../migrations/20260802100000_capability_grant_lifecycle.sql?raw";
import tokenContractMigrationSql from "../migrations/20260803120000_token_contract.sql?raw";
import canaryMigrationSql from "../migrations/20260803100000_routing_policy_canary.sql?raw";
import statusMigrationSql from "../migrations/20260805190000_routing_policy_status.sql?raw";
import killSwitchMigrationSql from "../migrations/20260807120000_kill_switch.sql?raw";
import {
  ConfigCache,
  ConfigCacheMissError,
  createD1ConfigReader,
  loadConfig,
  type D1Reader,
} from "../src/config-cache";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
  }
}

const FIXTURE_INSTALLATION_ID = "inst-reader-001";
const FIXTURE_ORG_ID = "org-reader-001";
const FIXTURE_CAPABILITY_ID = "clinic.reader";
const FIXTURE_CAPABILITY_VERSION = "1.0.0";
const FIXTURE_KEY_ID = "kid-reader-001";
const FIXTURE_NOW = "2026-07-31T12:00:00.000Z";
const FIXTURE_ROUTING_POLICY_REF = "routing/standard";
const FIXTURE_TOKEN_VER = "1";

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

async function clearReaderTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM kill_switch"),
    env.DB.prepare("DELETE FROM routing_policy"),
    env.DB.prepare("DELETE FROM capability_grant"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation_key"),
    env.DB.prepare("DELETE FROM installation"),
    env.DB.prepare("DELETE FROM token_contract"),
    env.DB.prepare(
      `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
       VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed')`,
    ),
  ]);
}

async function seedInstallation(): Promise<void> {
  await env.DB
    .prepare(
      `INSERT INTO installation (
        installation_id, org_id, display_name, status, region, enrolled_at
      ) VALUES (?, ?, ?, 'active', 'us-east-1', ?)`,
    )
    .bind(FIXTURE_INSTALLATION_ID, FIXTURE_ORG_ID, "Reader Test Clinic", FIXTURE_NOW)
    .run();
}

async function seedInstallationKey(): Promise<void> {
  await env.DB
    .prepare(
      `INSERT INTO installation_key (
        key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at
      ) VALUES (?, ?, ?, 'EdDSA', ?, NULL, NULL)`,
    )
    .bind(
      FIXTURE_KEY_ID,
      FIXTURE_INSTALLATION_ID,
      "dGVzdC1wdWJsaWMta2V5",
      FIXTURE_NOW,
    )
    .run();
}

async function seedEntitlement(): Promise<void> {
  await env.DB
    .prepare(
      `INSERT INTO entitlement (
        entitlement_id, installation_id, plan, period_start, period_end,
        request_quota, token_budget, cost_budget, allowed_capabilities,
        soft_threshold, status
      ) VALUES (?, ?, 'professional', ?, ?, 1000, 1000000, 100, '[]', 0.8, 'active')`,
    )
    .bind(`ent-${FIXTURE_INSTALLATION_ID}`, FIXTURE_INSTALLATION_ID, FIXTURE_NOW, FIXTURE_NOW)
    .run();
}

async function seedGrant(): Promise<void> {
  await env.DB
    .prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, 'operator-test')`,
    )
    .bind(
      `grant-${FIXTURE_CAPABILITY_ID}`,
      `installation:${FIXTURE_INSTALLATION_ID}`,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      FIXTURE_NOW,
      FIXTURE_NOW,
    )
    .run();
}

async function seedLifecycleOverlay(): Promise<void> {
  await env.DB
    .prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by,
        lifecycle_state, successor_id, deprecated_at, retire_after
      ) VALUES (?, 'global', ?, ?, ?, NULL, ?, 'operator-test', 'deprecated', NULL, ?, NULL)`,
    )
    .bind(
      `overlay-${FIXTURE_CAPABILITY_ID}`,
      FIXTURE_CAPABILITY_ID,
      FIXTURE_CAPABILITY_VERSION,
      FIXTURE_NOW,
      FIXTURE_NOW,
      FIXTURE_NOW,
    )
    .run();
}

async function seedKillSwitch(
  scope: string = "global",
  target: string = "global",
): Promise<void> {
  await env.DB
    .prepare(
      `INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
       VALUES (?, ?, 1, ?, 'operator-test')`,
    )
    .bind(scope, target, FIXTURE_NOW)
    .run();
}

async function seedRoutingPolicy(): Promise<void> {
  await env.DB
    .prepare(
      `INSERT INTO routing_policy (
        policy_id, version, content_pointer, active_from, activated_by, status
      ) VALUES ('standard', '1', 'control/routing-policy/standard/1.json', ?, 'operator-test', 'active')`,
    )
    .bind(FIXTURE_NOW)
    .run();
}

function createSpiedD1Reader(db: D1Database): D1Reader & { readCount: () => number } {
  const inner = createD1ConfigReader(db);
  const read = vi.fn(inner.read.bind(inner));
  return {
    read,
    readCount: () => read.mock.calls.length,
  };
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, lifecycleMigrationSql);
  await applyPlatformSchema(env.DB, tokenContractMigrationSql);
  await applyPlatformSchema(env.DB, canaryMigrationSql);
  await applyPlatformSchema(env.DB, statusMigrationSql);
  await applyPlatformSchema(env.DB, killSwitchMigrationSql);
});

beforeEach(async () => {
  await clearReaderTables();
});

describe("T6 config_reader_presence_installation", () => {
  it("serves a present installation row through the production D1 config reader", async () => {
    await seedInstallation();

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB);
    const row = await loadConfig(
      cache,
      reader,
      "installations",
      FIXTURE_INSTALLATION_ID,
    );

    expect(row.installation_id).toBe(FIXTURE_INSTALLATION_ID);
    expect(row.org_id).toBe(FIXTURE_ORG_ID);
  });
});

describe("T7 config_reader_presence_keys", () => {
  it("serves a present installation key through the production D1 config reader", async () => {
    await seedInstallation();
    await seedInstallationKey();

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB);
    const row = await loadConfig(cache, reader, "keys", FIXTURE_KEY_ID);

    expect(row.key_id).toBe(FIXTURE_KEY_ID);
    expect(row.installation_id).toBe(FIXTURE_INSTALLATION_ID);
  });
});

describe("T8 config_reader_presence_entitlements", () => {
  it("serves a present entitlement through the production D1 config reader", async () => {
    await seedInstallation();
    await seedEntitlement();

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB);
    const row = await loadConfig(
      cache,
      reader,
      "entitlements",
      FIXTURE_INSTALLATION_ID,
    );

    expect(row.installation_id).toBe(FIXTURE_INSTALLATION_ID);
    expect(row.plan).toBe("professional");
  });
});

describe("T9 config_reader_presence_grants_lifecycle_overlay", () => {
  it("serves present grant and global lifecycle overlay through the production D1 config reader", async () => {
    await seedInstallation();
    await seedGrant();
    await seedLifecycleOverlay();

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB);
    const grant = await loadConfig(
      cache,
      reader,
      "grants",
      `${FIXTURE_INSTALLATION_ID}/${FIXTURE_CAPABILITY_ID}`,
    );

    expect(grant.capability_id).toBe(FIXTURE_CAPABILITY_ID);
    expect(grant.capability_version).toBe(FIXTURE_CAPABILITY_VERSION);

    const overlay = await loadConfig(
      cache,
      reader,
      "grants",
      `global/${FIXTURE_CAPABILITY_ID}/${FIXTURE_CAPABILITY_VERSION}`,
    );

    expect(overlay.scope).toBe("global");
    expect(overlay.capability_id).toBe(FIXTURE_CAPABILITY_ID);
    expect(overlay.lifecycle_state).toBe("deprecated");
  });
});

describe("T10 config_reader_presence_kill_switches", () => {
  it("serves present kill_switch rows for global and {scope}:{target} cache keys", async () => {
    await seedKillSwitch("global", "global");
    await seedKillSwitch("capability", FIXTURE_CAPABILITY_ID);
    await seedKillSwitch("installation", FIXTURE_INSTALLATION_ID);
    await seedKillSwitch("provider", "deepseek");

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB);

    const globalRow = await loadConfig(cache, reader, "kill_switches", "global");
    expect(globalRow.active).toBe(true);
    expect(globalRow.scope).toBe("global");
    expect(globalRow.target).toBe("global");

    const capabilityKey = `capability:${FIXTURE_CAPABILITY_ID}`;
    const capabilityRow = await loadConfig(
      cache,
      reader,
      "kill_switches",
      capabilityKey,
    );
    expect(capabilityRow.active).toBe(true);
    expect(capabilityRow.scope).toBe("capability");
    expect(capabilityRow.target).toBe(FIXTURE_CAPABILITY_ID);

    const installationKey = `installation:${FIXTURE_INSTALLATION_ID}`;
    const installationRow = await loadConfig(
      cache,
      reader,
      "kill_switches",
      installationKey,
    );
    expect(installationRow.active).toBe(true);
    expect(installationRow.scope).toBe("installation");
    expect(installationRow.target).toBe(FIXTURE_INSTALLATION_ID);

    const providerRow = await loadConfig(
      cache,
      reader,
      "kill_switches",
      "provider:deepseek",
    );
    expect(providerRow.active).toBe(true);
    expect(providerRow.scope).toBe("provider");
    expect(providerRow.target).toBe("deepseek");
  });
});

describe("T11 config_reader_presence_active_routing_policy", () => {
  it("serves a present active routing policy through the production D1 config reader", async () => {
    await seedRoutingPolicy();

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB);
    const row = await loadConfig(
      cache,
      reader,
      "active_routing_policy",
      FIXTURE_ROUTING_POLICY_REF,
    );

    expect(row.policy_id).toBe("standard");
    expect(row.status).toBe("active");
  });
});

describe("T12 config_reader_presence_token_contract", () => {
  it("serves a present token_contract accepted ver through the production D1 config reader", async () => {
    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB);
    const row = await loadConfig(cache, reader, "token_contracts", FIXTURE_TOKEN_VER);

    expect(row.ver).toBe(FIXTURE_TOKEN_VER);
    expect(row.retired_at).toBeNull();
  });
});

describe("T13 config_reader_cold_isolate_single_d1_read_pattern", () => {
  it("performs exactly one D1 read on a cold isolate first config load", async () => {
    await seedInstallation();

    const cache = new ConfigCache();
    const reader = createSpiedD1Reader(env.DB);

    await loadConfig(cache, reader, "installations", FIXTURE_INSTALLATION_ID);

    expect(reader.readCount()).toBe(1);
  });
});

describe("T14 config_reader_miss_typed_failure_not_silent_admit", () => {
  it("throws ConfigCacheMissError on miss instead of silently admitting", async () => {
    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB);

    await expect(
      loadConfig(cache, reader, "installations", "missing-installation"),
    ).rejects.toBeInstanceOf(ConfigCacheMissError);
  });
});

const CANARY_COHORT_INSTALLATION = "inst-parse-canary";
const CANARY_OTHER_INSTALLATION = "inst-parse-other";

async function seedCanaryRoutingPolicies(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO routing_policy (
        policy_id, version, content_pointer, active_from, activated_by, status
      ) VALUES ('standard', '1', 'control/routing-policy/standard/1.json', ?, 'operator-test', 'active')`,
    ).bind(FIXTURE_NOW),
    env.DB.prepare(
      `INSERT INTO routing_policy (
        policy_id, version, content_pointer, active_from, activated_by,
        canary_installation_ids, status
      ) VALUES ('standard', '2', 'control/routing-policy/standard/2.json', ?, 'operator-test', ?, 'canary')`,
    ).bind(FIXTURE_NOW, JSON.stringify([CANARY_COHORT_INSTALLATION])),
  ]);
}

describe("active_routing_policy cache key parsing", () => {
  it("resolves all four accepted key shapes for bare ref, legacy @v suffix, and installation suffix", async () => {
    await seedCanaryRoutingPolicies();

    const cache = new ConfigCache();
    const reader = createD1ConfigReader(env.DB);

    const bareActive = await loadConfig(
      cache,
      reader,
      "active_routing_policy",
      "routing/standard",
    );
    expect(bareActive.version).toBe("1");
    expect(bareActive.policy_id).toBe("standard");

    const legacyBareActive = await loadConfig(
      cache,
      reader,
      "active_routing_policy",
      "routing/standard@v1",
    );
    expect(legacyBareActive.version).toBe("1");

    const bareCanary = await loadConfig(
      cache,
      reader,
      "active_routing_policy",
      `routing/standard/${CANARY_COHORT_INSTALLATION}`,
    );
    expect(bareCanary.version).toBe("2");
    expect(bareCanary.status).toBe("canary");

    const legacyCanary = await loadConfig(
      cache,
      reader,
      "active_routing_policy",
      `routing/standard@v1/${CANARY_COHORT_INSTALLATION}`,
    );
    expect(legacyCanary.version).toBe("2");

    const otherInstallation = await loadConfig(
      cache,
      reader,
      "active_routing_policy",
      `routing/standard/${CANARY_OTHER_INSTALLATION}`,
    );
    expect(otherInstallation.version).toBe("1");
  });
});
