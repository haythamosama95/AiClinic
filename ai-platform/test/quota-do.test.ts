import { env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { IDEMPOTENCY_STATES } from "../src/quota-do/index";
import quotaDoSource from "../src/quota-do/index.ts?raw";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    DO: DurableObjectNamespace;
  }
}

const RPC_URL = "https://quota-do.internal/rpc";
const EPHEMERAL_HORIZON_MS = 7_200_000;
const CONCURRENCY_LIMIT = 16;

type EntitlementSnapshot = {
  plan: string;
  period_bounds: {
    period_start: string;
    period_end: string;
  };
  request_quota: number;
  token_cost_budget: {
    token_budget: number;
    cost_budget: number;
  };
  credit_budget: number;
  allowed_capabilities: string[];
  soft_threshold: number;
  status: string;
};

type AdmissionRequest = {
  kind: "admission";
  jti: string;
  installationId: string;
  idempotencyKey: string;
  entitlement: EntitlementSnapshot;
  requestReference: string;
};

type IdempotencyRequestState =
  | "admitted"
  | "completed"
  | "failed"
  | "cancelled";

type IdempotencyPriorState = {
  requestReference: string;
  state: IdempotencyRequestState;
  requestId: string;
};

type AdmissionAdmitted = {
  kind: "admission";
  outcome: "admitted";
  requestId: string;
};

type AdmissionReplay = {
  kind: "admission";
  outcome: "replay";
};

type AdmissionIdempotent = {
  kind: "admission";
  outcome: "idempotent";
  priorState: IdempotencyPriorState;
};

type AdmissionQuotaExhausted = {
  kind: "admission";
  outcome: "quota_exhausted";
};

type AdmissionConcurrencyExhausted = {
  kind: "admission";
  outcome: "concurrency_exhausted";
};

type AdmissionResponse =
  | AdmissionAdmitted
  | AdmissionReplay
  | AdmissionIdempotent
  | AdmissionQuotaExhausted
  | AdmissionConcurrencyExhausted;

type CreditRequest = {
  kind: "credit";
  installationId: string;
  requestId: string;
  requestReference: string;
  usage: {
    tokens: number;
    cost: number;
  };
  credits: number;
  partial: boolean;
  idempotencyState?: "failed" | "cancelled" | "completed";
  entitlement?: EntitlementSnapshot;
};

type PeriodCounters = {
  requestsUsed: number;
  tokensUsed: number;
  costUsed: number;
  creditsUsed: number;
  inFlight: number;
};

type CreditAcknowledged = {
  kind: "credit";
  ok: true;
  periodCounters: PeriodCounters;
};

type CreditUnknownRequest = {
  kind: "credit";
  ok: false;
  code: "unknown_request";
};

type CreditResponse = CreditAcknowledged | CreditUnknownRequest;

type ReleaseRequest = {
  kind: "release";
  installationId: string;
  requestId: string;
  idempotencyKey: string;
  jti: string;
};

type ReleaseAcknowledged = {
  kind: "release";
  ok: true;
};

type ReleaseUnknownRequest = {
  kind: "release";
  ok: false;
  code: "unknown_request";
};

type ReleaseResponse = ReleaseAcknowledged | ReleaseUnknownRequest;

type InspectRequest = {
  kind: "inspect";
  now?: number;
};

type QuotaDoState = {
  periodCounters: PeriodCounters;
  periodBounds?: { period_start: string; period_end: string };
  jtiReplay: Record<string, { expiresAt: number }>;
  idempotency: Record<
    string,
    {
      expiresAt: number;
      requestReference: string;
      state: IdempotencyRequestState;
      requestId: string;
    }
  >;
  creditedRequests: Record<string, { expiresAt: number }>;
  admittedRequests: Record<
    string,
    {
      requestReference: string;
      admittedAt: number;
      entitlement: EntitlementSnapshot;
    }
  >;
  boundInstallationId?: string;
};

type InspectResponse = {
  kind: "inspect";
  state: QuotaDoState;
};

let jtiCounter = 0;
let idempotencyKeyCounter = 0;
let requestReferenceCounter = 0;

function uniqueJti(): string {
  jtiCounter += 1;
  return `f4000000-0000-4000-8000-${String(jtiCounter).padStart(12, "0")}`;
}

function uniqueIdempotencyKey(): string {
  idempotencyKeyCounter += 1;
  return `01ARZ3NDEK${String(idempotencyKeyCounter).padStart(14, "0")}`;
}

function uniqueRequestReference(): string {
  requestReferenceCounter += 1;
  return `AI-${String(requestReferenceCounter).padStart(6, "0")}`;
}

function freshInstallationId(): string {
  return crypto.randomUUID();
}

function buildEntitlementSnapshot(
  overrides: Partial<EntitlementSnapshot> & {
    request_quota?: number;
    token_budget?: number;
    cost_budget?: number;
    credit_budget?: number;
  } = {},
): EntitlementSnapshot {
  const {
    request_quota,
    token_budget,
    cost_budget,
    credit_budget,
    token_cost_budget,
    period_bounds,
    ...rest
  } = overrides;

  return {
    plan: "standard",
    period_bounds: period_bounds ?? {
      period_start: "2026-08-01T00:00:00.000Z",
      period_end: "2026-09-01T00:00:00.000Z",
    },
    request_quota: request_quota ?? 1_000,
    token_cost_budget: token_cost_budget ?? {
      token_budget: token_budget ?? 500_000,
      cost_budget: cost_budget ?? 50.0,
    },
    credit_budget: credit_budget ?? 10_000,
    allowed_capabilities: ["ai.access"],
    soft_threshold: 0.8,
    status: "active",
    ...rest,
  };
}

