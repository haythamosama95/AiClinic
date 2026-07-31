import { drainPendingGraceAdmissions } from "../admission";
import type { PeriodCounters } from "../quota-do/index";

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
  | { ok: false; code: "unknown_request" };

export type ReconcileGraceResult = {
  reconciled: number;
};

type CreditWireResponse =
  | { kind: "credit"; ok: true; periodCounters: PeriodCounters }
  | { kind: "credit"; ok: false; code: "unknown_request" };

async function invokeCreditRpc(
  installationId: string,
  requestId: string,
  requestReference: string,
  usage: { tokens: number; cost: number },
  partial: boolean,
  bindings: CreditBindings,
): Promise<CreditResult> {
  const id = bindings.DO.idFromString(installationId);
  const stub = bindings.DO.get(id);
  const response = await stub.fetch(QUOTA_DO_RPC_URL, {
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

  if (!response.ok) {
    return { ok: false, code: "unknown_request" };
  }

  const body = (await response.json()) as CreditWireResponse;
  if (body.kind !== "credit" || !body.ok) {
    return { ok: false, code: "unknown_request" };
  }

  return { ok: true, periodCounters: body.periodCounters };
}

export async function creditUsage(
  input: CreditInput,
  bindings: CreditBindings,
): Promise<CreditResult> {
  return invokeCreditRpc(
    input.installationId,
    input.requestId,
    input.requestReference,
    input.usage,
    input.partial,
    bindings,
  );
}

/**
 * Reconciles grace admissions queued by `src/admission/` when the Quota DO was
 * unavailable (FR-013). Requires admission to export `drainPendingGraceAdmissions`.
 */
export async function reconcileGraceUsage(
  bindings: CreditBindings,
): Promise<ReconcileGraceResult> {
  const pending = drainPendingGraceAdmissions();
  let reconciled = 0;

  for (const entry of pending) {
    await invokeCreditRpc(
      entry.installationId,
      entry.requestId,
      entry.requestReference,
      { tokens: 0, cost: 0 },
      false,
      bindings,
    );
    reconciled += 1;
  }

  return { reconciled };
}
