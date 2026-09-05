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
  count,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  generateTestKeypair,
  mintAat,
  newScenario,
  nowSeconds,
  queryOne,
  readHttpResult,
  resetE2eState,
  TAXONOMY_BODY_KEYS,
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

/** Catalog B0 has an installation-scope grant only (no plan grant). */
const B0_ENTITLE: EntitlePayload = {
  ...DEFAULT_ENTITLE_PAYLOAD,
  grants: [
    {
      capability_id: CAPABILITY_ID,
      capability_version: CAPABILITY_VERSION,
      scope: "installation",
    },
  ],
};

/** Catalog S07-016 forged `iss` — not a D1 row; not a `newScenario()` installation. */
const UNKNOWN_INSTALLATION_ISS = "11111111-2222-4333-8444-555555555555";

async function provisionB0(): Promise<{ scenario: Scenario; token: string }> {
  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  const entitled = await entitleInstallation(scenario, B0_ENTITLE);
  expect(entitled.status).toBe(200);
  const token = await mintAat(scenario);
  return { scenario, token };
}

function assertNoCacheHeaders(result: HttpResult): void {
  expect(result.headers.get("etag")).toBeNull();
  expect(result.headers.get("cache-control")).toBeNull();
}

function assertPlainNotFound(result: HttpResult): void {
  expect(result.status).toBe(404);
  expect(result.text).toBe("Not Found");
  expect(result.json).toBeNull();
  expect(result.headers.get("content-type") ?? "").not.toContain(
    "application/json",
  );
  assertNoCacheHeaders(result);
}

function assertUnauthenticated(result: HttpResult): void {
  expect(result.status).toBe(401);
  expect(result.headers.get("content-type")).toContain("application/json");
  assertTaxonomyBody(result.json, { code: "unauthenticated", retry_safe: true });
  const body = result.json as {
    request_reference: string;
    trace_id: string;
  };
  assertRequestReferenceShape(body.request_reference);
  assertUlidShape(body.trace_id);
  expect(Object.keys(body).sort()).toEqual([...TAXONOMY_BODY_KEYS].sort());
  assertNoCacheHeaders(result);
}

async function discoveryGet(options: {
  token?: string | null;
  headers?: Record<string, string>;
} = {}): Promise<HttpResult> {
  const response = await clinicFetch("/v1/capabilities", {
    token: options.token ?? undefined,
    headers: options.headers,
  });
  return readHttpResult(response);
}

async function discoveryWithAuthorization(
  authorization: string,
): Promise<HttpResult> {
  return discoveryGet({ headers: { authorization } });
}

function assertEntitledDiscovery(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  const body = result.json as { manifests?: unknown };
  expect(Array.isArray(body.manifests)).toBe(true);
  expect(body.manifests).toHaveLength(1);
}

