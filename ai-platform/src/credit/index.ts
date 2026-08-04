import {
  drainPendingGraceAdmissions,
  requeueGraceAdmission,
  type PendingGraceAdmission,
} from "../admission";
import type {
  AdmissionResponse,
  PeriodCounters,
} from "../quota-do/index";

const QUOTA_DO_RPC_URL = "https://quota-do.internal/rpc";

export type CreditInput = {
  installationId: string;
  requestId: string;
  requestReference: string;
  usage: { tokens: number; cost: number };
  partial: boolean;
};

export type CreditBindings = {
  DO: DurableObjectNamespace;
};

export type CreditResult =
  | { ok: true; periodCounters: PeriodCounters }
  | { ok: false; code: "unknown_request" | "unavailable" | "internal_error" };

export type ReconcileGraceResult = {
  reconciled: number;
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

function doIssuedRequestId(body: AdmissionResponse): string | null {
  if (body.kind !== "admission") {
    return null;
  }
  if (body.outcome === "admitted") {
    return body.requestId;
  }
  if (body.outcome === "idempotent") {
    return body.priorState.requestId;
  }
  return null;
}

async function invokeCreditRpc(
  installationId: string,
  requestId: string,
  requestReference: string,
  usage: { tokens: number; cost: number },
  partial: boolean,
  bindings: CreditBindings,
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
  const outcome = await invokeCreditRpc(
    input.installationId,
    input.requestId,
    input.requestReference,
    input.usage,
    input.partial,
    bindings,
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
 */
export async function reconcileGraceUsage(
  bindings: CreditBindings,
): Promise<ReconcileGraceResult> {
  const pending = drainPendingGraceAdmissions();
  let reconciled = 0;

  for (const entry of pending) {
    const admission = await invokeAdmissionRpc(entry, bindings);
    if (!admission.ok) {
      requeueGraceAdmission(entry);
      continue;
    }

    const requestId = doIssuedRequestId(admission.body);
    if (requestId === null) {
      requeueGraceAdmission(entry);
      continue;
    }

    const credit = await invokeCreditRpc(
      entry.installationId,
      requestId,
      entry.requestReference,
      entry.usage ?? { tokens: 0, cost: 0 },
      entry.partial ?? false,
      bindings,
    );

    if (!credit.ok) {
      requeueGraceAdmission(entry);
      continue;
    }

    reconciled += 1;
  }

  return { reconciled };
}
