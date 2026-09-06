import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertRequestReferenceShape,
  assertTaxonomyBody,
  assertUlidShape,
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clearConfigCache,
  clinicFetch,
  controlFetch,
  count,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  enrollPayload,
  entitleInstallation,
  env,
  getCapabilities,
  getGrants,
  isolateConfigCache,
  mintAat,
  newScenario,
  PLATFORM_TABLES,
  readHttpResult,
  resetE2eState,
  seedSql,
  type EntitlePayload,
  type HttpResult,
  type Scenario,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const ETAG_QUOTED_64_HEX = /^"[0-9a-f]{64}"$/;
const CACHE_CONTROL = "private, must-revalidate";
const PAST_RETIRE_AFTER = "2020-01-01T00:00:00.000Z";
const REVOKE_AT = "2026-09-05T00:00:00.000Z";

const DEPRECATE_PATH = `/control/capabilities/${CAPABILITY_ID}/versions/${CAPABILITY_VERSION}/deprecate`;
const RETIRE_PATH = `/control/capabilities/${CAPABILITY_ID}/versions/${CAPABILITY_VERSION}/retire`;

/** Catalog B0 / S07-042 is installation-scope only. Default entitle also writes a plan grant (S07-034 fallback). */
const INSTALLATION_ONLY_ENTITLE: EntitlePayload = {
  ...DEFAULT_ENTITLE_PAYLOAD,
  grants: [
    {
      capability_id: CAPABILITY_ID,
      capability_version: CAPABILITY_VERSION,
      scope: "installation",
    },
  ],
};

const EXPECTED_PUBLIC_PROJECTION = {
  Identity: {
    capabilityId: CAPABILITY_ID,
    version: CAPABILITY_VERSION,
    title: "Visit summary",
    lifecycleState: "active",
    successorId: null,
  },
  Interaction: { interactionMode: "single_shot" },
  Input: {
    userIntentShape: "plain_text",
    priorTurnShape: null,
    sizeLimits: { maxChars: 8000 },
    allowedLanguages: ["en"],
  },
  "Context requirements": [
    {
      key: "visit.chief_complaint@v1",
      required: true,
      shapeRef: "visit.chief_complaint@v1",
      maxSize: 4096,
    },
  ],
  Output: { mode: "prose", outputSchemaRef: null },
  Governance: { acceptanceMode: "advisory_display" },
} as const;

