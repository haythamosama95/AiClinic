import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertRequestReferenceShape,
  assertTaxonomyBody,
  assertUlidShape,
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clinicFetch,
  count,
  GATEWAY_ORIGIN,
  newScenario,
  postRequest,
  readHttpResult,
  resetE2eState,
  SELF,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const INGRESS_BODY_SIZE_LIMIT = 1_048_576;

function requiredHeaders(idempotencyKey: string): Record<string, string> {
  return {
    "x-idempotency-key": idempotencyKey,
    "x-capability-version": CAPABILITY_VERSION,
  };
}

function jsonObjectOfByteLength(byteLength: number): string {
  const prefix = `{"capability_id":"${CAPABILITY_ID}","pad":"`;
  const suffix = '"}';
  const padLen = byteLength - prefix.length - suffix.length;
  return `${prefix}${"x".repeat(padLen)}${suffix}`;
}

function bytesStream(bytes: Uint8Array): ReadableStream<Uint8Array> {
  return new ReadableStream({
    start(controller) {
      controller.enqueue(bytes);
      controller.close();
    },
  });
}

/**
 * POST /v1/requests with a ReadableStream body so workerd does not set
 * Content-Length from a string (Register 5 #37).
 */
async function postStreamBody(
  headers: Record<string, string>,
  bytes: Uint8Array,
): Promise<Awaited<ReturnType<typeof readHttpResult>>> {
  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
      method: "POST",
      headers,
      body: bytesStream(bytes),
      duplex: "half",
    } as RequestInit),
  );
  return readHttpResult(response);
}

function assertBare422(result: {
  status: number;
  headers: Headers;
  text: string;
}): void {
  expect(result.status).toBe(422);
  expect(result.headers.get("content-type")).toContain("text/plain");
  expect(result.text).toBe("");
  expect(result.text).toHaveLength(0);
}

function assertRequestTooLargeEmptyRef(body: unknown): void {
  assertTaxonomyBody(body, {
    code: "request_too_large",
    retry_safe: false,
  });
  expect(body.request_reference).toBe("");
  expect(body.trace_id).toBe("");
  expect(body).toEqual({
    code: "request_too_large",
    request_reference: "",
    trace_id: "",
    retry_safe: false,
  });
}

function assertUnauthenticated(body: unknown): void {
  assertTaxonomyBody(body, {
    code: "unauthenticated",
    retry_safe: true,
  });
  assertRequestReferenceShape(body.request_reference);
  assertUlidShape(body.trace_id);
  expect(body.request_reference).not.toBe("");
  expect(body.trace_id).not.toBe("");
}