describe("Stage 07 — discovery routing and identity (S07-001…S07-018)", () => {
  it("S07-001 — POST /v1/capabilities is not routed", async () => {
    const { token } = await provisionB0();
    const aiRequestBefore = await count("ai_request");

    const response = await clinicFetch("/v1/capabilities", {
      method: "POST",
      token,
      headers: { "content-type": "application/json" },
      body: {},
    });
    const result = await readHttpResult(response);

    assertPlainNotFound(result);
    expect(await count("ai_request")).toBe(aiRequestBefore);
  });

  it("S07-002 — GET /v1/capabilities/ trailing slash is not routed", async () => {
    const { token } = await provisionB0();
    const aiRequestBefore = await count("ai_request");

    const response = await clinicFetch("/v1/capabilities/", { token });
    const result = await readHttpResult(response);

    assertPlainNotFound(result);
    expect(await count("ai_request")).toBe(aiRequestBefore);
  });

  it("S07-003 — Missing Authorization → 401 unauthenticated", async () => {
    await provisionB0();
    // HARNESS-GAP: cannot assert discovery_auth_rejected log reason
    // missing_authorization_header (isolate console is not captured).
    const result = await discoveryGet();

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S07-004 — Non-Bearer Authorization scheme → 401", async () => {
    await provisionB0();
    // HARNESS-GAP: cannot assert log reason invalid_authorization_scheme
    // with authorization_scheme "Basic". Scheme check is case-sensitive
    // startsWith("Bearer ").
    const result = await discoveryWithAuthorization(
      "Basic bm90LWFuLWFhdA==",
    );

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S07-005 — Bearer with whitespace-only token → 401", async () => {
    await provisionB0();
    // HARNESS-GAP: cannot assert log reason empty_bearer_token. Bare
    // `Authorization: Bearer` (no trailing space) is a different reason
    // (invalid_authorization_scheme); this case is whitespace-only.
    const result = await discoveryWithAuthorization("Bearer    ");

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S07-006 — Lowercase bearer scheme → 401", async () => {
    const { token } = await provisionB0();
    // HARNESS-GAP: cannot assert log reason invalid_authorization_scheme
    // with authorization_scheme "bearer".
    const result = await discoveryWithAuthorization(`bearer ${token}`);

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S07-007 — Token is not three segments → 401", async () => {
    await provisionB0();
    const result = await discoveryGet({ token: "not-a-valid-token" });

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S07-008 — Undecodable / non-JSON JWT header → 401", async () => {
    await provisionB0();

    const undecodable = await discoveryGet({ token: "###.e30.sig" });
    assertUnauthenticated(undecodable);

    const notJsonHeader = `${base64urlEncode("not json")}.e30.sig`;
    const nonJson = await discoveryGet({ token: notJsonHeader });
    assertUnauthenticated(nonJson);

    expect(await count("ai_request")).toBe(0);
  });

  it("S07-009 — JWT alg HS256 → 401", async () => {
    const { scenario } = await provisionB0();
    const token = await mintAat(scenario, { alg: "HS256" });
    const result = await discoveryGet({ token });

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S07-010 — JWT header missing kid → 401", async () => {
    const { scenario } = await provisionB0();
    const token = await mintAat(scenario, { omitHeaderFields: ["kid"] });
    const result = await discoveryGet({ token });

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S07-011 — Payload missing required claims → 401", async () => {
    const { scenario } = await provisionB0();

    const missingClaims = await mintAat(scenario, {
      omitClaims: ["sub", "org", "branch", "role", "scopes", "jti", "ver"],
    });
    assertUnauthenticated(await discoveryGet({ token: missingClaims }));

    const scopesAsString = await mintAat(scenario, {
      claims: { scopes: "ai.visit_summary" },
      skipValidityWait: true,
    });
    assertUnauthenticated(await discoveryGet({ token: scopesAsString }));

    const expAsString = await mintAat(scenario, {
      claims: { exp: String(nowSeconds() + 300) },
      skipValidityWait: true,
    });
    assertUnauthenticated(await discoveryGet({ token: expAsString }));

    expect(await count("ai_request")).toBe(0);
  });

  it("S07-012 — Wrong audience claim → 401", async () => {
    const { scenario } = await provisionB0();
    const token = await mintAat(scenario, {
      claims: { aud: "clinic-portal" },
    });
    const result = await discoveryGet({ token });

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S07-013 — Expired AAT beyond 60s skew → 401", async () => {
    const { scenario } = await provisionB0();
    const now = nowSeconds();

    const expired = await mintAat(scenario, {
      claims: { iat: now - 900, exp: now - 120 },
      skipValidityWait: true,
    });
    assertUnauthenticated(await discoveryGet({ token: expired }));

    const insideSkew = await mintAat(scenario, {
      claims: { iat: now - 300, exp: now - 59 },
      skipValidityWait: true,
    });
    assertEntitledDiscovery(await discoveryGet({ token: insideSkew }));
  });

  it("S07-014 — AAT iat in the future beyond skew → 401", async () => {
    const { scenario } = await provisionB0();
    const now = nowSeconds();

    const tooNew = await mintAat(scenario, {
      claims: { iat: now + 120, exp: now + 420 },
      skipValidityWait: true,
    });
    assertUnauthenticated(await discoveryGet({ token: tooNew }));

    const insideSkew = await mintAat(scenario, {
      claims: { iat: now + 59, exp: now + 59 + 330 },
      skipValidityWait: true,
    });
    assertEntitledDiscovery(await discoveryGet({ token: insideSkew }));
  });

  it("S07-015 — AAT lifetime exceeds 600s → 401", async () => {
    const { scenario } = await provisionB0();
    const iat = nowSeconds();

    const overCap = await mintAat(scenario, {
      claims: { iat, exp: iat + 601 },
      skipValidityWait: true,
    });
    assertUnauthenticated(await discoveryGet({ token: overCap }));

    const atCap = await mintAat(scenario, {
      claims: { iat, exp: iat + 600 },
      skipValidityWait: true,
    });
    assertEntitledDiscovery(await discoveryGet({ token: atCap }));
  });

  it("S07-016 — Unknown installation iss → 401", async () => {
    const { scenario } = await provisionB0();
    const unknownKey = await generateTestKeypair();
    const token = await mintAat(scenario, {
      claims: { iss: UNKNOWN_INSTALLATION_ISS },
      keypair: unknownKey,
    });
    const result = await discoveryGet({ token });

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S07-017 — Unknown kid in header → 401", async () => {
    const { scenario } = await provisionB0();
    const unknownKid = crypto.randomUUID();
    const token = await mintAat(scenario, { kid: unknownKid });
    const result = await discoveryGet({ token });

    assertUnauthenticated(result);
    expect(
      await queryOne("SELECT key_id FROM installation_key WHERE key_id = ?", [
        unknownKid,
      ]),
    ).toBeNull();
    expect(await count("ai_request")).toBe(0);
  });

  it("S07-018 — Revoked signing key → 401", async () => {
    const { scenario, token } = await provisionB0();
    const rotated = await generateTestKeypair();

    const rotate = await controlFetch(
      `/control/installations/${scenario.installationId}/rotate`,
      {
        body: {
          kid: rotated.kid,
          public_key: rotated.publicKeyB64,
          algorithm: "EdDSA",
        },
      },
    );
    expect(rotate.status).toBe(200);

    const revoke = await controlFetch(
      `/control/installations/${scenario.installationId}/revoke-key`,
      { body: { kid: scenario.kid } },
    );
    expect(revoke.status).toBe(200);
    clearConfigCache();

    const key = await queryOne<{ revoked_at: string | null }>(
      "SELECT revoked_at FROM installation_key WHERE key_id = ?",
      [scenario.kid],
    );
    expect(key?.revoked_at).not.toBeNull();

    const aiRequestBefore = await count("ai_request");
    const result = await discoveryGet({ token });

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(aiRequestBefore);
    const keyAfter = await queryOne<{ revoked_at: string | null }>(
      "SELECT revoked_at FROM installation_key WHERE key_id = ?",
      [scenario.kid],
    );
    expect(keyAfter?.revoked_at).toBe(key?.revoked_at);
  });
});
