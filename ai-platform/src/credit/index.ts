import { noopLogger, type Logger } from "../logger";
import type { CreditIdempotencyState, PeriodCounters } from "../quota-do/index";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { isTaxonomyCode, type TaxonomyCode } from "../errors";
import { clockNowIso } from "../clock";
import { generateUlid } from "../trace";
import { decodeDoResponse } from "../quota-do/response-decoder";

const QUOTA_DO_RPC_URL = "https://quota-do.internal/rpc";

export type CreditInput = {
  installationId: string;
  requestId: string;
  requestReference: string;
  termId?: string;
  usage: { tokens: number; cost: number };
  partial: boolean;
  credits: number;
  idempotencyState?: CreditIdempotencyState;
  terminalErrorCode?: TaxonomyCode;
  outcome?: "consumed" | "released";
  entitlement?: import("../quota-do/index").EntitlementSnapshot;
};

export type CreditBindings = {
  DO: DurableObjectNamespace;
  DB?: D1Database;
  DURATION_SCALE?: string;
};

export type CreditResult =
  | {
      ok: true;
      periodCounters: PeriodCounters;
      settlement: { disposition: "settled" | "already_accounted"; chargedWeight: number };
    }
  | { ok: false; code: "unknown_request" | "unavailable" | "internal_error" };

export type ReconcileGraceResult = {
  reconciled: number;
};

export type ReconcileGraceContext = {
  now?: number;
  clock?: { DB?: D1Database; TEST_CLOCK?: string };
};

type CreditWireResponse =
  | {
      kind: "credit";
      ok: true;
      periodCounters: PeriodCounters;
      settlement: { disposition: "settled" | "already_accounted"; chargedWeight: number };
    }
  | { kind: "credit"; ok: false; code: "unknown_request" };

type CreditRpcOutcome =
  | {
      ok: true;
      periodCounters: PeriodCounters;
      settlement: { disposition: "settled" | "already_accounted"; chargedWeight: number };
    }
  | { ok: false; reason: "unknown_request" | "unavailable" | "client_error" };

type SettleFallbackWireResponse = {
  kind: "settleFallback";
  outcome: "settled" | "already_accounted" | "deferred" | "conflict";
  chargedWeight?: number;
  settlementOutcome?: "consumed" | "released";
};

type FallbackAdmissionRow = {
  installation_id: string;
  idempotency_key: string;
  term_id: string;
  request_id: string;
  weight: number;
  admitted_at: string;
  state: "pending" | "consumed" | "released" | "settled";
  accounting_state: "pending" | "settled" | null;
  accounting_receipt_acknowledged: number | null;
  request_state: string | null;
};

type PendingAccountingRow = {
  request_id: string;
  request_reference: string;
  installation_id: string;
  state: string;
  terminal_error_code: string | null;
  accounting_term_id: string;
  accounting_request_id: string;
  accounting_quota_weight: number;
  accounting_outcome: "consumed" | "released";
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
  outcome?: "consumed" | "released",
  termId?: string,
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
        ...(termId !== undefined ? { term_id: termId } : {}),
        requestReference,
        usage,
        partial,
        credits,
        ...(idempotencyState !== undefined ? { idempotencyState } : {}),
        ...(terminalErrorCode !== undefined ? { terminalErrorCode } : {}),
        ...(outcome !== undefined ? { outcome } : {}),
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

  let body: CreditWireResponse | undefined;
  try {
    body = decodeDoResponse<CreditWireResponse>(
      await response.json(),
      CHANNEL_VERSIONS.platformDo,
    );
  } catch {
    return { ok: false, reason: "unavailable" };
  }
  if (body === undefined) {
    return { ok: false, reason: "unavailable" };
  }
  if (body.kind !== "credit" || !body.ok) {
    return { ok: false, reason: "unknown_request" };
  }
  if (
    body.settlement === undefined ||
    !Number.isInteger(body.settlement.chargedWeight) ||
    body.settlement.chargedWeight < 0
  ) {
    return { ok: false, reason: "unavailable" };
  }

  return {
    ok: true,
    periodCounters: body.periodCounters,
    settlement: body.settlement,
  };
}

