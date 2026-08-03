export const EPHEMERAL_HORIZON_MS = 7_200_000;
export const CONCURRENCY_LIMIT = 16;

const STATE_KEY = "state";

export interface EphemeralEntry {
  expiresAt: number;
}

export type JtiReplayEntry = EphemeralEntry;

export type IdempotencyRequestState =
  | "admitted"
  | "in_progress"
  | "completed"
  | "failed"
  | "cancelled"
  | "awaiting_context";

export interface IdempotencyEntry extends EphemeralEntry {
  requestReference: string;
  state: IdempotencyRequestState;
  requestId: string;
}

export interface EntitlementSnapshot {
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
}

export interface PeriodCounters {
  requestsUsed: number;
  tokensUsed: number;
  costUsed: number;
  inFlight: number;
}

export interface QuotaDoState {
  periodCounters: PeriodCounters;
  periodBounds?: { period_start: string; period_end: string };
  jtiReplay: Record<string, JtiReplayEntry>;
  idempotency: Record<string, IdempotencyEntry>;
  creditedRequests: Record<string, { expiresAt: number }>;
  admittedRequests: Record<string, { requestReference: string; admittedAt: number }>;
  boundInstallationId?: string;
}

export interface AdmissionRequest {
  kind: "admission";
  jti: string;
  installationId: string;
  idempotencyKey: string;
  entitlement: EntitlementSnapshot;
  requestReference: string;
}

export interface IdempotencyPriorState {
  requestReference: string;
  state: IdempotencyRequestState;
  requestId: string;
}

export interface AdmissionAdmitted {
  kind: "admission";
  outcome: "admitted";
  requestId: string;
  degraded?: boolean;
}

export interface AdmissionReplay {
  kind: "admission";
  outcome: "replay";
}

export interface AdmissionIdempotent {
  kind: "admission";
  outcome: "idempotent";
  priorState: IdempotencyPriorState;
}

export interface AdmissionQuotaExhausted {
  kind: "admission";
  outcome: "quota_exhausted";
  period_end: string;
}

export interface AdmissionConcurrencyExhausted {
  kind: "admission";
  outcome: "concurrency_exhausted";
}

export type AdmissionResponse =
  | AdmissionAdmitted
  | AdmissionReplay
  | AdmissionIdempotent
  | AdmissionQuotaExhausted
  | AdmissionConcurrencyExhausted;

export interface UsageActual {
  tokens: number;
  cost: number;
}

export interface CreditRequest {
  kind: "credit";
  installationId: string;
  requestId: string;
  requestReference: string;
  usage: UsageActual;
  partial: boolean;
}

export interface CreditAcknowledged {
  kind: "credit";
  ok: true;
  periodCounters: PeriodCounters;
}

export interface CreditUnknownRequest {
  kind: "credit";
  ok: false;
  code: "unknown_request";
}

export type CreditResponse = CreditAcknowledged | CreditUnknownRequest;

function initialPeriodCounters(): PeriodCounters {
  return {
    requestsUsed: 0,
    tokensUsed: 0,
    costUsed: 0,
    inFlight: 0,
  };
}

function initialState(): QuotaDoState {
  return {
    periodCounters: initialPeriodCounters(),
    jtiReplay: {},
    idempotency: {},
    creditedRequests: {},
    admittedRequests: {},
  };
}

async function loadState(storage: DurableObjectStorage): Promise<QuotaDoState> {
  const stored = await storage.get<QuotaDoState>(STATE_KEY);
  return stored ?? initialState();
}

function assertInstallationBound(state: QuotaDoState, installationId: string): void {
  if (
    state.boundInstallationId !== undefined &&
    state.boundInstallationId !== installationId
  ) {
    throw new Error("installation_id_mismatch");
  }
}

function sweepAbandonedAdmissions(state: QuotaDoState, now: number): void {
  const cutoff = now - EPHEMERAL_HORIZON_MS;

  for (const [requestId, entry] of Object.entries(state.admittedRequests)) {
    if (entry.admittedAt <= cutoff) {
      delete state.admittedRequests[requestId];
      state.periodCounters.inFlight = Math.max(
        0,
        state.periodCounters.inFlight - 1,
      );
    }
  }
}

function sweepEphemeral(state: QuotaDoState, now: number): void {
  for (const [jti, entry] of Object.entries(state.jtiReplay)) {
    if (entry.expiresAt <= now) {
      delete state.jtiReplay[jti];
    }
  }

  for (const [key, entry] of Object.entries(state.idempotency)) {
    if (entry.expiresAt <= now) {
      delete state.idempotency[key];
    }
  }

  for (const [requestId, entry] of Object.entries(state.creditedRequests)) {
    if (entry.expiresAt <= now) {
      delete state.creditedRequests[requestId];
    }
  }

  sweepAbandonedAdmissions(state, now);
}

function maybeResetPeriod(state: QuotaDoState, entitlement: EntitlementSnapshot): void {
  const bounds = entitlement.period_bounds;

  if (
    state.periodBounds?.period_start === bounds.period_start &&
    state.periodBounds?.period_end === bounds.period_end
  ) {
    return;
  }

  const inFlight = state.periodCounters.inFlight;
  state.periodBounds = {
    period_start: bounds.period_start,
    period_end: bounds.period_end,
  };
  state.periodCounters = {
    ...initialPeriodCounters(),
    inFlight,
  };
}