function expectPeriodCounters(
  actual: PeriodCounters,
  expected: Partial<PeriodCounters> & Pick<PeriodCounters, "requestsUsed" | "inFlight">,
): void {
  expect(actual).toEqual({
    requestsUsed: expected.requestsUsed,
    tokensUsed: expected.tokensUsed ?? 0,
    costUsed: expected.costUsed ?? 0,
    creditsUsed: expected.creditsUsed ?? 0,
    inFlight: expected.inFlight,
  });
}

function quotaStub(installationId: string) {
  const id = env.DO.idFromName(installationId);
  return env.DO.get(id);
}

async function fetchRpc(
  installationId: string,
  body:
    | AdmissionRequest
    | CreditRequest
    | ReleaseRequest
    | InspectRequest
    | (AdmissionRequest & { now?: number })
    | (CreditRequest & { now?: number }),
): Promise<Response> {
  try {
    return await quotaStub(installationId).fetch(RPC_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    return new Response(JSON.stringify({ error: "do_fetch_unavailable" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }
}

async function callAdmissionRPC(
  installationId: string,
  overrides: Partial<AdmissionRequest> = {},
): Promise<{ response: Response; body: AdmissionResponse }> {
  const body: AdmissionRequest = {
    kind: "admission",
    jti: overrides.jti ?? uniqueJti(),
    installationId,
    idempotencyKey: overrides.idempotencyKey ?? uniqueIdempotencyKey(),
    requestReference: overrides.requestReference ?? uniqueRequestReference(),
    entitlement: overrides.entitlement ?? buildEntitlementSnapshot(),
    ...overrides,
  };

  const response = await fetchRpc(installationId, body);

  return {
    response,
    body: (await response.json()) as AdmissionResponse,
  };
}

async function callCreditRPC(
  installationId: string,
  overrides: Partial<CreditRequest> = {},
): Promise<{ response: Response; body: CreditResponse }> {
  const body: CreditRequest = {
    kind: "credit",
    installationId,
    requestId: overrides.requestId ?? crypto.randomUUID(),
    requestReference: overrides.requestReference ?? uniqueRequestReference(),
    usage: overrides.usage ?? { tokens: 0, cost: 0 },
    credits: overrides.credits ?? 0,
    partial: overrides.partial ?? false,
    ...overrides,
  };

  const response = await fetchRpc(installationId, body);

  return {
    response,
    body: (await response.json()) as CreditResponse,
  };
}

async function callInspectRPC(
  installationId: string,
  options: { now?: number } = {},
): Promise<{ response: Response; body: InspectResponse }> {
  const body: InspectRequest = { kind: "inspect", ...options };
  const response = await fetchRpc(installationId, body);

  return {
    response,
    body: (await response.json()) as InspectResponse,
  };
}

async function callReleaseRPC(
  installationId: string,
  overrides: Partial<ReleaseRequest> &
    Pick<ReleaseRequest, "requestId" | "idempotencyKey" | "jti">,
): Promise<{ response: Response; body: ReleaseResponse }> {
  const body: ReleaseRequest = {
    kind: "release",
    installationId,
    requestId: overrides.requestId,
    idempotencyKey: overrides.idempotencyKey,
    jti: overrides.jti,
  };

  const response = await fetchRpc(installationId, body);

  return {
    response,
    body: (await response.json()) as ReleaseResponse,
  };
}

async function admitFresh(
  installationId: string,
  overrides: Partial<AdmissionRequest> = {},
): Promise<AdmissionAdmitted> {
  const { response, body } = await callAdmissionRPC(installationId, overrides);
  expect(response.ok).toBe(true);
  expect(body).toMatchObject({ kind: "admission", outcome: "admitted" });
  return body as AdmissionAdmitted;
}

beforeEach(() => {
  jtiCounter = 0;
  idempotencyKeyCounter = 0;
  requestReferenceCounter = 0;
  vi.useRealTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("admission_fresh_jti_accepted", () => {
  it("admits a previously-unseen jti with requestId", async () => {
    const installationId = freshInstallationId();
    const jti = uniqueJti();

    const { response, body } = await callAdmissionRPC(installationId, { jti });

    expect(response.ok).toBe(true);
    expect(body).toEqual({
      kind: "admission",
      outcome: "admitted",
      requestId: expect.any(String),
    });
    expect((body as AdmissionAdmitted).requestId.length).toBeGreaterThan(0);
  });
});

describe("admission_repeated_jti_rejected", () => {
  it("rejects a repeated jti as replay", async () => {
    const installationId = freshInstallationId();
    const jti = uniqueJti();

    const first = await callAdmissionRPC(installationId, { jti });
    expect(first.body).toMatchObject({ kind: "admission", outcome: "admitted" });

    const second = await callAdmissionRPC(installationId, {
      jti,
      idempotencyKey: uniqueIdempotencyKey(),
    });

    expect(second.response.ok).toBe(true);
    expect(second.body).toEqual({
      kind: "admission",
      outcome: "replay",
    });
  });
});

describe("admission_new_idempotency_key_accepted", () => {
  it("admits a previously-unseen idempotency key", async () => {
    const installationId = freshInstallationId();
    const idempotencyKey = uniqueIdempotencyKey();

    const { response, body } = await callAdmissionRPC(installationId, {
      idempotencyKey,
    });

    expect(response.ok).toBe(true);
    expect(body).toEqual({
      kind: "admission",
      outcome: "admitted",
      requestId: expect.any(String),
    });
  });
});

describe("admission_repeat_idempotency_key_returns_prior_record", () => {
  it("returns idempotent priorState matching the first admission", async () => {
    const installationId = freshInstallationId();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();

    const first = await callAdmissionRPC(installationId, {
      idempotencyKey,
      requestReference,
    });
    expect(first.body).toMatchObject({ kind: "admission", outcome: "admitted" });
    const firstAdmitted = first.body as AdmissionAdmitted;

    const second = await callAdmissionRPC(installationId, {
      jti: uniqueJti(),
      idempotencyKey,
      requestReference: uniqueRequestReference(),
    });

    expect(second.response.ok).toBe(true);
    expect(second.body).toEqual({
      kind: "admission",
      outcome: "idempotent",
      priorState: {
        requestReference,
        state: "admitted",
        requestId: firstAdmitted.requestId,
      },
    });
  });
});

describe("admission_budget_exhaustion_rejected", () => {
  it("rejects admission when request quota is exhausted", async () => {
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({ request_quota: 1 });

    const admitted = await admitFresh(installationId, { entitlement });
    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      requestReference: uniqueRequestReference(),
      usage: { tokens: 10, cost: 0.01 },
    });

    const exhausted = await callAdmissionRPC(installationId, {
      entitlement,
    });

    expect(exhausted.response.ok).toBe(true);
    expect(exhausted.body).toEqual({
      kind: "admission",
      outcome: "quota_exhausted",
      period_end: entitlement.period_bounds.period_end,
    });
  });
});

describe("admission_token_budget_exhaustion_rejected", () => {
  it("still admits when token budget is exhausted at settlement only", async () => {
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({
      request_quota: 10_000,
      token_budget: 100,
      cost_budget: 50.0,
      credit_budget: 10_000,
    });

    const admitted = await admitFresh(installationId, { entitlement });
    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      credits: 1,
      usage: { tokens: 100, cost: 0.01 },
    });

    const next = await callAdmissionRPC(installationId, { entitlement });

    expect(next.response.ok).toBe(true);
    expect(next.body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
      requestId: expect.any(String),
    });
  });
});

describe("admission_cost_budget_exhaustion_rejected", () => {
  it("still admits when cost budget is exhausted at settlement only", async () => {
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({
      request_quota: 10_000,
      token_budget: 500_000,
      cost_budget: 1.0,
      credit_budget: 10_000,
    });

    const admitted = await admitFresh(installationId, { entitlement });
    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      credits: 1,
      usage: { tokens: 10, cost: 1.0 },
    });

    const next = await callAdmissionRPC(installationId, { entitlement });

    expect(next.response.ok).toBe(true);
    expect(next.body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
      requestId: expect.any(String),
    });
  });
});

