/**
 * Suite 6 — failure taxonomy matrix (plan §4, SYS-6.1–SYS-6.16).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { VISIT_CHIEF_COMPLAINT_V1 } from "../../src/context";
import { liveHttpStatusForCode } from "../../src/errors";
import { isValidRequestReference } from "../../src/reference";
import {
  applyAllMigrations,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clearConfigCache,
  count,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollScenario,
  entitleScenario,
  fakePolicyDocument,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  getAiRequest,
  getUsageEvents,
  mintAat,
  newScenario,
  operatorFetch,
  parseSseEvents,
  POLICY_ID,
  POLICY_VERSION,
  publishPolicy,
  promote,
  registerVisitSummaryCapability,
  resetPlatformState,
  setupPromotedFakePolicy,
  type Scenario,
  type SseEvent,
  visitSummaryInvokeBody,
} from "./harness";

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
});

function base64urlEncode(data: string | Uint8Array): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

async function mintCustomAat(
  scenario: Scenario,
  opts: {
    claims?: Record<string, unknown>;
    header?: Record<string, unknown>;
    signWith?: Scenario["keypair"];
  } = {},
): Promise<string> {
  const keypair = opts.signWith ?? scenario.keypair;
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: scenario.installationId,
    aud: "ai-platform",
    sub: scenario.actorId,
    org: scenario.orgId,
    branch: scenario.branchId,
    role: "clinician",
    scopes: ["ai.visit_summary", "ai.access"],
    jti: crypto.randomUUID(),
    iat: now - 30,
    exp: now + 300,
    ver: "1",
    ...opts.claims,
  };
  const header = { alg: "EdDSA", kid: keypair.kid, ...opts.header };
  const headerB64 = base64urlEncode(JSON.stringify(header));
  const payloadB64 = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    keypair.privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64urlEncode(new Uint8Array(signature))}`;
}

async function postRequests(
  opts: {
    scenario?: Scenario;
    token?: string;
    headers?: Record<string, string>;
    body?: string | Record<string, unknown>;
    signal?: AbortSignal;
    includeDefaultHeaders?: boolean;
  } = {},
): Promise<{
  status: number;
  headers: Headers;
  json: Record<string, unknown> | null;
  text: string;
  events: SseEvent[];
}> {
  const scenario = opts.scenario ?? (await newScenario());
  const includeDefaults = opts.includeDefaultHeaders !== false;
  const headers: Record<string, string> = {
    "content-type": "application/json",
    ...opts.headers,
  };
  if (includeDefaults) {
    if (!headers["x-idempotency-key"]) {
      headers["x-idempotency-key"] = crypto.randomUUID();
    }
    if (!headers["x-capability-version"]) {
      headers["x-capability-version"] = CAPABILITY_VERSION;
    }
  }
  if (opts.token) {
    headers.authorization = `Bearer ${opts.token}`;
  }
  const body =
    opts.body === undefined
      ? JSON.stringify(visitSummaryInvokeBody(scenario))
      : typeof opts.body === "string"
        ? opts.body
        : JSON.stringify(opts.body);

  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
      method: "POST",
      headers,
      body,
      signal: opts.signal,
    }),
  );

  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("text/event-stream")) {
    const events = await parseSseEvents(response);
    await flushBackgroundWork();
    return {
      status: response.status,
      headers: response.headers,
      json: null,
      text: "",
      events,
    };
  }

  const text = await response.text();
  await flushBackgroundWork();
  return {
    status: response.status,
    headers: response.headers,
    json: text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : null,
    text,
    events: [],
  };
}

async function assertJournalUnchanged(before: number): Promise<void> {
  expect(await count("ai_request")).toBe(before);
}

function assertNotSse(headers: Headers): void {
  expect(headers.get("content-type") ?? "").not.toContain("text/event-stream");
}

function assertTaxonomyBody(
  body: Record<string, unknown> | null,
  expected: {
    code: string;
    retry_safe: boolean;
    request_reference?: "" | "non-empty";
    trace_id?: "" | "non-empty" | "echo";
    retry_after?: "present" | "absent";
    missing_keys?: "absent" | string[];
  },
  echoedTraceId?: string,
): void {
  expect(body?.code).toBe(expected.code);
  expect(body?.retry_safe).toBe(expected.retry_safe);
  if (expected.request_reference === "") {
    expect(body?.request_reference).toBe("");
  } else if (expected.request_reference === "non-empty") {
    expect(isValidRequestReference(String(body?.request_reference))).toBe(true);
  }
  if (expected.trace_id === "") {
    expect(body?.trace_id).toBe("");
  } else if (expected.trace_id === "non-empty") {
    expect(String(body?.trace_id).length).toBeGreaterThan(0);
  } else if (expected.trace_id === "echo" && echoedTraceId) {
    expect(body?.trace_id).toBe(echoedTraceId);
  }
  if (expected.retry_after === "present") {
    expect(typeof body?.retry_after).toBe("number");
    expect(Number(body?.retry_after)).toBeGreaterThan(0);
  } else if (expected.retry_after === "absent") {
    expect(body?.retry_after).toBeUndefined();
  }
  if (expected.missing_keys === "absent") {
    expect(body?.missing_keys).toBeUndefined();
  } else if (Array.isArray(expected.missing_keys)) {
    expect(body?.missing_keys).toEqual(expected.missing_keys);
  }
}

describe("failure taxonomy matrix", () => {
  it("SYS-6.1 — AAT defect variants → unauthenticated", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const before = await count("ai_request");
    const other = await newScenario();
    await enrollScenario(other);

    const variants: Array<{
      name: string;
      prepare?: () => Promise<void>;
      restore?: () => Promise<void>;
      token: () => Promise<string | undefined>;
      headers?: Record<string, string>;
    }> = [
      { name: "missing-token", token: async () => undefined },
      { name: "garbage-token", token: async () => "not-a-jwt" },
      {
        name: "expired",
        token: async () =>
          mintCustomAat(scenario, {
            claims: {
              iat: Math.floor(Date.now() / 1000) - 600,
              exp: Math.floor(Date.now() / 1000) - 120,
            },
          }),
      },
      {
        name: "aud-mismatch",
        token: async () =>
          mintCustomAat(scenario, { claims: { aud: "wrong-audience" } }),
      },
      {
        name: "ver-unknown",
        token: async () => mintCustomAat(scenario, { claims: { ver: "99" } }),
      },
      {
        name: "lifetime-over-600s",
        token: async () =>
          mintCustomAat(scenario, {
            claims: {
              iat: Math.floor(Date.now() / 1000),
              exp: Math.floor(Date.now() / 1000) + 601,
            },
          }),
      },
      {
        name: "wrong-alg",
        token: async () =>
          mintCustomAat(scenario, { header: { alg: "HS256" } }),
      },
      {
        name: "missing-org",
        token: async () =>
          mintCustomAat(scenario, {
            claims: { org: undefined },
          }),
      },
      {
        name: "unknown-kid",
        token: async () =>
          mintCustomAat(scenario, {
            header: { kid: crypto.randomUUID() },
          }),
      },
      {
        name: "unknown-installation",
        token: async () =>
          mintCustomAat(scenario, {
            claims: { iss: crypto.randomUUID() },
          }),
      },
      {
        name: "key-revoked",
        prepare: async () => {
          await env.DB.prepare(
            "UPDATE installation_key SET revoked_at = ? WHERE installation_id = ?",
          )
            .bind(new Date().toISOString(), scenario.installationId)
            .run();
          clearConfigCache();
        },
        restore: async () => {
          await env.DB.prepare(
            "UPDATE installation_key SET revoked_at = NULL WHERE installation_id = ?",
          )
            .bind(scenario.installationId)
            .run();
          clearConfigCache();
        },
        token: async () => mintAat(scenario),
      },
      {
        name: "key-expired",
        prepare: async () => {
          await env.DB.prepare(
            "UPDATE installation_key SET valid_until = '2020-01-01T00:00:00.000Z' WHERE installation_id = ?",
          )
            .bind(scenario.installationId)
            .run();
          clearConfigCache();
        },
        restore: async () => {
          const key = await env.DB.prepare(
            "SELECT valid_from FROM installation_key WHERE installation_id = ?",
          )
            .bind(scenario.installationId)
            .first<{ valid_from: string }>();
          const validUntil = new Date(
            Date.parse(String(key?.valid_from)) + 365 * 24 * 60 * 60 * 1000,
          ).toISOString();
          await env.DB.prepare(
            "UPDATE installation_key SET valid_until = ? WHERE installation_id = ?",
          )
            .bind(validUntil, scenario.installationId)
            .run();
          clearConfigCache();
        },
        token: async () => mintAat(scenario),
      },
      {
        name: "key-installation-mismatch",
        token: async () =>
          mintCustomAat(scenario, {
            claims: { iss: scenario.installationId },
            signWith: other.keypair,
            header: { kid: other.kid },
          }),
      },
    ];

    for (const variant of variants) {
      await variant.prepare?.();
      const token = await variant.token();
      const response = await postRequests({
        scenario,
        token,
        body: visitSummaryInvokeBody(scenario),
        headers: variant.headers,
      });
      expect(response.status, variant.name).toBe(
        liveHttpStatusForCode("unauthenticated"),
      );
      assertNotSse(response.headers);
      assertTaxonomyBody(response.json, {
        code: "unauthenticated",
        retry_safe: true,
        request_reference: "non-empty",
        trace_id: "non-empty",
        retry_after: "absent",
      });
      await variant.restore?.();
    }

    await assertJournalUnchanged(before);
  });

  it("SYS-6.2 — Suspended installation → installation_suspended", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const before = await count("ai_request");
    const suspended = await operatorFetch(
      `/control/installations/${scenario.installationId}/suspend`,
      {},
    );
    expect(suspended.status).toBe(200);
    clearConfigCache();

    const token = await mintAat(scenario);
    const response = await postRequests({
      scenario,
      token,
      body: visitSummaryInvokeBody(scenario),
    });
    expect(response.status).toBe(liveHttpStatusForCode("installation_suspended"));
    assertNotSse(response.headers);
    assertTaxonomyBody(response.json, {
      code: "installation_suspended",
      retry_safe: false,
      request_reference: "non-empty",
      trace_id: "non-empty",
    });
    await assertJournalUnchanged(before);
  });

  it("SYS-6.3 — Pending entitlement / plan / grants / role / scope → forbidden_capability", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);
    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    await promote(POLICY_ID, POLICY_VERSION);

    const cases: Array<{
      name: string;
      setup: () => Promise<string>;
    }> = [
      {
        name: "pending-entitlement",
        setup: async () => {
          await env.DB.prepare(
            "UPDATE entitlement SET status = 'pending' WHERE installation_id = ?",
          )
            .bind(scenario.installationId)
            .run();
          clearConfigCache();
          return mintAat(scenario);
        },
      },
      {
        name: "plan-starter",
        setup: async () => {
          await env.DB.prepare(
            "UPDATE entitlement SET plan = 'starter' WHERE installation_id = ?",
          )
            .bind(scenario.installationId)
            .run();
          clearConfigCache();
          return mintAat(scenario);
        },
      },
      {
        name: "empty-allowed-capabilities",
        setup: async () => {
          await env.DB.prepare(
            "UPDATE entitlement SET allowed_capabilities = '[]' WHERE installation_id = ?",
          )
            .bind(scenario.installationId)
            .run();
          clearConfigCache();
          return mintAat(scenario);
        },
      },
      {
        name: "doctor-role",
        setup: async () => mintAat(scenario, { role: "doctor" }),
      },
      {
        name: "missing-scope",
        setup: async () => mintAat(scenario, { scopes: ["ai.access"] }),
      },
    ];

    for (const testCase of cases) {
      const before = await count("ai_request");
      const token = await testCase.setup();
      const response = await postRequests({
        scenario,
        token,
        body: visitSummaryInvokeBody(scenario),
      });
      expect(response.status, testCase.name).toBe(
        liveHttpStatusForCode("forbidden_capability"),
      );
      assertNotSse(response.headers);
      assertTaxonomyBody(response.json, {
        code: "forbidden_capability",
        retry_safe: false,
        request_reference: "non-empty",
        trace_id: "non-empty",
      });
      await assertJournalUnchanged(before);
      await env.DB.prepare(
        "UPDATE entitlement SET status = 'active', plan = 'standard', allowed_capabilities = ? WHERE installation_id = ?",
      )
        .bind(
          JSON.stringify(DEFAULT_ENTITLE_PAYLOAD.allowed_capabilities),
          scenario.installationId,
        )
        .run();
      clearConfigCache();
    }
  });

  it("SYS-6.4 — Adapter 1 MiB gate → request_too_large empty reference", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const before = await count("ai_request");
    const token = await mintAat(scenario);

    const contentLengthOnly = await postRequests({
      scenario,
      token,
      headers: { "content-length": "1048577" },
      body: "{}",
    });
    expect(contentLengthOnly.status).toBe(
      liveHttpStatusForCode("request_too_large"),
    );
    assertNotSse(contentLengthOnly.headers);
    assertTaxonomyBody(contentLengthOnly.json, {
      code: "request_too_large",
      retry_safe: false,
      request_reference: "",
      trace_id: "",
    });

    const oversizeStream = await postRequests({
      scenario,
      token,
      body: JSON.stringify({
        capability_id: CAPABILITY_ID,
        user_intent: "x".repeat(2_000_000),
        context: {},
      }),
    });
    expect(oversizeStream.status).toBe(liveHttpStatusForCode("request_too_large"));
    assertTaxonomyBody(oversizeStream.json, {
      code: "request_too_large",
      retry_safe: false,
      request_reference: "",
      trace_id: "",
    });

    await assertJournalUnchanged(before);
  });

  it("SYS-6.5 — Malformed ingress → 422 text/plain empty body", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario);
    const baseHeaders = {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      "x-idempotency-key": crypto.randomUUID(),
      "x-capability-version": CAPABILITY_VERSION,
    };

    const bodies = ["not-json", "[]", "null", ""];
    const headerVariants: Array<Record<string, string>> = [
      { ...baseHeaders, "x-idempotency-key": "" },
      Object.fromEntries(
        Object.entries(baseHeaders).filter(([key]) => key !== "x-idempotency-key"),
      ),
      { ...baseHeaders, "x-capability-version": "" },
      Object.fromEntries(
        Object.entries(baseHeaders).filter(
          ([key]) => key !== "x-capability-version",
        ),
      ),
      { ...baseHeaders, "x-trace-id": "" },
    ];

    for (const body of bodies) {
      const before = await count("ai_request");
      const response = await SELF.fetch(
        new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
          method: "POST",
          headers: baseHeaders,
          body,
        }),
      );
      expect(response.status).toBe(422);
      expect(response.headers.get("content-type")).toContain("text/plain");
      expect(await response.text()).toBe("");
      assertNotSse(response.headers);
      await assertJournalUnchanged(before);
    }

    for (const headers of headerVariants) {
      const before = await count("ai_request");
      const response = await SELF.fetch(
        new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
          method: "POST",
          headers,
          body: JSON.stringify(visitSummaryInvokeBody(scenario)),
        }),
      );
      expect(response.status).toBe(422);
      expect(response.headers.get("content-type")).toContain("text/plain");
      expect(await response.text()).toBe("");
      await assertJournalUnchanged(before);
    }
  });

  it("SYS-6.6 — Missing capability_id → internal_error with reference", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const before = await count("ai_request");
    const token = await mintAat(scenario);
    const traceId = "01SYS6TRACE000000000001";

    const missing = await postRequests({
      scenario,
      token,
      headers: {
        "x-idempotency-key": crypto.randomUUID(),
        "x-capability-version": CAPABILITY_VERSION,
        "x-trace-id": traceId,
      },
      body: visitSummaryInvokeBody(scenario, { capability_id: undefined }),
    });
    expect(missing.status).toBe(liveHttpStatusForCode("internal_error"));
    assertNotSse(missing.headers);
    assertTaxonomyBody(missing.json, {
      code: "internal_error",
      retry_safe: true,
      request_reference: "non-empty",
      trace_id: "echo",
    }, traceId);

    const nonString = await postRequests({
      scenario,
      token,
      body: { ...visitSummaryInvokeBody(scenario), capability_id: 123 },
    });
    expect(nonString.status).toBe(liveHttpStatusForCode("internal_error"));
    await assertJournalUnchanged(before);
  });

  it("SYS-6.7 — Stage-7 preflight oversize → request_too_large with reference", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const before = await count("ai_request");
    const token = await mintAat(scenario);
    const response = await postRequests({
      scenario,
      token,
      body: visitSummaryInvokeBody(scenario, {
        user_intent: "x".repeat(50_000),
      }),
    });
    expect(response.status).toBe(liveHttpStatusForCode("request_too_large"));
    assertNotSse(response.headers);
    assertTaxonomyBody(response.json, {
      code: "request_too_large",
      retry_safe: false,
      request_reference: "non-empty",
      trace_id: "non-empty",
    });
    await assertJournalUnchanged(before);
  });

  it("SYS-6.8 — Missing required context → context_required", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const before = await count("ai_request");
    const token = await mintAat(scenario);
    const response = await postRequests({
      scenario,
      token,
      body: visitSummaryInvokeBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
        },
      }),
    });
    expect(response.status).toBe(liveHttpStatusForCode("context_required"));
    assertNotSse(response.headers);
    assertTaxonomyBody(response.json, {
      code: "context_required",
      retry_safe: true,
      request_reference: "non-empty",
      trace_id: "non-empty",
      missing_keys: [VISIT_CHIEF_COMPLAINT_V1],
    });
    await assertJournalUnchanged(before);
  });

  it("SYS-6.9 — Invalid context → context_invalid", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario);

    const cases = [
      {
        name: "wrong-org",
        body: visitSummaryInvokeBody(scenario, {
          context: {
            org: crypto.randomUUID(),
            branch: scenario.branchId,
            [VISIT_CHIEF_COMPLAINT_V1]: {
              visit_id: crypto.randomUUID(),
              complaint: "Headache.",
              recorded_at: new Date().toISOString(),
            },
          },
        }),
      },
      {
        name: "wrong-branch",
        body: visitSummaryInvokeBody(scenario, {
          context: {
            org: scenario.orgId,
            branch: crypto.randomUUID(),
            [VISIT_CHIEF_COMPLAINT_V1]: {
              visit_id: crypto.randomUUID(),
              complaint: "Headache.",
              recorded_at: new Date().toISOString(),
            },
          },
        }),
      },
      {
        name: "wrong-shape",
        body: visitSummaryInvokeBody(scenario, {
          context: {
            org: scenario.orgId,
            branch: scenario.branchId,
            [VISIT_CHIEF_COMPLAINT_V1]: "not-an-object",
          },
        }),
      },
      {
        name: "complaint-too-large",
        body: visitSummaryInvokeBody(scenario, {
          context: {
            org: scenario.orgId,
            branch: scenario.branchId,
            [VISIT_CHIEF_COMPLAINT_V1]: {
              visit_id: crypto.randomUUID(),
              complaint: "x".repeat(4097),
              recorded_at: new Date().toISOString(),
            },
          },
        }),
      },
    ];

    for (const testCase of cases) {
      const before = await count("ai_request");
      const response = await postRequests({ scenario, token, body: testCase.body });
      expect(response.status, testCase.name).toBe(
        liveHttpStatusForCode("context_invalid"),
      );
      assertNotSse(response.headers);
      assertTaxonomyBody(response.json, {
        code: "context_invalid",
        retry_safe: false,
        request_reference: "non-empty",
        trace_id: "non-empty",
      });
      await assertJournalUnchanged(before);
    }
  });

  it("SYS-6.10 — Unknown capability / version → capability_unknown", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario);

    await env.DB.prepare(
      "UPDATE entitlement SET allowed_capabilities = ? WHERE installation_id = ?",
    )
      .bind(
        JSON.stringify([CAPABILITY_ID, "clinic.does_not_exist"]),
        scenario.installationId,
      )
      .run();
    await env.DB.prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by
      ) VALUES (?, ?, ?, ?, datetime('now'), NULL, datetime('now'), 'system-test')`,
    )
      .bind(
        crypto.randomUUID(),
        `installation:${scenario.installationId}`,
        "clinic.does_not_exist",
        CAPABILITY_VERSION,
      )
      .run();
    clearConfigCache();

    const unknownId = await postRequests({
      scenario,
      token,
      body: visitSummaryInvokeBody(scenario, {
        capability_id: "clinic.does_not_exist",
      }),
    });
    expect(unknownId.status).toBe(liveHttpStatusForCode("capability_unknown"));
    assertNotSse(unknownId.headers);

    const before = await count("ai_request");
    const wrongVersion = await postRequests({
      scenario,
      token,
      headers: { "x-capability-version": "9.9.9" },
      body: visitSummaryInvokeBody(scenario),
    });
    expect(wrongVersion.status).toBe(liveHttpStatusForCode("forbidden_capability"));

    await env.DB.prepare(
      `UPDATE capability_grant
       SET capability_version = '9.9.9'
       WHERE scope = ? AND capability_id = ?`,
    )
      .bind(`installation:${scenario.installationId}`, CAPABILITY_ID)
      .run();
    clearConfigCache();
    const wrongVersionForced = await postRequests({
      scenario,
      token,
      headers: { "x-capability-version": "9.9.9" },
      body: visitSummaryInvokeBody(scenario),
    });
    expect(wrongVersionForced.status).toBe(
      liveHttpStatusForCode("capability_unknown"),
    );
    await assertJournalUnchanged(before);
  });

  it("SYS-6.11 — Global retired overlay → capability_retired", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const before = await count("ai_request");
    await env.DB.prepare(
      `INSERT INTO capability_grant (
        grant_id, scope, capability_id, capability_version,
        granted_at, revoked_at, changed_at, changed_by,
        lifecycle_state, successor_id, deprecated_at, retire_after
      ) VALUES (?, 'global', ?, ?, datetime('now'), datetime('now'), datetime('now'), 'system-test',
        'retired', ?, datetime('now'), datetime('now'))`,
    )
      .bind(
        crypto.randomUUID(),
        CAPABILITY_ID,
        CAPABILITY_VERSION,
        `${CAPABILITY_ID}@${CAPABILITY_VERSION}`,
      )
      .run();
    clearConfigCache();

    const token = await mintAat(scenario);
    const response = await postRequests({ scenario, token, body: visitSummaryInvokeBody(scenario) });
    expect(response.status).toBe(liveHttpStatusForCode("capability_retired"));
    assertNotSse(response.headers);
    assertTaxonomyBody(response.json, {
      code: "capability_retired",
      retry_safe: false,
      request_reference: "non-empty",
      trace_id: "non-empty",
    });
    await assertJournalUnchanged(before);
  });

  it("SYS-6.12 — Kill switch scopes → capability_disabled", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario);

    const scopes: Array<{ scope: string; target: string }> = [
      { scope: "global", target: "global" },
      { scope: "capability", target: CAPABILITY_ID },
      { scope: "installation", target: scenario.installationId },
    ];

    for (const kill of scopes) {
      const before = await count("ai_request");
      await env.DB.prepare(
        `INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
         VALUES (?, ?, 1, datetime('now'), 'system-test')`,
      )
        .bind(kill.scope, kill.target)
        .run();
      clearConfigCache();

      const response = await postRequests({ scenario, token, body: visitSummaryInvokeBody(scenario) });
      expect(response.status, kill.scope).toBe(
        liveHttpStatusForCode("capability_disabled"),
      );
      assertNotSse(response.headers);
      assertTaxonomyBody(response.json, {
        code: "capability_disabled",
        retry_safe: true,
        request_reference: "non-empty",
        trace_id: "non-empty",
      });
      await assertJournalUnchanged(before);

      await env.DB.prepare("DELETE FROM kill_switch WHERE changed_by = 'system-test'").run();
      clearConfigCache();
    }
  });

  it("SYS-6.13 — Empty routing chain → SSE failed provider_unavailable", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const document = fakePolicyDocument(POLICY_ID, "2", {
      ruleId: "all-excluded",
      overrides: [
        {
          installation_id: scenario.installationId,
          exclude_providers: ["fake"],
        },
      ],
    });
    await publishPolicy(POLICY_ID, "2", document);
    await promote(POLICY_ID, "2");

    const response = await postRequests({
      token: await mintAat(scenario),
      body: visitSummaryInvokeBody(scenario),
    });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/event-stream");
    expect(response.events[0]?.event).toBe("accepted");
    const failed = response.events.find((event) => event.event === "failed");
    expect(failed?.data.code).toBe("provider_unavailable");
    expect(failed?.data.retry_safe).toBe(true);

    const ref = String(response.events[0]?.data.request_reference);
    const request = await getAiRequest(ref);
    expect(request?.state).toBe("Failed");
    const usage = await getUsageEvents(String(request?.request_id));
    expect(usage).toHaveLength(1);
  });

  it("SYS-6.14 — No active routing policy → SSE failed internal_error", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);
    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    await publishPolicy(POLICY_ID, POLICY_VERSION, document);

    const response = await postRequests({
      token: await mintAat(scenario),
      body: visitSummaryInvokeBody(scenario),
    });
    expect(response.status).toBe(200);
    expect(response.events[0]?.event).toBe("accepted");
    const failed = response.events.find((event) => event.event === "failed");
    expect(failed?.data.code).toBe("internal_error");
  });

  it("SYS-6.15 — Client abort mid-stream → Cancelled with usage", async () => {
    const fakeMod = await import("../../src/provider/fake");
    let invokeEntered = false;
    const invokeSpy = vi.spyOn(fakeMod, "FakeAdapter").mockImplementation(
      () =>
        ({
          async invoke(
            _request: unknown,
            options?: { signal?: AbortSignal },
          ) {
            invokeEntered = true;
            const signal = options?.signal;
            await new Promise<void>((resolve, reject) => {
              if (signal?.aborted) {
                reject(
                  new DOMException("The operation was aborted.", "AbortError"),
                );
                return;
              }
              const timer = setTimeout(() => resolve(), 5_000);
              signal?.addEventListener(
                "abort",
                () => {
                  clearTimeout(timer);
                  reject(
                    new DOMException(
                      "The operation was aborted.",
                      "AbortError",
                    ),
                  );
                },
                { once: true },
              );
            });
            return {
              kind: "success" as const,
              result: {
                finalContent: { type: "text" as const, text: "never" },
                usage: { input: 1, output: 1, cached: 0 },
                providerModel: { provider: "fake", model: "fake-v1" },
                finishReason: "stop" as const,
                providerRequestId: "abort",
                timing: { queue_ms: 0, provider_ms: 1, total_ms: 1 },
              },
              chunks: [],
            };
          },
        }) as never,
    );

    try {
      const scenario = await newScenario();
      await setupPromotedFakePolicy(scenario);
      const controller = new AbortController();
      const token = await mintAat(scenario);
      const fetchPromise = SELF.fetch(
        new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
          method: "POST",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
            "x-idempotency-key": crypto.randomUUID(),
            "x-capability-version": CAPABILITY_VERSION,
          },
          body: JSON.stringify(visitSummaryInvokeBody(scenario)),
          signal: controller.signal,
        }),
      );
      for (let i = 0; i < 40 && !invokeEntered; i += 1) {
        await new Promise((resolve) => setTimeout(resolve, 25));
      }
      controller.abort();
      try {
        await fetchPromise;
      } catch {
        // Client abort may reject the fetch.
      }
      await flushBackgroundWork();
      await new Promise((resolve) => setTimeout(resolve, 200));

      const row = await env.DB.prepare(
        "SELECT state, terminal_error_code FROM ai_request WHERE installation_id = ? ORDER BY created_at DESC LIMIT 1",
      )
        .bind(scenario.installationId)
        .first<{ state: string; terminal_error_code: string | null }>();
      expect(row?.state).toBe("Cancelled");
      expect(row?.terminal_error_code).toBeNull();
      const usage = await getUsageEvents(
        String(
          (
            await env.DB.prepare(
              "SELECT request_id FROM ai_request WHERE installation_id = ? ORDER BY created_at DESC LIMIT 1",
            )
              .bind(scenario.installationId)
              .first<{ request_id: string }>()
          )?.request_id,
        ),
      );
      expect(usage).toHaveLength(1);
    } finally {
      invokeSpy.mockRestore();
    }
  });

  it("SYS-6.16 — Rate-limit burst → rate_limited", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const before = await count("ai_request");
    const cheapBody = JSON.stringify(
      visitSummaryInvokeBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
        },
      }),
    );

    let rateLimitedBody: Record<string, unknown> | null = null;

    for (let i = 0; i < 121; i += 1) {
      const token = await mintAat(scenario);
      const response = await SELF.fetch(
        new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
          method: "POST",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
            "x-idempotency-key": crypto.randomUUID(),
            "x-capability-version": CAPABILITY_VERSION,
          },
          body: cheapBody,
        }),
      );

      const text = await response.text();
      const json =
        text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : null;

      if (i < 120) {
        expect(response.status).toBe(liveHttpStatusForCode("context_required"));
        assertNotSse(response.headers);
        assertTaxonomyBody(json, {
          code: "context_required",
          retry_safe: true,
          request_reference: "non-empty",
          trace_id: "non-empty",
          missing_keys: [VISIT_CHIEF_COMPLAINT_V1],
        });
        continue;
      }

      expect(response.status).toBe(liveHttpStatusForCode("rate_limited"));
      rateLimitedBody = json;
    }

    expect(rateLimitedBody).not.toBeNull();
    assertTaxonomyBody(rateLimitedBody, {
      code: "rate_limited",
      retry_safe: true,
      request_reference: "non-empty",
      trace_id: "non-empty",
      retry_after: "present",
    });
    expect(rateLimitedBody?.code).not.toBe("quota_exhausted");
    await assertJournalUnchanged(before);
  });
});
