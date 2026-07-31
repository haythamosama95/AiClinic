import { env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

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
  | "in_progress"
  | "completed"
  | "failed"
  | "cancelled"
  | "awaiting_context";

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
  partial: boolean;
};

type PeriodCounters = {
  requestsUsed: number;
  tokensUsed: number;
  costUsed: number;
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
  return env.DO.newUniqueId().toString();
}

function buildEntitlementSnapshot(
  overrides: Partial<EntitlementSnapshot> & {
    request_quota?: number;
    token_budget?: number;
    cost_budget?: number;
  } = {},
): EntitlementSnapshot {
  const {
    request_quota,
    token_budget,
    cost_budget,
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
    allowed_capabilities: ["ai.access"],
    soft_threshold: 0.8,
    status: "active",
    ...rest,
  };
}

function quotaStub(installationId: string) {
  const id = env.DO.idFromString(installationId);
  return env.DO.get(id);
}

async function fetchRpc(
  installationId: string,
  body: AdmissionRequest | CreditRequest,
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
    partial: overrides.partial ?? false,
    ...overrides,
  };

  const response = await fetchRpc(installationId, body);

  return {
    response,
    body: (await response.json()) as CreditResponse,
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
        inFlight: 0,
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

    const lastCredit = credits[credits.length - 1]?.body as CreditAcknowledged;
    expect(lastCredit).toMatchObject({ kind: "credit", ok: true });

    const expectedCost = admittedBodies.reduce(
      (sum, _, index) => sum + 0.001 * (index + 1),
      0,
    );

    let tokensSum = 0;
    for (let i = 0; i < parallelCount; i += 1) {
      tokensSum += 50 + i;
    }

    expect(lastCredit.periodCounters).toEqual({
      requestsUsed: parallelCount,
      tokensUsed: tokensSum,
      costUsed: expect.closeTo(expectedCost, 5),
      inFlight: 0,
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
});
