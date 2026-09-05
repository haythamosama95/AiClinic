import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertRequestReferenceShape,
  assertSseSequence,
  assertTaxonomyBody,
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clinicFetch,
  createRateLimiterDouble,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  env,
  GATEWAY_ORIGIN,
  handleAdapterRequest,
  installEnvOverrides,
  mintAat,
  newScenario,
  parseSseEvents,
  parseSseText,
  postRequest,
  provisionHappyPath,
  resetE2eState,
  SELF,
  terminalEventTypes,
  visitSummaryInvokeBody,
  VISIT_CHIEF_COMPLAINT_V1,
  type InvokeResult,
  type Scenario,
  type SseEvent,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const TRACE_ID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
const S08_044_KEY = "7b8c9d0e-1f2a-4b3c-4d5e-6f7a8b9c0d1e";
const S08_049_KEY = "8c9d0e1f-2a3b-4c5d-6e7f-8a9b0c1d2e3f";
const S08_050_KEY = "9d0e1f2a-3b4c-4d5e-6f7a-8b9c0d1e2f3a";
const S08_051_KEY = "0e1f2a3b-4c5d-4e6f-7a8b-9c0d1e2f3a4b";
const TENANT_MISMATCH_ORG = "00000000-0000-4000-8000-0000000000aa";
const UNKNOWN_CAPABILITY_ID = "clinic.not_a_capability";

async function entitledJourney(
  entitle = DEFAULT_ENTITLE_PAYLOAD,
): Promise<{ scenario: Scenario; token: string }> {
  const scenario = await provisionHappyPath(undefined, entitle);
  const token = await mintAat(scenario);
  return { scenario, token };
}

function happyVisitBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return visitSummaryInvokeBody(scenario, {
    user_intent: "Summarize today's visit for the chart.",
    ...overrides,
  });
}

function chiefComplaintContext(
  scenario: Scenario,
  complaint: string,
): Record<string, unknown> {
  return {
    org: scenario.orgId,
    branch: scenario.branchId,
    [VISIT_CHIEF_COMPLAINT_V1]: {
      visit_id: crypto.randomUUID(),
      complaint,
      recorded_at: new Date().toISOString(),
    },
  };
}

function assertJsonTaxonomy(
  result: InvokeResult,
  status: number,
  code: string,
  retrySafe: boolean,
): void {
  expect(result.status).toBe(status);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.events).toEqual([]);
  assertTaxonomyBody(result.body, { code, retry_safe: retrySafe });
  assertRequestReferenceShape(String(result.body?.request_reference));
}

function assertAcceptedSse(
  result: InvokeResult,
  opts: { traceId?: string; degradedNotice?: boolean } = {},
): SseEvent {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
  assertSseSequence(result.events, ["accepted"]);
  const accepted = result.events[0];
  expect(accepted?.event).toBe("accepted");
  assertRequestReferenceShape(String(accepted?.data.request_reference));
  if (opts.traceId !== undefined) {
    expect(accepted?.data.trace_id).toBe(opts.traceId);
  } else {
    expect(typeof accepted?.data.trace_id).toBe("string");
    expect(String(accepted?.data.trace_id).length).toBeGreaterThan(0);
  }
  if (opts.degradedNotice === true) {
    expect(accepted?.data.degraded_notice).toBe(true);
  } else {
    expect("degraded_notice" in (accepted?.data ?? {})).toBe(false);
  }
  return accepted!;
}

function requiredAdapterHeaders(
  extra: Record<string, string> = {},
): Record<string, string> {
  return {
    "content-type": "application/json",
    "x-idempotency-key": crypto.randomUUID(),
    "x-capability-version": CAPABILITY_VERSION,
    ...extra,
  };
}

function adapterContractRequest(
  body: BodyInit | Record<string, unknown> = { capability_id: CAPABILITY_ID },
  extra: { headers?: Record<string, string>; signal?: AbortSignal } = {},
): Request {
  const serialized: BodyInit =
    typeof body === "string" ||
    body instanceof ReadableStream ||
    body instanceof ArrayBuffer ||
    ArrayBuffer.isView(body)
      ? (body as BodyInit)
      : JSON.stringify(body);
  return new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
    method: "POST",
    headers: requiredAdapterHeaders(extra.headers),
    body: serialized,
    signal: extra.signal,
  });
}

