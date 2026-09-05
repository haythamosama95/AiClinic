import {
  afterEach,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";
import {
  assertRequestReferenceShape,
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clinicFetch,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  env,
  fakePolicyDocument,
  flushBackgroundWork,
  getAiRequest,
  getRequestByRef,
  getR2Json,
  mintAat,
  newScenario,
  parseSseText,
  POLICY_ID,
  POLICY_VERSION,
  postRequest,
  promotePolicy,
  provisionHappyPath,
  publishPolicy,
  queryOne,
  r2Exists,
  readHttpResult,
  resetE2eState,
  seedSql,
  visitSummaryInvokeBody,
  type HttpResult,
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

const NON_TERMINAL_STATES = new Set([
  "Accepted",
  "Composing",
  "Invoking",
  "Streaming",
  "Validating",
  "Repairing",
]);

const NORMALIZED_REF = "81S0-1MNP";
const NORMALIZED_PATH = "8iso-lmnp";
const AWAITING_REF = "3VBM-7KPD";
const BOGUS_REF = "6HND-4WQC";
const INFLIGHT_SEED_REF = "1NV0-K1NG";

type FakeModule = typeof import("../../src/provider/fake");

/**
 * HARNESS-GAP: FakeAdapter scripting is not on the frozen barrel; catalog
 * (Stage 11 §1 / S12-007, S12-009) documents vi.spyOn(fakeMod, "FakeAdapter").
 */
async function loadFakeModule(): Promise<FakeModule> {
  return import("../../src/provider/fake");
}

function assertEmpty404(result: HttpResult) {
  expect(result.status).toBe(404);
  expect(result.text).toBe("");
  expect(result.json).toBeNull();
}

function assertPlainNotFound(result: HttpResult) {
  expect(result.status).toBe(404);
  expect(result.text).toBe("Not Found");
}

function visitBody(scenario: Scenario): Record<string, unknown> {
  return visitSummaryInvokeBody(scenario);
}

async function enrollOnly(): Promise<Scenario> {
  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  return scenario;
}

async function setupFailedScenario(): Promise<Scenario> {
  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  const entitled = await entitleInstallation(scenario, DEFAULT_ENTITLE_PAYLOAD);
  expect(entitled.status).toBe(200);

  const baseline = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const publishedBaseline = await publishPolicy(
    POLICY_ID,
    POLICY_VERSION,
    baseline,
  );
  expect(publishedBaseline.status).toBe(200);
  const promotedBaseline = await promotePolicy(POLICY_ID, POLICY_VERSION);
  expect(promotedBaseline.status).toBe(200);

  const document = fakePolicyDocument(POLICY_ID, "2", {
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
  return scenario;
}

async function settleCompleted(): Promise<{
  scenario: Scenario;
  ref: string;
  requestId: string;
  pointer: string;
  lookup: HttpResult;
}> {
  const scenario = await provisionHappyPath();
  const result = await postRequest(scenario, {
    token: await mintAat(scenario),
    idempotencyKey: `s12-completed-${crypto.randomUUID()}`,
    body: visitBody(scenario),
  });
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
  expect(result.events.some((event) => event.event === "completed")).toBe(true);
  const ref = String(
    result.events.find((event) => event.event === "accepted")?.data
      .request_reference ?? "",
  );
  assertRequestReferenceShape(ref);
  await flushBackgroundWork(200);

  const row = await getAiRequest(ref);
  expect(row).not.toBeNull();
  expect(row?.state).toBe("Completed");
  const requestId = String(row!.request_id);
  const pointer = String(row!.payload_pointer);
  expect(pointer).toBe(`request/${requestId}/envelope`);
  expect(await r2Exists(pointer)).toBe(true);

  const lookup = await getRequestByRef(await mintAat(scenario), ref);
  return { scenario, ref, requestId, pointer, lookup };
}

function assertCanonicalCompletedBody(
  json: unknown,
  envelopeResult: unknown,
): void {
  expect(json).toEqual({ state: "Completed", result: envelopeResult });
  const body = json as Record<string, unknown>;
  expect(Object.keys(body).sort()).toEqual(["result", "state"]);
  expect(body.state).toBe("Completed");
  expect(body).not.toHaveProperty("attempts");
  expect(body).not.toHaveProperty("envelope");
  expect(body).not.toHaveProperty("request_id");
  expect(body).not.toHaveProperty("installation_id");

  const result = body.result as Record<string, unknown>;
  expect(result.finalContent).toBeDefined();
  const usage = result.usage as Record<string, unknown>;
  expect(usage).toEqual(
    expect.objectContaining({
      input: expect.any(Number),
      output: expect.any(Number),
      cached: expect.any(Number),
    }),
  );
  const providerModel = result.providerModel as Record<string, unknown>;
  expect(providerModel).toEqual(
    expect.objectContaining({
      provider: expect.any(String),
      model: expect.any(String),
    }),
  );
  expect(result.finishReason).toEqual(expect.any(String));
  expect(result.providerRequestId).toEqual(expect.any(String));
  const timing = result.timing as Record<string, unknown>;
  expect(timing).toEqual(
    expect.objectContaining({
      queue_ms: expect.any(Number),
      provider_ms: expect.any(Number),
      total_ms: expect.any(Number),
    }),
  );
}

async function settleFailed(): Promise<{ scenario: Scenario; ref: string }> {
  const scenario = await setupFailedScenario();
  const result = await postRequest(scenario, {
    token: await mintAat(scenario),
    idempotencyKey: `s12-failed-${crypto.randomUUID()}`,
    body: visitBody(scenario),
  });
  expect(result.status).toBe(200);
  const ref = String(
    result.events.find((event) => event.event === "accepted")?.data
      .request_reference ?? "",
  );
  assertRequestReferenceShape(ref);
  const failed = result.events.find((event) => event.event === "failed");
  expect(failed?.data.code).toBe("provider_unavailable");
  await flushBackgroundWork(200);
  const row = await getAiRequest(ref);
  expect(row?.state).toBe("Failed");
  expect(row?.terminal_error_code).toBe("provider_unavailable");
  return { scenario, ref };
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

async function cancelResponseBody(
  response: Response | undefined,
): Promise<void> {
  if (!response?.body) {
    return;
  }
  try {
    await response.body.cancel();
  } catch {
    // ignore
  }
}

async function settleAbortedFetch(
  fetchPromise: Promise<Response>,
): Promise<void> {
  let response: Response | undefined;
  try {
    response = await fetchPromise;
    if (response) {
      try {
        await response.text();
      } catch {
        // Client abort may tear the body down before it can be read.
      }
    }
  } catch {
    // Client abort may reject the fetch.
  } finally {
    await cancelResponseBody(response);
  }
}

/**
 * Keep reading SSE without cancelling on a stop predicate. `readSseUntil`
 * cancels the reader in `finally`, which would settle Cancelled before GET.
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

async function seedAiRequest(opts: {
  scenario: Scenario;
  requestId: string;
  requestReference: string;
  state: string;
  idempotencyKey: string;
  traceId: string;
}): Promise<void> {
  const now = new Date().toISOString();
  await seedSql([
    {
      sql: `INSERT INTO ai_request (
              request_id, request_reference, installation_id, actor_id, branch_id,
              capability_id, capability_version, prompt_artifact_hash, idempotency_key,
              state, created_at, updated_at, completed_at, terminal_error_code,
              trace_id, payload_pointer
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, NULL)`,
      params: [
        opts.requestId,
        opts.requestReference,
        opts.scenario.installationId,
        opts.scenario.actorId,
        opts.scenario.branchId,
        CAPABILITY_ID,
        CAPABILITY_VERSION,
        "s12-seed-prompt-hash",
        opts.idempotencyKey,
        opts.state,
        now,
        now,
        opts.traceId,
      ],
    },
  ]);
}

function assertPendingLookup(json: unknown): void {
  expect(json).toEqual(
    expect.objectContaining({
      pending: true,
      state: expect.any(String),
    }),
  );
  const body = json as { state: string; pending: boolean };
  expect(body.pending).toBe(true);
  expect(NON_TERMINAL_STATES.has(body.state)).toBe(true);
  expect(Object.keys(body).sort()).toEqual(["pending", "state"]);
}

describe("Stage 12 — GET /v1/requests lookup (S12-001…S12-018)", () => {
  it("S12-001 — GET Completed returns R2 envelope result", async () => {
    const { ref, pointer, lookup } = await settleCompleted();

    expect(lookup.status).toBe(200);
    const envelope = await getR2Json(pointer);
    assertCanonicalCompletedBody(lookup.json, envelope.result);

    const after = await getAiRequest(ref);
    expect(after?.state).toBe("Completed");
    expect(await r2Exists(pointer)).toBe(true);
  });

  it("S12-002 — GET Completed with NULL payload_pointer omits result", async () => {
    const { scenario, ref } = await settleCompleted();

    // [SEED] NULL-pointer branch is unreachable on a settled row because
    // persistPostResponseDetail always writes the pointer.
    await seedSql([
      {
        sql: "UPDATE ai_request SET payload_pointer = NULL WHERE request_reference = ?",
        params: [ref],
      },
    ]);

    const got = await getRequestByRef(await mintAat(scenario), ref);
    expect(got.status).toBe(200);
    expect(got.json).toEqual({ state: "Completed" });
    expect(got.json as Record<string, unknown>).not.toHaveProperty("result");
  });

  it("S12-003 — GET Completed with missing R2 object omits result", async () => {
    const { scenario, ref, pointer } = await settleCompleted();

    // [SEED] R2 delete while leaving payload_pointer set (retention race).
    await env.R2.delete(pointer);
    expect(await r2Exists(pointer)).toBe(false);

    const got = await getRequestByRef(await mintAat(scenario), ref);
    expect(got.status).toBe(200);
    expect(got.json).toEqual({ state: "Completed" });
    expect(got.json as Record<string, unknown>).not.toHaveProperty("result");
  });

  it("S12-004 — GET Completed with corrupt envelope JSON omits result", async () => {
    const { scenario, ref, pointer } = await settleCompleted();

    // [SEED] overwrite envelope bytes to cover JSON.parse throw → resultMissing.
    await env.R2.put(pointer, "not-json{");

    const got = await getRequestByRef(await mintAat(scenario), ref);
    expect(got.status).toBe(200);
    expect(got.json).toEqual({ state: "Completed" });
    expect(got.json as Record<string, unknown>).not.toHaveProperty("result");
  });

  it("S12-005 — GET Failed returns terminal_error_code", async () => {
    const { scenario, ref } = await settleFailed();

    const got = await getRequestByRef(await mintAat(scenario), ref);
    expect(got.status).toBe(200);
    expect(got.json).toEqual({
      state: "Failed",
      terminal_error_code: "provider_unavailable",
    });
  });

  it("S12-006 — GET Failed with NULL terminal_error_code falls back to internal_error", async () => {
    const { scenario, ref } = await settleFailed();

    // [SEED] C3-R3 makes Failed-without-code unreachable through the pipeline.
    await seedSql([
      {
        sql: "UPDATE ai_request SET terminal_error_code = NULL WHERE request_reference = ?",
        params: [ref],
      },
    ]);

    const got = await getRequestByRef(await mintAat(scenario), ref);
    expect(got.status).toBe(200);
    expect(got.json).toEqual({
      state: "Failed",
      terminal_error_code: "internal_error",
    });
  });

  it("S12-007 — GET Cancelled", async () => {
    const scenario = await provisionHappyPath();
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    class HangFake extends original {
      override async invoke(
        _request: unknown,
        options?: { signal?: AbortSignal },
      ) {
        await hangUntilAbort(options?.signal, 5000);
        return super.invoke(_request as never, options as never);
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new HangFake(["success"]) as never);
    const controller = new AbortController();

    try {
      const token = await mintAat(scenario);
      const fetchPromise = clinicFetch("/v1/requests", {
        method: "POST",
        token,
        headers: {
          "x-idempotency-key": `s12-007-${crypto.randomUUID()}`,
          "x-capability-version": CAPABILITY_VERSION,
        },
        body: visitBody(scenario),
        signal: controller.signal,
      });
      await waitForLatestRequestRow(scenario.installationId);
      controller.abort();
      await settleAbortedFetch(fetchPromise);
      await flushBackgroundWork(350);

      const row = await waitForLatestRequestState(
        scenario.installationId,
        "Cancelled",
      );
      expect(row.terminal_error_code).toBeNull();
      const ref = String(row.request_reference);
      assertRequestReferenceShape(ref);

      const got = await getRequestByRef(await mintAat(scenario), ref);
      expect(got.status).toBe(200);
      expect(got.json).toEqual({ state: "Cancelled" });
    } finally {
      adapterSpy.mockRestore();
    }
  });

  it("S12-008 — GET AwaitingContext", async () => {
    const scenario = await enrollOnly();

    // [SEED] AwaitingContext is conversational-only; the published manifest is
    // single_shot so no live pipeline can produce this state.
    await seedAiRequest({
      scenario,
      requestId: "01JZS12AWAIT0000000000008",
      requestReference: AWAITING_REF,
      state: "AwaitingContext",
      idempotencyKey: "idem-s12-008",
      traceId: "01JZS12TRCE000000000000008",
    });

    const got = await getRequestByRef(await mintAat(scenario), AWAITING_REF);
    expect(got.status).toBe(200);
    expect(got.json).toEqual({ state: "AwaitingContext" });
  });

  it("S12-009 — GET in-flight request returns pending:true", async () => {
    // Register 5 #10: live in-flight race — implement, do not skip. Prefer
    // POST → accepted → GET before settlement; hang FakeAdapter so the window
    // is deterministic. [SEED] state='Invoking' is the catalog-justified
    // fallback if the live GET already settled.
    const scenario = await provisionHappyPath();
    const fakeMod = await loadFakeModule();
    const original = fakeMod.FakeAdapter;
    class HangFake extends original {
      override async invoke(
        _request: unknown,
        options?: { signal?: AbortSignal },
      ) {
        await hangUntilAbort(options?.signal, 8000);
        return super.invoke(_request as never, options as never);
      }
    }
    const adapterSpy = vi
      .spyOn(fakeMod, "FakeAdapter")
      .mockImplementation(() => new HangFake(["success"]) as never);
    const controller = new AbortController();
    let pump: ReturnType<typeof startSsePump> | undefined;
    let response: Response | undefined;

    try {
      const token = await mintAat(scenario);
      response = await clinicFetch("/v1/requests", {
        method: "POST",
        token,
        headers: {
          "x-idempotency-key": `s12-009-${crypto.randomUUID()}`,
          "x-capability-version": CAPABILITY_VERSION,
        },
        body: visitBody(scenario),
        signal: controller.signal,
      });
      expect(response.status).toBe(200);
      pump = startSsePump(response);
      await waitFor("accepted SSE", () =>
        pump!.events().some((event) => event.event === "accepted"),
      );
      const ref = String(
        pump
          .events()
          .find((event) => event.event === "accepted")?.data.request_reference ??
          "",
      );
      assertRequestReferenceShape(ref);

      const live = await getRequestByRef(await mintAat(scenario), ref);
      if (
        live.status === 200 &&
        live.json !== null &&
        typeof live.json === "object" &&
        (live.json as { pending?: unknown }).pending === true
      ) {
        assertPendingLookup(live.json);
        return;
      }

      // [SEED] catalog-justified fallback: live GET already left the
      // non-terminal window (Register 5 #10 / S12-009 Journey setup).
      await seedAiRequest({
        scenario,
        requestId: "01JZS12INVOK0000000000009",
        requestReference: INFLIGHT_SEED_REF,
        state: "Invoking",
        idempotencyKey: "idem-s12-009",
        traceId: "01JZS12NVK0000000000000009",
      });
      const seeded = await getRequestByRef(
        await mintAat(scenario),
        INFLIGHT_SEED_REF,
      );
      expect(seeded.status).toBe(200);
      expect(seeded.json).toEqual({ state: "Invoking", pending: true });
    } finally {
      controller.abort();
      await pump?.close();
      await cancelResponseBody(response);
      adapterSpy.mockRestore();
    }
  });

  it("S12-010 — GET row with unknown state string returns 404", async () => {
    const scenario = await enrollOnly();

    // [SEED] covers the defensive isTransitionState guard; unreachable through
    // journalTransition / recordTerminalState.
    await seedAiRequest({
      scenario,
      requestId: "01JZS12BOGUS0000000000010",
      requestReference: BOGUS_REF,
      state: "Bogus",
      idempotencyKey: "idem-s12-010",
      traceId: "01JZS12BGS0000000000000010",
    });

    const got = await getRequestByRef(await mintAat(scenario), BOGUS_REF);
    assertEmpty404(got);
  });

  it("S12-011 — GET unknown well-formed reference returns empty 404", async () => {
    const scenario = await enrollOnly();
    const got = await getRequestByRef(await mintAat(scenario), "AAAA-BBBB");
    assertEmpty404(got);
  });

  it("S12-012 — GET malformed reference returns empty 404", async () => {
    const scenario = await enrollOnly();
    const got = await getRequestByRef(await mintAat(scenario), "SHORT");
    assertEmpty404(got);
  });

  it("S12-013 — GET /v1/requests/ empty reference 404 before auth", async () => {
    const response = await clinicFetch("/v1/requests/");
    const got = await readHttpResult(response);
    assertEmpty404(got);
  });

  it("S12-014 — GET /v1/requests no trailing slash Not Found", async () => {
    const scenario = await enrollOnly();
    const response = await clinicFetch("/v1/requests", {
      token: await mintAat(scenario),
    });
    const got = await readHttpResult(response);
    assertPlainNotFound(got);
  });

  it("S12-015 — GET reference normalization", async () => {
    const { scenario, ref, requestId, pointer, lookup } =
      await settleCompleted();
    expect(lookup.status).toBe(200);
    const envelope = await getR2Json(pointer);

    // [SEED] minting is random; pin a reference that exercises I/L/O mapping.
    const occupant = await getAiRequest(NORMALIZED_REF);
    if (occupant && String(occupant.request_id) !== requestId) {
      await seedSql([
        {
          sql: "UPDATE ai_request SET request_reference = ? WHERE request_id = ?",
          params: [`TMP0-${ref.slice(0, 4)}`, occupant.request_id],
        },
      ]);
    }
    await seedSql([
      {
        sql: "UPDATE ai_request SET request_reference = ? WHERE request_id = ?",
        params: [NORMALIZED_REF, requestId],
      },
    ]);

    const got = await getRequestByRef(await mintAat(scenario), NORMALIZED_PATH);
    expect(got.status).toBe(200);
    assertCanonicalCompletedBody(got.json, envelope.result);
    expect(got.json).toEqual(lookup.json);
  });

  it("S12-016 — GET whitespace-padded path 404", async () => {
    const { scenario, ref } = await settleCompleted();

    const response = await clinicFetch(`/v1/requests/%20${ref}`, {
      token: await mintAat(scenario),
    });
    const got = await readHttpResult(response);
    assertEmpty404(got);
  });

  it("S12-017 — Cross-installation GET empty 404", async () => {
    const { ref } = await settleCompleted();
    const other = await enrollOnly();

    const got = await getRequestByRef(await mintAat(other), ref);
    assertEmpty404(got);
  });

  it("S12-018 — Non-GET method on /v1/requests/{ref} Not Found", async () => {
    const { scenario, ref } = await settleCompleted();
    const posted = await readHttpResult(
      await clinicFetch(`/v1/requests/${ref}`, {
        method: "POST",
        token: await mintAat(scenario),
        body: {},
      }),
    );
    assertPlainNotFound(posted);

    const deleted = await readHttpResult(
      await clinicFetch(`/v1/requests/${ref}`, {
        method: "DELETE",
        token: await mintAat(scenario),
      }),
    );
    assertPlainNotFound(deleted);
  });
});
