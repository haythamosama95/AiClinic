import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertRequestReferenceShape,
  assertSseSequence,
  assertTaxonomyBody,
  base64urlEncode,
  bootstrapE2e,
  clearConfigCache,
  controlFetch,
  count,
  enrollInstallation,
  ensureInstallationKeyActive,
  generateTestKeypair,
  mintAat,
  newScenario,
  nowSeconds,
  postRequest,
  provisionHappyPath,
  queryOne,
  resetE2eState,
  seedSql,
  visitSummaryInvokeBody,
  type InvokeResult,
  type Scenario,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const TRACE_ID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
const INGRESS_OVER_LIMIT_BYTES = 1_048_577;
const UNKNOWN_INSTALLATION_ISS = "00000000-0000-4000-8000-000000000099";

function happyBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return visitSummaryInvokeBody(scenario, {
    user_intent: "Summarize today's visit for the chart.",
    ...overrides,
  });
}

function paddedH0(scenario: Scenario, targetBytes: number): string {
  const withoutPad = JSON.stringify(happyBody(scenario));
  const prefix = `${withoutPad.slice(0, -1)},"pad":"`;
  const suffix = `"}`;
  const padLen = targetBytes - prefix.length - suffix.length;
  return `${prefix}${"x".repeat(padLen)}${suffix}`;
}

function assertBare422(result: InvokeResult): void {
  expect(result.status).toBe(422);
  expect(result.headers.get("content-type")).toContain("text/plain");
  expect(result.text).toBe("");
  expect(result.body).toBeNull();
  expect(result.events).toEqual([]);
}

function assertJsonTaxonomyNoSse(result: InvokeResult): void {
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.events).toEqual([]);
}

function assertUnauthenticated(result: InvokeResult): void {
  expect(result.status).toBe(401);
  assertJsonTaxonomyNoSse(result);
  assertTaxonomyBody(result.body, {
    code: "unauthenticated",
    retry_safe: true,
  });
  assertRequestReferenceShape(String(result.body.request_reference));
  expect(result.body.request_reference).not.toBe("");
  expect(result.body.trace_id).toBe(TRACE_ID);
}

function assertNotRejectedAsUnauthenticated(result: InvokeResult): void {
  expect(result.status).not.toBe(401);
  if (result.body?.code !== undefined) {
    expect(result.body.code).not.toBe("unauthenticated");
  }
}

function assertAcceptedSse(result: InvokeResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
  assertSseSequence(result.events, ["accepted"]);
  const accepted = result.events[0];
  expect(accepted?.event).toBe("accepted");
  assertRequestReferenceShape(String(accepted?.data.request_reference));
  expect(accepted?.data.trace_id).toBe(TRACE_ID);
}

async function assertNoRequestWrites(): Promise<void> {
  expect(await count("ai_request")).toBe(0);
  expect(await count("usage_event")).toBe(0);
  expect(await count("grace_admission_queue")).toBe(0);
}

async function postInvoke(
  scenario: Scenario,
  options: {
    token?: string | null;
    body?: Record<string, unknown> | string;
  } = {},
): Promise<InvokeResult> {
  const token =
    options.token !== undefined ? options.token : await mintAat(scenario);
  return postRequest(scenario, {
    token,
    body: options.body ?? happyBody(scenario),
    traceId: TRACE_ID,
  });
}

