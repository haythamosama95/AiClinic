import { coverageEventId } from "vendor-contracts";
import { addDuration, type DurationScale } from "../coverage/calendar";
import type { TaxonomyCode } from "../errors";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";
import {
  allowanceBand,
  applyDueBoundaries,
  buildCoverageSnapshot,
  computeGraceAllowance,
  insertOutbox,
  loadHot,
  loadTerms,
  resolveOrgIdFromStorage,
  sqlSelect,
  type HotRow,
  type TermRow,
  updateHot,
} from "./coverage";

export const EPHEMERAL_HORIZON_MS = 7_200_000;
export const CONCURRENCY_LIMIT = 16;
const STALE_RESERVATION_MS = 15 * 60 * 1000;
const CONCURRENCY_RETRY_AFTER_SECONDS = 60;

const STATE_KEY = "state";

export interface EphemeralEntry {
  expiresAt: number;
}

export type JtiReplayEntry = EphemeralEntry;

export const IDEMPOTENCY_STATES = [
  "admitted",
  "completed",
  "failed",
  "cancelled",
] as const;

export type IdempotencyRequestState = (typeof IDEMPOTENCY_STATES)[number];

export interface IdempotencyEntry extends EphemeralEntry {
  requestReference: string;
  state: IdempotencyRequestState;
  requestId: string;
  terminalErrorCode?: TaxonomyCode;
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
  credit_budget: number;
  allowed_capabilities: string[];
  soft_threshold: number;
  status: string;
}

export interface PeriodCounters {
  requestsUsed: number;
  tokensUsed: number;
  costUsed: number;
  creditsUsed: number;
  inFlight: number;
}

export interface QuotaDoState {
  periodCounters: PeriodCounters;
  periodBounds?: { period_start: string; period_end: string };
  jtiReplay: Record<string, JtiReplayEntry>;
  idempotency: Record<string, IdempotencyEntry>;
  creditedRequests: Record<string, { expiresAt: number }>;
  admittedRequests: Record<string, {
    requestReference: string;
    admittedAt: number;
    entitlement: EntitlementSnapshot;
  }>;
  boundInstallationId?: string;
}

export interface AdmissionRequest {
  kind: "admission";
  jti: string;
  installationId: string;
  idempotencyKey: string;
  entitlement?: EntitlementSnapshot;
  requestReference: string;
  capabilityId?: string;
  quotaWeight?: number;
  orgId?: string;
  vendorContractVersion?: number;
  nowIso?: string;
  durationScale?: DurationScale;
  requestId?: string;
}

export interface SettleFallbackRequest {
  kind: "settleFallback";
  installationId: string;
  request_id: string;
  term_id: string;
  weight: number;
}

export type SettleFallbackResponse =
  | { kind: "settleFallback"; outcome: "settled" }
  | { kind: "settleFallback"; outcome: "skipped" };

export interface IdempotencyPriorState {
  requestReference: string;
  state: IdempotencyRequestState;
  requestId: string;
  traceId?: string;
  terminalErrorCode?: TaxonomyCode;
}

export interface AdmissionAdmitted {
  kind: "admission";
  outcome: "admitted";
  requestId: string;
  reservation_id?: string;
  term_id?: string;
  snapshot?: { capabilities: string[]; max_cost_class: string };
  band?: "ok" | "75" | "90" | "exhausted";
  degraded?: boolean;
}

export interface AdmissionTermRefusal {
  kind: "admission";
  outcome:
    | "suspended"
    | "allowance_exhausted"
    | "coverage_lapsed"
    | "forbidden_capability"
    | "concurrency_limited";
  coverage_reason?:
    | "none"
    | "expired"
    | "grace_exhausted"
    | "reversed"
    | "transferred"
    | "transfer_pending";
  retry_after?: number;
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
  | AdmissionTermRefusal
  | AdmissionReplay
  | AdmissionIdempotent
  | AdmissionQuotaExhausted
  | AdmissionConcurrencyExhausted;

export interface UsageActual {
  tokens: number;
  cost: number;
}

export type CreditIdempotencyState = Extract<
  IdempotencyRequestState,
  "completed" | "failed" | "cancelled"
>;

export interface CreditRequest {
  kind: "credit";
  installationId: string;
  requestId: string;
  reservation_id?: string;
  requestReference: string;
  usage: UsageActual;
  partial: boolean;
  credits: number;
  idempotencyState?: CreditIdempotencyState;
  terminalErrorCode?: TaxonomyCode;
  entitlement?: EntitlementSnapshot;
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
    creditsUsed: 0,
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

      for (const idempotency of Object.values(state.idempotency)) {
        if (
          idempotency.requestId === requestId &&
          idempotency.state === "admitted"
        ) {
          idempotency.state = "failed";
          idempotency.expiresAt = now + EPHEMERAL_HORIZON_MS;
          break;
        }
      }
    }
  }
}

function sweepEphemeral(state: QuotaDoState, now: number): void {
  for (const [jti, entry] of Object.entries(state.jtiReplay)) {
    if (entry.expiresAt <= now) {
      delete state.jtiReplay[jti];
    }
  }

  sweepAbandonedAdmissions(state, now);

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
    counters.creditsUsed >= entitlement.credit_budget
  );
}

function hasCoverageHotRow(storage: DurableObjectStorage): boolean {
  return sqlSelect<{ n: number }>(storage, "SELECT 1 AS n FROM hot LIMIT 1").length > 0;
}

