import { coverageEventId } from "vendor-contracts";
import { addDuration, type DurationScale } from "../coverage/calendar";
import type { TaxonomyCode } from "../errors";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";
import {
  allowanceBand,
  buildCoverageSnapshot,
  insertOutbox,
  loadHot,
  loadTerms,
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
}

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

type ParsedHot = {
  row: HotRow;
  reservations: ReservationRow[];
  replay: Record<string, StoredAnswerEntry>;
  idempotency: Record<string, StoredAnswerEntry>;
  band_emitted: Record<string, boolean>;
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
    band_emitted: JSON.parse(row.band_emitted || "{}") as Record<string, boolean>,
  };
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
      hot.row.used += reservation.weight;
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

function emitBandCrossedIfNeeded(
  storage: DurableObjectStorage,
  hot: ParsedHot,
  terms: TermRow[],
  request: AdmissionRequest,
  usageTotal: number,
  allowance: number,
  nowIso: string,
): void {
  if (!(allowance > 0)) {
    return;
  }
  const orgId = request.orgId ?? "";
  const vendorVersion = request.vendorContractVersion ?? 1;
  const bands: Array<"75" | "90"> = [];
  if (
    usageTotal * 4 >= allowance * 3 &&
    !hot.band_emitted["75"]
  ) {
    bands.push("75");
  }
  if (
    usageTotal * 10 >= allowance * 9 &&
    !hot.band_emitted["90"]
  ) {
    bands.push("90");
  }
  for (const band of bands) {
    hot.band_emitted[band] = true;
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

  const persistIfChanged = (): void => {
    if (stateChanged) {
      persistParsedHot(storage, hot);
    }
  };

  // Step 3 — boundary transitions are P3.5; no-op here.

  const capabilityId = resolveCapabilityId(request);
  const quotaWeight = resolveQuotaWeight(request);

  if (hot.row.suspended !== 0) {
    persistIfChanged();
    return { kind: "admission", outcome: "suspended" };
  }

  const billableTerm = activeOrGraceTerm(terms);
  if (billableTerm === undefined) {
    const last = lastEndedTerm(terms);
    persistIfChanged();
    if (last?.state === "exhausted" || last?.end_reason === "exhausted") {
      return { kind: "admission", outcome: "allowance_exhausted" };
    }
    return {
      kind: "admission",
      outcome: "coverage_lapsed",
      coverage_reason: coverageLapseReason(terms),
    };
  }

  const plan = planSnapshotForTerm(billableTerm);
  if (!plan.capabilities.includes(capabilityId)) {
    persistIfChanged();
    return { kind: "admission", outcome: "forbidden_capability" };
  }

  if (hot.reservations.length >= plan.concurrency_limit) {
    persistIfChanged();
    return {
      kind: "admission",
      outcome: "concurrency_limited",
      retry_after: CONCURRENCY_RETRY_AFTER_SECONDS,
    };
  }

  const allowance = billableTerm.allowance ?? 0;
  const creditsRemaining = allowance - hot.row.used - hot.row.reserved;
  if (creditsRemaining < quotaWeight) {
    persistIfChanged();
    return { kind: "admission", outcome: "allowance_exhausted" };
  }

  const reservationId = crypto.randomUUID();
  hot.reservations.push({
    id: reservationId,
    weight: quotaWeight,
    term_id: billableTerm.term_id,
    capability: capabilityId,
    admitted_at: now,
  });
  hot.row.reserved += quotaWeight;

  if (
    billableTerm.state === "active" &&
    hot.row.used + hot.row.reserved >= allowance
  ) {
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

  emitBandCrossedIfNeeded(
    storage,
    hot,
    loadTerms(storage),
    request,
    hot.row.used + hot.row.reserved,
    allowance,
    nowIso,
  );

  const admittedAnswer: AdmissionAdmitted = {
    kind: "admission",
    outcome: "admitted",
    requestId: reservationId,
    reservation_id: reservationId,
    term_id: billableTerm.term_id,
    snapshot: {
      capabilities: plan.capabilities,
      max_cost_class: plan.max_cost_class,
    },
    band: allowanceBand(
      hot.row.used + hot.row.reserved,
      allowance,
      billableTerm.state,
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
  if (consumed) {
    hot.row.used += reservation.weight;
  }
  hot.row.reserved = Math.max(0, hot.row.reserved - reservation.weight);
  hot.reservations.splice(index, 1);

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
    if (!sqlStorage.sql) {
      return {
        kind: "admission",
        outcome: "coverage_lapsed",
        coverage_reason: "none",
      };
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
    if (sqlStorage.sql) {
      if (
        hotRowInstallationMismatch(storage, request.installationId)
      ) {
        logger.info("Credit rejected — unknown request", {
          installation_id: request.installationId,
          request_id: request.requestId,
        });
        return { kind: "credit", ok: false, code: "unknown_request" };
      }
      return settleReservationOnHot(storage, request, timestamp);
    }

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
    state.periodCounters.creditsUsed += request.credits;
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
      credits: request.credits,
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
  readCoverageRPC,
  scheduleOutboxAlarmIfPending,
  shipCoverageOutboxAlarm,
  type ApplyGrantRequest,
  type ApplyGrantResponse,
  type ReadCoverageRequest,
  type ReadCoverageResponse,
  type CoverageShipEnv,
} from "./coverage";
