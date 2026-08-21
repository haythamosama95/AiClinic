import {
  attachGraceUsage,
  listPendingGraceAdmissions,
  markGraceAdmissionStatus,
  stampGraceReconcileRetry,
  type PendingGraceAdmission,
} from "../admission";
import { noopLogger, type Logger } from "../logger";
import type {
  AdmissionResponse,
  CreditIdempotencyState,
  EntitlementSnapshot,
  PeriodCounters,
} from "../quota-do/index";

const QUOTA_DO_RPC_URL = "https://quota-do.internal/rpc";

/** Max reconcile presentations before a grace entry is dropped. */
export const GRACE_RECONCILE_MAX_ATTEMPTS = 5;

/** Wall-clock TTL for a grace entry from first reconcile sighting. */
export const GRACE_RECONCILE_TTL_MS = 7_200_000;

export type CreditInput = {
  installationId: string;
  requestId: string;
  requestReference: string;
  usage: { tokens: number; cost: number };
  partial: boolean;
  idempotencyState?: CreditIdempotencyState;
  entitlement?: EntitlementSnapshot;
};

export type CreditBindings = {
  DO: DurableObjectNamespace;
  DB?: D1Database;
};

export type CreditResult =
  | { ok: true; periodCounters: PeriodCounters }
  | { ok: false; code: "unknown_request" | "unavailable" | "internal_error" };

export type ReconcileGraceResult = {
  reconciled: number;
};

export type ReconcileGraceContext = {
  now?: number;
};

export type GraceDropReason =
  | "settled_by_another_path_idempotent"
  | "settled_by_another_path_replay"
  | "settled_by_another_path_unknown_request"
  | "expired"
  | "max_attempts";

export type DroppedGraceJournalEntry = {
  reason: GraceDropReason;
  installationId: string;
  requestReference: string;
  graceRequestId: string;
  idempotencyKey: string;
  atMs: number;
};

type CreditWireResponse =
  | { kind: "credit"; ok: true; periodCounters: PeriodCounters }
  | { kind: "credit"; ok: false; code: "unknown_request" };

type CreditRpcOutcome =
  | { ok: true; periodCounters: PeriodCounters }
  | { ok: false; reason: "unknown_request" | "unavailable" | "client_error" };

type AdmissionRpcOutcome =
  | { ok: true; body: AdmissionResponse }
  | { ok: false; reason: "unavailable" | "client_error" };

/** Credit-owned reconcile bookkeeping stamped onto queue entries on requeue. */
type TrackedGraceAdmission = PendingGraceAdmission & {
  reconcileAttempts?: number;
  reconcileQueuedAtMs?: number;
};

const droppedGraceJournal: DroppedGraceJournalEntry[] = [];

/** Drains journaled grace drops (tests / diagnostics). */
export function drainDroppedGraceJournal(): DroppedGraceJournalEntry[] {
  return droppedGraceJournal.splice(0);
}

/** Non-destructive view of journaled grace drops (tests / diagnostics). */
export function peekDroppedGraceJournal(): readonly DroppedGraceJournalEntry[] {
  return droppedGraceJournal.slice();
}

function journalGraceDrop(
  entry: TrackedGraceAdmission,
  reason: GraceDropReason,
  atMs: number,
  logger: Logger,
): void {
  const record: DroppedGraceJournalEntry = {
    reason,
    installationId: entry.installationId,
    requestReference: entry.requestReference,
    graceRequestId: entry.graceRequestId,
    idempotencyKey: entry.idempotencyKey,
    atMs,
  };
  droppedGraceJournal.push(record);
  const level =
    reason === "expired" || reason === "max_attempts" ? "error" : "info";
  logger[level]("grace_reconcile_dropped", record);
}

