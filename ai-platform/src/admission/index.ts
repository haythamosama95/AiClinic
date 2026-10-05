/**
 * Stage-8 admission caller — one Quota DO round trip per request (B4 §6.1 stage 8).
 */

import {
  ConfigCacheMissError,
  type ConfigCache,
  type D1Reader,
  loadConfig,
} from "../config-cache";
import type { Principal } from "../identity";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";
import {
  DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS,
  type CoverageLapseReason,
  type TaxonomyCode,
} from "../errors";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import {
  coerceSoftThreshold,
  type AdmissionResponse,
  type EntitlementSnapshot,
  type IdempotencyPriorState,
} from "../quota-do/index";
import {
  flushRejectionCounters,
  recordGuardRejection,
} from "../rate-limit";
const GRACE_ADMISSION_CAP = 5;
/** Matches B3 identity default skew (seconds) for the defensive stage-8 recheck. */
const ADMISSION_CLOCK_SKEW_SECONDS = 60;

type D1Row = Record<string, unknown>;

export type AdmissionInput = {
  principal: Principal;
  idempotencyKey: string;
  requestReference: string;
  capabilityId: string;
  quotaWeight: number;
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
  /** Injectable DO clock (milliseconds). */
  nowMs?: number;
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
    entitlement: EntitlementSnapshot;
  }
  | { ok: true; outcome: "idempotent"; priorState: IdempotencyPriorState };

type AdmissionFailure = {
  ok: false;
  code: Extract<
    TaxonomyCode,
    | "unauthenticated"
    | "allowance_exhausted"
    | "coverage_lapsed"
    | "forbidden_capability"
    | "suspended"
    | "concurrency_limited"
    | "coverage_unknown"
    | "rate_limited"
    | "internal_error"
  >;
  retryAfter?: number;
  coverageReason?: CoverageLapseReason;
};

export type AdmissionResult = AdmissionSuccess | AdmissionFailure;

/**
 * Queued grace admission params for later DO re-admission + settlement.
 * `graceRequestId` is Worker-local tracking only — never a DO-issued requestId.
 */
export type PendingGraceAdmission = {
  installationId: string;
  requestReference: string;
  jti: string;
  idempotencyKey: string;
  entitlement: EntitlementSnapshot;
  /** Local Worker-side tracking id returned as `grace_admitted.requestId`. */
  graceRequestId: string;
  usage?: { tokens: number; cost: number };
  partial?: boolean;
  reconcileAttempts?: number;
  reconcileQueuedAtMs?: number;
};

export type GraceQueueStatus = "pending" | "reconciled" | "dropped";

type GraceQueueRow = {
  grace_request_id: string;
  installation_id: string;
  idempotency_key: string;
  jti: string;
  request_reference: string;
  entitlement_json: string;
  usage_tokens: number | null;
  usage_cost: number | null;
  partial: number | null;
  queued_at: string;
  reconcile_attempts: number;
  reconcile_first_seen_at_ms: number | null;
  status: string;
};

type JournaledRequestRow = {
  request_id: string;
  request_reference: string;
  state: string;
};

type AdmissionDoTransportResult =
  | { ok: true; body: AdmissionResponse }
  | { ok: false; reason: "unavailable" }
  | { ok: false; reason: "client_error" }
  | { ok: false; reason: "contract_rejected" };

const GRACE_QUEUE_SELECT = `SELECT grace_request_id, installation_id, idempotency_key, jti,
  request_reference, entitlement_json, usage_tokens, usage_cost, partial, queued_at,
  reconcile_attempts, reconcile_first_seen_at_ms, status
 FROM grace_admission_queue`;

function parseAllowedCapabilities(entitlement: D1Row): string[] {
  const raw = entitlement.allowed_capabilities;
  if (Array.isArray(raw)) {
    return raw as string[];
  }
  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw) as unknown;
      return Array.isArray(parsed) ? (parsed as string[]) : [];
    } catch {
      return [];
    }
  }
  return [];
}

function mapEntitlementSnapshot(row: D1Row): EntitlementSnapshot {
  return {
    plan: row.plan as string,
    period_bounds: {
      period_start: row.period_start as string,
      period_end: row.period_end as string,
    },
    request_quota: row.request_quota as number,
    token_cost_budget: {
      token_budget: row.token_budget as number,
      cost_budget: row.cost_budget as number,
    },
    credit_budget: row.credit_budget as number,
    allowed_capabilities: parseAllowedCapabilities(row),
    // Out-of-range values coerce to 0 (never degrade); write path must keep [0, 1].
    soft_threshold: coerceSoftThreshold(row.soft_threshold as number),
    status: row.status as string,
  };
}

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

