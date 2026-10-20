/**
 * Stage-8 admission caller — one Quota DO round trip per request (B4 §6.1 stage 8).
 */

import type { ConfigCache, D1Reader } from "../config-cache";
import type { Principal } from "../identity";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";
import {
  DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS,
  type CoverageLapseReason,
  type TaxonomyCode,
} from "../errors";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { publishedQuotaWeightMax } from "../capability";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock";
import { mirrorTermViewFromSnapshot } from "../quota-do/coverage";
import {
  type AdmissionResponse,
  type EntitlementSnapshot,
  type IdempotencyPriorState,
} from "../quota-do/index";
import { decodeDoResponse } from "../quota-do/response-decoder";
import {
  flushRejectionCounters,
  recordGuardRejection,
} from "../rate-limit";

const ADMISSION_DEADLINE_MS = 2_000;
/** Matches B3 identity default skew (seconds) for the defensive stage-8 recheck. */
const ADMISSION_CLOCK_SKEW_SECONDS = 60;

export type AdmissionInput = {
  principal: Principal;
  idempotencyKey: string;
  requestReference: string;
  capabilityId: string;
  quotaWeight: number;
  requestFingerprint?: string;
  orgId?: string;
  cache: ConfigCache;
  reader: D1Reader;
  logger?: Logger;
};

export type AdmissionBindings = {
  DB: D1Database;
  DO: DurableObjectNamespace;
};

export type AdmissionContext = {
  /** JWT exp skew check (seconds). */
  now?: number;
  /** Injectable DO clock (milliseconds) at pipeline start. */
  nowMs?: number;
  /** Harness / platform clock source for admission deadline races. */
  clock?: ClockEnv;
};

type AdmissionSuccess =
  | {
    ok: true;
    outcome: "admitted";
    requestId: string;
    termId: string;
    reservationId: string;
    snapshot: { capabilities: string[]; max_cost_class: string };
    band?: "ok" | "75" | "90" | "exhausted";
    degraded?: boolean;
  }
  | {
    ok: true;
    outcome: "grace_admitted";
    requestId: string;
    requestReference: string;
    /** Present for D1 fallback admissions; legacy mocks may omit it. */
    termId?: string;
    reservationId?: string;
    snapshot?: { capabilities: string[]; max_cost_class: string };
    accountingMode?: "fallback";
    entitlement?: EntitlementSnapshot;
  }
  | { ok: true; outcome: "idempotent"; priorState: IdempotencyPriorState };

type AdmissionFailure = {
  ok: false;
  code: Extract<
    TaxonomyCode,
    | "unauthenticated"
    | "quota_exhausted"
    | "allowance_exhausted"
    | "coverage_lapsed"
    | "forbidden_capability"
    | "suspended"
    | "concurrency_limited"
    | "coverage_unknown"
    | "rate_limited"
    | "internal_error"
    | "idempotency_conflict"
  >;
  retryAfter?: number;
  coverageReason?: CoverageLapseReason;
  periodReset?: string;
};

export type AdmissionResult = AdmissionSuccess | AdmissionFailure;

/** Legacy grace-queue shape — retained for downstream imports until suite updates. */
export type PendingGraceAdmission = {
  installationId: string;
  requestReference: string;
  jti: string;
  idempotencyKey: string;
  entitlement: EntitlementSnapshot;
  graceRequestId: string;
  usage?: { tokens: number; cost: number };
  partial?: boolean;
  reconcileAttempts?: number;
  reconcileQueuedAtMs?: number;
};

export type GraceQueueStatus = "pending" | "reconciled" | "dropped";

type JournaledRequestRow = {
  request_id: string;
  request_reference: string;
  state: string;
  terminal_error_code: string | null;
  trace_id: string;
  actor_id: string;
  branch_id: string | null;
  capability_id: string;
  request_fingerprint: string | null;
};

type AdmissionDoTransportResult =
  | { ok: true; body: AdmissionResponse }
  | { ok: false; reason: "unavailable" }
  | { ok: false; reason: "client_error" }
  | { ok: false; reason: "contract_rejected" };

type CoverageMirrorRow = {
  state: string;
  suspended: number;
  hard_stop_at: string | null;
  term_snapshot: string;
};