function usesLegacyEntitlementAdmission(request: AdmissionRequest): boolean {
  return request.entitlement !== undefined;
}

function usesLegacyEntitlementCredit(request: CreditRequest): boolean {
  return request.entitlement !== undefined;
}

async function shouldUseLegacyCredit(
  storage: DurableObjectStorage,
  request: CreditRequest,
): Promise<boolean> {
  if (usesLegacyEntitlementCredit(request) || !hasCoverageHotRow(storage)) {
    return true;
  }
  const state = await loadState(storage);
  return (
    state.admittedRequests[request.requestId] !== undefined ||
    state.creditedRequests[request.requestId] !== undefined
  );
}

async function mirrorProductionCreditToLegacy(
  storage: DurableObjectStorage,
  request: CreditRequest,
  timestamp: number,
): Promise<PeriodCounters> {
  const state = await loadState(storage);
  sweepEphemeral(state, timestamp);
  const credits = request.credits ?? 1;
  state.periodCounters.tokensUsed += request.usage.tokens;
  state.periodCounters.costUsed += request.usage.cost;
  state.periodCounters.creditsUsed += credits;
  state.periodCounters.requestsUsed += 1;
  await storage.put(STATE_KEY, state);
  return { ...state.periodCounters };
}

async function applyFallbackWeightToLegacy(
  storage: DurableObjectStorage,
  weight: number,
): Promise<void> {
  const state = await loadState(storage);
  state.periodCounters.requestsUsed += weight;
  state.periodCounters.creditsUsed += weight;
  await storage.put(STATE_KEY, state);
}

async function admissionOnLegacyState(
  storage: DurableObjectStorage,
  request: AdmissionRequest,
  timestamp: number,
  logger: Logger,
): Promise<AdmissionResponse> {
  const entitlement = request.entitlement;
  if (entitlement === undefined) {
    return {
      kind: "admission",
      outcome: "coverage_lapsed",
      coverage_reason: "none",
    };
  }

  const state = await loadState(storage);

  assertInstallationBound(state, request.installationId);
  sweepEphemeral(state, timestamp);
  maybeResetPeriod(state, entitlement);

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
        ...(existingIdempotency.terminalErrorCode !== undefined
          ? { terminalErrorCode: existingIdempotency.terminalErrorCode }
          : {}),
      },
    };
  }

  if (isQuotaExhausted(state.periodCounters, entitlement)) {
    logger.info("Admission quota exhausted", {
      installation_id: request.installationId,
    });
    await storage.put(STATE_KEY, state);
    return {
      kind: "admission",
      outcome: "quota_exhausted",
      period_end: entitlement.period_bounds.period_end,
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
    entitlement,
  };
  state.periodCounters.inFlight += 1;

  const degraded = isSoftThresholdCrossed(state.periodCounters, entitlement);

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
}

