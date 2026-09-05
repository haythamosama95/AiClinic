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
  mintAat,
  newScenario,
  OPERATOR_BEARER,
  postRequest,
  provisionHappyPath,
  readHttpResult,
  resetE2eState,
  TAXONOMY_BODY_KEYS,
  ULID_PATTERN,
  visitSummaryInvokeBody,
  type InvokeResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const CLIENT_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
const PADDED_UUID_TRACE = "  550e8400-e29b-41d4-a716-446655440000  ";
const TRIMMED_UUID_TRACE = "550e8400-e29b-41d4-a716-446655440000";
const VISIT_SUMMARY_BODY = { capability_id: CAPABILITY_ID };

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
}

function assertInternalError(result: InvokeResult): void {
  expect(result.status).toBe(500);
  assertJsonTaxonomyNoSse(result);
  assertTaxonomyBody(result.body, {
    code: "internal_error",
    retry_safe: true,
  });
  assertRequestReferenceShape(String(result.body.request_reference));
  expect(result.body.request_reference).not.toBe("");
}

describe("Stage 08 — request ingress trace and auth (S08-021…S08-040)", () => {
  it("S08-021 — Present-but-empty x-trace-id is a bare 422", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: VISIT_SUMMARY_BODY,
      traceId: "   ",
    });

    assertBare422(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-022 — Both required headers missing is the same bare 422", async () => {
    const scenario = await newScenario();

    const missingBoth = await postRequest(scenario, {
      token: null,
      body: VISIT_SUMMARY_BODY,
      omitIdempotencyKey: true,
      omitCapabilityVersion: true,
    });
    assertBare422(missingBoth);

    const emptyTrace = await postRequest(scenario, {
      token: null,
      body: VISIT_SUMMARY_BODY,
      omitIdempotencyKey: true,
      omitCapabilityVersion: true,
      extraHeaders: { "x-trace-id": "" },
    });
    assertBare422(emptyTrace);

    expect(await count("ai_request")).toBe(0);
  });

  it("S08-023 — Whitespace-padded valid headers are trimmed", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: VISIT_SUMMARY_BODY,
      extraHeaders: {
        "x-idempotency-key": "  5f6a7b8c-9d0e-4f1a-2b3c-4d5e6f7a8b9c  ",
        "x-capability-version": "  1.0.0  ",
      },
    });

    expect(result.status).not.toBe(422);
    assertUnauthenticated(result);
    assertUlidShape(String(result.body?.trace_id));
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-024 — Single-char key and non-semver version pass ingress", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: VISIT_SUMMARY_BODY,
      idempotencyKey: "x",
      capabilityVersion: "not-a-published-version",
    });

    expect(result.status).not.toBe(422);
    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-025 — 512-char idempotency key passes ingress", async () => {
    const scenario = await newScenario();
    const longKey = "a1b2".repeat(128);
    expect(longKey.length).toBe(512);

    const result = await postRequest(scenario, {
      token: null,
      body: VISIT_SUMMARY_BODY,
      idempotencyKey: longKey,
      capabilityVersion: CAPABILITY_VERSION,
    });

    expect(result.status).not.toBe(422);
    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-026 — Absent x-trace-id yields a server-minted ULID", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: {},
    });

    assertInternalError(result);
    const mintedTrace = String(result.body?.trace_id);
    assertUlidShape(mintedTrace);
    expect(mintedTrace).toMatch(ULID_PATTERN);
    expect(mintedTrace).toMatch(/^[0-7][0-9A-HJKMNP-TV-Z]{25}$/);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-027 — Non-ULID supplied trace id is echoed verbatim", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: {},
      traceId: PADDED_UUID_TRACE,
    });

    assertInternalError(result);
    expect(result.body?.trace_id).toBe(TRIMMED_UUID_TRACE);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-028 — Client ULID trace id is echoed", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: {},
      traceId: CLIENT_ULID,
    });

    assertInternalError(result);
    expect(result.body?.trace_id).toBe(CLIENT_ULID);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-029 — Missing capability_id is internal_error 500", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: {},
      traceId: CLIENT_ULID,
    });

    assertInternalError(result);
    expect(result.body?.trace_id).toBe(CLIENT_ULID);
    expect(result.body?.retry_safe).toBe(true);
    expect(Object.keys(result.body ?? {}).sort()).toEqual(
      [...TAXONOMY_BODY_KEYS].sort(),
    );
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-030 — Non-string capability_id is internal_error 500", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: { capability_id: 1 },
    });

    assertInternalError(result);
    assertUlidShape(String(result.body?.trace_id));
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-031 — Empty-string capability_id is internal_error 500", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: { capability_id: "" },
    });

    assertInternalError(result);
    assertUlidShape(String(result.body?.trace_id));
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-032 — Alias capability is honored when capability_id is absent", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: { capability: CAPABILITY_ID },
    });

    expect(result.status).not.toBe(500);
    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-033 — Non-string capability_id falls through to capability alias", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: { capability_id: 1, capability: CAPABILITY_ID },
    });

    expect(result.status).not.toBe(500);
    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-034 — capability_id wins over capability when both present", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario);
    const aiRequestBefore = await count("ai_request");

    const result = await postRequest(scenario, {
      token,
      body: visitSummaryInvokeBody(scenario, {
        capability_id: "clinic.not_a_capability",
        capability: "clinic.visit_summary",
      }),
    });

    // Catalog expected 404 capability_unknown from registry stage 5. Guard
    // extracts capability_id first (alias ignored), then stage 3 entitlement
    // rejects capability_not_granted before stage 5 resolve. If the alias had
    // won, this entitled installation would reach HTTP 200 SSE.
    expect(result.status).not.toBe(200);
    expect(result.status).toBe(403);
    assertJsonTaxonomyNoSse(result);
    assertTaxonomyBody(result.body, {
      code: "forbidden_capability",
      retry_safe: false,
    });
    assertRequestReferenceShape(String(result.body.request_reference));
    expect(await count("ai_request")).toBe(aiRequestBefore);
  });

  it("S08-035 — No Authorization header fails identity as 401", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: VISIT_SUMMARY_BODY,
      traceId: "probe-anon-trace",
    });

    assertUnauthenticated(result);
    expect(result.body?.trace_id).toBe("probe-anon-trace");
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-036 — Non-JWS Bearer token is 401", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: "not-a-jws",
      body: VISIT_SUMMARY_BODY,
    });

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-037 — Basic scheme is treated as no token", async () => {
    // HARNESS-GAP: postRequest always prefixes Authorization as Bearer when a
    // token is supplied. A Basic scheme must be sent via clinicFetch.
    const response = await clinicFetch("/v1/requests", {
      method: "POST",
      headers: {
        authorization: "Basic Zm9vOmJhcg==",
        "x-idempotency-key": crypto.randomUUID(),
        "x-capability-version": CAPABILITY_VERSION,
      },
      body: VISIT_SUMMARY_BODY,
    });
    const parsed = await readHttpResult(response);
    const result: InvokeResult = {
      status: parsed.status,
      headers: parsed.headers,
      body:
        parsed.json !== null && typeof parsed.json === "object"
          ? (parsed.json as Record<string, unknown>)
          : null,
      events: [],
      text: parsed.text,
    };

    expect(result.status).not.toBe(422);
    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-038 — Bare Bearer with no token is 401", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: VISIT_SUMMARY_BODY,
      extraHeaders: { authorization: "Bearer" },
    });

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-039 — Operator bearer is not an AAT on this route", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: OPERATOR_BEARER,
      body: VISIT_SUMMARY_BODY,
    });

    assertUnauthenticated(result);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-040 — installation_suspended maps to 403 taxonomy JSON", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario);
    const suspended = await controlFetch(
      `/control/installations/${scenario.installationId}/suspend`,
      { body: {} },
    );
    expect(suspended.status).toBe(200);
    clearConfigCache();

    const aiRequestBefore = await count("ai_request");
    const result = await postRequest(scenario, {
      token,
      idempotencyKey: "6a7b8c9d-0e1f-4a2b-3c4d-5e6f7a8b9c0d",
      capabilityVersion: CAPABILITY_VERSION,
      body: visitSummaryInvokeBody(scenario),
    });

    expect(result.status).toBe(403);
    assertJsonTaxonomyNoSse(result);
    assertTaxonomyBody(result.body, {
      code: "installation_suspended",
      retry_safe: false,
    });
    assertRequestReferenceShape(String(result.body.request_reference));
    expect(result.body).not.toHaveProperty("retry_after");
    expect(await count("ai_request")).toBe(aiRequestBefore);
  });
});