type FallbackAdmissionBindingRow = {
  request_id: string;
  term_id: string;
  jti: string | null;
  actor_id: string | null;
  branch_id: string | null;
  capability_id: string | null;
  request_fingerprint: string | null;
  plan_snapshot: string | null;
};

function mapJournalState(state: string): IdempotencyPriorState["state"] {
  switch (state) {
    case "Completed":
      return "completed";
    case "Failed":
      return "failed";
    case "Cancelled":
      return "cancelled";
    default:
      return "admitted";
  }
}

function idempotentFromJournal(row: JournaledRequestRow): AdmissionResult {
  return {
    ok: true,
    outcome: "idempotent",
    priorState: {
      requestReference: row.request_reference,
      state: mapJournalState(row.state),
      requestId: row.request_id,
      traceId: row.trace_id,
      ...(row.terminal_error_code !== null
        ? { terminalErrorCode: row.terminal_error_code as TaxonomyCode }
        : {}),
    },
  };
}

async function selectAiRequestByKey(
  db: D1Database,
  installationId: string,
  idempotencyKey: string,
): Promise<JournaledRequestRow | null> {
  const row = await db
    .prepare(
      `SELECT request_id, request_reference, state, terminal_error_code, trace_id,
              actor_id, branch_id, capability_id, request_fingerprint
       FROM ai_request
       WHERE installation_id = ? AND idempotency_key = ?
       ORDER BY created_at ASC
       LIMIT 1`,
    )
    .bind(installationId, idempotencyKey)
    .first<JournaledRequestRow>();
  return row ?? null;
}

async function selectAiRequestById(
  db: D1Database,
  installationId: string,
  requestId: string,
): Promise<JournaledRequestRow | null> {
  const row = await db
    .prepare(
      `SELECT request_id, request_reference, state, terminal_error_code, trace_id,
              actor_id, branch_id, capability_id, request_fingerprint
       FROM ai_request
       WHERE installation_id = ? AND request_id = ?
       LIMIT 1`,
    )
    .bind(installationId, requestId)
    .first<JournaledRequestRow>();
  return row ?? null;
}

async function currentClockMs(ctx?: AdmissionContext): Promise<number> {
  if (ctx?.clock) {
    return clockNowMs(ctx.clock);
  }
  return ctx?.nowMs ?? Date.now();
}

async function yieldForTestClock(signal: AbortSignal): Promise<void> {
  if (signal.aborted) return;
  await new Promise<void>((resolve) => {
    let timer: ReturnType<typeof setTimeout>;
    const finish = (): void => {
      clearTimeout(timer);
      signal.removeEventListener("abort", finish);
      resolve();
    };
    timer = setTimeout(finish, 0);
    signal.addEventListener("abort", finish, { once: true });
    if (signal.aborted) finish();
  });
}

async function waitUntilAdmissionDeadline(
  deadlineMonotonicMs: number,
  signal: AbortSignal,
): Promise<void> {
  while (!signal.aborted && performance.now() < deadlineMonotonicMs) {
    await yieldForTestClock(signal);
  }
}

/** Lists pending D1 grace rows for cron reconciliation (legacy — table dropped in P3.9). */
export async function listPendingGraceAdmissions(
  _db: D1Database,
): Promise<PendingGraceAdmission[]> {
  return [];
}

export async function markGraceAdmissionStatus(
  _db: D1Database,
  _graceRequestId: string,
  _status: Extract<GraceQueueStatus, "reconciled" | "dropped">,
): Promise<void> { }

export async function stampGraceReconcileRetry(
  _db: D1Database,
  _entry: PendingGraceAdmission,
  _nowMs: number,
): Promise<void> { }

export function drainPendingGraceAdmissions(): PendingGraceAdmission[] {
  return [];
}

export async function peekPendingGraceAdmissions(
  _db: D1Database,
): Promise<readonly PendingGraceAdmission[]> {
  return [];
}

export async function attachGraceUsage(
  _db: D1Database,
  _graceRequestIdOrReference: string,
  _usage: { tokens: number; cost: number },
  _partial = false,
): Promise<boolean> {
  return false;
}

export function resetGraceAdmissionCounter(_installationId: string): void { }