async function creditOnLegacyState(
  storage: DurableObjectStorage,
  request: CreditRequest,
  timestamp: number,
  logger: Logger,
): Promise<CreditResponse> {
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

  const admitted = state.admittedRequests[request.requestId];
  const entitlement = request.entitlement ?? admitted.entitlement;
  if (entitlement) {
    maybeResetPeriod(state, entitlement);
  }

  const credits = request.credits ?? 1;
  state.periodCounters.tokensUsed += request.usage.tokens;
  state.periodCounters.costUsed += request.usage.cost;
  state.periodCounters.creditsUsed += credits;
  state.periodCounters.requestsUsed += 1;
  state.periodCounters.inFlight = Math.max(0, state.periodCounters.inFlight - 1);

  delete state.admittedRequests[request.requestId];
  state.creditedRequests[request.requestId] = {
    expiresAt: timestamp + EPHEMERAL_HORIZON_MS,
  };

  markIdempotencyOnCredit(
    state,
    request.requestId,
    request.partial,
    timestamp,
    request.idempotencyState,
    request.terminalErrorCode,
  );

  await storage.put(STATE_KEY, state);

  logger.info("Credit applied", {
    installation_id: request.installationId,
    request_id: request.requestId,
    partial: request.partial,
    tokens: request.usage.tokens,
    cost: request.usage.cost,
    credits,
  });

  return {
    kind: "credit",
    ok: true,
    periodCounters: { ...state.periodCounters },
  };
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

  const creditBudget = entitlement.credit_budget;
  if (creditBudget > 0) {
    const ratio = counters.creditsUsed / creditBudget;
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
  now: number,
  idempotencyState?: CreditIdempotencyState,
  terminalErrorCode?: TaxonomyCode,
): void {
  const nextState: IdempotencyRequestState =
    idempotencyState ?? (partial ? "cancelled" : "completed");

  for (const entry of Object.values(state.idempotency)) {
    if (entry.requestId === requestId) {
      entry.state = nextState;
      entry.expiresAt = now + EPHEMERAL_HORIZON_MS;
      if (nextState === "failed" && terminalErrorCode !== undefined) {
        entry.terminalErrorCode = terminalErrorCode;
      }
      break;
    }
  }
}

type ReservationRow = {
  id: string;
  weight: number;
  term_id: string;
  capability: string;
  admitted_at: number;
};

type StoredAnswerEntry = {
  expiresAt: number;
  answer: AdmissionResponse;
};

type TermBandEmitted = Record<string, boolean>;

type ParsedHot = {
  row: HotRow;
  reservations: ReservationRow[];
  replay: Record<string, StoredAnswerEntry>;
  idempotency: Record<string, StoredAnswerEntry>;
  /** Per-term band flags (`term_id` → `{ "75"?, "90"? }`). */
  band_emitted: Record<string, TermBandEmitted>;
};

function parseHotRow(row: HotRow): ParsedHot {
  return {
    row,
    reservations: JSON.parse(row.reservations || "[]") as ReservationRow[],
    replay: JSON.parse(row.replay || "{}") as Record<string, StoredAnswerEntry>,
    idempotency: JSON.parse(row.idempotency || "{}") as Record<
      string,
      StoredAnswerEntry
    >,
    band_emitted: parseBandEmitted(row.band_emitted || "{}"),
  };
}

function parseBandEmitted(raw: string): Record<string, TermBandEmitted> {
  const parsed = JSON.parse(raw) as Record<string, unknown>;
  const perTerm: Record<string, TermBandEmitted> = {};
  for (const [key, value] of Object.entries(parsed)) {
    if (value === true && (key === "75" || key === "90")) {
      // Legacy clinic-wide flags — ignore; bands are tracked per term now.
      continue;
    }
    if (value && typeof value === "object" && !Array.isArray(value)) {
      perTerm[key] = value as TermBandEmitted;
    }
  }
  return perTerm;
}

function termBandFlags(hot: ParsedHot, termId: string): TermBandEmitted {
  if (hot.band_emitted[termId] === undefined) {
    hot.band_emitted[termId] = {};
  }
  return hot.band_emitted[termId]!;
}

function persistParsedHot(storage: DurableObjectStorage, hot: ParsedHot): void {
  updateHot(storage, {
    used: hot.row.used,
    reserved: hot.row.reserved,
    grace_base_used: hot.row.grace_base_used,
    active_term_id: hot.row.active_term_id,
    suspended: hot.row.suspended,
    clinic_seq: hot.row.clinic_seq,
    next_alarm_at: hot.row.next_alarm_at,
    reservations: JSON.stringify(hot.reservations),
    replay: JSON.stringify(hot.replay),
    idempotency: JSON.stringify(hot.idempotency),
    band_emitted: JSON.stringify(hot.band_emitted),
  });
}

function sweepStoredAnswers(
  hot: ParsedHot,
  now: number,
): void {
  for (const [key, entry] of Object.entries(hot.replay)) {
    if (entry.expiresAt <= now) {
      delete hot.replay[key];
    }
  }
  for (const [key, entry] of Object.entries(hot.idempotency)) {
    if (entry.expiresAt <= now) {
      delete hot.idempotency[key];
    }
  }
}

function storeAnswer(
  hot: ParsedHot,
  jti: string,
  idempotencyKey: string,
  answer: AdmissionResponse,
  now: number,
): void {
  const expiresAt = now + EPHEMERAL_HORIZON_MS;
  hot.replay[jti] = { expiresAt, answer };
  hot.idempotency[idempotencyKey] = { expiresAt, answer };
}

function returnStoredAdmission(
  storage: DurableObjectStorage,
  hot: ParsedHot,
  request: AdmissionRequest,
  answer: AdmissionResponse,
  now: number,
): AdmissionResponse {
  storeAnswer(hot, request.jti, request.idempotencyKey, answer, now);
  persistParsedHot(storage, hot);
  return answer;
}

function adjustEndedTermUsedFinal(
  storage: DurableObjectStorage,
  termId: string,
  delta: number,
): void {
  sqlExecLocal(
    storage,
    `UPDATE term SET used_final = CASE
       WHEN COALESCE(used_final, 0) + (${delta}) < 0 THEN 0
       ELSE COALESCE(used_final, 0) + (${delta})
     END
     WHERE term_id = ${sqlStringLocal(termId)}`,
  );
}

function planSnapshotForTerm(term: TermRow): {
  capabilities: string[];
  max_cost_class: string;
  concurrency_limit: number;
} {
  const snapshot = JSON.parse(term.plan_snapshot) as {
    capabilities?: unknown;
    max_cost_class?: string;
    concurrency_limit?: number;
  };
  const capabilities = Array.isArray(snapshot.capabilities)
    ? (snapshot.capabilities as string[])
    : [];
  return {
    capabilities,
    max_cost_class: snapshot.max_cost_class ?? "standard",
    concurrency_limit: snapshot.concurrency_limit ?? CONCURRENCY_LIMIT,
  };
}

function resolveCapabilityId(request: AdmissionRequest): string {
  if (request.capabilityId) {
    return request.capabilityId;
  }
  const allowed = request.entitlement.allowed_capabilities;
  if (allowed.length > 0) {
    return allowed[0]!;
  }
  return "clinic.visit_summary";
}

function resolveQuotaWeight(request: AdmissionRequest): number {
  const weight = request.quotaWeight ?? 1;
  return weight > 0 ? weight : 1;
}

function activeOrGraceTerm(terms: TermRow[]): TermRow | undefined {
  return terms.find((term) => term.state === "active" || term.state === "grace");
}

function lastEndedTerm(terms: TermRow[]): TermRow | undefined {
  const ended = terms.filter((term) => term.state === "ended" || term.state === "exhausted");
  if (ended.length === 0) {
    return undefined;
  }
  return ended.sort((left, right) => right.position - left.position)[0];
}

function coverageLapseReason(terms: TermRow[]): AdmissionTermRefusal["coverage_reason"] {
  if (terms.length === 0) {
    return "none";
  }
  const last = lastEndedTerm(terms);
  if (last === undefined) {
    return "none";
  }
  if (last.end_reason === "expired") {
    return "expired";
  }
  if (last.end_reason === "grace_exhausted") {
    return "grace_exhausted";
  }
  if (last.end_reason === "reversed") {
    return "reversed";
  }
  if (last.state === "ended" && last.end_reason === "transferred") {
    return "transferred";
  }
  return "none";
}

function chargeStaleReservations(
  storage: DurableObjectStorage,
  hot: ParsedHot,
  installationId: string,
  now: number,
  nowIso: string,
): boolean {
  let changed = false;
  const remaining: ReservationRow[] = [];
  for (const reservation of hot.reservations) {
    if (now - reservation.admitted_at > STALE_RESERVATION_MS) {
      if (reservation.term_id === hot.row.active_term_id) {
        hot.row.used += reservation.weight;
      }
      hot.row.reserved = Math.max(0, hot.row.reserved - reservation.weight);
      insertOutbox(storage, "usage_adjustment", {
        request_id: reservation.id,
        installation_id: installationId,
        term_id: reservation.term_id,
        quota_weight: reservation.weight,
        tokens: 0,
        cost: 0,
        recorded_at: nowIso,
      });
      changed = true;
      continue;
    }
    remaining.push(reservation);
  }
  hot.reservations = remaining;
  return changed;
}

function endGraceIfExhausted(
  storage: DurableObjectStorage,
  hot: ParsedHot,
  graceTerm: TermRow,
  context: {
    installationId: string;
    orgId: string;
    vendorContractVersion: number;
    durationScale?: DurationScale;
    nowIso: string;
  },
): boolean {
  const graceUsed =
    hot.row.used + hot.row.reserved - hot.row.grace_base_used;
  const graceAllowance = computeGraceAllowance(
    graceTerm,
    hot.row.grace_base_used,
  );
  if (graceUsed < graceAllowance) {
    return false;
  }
  const usedFinal = hot.row.used + hot.row.reserved;
  sqlExecLocal(
    storage,
    `UPDATE term SET state = 'ended', end_reason = 'grace_exhausted', used_final = ${usedFinal}, ended_at = ${sqlStringLocal(context.nowIso)}
     WHERE term_id = ${sqlStringLocal(graceTerm.term_id)}`,
  );
  const terms = loadTerms(storage);
  hot.row.active_term_id = null;
  hot.row.grace_base_used = 0;
  hot.row.clinic_seq += 1;
  const endedSnapshot = buildCoverageSnapshot({
    vendorContractVersion: context.vendorContractVersion,
    orgId: context.orgId,
    hot: hot.row,
    terms,
    durationScale: context.durationScale,
  });
  insertOutbox(storage, "coverage_event", {
    event_id: coverageEventId(context.installationId, hot.row.clinic_seq),
    org_id: context.orgId,
    installation_id: context.installationId,
    binding_epoch: hot.row.binding_epoch,
    clinic_seq: hot.row.clinic_seq,
    kind: "term_ended",
    at: context.nowIso,
    snapshot: endedSnapshot,
  });
  return true;
}

function emitBandCrossedIfNeeded(
  storage: DurableObjectStorage,
  hot: ParsedHot,
  terms: TermRow[],
  request: AdmissionRequest,
  termId: string,
  usageTotal: number,
  allowance: number,
  nowIso: string,
): void {
  if (!(allowance > 0)) {
    return;
  }
  const orgId = request.orgId ?? "";
  const vendorVersion = request.vendorContractVersion ?? 1;
  const bandFlags = termBandFlags(hot, termId);
  const bands: Array<"75" | "90"> = [];
  if (
    usageTotal * 4 >= allowance * 3 &&
    !bandFlags["75"]
  ) {
    bands.push("75");
  }
  if (
    usageTotal * 10 >= allowance * 9 &&
    !bandFlags["90"]
  ) {
    bands.push("90");
  }
  for (const band of bands) {
    bandFlags[band] = true;
    hot.row.clinic_seq += 1;
    const snapshot = buildCoverageSnapshot({
      vendorContractVersion: vendorVersion,
      orgId,
      hot: hot.row,
      terms,
      durationScale: request.durationScale,
    });
    const term = snapshot.term as Record<string, unknown> | null;
    if (term) {
      term.band = band;
    }
    insertOutbox(storage, "coverage_event", {
      event_id: coverageEventId(request.installationId, hot.row.clinic_seq),
      org_id: orgId,
      installation_id: request.installationId,
      binding_epoch: hot.row.binding_epoch,
      clinic_seq: hot.row.clinic_seq,
      kind: "band_crossed",
      at: nowIso,
      snapshot,
    });
    bandFlags[band] = true;
  }
}

function activateSuccessorTerm(
  storage: DurableObjectStorage,
  hot: ParsedHot,
  terms: TermRow[],
  nowIso: string,
  durationScale?: DurationScale,
): TermRow | undefined {
  const queued = terms
    .filter((term) => term.state === "queued")
    .sort((left, right) => left.position - right.position)[0];
  if (queued === undefined) {
    hot.row.active_term_id = null;
    return undefined;
  }
  const durationUnit = (queued.duration_unit ?? "month") as "month" | "day";
  const durationCount = queued.duration_count ?? 1;
  const startsAt = nowIso;
  const endsAt = addDuration(startsAt, durationUnit, durationCount, durationScale);
  sqlExecLocal(
    storage,
    `UPDATE term SET state = 'active', starts_at = ${sqlStringLocal(startsAt)}, ends_at = ${sqlStringLocal(endsAt)}, calendar_start = ${sqlStringLocal(startsAt)}
     WHERE term_id = ${sqlStringLocal(queued.term_id)}`,
  );
  hot.row.active_term_id = queued.term_id;
  hot.row.used = 0;
  return { ...queued, state: "active", starts_at: startsAt, ends_at: endsAt };
}

type SqlStorage = DurableObjectStorage & {
  sql?: { exec: (query: string) => unknown };
};

function sqlExecLocal(storage: DurableObjectStorage, query: string): void {
  const sqlStorage = storage as SqlStorage;
  sqlStorage.sql?.exec(query);
}

function sqlStringLocal(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

function admitOnHotRow(
  storage: DurableObjectStorage,
  request: AdmissionRequest,
  now: number,
  logger: Logger,
): AdmissionResponse {
  const hotRows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
  if (hotRows.length === 0) {
    return {
      kind: "admission",
      outcome: "coverage_lapsed",
      coverage_reason: "none",
    };
  }

  let hot = parseHotRow(hotRows[0]!);
  sweepStoredAnswers(hot, now);

  const replayEntry = hot.replay[request.jti];
  if (replayEntry) {
    return replayEntry.answer;
  }
  const idempotencyEntry = hot.idempotency[request.idempotencyKey];
  if (idempotencyEntry) {
    return idempotencyEntry.answer;
  }

  const nowIso =
    request.nowIso ?? new Date(now).toISOString();
  let terms = loadTerms(storage);
  let stateChanged = chargeStaleReservations(
    storage,
    hot,
    request.installationId,
    now,
    nowIso,
  );
  if (stateChanged) {
    persistParsedHot(storage, hot);
  }

  const persistIfChanged = (): void => {
    if (stateChanged) {
      persistParsedHot(storage, hot);
    }
  };

  applyDueBoundaries({
    storage,
    clockNowIso: nowIso,
    installationId: request.installationId,
    orgId: request.orgId ?? "",
    vendorContractVersion: request.vendorContractVersion ?? 1,
    durationScale: request.durationScale,
  });
  const hotReloaded = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1")[0];
  if (hotReloaded !== undefined) {
    hot = parseHotRow(hotReloaded);
  }
  terms = loadTerms(storage);

  const capabilityId = resolveCapabilityId(request);
  const quotaWeight = resolveQuotaWeight(request);

  if (hot.row.transfer_pending !== 0) {
    persistIfChanged();
    return returnStoredAdmission(storage, hot, request, {
      kind: "admission",
      outcome: "coverage_lapsed",
      coverage_reason: "transfer_pending",
    }, now);
  }

  if (hot.row.suspended !== 0) {
    persistIfChanged();
    return returnStoredAdmission(storage, hot, request, {
      kind: "admission",
      outcome: "suspended",
    }, now);
  }

  const billableTerm = activeOrGraceTerm(terms);
  if (billableTerm === undefined) {
    const last = lastEndedTerm(terms);
    persistIfChanged();
    if (last?.state === "exhausted" || last?.end_reason === "exhausted") {
      return returnStoredAdmission(storage, hot, request, {
        kind: "admission",
        outcome: "allowance_exhausted",
      }, now);
    }
    return returnStoredAdmission(storage, hot, request, {
      kind: "admission",
      outcome: "coverage_lapsed",
      coverage_reason: coverageLapseReason(terms),
    }, now);
  }

  const plan = planSnapshotForTerm(billableTerm);
  if (!plan.capabilities.includes(capabilityId)) {
    persistIfChanged();
    return returnStoredAdmission(storage, hot, request, {
      kind: "admission",
      outcome: "forbidden_capability",
    }, now);
  }

  if (hot.reservations.length >= plan.concurrency_limit) {
    persistIfChanged();
    return returnStoredAdmission(storage, hot, request, {
      kind: "admission",
      outcome: "concurrency_limited",
      retry_after: CONCURRENCY_RETRY_AFTER_SECONDS,
    }, now);
  }

  const allowance = billableTerm.allowance ?? 0;
  const creditsRemaining =
    billableTerm.state === "grace"
      ? computeGraceAllowance(billableTerm, hot.row.grace_base_used) -
        (hot.row.used + hot.row.reserved - hot.row.grace_base_used)
      : allowance - hot.row.used - hot.row.reserved;
  if (creditsRemaining < 1) {
    if (billableTerm.state === "grace") {
      const graceEnded = endGraceIfExhausted(storage, hot, billableTerm, {
        installationId: request.installationId,
        orgId: request.orgId ?? "",
        vendorContractVersion: request.vendorContractVersion ?? 1,
        durationScale: request.durationScale,
        nowIso,
      });
      if (graceEnded) {
        stateChanged = true;
      }
      persistIfChanged();
      return returnStoredAdmission(storage, hot, request, {
        kind: "admission",
        outcome: "coverage_lapsed",
        coverage_reason: "grace_exhausted",
      }, now);
    }
    persistIfChanged();
    return returnStoredAdmission(storage, hot, request, {
      kind: "admission",
      outcome: "allowance_exhausted",
    }, now);
  }

  const reservationId = request.requestId ?? crypto.randomUUID();
  hot.reservations.push({
    id: reservationId,
    weight: quotaWeight,
    term_id: billableTerm.term_id,
    capability: capabilityId,
    admitted_at: now,
  });
  hot.row.reserved += quotaWeight;

  const admittingTermId = billableTerm.term_id;
  const usageTotal = hot.row.used + hot.row.reserved;
  const willExhaust =
    billableTerm.state === "active" && usageTotal >= allowance;

  emitBandCrossedIfNeeded(
    storage,
    hot,
    terms,
    request,
    admittingTermId,
    usageTotal,
    allowance,
    nowIso,
  );

  if (willExhaust) {
    const usedFinal = hot.row.used + hot.row.reserved;
    sqlExecLocal(
      storage,
      `UPDATE term SET state = 'exhausted', end_reason = 'exhausted', used_final = ${usedFinal}, ended_at = ${sqlStringLocal(nowIso)}
       WHERE term_id = ${sqlStringLocal(billableTerm.term_id)}`,
    );
    terms = loadTerms(storage);
    const orgId = request.orgId ?? "";
    const vendorVersion = request.vendorContractVersion ?? 1;
    hot.row.clinic_seq += 1;
    const endedSnapshot = buildCoverageSnapshot({
      vendorContractVersion: vendorVersion,
      orgId,
      hot: hot.row,
      terms,
      durationScale: request.durationScale,
    });
    insertOutbox(storage, "coverage_event", {
      event_id: coverageEventId(request.installationId, hot.row.clinic_seq),
      org_id: orgId,
      installation_id: request.installationId,
      binding_epoch: hot.row.binding_epoch,
      clinic_seq: hot.row.clinic_seq,
      kind: "term_ended",
      at: nowIso,
      snapshot: endedSnapshot,
    });

    const successor = activateSuccessorTerm(
      storage,
      hot,
      loadTerms(storage),
      nowIso,
      request.durationScale,
    );
    if (successor !== undefined) {
      terms = loadTerms(storage);
      hot.row.clinic_seq += 1;
      const activatedSnapshot = buildCoverageSnapshot({
        vendorContractVersion: vendorVersion,
        orgId,
        hot: hot.row,
        terms,
        durationScale: request.durationScale,
      });
      insertOutbox(storage, "coverage_event", {
        event_id: coverageEventId(request.installationId, hot.row.clinic_seq),
        org_id: orgId,
        installation_id: request.installationId,
        binding_epoch: hot.row.binding_epoch,
        clinic_seq: hot.row.clinic_seq,
        kind: "term_activated",
        at: nowIso,
        snapshot: activatedSnapshot,
      });
    }
  }

  if (billableTerm.state === "grace") {
    if (
      endGraceIfExhausted(storage, hot, billableTerm, {
        installationId: request.installationId,
        orgId: request.orgId ?? "",
        vendorContractVersion: request.vendorContractVersion ?? 1,
        durationScale: request.durationScale,
        nowIso,
      })
    ) {
      stateChanged = true;
    }
  }

  const admittedAnswer: AdmissionAdmitted = {
    kind: "admission",
    outcome: "admitted",
    requestId: reservationId,
    reservation_id: reservationId,
    term_id: admittingTermId,
    snapshot: {
      capabilities: plan.capabilities,
      max_cost_class: plan.max_cost_class,
    },
    band: allowanceBand(
      usageTotal,
      allowance,
      willExhaust ? "exhausted" : billableTerm.state,
    ),
  };

  storeAnswer(hot, request.jti, request.idempotencyKey, admittedAnswer, now);
  persistParsedHot(storage, hot);

  logger.info("Term admission granted", {
    installation_id: request.installationId,
    reservation_id: reservationId,
    term_id: billableTerm.term_id,
  });

  return admittedAnswer;
}

function hotRowInstallationMismatch(
  _storage: DurableObjectStorage,
  _installationId: string,
): boolean {
  return false;
}

function settleReservationOnHot(
  storage: DurableObjectStorage,
  request: CreditRequest,
  now: number,
): CreditResponse {
  const hotRows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
  if (hotRows.length === 0) {
    return { kind: "credit", ok: false, code: "unknown_request" };
  }

  let hot = parseHotRow(hotRows[0]!);
  sweepStoredAnswers(hot, now);

  const reservationId = request.reservation_id ?? request.requestId;
  const index = hot.reservations.findIndex(
    (reservation) => reservation.id === reservationId,
  );
  if (index < 0) {
    persistParsedHot(storage, hot);
    return {
      kind: "credit",
      ok: true,
      periodCounters: { ...legacyCountersFromHot(hot.row) },
    };
  }

  const reservation = hot.reservations[index]!;
  const consumed =
    request.usage.tokens > 0 || request.usage.cost > 0;
  const onActiveTerm =
    hot.row.active_term_id !== null &&
    reservation.term_id === hot.row.active_term_id;
  if (consumed) {
    if (onActiveTerm) {
      hot.row.used += reservation.weight;
    }
  } else if (!onActiveTerm) {
    adjustEndedTermUsedFinal(storage, reservation.term_id, -reservation.weight);
  }
  hot.row.reserved = Math.max(0, hot.row.reserved - reservation.weight);
  hot.reservations.splice(index, 1);

  const nowIso = new Date(now).toISOString();
  const terms = loadTerms(storage);
  const graceTerm = terms.find(
    (term) =>
      term.state === "grace" && term.term_id === hot.row.active_term_id,
  );
  if (graceTerm !== undefined) {
    endGraceIfExhausted(storage, hot, graceTerm, {
      installationId: request.installationId,
      orgId: resolveOrgIdFromStorage(storage),
      vendorContractVersion: 1,
      nowIso,
    });
  }

  persistParsedHot(storage, hot);
  return {
    kind: "credit",
    ok: true,
    periodCounters: { ...legacyCountersFromHot(hot.row) },
  };
}

function legacyCountersFromHot(row: HotRow): PeriodCounters {
  return {
    requestsUsed: row.used,
    tokensUsed: 0,
    costUsed: 0,
    creditsUsed: row.used,
    inFlight: hotReservationCount(row),
  };
}

function hotReservationCount(row: HotRow): number {
  const reservations = JSON.parse(row.reservations || "[]") as ReservationRow[];
  return reservations.length;
}

function admittedRequestIdFromAnswer(answer: AdmissionResponse): string | undefined {
  if (answer.kind !== "admission" || answer.outcome !== "admitted") {
    return undefined;
  }
  return answer.requestId;
}

function hotStillHoldsRequestId(hot: ParsedHot, requestId: string): boolean {
  if (hot.reservations.some((reservation) => reservation.id === requestId)) {
    return true;
  }
  for (const entry of Object.values(hot.replay)) {
    if (admittedRequestIdFromAnswer(entry.answer) === requestId) {
      return true;
    }
  }
  for (const entry of Object.values(hot.idempotency)) {
    if (admittedRequestIdFromAnswer(entry.answer) === requestId) {
      return true;
    }
  }
  return false;
}

export async function settleFallbackRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: SettleFallbackRequest,
): Promise<SettleFallbackResponse> {
  return blockConcurrencyWhile(async () => {
    const sqlStorage = storage as SqlStorage;
    if (!sqlStorage.sql || !hasCoverageHotRow(storage)) {
      await applyFallbackWeightToLegacy(storage, request.weight);
      return { kind: "settleFallback", outcome: "settled" };
    }
    const hotRows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
    if (hotRows.length === 0) {
      await applyFallbackWeightToLegacy(storage, request.weight);
      return { kind: "settleFallback", outcome: "settled" };
    }
    const hot = parseHotRow(hotRows[0]!);
    const reservationIndex = hot.reservations.findIndex(
      (reservation) => reservation.id === request.request_id,
    );
    if (reservationIndex >= 0) {
      const reservation = hot.reservations[reservationIndex]!;
      hot.reservations.splice(reservationIndex, 1);
      hot.row.reserved = Math.max(0, hot.row.reserved - reservation.weight);
    }
    if (hot.row.active_term_id === request.term_id) {
      hot.row.used += request.weight;
      persistParsedHot(storage, hot);
    } else {
      adjustEndedTermUsedFinal(storage, request.term_id, request.weight);
      persistParsedHot(storage, hot);
    }
    await applyFallbackWeightToLegacy(storage, request.weight);
    return { kind: "settleFallback", outcome: "settled" };
  });
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
    const sqlStorage = storage as SqlStorage;
    if (
      usesLegacyEntitlementAdmission(request) ||
      !sqlStorage.sql ||
      !hasCoverageHotRow(storage)
    ) {
      return admissionOnLegacyState(storage, request, timestamp, logger);
    }
    return admitOnHotRow(storage, request, timestamp, logger);
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
    const sqlStorage = storage as SqlStorage;
    if (
      !sqlStorage.sql ||
      (await shouldUseLegacyCredit(storage, request))
    ) {
      return creditOnLegacyState(storage, request, timestamp, logger);
    }

    if (hotRowInstallationMismatch(storage, request.installationId)) {
      logger.info("Credit rejected — unknown request", {
        installation_id: request.installationId,
        request_id: request.requestId,
      });
      return { kind: "credit", ok: false, code: "unknown_request" };
    }

    const hotResult = settleReservationOnHot(storage, request, timestamp);
    if (!hotResult.ok) {
      return hotResult;
    }

    const periodCounters = await mirrorProductionCreditToLegacy(
      storage,
      request,
      timestamp,
    );
    return {
      kind: "credit",
      ok: true,
      periodCounters,
    };
  });
}

