import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertRequestReferenceShape,
  assertTaxonomyBody,
  assertUlidShape,
  base64urlEncode,
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clearConfigCache,
  clinicFetch,
  controlFetch,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  enrollPayload,
  entitleInstallation,
  getEntitlement,
  getGrants,
  mintAat,
  newScenario,
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
const EMPTY_LIST_BODY = { manifests: [] } as const;
const CLOSED_VALID_UNTIL = "2026-09-01T00:00:00.000Z";
const GRANT_REVOKED_AT = "2026-09-05T00:00:00.000Z";
const UNPUBLISHED_CAPABILITY_ID = "clinic.patient_triage";

const INSTALLATION_GRANT = {
  capability_id: CAPABILITY_ID,
  capability_version: CAPABILITY_VERSION,
  scope: "installation" as const,
};

const PLAN_GRANT = {
  capability_id: CAPABILITY_ID,
  capability_version: CAPABILITY_VERSION,
  scope: "plan" as const,
};

const UNPUBLISHED_INSTALLATION_GRANT = {
  capability_id: UNPUBLISHED_CAPABILITY_ID,
  capability_version: CAPABILITY_VERSION,
  scope: "installation" as const,
};

function installationOnlyPayload(
  overrides: Partial<EntitlePayload> = {},
): EntitlePayload {
  return {
    ...DEFAULT_ENTITLE_PAYLOAD,
    grants: [INSTALLATION_GRANT],
    ...overrides,
  };
}

async function enrollWithPlan(
  scenario: Scenario,
  plan: string,
): Promise<void> {
  const enrolled = await enrollInstallation(scenario, {
    payload: enrollPayload(scenario, { plan }),
  });
  expect(enrolled.status).toBe(200);
}

/** Catalog B0: enrolled professional installation, installation-scope grant only. */
async function provisionB0(scenario?: Scenario): Promise<Scenario> {
  const ready = scenario ?? (await newScenario());
  await enrollWithPlan(ready, "professional");
  const entitled = await entitleInstallation(
    ready,
    installationOnlyPayload(),
  );
  expect(entitled.status).toBe(200);
  return ready;
}

/**
 * HARNESS-GAP: `getCapabilities` does not return Cache-Control (or the
 * full header set). Catalog empty-list 200s require
 * `Cache-Control: private, must-revalidate` and a quoted ETag.
 */
async function discoveryGet(token: string): Promise<HttpResult> {
  const response = await clinicFetch("/v1/capabilities", { token });
  return readHttpResult(response);
}

function assertUnauthenticated(result: HttpResult): void {
  expect(result.status).toBe(401);
  assertTaxonomyBody(result.json, {
    code: "unauthenticated",
    retry_safe: true,
  });
  const body = result.json as { request_reference: string; trace_id: string };
  assertRequestReferenceShape(body.request_reference);
  assertUlidShape(body.trace_id);
  expect(result.headers.get("etag")).toBeNull();
  expect(result.headers.get("cache-control")).toBeNull();
}

async function emptyListQuotedEtag(): Promise<string> {
  const encoded = new TextEncoder().encode('{"manifests":[]}');
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  const hex = [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return `"${hex}"`;
}

async function assertEmptyList(result: HttpResult): Promise<void> {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.headers.get("cache-control")).toBe("private, must-revalidate");
  expect(result.headers.get("etag")).toBe(await emptyListQuotedEtag());
  expect(result.headers.get("etag")).toMatch(ETAG_QUOTED_64_HEX);
  expect(result.json).toEqual(EMPTY_LIST_BODY);
  expect(result.text).toBe('{"manifests":[]}');
}

function assertListedVisitSummary(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.headers.get("etag")).toMatch(ETAG_QUOTED_64_HEX);
  const body = result.json as Record<string, unknown>;
  const manifests = body.manifests;
  expect(Array.isArray(manifests)).toBe(true);
  expect(manifests).toHaveLength(1);
  const identity = (manifests as Record<string, unknown>[])[0]?.Identity as
    | Record<string, unknown>
    | undefined;
  expect(identity).toMatchObject({
    capabilityId: CAPABILITY_ID,
    version: CAPABILITY_VERSION,
  });
}

