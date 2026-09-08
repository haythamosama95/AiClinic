import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import publishedVisitSummary from "../../manifests/published/clinic.visit_summary@1.0.0.json";
import {
  assertRequestReferenceShape,
  assertSseSequence,
  assertTaxonomyBody,
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clinicFetch,
  count,
  createCapabilityRegistry,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  env,
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
  loadManifest,
  mintAat,
  newScenario,
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
  seedSql,
  setCapabilityRegistry,
  visitSummaryInvokeBody,
  wrapDurableObjectNamespace,
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
const PERIOD_START_JULY = "2026-07-01T00:00:00.000Z";
const PERIOD_END_COVERING_NOW = "2027-01-01T00:00:00.000Z";
const PERIOD_A_START = "2026-07-01T00:00:00.000Z";
const PERIOD_A_END = "2026-08-01T00:00:00.000Z";
const PERIOD_B_START = "2026-08-01T00:00:00.000Z";
const PERIOD_B_END = "2026-09-01T00:00:00.000Z";
const ENVELOPE_TOP_KEYS = ["attempts", "context", "prompt", "result"] as const;
const CANONICAL_RESULT_KEYS = [
  "finalContent",
  "finishReason",
  "providerModel",
  "providerRequestId",
  "timing",
  "usage",
] as const;
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

const JULY_ENTITLE: EntitlePayload = {
  ...DEFAULT_ENTITLE_PAYLOAD,
  period_start: PERIOD_START_JULY,
  period_end: PERIOD_END_COVERING_NOW,
};

type FakeModule = typeof import("../../src/provider/fake");
type CreditModule = typeof import("../../src/credit");
type JournalModule = typeof import("../../src/journal");

type QuotaInspectState = {
  periodCounters?: {
    inFlight?: number;
    requestsUsed?: number;
    tokensUsed?: number;
    costUsed?: number;
  };
  periodBounds?: { period_start?: string; period_end?: string };
  admittedRequests?: Record<string, unknown>;
  creditedRequests?: Record<string, unknown>;
  idempotency?: Record<
    string,
    {
      state?: string;
      requestId?: string;
      requestReference?: string;
      terminalErrorCode?: string;
      expiresAt?: number;
    }
  >;
};

type EnvelopeAttempt = {
  payload?: unknown;
  truncated?: boolean;
};

type CanonicalResultShape = {
  finalContent?: { type?: string; text?: string };
  usage?: { input?: number; output?: number; cached?: number };
  providerModel?: { provider?: string; model?: string };
  finishReason?: string;
  providerRequestId?: string;
  timing?: { queue_ms?: number; provider_ms?: number; total_ms?: number };
};

/**
 * HARNESS-GAP: FakeAdapter scripting is not on the frozen barrel; catalog §1
 * documents vi.spyOn(fakeMod, "FakeAdapter") as the seam.
 */
async function loadFakeModule(): Promise<FakeModule> {
  return import("../../src/provider/fake");
}

/**
 * HARNESS-GAP: creditUsage is NOT on the barrel. Catalog S11-021 Action
 * calls it with a stubbed DO; S11-012 notes the wrapper mapping.
 */
async function loadCreditModule(): Promise<CreditModule> {
  return import("../../src/credit");
}

/**
 * HARNESS-GAP: writeSettlementJournal is not exported. S11-021's
 * settleTerminal-equivalent journal path is createRequestRow +
 * writePostResponseDetail (persistPostResponseDetail).
 */
async function loadJournalModule(): Promise<JournalModule> {
  return import("../../src/journal");
}

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

function visitBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return visitSummaryInvokeBody(scenario, overrides);
}

function policyTarget(
  modelId: string,
  overrides: Record<string, unknown> = {},
  opts: Parameters<typeof fakePolicyTarget>[1] = {},
): Record<string, unknown> {
  return { ...fakePolicyTarget(modelId, opts), ...overrides };
}

function costOf(row: Record<string, unknown> | undefined, key: string): number {
  return Number(row?.[key] ?? NaN);
}

function fakeSuccessResult() {
  return {
    finalContent: { type: "text" as const, text: FAKE_SUMMARY },
    usage: { input: 10, output: 20, cached: 0 },
    providerModel: { provider: "fake", model: "fake-v1" },
    finishReason: "stop" as const,
    providerRequestId: "fake-req-001",
    timing: { queue_ms: 1, provider_ms: 5, total_ms: 6 },
  };
}

async function setupFresh(options?: {
  targets?: Record<string, unknown>[];
  entitle?: EntitlePayload;
  skipPolicy?: boolean;
}): Promise<Scenario> {
  if (
    options?.targets === undefined &&
    options?.entitle === undefined &&
    options?.skipPolicy !== true
  ) {
    return provisionHappyPath(undefined, JULY_ENTITLE);
  }

  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  const entitled = await entitleInstallation(
    scenario,
    options?.entitle ?? JULY_ENTITLE,
  );
  expect(entitled.status).toBe(200);
  if (options?.skipPolicy !== true) {
    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION, {
      targets: options?.targets,
    });
    const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    expect(published.status).toBe(200);
    const promoted = await promotePolicy(POLICY_ID, POLICY_VERSION);
    expect(promoted.status).toBe(200);
  }
  return scenario;
}

/**
 * Pool TTL is 100 ms. Parallel files share isolateConfigCache and call
 * clear(); preload→consult can then miss
 * `active_routing_policy:routing/standard` (ConfigCacheMissError → Failed
 * with taxonomy internal_error instead of empty-chain provider_unavailable).
 * Raise TTL and re-stamp the serving policy immediately before POST so the
 * post-accept consult cannot miss.
 */