function canonicalStringify(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((entry) => canonicalStringify(entry)).join(",")}]`;
  }
  const object = value as Record<string, unknown>;
  const keys = Object.keys(object).sort();
  return `{${keys
    .map((key) => `${JSON.stringify(key)}:${canonicalStringify(object[key])}`)
    .join(",")}}`;
}

async function hashCanonical(json: unknown): Promise<string> {
  const encoded = new TextEncoder().encode(canonicalStringify(json));
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function quotedEtagFor(body: unknown): Promise<string> {
  return `"${await hashCanonical(body)}"`;
}

function asObject(json: unknown): Record<string, unknown> {
  expect(json).not.toBeNull();
  expect(typeof json).toBe("object");
  expect(Array.isArray(json)).toBe(false);
  return json as Record<string, unknown>;
}

function assertEmptyManifests(json: unknown): Record<string, unknown> {
  const body = asObject(json);
  expect(Object.keys(body)).toEqual(["manifests"]);
  expect(body).toEqual({ manifests: [] });
  return body;
}

function assertPublicProjection(
  json: unknown,
  identity: {
    lifecycleState: string;
    successorId: string | null;
  } = { lifecycleState: "active", successorId: null },
): Record<string, unknown> {
  const body = asObject(json);
  expect(Object.keys(body)).toEqual(["manifests"]);
  const manifests = body.manifests;
  expect(Array.isArray(manifests)).toBe(true);
  expect(manifests).toHaveLength(1);
  const pub = (manifests as Record<string, unknown>[])[0]!;
  expect(pub).toEqual({
    ...EXPECTED_PUBLIC_PROJECTION,
    Identity: {
      ...EXPECTED_PUBLIC_PROJECTION.Identity,
      lifecycleState: identity.lifecycleState,
      successorId: identity.successorId,
    },
  });
  expect(pub).not.toHaveProperty("Access");
  expect(pub).not.toHaveProperty("Prompt binding");
  expect(pub).not.toHaveProperty("Routing");
  expect(pub).not.toHaveProperty("Economics");
  expect(pub).not.toHaveProperty("interactionMode");
  return body;
}

function assertUnauthenticated(json: unknown): void {
  assertTaxonomyBody(json, { code: "unauthenticated", retry_safe: true });
  assertRequestReferenceShape(String(asObject(json).request_reference));
  assertUlidShape(String(asObject(json).trace_id));
}

function assertQuotedEtag(etag: string | null): string {
  expect(etag).toMatch(ETAG_QUOTED_64_HEX);
  return etag as string;
}

function assert200DiscoveryHeaders(result: HttpResult): string {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toBe("application/json");
  expect(result.headers.get("cache-control")).toBe(CACHE_CONTROL);
  return assertQuotedEtag(result.headers.get("etag"));
}

function assert304DiscoveryHeaders(result: HttpResult, etag: string): void {
  expect(result.status).toBe(304);
  expect(result.text).toHaveLength(0);
  expect(result.json).toBeNull();
  expect(result.headers.get("etag")).toBe(etag);
  expect(result.headers.get("cache-control")).toBe(CACHE_CONTROL);
  expect(result.headers.get("content-type")).toBeNull();
}

// HARNESS-GAP: getCapabilities does not return Cache-Control or Content-Type
// and treats 304 as body: null. Header / zero-byte assertions use clinicFetch
// + readHttpResult. Do not extend the frozen barrel.
async function fetchDiscovery(
  token: string,
  extraHeaders: Record<string, string> = {},
): Promise<HttpResult> {
  const response = await clinicFetch("/v1/capabilities", {
    token,
    headers: extraHeaders,
  });
  return readHttpResult(response);
}

async function snapshotPlatform(): Promise<Record<string, number>> {
  const snapshot: Record<string, number> = {};
  for (const table of PLATFORM_TABLES) {
    snapshot[table] = await count(table);
  }
  return snapshot;
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

async function enrollClinic(scenario?: Scenario): Promise<Scenario> {
  const ready = scenario ?? (await newScenario());
  const enrolled = await enrollInstallation(ready, {
    payload: enrollPayload(ready, { plan: "professional" }),
  });
  expect(enrolled.status).toBe(200);
  return ready;
}

async function provisionEntitled(
  mintClaims?: Record<string, unknown>,
): Promise<{ scenario: Scenario; token: string }> {
  const scenario = await enrollClinic();
  const entitled = await entitleInstallation(scenario, INSTALLATION_ONLY_ENTITLE);
  expect(entitled.status).toBe(200);
  const token = await mintAat(
    scenario,
    mintClaims ? { claims: mintClaims } : {},
  );
  return { scenario, token };
}

async function provisionEnrolled(): Promise<{
  scenario: Scenario;
  token: string;
}> {
  const scenario = await enrollClinic();
  const token = await mintAat(scenario);
  return { scenario, token };
}

async function deprecateVisitSummary(): Promise<void> {
  const result = await controlFetch(DEPRECATE_PATH, {
    body: { successor_id: CAPABILITY_ID },
  });
  expect(result.status).toBe(200);
}

async function retireVisitSummary(): Promise<void> {
  await deprecateVisitSummary();
  await seedSql([
    {
      sql: `UPDATE capability_grant
            SET retire_after = ?
            WHERE scope = 'global'
              AND capability_id = ?
              AND capability_version = ?
              AND lifecycle_state = 'deprecated'`,
      params: [PAST_RETIRE_AFTER, CAPABILITY_ID, CAPABILITY_VERSION],
    },
  ]);
  const result = await controlFetch(RETIRE_PATH, { body: {} });
  expect(result.status).toBe(200);
  clearConfigCache();
}

describe("Stage 07 — discovery ETag, cache, lifecycle overlay (S07-038…S07-052)", () => {
  it("S07-038 — Lifecycle overlay retired excludes the capability", async () => {
    const { token } = await provisionEntitled();
    await retireVisitSummary();

    const result = await fetchDiscovery(token);
    const etag = assert200DiscoveryHeaders(result);
    assertEmptyManifests(result.json);
    expect(etag).toBe(await quotedEtagFor({ manifests: [] }));
  });

  it("S07-039 — Deprecated overlay lists with successorId; other fields unchanged", async () => {
    const { token } = await provisionEntitled();
    await deprecateVisitSummary();
    clearConfigCache();

    const result = await fetchDiscovery(token);
    assert200DiscoveryHeaders(result);
    assertPublicProjection(result.json, {
      lifecycleState: "deprecated",
      successorId: CAPABILITY_ID,
    });
    // Pairwise overlay lifecycle_state = "sunset" is also excluded (only
    // active|deprecated pass). No control-plane sunset route exists; reaching
    // it would need an unlabeled D1 UPDATE, so that pairing is not exercised.
  });

  it("S07-040 — Active kill switch does not remove the capability from discovery", async () => {
    const { token } = await provisionEntitled();
    // Catalog S07-040 is [SEED] INSERT (Register 5 #27 claimed no HTTP API).
    // Code has POST /control/kill-switches/arm (Stage 05). Follow the real arm.
    const armed = await controlFetch("/control/kill-switches/arm", {
      body: { scope: "capability", target: CAPABILITY_ID },
    });
    expect(armed.status).toBe(200);
    clearConfigCache();

    const result = await fetchDiscovery(token);
    assert200DiscoveryHeaders(result);
    assertPublicProjection(result.json);
  });

  it("S07-041 — Receptionist + empty scopes still lists the capability", async () => {
    const { token } = await provisionEntitled({
      role: "receptionist",
      scopes: [],
    });

    const result = await fetchDiscovery(token);
    assert200DiscoveryHeaders(result);
    assertPublicProjection(result.json);
  });

  it("S07-042 — Entitled happy path: public projection, ETag, Cache-Control", async () => {
    const { token } = await provisionEntitled();
    const tablesBefore = await snapshotPlatform();
    const r2Before = await countR2Objects();
    expect(tablesBefore.ai_request).toBe(0);

    const result = await fetchDiscovery(token);
    const etag = assert200DiscoveryHeaders(result);
    const body = assertPublicProjection(result.json);
    expect(etag).toBe(await quotedEtagFor(body));

    expect(await snapshotPlatform()).toEqual(tablesBefore);
    expect(await count("ai_request")).toBe(0);
    expect(await countR2Objects()).toBe(r2Before);
  });

  it("S07-043 — If-None-Match exact quoted ETag → 304 empty body", async () => {
    const { token } = await provisionEntitled();
    const first = await fetchDiscovery(token);
    const etag0 = assert200DiscoveryHeaders(first);
    assertPublicProjection(first.json);

    const second = await fetchDiscovery(token, { "If-None-Match": etag0 });
    assert304DiscoveryHeaders(second, etag0);
  });

  it("S07-044 — If-None-Match W/\"etag\" weak validator → 304", async () => {
    const { token } = await provisionEntitled();
    const first = await fetchDiscovery(token);
    const etag0 = assert200DiscoveryHeaders(first);

    const second = await fetchDiscovery(token, {
      "If-None-Match": `W/${etag0}`,
    });
    assert304DiscoveryHeaders(second, etag0);
  });

  it("S07-045 — If-None-Match list with one matching tag → 304", async () => {
    const { token } = await provisionEntitled();
    const first = await fetchDiscovery(token);
    const etag0 = assert200DiscoveryHeaders(first);

    const second = await fetchDiscovery(token, {
      "If-None-Match": `"stale-tag-from-older-poll", ${etag0}`,
    });
    assert304DiscoveryHeaders(second, etag0);
  });

  it("S07-046 — If-None-Match: * → 304 (entitled and empty-list)", async () => {
    const { token } = await provisionEntitled();
    const first = await fetchDiscovery(token);
    const etag0 = assert200DiscoveryHeaders(first);

    const starred = await fetchDiscovery(token, { "If-None-Match": "*" });
    assert304DiscoveryHeaders(starred, etag0);

    const { token: emptyToken } = await provisionEnrolled();
    const emptyGet = await fetchDiscovery(emptyToken);
    const emptyEtag = assert200DiscoveryHeaders(emptyGet);
    assertEmptyManifests(emptyGet.json);
    expect(emptyEtag).toBe(await quotedEtagFor({ manifests: [] }));

    const emptyStar = await fetchDiscovery(emptyToken, {
      "If-None-Match": "*",
    });
    assert304DiscoveryHeaders(emptyStar, emptyEtag);
  });

  it("S07-047 — Stale If-None-Match tag → 200 full body", async () => {
    const { token } = await provisionEntitled();
    const first = await fetchDiscovery(token);
    const etag0 = assert200DiscoveryHeaders(first);

    const stale = await fetchDiscovery(token, {
      "If-None-Match": '"stale-etag-not-current"',
    });
    const etag = assert200DiscoveryHeaders(stale);
    expect(etag).toBe(etag0);
    assertPublicProjection(stale.json);
  });

  it("S07-048 — Malformed If-None-Match → 200; empty value also 200", async () => {
    const { token } = await provisionEntitled();
    const first = await fetchDiscovery(token);
    const etag0 = assert200DiscoveryHeaders(first);

    const malformed = await fetchDiscovery(token, {
      "If-None-Match": "garbage%%%not-an-etag",
    });
    expect(assert200DiscoveryHeaders(malformed)).toBe(etag0);
    assertPublicProjection(malformed.json);

    const emptyHeader = await fetchDiscovery(token, { "If-None-Match": "" });
    expect(assert200DiscoveryHeaders(emptyHeader)).toBe(etag0);
    assertPublicProjection(emptyHeader.json);
  });

  it("S07-049 — Garbage token + If-None-Match never evaluates to 304", async () => {
    const { token } = await provisionEntitled();
    const first = await fetchDiscovery(token);
    const etag0 = assert200DiscoveryHeaders(first);

    const rejected = await fetchDiscovery("not-a-valid-token", {
      "If-None-Match": etag0,
    });
    expect(rejected.status).toBe(401);
    expect(rejected.status).not.toBe(304);
    assertUnauthenticated(rejected.json);
    expect(rejected.headers.get("etag")).toBeNull();
    expect(rejected.headers.get("cache-control")).toBeNull();
  });

  it("S07-050 — ETag is content-derived, not installation-derived", async () => {
    const a = await provisionEntitled();
    const b = await provisionEntitled();

    const first = await fetchDiscovery(a.token);
    const second = await fetchDiscovery(b.token);
    const etagA = assert200DiscoveryHeaders(first);
    const etagB = assert200DiscoveryHeaders(second);
    assertPublicProjection(first.json);
    assertPublicProjection(second.json);
    expect(second.text).toBe(first.text);
    expect(etagB).toBe(etagA);

    const emptyA = await provisionEnrolled();
    const emptyB = await provisionEnrolled();
    const emptyFirst = await fetchDiscovery(emptyA.token);
    const emptySecond = await fetchDiscovery(emptyB.token);
    const emptyEtagA = assert200DiscoveryHeaders(emptyFirst);
    const emptyEtagB = assert200DiscoveryHeaders(emptySecond);
    assertEmptyManifests(emptyFirst.json);
    assertEmptyManifests(emptySecond.json);
    expect(emptySecond.text).toBe(emptyFirst.text);
    expect(emptyEtagB).toBe(emptyEtagA);
    expect(emptyEtagA).toBe(await quotedEtagFor({ manifests: [] }));
    expect(emptyEtagA).not.toBe(etagA);
  });

  it("S07-051 — Revoked grant stays listed while isolate cache is warm", async () => {
    // Pool TTL is 0. Raise a short TTL, revoke in D1 without clearing, then
    // wait for real expiry instead of setTtlMs(30_000) / clearConfigCache().
    const { scenario, token } = await provisionEntitled();
    expect(
      await getGrants(`plan:professional`),
    ).toEqual([]);

    const staleTtlMs = 400;
    const previousTtl = isolateConfigCache.getTtlMs();
    isolateConfigCache.setTtlMs(staleTtlMs);
    try {
      const warm = await getCapabilities(token);

      await env.DB.prepare(
        `UPDATE capability_grant
         SET revoked_at = ?
         WHERE scope = ?
           AND capability_id = ?
           AND capability_version = ?`,
      )
        .bind(
          REVOKE_AT,
          `installation:${scenario.installationId}`,
          CAPABILITY_ID,
          CAPABILITY_VERSION,
        )
        .run();

      const stale = await getCapabilities(token);

      expect(warm.status).toBe(200);
      assertPublicProjection(warm.body);
      const warmEtag = assertQuotedEtag(warm.etag);
      expect(stale.status).toBe(200);
      assertPublicProjection(stale.body);
      expect(stale.etag).toBe(warmEtag);

      await new Promise((resolve) => setTimeout(resolve, staleTtlMs + 50));

      const fresh = await getCapabilities(token);
      expect(fresh.status).toBe(200);
      assertEmptyManifests(fresh.body);
      expect(fresh.etag).toBe(await quotedEtagFor({ manifests: [] }));
      expect(fresh.etag).not.toBe(warmEtag);
    } finally {
      isolateConfigCache.setTtlMs(previousTtl);
    }
  });

  it("S07-052 — Entitle after cached pending entitlement is stale until cache clear", async () => {
    // HARNESS-GAP: entitleInstallation always isolateConfigCache.clear().
    // Catalog wants entitle without busting the cache; use raw controlFetch
    // so the helper's clear is skipped (same pattern as S00-037 activate).
    // Catalog wants injectable new ConfigCache(30000) on handleDiscoveryRequest.
    // SELF.fetch consults isolateConfigCache (barrel); pool TTL is 100 ms.
    // isolateConfigCache is process-global — concurrent files call clear()
    // and restore TTL 100. setTtlMs(30_000) + re-stamp the warmed pending
    // row so the stale GET still observes catalog empty-until-clear.
    const { scenario, token } = await provisionEnrolled();

    const previousTtl = isolateConfigCache.getTtlMs();
    isolateConfigCache.setTtlMs(30_000);
    try {
      const pending = await getCapabilities(token);
      expect(pending.status).toBe(200);
      assertEmptyManifests(pending.body);
      const emptyEtag = assertQuotedEtag(pending.etag);
      expect(emptyEtag).toBe(await quotedEtagFor({ manifests: [] }));

      let cachedPending = isolateConfigCache.consult(
        "entitlements",
        scenario.installationId,
      );
      if (cachedPending?.status !== "pending") {
        const rewarm = await getCapabilities(token);
        expect(rewarm.status).toBe(200);
        assertEmptyManifests(rewarm.body);
        cachedPending = isolateConfigCache.consult(
          "entitlements",
          scenario.installationId,
        );
      }
      expect(cachedPending).toBeDefined();
      expect(cachedPending?.status).toBe("pending");
      const pendingRow = cachedPending!;

      const entitled = await controlFetch(
        `/control/installations/${scenario.installationId}/entitle`,
        { body: INSTALLATION_ONLY_ENTITLE },
      );
      expect(entitled.status).toBe(200);

      let stale: Awaited<ReturnType<typeof getCapabilities>> | undefined;
      for (let attempt = 0; attempt < 8; attempt++) {
        isolateConfigCache.setTtlMs(30_000);
        isolateConfigCache.remember(
          "entitlements",
          scenario.installationId,
          pendingRow,
        );
        stale = await getCapabilities(token);
        const manifests = stale.body?.manifests;
        if (Array.isArray(manifests) && manifests.length === 0) {
          break;
        }
      }

      expect(stale).toBeDefined();
      expect(stale!.status).toBe(200);
      assertEmptyManifests(stale!.body);
      expect(stale!.etag).toBe(emptyEtag);

      clearConfigCache();

      const fresh = await getCapabilities(token);
      expect(fresh.status).toBe(200);
      assertPublicProjection(fresh.body);
      const listedEtag = assertQuotedEtag(fresh.etag);
      expect(listedEtag).not.toBe(emptyEtag);
      expect(listedEtag).toBe(await quotedEtagFor(fresh.body));
    } finally {
      isolateConfigCache.setTtlMs(previousTtl);
      clearConfigCache();
    }
  });
});
