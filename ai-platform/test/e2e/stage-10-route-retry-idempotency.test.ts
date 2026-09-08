import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  assertRequestReferenceShape,
  assertSseSequence,
  assertTaxonomyBody,
  bootstrapE2e,
  CAPABILITY_VERSION,
  clinicFetch,
  count,
  enrollInstallation,
  entitleInstallation,
  fakePolicyDocument,
  fakePolicyTarget,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  getAiRequest,
  getAttempts,
  getR2Json,
  getRoutingPolicy,
  getUsageEvents,
  handleAdapterRequest,
  isolateConfigCache,
  mintAat,
  newScenario,
  parseSseEvents,
  parseSseText,
  POLICY_ID,
  POLICY_REF,
  POLICY_VERSION,
  postRequest,
  promotePolicy,
  provisionHappyPath,
  publishPolicy,
  queryOne,
  r2Exists,
  resetE2eState,
  terminalEventTypes,
  visitSummaryInvokeBody,
  type InvokeResult,
  type Scenario,
  type SseEvent,
} from "./harness";
import {
  assertCreditUsage,
  CANCELLED_STREAMED,
  CANCELLED_ZERO,
  COMPLETED_CREDIT,
  COMPLETED_PARTIAL_FALSE,
  FAILED_FULL_CONSUME,
  FAILED_PARTIAL,
  FAILED_PARTIAL_ZERO,
  NO_CREDIT,
  spyCreditUsage,
} from "./stage-10-credit-spy";

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
const YYYY_MM = /^\d{4}-\d{2}$/;

/**
 * Pool TTL is 100 ms. Parallel files share isolateConfigCache and call
 * clear(); preload→consult can then miss
 * `active_routing_policy:routing/standard` (ConfigCacheMissError → Failed
 * with routing_decision null). Raise TTL and re-stamp the just-promoted
 * policy immediately before POST so the post-accept consult cannot miss.
 */
const SERVE_CACHE_TTL_MS = 30_000;

async function loadServingPolicyRow(
  policyVersion?: string,
): Promise<Record<string, unknown>> {
  const row = policyVersion
    ? await getRoutingPolicy(POLICY_ID, policyVersion)
    : await queryOne(
        `SELECT * FROM routing_policy
         WHERE policy_id = ? AND status = 'active'
         ORDER BY active_from DESC, rowid DESC LIMIT 1`,
        [POLICY_ID],
      );
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

/** Pin the active serving policy immediately before a live clinic POST. */
async function pinActiveServingPolicy(installationId: string): Promise<void> {
  pinServingRoutingPolicy(await loadServingPolicyRow(), [installationId]);
}

type RoutingDecisionJson = {
  policy_id?: string;
  rule_id?: string;
  chain?: Array<{
    provider_id?: string;
    model_id?: string;
    max_attempts?: number;
    timeout_ms?: number;
  }>;
  excluded?: Array<{
    provider_id?: string;
    model_id?: string;
    reason_code?: string;
  }>;
};

type FakeModule = typeof import("../../src/provider/fake");

/**
 * HARNESS-GAP: FakeAdapter scripting is not on the frozen barrel; catalog §1
 * documents vi.spyOn(fakeMod, "FakeAdapter") / prototype.invoke as the seam.
 */
async function loadFakeModule(): Promise<FakeModule> {
  return import("../../src/provider/fake");
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
}): Promise<{ scenario: Scenario; token: string }> {
  if (!options?.skipPolicy && options?.targets === undefined) {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario);
    return { scenario, token };
  }

  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  const entitled = await entitleInstallation(scenario);
  expect(entitled.status).toBe(200);
  if (!options?.skipPolicy) {
    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION, {
      targets: options?.targets,
    });
    const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    expect(published.status).toBe(200);
    const promoted = await promotePolicy(POLICY_ID, POLICY_VERSION);
    expect(promoted.status).toBe(200);
  }
  const token = await mintAat(scenario);
  return { scenario, token };
}

async function postVisit(
  scenario: Scenario,
  token: string,
  opts: { idempotencyKey: string; traceId: string; pinPolicy?: boolean },
): Promise<InvokeResult> {
  if (opts.pinPolicy !== false) {
    await pinActiveServingPolicy(scenario.installationId);
  }
  const result = await postRequest(scenario, {
    token,
    idempotencyKey: opts.idempotencyKey,
    traceId: opts.traceId,
    body: visitBody(scenario),
  });
  await flushBackgroundWork(200);
  return result;
}

function jwtPayload(token: string): Record<string, unknown> {
  const segment = token.split(".")[1] ?? "";
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/");
  const pad = "=".repeat((4 - (padded.length % 4)) % 4);
  return JSON.parse(atob(padded + pad)) as Record<string, unknown>;
}