describe("admission_concurrency_ceiling_rejected", () => {
  it(`rejects when inFlight reaches CONCURRENCY_LIMIT (${CONCURRENCY_LIMIT})`, async () => {
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({ request_quota: 10_000 });

    for (let i = 0; i < CONCURRENCY_LIMIT; i += 1) {
      const { body } = await callAdmissionRPC(installationId, { entitlement });
      expect(body).toMatchObject({ kind: "admission", outcome: "admitted" });
    }

    const rejected = await callAdmissionRPC(installationId, { entitlement });

    expect(rejected.response.ok).toBe(true);
    expect(rejected.body).toEqual({
      kind: "admission",
      outcome: "concurrency_exhausted",
    });
  });
});

describe("credit_reruns_period_reset_before_applying_usage", () => {
  it("applies credit to the entitlement period passed at credit time, not a stale DO period", async () => {
    const installationId = freshInstallationId();
    const periodA = {
      period_start: "2026-08-01T00:00:00.000Z",
      period_end: "2026-09-01T00:00:00.000Z",
    };
    const periodB = {
      period_start: "2026-09-01T00:00:00.000Z",
      period_end: "2026-10-01T00:00:00.000Z",
    };
    const entA = buildEntitlementSnapshot({
      request_quota: 100,
      period_bounds: periodA,
    });
    const entB = buildEntitlementSnapshot({
      request_quota: 1,
      period_bounds: periodB,
    });

    const admitted = await admitFresh(installationId, { entitlement: entA });
    const credit = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      usage: { tokens: 50, cost: 0.05 },
      entitlement: entB,
    });
    expect(credit.body).toMatchObject({ kind: "credit", ok: true });

    const next = await callAdmissionRPC(installationId, { entitlement: entB });
    expect(next.body).toMatchObject({
      kind: "admission",
      outcome: "quota_exhausted",
      period_end: periodB.period_end,
    });
  });
});

describe("credit_adjusts_counters_with_actual_usage", () => {
  it("reflects tokens, cost, and requestsUsed after credit", async () => {
    const installationId = freshInstallationId();
    const requestReference = uniqueRequestReference();
    const usage = { tokens: 842, cost: 0.0031 };

    const admitted = await admitFresh(installationId, { requestReference });

    const { response, body } = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      requestReference,
      usage,
      partial: false,
    });

    expect(response.ok).toBe(true);
    expect(body).toEqual({
      kind: "credit",
      ok: true,
      periodCounters: {
        requestsUsed: 1,
        tokensUsed: usage.tokens,
        costUsed: usage.cost,
        creditsUsed: 0,
        inFlight: 0,
      },
    });
  });
});

describe("credit_adjusts_counters_with_partial_usage", () => {
  it("adjusts counters when partial is true", async () => {
    const installationId = freshInstallationId();
    const requestReference = uniqueRequestReference();
    const usage = { tokens: 120, cost: 0.0015 };

    const admitted = await admitFresh(installationId, { requestReference });

    const { response, body } = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      requestReference,
      usage,
      partial: true,
    });

    expect(response.ok).toBe(true);
    expect(body).toEqual({
      kind: "credit",
      ok: true,
      periodCounters: {
        requestsUsed: 1,
        tokensUsed: usage.tokens,
        costUsed: usage.cost,
        creditsUsed: 0,
        inFlight: 0,
      },
    });
  });
});