function mapGraceQueueRow(row: GraceQueueRow): PendingGraceAdmission {
  const entry: PendingGraceAdmission = {
    installationId: row.installation_id,
    requestReference: row.request_reference,
    jti: row.jti,
    idempotencyKey: row.idempotency_key,
    entitlement: JSON.parse(row.entitlement_json) as EntitlementSnapshot,
    graceRequestId: row.grace_request_id,
    reconcileAttempts: Number(row.reconcile_attempts ?? 0),
    reconcileQueuedAtMs: row.reconcile_first_seen_at_ms ?? undefined,
  };
  if (row.usage_tokens != null) {
    entry.usage = {
      tokens: Number(row.usage_tokens),
      cost: Number(row.usage_cost ?? 0),
    };
  }
  if (row.partial != null) {
    entry.partial = Number(row.partial) === 1;
  }
  return entry;
}

function isUniqueConstraintError(error: unknown): boolean {
  return error instanceof Error && /UNIQUE constraint failed/i.test(error.message);
}

function graceAdmittedResult(entry: {
  graceRequestId: string;
  requestReference: string;
  entitlement: EntitlementSnapshot;
}): AdmissionResult {
  return {
    ok: true,
    outcome: "grace_admitted",
    requestId: entry.graceRequestId,
    requestReference: entry.requestReference,
    entitlement: entry.entitlement,
  };
}

function idempotentFromJournal(row: JournaledRequestRow): AdmissionResult {
  return {
    ok: true,
    outcome: "idempotent",
    priorState: {
      requestReference: row.request_reference,
      state: mapJournalState(row.state),
      requestId: row.request_id,
    },
  };
}

async function selectGraceByKey(
  db: D1Database,
  installationId: string,
  idempotencyKey: string,
): Promise<GraceQueueRow | null> {
  const row = await db
    .prepare(`${GRACE_QUEUE_SELECT} WHERE installation_id = ? AND idempotency_key = ?`)
    .bind(installationId, idempotencyKey)
    .first<GraceQueueRow>();
  return row ?? null;
}