async function revokeInstallationVisitSummaryGrant(
  installationId: string,
): Promise<void> {
  // Catalog specified D1 UPDATE; no revoke-grant HTTP exists.
  await seedSql([
    {
      sql: `UPDATE capability_grant
            SET revoked_at = ?
            WHERE scope = ? AND capability_id = ?`,
      params: [
        GRANT_REVOKED_AT,
        `installation:${installationId}`,
        CAPABILITY_ID,
      ],
    },
  ]);
  clearConfigCache();
}

describe("Stage 07 — entitlement filters (S07-019…S07-037)", () => {
  it("S07-019 — signing key outside validity window → 401", async () => {
    const closed = await provisionB0();
    const closedToken = await mintAat(closed);
    // Catalog D1 UPDATE: no HTTP sets valid_until; last active key cannot be revoked.
    await seedSql([
      {
        sql: "UPDATE installation_key SET valid_until = ? WHERE key_id = ?",
        params: [CLOSED_VALID_UNTIL, closed.kid],
      },
    ]);
    clearConfigCache();
    assertUnauthenticated(await discoveryGet(closedToken));

    // Boundary pairing: a future valid_from rejects symmetrically.
    const future = await provisionB0();
    const futureToken = await mintAat(future);
    await seedSql([
      {
        sql: "UPDATE installation_key SET valid_from = ? WHERE key_id = ?",
        params: ["2099-01-01T00:00:00.000Z", future.kid],
      },
    ]);
    clearConfigCache();
    assertUnauthenticated(await discoveryGet(futureToken));
  });

  it("S07-020 — kid belongs to a different installation → 401", async () => {
    const i0 = await provisionB0();
    const i1 = await newScenario();
    await enrollWithPlan(i1, "professional");

    const token = await mintAat(i0, { kid: i1.kid });
    assertUnauthenticated(await discoveryGet(token));
  });

  it("S07-021 — stored key material unimportable → 401", async () => {
    const scenario = await provisionB0();
    const token = await mintAat(scenario);
    await seedSql([
      {
        sql: "UPDATE installation_key SET public_key = ? WHERE key_id = ?",
        params: ["not-base64url!!!", scenario.kid],
      },
    ]);
    clearConfigCache();
    assertUnauthenticated(await discoveryGet(token));
  });

  it("S07-022 — invalid Ed25519 signature → 401", async () => {
    const scenario = await provisionB0();
    const token = await mintAat(scenario, {
      signatureB64: base64urlEncode(new Uint8Array(64)),
    });
    assertUnauthenticated(await discoveryGet(token));
  });

  it("S07-023 — suspended installation → 403 installation_suspended", async () => {
    const scenario = await provisionB0();
    const token = await mintAat(scenario);
    const suspended = await controlFetch(
      `/control/installations/${scenario.installationId}/suspend`,
      { body: {} },
    );
    expect(suspended.status).toBe(200);
    clearConfigCache();

    const result = await discoveryGet(token);
    expect(result.status).toBe(403);
    assertTaxonomyBody(result.json, {
      code: "installation_suspended",
      retry_safe: false,
    });
    const body = result.json as { request_reference: string; trace_id: string };
    assertRequestReferenceShape(body.request_reference);
    assertUlidShape(body.trace_id);
    expect(result.headers.get("etag")).toBeNull();
    expect(result.headers.get("cache-control")).toBeNull();
  });

  it("S07-024 — pending installation → 401 not 403", async () => {
    const scenario = await newScenario();
    await enrollWithPlan(scenario, "professional");
    // Catalog D1 UPDATE: enroll writes status=active; no HTTP "stop before activation".
    await seedSql([
      {
        sql: "UPDATE installation SET status = ? WHERE installation_id = ?",
        params: ["pending", scenario.installationId],
      },
    ]);
    clearConfigCache();

    const token = await mintAat(scenario);
    const result = await discoveryGet(token);
    assertUnauthenticated(result);
    expect(result.json).not.toEqual(
      expect.objectContaining({ code: "installation_suspended" }),
    );
  });

  it("S07-025 — unknown token contract ver → 401", async () => {
    const scenario = await provisionB0();
    const token = await mintAat(scenario, { claims: { ver: "2" } });
    assertUnauthenticated(await discoveryGet(token));
  });

  it("S07-026 — retired token contract → 401", async () => {
    const scenario = await provisionB0();
    const token = await mintAat(scenario);

    const opened = await controlFetch("/control/token-contract/begin-rotation", {
      body: { ver: "2" },
    });
    expect(opened.status).toBe(200);
    const retired = await controlFetch("/control/token-contract/retire", {
      body: { ver: "1" },
    });
    expect(retired.status).toBe(200);
    clearConfigCache();

    assertUnauthenticated(await discoveryGet(token));
  });

  it("S07-027 — no entitlement row → 200 empty list", async () => {
    const scenario = await newScenario();
    await enrollWithPlan(scenario, "professional");
    // Catalog journey: delete the enroll pending sentinel. No HTTP deletes it.
    await seedSql([
      {
        sql: "DELETE FROM entitlement WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();
    expect(await getEntitlement(scenario.installationId)).toBeNull();

    const token = await mintAat(scenario);
    await assertEmptyList(await discoveryGet(token));
  });

  it("S07-028 — entitlement pending → 200 empty list", async () => {
    const scenario = await newScenario();
    await enrollWithPlan(scenario, "professional");
    const entitlement = await getEntitlement(scenario.installationId);
    expect(entitlement?.status).toBe("pending");
    expect(entitlement?.allowed_capabilities).toBe("[]");

    const token = await mintAat(scenario);
    await assertEmptyList(await discoveryGet(token));
  });

  it("S07-029 — active entitlement empty allowed_capabilities → 200 empty", async () => {
    const scenario = await newScenario();
    await enrollWithPlan(scenario, "professional");
    // Catalog wants grants: [] / no grant rows. Code rejects empty grants
    // (400 invalid_payload, S04-040). Dummy grant is never consulted:
    // allowed_capabilities [] skips the registry loop before grant evaluation.
    const entitled = await entitleInstallation(
      scenario,
      installationOnlyPayload({ allowed_capabilities: [] }),
    );
    expect(entitled.status).toBe(200);

    const token = await mintAat(scenario);
    await assertEmptyList(await discoveryGet(token));
  });

  it("S07-030 — malformed allowed_capabilities JSON → 200 empty", async () => {
    const variants = ["not json", "[1]", '{"a":1}'];
    for (const corrupt of variants) {
      const scenario = await provisionB0();
      await seedSql([
        {
          sql: "UPDATE entitlement SET allowed_capabilities = ? WHERE installation_id = ?",
          params: [corrupt, scenario.installationId],
        },
      ]);
      clearConfigCache();
      const token = await mintAat(scenario);
      await assertEmptyList(await discoveryGet(token));
    }
  });

  it("S07-031 — capability not in allowed list → 200 empty", async () => {
    const scenario = await newScenario();
    await enrollWithPlan(scenario, "professional");
    const entitled = await entitleInstallation(
      scenario,
      installationOnlyPayload({
        allowed_capabilities: [UNPUBLISHED_CAPABILITY_ID],
        grants: [UNPUBLISHED_INSTALLATION_GRANT],
      }),
    );
    expect(entitled.status).toBe(200);

    const token = await mintAat(scenario);
    await assertEmptyList(await discoveryGet(token));
  });

  it("S07-032 — plan below minimum (starter) empty; standard lists", async () => {
    const starter = await newScenario();
    await enrollWithPlan(starter, "starter");
    const starterEntitled = await entitleInstallation(
      starter,
      installationOnlyPayload(),
    );
    expect(starterEntitled.status).toBe(200);
    expect(await getGrants(`installation:${starter.installationId}`)).toHaveLength(
      1,
    );
    const starterToken = await mintAat(starter);
    await assertEmptyList(await discoveryGet(starterToken));

    const standard = await newScenario();
    await enrollWithPlan(standard, "standard");
    const standardEntitled = await entitleInstallation(
      standard,
      installationOnlyPayload(),
    );
    expect(standardEntitled.status).toBe(200);
    const standardToken = await mintAat(standard);
    assertListedVisitSummary(await discoveryGet(standardToken));
  });

  it("S07-033 — installation grant revoked, no plan grant → 200 empty", async () => {
    const scenario = await provisionB0();
    expect(
      await getGrants(`plan:professional`),
    ).toEqual([]);
    await revokeInstallationVisitSummaryGrant(scenario.installationId);

    const token = await mintAat(scenario);
    await assertEmptyList(await discoveryGet(token));
  });

  it("S07-034 — installation grant revoked but plan grant exists → listed", async () => {
    const scenario = await newScenario();
    await enrollWithPlan(scenario, "professional");
    const entitled = await entitleInstallation(scenario, {
      ...DEFAULT_ENTITLE_PAYLOAD,
      grants: [INSTALLATION_GRANT, PLAN_GRANT],
    });
    expect(entitled.status).toBe(200);
    await revokeInstallationVisitSummaryGrant(scenario.installationId);

    const token = await mintAat(scenario);
    assertListedVisitSummary(await discoveryGet(token));
  });

  it("S07-035 — grant pinned to 2.0.0 → 200 empty", async () => {
    const scenario = await newScenario();
    await enrollWithPlan(scenario, "professional");
    const entitled = await entitleInstallation(
      scenario,
      installationOnlyPayload({
        grants: [
          {
            capability_id: CAPABILITY_ID,
            capability_version: "2.0.0",
            scope: "installation",
          },
        ],
      }),
    );
    expect(entitled.status).toBe(200);
    expect(await getGrants("plan:professional")).toEqual([]);

    const token = await mintAat(scenario);
    await assertEmptyList(await discoveryGet(token));
  });

  it("S07-036 — plan-scope grant only → listed", async () => {
    const scenario = await newScenario();
    await enrollWithPlan(scenario, "professional");
    const entitled = await entitleInstallation(scenario, {
      ...DEFAULT_ENTITLE_PAYLOAD,
      grants: [PLAN_GRANT],
    });
    expect(entitled.status).toBe(200);
    expect(
      await getGrants(`installation:${scenario.installationId}`),
    ).toEqual([]);
    expect(await getGrants("plan:professional")).toHaveLength(1);

    const token = await mintAat(scenario);
    assertListedVisitSummary(await discoveryGet(token));
  });

  it("S07-037 — no grant at either scope → 200 empty", async () => {
    const scenario = await newScenario();
    await enrollWithPlan(scenario, "professional");
    // Catalog wants grants: []. Code rejects empty grants (400 invalid_payload,
    // S04-040). Dummy unpublished installation grant so both visit_summary
    // grant lookups miss (installation miss → plan miss → skip).
    const entitled = await entitleInstallation(
      scenario,
      installationOnlyPayload({
        allowed_capabilities: [CAPABILITY_ID],
        grants: [UNPUBLISHED_INSTALLATION_GRANT],
      }),
    );
    expect(entitled.status).toBe(200);
    const installationGrants = await getGrants(
      `installation:${scenario.installationId}`,
    );
    expect(
      installationGrants.filter((row) => row.capability_id === CAPABILITY_ID),
    ).toEqual([]);
    expect(await getGrants("plan:professional")).toEqual([]);

    const token = await mintAat(scenario);
    await assertEmptyList(await discoveryGet(token));
  });
});