describe("credit_evicts_admitted_request_and_expires_credited", () => {
  it("evicts the admitted entry so a second credit returns unknown_request", async () => {
    const installationId = freshInstallationId();
    const admitted = await admitFresh(installationId);

    const first = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      usage: { tokens: 10, cost: 0.01 },
    });
    expect(first.body).toMatchObject({ kind: "credit", ok: true });

    const second = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      usage: { tokens: 10, cost: 0.01 },
    });
    expect(second.response.ok).toBe(true);
    expect(second.body).toEqual({
      kind: "credit",
      ok: false,
      code: "unknown_request",
    });
  });
});

describe("unknown_credit_request_id_returns_unknown_request", () => {
  it("returns unknown_request for a never-admitted requestId", async () => {
    const installationId = freshInstallationId();
    await admitFresh(installationId);

    const { response, body } = await callCreditRPC(installationId, {
      requestId: crypto.randomUUID(),
      usage: { tokens: 1, cost: 0.001 },
    });

    expect(response.ok).toBe(true);
    expect(body).toEqual({
      kind: "credit",
      ok: false,
      code: "unknown_request",
    });
  });
});

describe("duplicate_credit_returns_unknown_request", () => {
  it("returns unknown_request when the same requestId is credited twice", async () => {
    const installationId = freshInstallationId();
    const admitted = await admitFresh(installationId);

    const first = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      usage: { tokens: 5, cost: 0.002 },
    });
    expect(first.body).toMatchObject({ kind: "credit", ok: true });

    const duplicate = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      usage: { tokens: 5, cost: 0.002 },
    });
    expect(duplicate.body).toEqual({
      kind: "credit",
      ok: false,
      code: "unknown_request",
    });
  });
});

describe("period_rollover_preserves_in_flight", () => {
  it("preserves inFlight across period rollover and resets usage counters", async () => {
    const installationId = freshInstallationId();
    const periodA = {
      period_start: "2026-08-01T00:00:00.000Z",
      period_end: "2026-09-01T00:00:00.000Z",
    };
    const periodB = {
      period_start: "2026-09-01T00:00:00.000Z",
      period_end: "2026-10-01T00:00:00.000Z",
    };
    const periodC = {
      period_start: "2026-10-01T00:00:00.000Z",
      period_end: "2026-11-01T00:00:00.000Z",
    };

    const entA = buildEntitlementSnapshot({
      request_quota: 1,
      period_bounds: periodA,
    });
    const first = await admitFresh(installationId, { entitlement: entA });
    const credit = await callCreditRPC(installationId, {
      requestId: first.requestId,
      usage: { tokens: 10, cost: 0.01 },
    });
    expect(credit.body).toMatchObject({
      kind: "credit",
      ok: true,
      periodCounters: { requestsUsed: 1, inFlight: 0 },
    });

    const blocked = await callAdmissionRPC(installationId, { entitlement: entA });
    expect(blocked.body).toMatchObject({
      kind: "admission",
      outcome: "quota_exhausted",
    });

    const entB = buildEntitlementSnapshot({
      request_quota: 10_000,
      period_bounds: periodB,
    });
    // Usage counters reset — admission succeeds despite period-A exhaustion.
    await admitFresh(installationId, { entitlement: entB });

    for (let i = 1; i < CONCURRENCY_LIMIT; i += 1) {
      await admitFresh(installationId, { entitlement: entB });
    }

    const entC = buildEntitlementSnapshot({
      request_quota: 10_000,
      period_bounds: periodC,
    });
    // inFlight carried across the B→C rollover — still at the ceiling.
    const rejected = await callAdmissionRPC(installationId, { entitlement: entC });
    expect(rejected.response.ok).toBe(true);
    expect(rejected.body).toEqual({
      kind: "admission",
      outcome: "concurrency_exhausted",
    });
  });
});

describe("abandoned_admission_swept_after_horizon", () => {
  it("sweeps abandoned admissions after EPHEMERAL_HORIZON_MS and frees inFlight", async () => {
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({ request_quota: 10_000 });
    const baseTime = new Date("2026-08-01T12:00:00.000Z");

    vi.setSystemTime(baseTime);

    for (let i = 0; i < CONCURRENCY_LIMIT; i += 1) {
      await admitFresh(installationId, { entitlement });
    }

    const blocked = await callAdmissionRPC(installationId, { entitlement });
    expect(blocked.body).toMatchObject({
      kind: "admission",
      outcome: "concurrency_exhausted",
    });

    vi.setSystemTime(new Date(baseTime.getTime() + EPHEMERAL_HORIZON_MS + 1));

    const recovered = await callAdmissionRPC(installationId, { entitlement });
    expect(recovered.response.ok).toBe(true);
    expect(recovered.body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
    });
  });

  it("replays a swept abandoned admission as failed, not admitted or completed", async () => {
    const installationId = freshInstallationId();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();
    const entitlement = buildEntitlementSnapshot({ request_quota: 10_000 });
    const baseTime = new Date("2026-08-01T12:00:00.000Z");

    vi.setSystemTime(baseTime);

    const admitted = await admitFresh(installationId, {
      idempotencyKey,
      requestReference,
      entitlement,
    });

    for (let i = 1; i < CONCURRENCY_LIMIT; i += 1) {
      await admitFresh(installationId, { entitlement });
    }

    const blocked = await callAdmissionRPC(installationId, { entitlement });
    expect(blocked.body).toMatchObject({
      kind: "admission",
      outcome: "concurrency_exhausted",
    });

    vi.setSystemTime(new Date(baseTime.getTime() + EPHEMERAL_HORIZON_MS + 1));

    const recovered = await callAdmissionRPC(installationId, { entitlement });
    expect(recovered.response.ok).toBe(true);
    expect(recovered.body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
    });

    const replay = await callAdmissionRPC(installationId, {
      jti: uniqueJti(),
      idempotencyKey,
      entitlement,
    });

    expect(replay.body).toEqual({
      kind: "admission",
      outcome: "idempotent",
      priorState: {
        requestReference,
        state: "failed",
        requestId: admitted.requestId,
      },
    });
  });
});