async function callAdmissionDo(
  bindings: AdmissionBindings,
  installationId: string,
  body: Record<string, unknown>,
): Promise<AdmissionDoTransportResult> {
  const id = bindings.DO.idFromName(installationId);
  const stub = bindings.DO.get(id);

  let response: Response;
  try {
    response = await stub.fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    return { ok: false, reason: "unavailable" };
  }

  if (response.status >= 500) {
    return { ok: false, reason: "unavailable" };
  }
  if (!response.ok) {
    return { ok: false, reason: "client_error" };
  }

  let payload: Record<string, unknown> | undefined;
  try {
    payload = decodeDoResponse<Record<string, unknown>>(
      await response.json(),
      CHANNEL_VERSIONS.platformDo,
    );
  } catch {
    return { ok: false, reason: "contract_rejected" };
  }
  if (payload === undefined || payload.result === "rejected") {
    return { ok: false, reason: "contract_rejected" };
  }

  return { ok: true, body: payload as AdmissionResponse };
}

function bandDegraded(
  band?: "ok" | "75" | "90" | "exhausted",
): boolean {
  return band === "75" || band === "90" || band === "exhausted";
}

function mapDoOutcome(
  body: AdmissionResponse,
  installationId: string,
): AdmissionResult {
  switch (body.outcome) {
    case "admitted": {
      const termId = body.term_id;
      const snapshot = body.snapshot;
      if (termId === undefined || snapshot === undefined) {
        return { ok: false, code: "internal_error" };
      }
      const reservationId = body.reservation_id ?? body.requestId;
      const degraded = body.degraded ?? bandDegraded(body.band);
      return {
        ok: true,
        outcome: "admitted",
        requestId: body.requestId,
        termId,
        reservationId,
        snapshot,
        ...(body.band !== undefined ? { band: body.band } : {}),
        ...(body.degraded !== undefined
          ? { degraded }
          : degraded
            ? { degraded: true }
            : {}),
      };
    }
    case "replay":
      recordGuardRejection({
        error_code: "unauthenticated",
        installation_id: installationId,
      });
      return { ok: false, code: "unauthenticated" };
    case "idempotent":
      return { ok: true, outcome: "idempotent", priorState: body.priorState };
    case "idempotency_conflict":
      recordGuardRejection({
        error_code: "idempotency_conflict",
        installation_id: installationId,
      });
      return { ok: false, code: "idempotency_conflict" };
    case "quota_exhausted":
      recordGuardRejection({
        error_code: "allowance_exhausted",
        installation_id: installationId,
      });
      return {
        ok: false,
        code: "allowance_exhausted",
      };
    case "suspended":
      recordGuardRejection({
        error_code: "suspended",
        installation_id: installationId,
      });
      return { ok: false, code: "suspended" };
    case "allowance_exhausted":
      recordGuardRejection({
        error_code: "allowance_exhausted",
        installation_id: installationId,
      });
      return { ok: false, code: "allowance_exhausted" };
    case "coverage_lapsed":
      recordGuardRejection({
        error_code: "coverage_lapsed",
        installation_id: installationId,
      });
      return {
        ok: false,
        code: "coverage_lapsed",
        coverageReason: body.coverage_reason ?? "none",
      };
    case "forbidden_capability":
      recordGuardRejection({
        error_code: "forbidden_capability",
        installation_id: installationId,
      });
      return { ok: false, code: "forbidden_capability" };
    case "concurrency_limited":
      recordGuardRejection({
        error_code: "concurrency_limited",
        installation_id: installationId,
      });
      return {
        ok: false,
        code: "concurrency_limited",
        retryAfter: body.retry_after ?? DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS,
      };
    case "concurrency_exhausted":
      recordGuardRejection({
        error_code: "concurrency_limited",
        installation_id: installationId,
      });
      return {
        ok: false,
        code: "concurrency_limited",
        retryAfter: DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS,
      };
    default:
      return { ok: false, code: "internal_error" };
  }
}

function coverageUnknown(installationId: string): AdmissionResult {
  recordGuardRejection({
    error_code: "coverage_unknown",
    installation_id: installationId,
  });
  return {
    ok: false,
    code: "coverage_unknown",
    retryAfter: DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS,
  };
}

