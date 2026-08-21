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
import { DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS } from "../errors";
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
  cache: ConfigCache;
  reader: D1Reader;
  logger?: Logger;
};

export type AdmissionBindings = {
  DB: D1Database;
  DO: DurableObjectNamespace;
};

export type AdmissionContext = {
  now?: number;
};

type AdmissionSuccess =
  | {
    ok: true;
    outcome: "admitted";
    requestId: string;
    degraded?: boolean;
    entitlement: EntitlementSnapshot;
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
  /**
   * Stage 8: `unauthenticated` | `quota_exhausted` | `rate_limited` | `internal_error`.
   * `rate_limited` is grace-cap refusal (budget remains; retry when the queue drains).
   */
  code: "unauthenticated" | "quota_exhausted" | "rate_limited" | "internal_error";
  periodReset?: string;
  retryAfter?: number;
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
  | { ok: false; reason: "client_error" };

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

  return { ok: true, body: (await response.json()) as AdmissionResponse };
}

function mapDoOutcome(
  body: AdmissionResponse,
  installationId: string,
  entitlement: EntitlementSnapshot,
): AdmissionResult {
  switch (body.outcome) {
    case "admitted":
      return {
        ok: true,
        outcome: "admitted",
        requestId: body.requestId,
        entitlement,
        ...(body.degraded ? { degraded: true } : {}),
      };
    case "replay":
      recordGuardRejection({
        error_code: "unauthenticated",
        installation_id: installationId,
      });
      return { ok: false, code: "unauthenticated" };
    case "idempotent":
      return { ok: true, outcome: "idempotent", priorState: body.priorState };
    case "quota_exhausted":
      recordGuardRejection({
        error_code: "quota_exhausted",
        installation_id: installationId,
      });
      return {
        ok: false,
        code: "quota_exhausted",
        periodReset: body.period_end,
      };
    case "concurrency_exhausted":
      // §6.1 stage 8 / Edge Cases: map onto `quota_exhausted` (closed §5.4 taxonomy).
      // Populate period_reset from the entitlement snapshot already loaded for this
      // admission (DO concurrency reply has no period_end carrier).
      recordGuardRejection({
        error_code: "quota_exhausted",
        installation_id: installationId,
      });
      return {
        ok: false,
        code: "quota_exhausted",
        periodReset: entitlement.period_bounds.period_end,
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
      error_code: "quota_exhausted",
      installation_id: installationId,
    });
    return {
      ok: false,
      code: "quota_exhausted",
      periodReset: entitlement.period_bounds.period_end,
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
  const { principal, idempotencyKey, requestReference, cache, reader } = input;

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
        error_code: "quota_exhausted",
        installation_id: principal.installationId,
      });
      return { ok: false, code: "quota_exhausted" };
    }
    throw error;
  }
  const entitlement = mapEntitlementSnapshot(entitlementRow);

  const rpcBody = {
    kind: "admission",
    jti: principal.jti,
    installationId: principal.installationId,
    idempotencyKey,
    entitlement,
    requestReference,
  };

  const transport = await callAdmissionDo(
    bindings,
    principal.installationId,
    rpcBody,
  );

  if (!transport.ok) {
    if (transport.reason === "unavailable") {
      logger.info("Quota DO unavailable — admitting under grace", {
        installation_id: principal.installationId,
      });
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

  const result = mapDoOutcome(
    transport.body,
    principal.installationId,
    entitlement,
  );
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
