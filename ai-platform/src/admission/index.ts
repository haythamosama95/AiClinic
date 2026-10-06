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

const ADMISSION_DEADLINE_MS = 2_000;
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
  trace_id: string;
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

function idempotentFromJournal(row: JournaledRequestRow): AdmissionResult {
  return {
    ok: true,
    outcome: "idempotent",
    priorState: {
      requestReference: row.request_reference,
      state: mapJournalState(row.state),
      requestId: row.request_id,
      traceId: row.trace_id,
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
      `SELECT request_id, request_reference, state, trace_id
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
      `SELECT request_id, request_reference, state, trace_id
       FROM ai_request
       WHERE installation_id = ? AND request_id = ?
       LIMIT 1`,
    )
    .bind(installationId, requestId)
    .first<JournaledRequestRow>();
  return row ?? null;
}

async function loadInstallationEntitlement(
  db: D1Database,
  installationId: string,
): Promise<EntitlementSnapshot | undefined> {
  const row = await db
    .prepare(`SELECT * FROM entitlement WHERE installation_id = ? LIMIT 1`)
    .bind(installationId)
    .first<D1Row>();
  return row ? mapEntitlementSnapshot(row) : undefined;
}

async function currentClockMs(ctx?: AdmissionContext): Promise<number> {
  if (ctx?.clock) {
    return clockNowMs(ctx.clock);
  }
  return ctx?.nowMs ?? Date.now();
}

async function yieldForTestClock(_ctx?: AdmissionContext): Promise<void> {
  await new Promise<void>((resolve) => {
    setTimeout(resolve, 0);
  });
}

async function waitUntilAdmissionDeadline(
  deadlineMs: number,
  ctx?: AdmissionContext,
): Promise<void> {
  while ((await currentClockMs(ctx)) < deadlineMs) {
    await yieldForTestClock(ctx);
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

async function pendingFallbackWeight(
  db: D1Database,
  installationId: string,
): Promise<number> {
  const row = await db
    .prepare(
      `SELECT COALESCE(SUM(weight), 0) AS total
       FROM fallback_admission
       WHERE installation_id = ? AND state = 'pending'`,
    )
    .bind(installationId)
    .first<{ total: number }>();
  return Number(row?.total ?? 0);
}

async function tryMirrorFallbackAdmission(input: {
  db: D1Database;
  principal: Principal;
  idempotencyKey: string;
  requestReference: string;
  capabilityId: string;
  quotaWeight: number;
  requestId: string;
  clock?: ClockEnv;
}): Promise<AdmissionResult | null> {
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

  let termRef = "";
  let capabilities: string[] = [];
  try {
    const snapshot = JSON.parse(mirror.term_snapshot) as {
      ref?: string;
      capabilities?: unknown;
    };
    termRef = typeof snapshot.ref === "string" ? snapshot.ref : "";
    capabilities = Array.isArray(snapshot.capabilities)
      ? snapshot.capabilities.filter(
          (entry): entry is string => typeof entry === "string",
        )
      : [];
  } catch {
    return null;
  }
  if (!termRef || !capabilities.includes(input.capabilityId)) {
    return null;
  }

  const w = input.quotaWeight;
  const cap = 5 * publishedQuotaWeightMax();
  const pending = await pendingFallbackWeight(
    input.db,
    input.principal.installationId,
  );
  if (pending + w > cap) {
    return null;
  }

  const admittedAt = nowIso;
  const inserted = await input.db
    .prepare(
      `INSERT OR IGNORE INTO fallback_admission (
         installation_id, idempotency_key, term_id, request_id, weight, admitted_at, state
       ) VALUES (?, ?, ?, ?, ?, ?, 'pending')`,
    )
    .bind(
      input.principal.installationId,
      input.idempotencyKey,
      termRef,
      input.requestId,
      w,
      admittedAt,
    )
    .run();
  if ((inserted.meta.changes ?? 0) === 0) {
    const raced = await input.db
      .prepare(
        `SELECT request_id FROM fallback_admission
         WHERE installation_id = ? AND idempotency_key = ?`,
      )
      .bind(input.principal.installationId, input.idempotencyKey)
      .first<{ request_id: string }>();
    if (raced) {
      const entitlement =
        (await loadInstallationEntitlement(
          input.db,
          input.principal.installationId,
        )) ?? {
          plan: "standard",
          period_bounds: { period_start: admittedAt, period_end: admittedAt },
          request_quota: 0,
          token_cost_budget: { token_budget: 0, cost_budget: 0 },
          credit_budget: 0,
          allowed_capabilities: capabilities,
          soft_threshold: 0,
          status: "active",
        };
      return {
        ok: true,
        outcome: "grace_admitted",
        requestId: raced.request_id,
        requestReference: input.requestReference,
        entitlement,
      };
    }
    return null;
  }

  const entitlement =
    (await loadInstallationEntitlement(
      input.db,
      input.principal.installationId,
    )) ?? {
      plan: "standard",
      period_bounds: { period_start: admittedAt, period_end: admittedAt },
      request_quota: 0,
      token_cost_budget: { token_budget: 0, cost_budget: 0 },
      credit_budget: 0,
      allowed_capabilities: capabilities,
      soft_threshold: 0,
      status: "active",
    };

  return {
    ok: true,
    outcome: "grace_admitted",
    requestId: input.requestId,
    requestReference: input.requestReference,
    entitlement,
  };
}

async function raceAdmissionDo(
  bindings: AdmissionBindings,
  installationId: string,
  rpcBody: Record<string, unknown>,
  deadlineMs: number,
  ctx?: AdmissionContext,
): Promise<AdmissionDoTransportResult> {
  const doPromise = callAdmissionDo(bindings, installationId, rpcBody);

  for (;;) {
    const nowMs = await currentClockMs(ctx);
    if (nowMs >= deadlineMs) {
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
      waitUntilAdmissionDeadline(deadlineMs, ctx).then(() => ({
        kind: "tick" as const,
      })),
    ]);
    if (raced.kind === "do") {
      return raced.result;
    }
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
  const {
    principal,
    idempotencyKey,
    requestReference,
    capabilityId,
    quotaWeight,
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
  if (journaled) {
    return idempotentFromJournal(journaled);
  }

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
    quotaWeight,
    requestId,
    ...(orgId !== undefined ? { orgId } : {}),
  };

  const deadlineMs = startMs + ADMISSION_DEADLINE_MS;
  const transport = await raceAdmissionDo(
    bindings,
    principal.installationId,
    rpcBody,
    deadlineMs,
    ctx,
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
    quotaWeight,
    requestId,
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
