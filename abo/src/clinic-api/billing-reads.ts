import { CHANNEL_VERSIONS, subscriptionRef } from "vendor-contracts";
import { listOffers } from "./offers.js";
import { clinicErrorResponse, clinicJsonResponse } from "./version.js";

const PAYMENTS_PAGE_SIZE = 20;

export type BillingReadsEnv = {
  DB: D1Database;
  PLATFORM: {
    getCoverage(args: Record<string, unknown>): Promise<Record<string, unknown>>;
  };
};

type CoverageSnapshot = Record<string, unknown> | null;

type PaymentRow = {
  payment_id: string;
  reference: string;
  paid_at: string;
  amount_minor: number;
  currency: string;
  offer_id: string;
  offer_version: number;
  classification: string;
  term_unit: string;
  term_count: number;
};

type ReversalRow = {
  reference: string;
  amount_minor: number;
  kind: string;
  is_full: number;
};

function parseSnapshot(value: unknown): CoverageSnapshot {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

async function loadCoverageViewSnapshot(
  env: BillingReadsEnv,
  orgId: string,
): Promise<CoverageSnapshot> {
  const row = await env.DB.prepare(
    `SELECT snapshot FROM coverage_view WHERE org_id = ?`,
  )
    .bind(orgId)
    .first<{ snapshot: string }>();
  if (row === null) {
    return null;
  }
  try {
    return parseSnapshot(JSON.parse(row.snapshot));
  } catch {
    return null;
  }
}

async function resolveSnapshot(
  env: BillingReadsEnv,
  orgId: string,
): Promise<CoverageSnapshot> {
  try {
    const envelope = await env.PLATFORM.getCoverage({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      org_id: orgId,
    });
    if (envelope.result === "ok" && typeof envelope.detail === "string") {
      const detail = JSON.parse(envelope.detail) as { snapshot?: unknown };
      return parseSnapshot(detail.snapshot);
    }
  } catch {
    // Fall through to coverage_view.
  }
  return loadCoverageViewSnapshot(env, orgId);
}

async function buildNotices(
  env: BillingReadsEnv,
  orgId: string,
  snapshot: CoverageSnapshot,
): Promise<string[]> {
  const notices: string[] = [];

  const dupRow = await env.DB.prepare(
    `SELECT 1 FROM payment
     WHERE org_id = ? AND classification = 'likely_duplicate'
     LIMIT 1`,
  )
    .bind(orgId)
    .first();
  if (dupRow !== null) {
    notices.push("duplicate_payment");
  }

  const lateRow = await env.DB.prepare(
    `SELECT 1 FROM payment
     WHERE org_id = ? AND classification = 'late'
     LIMIT 1`,
  )
    .bind(orgId)
    .first();
  if (lateRow !== null) {
    notices.push("late_payment_honoured");
  }

  const withheldRow = await env.DB.prepare(
    `SELECT 1 FROM payment
     WHERE org_id = ? AND disposition = 'withheld_mismatch'
     LIMIT 1`,
  )
    .bind(orgId)
    .first();
  if (withheldRow !== null) {
    notices.push("payment_withheld");
  }

  const reversalRow = await env.DB.prepare(
    `SELECT 1 FROM reversal r
     INNER JOIN payment p ON p.payment_id = r.payment_id
     WHERE p.org_id = ?
     LIMIT 1`,
  )
    .bind(orgId)
    .first();
  if (reversalRow !== null) {
    notices.push("reversal_recorded");
  }

  if (
    snapshot !== null &&
    typeof snapshot.held_count === "number" &&
    snapshot.held_count > 0
  ) {
    notices.push("terms_held");
  }

  return notices;
}

async function planDisplayNames(
  env: BillingReadsEnv,
): Promise<Map<string, string>> {
  const offers = await listOffers(env);
  const names = new Map<string, string>();
  for (const offer of offers) {
    names.set(offer.offer_id, offer.plan_display_name);
  }
  return names;
}

async function loadReversals(
  env: BillingReadsEnv,
  paymentId: string,
): Promise<
  Array<{
    reference: string;
    amount_minor: number;
    kind: string;
    is_full: boolean;
  }>
> {
  const rows = await env.DB.prepare(
    `SELECT reference, amount_minor, kind, is_full
     FROM reversal
     WHERE payment_id = ?
     ORDER BY reference ASC`,
  )
    .bind(paymentId)
    .all<ReversalRow>();
  return (rows.results ?? []).map((row) => ({
    reference: row.reference,
    amount_minor: row.amount_minor,
    kind: row.kind,
    is_full: row.is_full === 1,
  }));
}

export async function handleGetSubscription(
  env: BillingReadsEnv,
  orgId: string,
  contractVersion: number,
): Promise<Response> {
  const subRef = await subscriptionRef(orgId);
  const snapshot = await resolveSnapshot(env, orgId);
  const notices = await buildNotices(env, orgId, snapshot);

  const body: Record<string, unknown> = {
    contract_version: contractVersion,
    subscription_ref: subRef,
    snapshot,
    notices,
  };

  return clinicJsonResponse(body, 200, contractVersion);
}

async function validateCursor(
  env: BillingReadsEnv,
  orgId: string,
  cursor: string,
): Promise<{ ok: true; paidAt: string } | { ok: false }> {
  const row = await env.DB.prepare(
    `SELECT paid_at FROM payment WHERE org_id = ? AND reference = ?`,
  )
    .bind(orgId, cursor)
    .first<{ paid_at: string }>();
  if (row === null) {
    return { ok: false };
  }
  return { ok: true, paidAt: row.paid_at };
}

async function loadPaymentPage(
  env: BillingReadsEnv,
  orgId: string,
  cursor: string | null,
): Promise<PaymentRow[]> {
  if (cursor === null) {
    const result = await env.DB.prepare(
      `SELECT p.payment_id, p.reference, p.paid_at, p.amount_minor, p.currency,
              p.offer_id, p.offer_version, p.classification,
              c.term_unit, c.term_count
       FROM payment p
       INNER JOIN checkout c ON c.checkout_id = p.checkout_id
       WHERE p.org_id = ?
       ORDER BY p.paid_at ASC, p.reference ASC
       LIMIT ?`,
    )
      .bind(orgId, PAYMENTS_PAGE_SIZE + 1)
      .all<PaymentRow>();
    return result.results ?? [];
  }

  const validated = await validateCursor(env, orgId, cursor);
  if (!validated.ok) {
    return [];
  }

  const result = await env.DB.prepare(
    `SELECT p.payment_id, p.reference, p.paid_at, p.amount_minor, p.currency,
            p.offer_id, p.offer_version, p.classification,
            c.term_unit, c.term_count
     FROM payment p
     INNER JOIN checkout c ON c.checkout_id = p.checkout_id
     WHERE p.org_id = ?
       AND (p.paid_at > ? OR (p.paid_at = ? AND p.reference > ?))
     ORDER BY p.paid_at ASC, p.reference ASC
     LIMIT ?`,
  )
    .bind(orgId, validated.paidAt, validated.paidAt, cursor, PAYMENTS_PAGE_SIZE + 1)
    .all<PaymentRow>();
  return result.results ?? [];
}

export async function handleGetPayments(
  request: Request,
  env: BillingReadsEnv,
  orgId: string,
  contractVersion: number,
): Promise<Response> {
  const url = new URL(request.url);
  const rawCursor = url.searchParams.get("cursor");
  const cursor =
    rawCursor === null || rawCursor === "" ? null : rawCursor;

  if (cursor !== null) {
    const validated = await validateCursor(env, orgId, cursor);
    if (!validated.ok) {
      return clinicErrorResponse("invalid_request", 422, contractVersion);
    }
  }

  const rows = await loadPaymentPage(env, orgId, cursor);
  const hasMore = rows.length > PAYMENTS_PAGE_SIZE;
  const pageRows = hasMore ? rows.slice(0, PAYMENTS_PAGE_SIZE) : rows;
  const displayNames = await planDisplayNames(env);

  const payments: Record<string, unknown>[] = [];
  for (const row of pageRows) {
    payments.push({
      reference: row.reference,
      paid_at: row.paid_at,
      amount_minor: row.amount_minor,
      currency: row.currency,
      plan_display_name:
        displayNames.get(row.offer_id) ?? "Clinic subscription",
      offer_version: row.offer_version,
      term_unit: row.term_unit,
      term_count: row.term_count,
      classification: row.classification,
      reversals: await loadReversals(env, row.payment_id),
    });
  }

  const lastReference =
    pageRows.length > 0 ? pageRows[pageRows.length - 1]!.reference : "";

  return clinicJsonResponse(
    {
      contract_version: contractVersion,
      payments,
      next_cursor: lastReference,
      has_more: hasMore,
    },
    200,
    contractVersion,
  );
}