const SERVE_CACHE_TTL_MS = 30_000;

async function loadServingPolicyRow(
  policyVersion: string,
): Promise<Record<string, unknown>> {
  const row = await getRoutingPolicy(POLICY_ID, policyVersion);
  expect(row?.status).toBe("active");
  const pointer = String(row!.content_pointer ?? "");
  const document = await getR2Json(pointer);
  return { ...row!, document };
}

async function loadActiveServingPolicyRow(): Promise<Record<string, unknown>> {
  const active = await queryOne<{ version: string }>(
    `SELECT version FROM routing_policy
     WHERE policy_id = ? AND status = 'active'
     ORDER BY active_from DESC, rowid DESC LIMIT 1`,
    [POLICY_ID],
  );
  expect(active?.version).toBeTruthy();
  return loadServingPolicyRow(String(active!.version));
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

async function postVisit(
  scenario: Scenario,
  opts: {
    idempotencyKey: string;
    traceId?: string;
    body?: Record<string, unknown>;
  },
): Promise<InvokeResult> {
  const token = await mintAat(scenario);
  const policyRow = await loadActiveServingPolicyRow();
  pinServingRoutingPolicy(policyRow, [scenario.installationId]);
  const result = await postRequest(scenario, {
    token,
    idempotencyKey: opts.idempotencyKey,
    traceId: opts.traceId,
    body: opts.body ?? visitBody(scenario),
  });
  await flushBackgroundWork(200);
  return result;
}

function assertHttpSse(result: InvokeResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
}

function assertAcceptedEvent(
  event: SseEvent | undefined,
  traceId?: string,
): string {
  expect(event?.event).toBe("accepted");
  const ref = String(event?.data.request_reference ?? "");
  assertRequestReferenceShape(ref);
  if (traceId !== undefined) {
    expect(event?.data.trace_id).toBe(traceId);
  } else {
    expect(typeof event?.data.trace_id).toBe("string");
    expect(String(event?.data.trace_id).length).toBeGreaterThan(0);
  }
  return ref;
}

async function requireAiRequest(
  ref: string,
): Promise<Record<string, unknown>> {
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

function entitlementSnapshot(
  periodStart: string,
  periodEnd: string,
): Record<string, unknown> {
  return {
    plan: "standard",
    period_bounds: {
      period_start: periodStart,
      period_end: periodEnd,
    },
    request_quota: 1000,
    token_cost_budget: {
      token_budget: 500000,
      cost_budget: 50.0,
    },
    allowed_capabilities: [CAPABILITY_ID],
    soft_threshold: 0.8,
    status: "active",
  };
}

function restorePublishedRegistry(): void {
  setCapabilityRegistry(
    createCapabilityRegistry([
      loadManifest(publishedVisitSummary as unknown as Record<string, unknown>),
    ]),
    { replace: true },
  );
}

function cloneVisitSummary(
  capabilityId: string,
  quotaWeight: number,
): Record<string, unknown> {
  const wire = structuredClone(
    publishedVisitSummary as unknown as Record<string, unknown>,
  );
  const identity = { ...(wire.Identity as Record<string, unknown>) };
  identity.capabilityId = capabilityId;
  wire.Identity = identity;
  const economics = { ...(wire.Economics as Record<string, unknown>) };
  economics.quotaWeight = quotaWeight;
  wire.Economics = economics;
  const access = wire.Access as Record<string, unknown>;
  expect(access.requiredCapabilityScope).toBe("ai.visit_summary");
  return wire;
}

function envelopeKey(requestId: string): string {
  return `request/${requestId}/envelope`;
}

function assertEnvelopeTopKeys(envelope: Record<string, unknown>): void {
  expect(Object.keys(envelope).sort()).toEqual([...ENVELOPE_TOP_KEYS]);
}

function assertPlaceholderResult(
  result: CanonicalResultShape | undefined,
  opts: { totalTokens: number; finishReason: string },
): void {
  expect(result).toBeDefined();
  expect(Object.keys(result ?? {}).sort()).toEqual(
    [...CANONICAL_RESULT_KEYS].sort(),
  );
  expect(result?.finalContent).toEqual({ type: "text", text: "" });
  expect(result?.usage).toEqual({
    input: opts.totalTokens,
    output: 0,
    cached: 0,
  });
  expect(result?.providerModel).toEqual({ provider: "", model: "" });
  expect(result?.finishReason).toBe(opts.finishReason);
  expect(result?.providerRequestId).toBe("");
  expect(result?.timing).toEqual({
    queue_ms: 0,
    provider_ms: 0,
    total_ms: 0,
  });
}

async function completeHappyRequest(
  scenario: Scenario,
  idempotencyKey: string,
  traceId?: string,
  body?: Record<string, unknown>,
): Promise<{ ref: string; requestId: string; row: Record<string, unknown> }> {
  const result = await postVisit(scenario, { idempotencyKey, traceId, body });
  assertHttpSse(result);
  const ref = assertAcceptedEvent(result.events[0], traceId);
  const completed = result.events.find((event) => event.event === "completed");
  expect(completed).toBeDefined();
  const row = await requireAiRequest(ref);
  expect(row.state).toBe("Completed");
  return { ref, requestId: String(row.request_id), row };
}

async function failEmptyChain(
  scenario: Scenario,
  idempotencyKey: string,
  traceId?: string,
): Promise<{ ref: string; requestId: string; row: Record<string, unknown> }> {
  const document = fakePolicyDocument(POLICY_ID, "2", {
    ruleId: "all-excluded",
    overrides: [
      {
        installation_id: scenario.installationId,
        exclude_providers: ["fake"],
      },
    ],
  });
  const published = await publishPolicy(POLICY_ID, "2", document);
  expect(published.status).toBe(200);
  const promoted = await promotePolicy(POLICY_ID, "2");
  expect(promoted.status).toBe(200);

  const result = await postVisit(scenario, { idempotencyKey, traceId });
  assertHttpSse(result);
  assertSseSequence(result.events, ["accepted", "failed"], "exact");
  const ref = assertAcceptedEvent(result.events[0], traceId);
  const failed = result.events[1];
  expect(failed?.event).toBe("failed");
  assertTaxonomyBody(failed?.data, {
    code: "provider_unavailable",
    retry_safe: true,
  });
  const row = await requireAiRequest(ref);
  expect(row.state).toBe("Failed");
  expect(row.terminal_error_code).toBe("provider_unavailable");
  return { ref, requestId: String(row.request_id), row };
}

async function failTruncationExhausted(
  scenario: Scenario,
  idempotencyKey: string,
  traceId?: string,
): Promise<{ ref: string; requestId: string; row: Record<string, unknown> }> {
  const document = fakePolicyDocument(POLICY_ID, "3", {
    targets: [policyTarget("fake-v1", { max_attempts: 1 })],
  });
  const published = await publishPolicy(POLICY_ID, "3", document);
  expect(published.status).toBe(200);
  const promoted = await promotePolicy(POLICY_ID, "3");
  expect(promoted.status).toBe(200);

  const fakeMod = await loadFakeModule();
  const original = fakeMod.FakeAdapter;
  const adapterSpy = spyFakeAdapterSequence(fakeMod, original, ["truncation"]);
  try {
    const result = await postVisit(scenario, { idempotencyKey, traceId });
    assertHttpSse(result);
    // Truncation-exhausted relays provisional text_delta then failed (S10-028).
    const ref = assertAcceptedEvent(result.events[0], traceId);
    const failed = result.events.find((event) => event.event === "failed");
    expect(failed).toBeDefined();
    assertTaxonomyBody(failed?.data, {
      code: "validation_failed",
      retry_safe: true,
    });
    const row = await requireAiRequest(ref);
    expect(row.state).toBe("Failed");
    expect(row.terminal_error_code).toBe("validation_failed");
    return { ref, requestId: String(row.request_id), row };
  } finally {
    adapterSpy.mockRestore();
  }
}

async function cancelInFlight(
  scenario: Scenario,
  idempotencyKey: string,
  traceId?: string,
): Promise<{ ref: string; requestId: string; row: Record<string, unknown> }> {
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
        result: fakeSuccessResult(),
        chunks: [],
      };
    }
  }
  const adapterSpy = vi
    .spyOn(fakeMod, "FakeAdapter")
    .mockImplementation(() => new HangFake(["success"]) as never);
  const controller = new AbortController();
  try {
    const token = await mintAat(scenario);
    const policyRow = await loadActiveServingPolicyRow();
    pinServingRoutingPolicy(policyRow, [scenario.installationId]);
    const fetchPromise = clinicFetch("/v1/requests", {
      method: "POST",
      token,
      headers: {
        "x-idempotency-key": idempotencyKey,
        "x-capability-version": CAPABILITY_VERSION,
        ...(traceId !== undefined ? { "x-trace-id": traceId } : {}),
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
    const row = await waitForLatestRequestState(
      scenario.installationId,
      "Cancelled",
    );
    expect(row.terminal_error_code).toBeNull();
    return {
      ref: String(row.request_reference),
      requestId: String(row.request_id),
      row,
    };
  } finally {
    adapterSpy.mockRestore();
  }
}

async function snapshotSettlement(requestId: string, ref: string) {
  const row = await requireAiRequest(ref);
  const attemptCount = await count("ai_attempt", "request_id = ?", [requestId]);
  const usageCount = await count("usage_event", "request_id = ?", [requestId]);
  const pointer = String(row.payload_pointer ?? "");
  const envelope = pointer.length > 0 ? await getR2Json(pointer) : null;
  return {
    row,
    rowJson: JSON.stringify(row),
    attemptCount,
    usageCount,
    pointer,
    envelopeJson: envelope === null ? null : JSON.stringify(envelope),
  };
}

function settlementFingerprint(
  snapshot: Awaited<ReturnType<typeof snapshotSettlement>>,
): string {
  return JSON.stringify({
    attemptCount: snapshot.attemptCount,
    usageCount: snapshot.usageCount,
    pointer: snapshot.pointer,
    envelopeJson: snapshot.envelopeJson,
    rowJson: snapshot.rowJson,
  });
}

/**
 * S11-008 in-flight cancel writes Cancelled + DO credit before
 * persistPostResponseDetail inserts the attempt/usage/envelope
 * (recordTerminalState is fire-and-forget; journal is waitUntil).
 * Snapshot only after that journal is stable so replay is not blamed
 * for the original settlement.
 */
async function waitForStableCancelledSnapshot(
  requestId: string,
  ref: string,
  timeoutMs = 8000,
): Promise<Awaited<ReturnType<typeof snapshotSettlement>>> {
  const started = Date.now();
  let previous: string | undefined;
  while (Date.now() - started < timeoutMs) {
    const current = await snapshotSettlement(requestId, ref);
    const settled =
      current.row.state === "Cancelled" &&
      current.attemptCount === 1 &&
      current.usageCount === 1 &&
      current.pointer.length > 0 &&
      current.envelopeJson !== null;
    const fingerprint = settlementFingerprint(current);
    if (settled && previous === fingerprint) {
      return current;
    }
    previous = settled ? fingerprint : undefined;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(
    `timed out waiting for stable Cancelled settlement for ${requestId}`,
  );
}

describe("Stage 11 — replay, envelope, grace (S11-012…S11-021)", () => {
  it("S11-012 — creditRPC rejects double credit and unknown ids", async () => {
    const scenario = await setupFresh();
    const idempotencyKey = `s11-012-${crypto.randomUUID()}`;
    const { requestId, ref } = await completeHappyRequest(
      scenario,
      idempotencyKey,
    );
    const now = Date.now();

    const afterComplete = await inspectState(scenario.installationId, now);
    expect(afterComplete.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 30,
      inFlight: 0,
    });
    expect(costOf(afterComplete.periodCounters, "costUsed")).toBeCloseTo(
      0.005,
      5,
    );
    expect(Object.keys(afterComplete.creditedRequests ?? {})).toEqual([
      requestId,
    ]);
    expect(afterComplete.idempotency?.[idempotencyKey]?.state).toBe("completed");
    expect(await count("usage_event", "request_id = ?", [requestId])).toBe(1);

    const doubleCredit = await gatewayObjectJson(
      scenario.installationId,
      {
        kind: "credit",
        installationId: scenario.installationId,
        requestId,
        requestReference: ref,
        usage: { tokens: 30, cost: 0.005 },
        partial: false,
      },
      { now },
    );
    expect(doubleCredit.status).toBe(200);
    expect(doubleCredit.json).toEqual({
      kind: "credit",
      ok: false,
      code: "unknown_request",
    });

    const afterDouble = await inspectState(scenario.installationId, now);
    expect(afterDouble.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 30,
      inFlight: 0,
    });
    expect(costOf(afterDouble.periodCounters, "costUsed")).toBeCloseTo(0.005, 5);
    expect(Object.keys(afterDouble.creditedRequests ?? {})).toHaveLength(1);
    expect(afterDouble.idempotency?.[idempotencyKey]?.state).toBe("completed");
    expect(await count("usage_event", "request_id = ?", [requestId])).toBe(1);

    const unknownId = crypto.randomUUID();
    const unknownCredit = await gatewayObjectJson(
      scenario.installationId,
      {
        kind: "credit",
        installationId: scenario.installationId,
        requestId: unknownId,
        requestReference: ref,
        usage: { tokens: 30, cost: 0.005 },
        partial: false,
      },
      { now },
    );
    expect(unknownCredit.json).toEqual({
      kind: "credit",
      ok: false,
      code: "unknown_request",
    });

    const afterUnknown = await inspectState(scenario.installationId, now);
    expect(Object.keys(afterUnknown.creditedRequests ?? {})).toHaveLength(1);
    expect(afterUnknown.creditedRequests?.[requestId]).toBeDefined();
    expect(afterUnknown.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 30,
      inFlight: 0,
    });
    expect(await count("usage_event", "request_id = ?", [requestId])).toBe(1);
  });

  it("S11-013 — idempotent replay after Completed", async () => {
    const scenario = await setupFresh();
    const idempotencyKey = `s11-013-${crypto.randomUUID()}`;
    const { ref, requestId } = await completeHappyRequest(
      scenario,
      idempotencyKey,
      "s11-013-orig",
    );
    const snapshot = await snapshotSettlement(requestId, ref);
    const doBefore = await inspectState(scenario.installationId);

    const replay = await postVisit(scenario, {
      idempotencyKey,
      traceId: "s11-013-replay",
    });
    assertHttpSse(replay);
    assertSseSequence(replay.events, ["accepted", "completed"]);
    const completed = replay.events.find((event) => event.event === "completed");
    const resultPayload = completed?.data.result as
      | { finalContent?: { text?: string; authoritative?: boolean } }
      | undefined;
    expect(resultPayload?.finalContent).toEqual({
      text: "Prior request completed.",
      authoritative: true,
    });

    const after = await snapshotSettlement(requestId, ref);
    expect(after.attemptCount).toBe(snapshot.attemptCount);
    expect(after.usageCount).toBe(snapshot.usageCount);
    expect(after.pointer).toBe(snapshot.pointer);
    expect(after.envelopeJson).toBe(snapshot.envelopeJson);
    expect(after.rowJson).toBe(snapshot.rowJson);
    expect(await count("ai_request")).toBe(1);

    const doAfter = await inspectState(scenario.installationId);
    expect(doAfter.periodCounters).toEqual(doBefore.periodCounters);
    expect(Object.keys(doAfter.creditedRequests ?? {})).toEqual(
      Object.keys(doBefore.creditedRequests ?? {}),
    );
  });

  it("S11-014 — idempotent replay after Failed", async () => {
    const scenario = await setupFresh();
    const idempotencyKey = `s11-014-${crypto.randomUUID()}`;
    const { ref, requestId } = await failEmptyChain(
      scenario,
      idempotencyKey,
      "s11-014-orig",
    );
    const snapshot = await snapshotSettlement(requestId, ref);
    const doBefore = await inspectState(scenario.installationId);

    const replay = await postVisit(scenario, {
      idempotencyKey,
      traceId: "s11-014-replay",
    });
    assertHttpSse(replay);
    assertSseSequence(replay.events, ["accepted", "failed"]);
    const failed = replay.events.find((event) => event.event === "failed");
    assertTaxonomyBody(failed?.data, {
      code: "provider_unavailable",
      retry_safe: true,
    });
    const completed = replay.events.find((event) => event.event === "completed");
    expect(completed).toBeUndefined();
    const replayText = JSON.stringify(replay.events);
    expect(replayText).not.toContain("Prior request completed.");

    const after = await snapshotSettlement(requestId, ref);
    expect(after.attemptCount).toBe(snapshot.attemptCount);
    expect(after.usageCount).toBe(snapshot.usageCount);
    expect(after.envelopeJson).toBe(snapshot.envelopeJson);
    expect(after.rowJson).toBe(snapshot.rowJson);
    expect(after.row.terminal_error_code).toBe("provider_unavailable");

    const doAfter = await inspectState(scenario.installationId);
    expect(doAfter.periodCounters).toEqual(doBefore.periodCounters);
  });

  it("S11-015 — idempotent replay after Cancelled", async () => {
    const scenario = await setupFresh();
    const idempotencyKey = `s11-015-${crypto.randomUUID()}`;
    const { ref, requestId } = await cancelInFlight(
      scenario,
      idempotencyKey,
      "s11-015-orig",
    );
    const snapshot = await waitForStableCancelledSnapshot(requestId, ref);
    const doBefore = await inspectState(scenario.installationId);
    expect(doBefore.idempotency?.[idempotencyKey]?.state).toBe("cancelled");

    const fakeMod = await loadFakeModule();
    const replaySpy = vi.spyOn(fakeMod, "FakeAdapter");
    try {
      const replay = await postVisit(scenario, {
        idempotencyKey,
        traceId: "s11-015-replay",
      });
      assertHttpSse(replay);
      assertSseSequence(replay.events, ["accepted", "cancelled"], "exact");
      const cancelled = replay.events.find((event) => event.event === "cancelled");
      expect(cancelled?.data).toEqual({ trace_id: "s11-015-replay" });
      expect(Object.keys(cancelled?.data ?? {})).toEqual(["trace_id"]);
      expect(replaySpy).not.toHaveBeenCalled();
    } finally {
      replaySpy.mockRestore();
    }

    const after = await snapshotSettlement(requestId, ref);
    expect(after.attemptCount).toBe(snapshot.attemptCount);
    expect(after.usageCount).toBe(1);
    expect(after.envelopeJson).toBe(snapshot.envelopeJson);
    expect(after.rowJson).toBe(snapshot.rowJson);
    expect(after.row.state).toBe("Cancelled");
    expect(after.row.terminal_error_code).toBeNull();

    const doAfter = await inspectState(scenario.installationId);
    expect(doAfter.idempotency?.[idempotencyKey]?.state).toBe("cancelled");
    expect(doAfter.periodCounters).toEqual(doBefore.periodCounters);
  });

  it("S11-016 — usage_event quota_weight from Economics.quotaWeight", async () => {
    const heavyId = "clinic.visit_summary_heavy";
    const zeroId = "clinic.visit_summary_zero";
    const published = publishedVisitSummary as unknown as Record<
      string,
      unknown
    >;
    setCapabilityRegistry(
      createCapabilityRegistry([
        loadManifest(published),
        loadManifest(cloneVisitSummary(heavyId, 3)),
        loadManifest(cloneVisitSummary(zeroId, 0)),
      ]),
      { replace: true },
    );

    try {
      const entitle: EntitlePayload = {
        ...JULY_ENTITLE,
        allowed_capabilities: [heavyId, zeroId],
        grants: [
          {
            capability_id: heavyId,
            capability_version: CAPABILITY_VERSION,
            scope: "installation",
          },
          {
            capability_id: heavyId,
            capability_version: CAPABILITY_VERSION,
            scope: "plan",
          },
          {
            capability_id: zeroId,
            capability_version: CAPABILITY_VERSION,
            scope: "installation",
          },
          {
            capability_id: zeroId,
            capability_version: CAPABILITY_VERSION,
            scope: "plan",
          },
        ],
      };
      const scenario = await setupFresh({ entitle });

      const heavy = await completeHappyRequest(
        scenario,
        `s11-016-heavy-${crypto.randomUUID()}`,
        "s11-016-heavy",
        visitBody(scenario, { capability_id: heavyId }),
      );
      const heavyUsage = await getUsageEvents(heavy.requestId);
      expect(heavyUsage).toHaveLength(1);
      expect(heavyUsage[0]?.quota_weight).toBe(3);
      expect(heavyUsage[0]?.tokens).toBe(30);
      expect(costOf(heavyUsage[0], "cost")).toBeCloseTo(0.005, 5);
      expect(heavyUsage[0]?.period).toBe("2026-07");

      const afterHeavy = await inspectState(scenario.installationId);
      expect(afterHeavy.periodCounters?.requestsUsed).toBe(1);

      const zero = await completeHappyRequest(
        scenario,
        `s11-016-zero-${crypto.randomUUID()}`,
        "s11-016-zero",
        visitBody(scenario, { capability_id: zeroId }),
      );
      const zeroUsage = await getUsageEvents(zero.requestId);
      expect(zeroUsage).toHaveLength(1);
      // Number(0) || 1 fallback in buildPostResponseInput.
      expect(zeroUsage[0]?.quota_weight).toBe(1);
      expect(zeroUsage[0]?.tokens).toBe(30);
      expect(costOf(zeroUsage[0], "cost")).toBeCloseTo(0.005, 5);
      expect(zeroUsage[0]?.period).toBe("2026-07");

      const afterZero = await inspectState(scenario.installationId);
      expect(afterZero.periodCounters?.requestsUsed).toBe(2);
      expect(afterZero.periodCounters?.tokensUsed).toBe(60);
    } finally {
      restorePublishedRegistry();
    }
  });

  it("S11-017 — usage_event period from admission; DO reset on credit", async () => {
    const scenario = await setupFresh();
    const { requestId: httpRequestId } = await completeHappyRequest(
      scenario,
      `s11-017-a-${crypto.randomUUID()}`,
    );
    const httpUsage = await getUsageEvents(httpRequestId);
    expect(httpUsage).toHaveLength(1);
    expect(httpUsage[0]?.period).toBe("2026-07");
    expect(String(httpUsage[0]?.period).length).toBeLessThanOrEqual(7);

    const now = Date.now();
    const doRef = "7K2M-9XQD";
    const admitted = await gatewayObjectJson(
      scenario.installationId,
      {
        kind: "admission",
        jti: crypto.randomUUID(),
        installationId: scenario.installationId,
        idempotencyKey: `s11-017-do-${crypto.randomUUID()}`,
        requestReference: doRef,
        entitlement: entitlementSnapshot(PERIOD_A_START, PERIOD_A_END),
      },
      { now },
    );
    expect(admitted.status).toBe(200);
    const admittedBody = admitted.json as {
      kind?: string;
      outcome?: string;
      requestId?: string;
    };
    expect(admittedBody.kind).toBe("admission");
    expect(admittedBody.outcome).toBe("admitted");
    const doRequestId = String(admittedBody.requestId);
    expect(doRequestId.length).toBeGreaterThan(0);

    const afterAdmit = await inspectState(scenario.installationId, now);
    expect(afterAdmit.periodCounters?.inFlight).toBe(1);
    expect(afterAdmit.admittedRequests?.[doRequestId]).toBeDefined();

    const credit = await gatewayObjectJson(
      scenario.installationId,
      {
        kind: "credit",
        installationId: scenario.installationId,
        requestId: doRequestId,
        requestReference: doRef,
        usage: { tokens: 30, cost: 0.005 },
        partial: false,
        entitlement: entitlementSnapshot(PERIOD_B_START, PERIOD_B_END),
      },
      { now },
    );
    expect(credit.status).toBe(200);
    expect(credit.json).toMatchObject({ kind: "credit", ok: true });

    const afterCredit = await inspectState(scenario.installationId, now);
    expect(afterCredit.periodBounds).toEqual({
      period_start: PERIOD_B_START,
      period_end: PERIOD_B_END,
    });
    expect(afterCredit.periodCounters).toMatchObject({
      requestsUsed: 1,
      tokensUsed: 30,
      inFlight: 0,
    });
    expect(costOf(afterCredit.periodCounters, "costUsed")).toBeCloseTo(0.005, 5);

    const stillHttp = await getUsageEvents(httpRequestId);
    expect(stillHttp).toHaveLength(1);
    expect(stillHttp[0]?.period).toBe("2026-07");
    expect(await count("usage_event", "request_id = ?", [doRequestId])).toBe(0);
  });

  it("S11-018 — envelope attempts[] raw body capped at 16 KB", async () => {
    const scenario = await setupFresh();
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    // HARNESS-GAP: captureRawProviderBody is not on the barrel.
    const { captureRawProviderBody, ENVELOPE_RAW_BODY_BYTE_LIMIT } =
      await import("../../src/provider/raw-body");
    const oversized = "".padStart(40_000, "…");
    const inputBytes = new TextEncoder().encode(oversized);
    expect(inputBytes.byteLength).toBeGreaterThan(ENVELOPE_RAW_BODY_BYTE_LIMIT);
    const captured = captureRawProviderBody(oversized);
    expect(captured.truncated).toBe(true);
    expect(typeof captured.payload).toBe("string");
    const capturedPayload = String(captured.payload);
    expect(new TextEncoder().encode(capturedPayload).byteLength).toBeLessThanOrEqual(
      ENVELOPE_RAW_BODY_BYTE_LIMIT,
    );
    expect(capturedPayload.endsWith("\uFFFD")).toBe(false);
    class RawBodyFake extends original {
      override async invoke() {
        return {
          kind: "success" as const,
          result: fakeSuccessResult(),
          chunks: [
            {
              sequenceNumber: 0,
              kind: "text_delta",
              payload: { text: FAKE_SUMMARY },
              terminal: true,
            },
          ],
          rawBody: captured,
        };
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new RawBodyFake(["success"]) as never);
    try {
      const { requestId, ref } = await completeHappyRequest(
        scenario,
        `s11-018-${crypto.randomUUID()}`,
      );
      const row = await requireAiRequest(ref);
      const envelope = await getR2Json(String(row.payload_pointer));
      assertEnvelopeTopKeys(envelope);
      const attempts = envelope.attempts as EnvelopeAttempt[];
      expect(attempts).toHaveLength(1);
      expect(attempts[0]?.truncated).toBe(true);
      expect(typeof attempts[0]?.payload).toBe("string");
      const storedPayload = String(attempts[0]?.payload);
      expect(storedPayload).toBe(captured.payload);
      expect(new TextEncoder().encode(storedPayload).byteLength).toBeLessThanOrEqual(
        16384,
      );
      expect(storedPayload.endsWith("\uFFFD")).toBe(false);

      const attemptRows = await getAttempts(requestId);
      expect(attemptRows).toHaveLength(1);
      expect(attemptRows[0]).toMatchObject({
        outcome: "success",
        provider: "fake",
        model: "fake-v1",
        tokens_in: 10,
        tokens_out: 20,
      });
      expect(costOf(attemptRows[0], "cost")).toBeCloseTo(0.005, 5);
      expect(await r2Exists(`${envelopeKey(requestId)}-2`)).toBe(false);
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S11-019 — non-JSON provider raw body stored as string", async () => {
    const scenario = await setupFresh();
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    // HARNESS-GAP: captureRawProviderBody is not on the barrel.
    const { captureRawProviderBody } = await import("../../src/provider/raw-body");
    const rawText = "502 Bad Gateway\nupstream connect error";
    const captured = captureRawProviderBody(rawText);
    class RawBodyFake extends original {
      override async invoke() {
        return {
          kind: "success" as const,
          result: fakeSuccessResult(),
          chunks: [
            {
              sequenceNumber: 0,
              kind: "text_delta",
              payload: { text: FAKE_SUMMARY },
              terminal: true,
            },
          ],
          rawBody: captured,
        };
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new RawBodyFake(["success"]) as never);
    try {
      const { requestId, ref } = await completeHappyRequest(
        scenario,
        `s11-019-${crypto.randomUUID()}`,
      );
      const row = await requireAiRequest(ref);
      expect(row.state).toBe("Completed");
      const envelope = await getR2Json(String(row.payload_pointer));
      const attempts = envelope.attempts as EnvelopeAttempt[];
      expect(attempts[0]).toEqual({
        payload: rawText,
        truncated: false,
      });

      const attemptRows = await getAttempts(requestId);
      expect(attemptRows).toHaveLength(1);
      expect(attemptRows[0]?.outcome).toBe("success");
      const usage = await getUsageEvents(requestId);
      expect(usage).toHaveLength(1);
      expect(usage[0]?.tokens).toBe(30);
      expect(costOf(usage[0], "cost")).toBeCloseTo(0.005, 5);
      const inspected = await inspectState(scenario.installationId);
      expect(inspected.periodCounters).toMatchObject({
        requestsUsed: 1,
        tokensUsed: 30,
        inFlight: 0,
      });
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S11-020 — failed and cancelled envelopes carry placeholder result", async () => {
    const scenario = await setupFresh();

    const failedZero = await failEmptyChain(
      scenario,
      `s11-020-003-${crypto.randomUUID()}`,
    );
    const failedAccrued = await failTruncationExhausted(
      scenario,
      `s11-020-006-${crypto.randomUUID()}`,
    );
    const cancelled = await cancelInFlight(
      scenario,
      `s11-020-008-${crypto.randomUUID()}`,
    );

    const cases = [
      {
        label: "S11-003",
        requestId: failedZero.requestId,
        ref: failedZero.ref,
        totalTokens: 0,
        finishReason: "provider_unavailable",
        getState: "Failed" as const,
        terminal: "provider_unavailable",
      },
      {
        label: "S11-006",
        requestId: failedAccrued.requestId,
        ref: failedAccrued.ref,
        totalTokens: 30,
        finishReason: "validation_failed",
        getState: "Failed" as const,
        terminal: "validation_failed",
      },
      {
        label: "S11-008",
        requestId: cancelled.requestId,
        ref: cancelled.ref,
        totalTokens: 0,
        finishReason: "cancelled",
        getState: "Cancelled" as const,
        terminal: null,
      },
    ];

    const token = await mintAat(scenario);
    for (const testCase of cases) {
      const pointer = envelopeKey(testCase.requestId);
      expect(await r2Exists(pointer)).toBe(true);
      expect(await r2Exists(`${pointer}-failed`)).toBe(false);
      expect(await r2Exists(`request/${testCase.requestId}/envelope-failed`)).toBe(
        false,
      );

      const envelope = await getR2Json(pointer);
      assertEnvelopeTopKeys(envelope);
      assertPlaceholderResult(envelope.result as CanonicalResultShape, {
        totalTokens: testCase.totalTokens,
        finishReason: testCase.finishReason,
      });

      const row = await requireAiRequest(testCase.ref);
      expect(row.payload_pointer).toBe(pointer);

      const got = await getRequestByRef(token, testCase.ref);
      expect(got.status).toBe(200);
      const body = got.json as Record<string, unknown> | null;
      expect(body).not.toHaveProperty("result");
      if (testCase.getState === "Failed") {
        expect(body).toEqual({
          state: "Failed",
          terminal_error_code: testCase.terminal,
        });
      } else {
        expect(body).toEqual({ state: "Cancelled" });
      }
    }
  });

  it("S11-021 — grace-admitted settlement attaches usage despite DO outage", async () => {
    const scenario = await setupFresh();
    const grid = crypto.randomUUID();
    const ref = "7K2M-9XQD";
    const snapshot = entitlementSnapshot(PERIOD_START_JULY, PERIOD_END_COVERING_NOW);

    await seedSql([
      {
        sql: `INSERT INTO grace_admission_queue (
                grace_request_id, installation_id, idempotency_key, jti,
                request_reference, entitlement_json, usage_tokens, usage_cost,
                partial, queued_at, reconcile_attempts, reconcile_first_seen_at_ms,
                status
              ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, 0, NULL, 'pending')`,
        params: [
          grid,
          scenario.installationId,
          `s11-021-${crypto.randomUUID()}`,
          crypto.randomUUID(),
          ref,
          JSON.stringify(snapshot),
          new Date().toISOString(),
        ],
      },
    ]);

    const doBefore = await inspectState(scenario.installationId);
    // Catalog writes `{ fetchThrow: true }`; barrel types Error | (() => Error).
    const stubDown = wrapDurableObjectNamespace(env.DO, {
      fetchThrow: new Error("quota DO unavailable"),
    });
    const creditMod = await loadCreditModule();
    const usage = { tokens: 30, cost: 0.005 };

    const first = await creditMod.creditUsage(
      {
        installationId: scenario.installationId,
        requestId: grid,
        requestReference: ref,
        usage,
        partial: false,
        entitlement: snapshot as never,
      },
      { DO: stubDown, DB: env.DB },
    );
    expect(first).toEqual({ ok: false, code: "unavailable" });

    const attached = await queryOne<{
      usage_tokens: number;
      usage_cost: number;
      partial: number;
    }>(
      `SELECT usage_tokens, usage_cost, partial FROM grace_admission_queue
       WHERE grace_request_id = ?`,
      [grid],
    );
    expect(attached?.usage_tokens).toBe(30);
    expect(Number(attached?.usage_cost)).toBeCloseTo(0.005, 5);
    expect(attached?.partial).toBe(0);

    // Distinct payload so a silent request_reference miss cannot reuse the
    // first-call attach values.
    const fallbackUsage = { tokens: 8, cost: 0.0016 };
    const second = await creditMod.creditUsage(
      {
        installationId: scenario.installationId,
        requestId: crypto.randomUUID(),
        requestReference: ref,
        usage: fallbackUsage,
        partial: false,
        entitlement: snapshot as never,
      },
      { DO: stubDown, DB: env.DB },
    );
    expect(second).toEqual({ ok: false, code: "unavailable" });

    const attachedByRef = await queryOne<{
      usage_tokens: number;
      usage_cost: number;
      partial: number;
    }>(
      `SELECT usage_tokens, usage_cost, partial FROM grace_admission_queue
       WHERE request_reference = ?`,
      [ref],
    );
    expect(attachedByRef?.usage_tokens).toBe(8);
    expect(Number(attachedByRef?.usage_cost)).toBeCloseTo(0.0016, 5);
    expect(attachedByRef?.partial).toBe(0);

    const doAfterCredit = await inspectState(scenario.installationId);
    expect(doAfterCredit.periodCounters).toEqual(doBefore.periodCounters);

    const journal = await loadJournalModule();
    const created = await journal.createRequestRow(
      {
        requestId: grid,
        requestReference: ref,
        principal: {
          installationId: scenario.installationId,
          organizationId: scenario.orgId,
          branchId: scenario.branchId,
          actorId: scenario.actorId,
          role: "clinician",
          scopes: ["ai.visit_summary", "ai.access"],
          jti: crypto.randomUUID(),
          iat: 0,
          exp: 0,
          ver: "1",
        },
        manifest: loadManifest(
          publishedVisitSummary as unknown as Record<string, unknown>,
        ),
        idempotencyKey: `s11-021-journal-${crypto.randomUUID()}`,
        traceId: "s11-021-trace",
      },
      env.DB,
    );
    expect(created.ok).toBe(true);

    const pending: Promise<unknown>[] = [];
    // HARNESS-GAP: emptyExecutionContext.waitUntil is a no-op; drain locally.
    const ctx = {
      waitUntil(promise: Promise<unknown>) {
        pending.push(promise);
      },
      passThroughOnException() {},
      props: {},
    } as ExecutionContext;
    journal.writePostResponseDetail(
      {
        requestId: grid,
        installationId: scenario.installationId,
        period: "2026-07",
        quotaWeight: 1,
        totalTokens: 30,
        totalCost: 0.005,
        filteredContext: {
          "visit.chief_complaint@v1": { complaint: "Headache for three days." },
        },
        composedPrompt: {
          parts: [{ role: "user", content: "" }],
          formatDirective: {},
          samplingConstraints: {},
          maxOutputTokens: 1,
          stopConditions: [],
          toolDeclarations: [],
          stream: true,
          deadline: null,
          correlationIds: { request_reference: ref, trace_id: "s11-021-trace" },
        },
        attempts: [
          {
            attemptNo: 1,
            provider: "fake",
            model: "fake-v1",
            outcome: "success",
            latencyMs: 6,
            tokensIn: 10,
            tokensOut: 20,
            cost: 0.005,
            providerRequestId: "fake-req-001",
            rawBody: { payload: { fake: true, outcome: "success" }, truncated: false },
          },
        ],
        validatedResult: fakeSuccessResult(),
        recordedAt: new Date().toISOString(),
      },
      { db: env.DB, r2: env.R2, ctx },
    );
    await Promise.all(pending);
    await flushBackgroundWork(200);

    const attempts = await getAttempts(grid);
    expect(attempts).toHaveLength(1);
    expect(attempts[0]).toMatchObject({
      attempt_no: 1,
      provider: "fake",
      model: "fake-v1",
      outcome: "success",
    });
    const usageEvents = await getUsageEvents(grid);
    expect(usageEvents).toHaveLength(1);
    expect(usageEvents[0]?.tokens).toBe(30);
    expect(costOf(usageEvents[0], "cost")).toBeCloseTo(0.005, 5);
    expect(await r2Exists(envelopeKey(grid))).toBe(true);
    const row = await queryOne<Record<string, unknown>>(
      "SELECT payload_pointer FROM ai_request WHERE request_id = ?",
      [grid],
    );
    expect(row?.payload_pointer).toBe(envelopeKey(grid));
    expect(await count("usage_event", "request_id = ?", [grid])).toBe(1);
  });
});