describe("credit_slides_idempotency_expires_at", () => {
  it("keeps a credited key idempotent after the original admission horizon", async () => {
    const installationId = freshInstallationId();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();
    const baseTime = new Date("2026-08-01T12:00:00.000Z");

    vi.setSystemTime(baseTime);

    const admitted = await admitFresh(installationId, {
      idempotencyKey,
      requestReference,
    });

    vi.setSystemTime(new Date(baseTime.getTime() + EPHEMERAL_HORIZON_MS - 1000));

    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      requestReference,
      usage: { tokens: 20, cost: 0.02 },
      partial: false,
    });

    vi.setSystemTime(new Date(baseTime.getTime() + EPHEMERAL_HORIZON_MS + 1000));

    const replay = await callAdmissionRPC(installationId, {
      jti: uniqueJti(),
      idempotencyKey,
    });

    expect(replay.body).toEqual({
      kind: "admission",
      outcome: "idempotent",
      priorState: {
        requestReference,
        state: "completed",
        requestId: admitted.requestId,
      },
    });
  });
});

describe("idempotency_do_states_exclude_unused", () => {
  it("does not include in_progress or awaiting_context on the Quota DO union", () => {
    expect(IDEMPOTENCY_STATES).toEqual([
      "admitted",
      "completed",
      "failed",
      "cancelled",
    ]);
    expect(IDEMPOTENCY_STATES).not.toContain("in_progress");
    expect(IDEMPOTENCY_STATES).not.toContain("awaiting_context");

    const match = quotaDoSource.match(
      /export type IdempotencyRequestState\s*=\s*([\s\S]*?);/,
    );
    expect(match).not.toBeNull();
    const unionBody = match![1];
    expect(unionBody).not.toMatch(/in_progress/);
    expect(unionBody).not.toMatch(/awaiting_context/);
  });
});

describe("credit_marks_idempotency_completed", () => {
  it("marks the idempotency record completed after a full credit", async () => {
    const installationId = freshInstallationId();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();

    const admitted = await admitFresh(installationId, {
      idempotencyKey,
      requestReference,
    });

    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      requestReference,
      usage: { tokens: 20, cost: 0.02 },
      partial: false,
    });

    const replay = await callAdmissionRPC(installationId, {
      jti: uniqueJti(),
      idempotencyKey,
    });

    expect(replay.body).toEqual({
      kind: "admission",
      outcome: "idempotent",
      priorState: {
        requestReference,
        state: "completed",
        requestId: admitted.requestId,
      },
    });
  });
});

describe("credit_partial_marks_idempotency_cancelled", () => {
  it("marks the idempotency record cancelled after a partial credit", async () => {
    const installationId = freshInstallationId();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();

    const admitted = await admitFresh(installationId, {
      idempotencyKey,
      requestReference,
    });

    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      requestReference,
      usage: { tokens: 5, cost: 0.001 },
      partial: true,
    });

    const replay = await callAdmissionRPC(installationId, {
      jti: uniqueJti(),
      idempotencyKey,
    });

    expect(replay.body).toEqual({
      kind: "admission",
      outcome: "idempotent",
      priorState: {
        requestReference,
        state: "cancelled",
        requestId: admitted.requestId,
      },
    });
  });
});

describe("credit_marks_idempotency_failed", () => {
  it("marks the idempotency record failed when credit carries idempotencyState failed", async () => {
    const installationId = freshInstallationId();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();

    const admitted = await admitFresh(installationId, {
      idempotencyKey,
      requestReference,
    });

    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      requestReference,
      usage: { tokens: 0, cost: 0 },
      partial: false,
      idempotencyState: "failed",
    });

    const replay = await callAdmissionRPC(installationId, {
      jti: uniqueJti(),
      idempotencyKey,
    });

    expect(replay.body).toEqual({
      kind: "admission",
      outcome: "idempotent",
      priorState: {
        requestReference,
        state: "failed",
        requestId: admitted.requestId,
      },
    });
  });
});

describe("parallel_admissions_exact_final_count", () => {
  it("produces exact inFlight and requestsUsed after parallel admits and credits", async () => {
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot();
    const parallelCount = 8;

    const admissions = await Promise.all(
      Array.from({ length: parallelCount }, () =>
        callAdmissionRPC(installationId, { entitlement }),
      ),
    );

    for (const admission of admissions) {
      expect(admission.response.ok).toBe(true);
      expect(admission.body).toMatchObject({
        kind: "admission",
        outcome: "admitted",
      });
    }

    const admittedBodies = admissions.map((a) => a.body as AdmissionAdmitted);

    const credits = await Promise.all(
      admittedBodies.map((admitted, index) =>
        callCreditRPC(installationId, {
          requestId: admitted.requestId,
          requestReference: `AI-PAR-${String(index).padStart(3, "0")}`,
          usage: { tokens: 50 + index, cost: 0.001 * (index + 1) },
        }),
      ),
    );

    for (const credit of credits) {
      expect(credit.body).toMatchObject({ kind: "credit", ok: true });
    }

    const expectedCost = admittedBodies.reduce(
      (sum, _, index) => sum + 0.001 * (index + 1),
      0,
    );

    let tokensSum = 0;
    for (let i = 0; i < parallelCount; i += 1) {
      tokensSum += 50 + i;
    }

    // Read counters only after every parallel credit has settled.
    const trailing = await admitFresh(installationId, { entitlement });
    const settled = await callCreditRPC(installationId, {
      requestId: trailing.requestId,
      usage: { tokens: 0, cost: 0 },
    });

    expect(settled.body).toEqual({
      kind: "credit",
      ok: true,
      periodCounters: {
        requestsUsed: parallelCount + 1,
        tokensUsed: tokensSum,
        costUsed: expect.closeTo(expectedCost, 5),
        creditsUsed: 0,
        inFlight: 0,
      },
    });
  });
});