/**
 * Roll back a stage-8 admission reservation when stage-9 journal insert fails:
 * drop jti replay, idempotency key, and in-flight slot for `requestId`.
 */
function releaseOnHotRow(
  storage: DurableObjectStorage,
  request: ReleaseRequest,
  now: number,
  logger: Logger,
): ReleaseResponse {
  const hotRows = sqlSelect<HotRow>(storage, "SELECT * FROM hot LIMIT 1");
  if (hotRows.length === 0) {
    return { kind: "release", ok: false, code: "unknown_request" };
  }

  let hot = parseHotRow(hotRows[0]!);
  sweepStoredAnswers(hot, now);

  const index = hot.reservations.findIndex(
    (reservation) => reservation.id === request.requestId,
  );
  if (index < 0) {
    persistParsedHot(storage, hot);
    logger.info("Release rejected — unknown request", {
      installation_id: request.installationId,
      request_id: request.requestId,
    });
    return { kind: "release", ok: false, code: "unknown_request" };
  }

  const reservation = hot.reservations[index]!;
  hot.reservations.splice(index, 1);
  hot.row.reserved = Math.max(0, hot.row.reserved - reservation.weight);

  delete hot.replay[request.jti];
  delete hot.idempotency[request.idempotencyKey];

  persistParsedHot(storage, hot);
  logger.info("Admission reservation released", {
    installation_id: request.installationId,
    request_id: request.requestId,
  });
  return { kind: "release", ok: true };
}