function parseDecision(raw: unknown): RoutingDecisionJson {
  if (typeof raw !== "string" || raw.length === 0) {
    return {};
  }
  return JSON.parse(raw) as RoutingDecisionJson;
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

/**
 * Read SSE frames without waiting for the stream to close. `postRequest`
 * drains via `response.text()` and cannot observe in-flight / mid-abort.
 * Pass `drainAfterStopMs` so a later fabricated terminal cannot hide
 * behind the first `accepted` chunk on an admitted replay.
 */
async function readSseUntil(
  response: Response,
  stop: (events: SseEvent[]) => boolean,
  options: { drainAfterStopMs?: number } = {},
): Promise<SseEvent[]> {
  expect(response.body).not.toBeNull();
  const reader = response.body!.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let events: SseEvent[] = [];
  let stoppedAt: number | undefined;
  const drainMs = options.drainAfterStopMs;
  try {
    while (true) {
      const drainRemaining =
        stoppedAt !== undefined && drainMs !== undefined
          ? drainMs - (Date.now() - stoppedAt)
          : undefined;
      if (drainRemaining !== undefined && drainRemaining <= 0) {
        break;
      }
      const { done, value } =
        drainRemaining === undefined
          ? await reader.read()
          : await readChunkWithTimeout(reader, drainRemaining);
      if (value) {
        buffer += decoder.decode(value, { stream: true });
        events = parseSseText(buffer);
      }
      if (stoppedAt === undefined && stop(events)) {
        stoppedAt = Date.now();
        if (drainMs === undefined) {
          break;
        }
      }
      if (done) {
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

async function readChunkWithTimeout(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  ms: number,
): Promise<ReadableStreamReadResult<Uint8Array>> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const timeout = new Promise<ReadableStreamReadResult<Uint8Array>>(
      (resolve) => {
        timer = setTimeout(() => resolve({ done: true, value: undefined }), ms);
      },
    );
    return await Promise.race([reader.read(), timeout]);
  } finally {
    if (timer !== undefined) {
      clearTimeout(timer);
    }
  }
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

function assertHttpSse(result: InvokeResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
}

function assertAcceptedEvent(event: SseEvent | undefined, traceId: string): string {
  expect(event?.event).toBe("accepted");
  const ref = String(event?.data.request_reference ?? "");
  assertRequestReferenceShape(ref);
  expect(event?.data.trace_id).toBe(traceId);
  expect("degraded_notice" in (event?.data ?? {})).toBe(false);
  return ref;
}

function assertTextDeltaEvent(event: SseEvent | undefined, text: string): void {
  expect(event?.event).toBe("text_delta");
  expect(event?.data.text).toBe(text);
  expect(event?.data.sequence).toBe(0);
  expect(event?.data.provisional).toBe(true);
  expect("trace_id" in (event?.data ?? {})).toBe(false);
}

function assertCompletedEvent(
  event: SseEvent | undefined,
  text: string,
  traceId: string,
): void {
  expect(event?.event).toBe("completed");
  const resultPayload = event?.data.result as
    | { finalContent?: { text?: string; authoritative?: boolean } }
    | undefined;
  expect(resultPayload?.finalContent?.text).toBe(text);
  expect(resultPayload?.finalContent?.authoritative).toBe(true);
  expect(event?.data.trace_id).toBe(traceId);
}

function assertHappyPathEvents(events: SseEvent[], traceId: string): string {
  assertSseSequence(events, ["accepted", "text_delta", "completed"], "exact");
  const ref = assertAcceptedEvent(events[0], traceId);
  assertTextDeltaEvent(events[1], FAKE_SUMMARY);
  assertCompletedEvent(events[2], FAKE_SUMMARY, traceId);
  expect(events.some((event) => event.event === "heartbeat")).toBe(false);
  expect(events.some((event) => event.event === "regenerating")).toBe(false);
  return ref;
}

function assertFailedEvents(
  events: SseEvent[],
  opts: { code: string; retrySafe: boolean; traceId: string },
): string {
  assertSseSequence(events, ["accepted", "failed"], "exact");
  const ref = assertAcceptedEvent(events[0], opts.traceId);
  const failed = events[1];
  expect(failed?.event).toBe("failed");
  assertTaxonomyBody(failed?.data, {
    code: opts.code,
    retry_safe: opts.retrySafe,
  });
  expect(failed?.data.request_reference).toBe(ref);
  expect(failed?.data.trace_id).toBe(opts.traceId);
  expect(events.some((event) => event.event === "text_delta")).toBe(false);
  return ref;
}

async function requireAiRequest(ref: string): Promise<Record<string, unknown>> {
  const row = await getAiRequest(ref);
  expect(row).not.toBeNull();
  return row!;
}

describe("Stage 10 — accept, route, invoke, stream (S10-001…S10-017)", () => {
  it("S10-001 — single-target chain success settles completed", async () => {
    const { scenario, token } = await setupFresh();
    const jti = String(jwtPayload(token).jti ?? "");
    const creditSpy = await spyCreditUsage();

    const result = await postVisit(scenario, token, {
      idempotencyKey: "s10-001-idem",
      traceId: "s10-001-trace",
    });

    assertHttpSse(result);
    const ref = assertHappyPathEvents(result.events, "s10-001-trace");

    const row = await requireAiRequest(ref);
    expect(row.state).toBe("Completed");
    expect(row.completed_at).toBeTruthy();
    expect(row.terminal_error_code).toBeNull();
    expect(row.routing_tier).toBe("standard");
    expect(row.payload_pointer).toBe(`request/${String(row.request_id)}/envelope`);

    const decision = parseDecision(row.routing_decision);
    expect(decision.policy_id).toBe("standard");
    expect(decision.rule_id).toBe("catch-all");
    expect(decision.chain).toHaveLength(1);
    expect(decision.excluded).toEqual([]);
    expect("max_parallel_attempts" in decision).toBe(false);

    const attempts = await getAttempts(String(row.request_id));
    expect(attempts).toHaveLength(1);
    expect(attempts[0]?.attempt_no).toBe(1);
    expect(attempts[0]?.provider).toBe("fake");
    expect(attempts[0]?.model).toBe("fake-v1");
    expect(attempts[0]?.outcome).toBe("success");
    expect(attempts[0]?.tokens_in).toBe(10);
    expect(attempts[0]?.tokens_out).toBe(20);
    expect(costOf(attempts[0], "cost")).toBeCloseTo(0.005, 5);
    expect(attempts[0]?.provider_request_id).toBe("fake-req-001");
    expect(attempts[0]?.error_code).toBeNull();

    const usage = await getUsageEvents(String(row.request_id));
    expect(usage).toHaveLength(1);
    expect(usage[0]?.tokens).toBe(30);
    expect(costOf(usage[0], "cost")).toBeCloseTo(0.005, 5);
    expect(usage[0]?.quota_weight).toBe(1);
    expect(String(usage[0]?.period)).toMatch(YYYY_MM);

    expect(await r2Exists(String(row.payload_pointer))).toBe(true);
    const envelope = await getR2Json(String(row.payload_pointer));
    const prompt = envelope.prompt as {
      stream?: boolean;
      deadline?: unknown;
      correlationIds?: { trace_id?: string };
    };
    expect(prompt.stream).toBe(true);
    expect(prompt.deadline).toBeNull();
    expect(prompt.correlationIds?.trace_id).toBe(jti);
    expect(prompt.correlationIds?.trace_id).not.toBe("s10-001-trace");
    const attemptPayload = envelope.attempts as Array<{
      payload?: { fake?: boolean; outcome?: string };
      truncated?: boolean;
    }>;
    expect(attemptPayload[0]?.payload).toEqual({ fake: true, outcome: "success" });
    expect(attemptPayload[0]?.truncated).toBe(false);
    assertCreditUsage(creditSpy, COMPLETED_CREDIT);
  });

  it("S10-002 — routing decision is persisted before provider I/O", async () => {
    const { scenario, token } = await setupFresh();
    const fakeMod = await loadFakeModule();
    const originalInvoke = fakeMod.FakeAdapter.prototype.invoke;
    let decisionAtInvoke: RoutingDecisionJson | null = null;
    const invokeSpy = vi
      .spyOn(fakeMod.FakeAdapter.prototype, "invoke")
      .mockImplementation(async function (this: unknown, ...args: never[]) {
        const request = args[0] as {
          correlationIds?: { request_reference?: string };
        };
        const ref = request?.correlationIds?.request_reference;
        const row = ref
          ? await queryOne<{ routing_decision: string | null }>(
              "SELECT routing_decision FROM ai_request WHERE request_reference = ?",
              [ref],
            )
          : await queryOne<{ routing_decision: string | null }>(
              `SELECT routing_decision FROM ai_request
               WHERE installation_id = ? AND state = 'Accepted'
               ORDER BY created_at DESC LIMIT 1`,
              [scenario.installationId],
            );
        decisionAtInvoke = parseDecision(row?.routing_decision);
        return originalInvoke.apply(this, args);
      });

    try {
      const result = await postVisit(scenario, token, {
        idempotencyKey: "s10-002-idem",
        traceId: "s10-002-trace",
      });

      expect(invokeSpy).toHaveBeenCalled();
      expect(decisionAtInvoke).not.toBeNull();
      expect(decisionAtInvoke?.chain?.[0]).toMatchObject({
        provider_id: "fake",
        model_id: "fake-v1",
        max_attempts: 1,
        timeout_ms: 30000,
      });
      expect(decisionAtInvoke?.excluded).toEqual([]);
      expect(decisionAtInvoke && "max_parallel_attempts" in decisionAtInvoke).toBe(
        false,
      );

      assertHttpSse(result);
      assertHappyPathEvents(result.events, "s10-002-trace");
    } finally {
      invokeSpy.mockRestore();
    }
  });

  it("S10-003 — missing routing policy after accepted fails internal_error", async () => {
    const { scenario, token } = await setupFresh({ skipPolicy: true });
    const creditSpy = await spyCreditUsage();

    // Catalog: no serving policy. Do not pin — the post-accept consult
    // must miss `active_routing_policy:routing/standard`.
    const result = await postVisit(scenario, token, {
      idempotencyKey: "s10-003-idem",
      traceId: "s10-003-trace",
      pinPolicy: false,
    });

    assertHttpSse(result);
    const ref = assertFailedEvents(result.events, {
      code: "internal_error",
      retrySafe: true,
      traceId: "s10-003-trace",
    });

    const row = await requireAiRequest(ref);
    expect(row.state).toBe("Failed");
    expect(row.terminal_error_code).toBe("internal_error");

    const attempts = await getAttempts(String(row.request_id));
    expect(attempts).toHaveLength(1);
    expect(attempts[0]?.attempt_no).toBe(1);
    expect(attempts[0]?.outcome).toBe("terminal_failure");
    expect(attempts[0]?.error_code).toBe("internal_error");

    const usage = await getUsageEvents(String(row.request_id));
    expect(usage).toHaveLength(1);

    expect(row.payload_pointer).toBeTruthy();
    expect(await r2Exists(String(row.payload_pointer))).toBe(true);
    const envelope = await getR2Json(String(row.payload_pointer));
    const attemptRaw = envelope.attempts as Array<{
      payload?: { reason?: string };
      truncated?: boolean;
    }>;
    expect(attemptRaw[0]?.payload?.reason).toBe("no_provider_attempt");
    expect(attemptRaw[0]?.truncated).toBe(false);
    assertCreditUsage(creditSpy, FAILED_PARTIAL_ZERO);
  });

  it("S10-004 — empty candidate chain fails provider_unavailable", async () => {
    const { scenario, token } = await setupFresh({
      targets: [policyTarget("fake-v1", {}, { minContextWindow: 1000 })],
    });
    const creditSpy = await spyCreditUsage();

    const result = await postVisit(scenario, token, {
      idempotencyKey: "s10-004-idem",
      traceId: "s10-004-trace",
    });

    assertHttpSse(result);
    const ref = assertFailedEvents(result.events, {
      code: "provider_unavailable",
      retrySafe: true,
      traceId: "s10-004-trace",
    });

    const row = await requireAiRequest(ref);
    expect(row.state).toBe("Failed");
    expect(row.terminal_error_code).toBe("provider_unavailable");
    const decision = parseDecision(row.routing_decision);
    expect(decision.chain).toEqual([]);
    expect(decision.excluded).toEqual([
      {
        provider_id: "fake",
        model_id: "fake-v1",
        reason_code: "context_window_too_small",
      },
    ]);

    const attempts = await getAttempts(String(row.request_id));
    expect(attempts).toHaveLength(1);
    expect(attempts[0]?.attempt_no).toBe(1);
    expect(attempts[0]?.provider).toBe("fake");
    expect(attempts[0]?.model).toBe("fake-v1");
    expect(attempts[0]?.outcome).toBe("terminal_failure");
    expect(attempts[0]?.error_code).toBe("provider_unavailable");
    expect(attempts[0]?.latency_ms).toBe(0);
    expect(attempts[0]?.tokens_in).toBe(0);
    expect(attempts[0]?.tokens_out).toBe(0);
    expect(costOf(attempts[0], "cost")).toBe(0);

    const usage = await getUsageEvents(String(row.request_id));
    expect(usage).toHaveLength(1);
    expect(usage[0]?.tokens).toBe(0);

    expect(await r2Exists(String(row.payload_pointer))).toBe(true);
    const envelope = await getR2Json(String(row.payload_pointer));
    const attemptRaw = envelope.attempts as Array<{
      payload?: { reason?: string; excluded?: unknown };
      truncated?: boolean;
    }>;
    expect(attemptRaw[0]?.payload?.reason).toBe("no_provider_attempt");
    expect(attemptRaw[0]?.payload?.excluded).toEqual(decision.excluded);
    expect(attemptRaw[0]?.truncated).toBe(false);
    assertCreditUsage(creditSpy, FAILED_PARTIAL_ZERO);
  });

  it("S10-005 — unknown provider_id retries then exhausts", async () => {
    const { scenario, token } = await setupFresh({
      targets: [
        policyTarget(
          "bogus-v1",
          { max_attempts: 2 },
          { providerId: "bogus-primary" },
        ),
      ],
    });

    const creditSpy = await spyCreditUsage();
    const started = Date.now();
    const result = await postVisit(scenario, token, {
      idempotencyKey: "s10-005-idem",
      traceId: "s10-005-trace",
    });
    const elapsed = Date.now() - started;

    assertHttpSse(result);
    const ref = assertFailedEvents(result.events, {
      code: "provider_unavailable",
      retrySafe: true,
      traceId: "s10-005-trace",
    });
    expect(elapsed).toBeGreaterThanOrEqual(100);

    const row = await requireAiRequest(ref);
    expect(row.state).toBe("Failed");
    expect(row.terminal_error_code).toBe("provider_unavailable");

    const attempts = await getAttempts(String(row.request_id));
    expect(attempts).toHaveLength(2);
    expect(attempts[0]).toMatchObject({
      attempt_no: 1,
      provider: "bogus-primary",
      outcome: "retryable_failure",
      error_code: "provider_unavailable",
    });
    expect(attempts[1]).toMatchObject({
      attempt_no: 2,
      outcome: "retryable_failure",
      error_code: "provider_unavailable",
    });

    expect(await getUsageEvents(String(row.request_id))).toHaveLength(1);
    expect(await r2Exists(String(row.payload_pointer))).toBe(true);
    assertCreditUsage(creditSpy, FAILED_PARTIAL);
  });

  it("S10-006 — retryable rate_limited then same-target success", async () => {
    const { scenario, token } = await setupFresh({
      targets: [policyTarget("fake-v1", { max_attempts: 2 })],
    });
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    const adapterSpy = spyFakeAdapterSequence(fakeMod, original, [
      "retryable:rate_limited",
      "success",
    ]);
    const creditSpy = await spyCreditUsage();

    try {
      const started = Date.now();
      const result = await postVisit(scenario, token, {
        idempotencyKey: "s10-006-idem",
        traceId: "s10-006-trace",
      });
      const elapsed = Date.now() - started;

      assertHttpSse(result);
      const ref = assertHappyPathEvents(result.events, "s10-006-trace");
      expect(result.events.some((event) => event.event === "regenerating")).toBe(
        false,
      );
      expect(elapsed).toBeGreaterThanOrEqual(100);
      expect(elapsed).toBeLessThan(10_000);

      const row = await requireAiRequest(ref);
      expect(row.state).toBe("Completed");
      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(2);
      expect(attempts[0]).toMatchObject({
        attempt_no: 1,
        outcome: "retryable_failure",
        error_code: "rate_limited",
      });
      expect(attempts[1]).toMatchObject({
        attempt_no: 2,
        outcome: "success",
        tokens_in: 10,
        tokens_out: 20,
      });
      expect(costOf(attempts[1], "cost")).toBeCloseTo(0.005, 5);

      const usage = await getUsageEvents(String(row.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(30);
      expect(costOf(usage[0], "cost")).toBeCloseTo(0.005, 5);
      assertCreditUsage(creditSpy, COMPLETED_CREDIT);
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S10-007 — malformed then success retries as internal_error", async () => {
    const { scenario, token } = await setupFresh({
      targets: [policyTarget("fake-v1", { max_attempts: 2 })],
    });
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    const adapterSpy = spyFakeAdapterSequence(fakeMod, original, [
      "malformed",
      "success",
    ]);
    const creditSpy = await spyCreditUsage();

    try {
      const result = await postVisit(scenario, token, {
        idempotencyKey: "s10-007-idem",
        traceId: "s10-007-trace",
      });

      assertHttpSse(result);
      const ref = assertHappyPathEvents(result.events, "s10-007-trace");

      const row = await requireAiRequest(ref);
      expect(row.state).toBe("Completed");
      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(2);
      expect(attempts[0]).toMatchObject({
        attempt_no: 1,
        outcome: "retryable_failure",
        error_code: "internal_error",
      });
      expect(attempts[1]?.outcome).toBe("success");
      assertCreditUsage(creditSpy, COMPLETED_PARTIAL_FALSE);
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S10-008 — first-target exhaustion falls back to fake", async () => {
    const { scenario, token } = await setupFresh({
      targets: [
        policyTarget(
          "bogus-v1",
          { max_attempts: 2 },
          { providerId: "bogus-primary" },
        ),
        policyTarget("fake-v1", { max_attempts: 1 }),
      ],
    });

    const creditSpy = await spyCreditUsage();
    const started = Date.now();
    const result = await postVisit(scenario, token, {
      idempotencyKey: "s10-008-idem",
      traceId: "s10-008-trace",
    });
    const elapsed = Date.now() - started;

    assertHttpSse(result);
    const ref = assertHappyPathEvents(result.events, "s10-008-trace");
    expect(result.events.some((event) => event.event === "regenerating")).toBe(
      false,
    );
    expect(elapsed).toBeGreaterThanOrEqual(100);
    // selection_reason is in-memory only — D1 ai_attempt has no such column.

    const row = await requireAiRequest(ref);
    expect(row.state).toBe("Completed");
    const decision = parseDecision(row.routing_decision);
    expect(decision.chain?.map((entry) => entry.provider_id)).toEqual([
      "bogus-primary",
      "fake",
    ]);

    const attempts = await getAttempts(String(row.request_id));
    expect(attempts).toHaveLength(3);
    expect(attempts[0]).toMatchObject({
      attempt_no: 1,
      provider: "bogus-primary",
      outcome: "retryable_failure",
      error_code: "provider_unavailable",
    });
    expect(attempts[1]).toMatchObject({
      attempt_no: 2,
      provider: "bogus-primary",
      outcome: "retryable_failure",
      error_code: "provider_unavailable",
    });
    expect(attempts[2]).toMatchObject({
      attempt_no: 3,
      provider: "fake",
      outcome: "success",
    });

    const usage = await getUsageEvents(String(row.request_id));
    expect(usage).toHaveLength(1);
    expect(usage[0]?.tokens).toBe(30);
    assertCreditUsage(creditSpy, COMPLETED_CREDIT);
  });

  it("S10-009 — missing DeepSeek key is terminal provider_rejected with no fallback", async () => {
    const { scenario, token } = await setupFresh({
      targets: [
        policyTarget(
          "deepseek-v4-flash",
          { max_attempts: 2 },
          { providerId: "deepseek" },
        ),
        policyTarget("fake-v1", { max_attempts: 1 }),
      ],
    });

    const creditSpy = await spyCreditUsage();
    const result = await postVisit(scenario, token, {
      idempotencyKey: "s10-009-idem",
      traceId: "s10-009-trace",
    });

    assertHttpSse(result);
    const ref = assertFailedEvents(result.events, {
      code: "provider_rejected",
      retrySafe: false,
      traceId: "s10-009-trace",
    });

    const row = await requireAiRequest(ref);
    expect(row.state).toBe("Failed");
    expect(row.terminal_error_code).toBe("provider_rejected");

    const attempts = await getAttempts(String(row.request_id));
    expect(attempts).toHaveLength(1);
    expect(attempts[0]).toMatchObject({
      provider: "deepseek",
      model: "deepseek-v4-flash",
      outcome: "terminal_failure",
      error_code: "provider_rejected",
      tokens_in: 0,
      tokens_out: 0,
    });
    expect(costOf(attempts[0], "cost")).toBe(0);
    expect(attempts.some((attempt) => attempt.provider === "fake")).toBe(false);

    expect(await getUsageEvents(String(row.request_id))).toHaveLength(1);
    expect(await r2Exists(String(row.payload_pointer))).toBe(true);
    assertCreditUsage(creditSpy, FAILED_FULL_CONSUME);
  });

  it("S10-010 — attempt timeouts retry then exhaust as provider_unavailable", async () => {
    const { scenario, token } = await setupFresh({
      targets: [policyTarget("fake-v1", { timeout_ms: 50, max_attempts: 2 })],
    });
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    class HangFake extends original {
      override async invoke(
        _request: unknown,
        options?: { signal?: AbortSignal },
      ) {
        await hangUntilAbort(options?.signal, 5000);
        return {
          kind: "success" as const,
          result: {
            finalContent: { type: "text" as const, text: FAKE_SUMMARY },
            usage: { input: 10, output: 20, cached: 0 },
            providerModel: { provider: "fake", model: "fake-v1" },
            finishReason: "stop" as const,
            providerRequestId: "fake-req-001",
            timing: { queue_ms: 1, provider_ms: 5, total_ms: 6 },
          },
          chunks: [],
        };
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new HangFake(["success"]) as never);
    const creditSpy = await spyCreditUsage();

    try {
      const started = Date.now();
      const result = await postVisit(scenario, token, {
        idempotencyKey: "s10-010-idem",
        traceId: "s10-010-trace",
      });
      const elapsed = Date.now() - started;

      assertHttpSse(result);
      const ref = assertFailedEvents(result.events, {
        code: "provider_unavailable",
        retrySafe: true,
        traceId: "s10-010-trace",
      });
      expect(elapsed).toBeGreaterThanOrEqual(100);

      const row = await requireAiRequest(ref);
      expect(row.state).toBe("Failed");
      expect(row.terminal_error_code).toBe("provider_unavailable");
      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(2);
      expect(attempts[0]).toMatchObject({
        attempt_no: 1,
        outcome: "timeout",
        error_code: "timeout",
      });
      expect(attempts[1]).toMatchObject({
        attempt_no: 2,
        outcome: "timeout",
        error_code: "timeout",
      });
      assertCreditUsage(creditSpy, FAILED_PARTIAL);
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S10-011 — fallback after timeout succeeds on second target", async () => {
    const { scenario, token } = await setupFresh({
      targets: [
        policyTarget("fake-slow", { timeout_ms: 50, max_attempts: 1 }),
        policyTarget("fake-v1", { timeout_ms: 30000, max_attempts: 1 }),
      ],
    });
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    class HangFake extends original {
      override async invoke(
        _request: unknown,
        options?: { signal?: AbortSignal },
      ) {
        await hangUntilAbort(options?.signal, 5000);
        return {
          kind: "success" as const,
          result: {
            finalContent: { type: "text" as const, text: "slow" },
            usage: { input: 0, output: 0, cached: 0 },
            providerModel: { provider: "fake", model: "fake-slow" },
            finishReason: "stop" as const,
            providerRequestId: "hang",
            timing: { queue_ms: 0, provider_ms: 0, total_ms: 0 },
          },
          chunks: [],
        };
      }
    }
    let constructions = 0;
    const adapterSpy = vi.spyOn(fakeMod, "FakeAdapter").mockImplementation(() => {
      constructions += 1;
      if (constructions === 1) {
        return new HangFake(["success"]) as never;
      }
      return new original(["success"]) as never;
    });

    try {
      const result = await postVisit(scenario, token, {
        idempotencyKey: "s10-011-idem",
        traceId: "s10-011-trace",
      });

      assertHttpSse(result);
      const ref = assertHappyPathEvents(result.events, "s10-011-trace");
      expect(result.events.some((event) => event.event === "regenerating")).toBe(
        false,
      );

      const row = await requireAiRequest(ref);
      expect(row.state).toBe("Completed");
      const attempts = await getAttempts(String(row.request_id));
      expect(attempts).toHaveLength(2);
      expect(attempts[0]).toMatchObject({
        model: "fake-slow",
        outcome: "timeout",
        error_code: "timeout",
      });
      expect(attempts[1]).toMatchObject({
        model: "fake-v1",
        outcome: "success",
      });
      // selection_reason fallback_after_timeout is in-memory only.

      const usage = await getUsageEvents(String(row.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(30);
      expect(costOf(usage[0], "cost")).toBeCloseTo(0.005, 5);
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S10-012 — all chain targets exhausted with real attempt rows", async () => {
    const { scenario, token } = await setupFresh({
      targets: [
        policyTarget(
          "bogus-v1",
          { max_attempts: 1 },
          { providerId: "bogus-a" },
        ),
        policyTarget(
          "bogus-v1",
          { max_attempts: 1 },
          { providerId: "bogus-b" },
        ),
      ],
    });

    const creditSpy = await spyCreditUsage();
    const result = await postVisit(scenario, token, {
      idempotencyKey: "s10-012-idem",
      traceId: "s10-012-trace",
    });

    assertHttpSse(result);
    const ref = assertFailedEvents(result.events, {
      code: "provider_unavailable",
      retrySafe: true,
      traceId: "s10-012-trace",
    });

    const row = await requireAiRequest(ref);
    expect(row.state).toBe("Failed");
    expect(row.terminal_error_code).toBe("provider_unavailable");

    const attempts = await getAttempts(String(row.request_id));
    expect(attempts).toHaveLength(2);
    expect(attempts[0]).toMatchObject({
      provider: "bogus-a",
      outcome: "retryable_failure",
      error_code: "provider_unavailable",
    });
    expect(attempts[1]).toMatchObject({
      provider: "bogus-b",
      outcome: "retryable_failure",
      error_code: "provider_unavailable",
    });

    expect(await getUsageEvents(String(row.request_id))).toHaveLength(1);
    expect(await r2Exists(String(row.payload_pointer))).toBe(true);
    assertCreditUsage(creditSpy, FAILED_PARTIAL);
  });

  it("S10-013 — client disconnect mid-stream credits partial streamed chars", async () => {
    const { scenario, token } = await setupFresh();
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    let invokeEntered = false;
    let chunkEmitted = false;
    class PartialHangFake extends original {
      override async invoke(
        _request: unknown,
        options?: {
          signal?: AbortSignal;
          onStreamChunk?: (chunk: {
            sequenceNumber: number;
            kind: string;
            payload: { text: string };
            terminal: boolean;
          }) => void;
        },
      ) {
        invokeEntered = true;
        options?.onStreamChunk?.({
          sequenceNumber: 0,
          kind: "text_delta",
          payload: { text: "Partial " },
          terminal: false,
        });
        chunkEmitted = true;
        await hangUntilAbort(options?.signal, 5000);
        return {
          kind: "success" as const,
          result: {
            finalContent: { type: "text" as const, text: "Partial " },
            usage: { input: 0, output: 0, cached: 0 },
            providerModel: { provider: "fake", model: "fake-v1" },
            finishReason: "stop" as const,
            providerRequestId: "partial",
            timing: { queue_ms: 0, provider_ms: 0, total_ms: 0 },
          },
          chunks: [],
        };
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new PartialHangFake(["success"]) as never);
    const creditSpy = await spyCreditUsage();
    const controller = new AbortController();

    try {
      await pinActiveServingPolicy(scenario.installationId);
      const fetchPromise = clinicFetch("/v1/requests", {
        method: "POST",
        token,
        headers: {
          "x-idempotency-key": "s10-013-idem",
          "x-capability-version": CAPABILITY_VERSION,
          "x-trace-id": "s10-013-trace",
        },
        body: visitBody(scenario),
        signal: controller.signal,
      });

      await waitFor(
        "invoke entered and stream chunk",
        () => invokeEntered && chunkEmitted,
      );
      controller.abort();
      let response: Response | undefined;
      try {
        response = await fetchPromise;
      } catch {
        // Client abort may reject the fetch.
      } finally {
        await cancelResponseBody(response);
      }

      await flushBackgroundWork(350);

      const row = await queryOne<Record<string, unknown>>(
        `SELECT * FROM ai_request WHERE installation_id = ?
         ORDER BY created_at DESC LIMIT 1`,
        [scenario.installationId],
      );
      expect(row).not.toBeNull();
      expect(row?.state).toBe("Cancelled");
      expect(row?.terminal_error_code).toBeNull();

      const attempts = await getAttempts(String(row?.request_id));
      expect(attempts).toHaveLength(1);
      expect(attempts[0]).toMatchObject({
        outcome: "terminal_failure",
        error_code: "cancelled",
        tokens_in: 0,
        tokens_out: 0,
      });

      const usage = await getUsageEvents(String(row?.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(8);
      expect(costOf(usage[0], "cost")).toBeCloseTo(0.0016, 5);
      expect(await r2Exists(String(row?.payload_pointer))).toBe(true);
      assertCreditUsage(creditSpy, CANCELLED_STREAMED);
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S10-014 — client disconnect before any provider byte credits zero usage", async () => {
    const { scenario, token } = await setupFresh();
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    let invokeEntered = false;
    class HangFake extends original {
      override async invoke(
        _request: unknown,
        options?: { signal?: AbortSignal },
      ) {
        invokeEntered = true;
        await hangUntilAbort(options?.signal, 5000);
        return {
          kind: "success" as const,
          result: {
            finalContent: { type: "text" as const, text: FAKE_SUMMARY },
            usage: { input: 10, output: 20, cached: 0 },
            providerModel: { provider: "fake", model: "fake-v1" },
            finishReason: "stop" as const,
            providerRequestId: "hang",
            timing: { queue_ms: 0, provider_ms: 0, total_ms: 0 },
          },
          chunks: [],
        };
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new HangFake(["success"]) as never);
    const creditSpy = await spyCreditUsage();
    const controller = new AbortController();

    try {
      await pinActiveServingPolicy(scenario.installationId);
      const fetchPromise = clinicFetch("/v1/requests", {
        method: "POST",
        token,
        headers: {
          "x-idempotency-key": "s10-014-idem",
          "x-capability-version": CAPABILITY_VERSION,
          "x-trace-id": "s10-014-trace",
        },
        body: visitBody(scenario),
        signal: controller.signal,
      });

      await waitFor("invoke entered", () => invokeEntered);
      controller.abort();
      let response: Response | undefined;
      try {
        response = await fetchPromise;
      } catch {
        // Client abort may reject the fetch.
      } finally {
        await cancelResponseBody(response);
      }

      await flushBackgroundWork(350);

      const row = await queryOne<Record<string, unknown>>(
        `SELECT * FROM ai_request WHERE installation_id = ?
         ORDER BY created_at DESC LIMIT 1`,
        [scenario.installationId],
      );
      expect(row).not.toBeNull();
      expect(row?.state).toBe("Cancelled");

      const attempts = await getAttempts(String(row?.request_id));
      expect(attempts).toHaveLength(1);
      expect(attempts[0]).toMatchObject({
        outcome: "terminal_failure",
        error_code: "cancelled",
      });

      const usage = await getUsageEvents(String(row?.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(0);
      expect(costOf(usage[0], "cost")).toBe(0);
      expect(await r2Exists(String(row?.payload_pointer))).toBe(true);
      assertCreditUsage(creditSpy, CANCELLED_ZERO);
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S10-015 — abort already signaled at entry leaves Accepted with no settlement", async () => {
    const { scenario, token } = await setupFresh();
    // workerd SELF.fetch cannot see Proxy/defineProperty on Request.signal
    // (and rejects constructing Request with an aborted signal). Drive the
    // documented barrel seam (Register 5 #39 / S08-057).
    const request = requestAbortedAtEntry(
      new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
          "x-idempotency-key": "s10-015-idem",
          "x-capability-version": CAPABILITY_VERSION,
          "x-trace-id": "s10-015-trace",
        },
        body: JSON.stringify(visitBody(scenario)),
      }),
    );

    let eventSourceInvoked = false;
    const response = await handleAdapterRequest(request, {
      preAccept: async () => ({ ok: true }),
      eventSource: () => {
        eventSourceInvoked = true;
      },
    });

    expect(eventSourceInvoked).toBe(false);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/event-stream");
    const events = await parseSseEvents(response);
    assertSseSequence(events, ["accepted"]);
    expect(events[0]?.data.trace_id).toBe("s10-015-trace");
    expect(events.some((event) => event.event === "cancelled")).toBe(false);
    expect(terminalEventTypes(events)).toEqual([]);

    await flushBackgroundWork(200);

    // Stub preAccept does not run the worker guard INSERT; abort-at-entry
    // never reaches the event source, so no ai_request row is created.
    expect(await count("ai_request")).toBe(0);
    expect(await count("ai_attempt")).toBe(0);
    expect(await count("usage_event")).toBe(0);
  });

  it("S10-016 — idempotent replay of completed prior returns placeholder", async () => {
    const { scenario } = await setupFresh();
    const first = await postVisit(scenario, await mintAat(scenario), {
      idempotencyKey: "s10-001-idem",
      traceId: "s10-001-trace",
    });
    assertHttpSse(first);
    const firstRef = assertHappyPathEvents(first.events, "s10-001-trace");
    const firstRow = await requireAiRequest(firstRef);
    expect(firstRow.state).toBe("Completed");
    expect(await count("ai_request")).toBe(1);

    const creditSpy = await spyCreditUsage();
    const replay = await postVisit(scenario, await mintAat(scenario), {
      idempotencyKey: "s10-001-idem",
      traceId: "s10-016-trace",
    });

    assertHttpSse(replay);
    assertSseSequence(replay.events, ["accepted", "completed"], "exact");
    const replayRef = assertAcceptedEvent(replay.events[0], "s10-016-trace");
    expect(replayRef).not.toBe(firstRef);
    assertCompletedEvent(replay.events[1], "Prior request completed.", "s10-016-trace");
    expect(replay.events.some((event) => event.event === "text_delta")).toBe(false);
    expect(await count("ai_request")).toBe(1);
    const after = await requireAiRequest(firstRef);
    expect(after.request_id).toBe(firstRow.request_id);
    assertCreditUsage(creditSpy, NO_CREDIT);
  });

  it("S10-017 — in-flight idempotent replay stays accepted-only", async () => {
    const { scenario } = await setupFresh();
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    let invokeEntered = false;
    class HangThenSuccess extends original {
      override async invoke(
        request: never,
        options?: { signal?: AbortSignal },
      ) {
        invokeEntered = true;
        await hangUntilAbort(options?.signal, 5000);
        return super.invoke(request, options);
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new HangThenSuccess(["success"]) as never);

    const body = visitBody(scenario);
    let firstResponse: Response | undefined;
    let secondResponse: Response | undefined;
    try {
      const firstToken = await mintAat(scenario);
      await pinActiveServingPolicy(scenario.installationId);
      firstResponse = await clinicFetch("/v1/requests", {
        method: "POST",
        token: firstToken,
        headers: {
          "x-idempotency-key": "s10-017-idem",
          "x-capability-version": CAPABILITY_VERSION,
          "x-trace-id": "s10-017-first",
        },
        body,
      });
      expect(firstResponse.status).toBe(200);
      await waitFor("first invoke entered", () => invokeEntered);

      const secondToken = await mintAat(scenario);
      await pinActiveServingPolicy(scenario.installationId);
      secondResponse = await clinicFetch("/v1/requests", {
        method: "POST",
        token: secondToken,
        headers: {
          "x-idempotency-key": "s10-017-idem",
          "x-capability-version": CAPABILITY_VERSION,
          "x-trace-id": "s10-017-trace",
        },
        body,
      });
      expect(secondResponse.status).toBe(200);
      expect(secondResponse.headers.get("content-type")).toContain(
        "text/event-stream",
      );
      const secondEvents = await readSseUntil(
        secondResponse,
        (seen) => seen.some((event) => event.event === "accepted"),
        { drainAfterStopMs: 250 },
      );
      assertSseSequence(secondEvents, ["accepted"], "exact");
      assertAcceptedEvent(secondEvents[0], "s10-017-trace");
      expect(terminalEventTypes(secondEvents)).toEqual([]);
      expect(JSON.stringify(secondEvents)).not.toContain(
        "Prior request completed.",
      );

      const firstEvents = await parseSseEvents(firstResponse);
      await flushBackgroundWork(200);
      assertHappyPathEvents(firstEvents, "s10-017-first");

      expect(await count("ai_request")).toBe(1);
      const row = await queryOne<Record<string, unknown>>(
        "SELECT * FROM ai_request ORDER BY created_at DESC LIMIT 1",
      );
      expect(row?.state).toBe("Completed");
      expect(await getAttempts(String(row?.request_id))).toHaveLength(1);
      const usage = await getUsageEvents(String(row?.request_id));
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(30);
    } finally {
      await cancelResponseBody(secondResponse);
      adapterSpy.mockRestore();
    }
  });
});
