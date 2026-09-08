/**
 * Stage 12 support lookup — S12-041…S12-055 (`POST /control/support/lookup`).
 *
 * Register 5 #2 `500 missing_r2_binding` has no S12 catalog ID (non-automatable
 * note only; same `dispatchControlRequest` seam as S03-083). Not implemented —
 * do not invent an extra scenario ID.
 */
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
  controlFetch,
  count,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  env,
  flushBackgroundWork,
  getAiRequest,
  getAttempts,
  getRequestByRef,
  getR2Json,
  getRoutingPolicy,
  isolateConfigCache,
  mintAat,
  newScenario,
  parseSseText,
  POLICY_ID,
  POLICY_REF,
  POLICY_VERSION,
  postRequest,
  provisionHappyPath,
  r2Exists,
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

const STORED_AMBIGUOUS_REF = "81S0-1MNP";
const PADDED_AMBIGUOUS_QUERY = " 8iso-lmnp ";
const UNKNOWN_WELL_FORMED_REF = "AAAA-BBBB";
const IN_FLIGHT_SEED_REF = "4NFR-8WQX";
const NON_TERMINAL_STATES = new Set([
  "Accepted",
  "Composing",
  "Invoking",
  "Streaming",
  "Validating",
  "Repairing",
]);
const LOOKUP_BODY_KEYS = ["attempts", "envelope", "request"] as const;
const REQUEST_TRACE_KEYS = [
  "actorId",
  "branchId",
  "capabilityId",
  "capabilityVersion",
  "completedAt",
  "createdAt",
  "installationId",
  "payloadPointer",
  "promptArtifactHash",
  "requestId",
  "requestReference",
  "state",
  "terminalErrorCode",
  "traceId",
  "updatedAt",
] as const;
const ATTEMPT_TRACE_KEYS = [
  "attemptNo",
  "cost",
  "errorCode",
  "latencyMs",
  "model",
  "outcome",
  "provider",
  "providerRequestId",
  "tokensIn",
  "tokensOut",
] as const;
const ENVELOPE_KEYS = ["attempts", "context", "prompt", "result"] as const;

type LookupRequest = {
  requestId: string;
  requestReference: string;
  installationId: string;
  actorId: string;
  branchId: string | null;
  capabilityId: string;
  capabilityVersion: string;
  promptArtifactHash: string;
  state: string;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
  terminalErrorCode: string | null;
  traceId: string;
  payloadPointer: string | null;
};

type LookupAttempt = {
  attemptNo: number;
  provider: string;
  model: string;
  outcome: string;
  latencyMs: number;
  tokensIn: number;
  tokensOut: number;
  cost: number;
  providerRequestId: string | null;
  errorCode: string | null;
};

type LookupEnvelope = {
  context: Record<string, unknown>;
  prompt: unknown;
  attempts: unknown[];
  result: unknown;
};

type LookupBody = {
  request: LookupRequest;
  attempts: LookupAttempt[];
  envelope: LookupEnvelope | null;
};

type Settled = {
  scenario: Scenario;
  token: string;
  ref: string;
  rid: string;
  row: Record<string, unknown>;
};

function lookupPath(reference?: string): string {
  if (reference === undefined) {
    return "/control/support/lookup";
  }
  return `/control/support/lookup?reference=${encodeURIComponent(reference)}`;
}

async function supportLookup(
  reference: string,
  options: Parameters<typeof controlFetch>[1] = {},
): Promise<HttpResult> {
  return controlFetch(lookupPath(reference), {
    method: "POST",
    ...options,
  });
}

function assertControlError(
  result: HttpResult,
  status: number,
  error: string,
): void {
  expect(result.status).toBe(status);
  expect(result.text).toBe(JSON.stringify({ error }));
  expect(result.json).toEqual({ error });
}

function asLookupBody(json: unknown): LookupBody {
  expect(json).toEqual(expect.any(Object));
  return json as LookupBody;
}

function envelopeKey(requestId: string): string {
  return `request/${requestId}/envelope`;
}

/**
 * Pool TTL is 100 ms. Parallel files share isolateConfigCache and call
 * clear(); preload→consult can then miss
 * `active_routing_policy:routing/standard` (ConfigCacheMissError → Failed,
 * no SSE `completed`). Raise TTL and re-stamp the promoted policy from
 * D1+R2 immediately before every clinic POST so the post-accept consult
 * cannot miss.
 */