describe("ephemeral_entries_expire_in_place", () => {
  it("admits the same jti again after EPHEMERAL_HORIZON_MS lazy sweep", async () => {
    const installationId = freshInstallationId();
    const jti = uniqueJti();
    const baseTime = new Date("2026-08-01T12:00:00.000Z");

    vi.setSystemTime(baseTime);

    const first = await callAdmissionRPC(installationId, { jti });
    expect(first.body).toMatchObject({ kind: "admission", outcome: "admitted" });

    vi.setSystemTime(new Date(baseTime.getTime() + EPHEMERAL_HORIZON_MS + 1));

    const second = await callAdmissionRPC(installationId, {
      jti,
      idempotencyKey: uniqueIdempotencyKey(),
    });

    expect(second.response.ok).toBe(true);
    expect(second.body).toEqual({
      kind: "admission",
      outcome: "admitted",
      requestId: expect.any(String),
    });
  });

  it("evicts expired idempotency keys so a repeat key admits fresh after the horizon", async () => {
    const installationId = freshInstallationId();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();
    const baseTime = new Date("2026-08-01T12:00:00.000Z");

    vi.setSystemTime(baseTime);

    const first = await callAdmissionRPC(installationId, {
      idempotencyKey,
      requestReference,
    });
    expect(first.body).toMatchObject({ kind: "admission", outcome: "admitted" });
    const admitted = first.body as AdmissionAdmitted;

    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      requestReference,
      usage: { tokens: 1, cost: 0.001 },
      partial: false,
    });

    vi.setSystemTime(new Date(baseTime.getTime() + EPHEMERAL_HORIZON_MS + 1));

    const second = await callAdmissionRPC(installationId, {
      jti: uniqueJti(),
      idempotencyKey,
    });

    expect(second.response.ok).toBe(true);
    expect(second.body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
      requestId: expect.any(String),
    });
  });
});

describe("admission_soft_threshold_sets_degraded", () => {
  it("sets degraded on admitted when soft_threshold is already crossed", async () => {
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({
      soft_threshold: 0.5,
      credit_budget: 100,
      request_quota: 10_000,
    });

    const first = await admitFresh(installationId, { entitlement });
    await callCreditRPC(installationId, {
      requestId: first.requestId,
      credits: 50,
      usage: { tokens: 1, cost: 0.001 },
    });

    // creditsUsed=50 / credit_budget=100 = 0.5 >= soft_threshold 0.5
    const { body } = await callAdmissionRPC(installationId, { entitlement });

    expect(body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
      degraded: true,
      requestId: expect.any(String),
    });
  });

  it("never degrades when soft_threshold is zero (enroll sentinel)", async () => {
    const installationId = freshInstallationId();
    const { body } = await callAdmissionRPC(installationId, {
      entitlement: buildEntitlementSnapshot({ soft_threshold: 0 }),
    });

    expect(body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
      requestId: expect.any(String),
    });
    expect(body).not.toHaveProperty("degraded");
  });
});

describe("release_rolls_back_admission_reservation", () => {
  it("frees jti, idempotency key, and in-flight slot after release", async () => {
    const installationId = freshInstallationId();
    const jti = uniqueJti();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();

    const admitted = await admitFresh(installationId, {
      jti,
      idempotencyKey,
      requestReference,
    });

    const released = await callReleaseRPC(installationId, {
      requestId: admitted.requestId,
      idempotencyKey,
      jti,
    });
    expect(released.response.ok).toBe(true);
    expect(released.body).toEqual({ kind: "release", ok: true });

    // Same jti may admit again (replay entry cleared).
    const jtiReuse = await callAdmissionRPC(installationId, {
      jti,
      idempotencyKey: uniqueIdempotencyKey(),
    });
    expect(jtiReuse.body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
    });

    // Same idempotency key may admit again (not stuck on idempotent).
    const keyReuse = await callAdmissionRPC(installationId, {
      jti: uniqueJti(),
      idempotencyKey,
      requestReference,
    });
    expect(keyReuse.body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
    });
  });

  it("returns unknown_request for a requestId that was never admitted", async () => {
    const installationId = freshInstallationId();
    await admitFresh(installationId);

    const released = await callReleaseRPC(installationId, {
      requestId: crypto.randomUUID(),
      idempotencyKey: uniqueIdempotencyKey(),
      jti: uniqueJti(),
    });

    expect(released.response.ok).toBe(true);
    expect(released.body).toEqual({
      kind: "release",
      ok: false,
      code: "unknown_request",
    });
  });

  it("returns unknown_request after the admission was already credited", async () => {
    const installationId = freshInstallationId();
    const jti = uniqueJti();
    const idempotencyKey = uniqueIdempotencyKey();
    const admitted = await admitFresh(installationId, { jti, idempotencyKey });

    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      usage: { tokens: 1, cost: 0.001 },
    });

    const released = await callReleaseRPC(installationId, {
      requestId: admitted.requestId,
      idempotencyKey,
      jti,
    });

    expect(released.body).toEqual({
      kind: "release",
      ok: false,
      code: "unknown_request",
    });
  });
});

