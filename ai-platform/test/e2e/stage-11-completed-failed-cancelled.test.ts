import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  assertRequestReferenceShape,
  assertSseSequence,
  assertTaxonomyBody,
  bootstrapE2e,
  CAPABILITY_VERSION,
  clinicFetch,
  count,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  fakePolicyDocument,
  fakePolicyTarget,
  flushBackgroundWork,
  gatewayObjectJson,
  getAiRequest,
  getAttempts,
  getRequestByRef,
  getR2Json,
  getRoutingPolicy,
  getUsageEvents,
  isolateConfigCache,
  mintAat,
  newScenario,
  parseSseText,
  POLICY_ID,
  POLICY_REF,
  POLICY_VERSION,
  postRequest,
  promotePolicy,
  publishPolicy,
  queryOne,
  r2Exists,
  resetE2eState,
  sseEventNames,
  visitSummaryInvokeBody,
  VISIT_CHIEF_COMPLAINT_V1,
  type EntitlePayload,
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

afterEach(() => {
  vi.restoreAllMocks();
});

const FAKE_SUMMARY = "Fake adapter summary.";
const ISO_INSTANT = /^\d{4}-\d{2}-\d{2}T/;
const CREDIT_HORIZON_MS = 7_200_000;
const PROMPT_KEYS = [
  "parts",
  "formatDirective",
  "samplingConstraints",
  "maxOutputTokens",
  "stopConditions",
  "toolDeclarations",
  "stream",
  "deadline",
  "correlationIds",
] as const;

/** Catalog period_start July 2026; period_end still contains wall-clock 2026-09-05. */
const JULY_ENTITLE: EntitlePayload = {
  ...DEFAULT_ENTITLE_PAYLOAD,
  period_start: "2026-07-01T00:00:00.000Z",
  period_end: "2027-01-01T00:00:00.000Z",
};

/**
 * Pool TTL is 100 ms. Parallel files share isolateConfigCache and call
 * clear(); preload→consult can then miss
 * `active_routing_policy:routing/standard` (ConfigCacheMissError → Failed
 * instead of the intended terminal). Raise TTL and re-stamp the
 * just-promoted D1+R2 policy immediately before every POST.
 */
const SERVE_CACHE_TTL_MS = 30_000;

async function loadServingPolicyRow(): Promise<Record<string, unknown>> {
  const row = await queryOne<Record<string, unknown>>(
    `SELECT * FROM routing_policy
     WHERE policy_id = ? AND status = 'active'
     ORDER BY active_from DESC, rowid DESC
     LIMIT 1`,
    [POLICY_ID],
  );
  expect(row).not.toBeNull();
  expect(row?.status).toBe("active");
  const pointer = String(row!.content_pointer ?? "");
  const document = await getR2Json(pointer);
  return { ...row!, document };
}

function pinServingRoutingPolicy(
  policyRow: Record<string, unknown>,
  installationIds: readonly string[],
): void {
  isolateConfigCache.setTtlMs(SERVE_CACHE_TTL_MS);
  isolateConfigCache.remember("active_routing_policy", POLICY_REF, policyRow);
  for (const installationId of installationIds) {
    isolateConfigCache.remember(
      "active_routing_policy",
      `${POLICY_REF}/${installationId}`,
      policyRow,
    );
  }
}

async function pinServingRoutingPolicyFor(scenario: Scenario): Promise<void> {
  const policyRow = await loadServingPolicyRow();
  pinServingRoutingPolicy(policyRow, [scenario.installationId]);
}

type FakeModule = typeof import("../../src/provider/fake");
type CreditModule = typeof import("../../src/credit");

type StreamChunk = {
  sequenceNumber: number;
  kind: string;
  payload: { text: string };
  terminal: boolean;
};

type InvokeOptions = {
  signal?: AbortSignal;
  onStreamChunk?: (chunk: StreamChunk) => void;
};

type QuotaInspectState = {
  periodCounters?: {
    inFlight?: number;
    requestsUsed?: number;
    tokensUsed?: number;
    costUsed?: number;
  };
  admittedRequests?: Record<string, unknown>;
  creditedRequests?: Record<string, { expiresAt?: number }>;
  idempotency?: Record<
    string,
    {
      state?: string;
      requestId?: string;
      requestReference?: string;
      expiresAt?: number;
      terminalErrorCode?: string;
    }
  >;
};

/**
 * HARNESS-GAP: FakeAdapter scripting is not on the frozen barrel; catalog §1
 * documents vi.spyOn(fakeMod, "FakeAdapter") / prototype.invoke as the seam.
 */
async function loadFakeModule(): Promise<FakeModule> {
  return import("../../src/provider/fake");
}

/**
 * HARNESS-GAP: creditUsage is not on the barrel; catalog requires partial /
 * idempotencyState / single-credit assertions on settlement.
 */
async function loadCreditModule(): Promise<CreditModule> {
  return import("../../src/credit");
}

/**
 * resolveProviderPort constructs `new FakeAdapter(...)` on every attempt
 * (worker.ts). Share script tokens across those constructions instead of
 * rebuilding a full script on each spy call.
 */
function spyFakeAdapterSequence(
  fakeMod: FakeModule,
  original: FakeModule["FakeAdapter"],
  tokens: string[],
) {
  const queue = [...tokens];
  return vi.spyOn(fakeMod, "FakeAdapter").mockImplementation(() => {
    const next = queue.shift();
    return new original((next === undefined ? [] : [next]) as never) as never;
  });
}

function visitBody(scenario: Scenario): Record<string, unknown> {
  return visitSummaryInvokeBody(scenario);
}

function policyTarget(
  modelId: string,
  overrides: Record<string, unknown> = {},
  opts: Parameters<typeof fakePolicyTarget>[1] = {},
): Record<string, unknown> {
  return { ...fakePolicyTarget(modelId, opts), ...overrides };
}

async function setupFresh(options?: {
  skipPolicy?: boolean;
  targets?: Record<string, unknown>[];
  policyVersion?: string;
  entitle?: EntitlePayload;
  overrides?: Record<string, unknown>[];
}): Promise<Scenario> {
  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  const entitled = await entitleInstallation(
    scenario,
    options?.entitle ?? JULY_ENTITLE,
  );
  expect(entitled.status).toBe(200);
  if (options?.skipPolicy) {
    return scenario;
  }

  const version = options?.policyVersion ?? POLICY_VERSION;
  if (version !== POLICY_VERSION) {
    const baseline = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    const publishedBaseline = await publishPolicy(
      POLICY_ID,
      POLICY_VERSION,
      baseline,
    );
    expect(publishedBaseline.status).toBe(200);
    const promotedBaseline = await promotePolicy(POLICY_ID, POLICY_VERSION);
    expect(promotedBaseline.status).toBe(200);
  }

  const document = fakePolicyDocument(POLICY_ID, version, {
    targets: options?.targets,
    overrides: options?.overrides?.map((row) => ({
      installation_id: scenario.installationId,
      ...row,
    })),
  });
  const published = await publishPolicy(POLICY_ID, version, document);
  expect(published.status).toBe(200);
  const promoted = await promotePolicy(POLICY_ID, version);
  expect(promoted.status).toBe(200);
  return scenario;
}