const SERVE_CACHE_TTL_MS = 30_000;

async function loadServingPolicyRow(): Promise<Record<string, unknown>> {
  const row = await getRoutingPolicy(POLICY_ID, POLICY_VERSION);
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

type FakeModule = typeof import("../../src/provider/fake");

/**
 * HARNESS-GAP: FakeAdapter scripting is not on the frozen barrel; catalog
 * (Stage 11 §1 / S12-009, S12-050) documents vi.spyOn(fakeMod, "FakeAdapter").
 */
async function loadFakeModule(): Promise<FakeModule> {
  return import("../../src/provider/fake");
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

/**
 * Keep reading SSE without cancelling on a stop predicate. Cancelling the
 * reader would settle Cancelled before support lookup can observe in-flight.
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

async function settleCompleted(): Promise<Settled> {
  const scenario = await newScenario();
  await provisionHappyPath(scenario, DEFAULT_ENTITLE_PAYLOAD);
  const policyRow = await loadServingPolicyRow();
  const token = await mintAat(scenario);
  pinServingRoutingPolicy(policyRow, [scenario.installationId]);
  const posted = await postRequest(scenario, {
    token,
    idempotencyKey: crypto.randomUUID(),
    body: visitSummaryInvokeBody(scenario),
  });
  await flushBackgroundWork(200);

  expect(posted.status).toBe(200);
  const accepted = posted.events.find((event) => event.event === "accepted");
  const ref = String(accepted?.data.request_reference ?? "");
  assertRequestReferenceShape(ref);
  expect(posted.events.some((event) => event.event === "completed")).toBe(true);

  const row = await getAiRequest(ref);
  expect(row).not.toBeNull();
  expect(row!.state).toBe("Completed");
  const rid = String(row!.request_id);
  return { scenario, token, ref, rid, row: row! };
}

function assertRequestTrace(
  request: LookupRequest,
  settled: Pick<Settled, "scenario" | "ref" | "rid" | "row">,
  overrides: Partial<LookupRequest> = {},
): void {
  expect(Object.keys(request).sort()).toEqual([...REQUEST_TRACE_KEYS]);
  expect(request.requestId).toBe(overrides.requestId ?? settled.rid);
  expect(request.requestReference).toBe(
    overrides.requestReference ?? settled.ref,
  );
  expect(request.installationId).toBe(
    overrides.installationId ?? settled.scenario.installationId,
  );
  expect(request.actorId).toBe(String(settled.row.actor_id));
  expect(request.branchId).toBe(
    settled.row.branch_id === null ? null : String(settled.row.branch_id),
  );
  expect(request.capabilityId).toBe(CAPABILITY_ID);
  expect(request.capabilityVersion).toBe(CAPABILITY_VERSION);
  expect(request.promptArtifactHash).toBe(
    String(settled.row.prompt_artifact_hash),
  );
  expect(request.state).toBe(overrides.state ?? "Completed");
  expect(request.createdAt).toBe(String(settled.row.created_at));
  expect(request.updatedAt).toBe(String(settled.row.updated_at));
  if (overrides.completedAt !== undefined) {
    expect(request.completedAt).toBe(overrides.completedAt);
  } else {
    expect(request.completedAt).toBe(String(settled.row.completed_at));
  }
  expect(request.terminalErrorCode).toBe(
    settled.row.terminal_error_code === undefined
      ? null
      : (settled.row.terminal_error_code as string | null),
  );
  expect(request.traceId).toBe(String(settled.row.trace_id));
  if (overrides.payloadPointer !== undefined) {
    expect(request.payloadPointer).toBe(overrides.payloadPointer);
  } else {
    expect(request.payloadPointer).toBe(envelopeKey(settled.rid));
  }
}

function assertAttemptTrace(
  attempt: LookupAttempt,
  d1Row: Record<string, unknown>,
): void {
  expect(Object.keys(attempt).sort()).toEqual([...ATTEMPT_TRACE_KEYS]);
  expect(attempt.attemptNo).toBe(1);
  expect(attempt.provider).toBe(String(d1Row.provider));
  expect(attempt.model).toBe(String(d1Row.model));
  expect(attempt.outcome).toBe(String(d1Row.outcome));
  expect(attempt.latencyMs).toBe(Number(d1Row.latency_ms));
  expect(attempt.tokensIn).toBe(Number(d1Row.tokens_in));
  expect(attempt.tokensOut).toBe(Number(d1Row.tokens_out));
  expect(Number(attempt.cost)).toBeCloseTo(Number(d1Row.cost), 6);
  expect(attempt.providerRequestId).toBe(
    d1Row.provider_request_id === null
      ? null
      : String(d1Row.provider_request_id),
  );
  expect(attempt.errorCode).toBe(
    d1Row.error_code === null ? null : (d1Row.error_code as string | null),
  );
}

async function assertHappyLookupBody(
  result: HttpResult,
  settled: Settled,
  options: {
    requestReference?: string;
    envelope?: "present" | "null";
    payloadPointer?: string | null;
    clinicResult?: unknown;
  } = {},
): Promise<LookupBody> {
  expect(result.status).toBe(200);
  const body = asLookupBody(result.json);
  expect(Object.keys(body).sort()).toEqual([...LOOKUP_BODY_KEYS]);

  const row = await getAiRequest(options.requestReference ?? settled.ref);
  expect(row).not.toBeNull();
  const current: Settled = { ...settled, row: row!, ref: options.requestReference ?? settled.ref };

  assertRequestTrace(body.request, current, {
    requestReference: options.requestReference,
    payloadPointer: options.payloadPointer,
  });

  const d1Attempts = await getAttempts(settled.rid);
  expect(body.attempts).toHaveLength(d1Attempts.length);
  expect(body.attempts.length).toBeGreaterThanOrEqual(1);
  assertAttemptTrace(body.attempts[0], d1Attempts[0]);

  if (options.envelope === "null") {
    expect(body.envelope).toBeNull();
    return body;
  }

  expect(body.envelope).not.toBeNull();
  expect(Object.keys(body.envelope!).sort()).toEqual([...ENVELOPE_KEYS]);
  const stored = await getR2Json(envelopeKey(settled.rid));
  expect(body.envelope).toEqual(stored);
  if (options.clinicResult !== undefined) {
    expect(body.envelope!.result).toEqual(options.clinicResult);
  }
  return body;
}

function isCatalogInFlight(body: LookupBody): boolean {
  return (
    NON_TERMINAL_STATES.has(body.request.state) &&
    body.request.completedAt === null &&
    body.request.payloadPointer === null &&
    Array.isArray(body.attempts) &&
    body.attempts.length === 0 &&
    body.envelope === null
  );
}

async function seedInvokingRow(scenario: Scenario): Promise<{
  ref: string;
  rid: string;
}> {
  const rid = crypto.randomUUID();
  const now = new Date().toISOString();
  await seedSql([
    {
      sql: `INSERT INTO ai_request (
              request_id, request_reference, installation_id, actor_id, branch_id,
              capability_id, capability_version, prompt_artifact_hash, idempotency_key,
              trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
              payload_pointer
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL)`,
      params: [
        rid,
        IN_FLIGHT_SEED_REF,
        scenario.installationId,
        scenario.actorId,
        scenario.branchId,
        CAPABILITY_ID,
        CAPABILITY_VERSION,
        "seed-s12-050-prompt-hash",
        `idem-s12-050-${rid}`,
        `trace-s12-050-${rid}`,
        "Invoking",
        now,
        now,
      ],
    },
  ]);
  return { ref: IN_FLIGHT_SEED_REF, rid };
}

describe("Stage 12 — support lookup (S12-041…S12-055)", () => {
  it("S12-041 — Support lookup happy path returns every field", async () => {
    const settled = await settleCompleted();
    const clinic = await getRequestByRef(settled.token, settled.ref);
    expect(clinic.status).toBe(200);
    const clinicBody = clinic.json as { state?: string; result?: unknown };
    expect(clinicBody.state).toBe("Completed");

    const auditBefore = await count("control_audit");
    const result = await supportLookup(settled.ref);
    await assertHappyLookupBody(result, settled, {
      clinicResult: clinicBody.result,
    });
    expect(await count("control_audit")).toBe(auditBefore);
  });

  it("S12-042 — Support lookup trims then normalizes mixed-case ambiguous refs", async () => {
    const settled = await settleCompleted();
    // [SEED] pin a reference that contains 1/0 so I/L/O + case + trim can be shown.
    // Clinic GET does not trim (S12-016); lookup does (this scenario).
    await seedSql([
      {
        sql: "UPDATE ai_request SET request_reference = ? WHERE request_id = ?",
        params: [STORED_AMBIGUOUS_REF, settled.rid],
      },
    ]);

    const result = await supportLookup(PADDED_AMBIGUOUS_QUERY);
    const clinic = await getRequestByRef(settled.token, STORED_AMBIGUOUS_REF);
    const clinicBody = clinic.json as { result?: unknown };
    await assertHappyLookupBody(result, settled, {
      requestReference: STORED_AMBIGUOUS_REF,
      clinicResult: clinicBody.result,
    });
  });

  it("S12-043 — Support lookup without operator bearer returns 401 unauthorized", async () => {
    const settled = await settleCompleted();
    const result = await supportLookup(settled.ref, { auth: "none" });
    assertControlError(result, 401, "unauthorized");
  });

  it("S12-044 — Support lookup with wrong bearer or clinic AAT returns 401", async () => {
    const settled = await settleCompleted();
    const aat = await mintAat(settled.scenario);

    const wrong = await supportLookup(settled.ref, { auth: "wrong" });
    assertControlError(wrong, 401, "unauthorized");

    const clinicAsOperator = await supportLookup(settled.ref, {
      auth: { bearer: aat },
    });
    assertControlError(clinicAsOperator, 401, "unauthorized");
  });

  it("S12-045 — Support lookup without reference param returns 400 missing_reference", async () => {
    const result = await controlFetch("/control/support/lookup", {
      method: "POST",
    });
    assertControlError(result, 400, "missing_reference");
  });

  it("S12-046 — Support lookup with blank or whitespace reference returns 400", async () => {
    const empty = await controlFetch("/control/support/lookup?reference=", {
      method: "POST",
    });
    assertControlError(empty, 400, "missing_reference");

    const whitespace = await controlFetch(
      "/control/support/lookup?reference=%20%20",
      { method: "POST" },
    );
    assertControlError(whitespace, 400, "missing_reference");
  });

  it("S12-047 — Support lookup with malformed reference returns 400 invalid_reference", async () => {
    for (const reference of ["SHORT", "AAAA-BBB", "AAAA-BBBBB", "AAAA!BBBB"]) {
      const result = await supportLookup(reference);
      assertControlError(result, 400, "invalid_reference");
    }
  });

  it("S12-048 — Support lookup with unknown well-formed reference returns 404", async () => {
    const result = await supportLookup(UNKNOWN_WELL_FORMED_REF);
    assertControlError(result, 404, "not_found");
  });

  it("S12-049 — Support lookup reads across installations", async () => {
    const settled = await settleCompleted();
    const other = await newScenario();
    const enrolled = await enrollInstallation(other);
    expect(enrolled.status).toBe(200);

    // [SEED] retarget the settled row at I1. FK must exist (enroll first).
    // Lookup SQL has no installation predicate (unlike clinic GET S12-017).
    await seedSql([
      {
        sql: "UPDATE ai_request SET installation_id = ? WHERE request_reference = ?",
        params: [other.installationId, settled.ref],
      },
    ]);

    const result = await supportLookup(settled.ref);
    expect(result.status).toBe(200);
    const body = asLookupBody(result.json);
    expect(body.request.installationId).toBe(other.installationId);

    await seedSql([
      {
        sql: "UPDATE ai_request SET installation_id = ? WHERE request_reference = ?",
        params: [settled.scenario.installationId, settled.ref],
      },
    ]);
  });

  it("S12-050 — Support lookup of in-flight request returns empty attempts and null envelope", async () => {
    // Register 5 #10 / S12-009: live in-flight race — prefer POST → accepted
    // → lookup before settlement; hang FakeAdapter so the window is
    // deterministic. [SEED] state='Invoking' is the catalog-justified
    // fallback if the live lookup already settled.
    const scenario = await newScenario();
    await provisionHappyPath(scenario, DEFAULT_ENTITLE_PAYLOAD);
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
      const policyRow = await loadServingPolicyRow();
      const token = await mintAat(scenario);
      pinServingRoutingPolicy(policyRow, [scenario.installationId]);
      response = await clinicFetch("/v1/requests", {
        method: "POST",
        token,
        headers: {
          "x-idempotency-key": `s12-050-${crypto.randomUUID()}`,
          "x-capability-version": CAPABILITY_VERSION,
        },
        body: visitSummaryInvokeBody(scenario),
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

      let result: HttpResult | null = null;
      let body: LookupBody | null = null;
      const live = await supportLookup(ref);
      if (live.status === 200) {
        result = live;
        body = asLookupBody(live.json);
      }

      if (!result || !body || !isCatalogInFlight(body)) {
        // [SEED] catalog-justified fallback: live lookup already left the
        // non-terminal window (Register 5 #10 / S12-050 Journey setup).
        const seeded = await seedInvokingRow(scenario);
        result = await supportLookup(seeded.ref);
        expect(result.status).toBe(200);
        body = asLookupBody(result.json);
      }

      expect(result.status).toBe(200);
      expect(Object.keys(body).sort()).toEqual([...LOOKUP_BODY_KEYS]);
      expect(NON_TERMINAL_STATES.has(body.request.state)).toBe(true);
      expect(body.request.completedAt).toBeNull();
      expect(body.request.payloadPointer).toBeNull();
      expect(body.attempts).toEqual([]);
      expect(body.envelope).toBeNull();
    } finally {
      controller.abort();
      await pump?.close();
      await cancelResponseBody(response);
      adapterSpy.mockRestore();
    }
  });

  it("S12-051 — Support lookup outside diagnostic retention returns null envelope", async () => {
    const settled = await settleCompleted();
    const aged = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();
    // [SEED] age the row past diagnostic_30d. R2 object is left in place.
    await seedSql([
      {
        sql: `UPDATE ai_request
              SET completed_at = ?, created_at = ?
              WHERE request_reference = ?`,
        params: [aged, aged, settled.ref],
      },
    ]);
    expect(await r2Exists(envelopeKey(settled.rid))).toBe(true);

    const result = await supportLookup(settled.ref);
    await assertHappyLookupBody(result, settled, { envelope: "null" });
    // HARNESS-GAP: no R2 get spy on the frozen barrel, so "no R2 get" cannot
    // be asserted directly. Envelope null plus the object still existing is
    // the observable contract (retention gate skips the read).
  });

  it("S12-052 — Support lookup falls back to derived envelope key when payload_pointer is NULL", async () => {
    const settled = await settleCompleted();
    // [SEED] NULL the pointer while leaving R2 at request/{RID}/envelope.
    // Contrast S12-002: clinic GET omits result when the pointer is NULL
    // (not asserted here).
    await seedSql([
      {
        sql: "UPDATE ai_request SET payload_pointer = NULL WHERE request_reference = ?",
        params: [settled.ref],
      },
    ]);
    expect(await r2Exists(envelopeKey(settled.rid))).toBe(true);

    const result = await supportLookup(settled.ref);
    await assertHappyLookupBody(result, settled, {
      payloadPointer: null,
      envelope: "present",
    });
  });

  it("S12-053 — Support lookup with missing R2 object returns null envelope", async () => {
    const settled = await settleCompleted();
    // [SEED] retention-style R2 delete without deleting the D1 row.
    await env.R2.delete(envelopeKey(settled.rid));
    expect(await r2Exists(envelopeKey(settled.rid))).toBe(false);

    const result = await supportLookup(settled.ref);
    await assertHappyLookupBody(result, settled, { envelope: "null" });
  });

  it("S12-054 — Support lookup writes no control_audit row", async () => {
    const settled = await settleCompleted();
    const clinic = await getRequestByRef(settled.token, settled.ref);
    const clinicBody = clinic.json as { result?: unknown };
    const auditBefore = await count("control_audit");
    const result = await supportLookup(settled.ref);
    await assertHappyLookupBody(result, settled, {
      clinicResult: clinicBody.result,
    });
    expect(await count("control_audit")).toBe(auditBefore);
  });

  it("S12-055 — GET method on the support-lookup route never reaches the handler", async () => {
    const settled = await settleCompleted();
    const result = await controlFetch(lookupPath(settled.ref), {
      method: "GET",
      auth: "operator",
    });
    expect(result.status).toBe(404);
    expect(result.text).toBe("Not Found");
    expect(result.json).toBeNull();
  });
});