async function selectAiRequestByKey(
  db: D1Database,
  installationId: string,
  idempotencyKey: string,
): Promise<JournaledRequestRow | null> {
  const row = await db
    .prepare(
      `SELECT request_id, request_reference, state
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
      `SELECT request_id, request_reference, state
       FROM ai_request
       WHERE installation_id = ? AND request_id = ?
       LIMIT 1`,
    )
    .bind(installationId, requestId)
    .first<JournaledRequestRow>();
  return row ?? null;
}

async function isLedgerQuotaExhausted(
  db: D1Database,
  installationId: string,
  entitlement: EntitlementSnapshot,
): Promise<boolean> {
  const periodStart = entitlement.period_bounds.period_start;
  const periodEnd = entitlement.period_bounds.period_end;

  const requestRow = await db
    .prepare(
      `SELECT COUNT(*) AS count
       FROM ai_request
       WHERE installation_id = ?
         AND created_at >= ?
         AND created_at < ?`,
    )
    .bind(installationId, periodStart, periodEnd)
    .first<{ count: number }>();
  if (Number(requestRow?.count ?? 0) >= entitlement.request_quota) {
    return true;
  }

  const usageRow = await db
    .prepare(
      `SELECT COALESCE(SUM(tokens), 0) AS tokens, COALESCE(SUM(cost), 0) AS cost
       FROM usage_event
       WHERE installation_id = ?
         AND recorded_at >= ?
         AND recorded_at < ?`,
    )
    .bind(installationId, periodStart, periodEnd)
    .first<{ tokens: number; cost: number }>();
  const tokensUsed = Number(usageRow?.tokens ?? 0);
  const costUsed = Number(usageRow?.cost ?? 0);
  return (
    tokensUsed >= entitlement.token_cost_budget.token_budget ||
    costUsed >= entitlement.token_cost_budget.cost_budget
  );
}

function existingGraceOutcome(row: GraceQueueRow): AdmissionResult {
  if (row.status === "pending") {
    return graceAdmittedResult({
      graceRequestId: row.grace_request_id,
      requestReference: row.request_reference,
      entitlement: JSON.parse(row.entitlement_json) as EntitlementSnapshot,
    });
  }
  return {
    ok: true,
    outcome: "idempotent",
    priorState: {
      requestReference: row.request_reference,
      state: "completed",
      requestId: row.grace_request_id,
    },
  };
}

/** Lists pending D1 grace rows for cron reconciliation (all isolates). */
export async function listPendingGraceAdmissions(
  db: D1Database,
): Promise<PendingGraceAdmission[]> {
  const result = await db
    .prepare(`${GRACE_QUEUE_SELECT} WHERE status = 'pending' ORDER BY queued_at ASC`)
    .all<GraceQueueRow>();
  return (result.results ?? []).map(mapGraceQueueRow);
}

export async function markGraceAdmissionStatus(
  db: D1Database,
  graceRequestId: string,
  status: Extract<GraceQueueStatus, "reconciled" | "dropped">,
): Promise<void> {
  await db
    .prepare(
      `UPDATE grace_admission_queue SET status = ? WHERE grace_request_id = ?`,
    )
    .bind(status, graceRequestId)
    .run();
}

/** Persists a failed reconcile attempt so the row stays pending for the next cron. */
export async function stampGraceReconcileRetry(
  db: D1Database,
  entry: PendingGraceAdmission,
  nowMs: number,
): Promise<void> {
  const attempts = (entry.reconcileAttempts ?? 0) + 1;
  const firstSeen = entry.reconcileQueuedAtMs ?? nowMs;
  await db
    .prepare(
      `UPDATE grace_admission_queue
       SET reconcile_attempts = ?, reconcile_first_seen_at_ms = ?
       WHERE grace_request_id = ?`,
    )
    .bind(attempts, firstSeen, entry.graceRequestId)
    .run();
}

/**
 * Test helper — no longer drains isolate memory. Clearing D1
 * `grace_admission_queue` is the durable reset.
 */
export function drainPendingGraceAdmissions(): PendingGraceAdmission[] {
  return [];
}

/** Non-destructive view of pending D1 grace rows (tests / diagnostics). */
export async function peekPendingGraceAdmissions(
  db: D1Database,
): Promise<readonly PendingGraceAdmission[]> {
  return listPendingGraceAdmissions(db);
}

/**
 * Persists usage onto a pending D1 grace row before reconcile.
 * Matches by `graceRequestId` or `requestReference`.
 */
export async function attachGraceUsage(
  db: D1Database,
  graceRequestIdOrReference: string,
  usage: { tokens: number; cost: number },
  partial = false,
): Promise<boolean> {
  const result = await db
    .prepare(
      `UPDATE grace_admission_queue
       SET usage_tokens = ?, usage_cost = ?, partial = ?
       WHERE status = 'pending'
         AND (grace_request_id = ? OR request_reference = ?)`,
    )
    .bind(
      usage.tokens,
      usage.cost,
      partial ? 1 : 0,
      graceRequestIdOrReference,
      graceRequestIdOrReference,
    )
    .run();
  return (result.meta.changes ?? 0) > 0;
}

/** No-op: the durable cap is `COUNT(*)` of pending D1 rows, not an isolate Map. */
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

  const payload = (await response.json()) as Record<string, unknown>;
  if (payload.result === "rejected") {
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
      const degraded = body.degraded === true || bandDegraded(body.band);
      return {
        ok: true,
        outcome: "admitted",
        requestId: body.requestId,
        termId,
        reservationId,
        snapshot,
        ...(body.band !== undefined ? { band: body.band } : {}),
        ...(degraded ? { degraded: true } : {}),
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
    default:
      return { ok: false, code: "internal_error" };
  }
}

async function admitUnderGrace(
  db: D1Database,
  principal: Principal,
  idempotencyKey: string,
  requestReference: string,
  entitlement: EntitlementSnapshot,
): Promise<AdmissionResult> {
  const installationId = principal.installationId;

  const journaled = await selectAiRequestByKey(db, installationId, idempotencyKey);
  if (journaled) {
    return idempotentFromJournal(journaled);
  }

  const existing = await selectGraceByKey(db, installationId, idempotencyKey);
  if (existing) {
    return existingGraceOutcome(existing);
  }

  if (await isLedgerQuotaExhausted(db, installationId, entitlement)) {
    recordGuardRejection({
      error_code: "allowance_exhausted",
      installation_id: installationId,
    });
    return {
      ok: false,
      code: "allowance_exhausted",
    };
  }

  const graceRequestId = crypto.randomUUID();
  const queuedAt = new Date().toISOString();

  try {
    const inserted = await db
      .prepare(
        `INSERT INTO grace_admission_queue (
           grace_request_id, installation_id, idempotency_key, jti, request_reference,
           entitlement_json, queued_at, reconcile_attempts, status
         )
         SELECT ?, ?, ?, ?, ?, ?, ?, 0, 'pending'
         WHERE (
           SELECT COUNT(*) FROM grace_admission_queue
           WHERE installation_id = ? AND status = 'pending'
         ) < ?`,
      )
      .bind(
        graceRequestId,
        installationId,
        idempotencyKey,
        principal.jti,
        requestReference,
        JSON.stringify(entitlement),
        queuedAt,
        installationId,
        GRACE_ADMISSION_CAP,
      )
      .run();

    if ((inserted.meta.changes ?? 0) === 0) {
      const raced = await selectGraceByKey(db, installationId, idempotencyKey);
      if (raced) {
        return existingGraceOutcome(raced);
      }
      recordGuardRejection({
        error_code: "rate_limited",
        installation_id: installationId,
      });
      return {
        ok: false,
        code: "rate_limited",
        retryAfter: DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS,
      };
    }
  } catch (error) {
    if (isUniqueConstraintError(error)) {
      const raced = await selectGraceByKey(db, installationId, idempotencyKey);
      if (raced) {
        return existingGraceOutcome(raced);
      }
    }
    throw error;
  }

  return graceAdmittedResult({ graceRequestId, requestReference, entitlement });
}

export async function runAdmission(
  input: AdmissionInput,
  bindings: AdmissionBindings,
  ctx?: AdmissionContext,
): Promise<AdmissionResult> {
  const logger = input.logger ?? noopLogger;
  // Principal.exp is a JWT NumericDate (seconds). Default must match.
  const now = ctx?.now ?? Math.floor(Date.now() / 1000);
  const nowMs = ctx?.nowMs ?? Date.now();
  const {
    principal,
    idempotencyKey,
    requestReference,
    capabilityId,
    quotaWeight,
    orgId,
    cache,
    reader,
  } = input;

  logger.info("Admission started", {
    installation_id: principal.installationId,
    request_reference: requestReference,
  });

  // Defensive recheck for §6.2 harness / mis-ordered pipeline: align with B3 skew.
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
  if (journaled) {
    return idempotentFromJournal(journaled);
  }

  const rpcBody = {
    contract_version: CHANNEL_VERSIONS.platformDo,
    now: nowMs,
    kind: "admission",
    jti: principal.jti,
    installationId: principal.installationId,
    idempotencyKey,
    requestReference,
    capabilityId,
    quotaWeight,
    ...(orgId !== undefined ? { orgId } : {}),
  };

  const transport = await callAdmissionDo(
    bindings,
    principal.installationId,
    rpcBody,
  );

  if (!transport.ok) {
    if (transport.reason === "contract_rejected") {
      recordGuardRejection({
        error_code: "coverage_unknown",
        installation_id: principal.installationId,
      });
      return {
        ok: false,
        code: "coverage_unknown",
        retryAfter: DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS,
      };
    }
    if (transport.reason === "unavailable") {
      logger.info("Quota DO unavailable — admitting under grace", {
        installation_id: principal.installationId,
      });
      let entitlementRow: D1Row;
      try {
        entitlementRow = await loadConfig(
          cache,
          reader,
          "entitlements",
          principal.installationId,
        );
      } catch (error) {
        if (error instanceof ConfigCacheMissError) {
          recordGuardRejection({
            error_code: "coverage_lapsed",
            installation_id: principal.installationId,
          });
          return {
            ok: false,
            code: "coverage_lapsed",
            coverageReason: "none",
          };
        }
        throw error;
      }
      const entitlement = mapEntitlementSnapshot(entitlementRow);
      const graceResult = await admitUnderGrace(
        bindings.DB,
        principal,
        idempotencyKey,
        requestReference,
        entitlement,
      );
      if (graceResult.ok && graceResult.outcome === "grace_admitted") {
        logger.info("Grace admission granted", {
          installation_id: principal.installationId,
          request_id: graceResult.requestId,
        });
      }
      return graceResult;
    }
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

/** Re-export B3 shared flush — admission no longer keeps a private tally. */
export { flushRejectionCounters };
