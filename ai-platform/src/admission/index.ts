/**
 * Stage-8 admission caller — one Quota DO round trip per request (B4 §6.1 stage 8).
 */

import {
  type ConfigCache,
  type D1Reader,
  loadConfig,
} from "../config-cache";
import type { Principal } from "../identity";
import type {
  AdmissionResponse,
  EntitlementSnapshot,
} from "../quota-do/index";
import {
  flushRejectionCounters,
  recordGuardRejection,
} from "../rate-limit";

const GRACE_ADMISSION_CAP = 5;

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
  code: "unauthenticated" | "quota_exhausted" | "concurrency_exhausted" | "internal_error";
  periodReset?: string;
};

export type AdmissionResult = AdmissionSuccess | AdmissionFailure;

export type PendingGraceAdmission = {
  installationId: string;
  requestId: string;
  requestReference: string;
  jti: string;
  idempotencyKey: string;
  entitlement: EntitlementSnapshot;
};

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
    soft_threshold: row.soft_threshold as number,
    status: row.status as string,
  };
}

function resetGraceCounterOnDoSuccess(installationId: string): void {
  graceAdmissionsUsed.delete(installationId);
}

function queueGraceAdmission(entry: PendingGraceAdmission): void {
  graceReconciliationQueue.push(entry);
}

/** Drains pending grace admissions for stage-15 reconciliation (§15 #3). */
export function drainPendingGraceAdmissions(): PendingGraceAdmission[] {
  return graceReconciliationQueue.splice(0);
}

/** Resets the in-isolate grace cap for an installation after reconciliation (Open Decision 3). */
export function resetGraceAdmissionCounter(installationId: string): void {
  graceAdmissionsUsed.delete(installationId);
}

async function callAdmissionDo(
  bindings: AdmissionBindings,
  installationId: string,
  body: Record<string, unknown>,
): Promise<AdmissionResponse | null> {
  const id = bindings.DO.idFromString(installationId);
  const stub = bindings.DO.get(id);
  const response = await stub.fetch("https://quota-do.internal/rpc", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    return null;
  }

  return (await response.json()) as AdmissionResponse;
}

function mapDoOutcome(
  body: AdmissionResponse,
  installationId: string,
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
      recordGuardRejection({
        error_code: "concurrency_exhausted",
        installation_id: installationId,
      });
      return { ok: false, code: "concurrency_exhausted" };
    default:
      return { ok: false, code: "internal_error" };
  }
}

function removeGraceQueueEntriesFor(installationId: string): void {
  for (let index = graceReconciliationQueue.length - 1; index >= 0; index -= 1) {
    if (graceReconciliationQueue[index]?.installationId === installationId) {
      graceReconciliationQueue.splice(index, 1);
    }
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
    removeGraceQueueEntriesFor(installationId);
    return { ok: false, code: "internal_error" };
  }

  graceAdmissionsUsed.set(installationId, used + 1);
  const requestId = crypto.randomUUID();

  queueGraceAdmission({
    installationId: principal.installationId,
    requestId,
    requestReference,
    jti: principal.jti,
    idempotencyKey,
    entitlement,
  });

  return { ok: true, outcome: "grace_admitted", requestId, requestReference };
}

export async function runAdmission(
  input: AdmissionInput,
  bindings: AdmissionBindings,
  ctx?: AdmissionContext,
): Promise<AdmissionResult> {
  const now = ctx?.now ?? Date.now();
  const { principal, idempotencyKey, requestReference, cache, reader } = input;

  if (principal.exp <= now) {
    return { ok: false, code: "unauthenticated" };
  }

  const entitlementRow = await loadConfig(
    cache,
    reader,
    "entitlements",
    principal.installationId,
  );
  const entitlement = mapEntitlementSnapshot(entitlementRow);

  const rpcBody = {
    kind: "admission",
    jti: principal.jti,
    installationId: principal.installationId,
    idempotencyKey,
    entitlement,
    requestReference,
  };

  try {
    const body = await callAdmissionDo(bindings, principal.installationId, rpcBody);
    if (body === null || body.kind !== "admission") {
      return admitUnderGrace(principal, idempotencyKey, requestReference, entitlement);
    }

    resetGraceCounterOnDoSuccess(principal.installationId);
    return mapDoOutcome(body, principal.installationId);
  } catch {
    return admitUnderGrace(principal, idempotencyKey, requestReference, entitlement);
  }
}

/** Re-export B3 shared flush — admission no longer keeps a private tally. */
export { flushRejectionCounters };