async function invokeAdmissionRpc(
  entry: PendingGraceAdmission,
  bindings: CreditBindings,
): Promise<AdmissionRpcOutcome> {
  const id = bindings.DO.idFromName(entry.installationId);
  const stub = bindings.DO.get(id);

  let response: Response;
  try {
    response = await stub.fetch(QUOTA_DO_RPC_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        kind: "admission",
        jti: entry.jti,
        installationId: entry.installationId,
        idempotencyKey: entry.idempotencyKey,
        entitlement: entry.entitlement,
        requestReference: entry.requestReference,
      }),
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

async function invokeCreditRpc(
  installationId: string,
  requestId: string,
  requestReference: string,
  usage: { tokens: number; cost: number },
  partial: boolean,
  bindings: CreditBindings,
  idempotencyState?: CreditIdempotencyState,
  entitlement?: EntitlementSnapshot,
): Promise<CreditRpcOutcome> {
  const id = bindings.DO.idFromName(installationId);
  const stub = bindings.DO.get(id);

  let response: Response;
  try {
    response = await stub.fetch(QUOTA_DO_RPC_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        kind: "credit",
        installationId,
        requestId,
        requestReference,
        usage,
        partial,
        ...(idempotencyState !== undefined ? { idempotencyState } : {}),
        ...(entitlement !== undefined ? { entitlement } : {}),
      }),
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

  const body = (await response.json()) as CreditWireResponse;
  if (body.kind !== "credit" || !body.ok) {
    return { ok: false, reason: "unknown_request" };
  }

  return { ok: true, periodCounters: body.periodCounters };
}

export async function creditUsage(
  input: CreditInput,
  bindings: CreditBindings,
): Promise<CreditResult> {
  if (bindings.DB) {
    const attached = await attachGraceUsage(
      bindings.DB,
      input.requestId,
      input.usage,
      input.partial,
    );
    if (!attached) {
      await attachGraceUsage(
        bindings.DB,
        input.requestReference,
        input.usage,
        input.partial,
      );
    }
  }

  const outcome = await invokeCreditRpc(
    input.installationId,
    input.requestId,
    input.requestReference,
    input.usage,
    input.partial,
    bindings,
    input.idempotencyState,
    input.entitlement,
  );

  if (outcome.ok) {
    return { ok: true, periodCounters: outcome.periodCounters };
  }

  if (outcome.reason === "unavailable") {
    return { ok: false, code: "unavailable" };
  }
  if (outcome.reason === "client_error") {
    return { ok: false, code: "internal_error" };
  }
  return { ok: false, code: "unknown_request" };
}

/**
 * Reconciles grace admissions queued by `src/admission/` when the Quota DO was
 * unavailable (FR-013). Re-presents each pending admission so the DO issues a
 * real requestId, then credits that id with attached (or zero) usage.
 *
 * Only a fresh `admitted` outcome may be credited. `idempotent` / `replay`
 * outcomes and `unknown_request` credits mean another path already settled the
 * key — the entry is dropped (journaled). Entries also drop on TTL / max
 * attempts so the queue cannot wedge forever.
 */
export async function reconcileGraceUsage(
  bindings: CreditBindings,
  ctx?: ReconcileGraceContext,
  logger: Logger = noopLogger,
): Promise<ReconcileGraceResult> {
  const nowMs = ctx?.now ?? Date.now();
  if (!bindings.DB) {
    logger.info("grace_reconcile_batch_start", { pending_count: 0 });
    return { reconciled: 0 };
  }
  const pending = await listPendingGraceAdmissions(bindings.DB);
  logger.info("grace_reconcile_batch_start", { pending_count: pending.length });
  let reconciled = 0;

  for (const raw of pending) {
    const prior = raw as TrackedGraceAdmission;
    const entry: TrackedGraceAdmission = {
      ...prior,
      reconcileQueuedAtMs: prior.reconcileQueuedAtMs ?? nowMs,
      reconcileAttempts: prior.reconcileAttempts ?? 0,
    };

    if (nowMs - entry.reconcileQueuedAtMs! > GRACE_RECONCILE_TTL_MS) {
      journalGraceDrop(entry, "expired", nowMs, logger);
      await markGraceAdmissionStatus(bindings.DB, entry.graceRequestId, "dropped");
      continue;
    }
    if (entry.reconcileAttempts! >= GRACE_RECONCILE_MAX_ATTEMPTS) {
      journalGraceDrop(entry, "max_attempts", nowMs, logger);
      await markGraceAdmissionStatus(bindings.DB, entry.graceRequestId, "dropped");
      continue;
    }

    const admission = await invokeAdmissionRpc(entry, bindings);
    if (!admission.ok) {
      await stampGraceReconcileRetry(bindings.DB, entry, nowMs);
      continue;
    }

    const body = admission.body;
    if (body.kind !== "admission") {
      await stampGraceReconcileRetry(bindings.DB, entry, nowMs);
      continue;
    }

    if (body.outcome === "idempotent") {
      journalGraceDrop(entry, "settled_by_another_path_idempotent", nowMs, logger);
      await markGraceAdmissionStatus(bindings.DB, entry.graceRequestId, "dropped");
      continue;
    }
    if (body.outcome === "replay") {
      journalGraceDrop(entry, "settled_by_another_path_replay", nowMs, logger);
      await markGraceAdmissionStatus(bindings.DB, entry.graceRequestId, "dropped");
      continue;
    }
    if (body.outcome !== "admitted") {
      await stampGraceReconcileRetry(bindings.DB, entry, nowMs);
      continue;
    }

    // Credit only a requestId issued by this entry's fresh `admitted` outcome.
    const requestId = body.requestId;
    const credit = await invokeCreditRpc(
      entry.installationId,
      requestId,
      entry.requestReference,
      entry.usage ?? { tokens: 0, cost: 0 },
      entry.partial ?? false,
      bindings,
      undefined,
      entry.entitlement,
    );

    if (!credit.ok) {
      if (credit.reason === "unknown_request") {
        journalGraceDrop(entry, "settled_by_another_path_unknown_request", nowMs, logger);
        await markGraceAdmissionStatus(bindings.DB, entry.graceRequestId, "dropped");
        continue;
      }
      await stampGraceReconcileRetry(bindings.DB, entry, nowMs);
      continue;
    }

    await markGraceAdmissionStatus(bindings.DB, entry.graceRequestId, "reconciled");
    reconciled += 1;
  }

  logger.info("grace_reconcile_batch_end", {
    pending_count: pending.length,
    reconciled,
  });
  return { reconciled };
}