async function invokeSettleFallback(
  row: FallbackAdmissionRow,
  bindings: CreditBindings,
): Promise<SettleFallbackWireResponse | null> {
  const id = bindings.DO.idFromName(row.installation_id);
  const stub = bindings.DO.get(id);
  const mirror = await bindings.DB?.prepare(
    `SELECT org_id FROM coverage_mirror WHERE installation_id = ? LIMIT 1`,
  )
    .bind(row.installation_id)
    .first<{ org_id: string }>();
  const nowIso = await clockNowIso({
    DB: bindings.DB,
    TEST_CLOCK: undefined,
  });
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
        outcome: row.state === "released" ? "released" : "consumed",
        nowIso,
        ...(mirror?.org_id ? { orgId: mirror.org_id } : {}),
        ...(bindings.DURATION_SCALE === "staging" ? { durationScale: "staging" } : {}),
      }),
    });
  } catch {
    return null;
  }
  if (!response.ok) {
    return null;
  }
  try {
    return decodeDoResponse<SettleFallbackWireResponse>(
      await response.json(),
      CHANNEL_VERSIONS.platformDo,
    ) ?? null;
  } catch {
    return null;
  }
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
    input.outcome,
    input.termId,
  );

  if (outcome.ok) {
    return {
      ok: true,
      periodCounters: outcome.periodCounters,
      settlement: outcome.settlement,
    };
  }

  if (outcome.reason === "unavailable") {
    return { ok: false, code: "unavailable" };
  }
  if (outcome.reason === "client_error") {
    return { ok: false, code: "internal_error" };
  }
  return { ok: false, code: "unknown_request" };
}

export type FallbackSettlementResult =
  | {
      ok: true;
      outcome: "settled" | "already_accounted";
      chargedWeight: number;
      settlementOutcome: "consumed" | "released";
    }
  | { ok: true; outcome: "deferred" | "conflict" }
  | { ok: false };

export async function settleFallbackUsage(
  input: {
    installationId: string;
    requestId: string;
    termId: string;
    weight: number;
    outcome: "consumed" | "released";
  },
  bindings: CreditBindings,
): Promise<FallbackSettlementResult> {
  const row: FallbackAdmissionRow = {
    installation_id: input.installationId,
    idempotency_key: "",
    term_id: input.termId,
    request_id: input.requestId,
    weight: input.weight,
    admitted_at: "",
    state: input.outcome,
    accounting_state: "pending",
    accounting_receipt_acknowledged: 0,
    request_state: "Completed",
  };
  const result = await invokeSettleFallback(row, bindings);
  if (result === null) return { ok: false };
  if (result.outcome === "deferred" || result.outcome === "conflict") {
    return { ok: true, outcome: result.outcome };
  }
  if (
    !Number.isInteger(result.chargedWeight) ||
    result.settlementOutcome !== input.outcome
  ) {
    return { ok: false };
  }
  return {
    ok: true,
    outcome: result.outcome,
    chargedWeight: result.chargedWeight!,
    settlementOutcome: result.settlementOutcome,
  };
}

