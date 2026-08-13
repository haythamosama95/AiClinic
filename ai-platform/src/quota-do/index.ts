import type { Logger } from "../logger";
import { noopLogger } from "../logger";

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

/** Compensating release after stage-8 admission when stage-9 journal insert fails. */
export interface ReleaseRequest {
  kind: "release";
  installationId: string;
  requestId: string;
  idempotencyKey: string;
  jti: string;
}

export interface ReleaseAcknowledged {
  kind: "release";
  ok: true;
}

export interface ReleaseUnknownRequest {
  kind: "release";
  ok: false;
  code: "unknown_request";
}

export type ReleaseResponse = ReleaseAcknowledged | ReleaseUnknownRequest;

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

/**
 * Soft threshold is a fraction of period budget (§4.3.3 / F4 contract §2).
 * `0` disables soft degradation (enroll's zero-threshold case); `(0, 1]` is active.
 * Values outside `[0, 1]` are rejected by {@link isSoftThresholdFraction}.
 */
export function isSoftThresholdFraction(value: number): boolean {
  return Number.isFinite(value) && value >= 0 && value <= 1;
}

/** Coerce an out-of-range soft_threshold to `0` (never degrade). */
export function coerceSoftThreshold(value: number): number {
  return isSoftThresholdFraction(value) ? value : 0;
}

/** Soft-threshold predicate (exported for F4 boundary tests). Hard exhaustion is separate. */
export function isSoftThresholdCrossed(
  counters: PeriodCounters,
  entitlement: EntitlementSnapshot,
): boolean {
  const threshold = entitlement.soft_threshold;
  // Zero (or non-positive) threshold never degrades — enroll and "disabled" sentinel.
  // Thresholds > 1 never fire before hard exhaustion; treat as inactive.
  if (!(threshold > 0) || threshold > 1) {
    return false;
  }

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
  logger: Logger = noopLogger,
): Promise<AdmissionResponse> {
  const timestamp = now ?? Date.now();

  return blockConcurrencyWhile(async () => {
    const state = await loadState(storage);

    assertInstallationBound(state, request.installationId);
    sweepEphemeral(state, timestamp);
    maybeResetPeriod(state, request.entitlement);

    if (state.jtiReplay[request.jti]) {
      logger.info("Admission replay detected", {
        installation_id: request.installationId,
        jti: request.jti,
      });
      await storage.put(STATE_KEY, state);
      return { kind: "admission", outcome: "replay" };
    }

    const existingIdempotency = state.idempotency[request.idempotencyKey];
    if (existingIdempotency) {
      logger.info("Admission idempotent replay", {
        installation_id: request.installationId,
        request_id: existingIdempotency.requestId,
        prior_state: existingIdempotency.state,
      });
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
      logger.info("Admission quota exhausted", {
        installation_id: request.installationId,
      });
      await storage.put(STATE_KEY, state);
      return {
        kind: "admission",
        outcome: "quota_exhausted",
        period_end: request.entitlement.period_bounds.period_end,
      };
    }

    if (state.periodCounters.inFlight >= CONCURRENCY_LIMIT) {
      logger.info("Admission concurrency exhausted", {
        installation_id: request.installationId,
        in_flight: state.periodCounters.inFlight,
      });
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
    logger.info("Admission granted", {
      installation_id: request.installationId,
      request_id: requestId,
      degraded,
    });
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
  logger: Logger = noopLogger,
): Promise<CreditResponse> {
  const timestamp = now ?? Date.now();

  return blockConcurrencyWhile(async () => {
    const state = await loadState(storage);

    if (
      state.boundInstallationId !== undefined &&
      state.boundInstallationId !== request.installationId
    ) {
      logger.info("Credit rejected — unknown request", {
        installation_id: request.installationId,
        request_id: request.requestId,
      });
      return { kind: "credit", ok: false, code: "unknown_request" };
    }

    sweepEphemeral(state, timestamp);

    if (
      !state.admittedRequests[request.requestId] ||
      state.creditedRequests[request.requestId]
    ) {
      await storage.put(STATE_KEY, state);
      logger.info("Credit rejected — unknown request", {
        installation_id: request.installationId,
        request_id: request.requestId,
      });
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

    logger.info("Credit applied", {
      installation_id: request.installationId,
      request_id: request.requestId,
      partial: request.partial,
      tokens: request.usage.tokens,
      cost: request.usage.cost,
    });

    return {
      kind: "credit",
      ok: true,
      periodCounters: { ...state.periodCounters },
    };
  });
}

/**
 * Roll back a stage-8 admission reservation when stage-9 journal insert fails:
 * drop jti replay, idempotency key, and in-flight slot for `requestId`.
 */
export async function releaseRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: ReleaseRequest,
  now?: number,
  logger: Logger = noopLogger,
): Promise<ReleaseResponse> {
  const timestamp = now ?? Date.now();

  return blockConcurrencyWhile(async () => {
    const state = await loadState(storage);

    if (
      state.boundInstallationId !== undefined &&
      state.boundInstallationId !== request.installationId
    ) {
      logger.info("Release rejected — unknown request", {
        installation_id: request.installationId,
        request_id: request.requestId,
      });
      return { kind: "release", ok: false, code: "unknown_request" };
    }

    sweepEphemeral(state, timestamp);

    const admitted = state.admittedRequests[request.requestId];
    if (!admitted) {
      await storage.put(STATE_KEY, state);
      logger.info("Release rejected — unknown request", {
        installation_id: request.installationId,
        request_id: request.requestId,
      });
      return { kind: "release", ok: false, code: "unknown_request" };
    }

    delete state.admittedRequests[request.requestId];
    state.periodCounters.inFlight = Math.max(0, state.periodCounters.inFlight - 1);

    const idempotency = state.idempotency[request.idempotencyKey];
    if (idempotency?.requestId === request.requestId) {
      delete state.idempotency[request.idempotencyKey];
    }

    delete state.jtiReplay[request.jti];

    await storage.put(STATE_KEY, state);
    logger.info("Admission reservation released", {
      installation_id: request.installationId,
      request_id: request.requestId,
    });
    return { kind: "release", ok: true };
  });
}
