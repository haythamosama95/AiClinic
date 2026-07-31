/**
 * Stage-8 admission caller — one Quota DO round trip per request (B4 §6.1 stage 8).
 */

import {
  type ConfigCache,
  type ConfigEntityKind,
  type D1Reader,
  loadConfig,
} from "../config-cache";
import type { Principal } from "../identity";
import type {
  AdmissionResponse,
  EntitlementSnapshot,
} from "../quota-do/index";

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
  | { ok: true; outcome: "admitted"; requestId: string }
  | { ok: true; outcome: "grace_admitted"; requestId: string; requestReference: string }
  | { ok: true; outcome: "idempotent"; priorState: IdempotencyPriorState };

type AdmissionFailure = {
  ok: false;
  code: "unauthenticated" | "quota_exhausted" | "concurrency_exhausted" | "internal_error";
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

/** In-isolate rejection tally keyed by time bucket + dimension set (§4.3.12). */
const rejectionTally = new Map<string, number>();

/** Grace admissions consumed per installation during a DO unavailability episode. */
const graceAdmissionsUsed = new Map<string, number>();

const graceReconciliationQueue: PendingGraceAdmission[] = [];

function scopeReaderForKind(reader: D1Reader, kind: ConfigEntityKind): D1Reader {
  return {
    read: (key) => reader.read(`${kind}:${key}`),
  };
}

function parseAllowedCapabilities(entitlement: D1Row): string[] {
  const raw = entitlement.allowed_capabilities;
  if (Array.isArray(raw)) {
    return raw as string[];
  }
  if (typeof raw === "string") {
    return JSON.parse(raw) as string[];
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

function currentTimeBucket(now = new Date()): string {
  const iso = now.toISOString();
  return `${iso.slice(0, 16)}:00`;
}

function dimensionSetFor(errorCode: string, installationId: string): string {
  return JSON.stringify({
    error_code: errorCode,
    installation_id: installationId,
  });
}

function tallyMapKey(timeBucket: string, dimensionSet: string): string {
  return `${timeBucket}\0${dimensionSet}`;
}

function recordRejection(errorCode: string, installationId: string): void {
  const timeBucket = currentTimeBucket();
  const dimensionSet = dimensionSetFor(errorCode, installationId);
  const key = tallyMapKey(timeBucket, dimensionSet);
  rejectionTally.set(key, (rejectionTally.get(key) ?? 0) + 1);
}

async function counterIdFor(
  dimensionSet: string,
  timeBucket: string,
): Promise<string> {
  const data = new TextEncoder().encode(`${timeBucket}:${dimensionSet}`);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
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
      return { ok: true, outcome: "admitted", requestId: body.requestId };
    case "replay":
      recordRejection("unauthenticated", installationId);
      return { ok: false, code: "unauthenticated" };
    case "idempotent":
      return { ok: true, outcome: "idempotent", priorState: body.priorState };
    case "quota_exhausted":
      recordRejection("quota_exhausted", installationId);
      return { ok: false, code: "quota_exhausted" };
    case "concurrency_exhausted":
      recordRejection("concurrency_exhausted", installationId);
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
    scopeReaderForKind(reader, "entitlements"),
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

export async function flushRejectionCounters(
  bindings: Pick<AdmissionBindings, "DB">,
): Promise<void> {
  if (rejectionTally.size === 0) {
    return;
  }

  for (const [mapKey, count] of rejectionTally) {
    const separator = mapKey.indexOf("\0");
    const timeBucket = mapKey.slice(0, separator);
    const dimensionSet = mapKey.slice(separator + 1);
    const counterId = await counterIdFor(dimensionSet, timeBucket);

    await bindings.DB.prepare(
      `INSERT INTO platform_counter (counter_id, dimension_set, time_bucket, count)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(counter_id) DO UPDATE SET count = count + excluded.count`,
    )
      .bind(counterId, dimensionSet, timeBucket, count)
      .run();
  }

  rejectionTally.clear();
}
