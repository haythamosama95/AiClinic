import { noopLogger, type Logger } from "../logger";
import type { CreditIdempotencyState, PeriodCounters } from "../quota-do/index";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import type { TaxonomyCode } from "../errors";
import { clockNowIso } from "../clock";
import { generateUlid } from "../trace";

const QUOTA_DO_RPC_URL = "https://quota-do.internal/rpc";

export type CreditInput = {
  installationId: string;
  requestId: string;
  requestReference: string;
  usage: { tokens: number; cost: number };
  partial: boolean;
  credits: number;
  idempotencyState?: CreditIdempotencyState;
  terminalErrorCode?: TaxonomyCode;
  entitlement?: import("../quota-do/index").EntitlementSnapshot;
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
  clock?: { DB?: D1Database; TEST_CLOCK?: string };
};

type CreditWireResponse =
  | { kind: "credit"; ok: true; periodCounters: PeriodCounters }
  | { kind: "credit"; ok: false; code: "unknown_request" };

type CreditRpcOutcome =
  | { ok: true; periodCounters: PeriodCounters }
  | { ok: false; reason: "unknown_request" | "unavailable" | "client_error" };

type SettleFallbackWireResponse = {
  kind: "settleFallback";
  outcome: "settled" | "skipped";
};

type FallbackAdmissionRow = {
  installation_id: string;
  idempotency_key: string;
  term_id: string;
  request_id: string;
  weight: number;
  admitted_at: string;
  state: string;
};

async function invokeCreditRpc(
  installationId: string,
  requestId: string,
  requestReference: string,
  usage: { tokens: number; cost: number },
  partial: boolean,
  credits: number,
  bindings: CreditBindings,
  idempotencyState?: CreditIdempotencyState,
  entitlement?: import("../quota-do/index").EntitlementSnapshot,
  terminalErrorCode?: TaxonomyCode,
): Promise<CreditRpcOutcome> {
  const id = bindings.DO.idFromName(installationId);
  const stub = bindings.DO.get(id);

  let response: Response;
  try {
    response = await stub.fetch(QUOTA_DO_RPC_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        kind: "credit",
        installationId,
        requestId,
        reservation_id: requestId,
        requestReference,
        usage,
        partial,
        credits,
        ...(idempotencyState !== undefined ? { idempotencyState } : {}),
        ...(terminalErrorCode !== undefined ? { terminalErrorCode } : {}),
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

async function invokeSettleFallback(
  row: FallbackAdmissionRow,
  bindings: CreditBindings,
): Promise<SettleFallbackWireResponse | null> {
  const id = bindings.DO.idFromName(row.installation_id);
  const stub = bindings.DO.get(id);
  let response: Response;
  try {
    response = await stub.fetch(QUOTA_DO_RPC_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        kind: "settleFallback",
        installationId: row.installation_id,
        request_id: row.request_id,
        term_id: row.term_id,
        weight: row.weight,
      }),
    });
  } catch {
    return null;
  }
  if (!response.ok) {
    return null;
  }
  return (await response.json()) as SettleFallbackWireResponse;
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
    input.credits,
    bindings,
    input.idempotencyState,
    input.entitlement,
    input.terminalErrorCode,
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

/** Drains pending mirror fallback admissions on the five-minute cron (P3.9). */
export async function reconcileGraceUsage(
  bindings: CreditBindings,
  ctx?: ReconcileGraceContext,
  logger: Logger = noopLogger,
): Promise<ReconcileGraceResult> {
  if (!bindings.DB) {
    logger.info("fallback_reconcile_batch_start", { pending_count: 0 });
    return { reconciled: 0 };
  }

  const clockEnv = ctx?.clock ?? {
    DB: bindings.DB,
    TEST_CLOCK: undefined,
  };
  const recordedAt = await clockNowIso(clockEnv);

  const pending = await bindings.DB
    .prepare(
      `SELECT installation_id, idempotency_key, term_id, request_id, weight, admitted_at, state
       FROM fallback_admission WHERE state = 'pending' ORDER BY admitted_at ASC`,
    )
    .all<FallbackAdmissionRow>();

  const rows = pending.results ?? [];
  logger.info("fallback_reconcile_batch_start", { pending_count: rows.length });
  let reconciled = 0;

  for (const row of rows) {
    const usageExists = await bindings.DB
      .prepare(
        `SELECT 1 AS ok FROM usage_event WHERE request_id = ? LIMIT 1`,
      )
      .bind(row.request_id)
      .first<{ ok: number }>();
    if (usageExists?.ok === 1) {
      continue;
    }

    const settled = await invokeSettleFallback(row, bindings);
    if (settled === null || settled.outcome === "skipped") {
      continue;
    }

    await bindings.DB.batch([
      bindings.DB.prepare(
        `INSERT OR IGNORE INTO usage_event (
           usage_event_id, installation_id, term_id, request_id,
           quota_weight, tokens, cost, recorded_at
         ) VALUES (?, ?, ?, ?, ?, 0, 0, ?)`,
      ).bind(
        generateUlid(),
        row.installation_id,
        row.term_id,
        row.request_id,
        row.weight,
        recordedAt,
      ),
      bindings.DB.prepare(
        `UPDATE fallback_admission SET state = 'settled'
         WHERE installation_id = ? AND idempotency_key = ?`,
      ).bind(row.installation_id, row.idempotency_key),
    ]);
    reconciled += 1;
  }

  logger.info("fallback_reconcile_batch_end", {
    pending_count: rows.length,
    reconciled,
  });
  return { reconciled };
}
