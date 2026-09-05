import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertRequestReferenceShape,
  assertSseSequence,
  assertTaxonomyBody,
  assertUlidShape,
  base64urlEncode,
  bootstrapE2e,
  clearConfigCache,
  clinicFetch,
  controlFetch,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  env,
  flushBackgroundWork,
  generateTestKeypair,
  getRequestByRef,
  isolateConfigCache,
  mintAat,
  newScenario,
  nowSeconds,
  postRequest,
  provisionHappyPath,
  queryOne,
  readHttpResult,
  resetE2eState,
  seedSql,
  TAXONOMY_BODY_KEYS,
  TOKEN_CONTRACT_VER,
  visitSummaryInvokeBody,
  type HttpResult,
  type Scenario,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

/** Catalog S12-029 uses `inst-ghost-999`; enroll ids are UUIDs. Same stand-in as S07-016. */
const UNKNOWN_INSTALLATION_ISS = "11111111-2222-4333-8444-555555555555";

const PAST_VALID_UNTIL = "2026-09-01T00:00:00.000Z";
const FUTURE_VALID_FROM = "2099-01-01T00:00:00.000Z";

type SettledGet = {
  scenario: Scenario;
  ref: string;
};

async function admitAndSettle(scenario: Scenario): Promise<SettledGet> {
  const admitToken = await mintAat(scenario);
  const posted = await postRequest(scenario, {
    token: admitToken,
    idempotencyKey: crypto.randomUUID(),
    body: visitSummaryInvokeBody(scenario),
  });
  await flushBackgroundWork(200);

  expect(posted.status).toBe(200);
  assertSseSequence(posted.events, ["accepted", "completed"], "subsequence");
  const accepted = posted.events.find((event) => event.event === "accepted");
  const ref = String(accepted?.data.request_reference ?? "");
  assertRequestReferenceShape(ref);
  return { scenario, ref };
}

async function settleCompleted(): Promise<SettledGet> {
  const scenario = await provisionHappyPath();
  return admitAndSettle(scenario);
}

/** Second installation in the same `it` — do not republish (409 already_published). */
async function settleOnLivePolicy(): Promise<SettledGet> {
  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  const entitled = await entitleInstallation(scenario, DEFAULT_ENTITLE_PAYLOAD);
  expect(entitled.status).toBe(200);
  return admitAndSettle(scenario);
}

/**
 * HARNESS-GAP: `getRequestByRef` always sends `Authorization: Bearer …`.
 * Missing / non-Bearer / empty-Bearer cases use `clinicFetch` instead.
 */
async function getClinic(
  ref: string,
  options: { token?: string | null; authorization?: string } = {},
): Promise<HttpResult> {
  if (options.authorization !== undefined) {
    const response = await clinicFetch(`/v1/requests/${ref}`, {
      headers: { authorization: options.authorization },
    });
    return readHttpResult(response);
  }
  if (options.token === undefined || options.token === null) {
    const response = await clinicFetch(`/v1/requests/${ref}`);
    return readHttpResult(response);
  }
  return getRequestByRef(options.token, ref);
}

function assertUnauthenticated(result: HttpResult, pathRef: string): void {
  expect(result.status).toBe(401);
  assertTaxonomyBody(result.json, { code: "unauthenticated", retry_safe: true });
  const body = result.json as {
    request_reference: string;
    trace_id: string;
  };
  assertRequestReferenceShape(body.request_reference);
  assertUlidShape(body.trace_id);
  expect(body.request_reference).not.toBe(pathRef);
  expect(Object.keys(body).sort()).toEqual([...TAXONOMY_BODY_KEYS].sort());
}

function assertInstallationSuspended(
  result: HttpResult,
  pathRef: string,
): void {
  expect(result.status).toBe(403);
  assertTaxonomyBody(result.json, {
    code: "installation_suspended",
    retry_safe: false,
  });
  const body = result.json as {
    request_reference: string;
    trace_id: string;
  };
  assertRequestReferenceShape(body.request_reference);
  assertUlidShape(body.trace_id);
  expect(body.request_reference).not.toBe(pathRef);
  expect(Object.keys(body).sort()).toEqual([...TAXONOMY_BODY_KEYS].sort());
}

function assertCompletedGet(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.json).not.toBeNull();
  const body = result.json as Record<string, unknown>;
  expect(Object.keys(body).sort()).toEqual(["result", "state"].sort());
  expect(body.state).toBe("Completed");
  expect(body).not.toHaveProperty("attempts");
  expect(body).not.toHaveProperty("envelope");
  expect(body).not.toHaveProperty("request_id");
  expect(body).not.toHaveProperty("installation_id");
  const canonical = body.result as Record<string, unknown>;
  expect(canonical.finalContent).toEqual({
    type: "text",
    text: "Fake adapter summary.",
  });
  expect(canonical.usage).toEqual({ input: 10, output: 20, cached: 0 });
  expect(canonical.providerModel).toEqual({
    provider: "fake",
    model: "fake-v1",
  });
  expect(canonical.finishReason).toBe("stop");
  expect(canonical.providerRequestId).toBe("fake-req-001");
  expect(canonical.timing).toEqual({
    queue_ms: 1,
    provider_ms: 5,
    total_ms: 6,
  });
}