export async function releaseRPC(
  storage: DurableObjectStorage,
  blockConcurrencyWhile: <T>(fn: () => Promise<T>) => Promise<T>,
  request: ReleaseRequest,
  now?: number,
  logger: Logger = noopLogger,
): Promise<ReleaseResponse> {
  const timestamp = now ?? Date.now();

  return blockConcurrencyWhile(async () => {
    const sqlStorage = storage as SqlStorage;
    if (sqlStorage.sql && hasCoverageHotRow(storage)) {
      return releaseOnHotRow(storage, request, timestamp, logger);
    }

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

export interface InspectRequest {
  kind: "inspect";
}

export interface InspectResponse {
  kind: "inspect";
  state: QuotaDoState;
}

/**
 * Read-only snapshot for operators. Applies the ephemeral sweep in memory so
 * the snapshot reflects effective state, but never persists (no storage.put).
 */
export async function inspectRPC(
  storage: DurableObjectStorage,
  now?: number,
): Promise<InspectResponse> {
  const timestamp = now ?? Date.now();
  const state = await loadState(storage);
  sweepEphemeral(state, timestamp);
  return { kind: "inspect", state };
}

type SqlExecStorage = DurableObjectStorage & {
  sql?: { exec: (query: string) => unknown };
};

const COVERAGE_DO_SCHEMA_STATEMENTS = [
  `CREATE TABLE IF NOT EXISTS hot (
    suspended INTEGER NOT NULL DEFAULT 0,
    transferred_out_to TEXT,
    awaiting_transfer INTEGER NOT NULL DEFAULT 0,
    transfer_pending INTEGER NOT NULL DEFAULT 0,
    active_term_id TEXT,
    used INTEGER NOT NULL DEFAULT 0,
    reserved INTEGER NOT NULL DEFAULT 0,
    grace_base_used INTEGER NOT NULL DEFAULT 0,
    reservations TEXT NOT NULL DEFAULT '[]',
    replay TEXT NOT NULL DEFAULT '{}',
    idempotency TEXT NOT NULL DEFAULT '{}',
    band_emitted TEXT NOT NULL DEFAULT '{}',
    binding_epoch INTEGER NOT NULL DEFAULT 0,
    clinic_seq INTEGER NOT NULL DEFAULT 0,
    next_alarm_at TEXT
  )`,
  `CREATE TABLE IF NOT EXISTS term (
    term_id TEXT PRIMARY KEY NOT NULL,
    grant_id TEXT NOT NULL,
    origin_grant_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    state TEXT NOT NULL,
    end_reason TEXT,
    plan_snapshot TEXT,
    allowance INTEGER,
    used_final INTEGER,
    duration_unit TEXT,
    duration_count INTEGER,
    grace_days INTEGER,
    grace_cap TEXT,
    calendar_start TEXT,
    starts_at TEXT,
    ends_at TEXT,
    grace_ends_at TEXT,
    ended_at TEXT
  )`,
  `CREATE TABLE IF NOT EXISTS grant (
    grant_id TEXT PRIMARY KEY NOT NULL,
    kind TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    envelope_sha256 TEXT NOT NULL,
    envelope TEXT NOT NULL,
    evidence TEXT NOT NULL,
    receipt TEXT,
    applied_at TEXT NOT NULL,
    voided_at TEXT,
    void_reason TEXT
  )`,
  `CREATE TABLE IF NOT EXISTS outbox (
    seq INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    kind TEXT NOT NULL,
    payload TEXT NOT NULL
  )`,
] as const;

/** Per-clinic coverage tables (P3.3); idempotent on every versioned fetch. */
export async function ensureCoverageDoTables(
  storage: DurableObjectStorage,
  runExclusive: <T>(fn: () => Promise<T>) => Promise<T>,
): Promise<void> {
  await runExclusive(async () => {
    const sqlStorage = storage as SqlExecStorage;
    if (!sqlStorage.sql) {
      return;
    }
    for (const statement of COVERAGE_DO_SCHEMA_STATEMENTS) {
      sqlStorage.sql.exec(statement);
    }
  });
}

export {
  applyGrantRPC,
  inspectCoverageRPC,
  openAwaitingTransferRPC,
  readCoverageRPC,
  releaseHeldRPC,
  scheduleOutboxAlarmIfPending,
  setTransferPendingRPC,
  shipCoverageOutboxAlarm,
  suspendResumeRPC,
  transferInRPC,
  transferOutRPC,
  voidForReversalRPC,
  voidGrantRPC,
  rebuildClinicDoRPC,
  runRebuildClinicDo,
  type ApplyGrantRequest,
  type RebuildClinicDoRequest,
  type RebuildClinicDoResponse,
  type ApplyGrantResponse,
  type InspectCoverageRequest,
  type InspectCoverageResponse,
  type ReadCoverageRequest,
  type ReadCoverageResponse,
  type OpenAwaitingTransferRequest,
  type OpenAwaitingTransferResponse,
  type TransferOutRequest,
  type TransferOutResponse,
  type TransferInRequest,
  type TransferInResponse,
  type SetTransferPendingRequest,
  type SetTransferPendingResponse,
  type ReleaseHeldRequest,
  type ReleaseHeldResponse,
  type SuspendResumeRequest,
  type SuspendResumeResponse,
  type CoverageShipEnv,
  type VoidForReversalRequest,
  type VoidForReversalResponse,
  type VoidGrantRequest,
  type VoidGrantResponse,
} from "./coverage";