describe("inspect_rpc", () => {
  it("returns zeroed counters and empty maps for a fresh installation", async () => {
    const installationId = freshInstallationId();

    const { response, body } = await callInspectRPC(installationId);

    expect(response.ok).toBe(true);
    expect(body.kind).toBe("inspect");
    expect(body.state.periodCounters).toEqual({
      requestsUsed: 0,
      tokensUsed: 0,
      costUsed: 0,
      creditsUsed: 0,
      inFlight: 0,
    });
    expect(body.state.jtiReplay).toEqual({});
    expect(body.state.idempotency).toEqual({});
    expect(body.state.admittedRequests).toEqual({});
    expect(body.state.creditedRequests).toEqual({});
    expect(body.state.boundInstallationId).toBeUndefined();
    expect(body.state.periodBounds).toBeUndefined();
  });

  it("reflects admitted state after a successful admission RPC", async () => {
    const installationId = freshInstallationId();
    const jti = uniqueJti();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();

    const admitted = await admitFresh(installationId, {
      jti,
      idempotencyKey,
      requestReference,
    });

    const { response, body } = await callInspectRPC(installationId);

    expect(response.ok).toBe(true);
    expect(body.state.periodCounters.inFlight).toBe(1);
    expect(Object.keys(body.state.jtiReplay)).toEqual([jti]);
    expect(body.state.idempotency[idempotencyKey]).toMatchObject({
      requestReference,
      state: "admitted",
      requestId: admitted.requestId,
    });
    expect(body.state.admittedRequests[admitted.requestId]).toMatchObject({
      requestReference,
    });
    expect(body.state.boundInstallationId).toBe(installationId);
  });

  it("reflects credited state after admission and credit RPCs", async () => {
    const installationId = freshInstallationId();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();
    const usage = { tokens: 60, cost: 0.01 };

    const admitted = await admitFresh(installationId, {
      idempotencyKey,
      requestReference,
    });

    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      requestReference,
      usage,
      partial: false,
    });

    const { response, body } = await callInspectRPC(installationId);

    expect(response.ok).toBe(true);
    expect(body.state.periodCounters).toEqual({
      requestsUsed: 1,
      tokensUsed: usage.tokens,
      costUsed: usage.cost,
      creditsUsed: 0,
      inFlight: 0,
    });
    expect(body.state.admittedRequests).toEqual({});
    expect(body.state.creditedRequests[admitted.requestId]).toBeDefined();
    expect(body.state.idempotency[idempotencyKey]).toMatchObject({
      state: "completed",
      requestId: admitted.requestId,
    });
  });

  it("applies ephemeral sweep in memory without persisting deletions", async () => {
    const installationId = freshInstallationId();
    const jti = uniqueJti();
    const idempotencyKey = uniqueIdempotencyKey();
    const requestReference = uniqueRequestReference();
    const baseTime = new Date("2026-08-01T12:00:00.000Z");

    vi.setSystemTime(baseTime);

    await admitFresh(installationId, {
      jti,
      idempotencyKey,
      requestReference,
    });

    vi.setSystemTime(new Date(baseTime.getTime() + EPHEMERAL_HORIZON_MS + 1));

    const { response, body } = await callInspectRPC(installationId);

    expect(response.ok).toBe(true);
    expect(body.state.periodCounters.inFlight).toBe(0);
    expect(body.state.jtiReplay).toEqual({});
    expect(body.state.admittedRequests).toEqual({});
    expect(body.state.idempotency[idempotencyKey]).toMatchObject({
      state: "failed",
    });
  });

  it("does not persist inspect sweeps so replay detection still works", async () => {
    const installationId = freshInstallationId();
    const jti = uniqueJti();
    const baseTime = new Date("2026-08-01T13:00:00.000Z");

    vi.setSystemTime(baseTime);
    await admitFresh(installationId, { jti });

    const inspectTime = baseTime.getTime() + EPHEMERAL_HORIZON_MS + 1;
    await callInspectRPC(installationId, { now: inspectTime });

    vi.setSystemTime(baseTime);
    const replay = await callAdmissionRPC(installationId, {
      jti,
      idempotencyKey: uniqueIdempotencyKey(),
    });

    expect(replay.body).toEqual({
      kind: "admission",
      outcome: "replay",
    });
  });
});

describe("credit_debits_declared_quota_weight", () => {
  it("increases creditsUsed by exactly W after stage-15 credit with credits: W", async () => {
    const W = 5;
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({ credit_budget: 1_000 });
    const admitted = await admitFresh(installationId, { entitlement });

    const { response, body } = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      credits: W,
      usage: { tokens: 100, cost: 0.01 },
    });

    expect(response.ok).toBe(true);
    expect(body).toMatchObject({ kind: "credit", ok: true });
    if (body.kind !== "credit" || !body.ok) {
      return;
    }
    expectPeriodCounters(body.periodCounters, {
      requestsUsed: 1,
      tokensUsed: 100,
      costUsed: 0.01,
      creditsUsed: W,
      inFlight: 0,
    });
  });
});

describe("conversational_leg_debits_per_leg", () => {
  it("increases creditsUsed by 2W when two legs each credit credits: W", async () => {
    const W = 7;
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({
      credit_budget: 1_000,
      request_quota: 10,
    });

    const first = await admitFresh(installationId, { entitlement });
    await callCreditRPC(installationId, {
      requestId: first.requestId,
      credits: W,
      usage: { tokens: 10, cost: 0.001 },
    });

    const second = await admitFresh(installationId, { entitlement });
    const { body } = await callCreditRPC(installationId, {
      requestId: second.requestId,
      credits: W,
      usage: { tokens: 12, cost: 0.002 },
    });

    expect(body).toMatchObject({ kind: "credit", ok: true });
    if (body.kind !== "credit" || !body.ok) {
      return;
    }
    expectPeriodCounters(body.periodCounters, {
      requestsUsed: 2,
      tokensUsed: 22,
      costUsed: 0.003,
      creditsUsed: 2 * W,
      inFlight: 0,
    });
  });
});