async function tryMirrorFallbackAdmission(input: {
  db: D1Database;
  principal: Principal;
  idempotencyKey: string;
  requestReference: string;
  capabilityId: string;
  requestFingerprint?: string;
  quotaWeight: number;
  requestId: string;
  allowNew?: boolean;
  clock?: ClockEnv;
}): Promise<AdmissionResult | null> {
  const existingKey = await input.db
    .prepare(
      `SELECT request_id, term_id, jti, actor_id, branch_id, capability_id,
              request_fingerprint, plan_snapshot
       FROM fallback_admission
       WHERE installation_id = ? AND idempotency_key = ?`,
    )
    .bind(input.principal.installationId, input.idempotencyKey)
    .first<FallbackAdmissionBindingRow>();
  if (existingKey) {
    const sameBinding =
      existingKey.actor_id === input.principal.actorId &&
      existingKey.branch_id === input.principal.branchId &&
      existingKey.capability_id === input.capabilityId &&
      existingKey.request_fingerprint === (input.requestFingerprint ?? null);
    if (!sameBinding || existingKey.plan_snapshot === null) {
      recordGuardRejection({
        error_code: "idempotency_conflict",
        installation_id: input.principal.installationId,
      });
      return { ok: false, code: "idempotency_conflict" };
    }
    let priorSnapshot: { capabilities: string[]; max_cost_class: string };
    try {
      priorSnapshot = JSON.parse(existingKey.plan_snapshot) as {
        capabilities: string[];
        max_cost_class: string;
      };
    } catch {
      return coverageUnknown(input.principal.installationId);
    }
    return {
      ok: true,
      outcome: "grace_admitted",
      requestId: existingKey.request_id,
      requestReference: input.requestReference,
      termId: existingKey.term_id,
      reservationId: existingKey.request_id,
      snapshot: priorSnapshot,
      accountingMode: "fallback",
    };
  }
  if (input.allowNew === false) {
    return null;
  }

  const mirror = await input.db
    .prepare(
      `SELECT state, suspended, hard_stop_at, term_snapshot
       FROM coverage_mirror WHERE installation_id = ?`,
    )
    .bind(input.principal.installationId)
    .first<CoverageMirrorRow>();
  if (!mirror) {
    return null;
  }

  const nowIso = input.clock
    ? await clockNowIso(input.clock)
    : new Date().toISOString();
  if (mirror.state !== "active" && mirror.state !== "grace") {
    return null;
  }
  if (Number(mirror.suspended) !== 0) {
    return null;
  }
  if (
    mirror.hard_stop_at === null ||
    mirror.hard_stop_at.length === 0 ||
    nowIso >= mirror.hard_stop_at
  ) {
    return null;
  }

  const termView = mirrorTermViewFromSnapshot(mirror.term_snapshot);
  if (
    termView === null ||
    !termView.capabilities.includes(input.capabilityId)
  ) {
    return null;
  }

  const snapshot = {
    capabilities: termView.capabilities,
    max_cost_class: termView.max_cost_class,
  };
  const existingJti = await input.db
    .prepare(
      `SELECT 1 AS present FROM fallback_admission
       WHERE installation_id = ? AND jti = ? LIMIT 1`,
    )
    .bind(input.principal.installationId, input.principal.jti)
    .first<{ present: number }>();
  if (existingJti) {
    recordGuardRejection({
      error_code: "unauthenticated",
      installation_id: input.principal.installationId,
    });
    return { ok: false, code: "unauthenticated" };
  }

  const w = input.quotaWeight;
  const cap = 5 * publishedQuotaWeightMax();
  const admittedAt = nowIso;
  const inserted = await input.db
    .prepare(
      `INSERT OR IGNORE INTO fallback_admission (
         installation_id, idempotency_key, term_id, request_id, weight, admitted_at,
         state, jti, actor_id, branch_id, capability_id, request_fingerprint, plan_snapshot
       ) SELECT ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?
       WHERE COALESCE((
         SELECT SUM(weight) FROM fallback_admission
         WHERE installation_id = ? AND state = 'pending'
       ), 0) + ? <= ?`,
    )
    .bind(
      input.principal.installationId,
      input.idempotencyKey,
      termView.ref,
      input.requestId,
      w,
      admittedAt,
      input.principal.jti,
      input.principal.actorId,
      input.principal.branchId,
      input.capabilityId,
      input.requestFingerprint ?? null,
      JSON.stringify(snapshot),
      input.principal.installationId,
      w,
      cap,
    )
    .run();
  if ((inserted.meta.changes ?? 0) === 0) {
    const raced = await input.db
      .prepare(
        `SELECT request_id, term_id, jti, actor_id, branch_id, capability_id,
                request_fingerprint, plan_snapshot FROM fallback_admission
         WHERE installation_id = ? AND idempotency_key = ?`,
      )
      .bind(input.principal.installationId, input.idempotencyKey)
      .first<FallbackAdmissionBindingRow>();
    if (raced) {
      if (
        raced.actor_id !== input.principal.actorId ||
        raced.branch_id !== input.principal.branchId ||
        raced.capability_id !== input.capabilityId ||
        raced.request_fingerprint !== (input.requestFingerprint ?? null) ||
        raced.plan_snapshot === null
      ) {
        recordGuardRejection({
          error_code: "idempotency_conflict",
          installation_id: input.principal.installationId,
        });
        return { ok: false, code: "idempotency_conflict" };
      }
      const priorSnapshot = JSON.parse(raced.plan_snapshot) as {
        capabilities: string[];
        max_cost_class: string;
      };
      return {
        ok: true,
        outcome: "grace_admitted",
        requestId: raced.request_id,
        requestReference: input.requestReference,
        termId: raced.term_id,
        reservationId: raced.request_id,
        snapshot: priorSnapshot,
        accountingMode: "fallback",
      };
    }
    const racedJti = await input.db
      .prepare(
        `SELECT 1 AS present FROM fallback_admission
         WHERE installation_id = ? AND jti = ? LIMIT 1`,
      )
      .bind(input.principal.installationId, input.principal.jti)
      .first<{ present: number }>();
    if (racedJti) {
      recordGuardRejection({
        error_code: "unauthenticated",
        installation_id: input.principal.installationId,
      });
      return { ok: false, code: "unauthenticated" };
    }
    return null;
  }

  return {
    ok: true,
    outcome: "grace_admitted",
    requestId: input.requestId,
    requestReference: input.requestReference,
    termId: termView.ref,
    reservationId: input.requestId,
    snapshot,
    accountingMode: "fallback",
  };
}