async function postVisit(
  scenario: Scenario,
  opts: { idempotencyKey: string; traceId: string },
): Promise<InvokeResult> {
  const token = await mintAat(scenario);
  await pinServingRoutingPolicyFor(scenario);
  const result = await postRequest(scenario, {
    token,
    idempotencyKey: opts.idempotencyKey,
    traceId: opts.traceId,
    body: visitBody(scenario),
  });
  await flushBackgroundWork(200);
  return result;
}

async function clinicPost(
  scenario: Scenario,
  opts: {
    idempotencyKey: string;
    traceId: string;
    signal?: AbortSignal;
  },
): Promise<Response> {
  const token = await mintAat(scenario);
  await pinServingRoutingPolicyFor(scenario);
  return clinicFetch("/v1/requests", {
    method: "POST",
    token,
    headers: {
      "x-idempotency-key": opts.idempotencyKey,
      "x-capability-version": CAPABILITY_VERSION,
      "x-trace-id": opts.traceId,
    },
    body: visitBody(scenario),
    signal: opts.signal,
  });
}

function costOf(row: Record<string, unknown> | undefined, key: string): number {
  return Number(row?.[key] ?? NaN);
}

function hangUntilAbort(
  signal: AbortSignal | undefined,
  ms: number,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(resolve, ms);
    const abort = (): void => {
      clearTimeout(timer);
      reject(Object.assign(new Error("Aborted"), { name: "AbortError" }));
    };
    if (signal?.aborted) {
      abort();
      return;
    }
    signal?.addEventListener("abort", abort, { once: true });
  });
}