describe("cancelled_request_debits_full_declared_weight", () => {
  it("adds the full credits weight when partial is true", async () => {
    const W = 9;
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({ credit_budget: 1_000 });
    const admitted = await admitFresh(installationId, { entitlement });
    const usage = { tokens: 40, cost: 0.004 };

    const { body } = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      credits: W,
      usage,
      partial: true,
    });

    expect(body).toMatchObject({ kind: "credit", ok: true });
    if (body.kind !== "credit" || !body.ok) {
      return;
    }
    expectPeriodCounters(body.periodCounters, {
      requestsUsed: 1,
      tokensUsed: usage.tokens,
      costUsed: usage.cost,
      creditsUsed: W,
      inFlight: 0,
    });
  });
});

describe("credit_budget_exhausted_quota_exhausted_with_reset_at", () => {
  it("returns quota_exhausted with period_end when creditsUsed reaches credit_budget", async () => {
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({
      credit_budget: 10,
      request_quota: 10_000,
      token_budget: 500_000,
      cost_budget: 50,
    });

    const admitted = await admitFresh(installationId, { entitlement });
    await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      credits: 10,
      usage: { tokens: 1, cost: 0.001 },
    });

    const exhausted = await callAdmissionRPC(installationId, { entitlement });

    expect(exhausted.response.ok).toBe(true);
    expect(exhausted.body).toEqual({
      kind: "admission",
      outcome: "quota_exhausted",
      period_end: entitlement.period_bounds.period_end,
    });
  });
});

describe("credit_ratio_soft_threshold_sets_degraded_flag", () => {
  it("sets degraded when creditsUsed / credit_budget crosses soft_threshold with budget remaining", async () => {
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({
      credit_budget: 100,
      soft_threshold: 0.5,
      request_quota: 10_000,
    });

    const first = await admitFresh(installationId, { entitlement });
    await callCreditRPC(installationId, {
      requestId: first.requestId,
      credits: 50,
      usage: { tokens: 1, cost: 0.001 },
    });

    const { body } = await callAdmissionRPC(installationId, { entitlement });

    expect(body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
      degraded: true,
      requestId: expect.any(String),
    });
  });
});

describe("below_credit_soft_threshold_not_degraded", () => {
  it("admits without degraded when the credit ratio is below soft_threshold", async () => {
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({
      credit_budget: 100,
      soft_threshold: 0.5,
      request_quota: 2,
    });

    const first = await admitFresh(installationId, { entitlement });
    await callCreditRPC(installationId, {
      requestId: first.requestId,
      credits: 10,
      usage: { tokens: 1, cost: 0.001 },
    });

    const { body } = await callAdmissionRPC(installationId, { entitlement });

    expect(body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
      requestId: expect.any(String),
    });
    expect(body).not.toHaveProperty("degraded");
  });
});

describe("token_and_cost_counters_settle_actuals_unchanged", () => {
  it("settles token and cost actuals without driving remaining-budget or the credit debit", async () => {
    const installationId = freshInstallationId();
    const W = 4;
    const entitlement = buildEntitlementSnapshot({
      credit_budget: 10_000,
      request_quota: 10_000,
      token_budget: 100,
      cost_budget: 50,
    });

    const admitted = await admitFresh(installationId, { entitlement });
    const partialUsage = { tokens: 100, cost: 1.0 };
    const credited = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      credits: W,
      usage: partialUsage,
      partial: true,
    });
    expect(credited.body).toMatchObject({ kind: "credit", ok: true });
    if (credited.body.kind !== "credit" || !credited.body.ok) {
      return;
    }
    expectPeriodCounters(credited.body.periodCounters, {
      requestsUsed: 1,
      tokensUsed: partialUsage.tokens,
      costUsed: partialUsage.cost,
      creditsUsed: W,
      inFlight: 0,
    });

    const next = await callAdmissionRPC(installationId, { entitlement });
    expect(next.body).toMatchObject({
      kind: "admission",
      outcome: "admitted",
      requestId: expect.any(String),
    });
  });
});

describe("credit_rpc_gains_fields_without_changing_existing_meanings", () => {
  it("extends snapshot, credit body, and counters without rewriting existing fields", async () => {
    const W = 6;
    const installationId = freshInstallationId();
    const entitlement = buildEntitlementSnapshot({ credit_budget: 500 });
    expect(entitlement.credit_budget).toBe(500);

    const requestReference = uniqueRequestReference();
    const idempotencyKey = uniqueIdempotencyKey();
    const admitted = await admitFresh(installationId, {
      entitlement,
      requestReference,
      idempotencyKey,
    });
    const usage = { tokens: 321, cost: 0.0321 };

    const { body } = await callCreditRPC(installationId, {
      requestId: admitted.requestId,
      requestReference,
      credits: W,
      usage,
      partial: false,
    });

    expect(body).toMatchObject({ kind: "credit", ok: true });
    if (body.kind !== "credit" || !body.ok) {
      return;
    }
    expectPeriodCounters(body.periodCounters, {
      requestsUsed: 1,
      tokensUsed: usage.tokens,
      costUsed: usage.cost,
      creditsUsed: W,
      inFlight: 0,
    });

    const replay = await callAdmissionRPC(installationId, {
      entitlement,
      idempotencyKey,
      jti: uniqueJti(),
      requestReference: uniqueRequestReference(),
    });
    expect(replay.body).toMatchObject({
      kind: "admission",
      outcome: "idempotent",
      priorState: {
        requestReference,
        state: "completed",
        requestId: admitted.requestId,
      },
    });
  });
});