async function raceAdmissionDo(
  bindings: AdmissionBindings,
  installationId: string,
  rpcBody: Record<string, unknown>,
  deadlineMonotonicMs: number,
): Promise<AdmissionDoTransportResult> {
  const doPromise = callAdmissionDo(bindings, installationId, rpcBody);
  const deadlinePoller = new AbortController();

  try {
    for (;;) {
      if (performance.now() >= deadlineMonotonicMs) {
        const atDeadline = await Promise.race([
          doPromise.then((result) => ({ kind: "do" as const, result })),
          Promise.resolve({ kind: "past_deadline" as const }),
        ]);
        if (atDeadline.kind === "do") {
          return atDeadline.result;
        }
        return { ok: false, reason: "unavailable" };
      }

      const raced = await Promise.race([
        doPromise.then((result) => ({ kind: "do" as const, result })),
        waitUntilAdmissionDeadline(deadlineMonotonicMs, deadlinePoller.signal).then(() => ({
          kind: "tick" as const,
        })),
      ]);
      if (raced.kind === "do") {
        return raced.result;
      }
    }
  } finally {
    // Always stop deadline polling once either the DO request or deadline wins.
    deadlinePoller.abort();
  }
}

export async function runAdmission(
  input: AdmissionInput,
  bindings: AdmissionBindings,
  ctx?: AdmissionContext,
): Promise<AdmissionResult> {
  const logger = input.logger ?? noopLogger;
  const now = ctx?.now ?? Math.floor(Date.now() / 1000);
  const startMs = await currentClockMs(ctx);
  const deadlineMonotonicMs = performance.now() + ADMISSION_DEADLINE_MS;
  const {
    principal,
    idempotencyKey,
    requestReference,
    capabilityId,
    quotaWeight,
    requestFingerprint,
    orgId,
  } = input;

  logger.info("Admission started", {
    installation_id: principal.installationId,
    request_reference: requestReference,
  });

  if (now > principal.exp + ADMISSION_CLOCK_SKEW_SECONDS) {
    logger.info("Admission rejected — token expired", {
      installation_id: principal.installationId,
    });
    recordGuardRejection({
      error_code: "unauthenticated",
      installation_id: principal.installationId,
    });
    return { ok: false, code: "unauthenticated" };
  }

  const journaled = await selectAiRequestByKey(
    bindings.DB,
    principal.installationId,
    idempotencyKey,
  );
  const idempotencyBinding = requestFingerprint === undefined ? undefined : {
    actorId: principal.actorId,
    branchId: principal.branchId,
    capabilityId,
    requestFingerprint,
  };
  const journaledBindingMatches =
    journaled !== null &&
    idempotencyBinding !== undefined &&
    journaled.actor_id === idempotencyBinding.actorId &&
    journaled.branch_id === idempotencyBinding.branchId &&
    journaled.capability_id === idempotencyBinding.capabilityId &&
    journaled.request_fingerprint === idempotencyBinding.requestFingerprint;
  const journaledAnswer = journaledBindingMatches && journaled
    ? {
        requestReference: journaled.request_reference,
        state: mapJournalState(journaled.state),
        requestId: journaled.request_id,
        traceId: journaled.trace_id,
        ...(journaled.terminal_error_code !== null
          ? { terminalErrorCode: journaled.terminal_error_code as TaxonomyCode }
          : {}),
      }
    : undefined;

  const requestId = crypto.randomUUID();
  const rpcBody = {
    contract_version: CHANNEL_VERSIONS.platformDo,
    now: startMs,
    kind: "admission",
    jti: principal.jti,
    installationId: principal.installationId,
    idempotencyKey,
    requestReference,
    capabilityId,
    ...(idempotencyBinding !== undefined ? { idempotencyBinding } : {}),
    ...(journaledAnswer !== undefined ? { journaledAnswer } : {}),
    ...(journaled !== null && !journaledBindingMatches
      ? { journaledConflict: true }
      : {}),
    quotaWeight,
    requestId,
    ...(orgId !== undefined ? { orgId } : {}),
  };

  const transport = await raceAdmissionDo(
    bindings,
    principal.installationId,
    rpcBody,
    deadlineMonotonicMs,
  );

  if (transport.ok) {
    if (transport.body.kind !== "admission") {
      recordGuardRejection({
        error_code: "internal_error",
        installation_id: principal.installationId,
      });
      return { ok: false, code: "internal_error" };
    }
    const result = mapDoOutcome(transport.body, principal.installationId);
    if (result.ok && result.outcome === "admitted") {
      const existing = await selectAiRequestById(
        bindings.DB,
        principal.installationId,
        result.requestId,
      );
      if (existing) {
        return idempotentFromJournal(existing);
      }
    }
    if (result.ok) {
      logger.info("Admission DO outcome", {
        installation_id: principal.installationId,
        outcome: result.outcome,
        ...(result.outcome === "admitted" || result.outcome === "grace_admitted"
          ? { request_id: result.requestId }
          : {}),
      });
    } else {
      logger.info("Admission rejected", {
        installation_id: principal.installationId,
        code: result.code,
      });
    }
    return result;
  }

  if (transport.reason === "contract_rejected") {
    return coverageUnknown(principal.installationId);
  }
  if (transport.reason === "client_error") {
    logger.error("Admission DO transport failed", {
      installation_id: principal.installationId,
      reason: transport.reason,
    });
    recordGuardRejection({
      error_code: "internal_error",
      installation_id: principal.installationId,
    });
    return { ok: false, code: "internal_error" };
  }

  logger.info("Quota DO unavailable — attempting mirror fallback", {
    installation_id: principal.installationId,
  });

  const fallback = await tryMirrorFallbackAdmission({
    db: bindings.DB,
    principal,
    idempotencyKey,
    requestReference,
    capabilityId,
    requestFingerprint,
    quotaWeight,
    requestId,
    allowNew: journaled === null,
    clock: ctx?.clock,
  });
  if (fallback) {
    logger.info("Admission mirror fallback", {
      installation_id: principal.installationId,
      request_id: fallback.ok ? fallback.requestId : undefined,
      outcome: fallback.ok ? fallback.outcome : undefined,
    });
    return fallback;
  }

  return coverageUnknown(principal.installationId);
}

/** Re-export B3 shared flush — admission no longer keeps a private tally. */
export { flushRejectionCounters };