describe("Stage 09 — adapter parse and identity (S09-001…S09-022)", () => {
  it("S09-001 — body over 1 MiB is request_too_large", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario);
    const body = paddedH0(scenario, INGRESS_OVER_LIMIT_BYTES);
    expect(new TextEncoder().encode(body).byteLength).toBe(
      INGRESS_OVER_LIMIT_BYTES,
    );

    const result = await postInvoke(scenario, { token, body });

    expect(result.status).toBe(413);
    assertJsonTaxonomyNoSse(result);
    assertTaxonomyBody(result.body, {
      code: "request_too_large",
      retry_safe: false,
    });
    expect(result.body.request_reference).toBe("");
    expect(result.body.trace_id).toBe("");
    expect(result.body).toEqual({
      code: "request_too_large",
      request_reference: "",
      trace_id: "",
      retry_safe: false,
    });
    await assertNoRequestWrites();
  });

  it("S09-002 — non-object JSON is a bare 422", async () => {
    const scenario = await provisionHappyPath();

    for (const raw of ["not-json", "[]", "null"] as const) {
      const token = await mintAat(scenario);
      const result = await postInvoke(scenario, { token, body: raw });
      assertBare422(result);
    }

    await assertNoRequestWrites();
  });

  it("S09-003 — missing capability_id is internal_error 500", async () => {
    const scenario = await provisionHappyPath();
    const h0 = happyBody(scenario, {
      user_intent: "Summarize today's visit.",
    });
    const token = await mintAat(scenario);
    const result = await postInvoke(scenario, {
      token,
      body: {
        user_intent: h0.user_intent,
        context: h0.context,
      },
    });

    expect(result.status).toBe(500);
    assertJsonTaxonomyNoSse(result);
    assertTaxonomyBody(result.body, {
      code: "internal_error",
      retry_safe: true,
    });
    assertRequestReferenceShape(String(result.body.request_reference));
    expect(result.body.request_reference).not.toBe("");
    expect(result.body.trace_id).toBe(TRACE_ID);
    await assertNoRequestWrites();
  });

  it("S09-004 — no Authorization is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const result = await postInvoke(scenario, { token: null });

    assertUnauthenticated(result);
    await assertNoRequestWrites();
  });

  it("S09-005 — Bearer not-a-jwt is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const result = await postInvoke(scenario, { token: "not-a-jwt" });

    assertUnauthenticated(result);
    await assertNoRequestWrites();
  });

  it("S09-006 — empty JWS payload segment is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const result = await postInvoke(scenario, { token: "e30..e30" });

    assertUnauthenticated(result);
    await assertNoRequestWrites();
  });

  it("S09-007 — undecodable or non-JSON JWS header is unauthenticated", async () => {
    const scenario = await provisionHappyPath();

    const undecodable = await postInvoke(scenario, {
      token: "%%%.e30.e30",
    });
    assertUnauthenticated(undecodable);

    const notJsonHeader = `${base64urlEncode("not json")}.e30.e30`;
    const nonJson = await postInvoke(scenario, { token: notJsonHeader });
    assertUnauthenticated(nonJson);

    await assertNoRequestWrites();
  });

  it("S09-008 — alg HS256 is unauthenticated before key lookup", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario, {
      alg: "HS256",
      signatureB64: "e30",
    });
    const result = await postInvoke(scenario, { token });

    assertUnauthenticated(result);
    await assertNoRequestWrites();
  });

  it("S09-009 — empty kid is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario, {
      kid: "",
      signatureB64: "e30",
    });
    const result = await postInvoke(scenario, { token });

    assertUnauthenticated(result);
    await assertNoRequestWrites();
  });

  it("S09-010 — undecodable or non-JSON JWS payload is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const headerB64 = base64urlEncode(
      JSON.stringify({ alg: "EdDSA", kid: scenario.kid }),
    );

    const undecodable = await postInvoke(scenario, {
      token: `${headerB64}.%%%.e30`,
    });
    assertUnauthenticated(undecodable);

    const notJsonPayload = `${headerB64}.${base64urlEncode("not json")}.e30`;
    const nonJson = await postInvoke(scenario, { token: notJsonPayload });
    assertUnauthenticated(nonJson);

    await assertNoRequestWrites();
  });

  it("S09-011 — missing or wrong-typed claims are unauthenticated", async () => {
    const scenario = await provisionHappyPath();

    const missingOrg = await mintAat(scenario, {
      omitClaims: ["org"],
      signatureB64: "e30",
    });
    assertUnauthenticated(await postInvoke(scenario, { token: missingOrg }));

    const scopesAsString = await mintAat(scenario, {
      claims: { scopes: "ai.visit_summary" },
      signatureB64: "e30",
      skipValidityWait: true,
    });
    assertUnauthenticated(
      await postInvoke(scenario, { token: scopesAsString }),
    );

    const iatAsString = await mintAat(scenario, {
      claims: { iat: "1757000000" },
      signatureB64: "e30",
      skipValidityWait: true,
    });
    assertUnauthenticated(await postInvoke(scenario, { token: iatAsString }));

    await assertNoRequestWrites();
  });

  it("S09-012 — wrong audience is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario, {
      claims: { aud: "other-audience" },
    });
    const result = await postInvoke(scenario, { token });

    assertUnauthenticated(result);
    await assertNoRequestWrites();
  });

  it("S09-013 — iat too far in the future is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const now = nowSeconds();

    const tooNew = await mintAat(scenario, {
      claims: { iat: now + 120, exp: now + 120 + 300 },
      skipValidityWait: true,
    });
    assertUnauthenticated(await postInvoke(scenario, { token: tooNew }));
    await assertNoRequestWrites();

    // Wait for valid_from, then mint at the iat skew limit so this token
    // is not rejected at the cheap iat check (identity/index.ts:L286-L291).
    await ensureInstallationKeyActive(scenario.installationId);
    const boundaryNow = nowSeconds();
    const atSkew = await mintAat(scenario, {
      claims: { iat: boundaryNow + 60, exp: boundaryNow + 60 + 300 },
    });
    const admitted = await postInvoke(scenario, { token: atSkew });
    assertNotRejectedAsUnauthenticated(admitted);
    assertAcceptedSse(admitted);
  });

  it("S09-014 — expired beyond skew is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const now = nowSeconds();

    const expired = await mintAat(scenario, {
      claims: { iat: now - 420, exp: now - 120 },
      skipValidityWait: true,
    });
    assertUnauthenticated(await postInvoke(scenario, { token: expired }));
    await assertNoRequestWrites();

    // Wait for valid_from, then recapture now so exp = now-60 stays inside
    // the 60s skew window after mintAat's wait (lifetime 240s ≤ 600).
    await ensureInstallationKeyActive(scenario.installationId);
    const boundaryNow = nowSeconds();
    const withinSkew = await mintAat(scenario, {
      claims: { iat: boundaryNow - 300, exp: boundaryNow - 60 },
    });
    const admitted = await postInvoke(scenario, { token: withinSkew });
    assertNotRejectedAsUnauthenticated(admitted);
    assertAcceptedSse(admitted);
  });

  it("S09-015 — lifetime over 600 s is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const now = nowSeconds();

    const overCap = await mintAat(scenario, {
      claims: { iat: now, exp: now + 601 },
      skipValidityWait: true,
    });
    assertUnauthenticated(await postInvoke(scenario, { token: overCap }));
    await assertNoRequestWrites();

    await ensureInstallationKeyActive(scenario.installationId);
    const boundaryNow = nowSeconds();
    const atCap = await mintAat(scenario, {
      claims: { iat: boundaryNow, exp: boundaryNow + 600 },
    });
    const admitted = await postInvoke(scenario, { token: atCap });
    assertNotRejectedAsUnauthenticated(admitted);
    assertAcceptedSse(admitted);
  });

  it("S09-016 — unknown installation iss is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario, {
      claims: { iss: UNKNOWN_INSTALLATION_ISS },
    });
    const result = await postInvoke(scenario, { token });

    assertUnauthenticated(result);
    await assertNoRequestWrites();
  });

  it("S09-017 — unknown kid is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario, {
      kid: "no-such-key",
      signatureB64: "e30",
    });
    const result = await postInvoke(scenario, { token });

    assertUnauthenticated(result);
    await assertNoRequestWrites();
  });

  it("S09-018 — revoked key is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
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

    const token = await mintAat(scenario);
    const result = await postInvoke(scenario, { token });

    assertUnauthenticated(result);
    await assertNoRequestWrites();
  });

  it("S09-019 — key not yet valid is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario);
    const original = await queryOne<{ valid_from: string }>(
      "SELECT valid_from FROM installation_key WHERE key_id = ?",
      [scenario.kid],
    );
    expect(original?.valid_from).toEqual(expect.any(String));

    const futureFrom = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    await seedSql([
      {
        sql: "UPDATE installation_key SET valid_from = ? WHERE key_id = ?",
        params: [futureFrom, scenario.kid],
      },
    ]);
    clearConfigCache();

    try {
      const result = await postInvoke(scenario, { token });
      assertUnauthenticated(result);
      await assertNoRequestWrites();
    } finally {
      await seedSql([
        {
          sql: "UPDATE installation_key SET valid_from = ? WHERE key_id = ?",
          params: [original?.valid_from, scenario.kid],
        },
      ]);
      clearConfigCache();
    }
  });

  it("S09-020 — key past valid_until is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario);
    const original = await queryOne<{ valid_until: string | null }>(
      "SELECT valid_until FROM installation_key WHERE key_id = ?",
      [scenario.kid],
    );

    const pastUntil = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    await seedSql([
      {
        sql: "UPDATE installation_key SET valid_until = ? WHERE key_id = ?",
        params: [pastUntil, scenario.kid],
      },
    ]);
    clearConfigCache();

    try {
      const result = await postInvoke(scenario, { token });
      assertUnauthenticated(result);
      await assertNoRequestWrites();
    } finally {
      await seedSql([
        {
          sql: "UPDATE installation_key SET valid_until = ? WHERE key_id = ?",
          params: [original?.valid_until, scenario.kid],
        },
      ]);
      clearConfigCache();
    }
  });

  it("S09-021 — key bound to a different installation is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const second = await newScenario();
    const enrolled = await enrollInstallation(second);
    expect(enrolled.status).toBe(200);

    const token = await mintAat(scenario);
    const original = await queryOne<{ installation_id: string }>(
      "SELECT installation_id FROM installation_key WHERE key_id = ?",
      [scenario.kid],
    );
    expect(original?.installation_id).toBe(scenario.installationId);

    await seedSql([
      {
        sql: "UPDATE installation_key SET installation_id = ? WHERE key_id = ?",
        params: [second.installationId, scenario.kid],
      },
    ]);
    clearConfigCache();

    try {
      const result = await postInvoke(scenario, { token });
      assertUnauthenticated(result);
      await assertNoRequestWrites();
    } finally {
      await seedSql([
        {
          sql: "UPDATE installation_key SET installation_id = ? WHERE key_id = ?",
          params: [scenario.installationId, scenario.kid],
        },
      ]);
      clearConfigCache();
    }
  });

  it("S09-022 — bad Ed25519 signature is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario);
    const parts = token.split(".");
    const signature = parts[2] ?? "";
    // Catalog `${AAT%?}x` only mutates unused trailing base64url bits on a
    // 64-byte Ed25519 signature (86 chars). Also flip an earlier character
    // so decoded signature bytes change and crypto.subtle.verify fails.
    const earlier = signature.slice(0, -2);
    const penultimate = signature.slice(-2, -1);
    const flippedSig = `${earlier}${penultimate === "A" ? "B" : "A"}x`;
    const flipped = `${parts[0]}.${parts[1]}.${flippedSig}`;

    const flippedResult = await postInvoke(scenario, { token: flipped });
    assertUnauthenticated(flippedResult);

    const otherKey = await generateTestKeypair();
    const wrongKey = await mintAat(scenario, {
      keypair: otherKey,
      kid: scenario.kid,
    });
    const wrongKeyResult = await postInvoke(scenario, { token: wrongKey });
    assertUnauthenticated(wrongKeyResult);

    await assertNoRequestWrites();
  });
});
