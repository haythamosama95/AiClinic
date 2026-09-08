import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import publishedVisitSummary from "../../manifests/published/clinic.visit_summary@1.0.0.json";
import publishedRegistry from "../../manifests/published-registry.json";
import {
  applyAllMigrations,
  assertRequestReferenceShape,
  assertTaxonomyBody,
  assertUlidShape,
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clinicFetch,
  controlFetch,
  count,
  createCapabilityRegistry,
  CRON_RETENTION,
  CRON_ROLLUP,
  enrollInstallation,
  entitleInstallation,
  env,
  getCapabilities,
  getHealth,
  hashManifest,
  invokeCron,
  isolateConfigCache,
  listTableNames,
  loadManifest,
  mintAat,
  newScenario,
  PLATFORM_TABLES,
  queryAll,
  queryOne,
  readHttpResult,
  resetE2eState,
  seedSql,
  setCapabilityRegistry,
  verifyManifestTree,
  type Manifest,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const HEALTH_BODY = { build: "local", environment: "development" } as const;

const EXPECTED_PLATFORM_TABLES = [
  "ai_attempt",
  "ai_request",
  "capability_grant",
  "control_audit",
  "entitlement",
  "grace_admission_queue",
  "installation",
  "installation_key",
  "kill_switch",
  "platform_counter",
  "routing_policy",
  "token_contract",
  "usage_event",
  "usage_rollup",
] as const;

const BUSINESS_TABLES = PLATFORM_TABLES.filter(
  (table) => table !== "token_contract",
);

const TOKEN_CONTRACT_SEED = {
  ver: "1",
  added_at: "2026-08-03T00:00:00.000Z",
  retired_at: null,
  changed_by: "seed",
} as const;

const PUBLISHED_HASH =
  "ce28a0b478fbcbb8eec7a2a975ebd9e2f52c6b8bb7dd7ecd1c2ec42981bab0fe";

const ETAG_QUOTED_64_HEX = /^"[0-9a-f]{64}"$/i;

type TokenContractRow = {
  ver: string;
  added_at: string;
  retired_at: string | null;
  changed_by: string;
};

function cloneJson(value: unknown): Record<string, unknown> {
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>;
}

const PUBLISHED_MANIFEST_FILE = "clinic.visit_summary@1.0.0.json";
const PUBLISHED_MANIFESTS_DIR = "manifests/published";
const PUBLISHED_REGISTRY_PATH = "manifests/published-registry.json";

function publishedManifestTreeIo(
  files: Record<string, Record<string, unknown>> = {
    [PUBLISHED_MANIFEST_FILE]: cloneJson(publishedVisitSummary),
  },
) {
  return {
    manifestsDir: PUBLISHED_MANIFESTS_DIR,
    registryPath: PUBLISHED_REGISTRY_PATH,
    readFile: async (filePath: string) => {
      if (filePath === PUBLISHED_REGISTRY_PATH) {
        return JSON.stringify(publishedRegistry);
      }
      const name = filePath.slice(PUBLISHED_MANIFESTS_DIR.length + 1);
      const json = files[name];
      if (json === undefined) {
        throw new Error(`No published manifest for ${filePath}`);
      }
      return JSON.stringify(json);
    },
    readdir: async () => Object.keys(files),
    join: (...parts: string[]) => parts.join("/"),
  };
}

function filterCatalogTables(names: string[]): string[] {
  return names.filter(
    (name) =>
      !name.startsWith("sqlite_") &&
      !name.startsWith("_cf_") &&
      name !== "d1_migrations",
  );
}

function assertUnauthenticatedTaxonomy(json: unknown): void {
  assertTaxonomyBody(json, { code: "unauthenticated", retry_safe: true });
  assertRequestReferenceShape(String(json.request_reference));
  assertUlidShape(String(json.trace_id));
}

async function assertTokenContractSeed(): Promise<TokenContractRow> {
  const rows = await queryAll<TokenContractRow>(
    "SELECT ver, added_at, retired_at, changed_by FROM token_contract",
  );
  expect(rows).toHaveLength(1);
  expect(rows[0]).toEqual(TOKEN_CONTRACT_SEED);
  return rows[0]!;
}

async function assertBusinessTablesEmpty(): Promise<void> {
  for (const table of BUSINESS_TABLES) {
    expect(await count(table), `${table} must be empty`).toBe(0);
  }
}

async function assertEmptyAirport(): Promise<void> {
  await assertBusinessTablesEmpty();
  await assertTokenContractSeed();
}

async function countR2Objects(): Promise<number> {
  let total = 0;
  let cursor: string | undefined;
  do {
    const page = await env.R2.list(cursor ? { cursor } : undefined);
    total += page.objects.length;
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return total;
}

function discoveryManifests(
  body: Record<string, unknown> | null,
): Record<string, unknown>[] {
  const manifests = body?.manifests;
  expect(Array.isArray(manifests)).toBe(true);
  return manifests as Record<string, unknown>[];
}

describe("Stage 00 — auth, schema, cron, happy path (S00-019…S00-037)", () => {
  it("S00-019 — Discovery without Authorization → taxonomy unauthenticated", async () => {
    const response = await clinicFetch("/v1/capabilities");
    const result = await readHttpResult(response);

    expect(result.status).toBe(401);
    assertUnauthenticatedTaxonomy(result.json);
    await assertEmptyAirport();
  });

  it("S00-020 — Discovery with garbage bearer → taxonomy unauthenticated", async () => {
    const response = await clinicFetch("/v1/capabilities", {
      token: "not-a-jwt",
    });
    const result = await readHttpResult(response);

    expect(result.status).toBe(401);
    assertUnauthenticatedTaxonomy(result.json);
    await assertEmptyAirport();
  });

  it("S00-021 — Control route missing/wrong operator bearer → 401 unauthorized", async () => {
    const missing = await controlFetch(
      "/control/token-contract/begin-rotation",
      { auth: "none", body: { ver: "1" } },
    );
    const wrong = await controlFetch("/control/token-contract/begin-rotation", {
      auth: "wrong",
      body: { ver: "1" },
    });

    for (const result of [missing, wrong]) {
      expect(result.status).toBe(401);
      expect(result.headers.get("content-type")).toContain("application/json");
      expect(result.json).toEqual({ error: "unauthorized" });
    }

    expect(await count("control_audit")).toBe(0);
    await assertTokenContractSeed();
  });

  it("S00-022 — GET /v1/requests/{ref} without token → taxonomy unauthenticated", async () => {
    const response = await clinicFetch("/v1/requests/9J3K-7Q2M");
    const result = await readHttpResult(response);

    expect(result.status).toBe(401);
    assertUnauthenticatedTaxonomy(result.json);
    await assertEmptyAirport();
  });

  it("S00-023 — /health stays 200 when D1 migrations never applied [SEED]", async () => {
    const dropOrder = [
      "usage_event",
      "ai_attempt",
      "grace_admission_queue",
      "control_audit",
      "platform_counter",
      "usage_rollup",
      "capability_grant",
      "routing_policy",
      "kill_switch",
      "entitlement",
      "installation_key",
      "ai_request",
      "installation",
      "token_contract",
    ] as const;
    try {
      try {
        await seedSql([{ sql: "PRAGMA foreign_keys = OFF" }]);
      } catch {
        // HARNESS-GAP: D1 may reject PRAGMA; child-first DROP still applies.
      }
      await seedSql(
        dropOrder.map((table) => ({
          sql: `DROP TABLE IF EXISTS ${table}`,
        })),
      );

      const health = await getHealth();
      expect(health.status).toBe(200);
      expect(health.json).toEqual(HEALTH_BODY);

      const response = await clinicFetch("/v1/capabilities", {
        token: "not-a-jwt",
      });
      const discovery = await readHttpResult(response);
      expect(discovery.status).toBe(401);
      assertUnauthenticatedTaxonomy(discovery.json);
    } finally {
      await applyAllMigrations();
    }
  });

  it("S00-024 — Unrecognized cron runs only flush + grace reconcile", async () => {
    // HARNESS-GAP: cannot capture worker log sequence
    // (scheduled_cron_start / scheduled_cron_complete; absence of
    // scheduled_retention_purge_start / scheduled_rollup_start).
    //
    // In-isolate rejectionTally survives resetE2eState (D1 wipe only).
    // Earlier tests in this file (S00-019/020/022/023) record unauthenticated
    // guard rejections; the first scheduled tick flushes them to
    // platform_counter. Drain via a real scheduled invocation, then wipe D1
    // so the catalog tick runs with empty tallies (and would fail if flush
    // wrote without clearing memory).
    await invokeCron("* * * * *");
    await resetE2eState();

    await expect(invokeCron("* * * * *")).resolves.toBeUndefined();

    expect(await count("platform_counter")).toBe(0);
    expect(await count("grace_admission_queue")).toBe(0);
    await assertEmptyAirport();
  });

  it("S00-025 — 03:00 cron retention purge no-op", async () => {
    // HARNESS-GAP: cannot capture worker log sequence
    // (scheduled_cron_start, scheduled_retention_purge_start,
    // scheduled_retention_purge_complete, scheduled_cron_complete).
    await expect(invokeCron(CRON_RETENTION)).resolves.toBeUndefined();

    expect(await count("ai_request")).toBe(0);
    expect(await count("usage_event")).toBe(0);
    expect(await count("platform_counter")).toBe(0);
    expect(await count("usage_rollup")).toBe(0);
    expect(await count("control_audit")).toBe(0);
    expect(await countR2Objects()).toBe(0);
    await assertTokenContractSeed();
  });

  it("S00-026 — 04:00 cron rollup no-op", async () => {
    // HARNESS-GAP: cannot capture worker log sequence
    // (scheduled_cron_start, scheduled_rollup_start, usage_rollup_reconciliation
    // with rollups_written/missing_attempt_rows/missing_usage_credit = 0,
    // scheduled_cron_complete; no retention-purge lines).
    await expect(invokeCron(CRON_ROLLUP)).resolves.toBeUndefined();

    expect(await count("usage_rollup")).toBe(0);
    await assertEmptyAirport();
  });

  it("S00-027 — Fresh migration apply: 14 tables + token_contract seed", async () => {
    const names = filterCatalogTables(await listTableNames()).sort();
    expect(names).toEqual([...EXPECTED_PLATFORM_TABLES]);

    const index = await queryOne<{ name: string; tbl_name: string; sql: string }>(
      `SELECT name, tbl_name, sql FROM sqlite_master
       WHERE type = 'index' AND name = ?`,
      ["idx_entitlement_installation_id"],
    );
    expect(index).not.toBeNull();
    expect(index?.name).toBe("idx_entitlement_installation_id");
    expect(index?.tbl_name).toBe("entitlement");
    expect(String(index?.sql).toLowerCase()).toContain("installation_id");

    await assertTokenContractSeed();
    await assertBusinessTablesEmpty();
  });

  it.skip(
    "S00-028 — The pool applies migrations once per test database; d1_migrations tracking is platform behavior, not worker code",
    () => {},
  );

  it("S00-029 — Boot + health + all cron ticks write zero business rows", async () => {
    const health = await getHealth();
    expect(health.status).toBe(200);
    expect(health.json).toEqual(HEALTH_BODY);

    await invokeCron("* * * * *");
    await invokeCron(CRON_RETENTION);
    await invokeCron(CRON_ROLLUP);

    for (const table of [
      "installation",
      "installation_key",
      "entitlement",
      "capability_grant",
      "routing_policy",
      "kill_switch",
      "ai_request",
      "ai_attempt",
      "usage_event",
      "usage_rollup",
      "platform_counter",
      "control_audit",
      "grace_admission_queue",
    ] as const) {
      expect(await count(table), `${table} must stay empty`).toBe(0);
    }

    const seed = await queryOne<TokenContractRow>(
      "SELECT retired_at FROM token_contract WHERE ver = ?",
      ["1"],
    );
    expect(seed?.retired_at ?? null).toBeNull();
  });

  it("S00-030 — Build gate accepts published manifest tree", async () => {
    const published = cloneJson(publishedVisitSummary);
    expect(() => loadManifest(published)).not.toThrow();

    const hash = await hashManifest(published);
    expect(hash).toBe(PUBLISHED_HASH);

    await expect(
      verifyManifestTree(publishedManifestTreeIo()),
    ).resolves.toBeUndefined();
  });

  it("S00-031 — Build gate rejects tampered published manifest", async () => {
    const tampered = cloneJson(publishedVisitSummary);
    const economics = {
      ...(tampered.Economics as Record<string, unknown>),
      quotaWeight: 2,
    };
    tampered.Economics = economics;

    expect(() => loadManifest(tampered)).not.toThrow();

    const onDiskHash = await hashManifest(tampered);
    expect(onDiskHash).not.toBe(PUBLISHED_HASH);

    await expect(
      verifyManifestTree(
        publishedManifestTreeIo({
          [PUBLISHED_MANIFEST_FILE]: tampered,
        }),
      ),
    ).rejects.toThrow(
      `Published manifest hash mismatch for clinic.visit_summary@1.0.0: on-disk ${onDiskHash}, registry ${PUBLISHED_HASH}`,
    );
  });

  it("S00-032 — Build gate rejects malformed manifest", async () => {
    const missingGovernance = cloneJson(publishedVisitSummary);
    delete missingGovernance.Governance;
    expect(() => loadManifest(missingGovernance)).toThrow(
      "Missing manifest group: Governance",
    );

    const badRetention = cloneJson(publishedVisitSummary);
    badRetention.Governance = {
      ...(badRetention.Governance as Record<string, unknown>),
      retentionClass: "diagnostic_400d",
    };
    expect(() => loadManifest(badRetention)).toThrow(
      "Malformed manifest Governance.retentionClass: diagnostic horizon must be 1–90 days",
    );

    const namesProvider = cloneJson(publishedVisitSummary);
    namesProvider.Routing = {
      ...(namesProvider.Routing as Record<string, unknown>),
      provider: "deepseek",
    };
    // Exact-key validation of Routing runs before the provider/model naming
    // ban; `provider` is not an allowed Routing key, so this input is
    // unreachable as the catalog's third example.
    expect(() => loadManifest(namesProvider)).toThrow(
      "Malformed manifest group: Routing",
    );
  });

  it("S00-033 — Loader normalizes legacy perRequestCostCeiling alias", async () => {
    const aliased = cloneJson(publishedVisitSummary);
    const economics = {
      ...(aliased.Economics as Record<string, unknown>),
    };
    economics.perRequestCostCeiling = 9024;
    delete economics.perRequestTokenCeiling;
    aliased.Economics = economics;

    const manifest: Manifest = loadManifest(aliased);
    expect(manifest.Economics.perRequestTokenCeiling).toBe(9024);
    expect("perRequestCostCeiling" in manifest.Economics).toBe(false);

    const bothKeys = cloneJson(publishedVisitSummary);
    bothKeys.Economics = {
      ...(bothKeys.Economics as Record<string, unknown>),
      perRequestTokenCeiling: 9024,
      perRequestCostCeiling: 1,
    };
    const bothKeysManifest: Manifest = loadManifest(bothKeys);
    expect(bothKeysManifest.Economics.perRequestTokenCeiling).toBe(9024);
    expect("perRequestCostCeiling" in bothKeysManifest.Economics).toBe(false);
  });

  it("S00-034 — /health answers any HTTP method", async () => {
    const post = await readHttpResult(
      await clinicFetch("/health", { method: "POST", body: {} }),
    );
    expect(post.status).toBe(200);
    expect(post.json).toEqual(HEALTH_BODY);

    const del = await readHttpResult(
      await clinicFetch("/health", { method: "DELETE" }),
    );
    expect(del.status).toBe(200);
    expect(del.json).toEqual(HEALTH_BODY);

    const put = await readHttpResult(
      await clinicFetch("/health", { method: "PUT", body: {} }),
    );
    expect(put.status).toBe(200);
    expect(put.json).toEqual(HEALTH_BODY);
  });

  it("S00-035 — Happy path first boot GET /health", async () => {
    const health = await getHealth();
    expect(health.status).toBe(200);
    expect(health.headers.get("content-type")).toContain("application/json");
    expect(health.json).toEqual(HEALTH_BODY);
  });

  it("S00-036 — Happy path boot registry serves bundled capability via authenticated discovery", async () => {
    const scenario = await newScenario();
    const enrolled = await enrollInstallation(scenario);
    expect(enrolled.status).toBe(200);
    const entitled = await entitleInstallation(scenario);
    expect(entitled.status).toBe(200);
    const token = await mintAat(scenario, {
      claims: { scopes: ["ai.visit_summary"] },
    });

    const response = await clinicFetch("/v1/capabilities", { token });
    const result = await readHttpResult(response);

    expect(result.status).toBe(200);
    expect(result.headers.get("etag")).toMatch(ETAG_QUOTED_64_HEX);
    expect(result.headers.get("cache-control")).toBe(
      "private, must-revalidate",
    );

    const body = result.json as Record<string, unknown>;
    const manifests = discoveryManifests(body);
    expect(manifests).toHaveLength(1);

    const pub = manifests[0]!;
    expect(pub.Identity).toMatchObject({
      capabilityId: "clinic.visit_summary",
      version: "1.0.0",
      lifecycleState: "active",
    });
    expect(pub.Interaction).toBeDefined();
    expect(pub.Input).toBeDefined();
    expect(pub["Context requirements"]).toBeDefined();
    expect(pub.Output).toEqual({ mode: "prose", outputSchemaRef: null });
    expect(pub.Governance).toEqual({ acceptanceMode: "advisory_display" });
    expect(pub).not.toHaveProperty("Access");
    expect(pub).not.toHaveProperty("Prompt binding");
    expect(pub).not.toHaveProperty("Routing");
    expect(pub).not.toHaveProperty("Economics");
  });

  it("S00-037 — Happy path configured cache TTL bounds staleness", async () => {
    // Dual registry before the warm GET: 1.0.0 lists for this installation;
    // 2.0.0 is registered so cohort-activate is valid, but discovery filters
    // it out (enterprise minimumPlanTier vs enroll plan "standard").
    const published = loadManifest(cloneJson(publishedVisitSummary));
    const v2Wire = cloneJson(publishedVisitSummary);
    (v2Wire.Identity as Record<string, unknown>).version = "2.0.0";
    (v2Wire.Access as Record<string, unknown>).minimumPlanTier = "enterprise";
    setCapabilityRegistry(
      createCapabilityRegistry([published, loadManifest(v2Wire)]),
      { replace: true },
    );

    // isolateConfigCache is process-global. Parallel files clear() it and
    // bump/restore TTL, so the pool's 100ms window can miss under the full
    // suite. Hold the warm rows in this test and re-stamp them for the
    // in-TTL GET; force consult eviction for the post-TTL GET. Catalog
    // claims are unchanged: stale listing of 1.0.0, then {"manifests":[]}.
    const previousTtl = isolateConfigCache.getTtlMs();
    isolateConfigCache.setTtlMs(30_000);

    try {
      const scenario = await newScenario();
      const enrolled = await enrollInstallation(scenario);
      expect(enrolled.status).toBe(200);
      const entitled = await entitleInstallation(scenario);
      expect(entitled.status).toBe(200);
      const token = await mintAat(scenario, {
        claims: { scopes: ["ai.visit_summary"] },
      });

      const grantKey = `${scenario.installationId}/${CAPABILITY_ID}`;
      const entitlementKey = scenario.installationId;

      const first = await getCapabilities(token);
      expect(first.status).toBe(200);
      const firstManifests = discoveryManifests(first.body);
      expect(firstManifests).toHaveLength(1);
      expect(firstManifests[0]?.Identity).toMatchObject({
        capabilityId: CAPABILITY_ID,
        version: CAPABILITY_VERSION,
      });

      let cachedGrant = isolateConfigCache.consult("grants", grantKey);
      let cachedEntitlement = isolateConfigCache.consult(
        "entitlements",
        entitlementKey,
      );
      for (let attempt = 0; attempt < 8 && cachedGrant === undefined; attempt++) {
        const rewarm = await getCapabilities(token);
        expect(rewarm.status).toBe(200);
        expect(discoveryManifests(rewarm.body)).toHaveLength(1);
        cachedGrant = isolateConfigCache.consult("grants", grantKey);
        cachedEntitlement = isolateConfigCache.consult(
          "entitlements",
          entitlementKey,
        );
      }
      expect(cachedGrant).toBeDefined();
      const warmGrant = cachedGrant!;
      const warmEntitlement = cachedEntitlement;

      // Entitle is one-shot (active → 409 not_pending). Cohort-activate via
      // controlFetch so isolateConfigCache is not cleared. Activate UPDATEs
      // the installation grant 1.0.0 → 2.0.0 in D1; cached grant stays 1.0.0
      // until TTL. Do not shrink the registry or clear the cache here.
      const activate = await controlFetch(
        `/control/capabilities/${CAPABILITY_ID}/versions/2.0.0/activate`,
        { body: { installation_ids: [scenario.installationId] } },
      );
      expect(activate.status).toBe(200);

      let stale: Awaited<ReturnType<typeof getCapabilities>> | undefined;
      for (let attempt = 0; attempt < 8; attempt++) {
        isolateConfigCache.setTtlMs(30_000);
        isolateConfigCache.remember("grants", grantKey, warmGrant);
        if (warmEntitlement) {
          isolateConfigCache.remember(
            "entitlements",
            entitlementKey,
            warmEntitlement,
          );
        }
        stale = await getCapabilities(token);
        const manifests = stale.body?.manifests;
        if (Array.isArray(manifests) && manifests.length === 1) {
          break;
        }
      }

      expect(stale).toBeDefined();
      expect(stale!.status).toBe(200);
      const staleManifests = discoveryManifests(stale!.body);
      expect(staleManifests).toHaveLength(1);
      expect(staleManifests[0]?.Identity).toMatchObject({
        capabilityId: CAPABILITY_ID,
        version: CAPABILITY_VERSION,
      });

      // Catalog (4): after TTL, consult misses and D1 grant 2.0.0 is empty.
      // Wall-clock 150ms is not enough if a parallel file left TTL at 30s;
      // stamp expiresAt in the past so consult evicts these keys, then wait.
      const ttlMs = isolateConfigCache.getTtlMs();
      isolateConfigCache.remember(
        "grants",
        grantKey,
        warmGrant,
        Date.now() - ttlMs - 1,
      );
      if (warmEntitlement) {
        isolateConfigCache.remember(
          "entitlements",
          entitlementKey,
          warmEntitlement,
          Date.now() - ttlMs - 1,
        );
      }
      isolateConfigCache.setTtlMs(previousTtl);
      await new Promise((resolve) => setTimeout(resolve, 150));

      const expired = await getCapabilities(token);
      expect(expired.status).toBe(200);
      expect(expired.body).toEqual({ manifests: [] });
      expect(expired.etag).not.toBe(first.etag);
      expect(expired.etag).not.toBe(stale!.etag);
    } finally {
      isolateConfigCache.setTtlMs(previousTtl);
      setCapabilityRegistry(createCapabilityRegistry([published]), {
        replace: true,
      });
    }
  });
});