/** Inject already-aborted signal after Request construction (workerd throws if passed to `new Request`). */
function requestAbortedAtEntry(request: Request): Request {
  const aborted = AbortSignal.abort();
  try {
    Object.defineProperty(request, "signal", {
      configurable: true,
      value: aborted,
    });
    if (request.signal.aborted) {
      return request;
    }
  } catch {
    // Request.signal may be a non-configurable getter.
  }
  return new Proxy(request, {
    get(target, prop) {
      if (prop === "signal") {
        return aborted;
      }
      const value = Reflect.get(target, prop, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

describe("Stage 08 — guard mapping, SSE accept, disconnect, adapter contract (S08-041…S08-060)", () => {
  it("S08-041 — forbidden_capability maps to 403", async () => {
    // Enroll inserts entitlement status `pending` (ai_disabled). Identity
    // still passes; ConfigCacheMissError 500 only happens with no entitlement
    // row. Dummy unpublished grant (Stage 07) is the fallback if that changes.
    const scenario = await newScenario();
    const enrolled = await enrollInstallation(scenario);
    expect(enrolled.status).toBe(200);
    const token = await mintAat(scenario);

    const result = await postRequest(scenario, {
      token,
      body: happyVisitBody(scenario),
    });

    assertJsonTaxonomy(result, 403, "forbidden_capability", false);
  });

  it("S08-042 — unpublished x-capability-version is 403 forbidden_capability", async () => {
    // Catalog 404 capability_unknown (stage 5). Code: stage 3 entitlement
    // rejects version mismatch as capability_not_granted before registry.
    const { scenario, token } = await entitledJourney();

    const result = await postRequest(scenario, {
      token,
      capabilityVersion: "not-a-published-version",
      body: happyVisitBody(scenario),
    });

    assertJsonTaxonomy(result, 403, "forbidden_capability", false);
  });

  it("S08-043 — unknown capability_id is 403 forbidden_capability", async () => {
    // Catalog 404 capability_unknown (stage 5). Code: stage 3 entitlement
    // rejects unknown id as capability_not_granted before registry.
    const { scenario, token } = await entitledJourney();

    const result = await postRequest(scenario, {
      token,
      body: happyVisitBody(scenario, {
        capability_id: UNKNOWN_CAPABILITY_ID,
      }),
    });

    assertJsonTaxonomy(result, 403, "forbidden_capability", false);
  });

  it("S08-044 — rate_limited maps to 429 with retry_after", async () => {
    const { scenario, token } = await entitledJourney();
    const deny = createRateLimiterDouble({
      success: false,
      retryAfter: 60,
    });
    // Guard stage 4 calls all three RATE_LIMITER_* bindings. Patch the host
    // objects the worker isolate may still hold, then swap env keys.
    const originalLimits: Array<{
      binding: RateLimit;
      limit: RateLimit["limit"];
    }> = [];
    for (const binding of [
      env.RATE_LIMITER_INSTALLATION,
      env.RATE_LIMITER_INSTALLATION_ACTOR,
      env.RATE_LIMITER_INSTALLATION_CAPABILITY,
    ]) {
      const limit = binding.limit;
      try {
        (binding as { limit: RateLimit["limit"] }).limit = (options) =>
          deny.limit(options);
        originalLimits.push({ binding, limit });
      } catch {
        // Native ratelimit host objects may freeze `limit`.
      }
    }
    // Documented seam Register 5 #31. worker.fetch ignores `_bindings` and
    // reads cloudflare:workers env. If SELF.fetch still returns 200 SSE:
    // HARNESS-GAP: RATE_LIMITER_* override never reaches limit().
    const restore = installEnvOverrides({
      RATE_LIMITER_INSTALLATION: deny,
      RATE_LIMITER_INSTALLATION_ACTOR: deny,
      RATE_LIMITER_INSTALLATION_CAPABILITY: deny,
    });
    try {
      const result = await postRequest(scenario, {
        token,
        idempotencyKey: S08_044_KEY,
        body: happyVisitBody(scenario),
      });

      assertJsonTaxonomy(result, 429, "rate_limited", true);
      expect(result.body?.retry_after).toBe(60);
    } finally {
      restore();
      for (const { binding, limit } of originalLimits) {
        try {
          (binding as { limit: RateLimit["limit"] }).limit = limit;
        } catch {
          // ignore restore failures on frozen host objects
        }
      }
    }
  });

  it("S08-045 — quota_exhausted maps to 429 without retry_after", async () => {
    const { scenario } = await entitledJourney({
      ...DEFAULT_ENTITLE_PAYLOAD,
      request_quota: 1,
    });

    const first = await postRequest(scenario, {
      token: await mintAat(scenario),
      body: happyVisitBody(scenario),
    });
    expect(first.status).toBe(200);
    assertSseSequence(first.events, ["accepted"]);

    const second = await postRequest(scenario, {
      token: await mintAat(scenario),
      body: happyVisitBody(scenario),
    });

    assertJsonTaxonomy(second, 429, "quota_exhausted", true);
    expect(second.body).not.toHaveProperty("retry_after");
    // Catalog omits period_reset; admission forwards entitlement period_end.
    expect(second.body?.period_reset).toBe(DEFAULT_ENTITLE_PAYLOAD.period_end);
  });

  it("S08-046 — omitted chief complaint is JSON context_required", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postRequest(scenario, {
      token,
      body: visitSummaryInvokeBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
        },
      }),
    });

    assertJsonTaxonomy(result, 422, "context_required", true);
  });

  it("S08-047 — tenant mismatch is 422 context_invalid", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postRequest(scenario, {
      token,
      body: happyVisitBody(scenario, {
        context: {
          org: TENANT_MISMATCH_ORG,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: {
            visit_id: crypto.randomUUID(),
            complaint: "Patient reports headache for 3 days.",
            recorded_at: new Date().toISOString(),
          },
        },
      }),
    });

    assertJsonTaxonomy(result, 422, "context_invalid", false);
  });

  it("S08-048 — 5000-char chief complaint is 422 context_invalid not 413", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postRequest(scenario, {
      token,
      body: happyVisitBody(scenario, {
        context: chiefComplaintContext(scenario, "x".repeat(5000)),
      }),
    });

    assertJsonTaxonomy(result, 422, "context_invalid", false);
    expect(result.status).not.toBe(413);
  });

  it("S08-049 — entitled happy path is HTTP 200 SSE accepted", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postRequest(scenario, {
      token,
      idempotencyKey: S08_049_KEY,
      traceId: TRACE_ID,
      body: happyVisitBody(scenario),
    });

    expect(result.status).toBe(200);
    expect(result.headers.get("content-type")).toContain("text/event-stream");
    expect(result.headers.get("cache-control")).toMatch(/no-cache/i);
    // Register 5 #40: hop-by-hop `connection` is often stripped on constructed
    // Responses in-pool. Do not require `connection: keep-alive` here.
    assertAcceptedSse(result, { traceId: TRACE_ID });
  });

  it("S08-050 — routing-injection keys are ignored on accepted", async () => {
    const { scenario, token } = await entitledJourney();
    const body = happyVisitBody(scenario, {
      capability: CAPABILITY_ID,
      routing_tier: "degraded",
      degraded: true,
      degraded_notice: true,
    });
    delete body.capability_id;

    const result = await postRequest(scenario, {
      token,
      idempotencyKey: S08_050_KEY,
      traceId: TRACE_ID,
      body,
    });

    assertAcceptedSse(result, { traceId: TRACE_ID });
  });

  it("S08-051 — soft-threshold admission sets degraded_notice on accepted", async () => {
    const { scenario } = await entitledJourney({
      ...DEFAULT_ENTITLE_PAYLOAD,
      // token_budget: 1 would hard-exhaust after FakeAdapter's ~30-token credit.
      request_quota: 5,
      token_budget: 50,
      soft_threshold: 0.01,
    });

    const warmup = await postRequest(scenario, {
      token: await mintAat(scenario),
      body: happyVisitBody(scenario),
    });
    expect(warmup.status).toBe(200);
    assertSseSequence(warmup.events, ["accepted"]);

    const result = await postRequest(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: S08_051_KEY,
      traceId: TRACE_ID,
      body: happyVisitBody(scenario),
    });

    assertAcceptedSse(result, { traceId: TRACE_ID, degradedNotice: true });
  });

  it("S08-052 — accepted references are Crockford and unique", async () => {
    const { scenario } = await entitledJourney();

    const first = await postRequest(scenario, {
      token: await mintAat(scenario),
      body: happyVisitBody(scenario),
    });
    const second = await postRequest(scenario, {
      token: await mintAat(scenario),
      body: happyVisitBody(scenario),
    });

    const refA = String(assertAcceptedSse(first).data.request_reference);
    const refB = String(assertAcceptedSse(second).data.request_reference);
    expect(refA).not.toBe(refB);
  });

  it("S08-053 — idempotent replay emits accepted then prior completed", async () => {
    const { scenario } = await entitledJourney();
    const body = happyVisitBody(scenario);

    const original = await postRequest(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: S08_049_KEY,
      traceId: TRACE_ID,
      body,
    });
    assertAcceptedSse(original, { traceId: TRACE_ID });

    const replay = await postRequest(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: S08_049_KEY,
      traceId: TRACE_ID,
      body,
    });

    expect(replay.status).toBe(200);
    assertSseSequence(replay.events, ["accepted", "completed"]);
    const accepted = replay.events[0];
    assertRequestReferenceShape(String(accepted?.data.request_reference));
    expect(accepted?.data.trace_id).toBe(TRACE_ID);
    const completed = replay.events.find((event) => event.event === "completed");
    expect(completed).toBeDefined();
    const resultPayload = completed?.data.result as
      | { finalContent?: { text?: string; authoritative?: boolean } }
      | undefined;
    expect(resultPayload?.finalContent?.text).toBe("Prior request completed.");
    // Code nests authoritative on finalContent, not the SSE data root.
    expect(resultPayload?.finalContent?.authoritative).toBe(true);
  });

  it("S08-054 — user_intent / intent alias and wrong-type fall-through reach accepted", async () => {
    const { scenario } = await entitledJourney();

    const both = await postRequest(scenario, {
      token: await mintAat(scenario),
      body: happyVisitBody(scenario, {
        user_intent: "Summarize for the chart.",
        intent: "IGNORED",
      }),
    });
    assertAcceptedSse(both);

    const aliasOnly = visitSummaryInvokeBody(scenario, {
      intent: "Summarize today.",
    });
    delete aliasOnly.user_intent;
    const onlyIntent = await postRequest(scenario, {
      token: await mintAat(scenario),
      body: aliasOnly,
    });
    assertAcceptedSse(onlyIntent);

    const wrongType = await postRequest(scenario, {
      token: await mintAat(scenario),
      body: happyVisitBody(scenario, {
        user_intent: 123,
        intent: "Summarize today.",
      }),
    });
    assertAcceptedSse(wrongType);
  });

  it("S08-055 — non-object context is JSON context_required not adapter 422", async () => {
    const { scenario, token } = await entitledJourney();
    const contexts: unknown[] = [[], "chief complaint text", null];

    for (const context of contexts) {
      const result = await postRequest(scenario, {
        token,
        body: visitSummaryInvokeBody(scenario, { context }),
      });
      assertJsonTaxonomy(result, 422, "context_required", true);
      expect(result.text).not.toBe("");
    }
  });

  it("S08-056 — disconnect after accepted closes stream without cancelled", async () => {
    const { scenario, token } = await entitledJourney();
    const controller = new AbortController();

    const response = await clinicFetch("/v1/requests", {
      method: "POST",
      token,
      headers: {
        "x-idempotency-key": crypto.randomUUID(),
        "x-capability-version": CAPABILITY_VERSION,
      },
      body: happyVisitBody(scenario),
      signal: controller.signal,
    });

    expect(response.status).toBe(200);
    expect(response.body).not.toBeNull();
    const reader = response.body!.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let events: SseEvent[] = [];
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (value) {
          buffer += decoder.decode(value, { stream: true });
          events = parseSseText(buffer);
        }
        if (events.some((event) => event.event === "accepted") || done) {
          break;
        }
      }
    } finally {
      controller.abort();
      try {
        await reader.cancel();
      } catch {
        // Abort/cancel may already have torn the stream down.
      }
    }

    // HARNESS-GAP: notifyDisconnect is not on the barrel; assert stream closed
    // and no `cancelled` frame on bytes already received (Register 5 #38).
    expect(events.some((event) => event.event === "accepted")).toBe(true);
    expect(events.some((event) => event.event === "cancelled")).toBe(false);
    await expect(reader.read()).resolves.toMatchObject({ done: true });
  });

  it("S08-057 — aborted-at-entry still emits accepted then closes", async () => {
    // workerd throws AbortError if an aborted signal is passed to `new Request`
    // or SELF.fetch. Inject after construction and drive the real adapter
    // entry, same unreachable-branch pattern as S08-058 / S08-060.
    const request = requestAbortedAtEntry(
      adapterContractRequest(
        { capability_id: CAPABILITY_ID },
        { headers: { "x-trace-id": TRACE_ID } },
      ),
    );

    let eventSourceInvoked = false;
    const response = await handleAdapterRequest(request, {
      preAccept: async () => ({ ok: true }),
      eventSource: (sink, ctx) => {
        eventSourceInvoked = true;
        sink.push({
          type: "completed",
          data: { result: {}, trace_id: ctx.traceId },
          trace_id: ctx.traceId,
        });
      },
    });

    expect(eventSourceInvoked).toBe(false);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/event-stream");
    const events = await parseSseEvents(response);
    assertSseSequence(events, ["accepted"]);
    assertRequestReferenceShape(String(events[0]?.data.request_reference));
    expect(events[0]?.data.trace_id).toBe(TRACE_ID);
    expect(events.some((event) => event.event === "cancelled")).toBe(false);
    expect(terminalEventTypes(events)).toEqual([]);
  });

  it("S08-058 — missing event source is 503 event source required", async () => {
    const response = await handleAdapterRequest(adapterContractRequest(), {
      preAccept: async () => ({ ok: true }),
    });

    expect(response.status).toBe(503);
    expect(response.headers.get("content-type")).toContain("text/plain");
    expect(await response.text()).toBe("event source required");
  });

  it("S08-059 — body stream read error is bare 422", async () => {
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode('{"a":'));
        controller.error(new Error("boom"));
      },
    });
    const request = new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
      method: "POST",
      headers: requiredAdapterHeaders(),
      body: stream,
      duplex: "half",
    } as RequestInit);

    const response = await SELF.fetch(request);

    expect(response.status).toBe(422);
    expect(response.headers.get("content-type")).toContain("text/plain");
    expect(await response.text()).toBe("");
  });

  it("S08-060 — adapter without preAccept accepts then completes", async () => {
    const response = await handleAdapterRequest(
      adapterContractRequest(
        { capability_id: CAPABILITY_ID },
        { headers: { "x-trace-id": TRACE_ID } },
      ),
      {
        eventSource: (sink, ctx) => {
          sink.push({
            type: "completed",
            data: { result: {}, trace_id: ctx.traceId },
            trace_id: ctx.traceId,
          });
        },
      },
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/event-stream");
    const events = await parseSseEvents(response);
    assertSseSequence(events, ["accepted", "completed"], "exact");
    assertRequestReferenceShape(String(events[0]?.data.request_reference));
    expect(events[0]?.data.trace_id).toBe(TRACE_ID);
    expect("degraded_notice" in (events[0]?.data ?? {})).toBe(false);
    expect(events[1]?.event).toBe("completed");
  });
});