async function waitFor(
  label: string,
  predicate: () => boolean,
  timeoutMs = 4000,
): Promise<void> {
  const started = Date.now();
  while (!predicate()) {
    if (Date.now() - started > timeoutMs) {
      throw new Error(`timed out waiting for ${label}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

async function waitForLatestRequestRow(
  installationId: string,
  timeoutMs = 4000,
): Promise<Record<string, unknown>> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const row = await queryOne<Record<string, unknown>>(
      `SELECT * FROM ai_request WHERE installation_id = ?
       ORDER BY created_at DESC LIMIT 1`,
      [installationId],
    );
    if (row) {
      return row;
    }
    await new Promise((resolve) => setTimeout(resolve, 15));
  }
  throw new Error("timed out waiting for ai_request row");
}

/**
 * Abort while `clinicFetch` / `SELF.fetch` is still pending (S10-013), then
 * collect whatever SSE was already buffered. Awaiting the Response before
 * abort leaves `options.signal` live; `hangUntilAbort`'s timer then resolves
 * as success.
 */
async function settleAbortedFetch(
  fetchPromise: Promise<Response>,
): Promise<{ response: Response | undefined; events: SseEvent[] }> {
  let response: Response | undefined;
  let events: SseEvent[] = [];
  try {
    response = await fetchPromise;
    if (response) {
      try {
        events = parseSseText(await response.text());
      } catch {
        // Client abort may tear the body down before it can be read.
      }
    }
  } catch {
    // Client abort may reject the fetch.
  } finally {
    await cancelResponseBody(response);
  }
  return { response, events };
}

/**
 * Abort-while-pending discards the unread SSE body. Capture bytes the
 * adapter enqueues (adapter.ts sink.push → TextEncoder.encode) so
 * regenerating / text_delta can still be asserted.
 */
function captureEnqueuedSse(): { events: () => SseEvent[]; restore: () => void } {
  let buffer = "";
  const orig = ReadableStreamDefaultController.prototype.enqueue;
  const spy = vi
    .spyOn(ReadableStreamDefaultController.prototype, "enqueue")
    .mockImplementation(function (this: ReadableStreamDefaultController, chunk) {
      if (chunk instanceof Uint8Array) {
        const text = new TextDecoder().decode(chunk);
        if (/^(?:event|data):/m.test(text)) {
          buffer += text;
        }
      }
      return orig.call(this, chunk);
    });
  return {
    events: () => parseSseText(buffer),
    restore: () => {
      spy.mockRestore();
    },
  };
}

/**
 * Read SSE frames without waiting for the stream to close. `postRequest`
 * drains via `response.text()` and cannot observe in-flight / mid-abort.
 */
async function readSseUntil(
  response: Response,
  stop: (events: SseEvent[]) => boolean,
): Promise<SseEvent[]> {
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
      if (stop(events) || done) {
        break;
      }
    }
  } finally {
    try {
      await reader.cancel();
    } catch {
      // Stream may already be torn down.
    }
  }
  return events;
}

async function cancelResponseBody(response: Response | undefined): Promise<void> {
  if (!response?.body) {
    return;
  }
  try {
    await response.body.cancel();
  } catch {
    // ignore
  }
}

/**
 * Keep reading SSE without cancelling on a stop predicate. Abort/in-flight
 * tests must not tear the body down before the invoke under test is entered;
 * `readSseUntil` cancels the reader in `finally`.
 */
function startSsePump(response: Response): {
  events: () => SseEvent[];
  close: () => Promise<void>;
} {
  expect(response.body).not.toBeNull();
  const reader = response.body!.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let events: SseEvent[] = [];
  const run = (async () => {
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (value) {
          buffer += decoder.decode(value, { stream: true });
          events = parseSseText(buffer);
        }
        if (done) {
          break;
        }
      }
    } catch {
      // Client abort / cancel.
    }
  })();
  return {
    events: () => events,
    close: async () => {
      try {
        await reader.cancel();
      } catch {
        // ignore
      }
      await run;
    },
  };
}

async function inspectState(
  installationId: string,
  now?: number,
): Promise<QuotaInspectState> {
  const result = await gatewayObjectJson(
    installationId,
    { kind: "inspect" },
    now === undefined ? {} : { now },
  );
  expect(result.status).toBe(200);
  const json = result.json as { kind?: string; state?: QuotaInspectState };
  expect(json.kind).toBe("inspect");
  return json.state ?? {};
}

function emitDelta(
  options: InvokeOptions | undefined,
  text: string,
  sequenceNumber = 0,
  terminal = true,
): void {
  options?.onStreamChunk?.({
    sequenceNumber,
    kind: "text_delta",
    payload: { text },
    terminal,
  });
}

function scriptedSuccess(
  model: string,
  usage: { input: number; output: number; cached: number },
) {
  return {
    kind: "success" as const,
    result: {
      finalContent: { type: "text" as const, text: FAKE_SUMMARY },
      usage,
      providerModel: { provider: "fake", model },
      finishReason: "stop" as const,
      providerRequestId: "fake-req-001",
      timing: { queue_ms: 1, provider_ms: 5, total_ms: 6 },
    },
    chunks: [
      {
        sequenceNumber: 0,
        kind: "text_delta" as const,
        payload: { text: FAKE_SUMMARY },
        terminal: true,
      },
    ],
    rawBody: { payload: { fake: true, outcome: "success" }, truncated: false },
  };
}

function spyFakeAdapterSuccess(
  fakeMod: FakeModule,
  original: FakeModule["FakeAdapter"],
  scripted: {
    model: string;
    usage: { input: number; output: number; cached: number };
  },
) {
  class Scripted extends original {
    override async invoke(_request: unknown, options?: InvokeOptions) {
      emitDelta(options, FAKE_SUMMARY);
      return scriptedSuccess(scripted.model, scripted.usage);
    }
  }
  return vi
    .spyOn(fakeMod, "FakeAdapter")
    .mockImplementation(() => new Scripted(["success"]) as never);
}

function assertHttpSse(result: InvokeResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
}

function assertAcceptedEvent(event: SseEvent | undefined, traceId: string): string {
  expect(event?.event).toBe("accepted");
  const ref = String(event?.data.request_reference ?? "");
  assertRequestReferenceShape(ref);
  expect(event?.data.trace_id).toBe(traceId);
  return ref;
}

function assertCompletedEvent(
  event: SseEvent | undefined,
  text: string,
  traceId?: string,
): void {
  expect(event?.event).toBe("completed");
  const resultPayload = event?.data.result as
    | { finalContent?: { text?: string; authoritative?: boolean } }
    | undefined;
  expect(resultPayload?.finalContent?.text).toBe(text);
  expect(resultPayload?.finalContent?.authoritative).toBe(true);
  if (traceId !== undefined) {
    expect(event?.data.trace_id).toBe(traceId);
  }
}

function assertFailedTerminal(
  event: SseEvent | undefined,
  opts: { code: string; retrySafe: boolean; traceId: string; requestReference: string },
): void {
  expect(event?.event).toBe("failed");
  assertTaxonomyBody(event?.data, {
    code: opts.code,
    retry_safe: opts.retrySafe,
  });
  expect(event?.data.request_reference).toBe(opts.requestReference);
  expect(event?.data.trace_id).toBe(opts.traceId);
}

function assertAcceptedFailed(
  events: SseEvent[],
  opts: { code: string; retrySafe: boolean; traceId: string },
): string {
  assertSseSequence(events, ["accepted", "failed"], "prefix");
  const ref = assertAcceptedEvent(events[0], opts.traceId);
  const failed = events.find((event) => event.event === "failed");
  assertFailedTerminal(failed, { ...opts, requestReference: ref });
  return ref;
}

async function requireAiRequest(ref: string): Promise<Record<string, unknown>> {
  const row = await getAiRequest(ref);
  expect(row).not.toBeNull();
  return row!;
}

async function waitForLatestRequestState(
  installationId: string,
  state: string,
  timeoutMs = 8000,
): Promise<Record<string, unknown>> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const row = await queryOne<Record<string, unknown>>(
      `SELECT * FROM ai_request WHERE installation_id = ?
       ORDER BY created_at DESC LIMIT 1`,
      [installationId],
    );
    if (row?.state === state) {
      return row;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`timed out waiting for ai_request state ${state}`);
}

function creditInput(spy: {
  mock: { calls: unknown[][] };
}): Record<string, unknown> {
  const first = spy.mock.calls[0]?.[0] as Record<string, unknown> | undefined;
  expect(first).toBeDefined();
  return first!;
}

function assertHorizonExpiry(expiresAt: number | undefined): void {
  const now = Date.now();
  expect(expiresAt).toBeGreaterThan(now + CREDIT_HORIZON_MS - 60_000);
  expect(expiresAt).toBeLessThanOrEqual(now + CREDIT_HORIZON_MS + 5_000);
}

describe("Stage 11 — terminal settlement completed/failed/cancelled (S11-001…S11-011)", () => {
  it("S11-001 — Completed settlement full ledger", async () => {
    const scenario = await setupFresh();
    const creditMod = await loadCreditModule();
    const creditSpy = vi.spyOn(creditMod, "creditUsage");
    const idempotencyKey = `s11-001-${crypto.randomUUID()}`;

    const result = await postVisit(scenario, {
      idempotencyKey,
      traceId: "s11-001-trace",
    });

    assertHttpSse(result);
    assertSseSequence(result.events, ["accepted", "completed"], "subsequence");
    const ref = assertAcceptedEvent(result.events[0], "s11-001-trace");
    const completed = result.events.find((event) => event.event === "completed");
    assertCompletedEvent(completed, FAKE_SUMMARY, "s11-001-trace");

    const row = await requireAiRequest(ref);
    expect(row.state).toBe("Completed");
    expect(String(row.completed_at)).toMatch(ISO_INSTANT);
    expect(row.terminal_error_code).toBeNull();
    expect(row.payload_pointer).toBe(`request/${String(row.request_id)}/envelope`);
    expect(String(row.payload_pointer)).not.toMatch(/\.json$/);
    expect(row.routing_decision).toBeTruthy();
    JSON.parse(String(row.routing_decision));
    expect(row.conversation_id).toBeNull();
    expect(row.turn_ordinal).toBeNull();

    const attempts = await getAttempts(String(row.request_id));
    expect(attempts).toHaveLength(1);
    expect(attempts[0]).toMatchObject({
      attempt_no: 1,
      provider: "fake",
      model: "fake-v1",
      outcome: "success",
      latency_ms: 6,
      tokens_in: 10,
      tokens_out: 20,
      provider_request_id: "fake-req-001",
      error_code: null,
    });
    expect(costOf(attempts[0], "cost")).toBeCloseTo(0.005, 6);

    const usage = await getUsageEvents(String(row.request_id));
    expect(usage).toHaveLength(1);
    expect(usage[0]?.installation_id).toBe(scenario.installationId);
    expect(usage[0]?.period).toBe("2026-07");
    expect(usage[0]?.request_id).toBe(row.request_id);
    expect(usage[0]?.quota_weight).toBe(1);
    expect(usage[0]?.tokens).toBe(30);
    expect(costOf(usage[0], "cost")).toBeCloseTo(0.005, 6);
    expect(String(usage[0]?.recorded_at)).toMatch(ISO_INSTANT);

    expect(await r2Exists(String(row.payload_pointer))).toBe(true);
    const envelope = await getR2Json(String(row.payload_pointer));
    expect(Object.keys(envelope).sort()).toEqual(
      ["attempts", "context", "prompt", "result"].sort(),
    );
    expect(envelope.context).toHaveProperty(VISIT_CHIEF_COMPLAINT_V1);
    const prompt = envelope.prompt as Record<string, unknown>;
    for (const key of PROMPT_KEYS) {
      expect(prompt).toHaveProperty(key);
    }
    const attemptRaw = envelope.attempts as Array<{
      payload?: { fake?: boolean; outcome?: string };
      truncated?: boolean;
    }>;
    expect(attemptRaw).toHaveLength(1);
    expect(attemptRaw[0]?.payload).toEqual({ fake: true, outcome: "success" });
    expect(attemptRaw[0]?.truncated).toBe(false);
    const envelopeResult = envelope.result as {
      finishReason?: string;
      usage?: { input?: number; output?: number; cached?: number };
    };
    expect(envelopeResult.finishReason).toBe("stop");
    expect(envelopeResult.usage).toEqual({ input: 10, output: 20, cached: 0 });

    expect(creditSpy).toHaveBeenCalledTimes(1);
    const credited = creditInput(creditSpy);
    expect(credited.partial).toBe(false);
    expect(credited.idempotencyState).toBeUndefined();
    expect(credited.entitlement).toBeTruthy();

    const inspect = await inspectState(scenario.installationId);
    expect(inspect.periodCounters?.requestsUsed).toBe(1);
    expect(inspect.periodCounters?.tokensUsed).toBe(30);
    expect(Number(inspect.periodCounters?.costUsed)).toBeCloseTo(0.005, 6);
    expect(inspect.periodCounters?.inFlight).toBe(0);
    expect(inspect.admittedRequests ?? {}).toEqual({});
    expect(inspect.creditedRequests?.[String(row.request_id)]).toBeTruthy();
    const idem = inspect.idempotency?.[idempotencyKey];
    expect(idem?.state).toBe("completed");
    assertHorizonExpiry(idem?.expiresAt);

    expect(await count("grace_admission_queue")).toBe(0);

    const got = await getRequestByRef(await mintAat(scenario), ref);
    expect(got.status).toBe(200);
    expect(got.json).toEqual({
      state: "Completed",
      result: envelope.result,
    });
  });

  it("S11-002 — Ledger cost from pricing table", async () => {
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    const cases = [
      {
        tag: "a",
        model: "deepseek-v4-flash",
        usage: { input: 1000, output: 500, cached: 0 },
        cost: 0.28,
        tokens: 1500,
      },
      {
        tag: "b",
        model: "gemini-3.5-flash",
        usage: { input: 2000, output: 100, cached: 0 },
        cost: 0.18,
        tokens: 2100,
      },
      {
        tag: "c",
        model: "unknown-model-x",
        usage: { input: 10, output: 20, cached: 0 },
        cost: 0.005,
        tokens: 30,
      },
    ] as const;

    let first = true;
    for (const testCase of cases) {
      const scenario = await setupFresh(first ? {} : { skipPolicy: true });
      first = false;
      const adapterSpy = spyFakeAdapterSuccess(fakeMod, original, {
        model: testCase.model,
        usage: testCase.usage,
      });
      try {
        const result = await postVisit(scenario, {
          idempotencyKey: `s11-002${testCase.tag}-${crypto.randomUUID()}`,
          traceId: `s11-002${testCase.tag}-trace`,
        });
        assertHttpSse(result);
        assertSseSequence(result.events, ["accepted", "completed"], "subsequence");
        const ref = assertAcceptedEvent(
          result.events[0],
          `s11-002${testCase.tag}-trace`,
        );
        const completed = result.events.find((event) => event.event === "completed");
        assertCompletedEvent(completed, FAKE_SUMMARY);

        const row = await requireAiRequest(ref);
        expect(row.state).toBe("Completed");
        const attempts = await getAttempts(String(row.request_id));
        expect(attempts).toHaveLength(1);
        expect(costOf(attempts[0], "cost")).toBeCloseTo(testCase.cost, 6);
        const usage = await getUsageEvents(String(row.request_id));
        expect(usage).toHaveLength(1);
        expect(usage[0]?.tokens).toBe(testCase.tokens);
        expect(costOf(usage[0], "cost")).toBeCloseTo(testCase.cost, 6);
        expect(costOf(attempts[0], "cost")).toBeCloseTo(
          costOf(usage[0], "cost"),
          6,
        );

        const envelope = await getR2Json(String(row.payload_pointer));
        const envelopeResult = envelope.result as {
          providerModel?: { model?: string };
        };
        expect(envelopeResult.providerModel?.model).toBe(testCase.model);

        const inspect = await inspectState(scenario.installationId);
        expect(Number(inspect.periodCounters?.costUsed)).toBeCloseTo(
          testCase.cost,
          6,
        );
        expect(inspect.periodCounters?.tokensUsed).toBe(testCase.tokens);
        expect(inspect.periodCounters?.requestsUsed).toBe(1);
      } finally {
        adapterSpy.mockRestore();
      }
    }
  });

  it("S11-003 — Empty chain provider_unavailable", async () => {
    const scenario = await setupFresh({
      policyVersion: "2",
      overrides: [{ exclude_providers: ["fake"] }],
    });
    const active = await getRoutingPolicy(POLICY_ID, "2");
    expect(active?.status).toBe("active");

      const creditMod = await loadCreditModule();
      const creditSpy = vi.spyOn(creditMod, "creditUsage");
      const idempotencyKey = `s11-003-${crypto.randomUUID()}`;

      const result = await postVisit(scenario, {
        idempotencyKey,
        traceId: "s11-003-trace",
      });

      assertHttpSse(result);
      const ref = assertAcceptedFailed(result.events, {
        code: "provider_unavailable",
        retrySafe: true,
        traceId: "s11-003-trace",
      });

      const row = await requireAiRequest(ref);
      expect(row.state).toBe("Failed");
      expect(row.completed_at).toBeTruthy();
      expect(row.terminal_error_code).toBe("provider_unavailable");

      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(1);
      expect(attempts[0]).toMatchObject({
        attempt_no: 1,
        provider: "fake",
        model: "fake-v1",
        outcome: "terminal_failure",
        latency_ms: 0,
        tokens_in: 0,
        tokens_out: 0,
        provider_request_id: null,
        error_code: "provider_unavailable",
      });
      expect(costOf(attempts[0], "cost")).toBe(0);

      const usage = await getUsageEvents(String(row.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(0);
      expect(costOf(usage[0], "cost")).toBe(0);
      expect(usage[0]?.period).toBe("2026-07");
      expect(usage[0]?.quota_weight).toBe(1);

      const envelope = await getR2Json(String(row.payload_pointer));
      const attemptRaw = envelope.attempts as Array<{
        payload?: { reason?: string; excluded?: unknown };
        truncated?: boolean;
      }>;
      expect(attemptRaw[0]?.payload?.reason).toBe("no_provider_attempt");
      expect(Array.isArray(attemptRaw[0]?.payload?.excluded)).toBe(true);
      expect(attemptRaw[0]?.truncated).toBe(false);
      const envelopeResult = envelope.result as { finishReason?: string };
      expect(envelopeResult.finishReason).toBe("provider_unavailable");

      expect(creditSpy).toHaveBeenCalledTimes(1);
      expect(creditInput(creditSpy)).toMatchObject({
        partial: true,
        idempotencyState: "failed",
        usage: { tokens: 0, cost: 0 },
      });

      const inspect = await inspectState(scenario.installationId);
      expect(inspect.periodCounters).toMatchObject({
        requestsUsed: 1,
        tokensUsed: 0,
        costUsed: 0,
        inFlight: 0,
      });
      expect(inspect.idempotency?.[idempotencyKey]?.state).toBe("failed");

      const got = await getRequestByRef(await mintAat(scenario), ref);
      expect(got.status).toBe(200);
      expect(got.json).toEqual({
        state: "Failed",
        terminal_error_code: "provider_unavailable",
      });
  });

  it("S11-004 — Timeouts settle provider_unavailable", async () => {
    const scenario = await setupFresh({
      policyVersion: "2",
      targets: [policyTarget("fake-v1", { max_attempts: 2, timeout_ms: 50 })],
    });
    const active = await getRoutingPolicy(POLICY_ID, "2");
    expect(active?.status).toBe("active");

      const fakeMod = await loadFakeModule();
      const original = fakeMod.FakeAdapter;
      class HangFake extends original {
        override async invoke(_request: unknown, options?: InvokeOptions) {
          await hangUntilAbort(options?.signal, 5000);
          return scriptedSuccess("fake-v1", { input: 10, output: 20, cached: 0 });
        }
      }
      const adapterSpy = vi
        .spyOn(fakeMod, "FakeAdapter")
        .mockImplementation(() => new HangFake(["success"]) as never);
      const creditMod = await loadCreditModule();
      const creditSpy = vi.spyOn(creditMod, "creditUsage");
      const idempotencyKey = `s11-004-${crypto.randomUUID()}`;

      try {
        const started = Date.now();
        const result = await postVisit(scenario, {
          idempotencyKey,
          traceId: "s11-004-trace",
        });
        const elapsed = Date.now() - started;

        assertHttpSse(result);
        const ref = assertAcceptedFailed(result.events, {
          code: "provider_unavailable",
          retrySafe: true,
          traceId: "s11-004-trace",
        });
        expect(elapsed).toBeGreaterThanOrEqual(100);

        const row = await requireAiRequest(ref);
        expect(row.state).toBe("Failed");
        expect(row.terminal_error_code).toBe("provider_unavailable");
        expect(row.terminal_error_code).not.toBe("timeout");

        const attempts = await getAttempts(String(row.request_id));
        expect(attempts).toHaveLength(2);
        expect(attempts[0]).toMatchObject({
          attempt_no: 1,
          outcome: "timeout",
          error_code: "timeout",
          tokens_in: 0,
          tokens_out: 0,
          latency_ms: 0,
        });
        expect(attempts[1]).toMatchObject({
          attempt_no: 2,
          outcome: "timeout",
          error_code: "timeout",
          tokens_in: 0,
          tokens_out: 0,
          latency_ms: 0,
        });
        expect(costOf(attempts[0], "cost")).toBe(0);
        expect(costOf(attempts[1], "cost")).toBe(0);

        const usage = await getUsageEvents(String(row.request_id));
        expect(usage).toHaveLength(1);
        expect(usage[0]?.tokens).toBe(0);
        expect(costOf(usage[0], "cost")).toBe(0);

        expect(creditSpy).toHaveBeenCalledTimes(1);
        expect(creditInput(creditSpy)).toMatchObject({
          partial: true,
          idempotencyState: "failed",
        });

        const envelope = await getR2Json(String(row.payload_pointer));
        const attemptRaw = envelope.attempts as unknown[];
        expect(attemptRaw).toHaveLength(2);
        expect((envelope.result as { finishReason?: string }).finishReason).toBe(
          "provider_unavailable",
        );

        const inspect = await inspectState(scenario.installationId);
        expect(inspect.idempotency?.[idempotencyKey]?.state).toBe("failed");
        expect(inspect.periodCounters?.inFlight).toBe(0);
      } finally {
        adapterSpy.mockRestore();
      }
  });

  it("S11-005 — provider_rejected consumes quota", async () => {
    const scenario = await setupFresh({
      targets: [policyTarget("fake-v1", { max_attempts: 2, timeout_ms: 30000 })],
    });
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    const adapterSpy = spyFakeAdapterSequence(fakeMod, original, [
      "retryable:rate_limited",
      "terminal:provider_rejected",
    ]);
    const creditMod = await loadCreditModule();
    const creditSpy = vi.spyOn(creditMod, "creditUsage");
    const idempotencyKey = `s11-005-${crypto.randomUUID()}`;

    try {
      const result = await postVisit(scenario, {
        idempotencyKey,
        traceId: "s11-005-trace",
      });

      assertHttpSse(result);
      const ref = assertAcceptedFailed(result.events, {
        code: "provider_rejected",
        retrySafe: false,
        traceId: "s11-005-trace",
      });

      const row = await requireAiRequest(ref);
      expect(row.state).toBe("Failed");
      expect(row.terminal_error_code).toBe("provider_rejected");

      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(2);
      expect(attempts[0]).toMatchObject({
        attempt_no: 1,
        outcome: "retryable_failure",
        error_code: "rate_limited",
        tokens_in: 0,
        tokens_out: 0,
      });
      expect(attempts[1]).toMatchObject({
        attempt_no: 2,
        outcome: "terminal_failure",
        error_code: "provider_rejected",
        tokens_in: 0,
        tokens_out: 0,
      });
      expect(costOf(attempts[0], "cost")).toBe(0);
      expect(costOf(attempts[1], "cost")).toBe(0);

      const usage = await getUsageEvents(String(row.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(0);
      expect(costOf(usage[0], "cost")).toBe(0);

      expect(creditSpy).toHaveBeenCalledTimes(1);
      expect(creditInput(creditSpy)).toMatchObject({
        partial: false,
        idempotencyState: "failed",
      });

      const inspect = await inspectState(scenario.installationId);
      expect(inspect.periodCounters).toMatchObject({
        requestsUsed: 1,
        tokensUsed: 0,
        costUsed: 0,
        inFlight: 0,
      });
      expect(inspect.idempotency?.[idempotencyKey]?.state).toBe("failed");

      const envelope = await getR2Json(String(row.payload_pointer));
      expect((envelope.result as { finishReason?: string }).finishReason).toBe(
        "provider_rejected",
      );
      const attemptRaw = envelope.attempts as Array<{
        payload?: { fake?: boolean; outcome?: string };
        truncated?: boolean;
      }>;
      expect(attemptRaw[0]).toEqual({
        payload: { fake: true, outcome: "retryable:rate_limited" },
        truncated: false,
      });
      expect(attemptRaw[1]).toEqual({
        payload: { fake: true, outcome: "terminal:provider_rejected" },
        truncated: false,
      });
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S11-006 — Truncation settles validation_failed", async () => {
    const scenario = await setupFresh({
      targets: [policyTarget("fake-v1", { max_attempts: 1 })],
    });
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    const adapterSpy = spyFakeAdapterSequence(fakeMod, original, ["truncation"]);
    const creditMod = await loadCreditModule();
    const creditSpy = vi.spyOn(creditMod, "creditUsage");
    const idempotencyKey = `s11-006-${crypto.randomUUID()}`;

    try {
      const result = await postVisit(scenario, {
        idempotencyKey,
        traceId: "s11-006-trace",
      });

      assertHttpSse(result);
      expect(sseEventNames(result.events)).toEqual([
        "accepted",
        "text_delta",
        "failed",
      ]);
      const ref = assertAcceptedEvent(result.events[0], "s11-006-trace");
      expect(result.events[1]?.data.text).toBe("Partial output…");
      expect(result.events[1]?.data.sequence).toBe(0);
      expect(result.events[1]?.data.provisional).toBe(true);
      assertFailedTerminal(result.events[2], {
        code: "validation_failed",
        retrySafe: true,
        traceId: "s11-006-trace",
        requestReference: ref,
      });
      expect(result.events.some((event) => event.event === "completed")).toBe(
        false,
      );

      const row = await requireAiRequest(ref);
      expect(row.state).toBe("Failed");
      expect(row.terminal_error_code).toBe("validation_failed");

      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(1);
      expect(attempts[0]).toMatchObject({
        outcome: "truncation",
        tokens_in: 10,
        tokens_out: 20,
        error_code: null,
      });
      expect(costOf(attempts[0], "cost")).toBeCloseTo(0.005, 6);

      const usage = await getUsageEvents(String(row.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(30);
      expect(costOf(usage[0], "cost")).toBeCloseTo(0.005, 6);

      expect(creditSpy).toHaveBeenCalledTimes(1);
      expect(creditInput(creditSpy)).toMatchObject({
        partial: false,
        idempotencyState: "failed",
      });
      expect(
        (creditInput(creditSpy).usage as { tokens?: number }).tokens,
      ).toBe(30);

      const inspect = await inspectState(scenario.installationId);
      expect(inspect.periodCounters?.tokensUsed).toBe(30);
      expect(inspect.periodCounters?.tokensUsed).not.toBe(60);
      expect(Number(inspect.periodCounters?.costUsed)).toBeCloseTo(0.005, 6);
      expect(inspect.creditedRequests?.[String(row.request_id)]).toBeTruthy();
      expect(inspect.idempotency?.[idempotencyKey]?.state).toBe("failed");

      const envelope = await getR2Json(String(row.payload_pointer));
      expect((envelope.result as { finishReason?: string }).finishReason).toBe(
        "validation_failed",
      );
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S11-007 — Empty output broker validation_failed", async () => {
    const scenario = await setupFresh();
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    class EmptyFake extends original {
      override async invoke() {
        return {
          ...scriptedSuccess("fake-v1", { input: 10, output: 20, cached: 0 }),
          result: {
            ...scriptedSuccess("fake-v1", { input: 10, output: 20, cached: 0 })
              .result,
            finalContent: { type: "text" as const, text: "" },
          },
          chunks: [],
        };
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new EmptyFake(["success"]) as never);
    const creditMod = await loadCreditModule();
    const creditSpy = vi.spyOn(creditMod, "creditUsage");
    const idempotencyKey = `s11-007-${crypto.randomUUID()}`;

    try {
      const result = await postVisit(scenario, {
        idempotencyKey,
        traceId: "s11-007-trace",
      });

      assertHttpSse(result);
      const ref = assertAcceptedFailed(result.events, {
        code: "validation_failed",
        retrySafe: true,
        traceId: "s11-007-trace",
      });
      expect(result.events.some((event) => event.event === "text_delta")).toBe(
        false,
      );
      expect(result.events.some((event) => event.event === "completed")).toBe(
        false,
      );

      const row = await requireAiRequest(ref);
      expect(row.state).toBe("Failed");
      expect(row.terminal_error_code).toBe("validation_failed");

      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(1);
      expect(attempts[0]).toMatchObject({
        outcome: "success",
        tokens_in: 10,
        tokens_out: 20,
        error_code: null,
      });
      expect(costOf(attempts[0], "cost")).toBeCloseTo(0.005, 6);

      const usage = await getUsageEvents(String(row.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(30);
      expect(costOf(usage[0], "cost")).toBeCloseTo(0.005, 6);

      expect(creditSpy).toHaveBeenCalledTimes(1);
      expect(creditInput(creditSpy)).toMatchObject({
        partial: false,
        idempotencyState: "failed",
      });

      const inspect = await inspectState(scenario.installationId);
      expect(inspect.periodCounters?.tokensUsed).toBe(30);
      expect(Number(inspect.periodCounters?.costUsed)).toBeCloseTo(0.005, 6);

      const envelope = await getR2Json(String(row.payload_pointer));
      expect((envelope.result as { finishReason?: string }).finishReason).toBe(
        "validation_failed",
      );
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S11-008 — Abort in-flight invoke cancelled", async () => {
    const scenario = await setupFresh();
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    let invokeEntered = false;
    class HangFake extends original {
      override async invoke(_request: unknown, options?: InvokeOptions) {
        invokeEntered = true;
        await hangUntilAbort(options?.signal, 5000);
        return scriptedSuccess("fake-v1", { input: 10, output: 20, cached: 0 });
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new HangFake(["success"]) as never);
    const creditMod = await loadCreditModule();
    const creditSpy = vi.spyOn(creditMod, "creditUsage");
    const idempotencyKey = `s11-008-${crypto.randomUUID()}`;
    const controller = new AbortController();
    const token = await mintAat(scenario);

    try {
      // Abort while fetch is still pending (S10-013). Awaiting the SSE
      // Response first lets hangUntilAbort's 5s timer resolve as success.
      await pinServingRoutingPolicyFor(scenario);
      const fetchPromise = clinicFetch("/v1/requests", {
        method: "POST",
        token,
        headers: {
          "x-idempotency-key": idempotencyKey,
          "x-capability-version": CAPABILITY_VERSION,
          "x-trace-id": "s11-008-trace",
        },
        body: visitBody(scenario),
        signal: controller.signal,
      });
      await waitFor("invoke entered", () => invokeEntered);
      controller.abort();
      const { events } = await settleAbortedFetch(fetchPromise);

      expect(events.some((event) => event.event === "cancelled")).toBe(false);

      await flushBackgroundWork(350);
      const row = await waitForLatestRequestState(
        scenario.installationId,
        "Cancelled",
      );
      expect(row.completed_at).toBeTruthy();
      expect(row.terminal_error_code).toBeNull();

      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(1);
      expect(attempts[0]).toMatchObject({
        outcome: "terminal_failure",
        error_code: "cancelled",
        tokens_in: 0,
        tokens_out: 0,
      });
      expect(costOf(attempts[0], "cost")).toBe(0);

      const usage = await getUsageEvents(String(row.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(0);
      expect(costOf(usage[0], "cost")).toBe(0);

      expect(creditSpy).toHaveBeenCalledTimes(1);
      expect(creditInput(creditSpy)).toMatchObject({
        partial: true,
        idempotencyState: "cancelled",
        usage: { tokens: 0, cost: 0 },
      });

      const inspect = await inspectState(scenario.installationId);
      expect(inspect.periodCounters?.inFlight).toBe(0);
      expect(inspect.idempotency?.[idempotencyKey]?.state).toBe("cancelled");

      expect(await r2Exists(String(row.payload_pointer))).toBe(true);
      const envelope = await getR2Json(String(row.payload_pointer));
      expect((envelope.result as { finishReason?: string }).finishReason).toBe(
        "cancelled",
      );
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S11-009 — Abort before first attempt", async () => {
    const scenario = await setupFresh();
    const idempotencyKey = `s11-009-${crypto.randomUUID()}`;
    const controller = new AbortController();
    // Catalog: unmodified FakeAdapter. Abort-immediately-after-dispatch cancels
    // SELF.fetch before admission. Hold after persistRoutingDecision (and do
    // not release until abort()) so the signal is set before runInvocation's
    // pre-attempt check — after ai_request exists, before recordAttempt.
    const journalMod = await import("../../src/journal");
    const originalPersist = journalMod.persistRoutingDecision;
    let releasePreAttemptHold: () => void = () => {};
    let inPreAttemptWindow = false;
    const persistSpy = vi
      .spyOn(journalMod, "persistRoutingDecision")
      .mockImplementation(async (...args: Parameters<typeof originalPersist>) => {
        await originalPersist(...args);
        inPreAttemptWindow = true;
        await new Promise<void>((resolve) => {
          releasePreAttemptHold = resolve;
        });
      });

    try {
      const token = await mintAat(scenario);
      await pinServingRoutingPolicyFor(scenario);
      const fetchPromise = clinicFetch("/v1/requests", {
        method: "POST",
        token,
        headers: {
          "x-idempotency-key": idempotencyKey,
          "x-capability-version": CAPABILITY_VERSION,
          "x-trace-id": "s11-009-trace",
        },
        body: visitBody(scenario),
        signal: controller.signal,
      });
      await waitFor("pre-attempt abort window", () => inPreAttemptWindow);
      await waitForLatestRequestRow(scenario.installationId);
      controller.abort();
      releasePreAttemptHold();
      await settleAbortedFetch(fetchPromise);

      await flushBackgroundWork(350);
      const row = await waitForLatestRequestState(
        scenario.installationId,
        "Cancelled",
      );
      expect(row.completed_at).toBeTruthy();
      expect(row.terminal_error_code).toBeNull();

      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(0);

      const usage = await getUsageEvents(String(row.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(0);
      expect(costOf(usage[0], "cost")).toBe(0);

      expect(await r2Exists(String(row.payload_pointer))).toBe(true);
      const envelope = await getR2Json(String(row.payload_pointer));
      expect(envelope.attempts).toEqual([]);
      expect((envelope.result as { finishReason?: string }).finishReason).toBe(
        "cancelled",
      );

      const inspect = await inspectState(scenario.installationId);
      expect(inspect.idempotency?.[idempotencyKey]?.state).toBe("cancelled");
      expect(inspect.periodCounters?.inFlight).toBe(0);
      expect(inspect.periodCounters?.tokensUsed).toBe(0);
    } finally {
      releasePreAttemptHold();
      persistSpy.mockRestore();
    }
  });

  it("S11-010 — Cancel after truncation fallback", async () => {
    const scenario = await setupFresh({
      policyVersion: "2",
      targets: [
        policyTarget("fake-v1", { max_attempts: 1, timeout_ms: 30000 }),
        policyTarget("fake-v1", { max_attempts: 1, timeout_ms: 30000 }),
      ],
    });
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    let constructed = 0;
    let invokeCount = 0;
    class CountingTruncation extends original {
      override async invoke(request: never, options?: InvokeOptions) {
        invokeCount += 1;
        return super.invoke(request, options);
      }
    }
    class HangFake extends original {
      override async invoke(_request: unknown, options?: InvokeOptions) {
        invokeCount += 1;
        await hangUntilAbort(options?.signal, 5000);
        return scriptedSuccess("fake-v1", { input: 10, output: 20, cached: 0 });
      }
    }
    const adapterSpy = vi.spyOn(fakeMod, "FakeAdapter").mockImplementation(() => {
      constructed += 1;
      if (constructed === 1) {
        return new CountingTruncation(["truncation"]) as never;
      }
      return new HangFake(["success"]) as never;
    });
    const creditMod = await loadCreditModule();
    const creditSpy = vi.spyOn(creditMod, "creditUsage");
    const idempotencyKey = `s11-010-${crypto.randomUUID()}`;
    const controller = new AbortController();
    const token = await mintAat(scenario);
    const sseCapture = captureEnqueuedSse();

    try {
      await pinServingRoutingPolicyFor(scenario);
      const fetchPromise = clinicFetch("/v1/requests", {
        method: "POST",
        token,
        headers: {
          "x-idempotency-key": idempotencyKey,
          "x-capability-version": CAPABILITY_VERSION,
          "x-trace-id": "s11-010-trace",
        },
        body: visitBody(scenario),
        signal: controller.signal,
      });
      await waitFor("second invoke entered", () => invokeCount >= 2);
      await waitFor("regenerating SSE enqueued", () =>
        sseCapture.events().some((event) => event.event === "regenerating"),
      );
      controller.abort();
      const settled = await settleAbortedFetch(fetchPromise);
      await flushBackgroundWork(350);
      const events =
        settled.events.length > 0 ? settled.events : sseCapture.events();

      expect(sseEventNames(events)).toContain("regenerating");
      expect(events.some((event) => event.event === "cancelled")).toBe(false);

      const row = await waitForLatestRequestState(
        scenario.installationId,
        "Cancelled",
      );
      expect(row.terminal_error_code).toBeNull();

      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(2);
      expect(attempts[0]).toMatchObject({
        outcome: "truncation",
        tokens_in: 10,
        tokens_out: 20,
        error_code: null,
      });
      expect(costOf(attempts[0], "cost")).toBeCloseTo(0.005, 6);
      expect(attempts[1]).toMatchObject({
        outcome: "terminal_failure",
        error_code: "cancelled",
        tokens_in: 0,
        tokens_out: 0,
      });
      expect(costOf(attempts[1], "cost")).toBe(0);

      const usage = await getUsageEvents(String(row.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(30);
      expect(costOf(usage[0], "cost")).toBeCloseTo(0.005, 6);

      expect(creditSpy).toHaveBeenCalledTimes(1);
      expect(creditInput(creditSpy)).toMatchObject({
        partial: true,
        idempotencyState: "cancelled",
      });
      expect(
        (creditInput(creditSpy).usage as { tokens?: number }).tokens,
      ).toBe(30);

      const inspect = await inspectState(scenario.installationId);
      expect(inspect.idempotency?.[idempotencyKey]?.state).toBe("cancelled");
      expect(inspect.periodCounters?.tokensUsed).toBe(30);
      expect(Number(inspect.periodCounters?.costUsed)).toBeCloseTo(0.005, 6);

      const envelope = await getR2Json(String(row.payload_pointer));
      expect(envelope.attempts as unknown[]).toHaveLength(2);
      expect((envelope.result as { usage?: unknown }).usage).toEqual({
        input: 30,
        output: 0,
        cached: 0,
      });
    } finally {
      sseCapture.restore();
      adapterSpy.mockRestore();
    }
  });

  it("S11-011 — Cancel prices streamed characters", async () => {
    const scenario = await setupFresh();
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    let invokeEntered = false;
    let chunkEmitted = false;
    const streamed = "x".repeat(250);
    class StreamThenHang extends original {
      override async invoke(_request: unknown, options?: InvokeOptions) {
        invokeEntered = true;
        emitDelta(options, streamed, 0, false);
        chunkEmitted = true;
        await hangUntilAbort(options?.signal, 5000);
        // Catalog: hang never returns a result. A success return settles Completed.
        await new Promise(() => {});
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new StreamThenHang(["success"]) as never);
    const creditMod = await loadCreditModule();
    const creditSpy = vi.spyOn(creditMod, "creditUsage");
    const idempotencyKey = `s11-011-${crypto.randomUUID()}`;
    const controller = new AbortController();
    const token = await mintAat(scenario);
    const sseCapture = captureEnqueuedSse();

    try {
      await pinServingRoutingPolicyFor(scenario);
      const fetchPromise = clinicFetch("/v1/requests", {
        method: "POST",
        token,
        headers: {
          "x-idempotency-key": idempotencyKey,
          "x-capability-version": CAPABILITY_VERSION,
          "x-trace-id": "s11-011-trace",
        },
        body: visitBody(scenario),
        signal: controller.signal,
      });
      await waitFor(
        "invoke entered and stream chunk",
        () => invokeEntered && chunkEmitted,
      );
      await waitFor("text_delta SSE enqueued", () =>
        sseCapture.events().some((event) => event.event === "text_delta"),
      );
      await new Promise((resolve) => setTimeout(resolve, 50));
      controller.abort();
      const settled = await settleAbortedFetch(fetchPromise);
      const events =
        settled.events.length > 0 ? settled.events : sseCapture.events();

      await flushBackgroundWork(350);

      const deltas = events.filter((event) => event.event === "text_delta");
      expect(deltas).toHaveLength(1);
      expect(deltas[0]?.data.text).toBe(streamed);
      expect(deltas[0]?.data.provisional).toBe(true);
      expect(events.some((event) => event.event === "cancelled")).toBe(false);
      expect(events.some((event) => event.event === "completed")).toBe(false);

      const row = await waitForLatestRequestState(
        scenario.installationId,
        "Cancelled",
      );

      const usage = await getUsageEvents(String(row.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(250);
      expect(costOf(usage[0], "cost")).toBeCloseTo(0.05, 6);

      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(1);
      expect(attempts[0]).toMatchObject({
        outcome: "terminal_failure",
        error_code: "cancelled",
        tokens_in: 0,
        tokens_out: 0,
      });
      expect(costOf(attempts[0], "cost")).toBe(0);

      expect(creditSpy).toHaveBeenCalledTimes(1);
      expect(creditInput(creditSpy)).toMatchObject({
        partial: true,
        idempotencyState: "cancelled",
      });
      expect(
        (creditInput(creditSpy).usage as { tokens?: number }).tokens,
      ).toBe(250);
      expect(
        Number((creditInput(creditSpy).usage as { cost?: number }).cost),
      ).toBeCloseTo(0.05, 6);

      const inspect = await inspectState(scenario.installationId);
      expect(inspect.periodCounters?.tokensUsed).toBe(250);
      expect(Number(inspect.periodCounters?.costUsed)).toBeCloseTo(0.05, 6);
      expect(inspect.idempotency?.[idempotencyKey]?.state).toBe("cancelled");
      expect(costOf(usage[0], "cost")).toBeCloseTo(
        Number(inspect.periodCounters?.costUsed),
        6,
      );
    } finally {
      sseCapture.restore();
      adapterSpy.mockRestore();
    }
  });
});