export async function acknowledgeUsageReceipt(
  input: {
    installationId: string;
    requestId: string;
    termId: string;
    weight: number;
  },
  bindings: CreditBindings,
): Promise<boolean> {
  const stub = bindings.DO.get(bindings.DO.idFromName(input.installationId));
  let response: Response;
  try {
    response = await stub.fetch(QUOTA_DO_RPC_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        kind: "ackUsageReceipt",
        installationId: input.installationId,
        request_id: input.requestId,
        term_id: input.termId,
        weight: input.weight,
      }),
    });
  } catch {
    return false;
  }
  if (!response.ok) return false;
  try {
    const body = decodeDoResponse<{
      kind: "ackUsageReceipt";
      outcome: "acknowledged" | "already_acknowledged" | "conflict";
    }>(await response.json(), CHANNEL_VERSIONS.platformDo);
    return body?.kind === "ackUsageReceipt" &&
      (body.outcome === "acknowledged" || body.outcome === "already_acknowledged");
  } catch {
    return false;
  }
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
      `SELECT f.installation_id, f.idempotency_key, f.term_id, f.request_id,
              f.weight, f.admitted_at, f.state,
              r.accounting_state, r.accounting_receipt_acknowledged,
              r.state AS request_state
       FROM fallback_admission f
       LEFT JOIN ai_request r ON r.request_id = f.request_id
       WHERE f.state IN ('pending', 'consumed', 'released', 'settled')
       ORDER BY f.admitted_at ASC`,
    )
    .all<FallbackAdmissionRow>();

  const rows = pending.results ?? [];
  logger.info("fallback_reconcile_batch_start", { pending_count: rows.length });
  let reconciled = 0;

  const normalIntents = await bindings.DB
    .prepare(
      `SELECT request_id, request_reference, installation_id, state,
              terminal_error_code, accounting_term_id, accounting_request_id,
              accounting_quota_weight, accounting_outcome
       FROM ai_request
       WHERE accounting_state = 'pending' AND accounting_mode = 'normal'
       ORDER BY created_at ASC`,
    )
    .all<PendingAccountingRow>();
  for (const intent of normalIntents.results ?? []) {
    if (intent.state !== "Completed" && intent.state !== "Failed" && intent.state !== "Cancelled") {
      continue;
    }
    const existingUsage = await bindings.DB
      .prepare("SELECT 1 AS ok FROM usage_event WHERE request_id = ? LIMIT 1")
      .bind(intent.request_id)
      .first<{ ok: number }>();
    let chargedWeight: number;
    if (existingUsage?.ok === 1) {
      // D1's durable usage fact is authoritative after a lost DO reply.
      chargedWeight = intent.accounting_outcome === "consumed"
        ? intent.accounting_quota_weight
        : 0;
    } else {
      const usage = await bindings.DB
        .prepare(
          `SELECT COALESCE(SUM(tokens_in + tokens_out), 0) AS tokens,
                  COALESCE(SUM(cost), 0) AS cost
           FROM ai_attempt WHERE request_id = ?`,
        )
        .bind(intent.request_id)
        .first<{ tokens: number; cost: number }>();
      const state = intent.state === "Completed"
        ? "completed"
        : intent.state === "Cancelled" ? "cancelled" : "failed";
      const terminalErrorCode = intent.terminal_error_code !== null &&
          isTaxonomyCode(intent.terminal_error_code)
        ? intent.terminal_error_code
        : undefined;
      const result = await creditUsage(
        {
          installationId: intent.installation_id,
          requestId: intent.accounting_request_id,
          requestReference: intent.request_reference,
          termId: intent.accounting_term_id,
          usage: { tokens: usage?.tokens ?? 0, cost: usage?.cost ?? 0 },
          partial: intent.accounting_outcome === "released",
          credits: intent.accounting_quota_weight,
          outcome: intent.accounting_outcome,
          idempotencyState: state,
          ...(terminalErrorCode !== undefined ? { terminalErrorCode } : {}),
        },
        bindings,
      );
      if (!result.ok) continue;
      chargedWeight = result.settlement.chargedWeight;
    }
    const usage = await bindings.DB
      .prepare(
        `SELECT COALESCE(SUM(tokens_in + tokens_out), 0) AS tokens,
                COALESCE(SUM(cost), 0) AS cost
         FROM ai_attempt WHERE request_id = ?`,
      )
      .bind(intent.request_id)
      .first<{ tokens: number; cost: number }>();
    await bindings.DB.batch([
      bindings.DB.prepare(
        `INSERT OR IGNORE INTO usage_event (
           usage_event_id, installation_id, term_id, request_id,
           quota_weight, tokens, cost, recorded_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        generateUlid(), intent.installation_id, intent.accounting_term_id,
        intent.request_id, chargedWeight, usage?.tokens ?? 0,
        usage?.cost ?? 0, recordedAt,
      ),
      bindings.DB.prepare(
        `UPDATE ai_request SET accounting_state = 'settled'
         WHERE request_id = ? AND accounting_state = 'pending'`,
      ).bind(intent.request_id),
    ]);
    reconciled += 1;
    const acknowledged = await acknowledgeUsageReceipt(
      {
        installationId: intent.installation_id,
        requestId: intent.accounting_request_id,
        termId: intent.accounting_term_id,
        weight: intent.accounting_quota_weight,
      },
      bindings,
    );
    if (acknowledged) {
      await bindings.DB.prepare(
        `UPDATE ai_request SET accounting_receipt_acknowledged = 1
         WHERE request_id = ? AND accounting_state = 'settled'`,
      ).bind(intent.request_id).run();
    }
  }

  const settledIntents = await bindings.DB
    .prepare(
      `SELECT request_id, installation_id, accounting_term_id,
              accounting_request_id, accounting_quota_weight
       FROM ai_request
       WHERE accounting_state = 'settled' AND accounting_receipt_acknowledged = 0
         AND accounting_mode = 'normal'`,
    )
    .all<Pick<PendingAccountingRow, "request_id" | "installation_id" | "accounting_term_id" | "accounting_request_id" | "accounting_quota_weight">>();
  for (const intent of settledIntents.results ?? []) {
    const acknowledged = await acknowledgeUsageReceipt(
      {
        installationId: intent.installation_id,
        requestId: intent.accounting_request_id,
        termId: intent.accounting_term_id,
        weight: intent.accounting_quota_weight,
      },
      bindings,
    );
    if (acknowledged) {
      await bindings.DB.prepare(
        `UPDATE ai_request SET accounting_receipt_acknowledged = 1
         WHERE request_id = ? AND accounting_state = 'settled'`,
      ).bind(intent.request_id).run();
    }
  }

  for (const row of rows) {
    if (row.state === "settled") {
      if (row.accounting_receipt_acknowledged !== 1) {
        const acknowledged = await acknowledgeUsageReceipt(
          {
            installationId: row.installation_id,
            requestId: row.request_id,
            termId: row.term_id,
            weight: row.weight,
          },
          bindings,
        );
        if (acknowledged) {
          await bindings.DB.prepare(
            `UPDATE ai_request SET accounting_receipt_acknowledged = 1
             WHERE request_id = ? AND accounting_state = 'settled'`,
          )
            .bind(row.request_id)
            .run();
        }
      }
      continue;
    }
    const usageExists = await bindings.DB
      .prepare(
        `SELECT 1 AS ok FROM usage_event WHERE request_id = ? LIMIT 1`,
      )
      .bind(row.request_id)
      .first<{ ok: number }>();
    if (usageExists?.ok === 1) {
      // A6: old pending rows may already have a durable fact (for example a
      // stale normal reservation shipped by the DO outbox). Close the mirror
      // row without asking the DO to charge it again.
      if (row.state === "pending") {
        await bindings.DB.batch([
          bindings.DB.prepare(
            `UPDATE fallback_admission SET state = 'settled'
             WHERE installation_id = ? AND idempotency_key = ? AND state = 'pending'`,
          ).bind(row.installation_id, row.idempotency_key),
          bindings.DB.prepare(
            `UPDATE ai_request SET accounting_state = 'settled'
             WHERE request_id = ? AND accounting_state = 'pending'`,
          ).bind(row.request_id),
        ]);
        reconciled += 1;
        const acknowledged = await acknowledgeUsageReceipt(
          {
            installationId: row.installation_id,
            requestId: row.request_id,
            termId: row.term_id,
            weight: row.weight,
          },
          bindings,
        );
        if (acknowledged) {
          await bindings.DB.prepare(
            `UPDATE ai_request SET accounting_receipt_acknowledged = 1
             WHERE request_id = ? AND accounting_state = 'settled'`,
          )
            .bind(row.request_id)
            .run();
        }
        continue;
      }
    }

    // Do not guess the provider outcome while the request is still running.
    // The terminal path persists consumed/released before the next cron.
    if (
      row.request_state !== "Completed" &&
      row.request_state !== "Failed" &&
      row.request_state !== "Cancelled"
    ) {
      continue;
    }

    const settled = await invokeSettleFallback(row, bindings);
    if (
      settled === null ||
      settled.outcome === "deferred" ||
      settled.outcome === "conflict" ||
      !Number.isInteger(settled.chargedWeight) ||
      settled.settlementOutcome !== (row.state === "released" ? "released" : "consumed")
    ) {
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
        settled.chargedWeight,
        recordedAt,
      ),
      bindings.DB.prepare(
        `UPDATE fallback_admission SET state = 'settled'
         WHERE installation_id = ? AND idempotency_key = ?`,
      ).bind(row.installation_id, row.idempotency_key),
      bindings.DB.prepare(
        `UPDATE ai_request SET accounting_state = 'settled'
         WHERE request_id = ? AND (accounting_state = 'pending' OR accounting_state IS NULL)`,
      ).bind(row.request_id),
    ]);
    reconciled += 1;
    const acknowledged = await acknowledgeUsageReceipt(
      {
        installationId: row.installation_id,
        requestId: row.request_id,
        termId: row.term_id,
        weight: row.weight,
      },
      bindings,
    );
    if (acknowledged) {
      await bindings.DB.prepare(
        `UPDATE ai_request SET accounting_receipt_acknowledged = 1
         WHERE request_id = ? AND accounting_state = 'settled'`,
      )
        .bind(row.request_id)
        .run();
    }
  }

  logger.info("fallback_reconcile_batch_end", {
    pending_count: rows.length,
    reconciled,
  });
  return { reconciled };
}
