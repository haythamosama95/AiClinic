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
import {
  coerceSoftThreshold,
  type AdmissionResponse,
  type EntitlementSnapshot,
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
};

export type AdmissionBindings = {
  DB: D1Database;
  DO: DurableObjectNamespace;
};

export type AdmissionContext = {
  now?: number;
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

type AdmissionSuccess =
  | { ok: true; outcome: "admitted"; requestId: string; degraded?: boolean }
  | { ok: true; outcome: "grace_admitted"; requestId: string; requestReference: string }
  | { ok: true; outcome: "idempotent"; priorState: IdempotencyPriorState };

type AdmissionFailure = {
  ok: false;
  /** Stage 8 owns only §5.4 codes named in §6.1: `unauthenticated` | `quota_exhausted`. */
  code: "unauthenticated" | "quota_exhausted" | "internal_error";
  periodReset?: string;
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
};

type AdmissionDoTransportResult =
  | { ok: true; body: AdmissionResponse }
  | { ok: false; reason: "unavailable" }
  | { ok: false; reason: "client_error" };

/** Grace admissions consumed per installation during a DO unavailability episode. */
const graceAdmissionsUsed = new Map<string, number>();

const graceReconciliationQueue: PendingGraceAdmission[] = [];

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

function resetGraceCounterOnDoSuccess(installationId: string): void {
  graceAdmissionsUsed.delete(installationId);
}

function queueGraceAdmission(entry: PendingGraceAdmission): void {
  graceReconciliationQueue.push(entry);
}

/** Re-queues a pending grace entry after a failed reconcile attempt. */
export function requeueGraceAdmission(entry: PendingGraceAdmission): void {
  graceReconciliationQueue.push(entry);
}

/** Drains pending grace admissions for stage-15 reconciliation (§15 #3). */
export function drainPendingGraceAdmissions(): PendingGraceAdmission[] {
  return graceReconciliationQueue.splice(0);
}

/** Non-destructive view of the grace reconciliation queue (tests / diagnostics). */
export function peekPendingGraceAdmissions(): readonly PendingGraceAdmission[] {
  return graceReconciliationQueue.slice();
}

/**
 * Attaches usage to a pending grace entry before reconcile (stage-15 path for
 * grace-admitted requests). Matches by `graceRequestId` or `requestReference`.
 */
export function attachGraceUsage(
  graceRequestIdOrReference: string,
  usage: { tokens: number; cost: number },
  partial = false,
): boolean {
  const entry = graceReconciliationQueue.find(
    (candidate) =>
      candidate.graceRequestId === graceRequestIdOrReference ||
      candidate.requestReference === graceRequestIdOrReference,
  );
  if (!entry) {
    return false;
  }
  entry.usage = usage;
  entry.partial = partial;
  return true;
}

/** Resets the in-isolate grace cap for an installation after reconciliation (Open Decision 3). */
export function resetGraceAdmissionCounter(installationId: string): void {
  graceAdmissionsUsed.delete(installationId);
}

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
  entitlementPeriodEnd: string,
): AdmissionResult {
  switch (body.outcome) {
    case "admitted":
      return {
        ok: true,
        outcome: "admitted",
        requestId: body.requestId,
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
        periodReset: entitlementPeriodEnd,
      };
    default:
      return { ok: false, code: "internal_error" };
  }
}

function admitUnderGrace(
  principal: Principal,
  idempotencyKey: string,
  requestReference: string,
  entitlement: EntitlementSnapshot,
): AdmissionResult {
  const installationId = principal.installationId;
  const used = graceAdmissionsUsed.get(installationId) ?? 0;
  if (used >= GRACE_ADMISSION_CAP) {
    recordGuardRejection({
      error_code: "quota_exhausted",
      installation_id: installationId,
    });
    return { ok: false, code: "quota_exhausted" };
  }

  graceAdmissionsUsed.set(installationId, used + 1);
  const graceRequestId = crypto.randomUUID();

  queueGraceAdmission({
    installationId: principal.installationId,
    requestReference,
    jti: principal.jti,
    idempotencyKey,
    entitlement,
    graceRequestId,
  });

  return {
    ok: true,
    outcome: "grace_admitted",
    requestId: graceRequestId,
    requestReference,
  };
}

export async function runAdmission(
  input: AdmissionInput,
  bindings: AdmissionBindings,
  ctx?: AdmissionContext,
): Promise<AdmissionResult> {
  const now = ctx?.now ?? Date.now();
  const { principal, idempotencyKey, requestReference, cache, reader } = input;

  // Defensive recheck for §6.2 harness / mis-ordered pipeline: align with B3 skew.
  if (now > principal.exp + ADMISSION_CLOCK_SKEW_SECONDS) {
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
      return admitUnderGrace(principal, idempotencyKey, requestReference, entitlement);
    }
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

  resetGraceCounterOnDoSuccess(principal.installationId);
  return mapDoOutcome(
    transport.body,
    principal.installationId,
    entitlement.period_bounds.period_end,
  );
}

/** Re-export B3 shared flush — admission no longer keeps a private tally. */
export { flushRejectionCounters };