describe("Stage 08 — request ingress size, JSON, and headers (S08-001…S08-020)", () => {
  it("S08-001 — Wrong HTTP method never reaches the adapter", async () => {
    const scenario = await newScenario();
    const headers = requiredHeaders(scenario.installationId);
    for (const method of ["GET", "PUT", "DELETE"] as const) {
      const response = await clinicFetch("/v1/requests", { method, headers });
      expect(response.status).toBe(404);
      expect(await response.text()).toBe("Not Found");
    }
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-002 — Trailing-slash path is not the ingress route", async () => {
    const scenario = await newScenario();
    const response = await clinicFetch("/v1/requests/", {
      method: "POST",
      headers: requiredHeaders(scenario.installationId),
      body: { capability_id: CAPABILITY_ID },
    });
    expect(response.status).toBe(404);
    expect(await response.text()).toBe("Not Found");
    expect(await count("ai_request")).toBe(0);
  });

  it.skip(
    "S08-003 — Content-Length one byte over 1 MiB (Register 5 #37: workerd may strip Content-Length on constructed Request; no in-pool seam)",
  );

  it("S08-004 — Streamed body over 1 MiB without Content-Length", async () => {
    const scenario = await newScenario();
    const bytes = new TextEncoder().encode("x".repeat(INGRESS_BODY_SIZE_LIMIT + 1));
    expect(bytes.byteLength).toBe(INGRESS_BODY_SIZE_LIMIT + 1);
    const result = await postStreamBody(
      requiredHeaders(scenario.installationId),
      bytes,
    );
    expect(result.status).toBe(413);
    expect(result.headers.get("content-type")).toContain("application/json");
    assertRequestTooLargeEmptyRef(result.json);
    expect(await count("ai_request")).toBe(0);
  });

  it.skip(
    "S08-005 — Under-declared Content-Length smuggle (Register 5 #37: workerd may strip Content-Length on constructed Request; no in-pool seam)",
  );

  it("S08-006 — Body of exactly 1,048,576 bytes is admitted", async () => {
    const scenario = await newScenario();
    const body = jsonObjectOfByteLength(INGRESS_BODY_SIZE_LIMIT);
    expect(new TextEncoder().encode(body).byteLength).toBe(
      INGRESS_BODY_SIZE_LIMIT,
    );
    const result = await postRequest(scenario, { token: null, body });
    expect(result.status).not.toBe(413);
    expect(result.status).toBe(401);
    expect(result.headers.get("content-type")).toContain("application/json");
    expect(result.events).toEqual([]);
    assertUnauthenticated(result.body);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-007 — Size gate counts UTF-8 bytes not characters", async () => {
    const scenario = await newScenario();
    const arabic = "م";
    expect(new TextEncoder().encode(arabic).byteLength).toBe(2);
    const text = arabic.repeat(524_289);
    const bytes = new TextEncoder().encode(text);
    expect(text.length).toBe(524_289);
    expect(text.length).toBeLessThan(INGRESS_BODY_SIZE_LIMIT);
    expect(bytes.byteLength).toBe(1_048_578);
    const result = await postStreamBody(
      requiredHeaders(scenario.installationId),
      bytes,
    );
    expect(result.status).toBe(413);
    expect(result.headers.get("content-type")).toContain("application/json");
    assertRequestTooLargeEmptyRef(result.json);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-008 — Oversize wins over invalid JSON and missing headers", async () => {
    const prefix = "not json";
    const text = `${prefix}${"x".repeat(INGRESS_BODY_SIZE_LIMIT + 1 - prefix.length)}`;
    const bytes = new TextEncoder().encode(text);
    expect(bytes.byteLength).toBe(INGRESS_BODY_SIZE_LIMIT + 1);
    const result = await postStreamBody({}, bytes);
    expect(result.status).toBe(413);
    expect(result.status).not.toBe(422);
    expect(result.headers.get("content-type")).toContain("application/json");
    assertRequestTooLargeEmptyRef(result.json);
    expect(await count("ai_request")).toBe(0);
  });

  it.skip(
    "S08-009 — Non-numeric Content-Length (Register 5 #37: workerd may strip Content-Length on constructed Request; no in-pool seam)",
  );

  it("S08-010 — Empty body is a bare 422", async () => {
    const scenario = await newScenario();
    // HARNESS-GAP: postRequest always sends a serialized body. Empty-body
    // ingress uses clinicFetch with no body at all.
    const response = await clinicFetch("/v1/requests", {
      method: "POST",
      headers: requiredHeaders(scenario.installationId),
    });
    const result = await readHttpResult(response);
    assertBare422(result);
    expect(result.json).toBeNull();
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-011 — Malformed JSON is a bare 422", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: "not json",
    });
    assertBare422(result);
    expect(result.body).toBeNull();
  });

  it("S08-012 — JSON array body is a bare 422", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: "[1,2,3]",
    });
    assertBare422(result);
    expect(result.body).toBeNull();
  });

  it("S08-013 — JSON null body is a bare 422", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: "null",
    });
    assertBare422(result);
    expect(result.body).toBeNull();
  });

  it("S08-014 — JSON string scalar body is a bare 422", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: '"hello"',
    });
    assertBare422(result);
    expect(result.body).toBeNull();
  });

  it("S08-015 — JSON number scalar body is a bare 422", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      body: "42",
    });
    assertBare422(result);
    expect(result.body).toBeNull();
  });

  it("S08-016 — Content-Type is never checked", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      extraHeaders: { "content-type": "text/plain" },
      body: { capability_id: CAPABILITY_ID },
    });
    expect(result.status).not.toBe(422);
    expect(result.status).not.toBe(415);
    expect(result.status).toBe(401);
    expect(result.headers.get("content-type")).toContain("application/json");
    expect(result.events).toEqual([]);
    assertUnauthenticated(result.body);
    expect(await count("ai_request")).toBe(0);
  });

  it("S08-017 — Missing x-idempotency-key is a bare 422", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      omitIdempotencyKey: true,
      body: { capability_id: CAPABILITY_ID },
    });
    assertBare422(result);
    expect(result.body).toBeNull();
  });

  it("S08-018 — Whitespace-only x-idempotency-key is a bare 422", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      extraHeaders: { "x-idempotency-key": "   " },
      body: { capability_id: CAPABILITY_ID },
    });
    assertBare422(result);
    expect(result.body).toBeNull();
  });

  it("S08-019 — Missing x-capability-version is a bare 422", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      omitCapabilityVersion: true,
      body: { capability_id: CAPABILITY_ID },
    });
    assertBare422(result);
    expect(result.body).toBeNull();
  });

  it("S08-020 — Whitespace-only x-capability-version is a bare 422", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, {
      token: null,
      extraHeaders: { "x-capability-version": "\t" },
      body: { capability_id: CAPABILITY_ID },
    });
    assertBare422(result);
    expect(result.body).toBeNull();
  });
});