function tamperPayloadSegment(token: string): string {
  const [header, payload, signature] = token.split(".");
  expect(payload).toEqual(expect.any(String));
  expect(payload!.length).toBeGreaterThan(0);
  const first = payload![0]!;
  const flipped = first === "A" ? "B" : "A";
  return `${header}.${flipped}${payload!.slice(1)}.${signature}`;
}

describe("Stage 12 — GET /v1/requests/{ref} auth (S12-019…S12-040)", () => {
  it("S12-019 — GET without Authorization header returns 401", async () => {
    const { ref } = await settleCompleted();
    const result = await getClinic(ref);
    assertUnauthenticated(result, ref);
  });

  it("S12-020 — non-Bearer Authorization scheme returns 401", async () => {
    const { ref } = await settleCompleted();
    const result = await getClinic(ref, { authorization: "Token abc123" });
    assertUnauthenticated(result, ref);
  });

  it("S12-021 — empty Bearer token returns 401", async () => {
    const { ref } = await settleCompleted();
    const result = await getClinic(ref, { authorization: "Bearer " });
    assertUnauthenticated(result, ref);
  });

  it("S12-022 — structurally malformed token returns 401", async () => {
    const { scenario, ref } = await settleCompleted();

    const twoSegments = await getClinic(ref, { token: "abc.def" });
    assertUnauthenticated(twoSegments, ref);

    const badHeaderB64 = await getClinic(ref, { token: "!!!.e30.sig" });
    assertUnauthenticated(badHeaderB64, ref);

    const nonJsonHeader = await getClinic(ref, {
      token: `${base64urlEncode("not json")}.e30.sig`,
    });
    assertUnauthenticated(nonJsonHeader, ref);

    const headerB64 = base64urlEncode(
      JSON.stringify({ alg: "EdDSA", kid: scenario.kid }),
    );
    const nonJsonPayload = await getClinic(ref, {
      token: `${headerB64}.${base64urlEncode("not json")}.sig`,
    });
    assertUnauthenticated(nonJsonPayload, ref);

    const missingClaims = await mintAat(scenario, {
      omitClaims: [
        "iss",
        "aud",
        "sub",
        "org",
        "branch",
        "role",
        "jti",
        "ver",
        "scopes",
        "iat",
        "exp",
      ],
      skipValidityWait: true,
    });
    const missingRequired = await getClinic(ref, { token: missingClaims });
    assertUnauthenticated(missingRequired, ref);
  });

  it("S12-023 — JWT alg HS256 returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const token = await mintAat(scenario, { alg: "HS256" });
    assertUnauthenticated(await getClinic(ref, { token }), ref);
  });

  it("S12-024 — missing or empty kid returns 401", async () => {
    const { scenario, ref } = await settleCompleted();

    const omitted = await mintAat(scenario, { omitHeaderFields: ["kid"] });
    assertUnauthenticated(await getClinic(ref, { token: omitted }), ref);

    const emptyKid = await mintAat(scenario, { kid: "" });
    assertUnauthenticated(await getClinic(ref, { token: emptyKid }), ref);
  });

  it("S12-025 — wrong audience returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const token = await mintAat(scenario, {
      claims: { aud: "other-service" },
    });
    assertUnauthenticated(await getClinic(ref, { token }), ref);
  });

  it("S12-026 — expired token beyond skew returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const now = nowSeconds();
    const token = await mintAat(scenario, {
      claims: { iat: now - 420, exp: now - 120 },
      skipValidityWait: true,
    });
    assertUnauthenticated(await getClinic(ref, { token }), ref);
  });

  it("S12-027 — future iat beyond skew returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const now = nowSeconds();
    const iat = now + 120;
    const token = await mintAat(scenario, {
      claims: { iat, exp: iat + 300 },
      skipValidityWait: true,
    });
    assertUnauthenticated(await getClinic(ref, { token }), ref);
  });

  it("S12-028 — token lifetime over 600 s returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const now = nowSeconds();
    const token = await mintAat(scenario, {
      claims: { iat: now, exp: now + 900 },
      skipValidityWait: true,
    });
    assertUnauthenticated(await getClinic(ref, { token }), ref);
  });

  it("S12-029 — unknown installation iss returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const unknownKey = await generateTestKeypair();
    const token = await mintAat(scenario, {
      claims: { iss: UNKNOWN_INSTALLATION_ISS },
      keypair: unknownKey,
    });
    assertUnauthenticated(await getClinic(ref, { token }), ref);
  });

  it("S12-030 — unknown kid returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const unknownKid = crypto.randomUUID();
    const token = await mintAat(scenario, { kid: unknownKid });
    assertUnauthenticated(await getClinic(ref, { token }), ref);
    expect(
      await queryOne("SELECT key_id FROM installation_key WHERE key_id = ?", [
        unknownKid,
      ]),
    ).toBeNull();
  });

  it("S12-031 — revoked key returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const token = await mintAat(scenario);
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

    assertUnauthenticated(await getClinic(ref, { token }), ref);
  });

  it("S12-032 — key outside validity window returns 401", async () => {
    const closed = await settleCompleted();
    const closedToken = await mintAat(closed.scenario);
    await seedSql([
      {
        sql: "UPDATE installation_key SET valid_until = ? WHERE key_id = ?",
        params: [PAST_VALID_UNTIL, closed.scenario.kid],
      },
    ]);
    clearConfigCache();
    assertUnauthenticated(
      await getClinic(closed.ref, { token: closedToken }),
      closed.ref,
    );

    const future = await settleOnLivePolicy();
    const futureToken = await mintAat(future.scenario);
    await seedSql([
      {
        sql: "UPDATE installation_key SET valid_from = ? WHERE key_id = ?",
        params: [FUTURE_VALID_FROM, future.scenario.kid],
      },
    ]);
    clearConfigCache();
    assertUnauthenticated(
      await getClinic(future.ref, { token: futureToken }),
      future.ref,
    );
  });

  it("S12-033 — kid bound to a different installation returns 401", async () => {
    const i0 = await settleCompleted();
    const i1 = await newScenario();
    const enrolled = await enrollInstallation(i1);
    expect(enrolled.status).toBe(200);

    const token = await mintAat(i0.scenario, {
      kid: i1.kid,
      keypair: i1.keypair,
    });
    assertUnauthenticated(await getClinic(i0.ref, { token }), i0.ref);
  });

  it("S12-034 — tampered payload signature returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const token = await mintAat(scenario);
    const tampered = tamperPayloadSegment(token);
    expect(tampered).not.toBe(token);
    assertUnauthenticated(await getClinic(ref, { token: tampered }), ref);
  });

  it("S12-035 — suspended installation returns 403", async () => {
    const { scenario, ref } = await settleCompleted();
    const token = await mintAat(scenario);
    const suspended = await controlFetch(
      `/control/installations/${scenario.installationId}/suspend`,
      { body: {} },
    );
    expect(suspended.status).toBe(200);
    clearConfigCache();

    assertInstallationSuspended(await getClinic(ref, { token }), ref);
  });

  it("S12-036 — deleted installation returns 401 not 403", async () => {
    const { scenario, ref } = await settleCompleted();
    const token = await mintAat(scenario);
    await seedSql([
      {
        sql: "UPDATE installation SET status = ? WHERE installation_id = ?",
        params: ["deleted", scenario.installationId],
      },
    ]);
    clearConfigCache();

    const result = await getClinic(ref, { token });
    assertUnauthenticated(result, ref);
    expect(result.json).not.toEqual(
      expect.objectContaining({ code: "installation_suspended" }),
    );
  });

  it("S12-037 — unknown token contract ver returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const token = await mintAat(scenario, { claims: { ver: "v99" } });
    assertUnauthenticated(await getClinic(ref, { token }), ref);
  });

  it("S12-038 — retired token contract returns 401", async () => {
    const { scenario, ref } = await settleCompleted();
    const token = await mintAat(scenario);
    await seedSql([
      {
        sql: "UPDATE token_contract SET retired_at = ? WHERE ver = ?",
        params: [new Date().toISOString(), TOKEN_CONTRACT_VER],
      },
    ]);
    clearConfigCache();

    try {
      assertUnauthenticated(await getClinic(ref, { token }), ref);
    } finally {
      await seedSql([
        {
          sql: "UPDATE token_contract SET retired_at = NULL WHERE ver = ?",
          params: [TOKEN_CONTRACT_VER],
        },
      ]);
      clearConfigCache();
    }
  });

  it("S12-039 — revoked key still authenticates within isolate cache TTL", async () => {
    const { scenario, ref } = await settleCompleted();
    const token = await mintAat(scenario);

    const previousTtl = isolateConfigCache.getTtlMs();
    isolateConfigCache.setTtlMs(30_000);
    try {
      clearConfigCache();
      const warm = await getClinic(ref, { token });
      assertCompletedGet(warm);

      await env.DB.prepare(
        "UPDATE installation_key SET revoked_at = ? WHERE key_id = ?",
      )
        .bind(new Date().toISOString(), scenario.kid)
        .run();

      const stale = await getClinic(ref, { token });
      assertCompletedGet(stale);
    } finally {
      isolateConfigCache.setTtlMs(previousTtl);
      clearConfigCache();
    }
  });

  it("S12-040 — revoked key rejected after isolate cache TTL expires", async () => {
    const { scenario, ref } = await settleCompleted();
    const token = await mintAat(scenario);

    const previousTtl = isolateConfigCache.getTtlMs();
    isolateConfigCache.setTtlMs(50);
    try {
      clearConfigCache();
      const warm = await getClinic(ref, { token });
      assertCompletedGet(warm);

      await env.DB.prepare(
        "UPDATE installation_key SET revoked_at = ? WHERE key_id = ?",
      )
        .bind(new Date().toISOString(), scenario.kid)
        .run();

      await flushBackgroundWork(200);

      const expired = await getClinic(ref, { token });
      assertUnauthenticated(expired, ref);
    } finally {
      isolateConfigCache.setTtlMs(previousTtl);
      clearConfigCache();
    }
  });
});