function isQuotaExhausted(
  counters: PeriodCounters,
  entitlement: EntitlementSnapshot,
): boolean {
  return (
    counters.requestsUsed >= entitlement.request_quota ||
    counters.tokensUsed >= entitlement.token_cost_budget.token_budget ||
    counters.costUsed >= entitlement.token_cost_budget.cost_budget
  );
}

function isSoftThresholdCrossed(
  counters: PeriodCounters,
  entitlement: EntitlementSnapshot,
): boolean {
  const threshold = entitlement.soft_threshold;

  if (entitlement.request_quota > 0) {
    const ratio = counters.requestsUsed / entitlement.request_quota;
    if (ratio >= threshold) {
      return true;
    }
  }

  const tokenBudget = entitlement.token_cost_budget.token_budget;
  if (tokenBudget > 0) {
    const ratio = counters.tokensUsed / tokenBudget;
    if (ratio >= threshold) {
      return true;
    }
  }

  const costBudget = entitlement.token_cost_budget.cost_budget;
  if (costBudget > 0) {
    const ratio = counters.costUsed / costBudget;
    if (ratio >= threshold) {
      return true;
    }
  }

  return false;
}

function markIdempotencyOnCredit(
  state: QuotaDoState,
  requestId: string,
  partial: boolean,
): void {
  const nextState: IdempotencyRequestState = partial ? "cancelled" : "completed";

  for (const entry of Object.values(state.idempotency)) {
    if (entry.requestId === requestId) {
      entry.state = nextState;
      break;
    }
  }
}

export async function admissionRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: AdmissionRequest,
  now?: number,
): Promise<AdmissionResponse> {
  const timestamp = now ?? Date.now();

  return blockConcurrencyWhile(async () => {
    const state = await loadState(storage);

    assertInstallationBound(state, request.installationId);
    sweepEphemeral(state, timestamp);
    maybeResetPeriod(state, request.entitlement);

    if (state.jtiReplay[request.jti]) {
      await storage.put(STATE_KEY, state);
      return { kind: "admission", outcome: "replay" };
    }

    const existingIdempotency = state.idempotency[request.idempotencyKey];
    if (existingIdempotency) {
      await storage.put(STATE_KEY, state);
      return {
        kind: "admission",
        outcome: "idempotent",
        priorState: {
          requestReference: existingIdempotency.requestReference,
          state: existingIdempotency.state,
          requestId: existingIdempotency.requestId,
        },
      };
    }

    if (isQuotaExhausted(state.periodCounters, request.entitlement)) {
      await storage.put(STATE_KEY, state);
      return {
        kind: "admission",
        outcome: "quota_exhausted",
        period_end: request.entitlement.period_bounds.period_end,
      };
    }

    if (state.periodCounters.inFlight >= CONCURRENCY_LIMIT) {
      await storage.put(STATE_KEY, state);
      return { kind: "admission", outcome: "concurrency_exhausted" };
    }

    const requestId = crypto.randomUUID();
    const expiresAt = timestamp + EPHEMERAL_HORIZON_MS;

    if (state.boundInstallationId === undefined) {
      state.boundInstallationId = request.installationId;
    }

    state.jtiReplay[request.jti] = { expiresAt };
    state.idempotency[request.idempotencyKey] = {
      expiresAt,
      requestReference: request.requestReference,
      state: "admitted",
      requestId,
    };
    state.admittedRequests[requestId] = {
      requestReference: request.requestReference,
      admittedAt: timestamp,
    };
    state.periodCounters.inFlight += 1;

    const degraded = isSoftThresholdCrossed(
      state.periodCounters,
      request.entitlement,
    );

    await storage.put(STATE_KEY, state);
    return {
      kind: "admission",
      outcome: "admitted",
      requestId,
      ...(degraded ? { degraded: true } : {}),
    };
  });
}

export async function creditRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: CreditRequest,
  now?: number,
): Promise<CreditResponse> {
  const timestamp = now ?? Date.now();

  return blockConcurrencyWhile(async () => {
    const state = await loadState(storage);

    if (
      state.boundInstallationId !== undefined &&
      state.boundInstallationId !== request.installationId
    ) {
      return { kind: "credit", ok: false, code: "unknown_request" };
    }

    sweepEphemeral(state, timestamp);

    if (
      !state.admittedRequests[request.requestId] ||
      state.creditedRequests[request.requestId]
    ) {
      await storage.put(STATE_KEY, state);
      return { kind: "credit", ok: false, code: "unknown_request" };
    }

    state.periodCounters.tokensUsed += request.usage.tokens;
    state.periodCounters.costUsed += request.usage.cost;
    state.periodCounters.requestsUsed += 1;
    state.periodCounters.inFlight = Math.max(0, state.periodCounters.inFlight - 1);

    delete state.admittedRequests[request.requestId];
    state.creditedRequests[request.requestId] = {
      expiresAt: timestamp + EPHEMERAL_HORIZON_MS,
    };

    markIdempotencyOnCredit(state, request.requestId, request.partial);

    await storage.put(STATE_KEY, state);

    return {
      kind: "credit",
      ok: true,
      periodCounters: { ...state.periodCounters },
    };
  });
}
