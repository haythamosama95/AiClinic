import {
  canonicalize,
  CHANNEL_VERSIONS,
  grantIdComp,
  grantIdPaid,
  sha256Hex,
  ulid,
} from "vendor-contracts";
import { raiseAlert, type AlertEnv } from "../alert/index.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import type { PaymobAdapterEnv } from "../provider/paymob/adapter.js";
import { parseStoredPaymobNotification } from "../provider/paymob/adapter.js";

const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const SEVEN_DAYS_MS = 7 * ONE_DAY_MS;

export type ReconciliationEnv = AlertEnv &
  ClockEnv &
  Pick<PaymobAdapterEnv, "PAYMOB_HMAC_SECRET"> & {
    DB: D1Database;
    R2: R2Bucket;
    PLATFORM: {
      listGrants(args: Record<string, unknown>): Promise<Record<string, unknown>>;
      getCoverage(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
      readCoverageEvents(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
    };
  };

type PlatformGrant = Record<string, unknown>;

async function newId(env: ReconciliationEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

async function findingExists(
  env: ReconciliationEnv,
  kind: string,
  subject: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM finding WHERE kind = ? AND subject = ?`,
  )
    .bind(kind, subject)
    .first();
  return row !== null;
}

async function insertFinding(
  env: ReconciliationEnv,
  kind: string,
  subject: string,
  detail: string,
): Promise<void> {
  if (await findingExists(env, kind, subject)) {
    return;
  }
  const findingId = await newId(env);
  const detectedAt = await clockNowIso(env);
  const canonicalRow = {
    finding_id: findingId,
    kind,
    subject,
    detail,
    detected_at: detectedAt,
  };
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO finding (finding_id, kind, subject, detail, detected_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).bind(findingId, kind, subject, detail, detectedAt),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind("finding", findingId, rowSha256, detectedAt),
  ]);
  await raiseAlert(env, "AL-10", `AL-10:${findingId}`, findingId);
}

async function parsePlatformGrants(
  env: ReconciliationEnv,
): Promise<PlatformGrant[] | null> {
  const envelope = await env.PLATFORM.listGrants({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
  });
  if (envelope.result !== "ok" || typeof envelope.detail !== "string") {
    return null;
  }
  const parsed = JSON.parse(envelope.detail) as unknown;
  return Array.isArray(parsed) ? (parsed as PlatformGrant[]) : [];
}

async function paidGrantIdsFromPayments(
  env: ReconciliationEnv,
): Promise<Set<string>> {
  const rows = await env.DB.prepare(`SELECT payment_id FROM payment`).all<{
    payment_id: string;
  }>();
  const grantIds = new Set<string>();
  for (const row of rows.results ?? []) {
    grantIds.add(await grantIdPaid(row.payment_id));
  }
  return grantIds;
}

async function complimentaryActionGrantIds(
  env: ReconciliationEnv,
): Promise<Set<string>> {
  const rows = await env.DB.prepare(
    `SELECT action_id FROM operator_action`,
  ).all<{ action_id: string }>();
  const grantIds = new Set<string>();
  for (const row of rows.results ?? []) {
    grantIds.add(await grantIdComp(row.action_id));
  }
  return grantIds;
}

async function checkPaymentWithoutGrant(env: ReconciliationEnv): Promise<void> {
  const nowMs = await clockNowMs(env);
  const rows = await env.DB.prepare(
    `SELECT payment_id, confirmed_at FROM payment WHERE disposition = 'grant'`,
  ).all<{ payment_id: string; confirmed_at: string }>();

  for (const row of rows.results ?? []) {
    const grantId = await grantIdPaid(row.payment_id);
    const outcome = await env.DB.prepare(
      `SELECT result, at FROM grant_outcome WHERE grant_id = ?`,
    )
      .bind(grantId)
      .first<{ result: string; at: string }>();

    if (
      outcome !== null &&
      (outcome.result === "applied" || outcome.result === "already_applied")
    ) {
      const confirmedMs = Date.parse(row.confirmed_at);
      const outcomeMs = Date.parse(outcome.at);
      if (
        !Number.isNaN(confirmedMs) &&
        !Number.isNaN(outcomeMs) &&
        outcomeMs <= confirmedMs + FIFTEEN_MINUTES_MS
      ) {
        continue;
      }
    }

    const confirmedMs = Date.parse(row.confirmed_at);
    if (
      outcome === null &&
      !Number.isNaN(confirmedMs) &&
      nowMs < confirmedMs + FIFTEEN_MINUTES_MS
    ) {
      continue;
    }

    await insertFinding(
      env,
      "payment_without_grant",
      row.payment_id,
      grantId,
    );
  }
}

async function checkGrantWithoutPayment(env: ReconciliationEnv): Promise<void> {
  const paidGrantIds = await paidGrantIdsFromPayments(env);
  const grants = await parsePlatformGrants(env);
  if (grants === null) {
    return;
  }
  for (const grant of grants) {
    if (grant.source_kind !== "paid") {
      continue;
    }
    const grantId = String(grant.grant_id ?? "");
    if (grantId.length === 0 || paidGrantIds.has(grantId)) {
      continue;
    }
    await insertFinding(env, "grant_without_payment", grantId, "");
  }
}

async function checkGrantWithoutOperatorAction(
  env: ReconciliationEnv,
): Promise<void> {
  const authorisedGrantIds = await complimentaryActionGrantIds(env);
  const grants = await parsePlatformGrants(env);
  if (grants === null) {
    return;
  }
  for (const grant of grants) {
    if (grant.source_kind !== "complimentary") {
      continue;
    }
    const grantId = String(grant.grant_id ?? "");
    if (grantId.length === 0 || authorisedGrantIds.has(grantId)) {
      continue;
    }
    await insertFinding(env, "grant_without_operator_action", grantId, "");
  }
}

async function checkTransferWithoutAuthorisation(
  env: ReconciliationEnv,
): Promise<void> {
  const grants = await parsePlatformGrants(env);
  if (grants === null) {
    return;
  }
  for (const grant of grants) {
    if (grant.source_kind !== "transfer") {
      continue;
    }
    const grantId = String(grant.grant_id ?? "");
    const orgId = String(grant.org_id ?? "");
    if (grantId.length === 0) {
      continue;
    }

    const request = await env.DB.prepare(
      `SELECT 1 FROM grant_request
       WHERE grant_id = ? AND source_kind = 'transfer'`,
    )
      .bind(grantId)
      .first();
    if (request === null) {
      await insertFinding(
        env,
        "transfer_without_authorisation",
        grantId,
        orgId,
      );
      continue;
    }

    if (orgId.length === 0) {
      await insertFinding(
        env,
        "transfer_without_authorisation",
        grantId,
        "",
      );
      continue;
    }

    const action = await env.DB.prepare(
      `SELECT 1 FROM operator_action
       WHERE action = 'beginTransfer' AND subject = ?`,
    )
      .bind(orgId)
      .first();
    if (action === null) {
      await insertFinding(
        env,
        "transfer_without_authorisation",
        grantId,
        orgId,
      );
    }
  }
}

async function checkReversalNotApplied(env: ReconciliationEnv): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT reversal_id, effect FROM reversal WHERE is_full = 1`,
  ).all<{ reversal_id: string; effect: string }>();

  for (const row of rows.results ?? []) {
    if (row.effect === "none" || row.effect === "tombstone") {
      continue;
    }
    const outcome = await env.DB.prepare(
      `SELECT 1 FROM reversal_outcome WHERE reversal_id = ?`,
    )
      .bind(row.reversal_id)
      .first();
    if (outcome !== null) {
      continue;
    }
    await insertFinding(
      env,
      "reversal_not_applied",
      row.reversal_id,
      row.effect,
    );
  }
}

async function checkPayoutUnmatched(env: ReconciliationEnv): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT import_id, line_no, kind, gross_minor, payment_id
     FROM payout_line WHERE kind = 'payment'`,
  ).all<{
    import_id: string;
    line_no: number;
    kind: string;
    gross_minor: number;
    payment_id: string | null;
  }>();

  for (const row of rows.results ?? []) {
    if (row.payment_id !== null) {
      const payment = await env.DB.prepare(
        `SELECT amount_minor FROM payment WHERE payment_id = ?`,
      )
        .bind(row.payment_id)
        .first<{ amount_minor: number }>();
      if (payment !== null && row.gross_minor === payment.amount_minor) {
        continue;
      }
    }
    await insertFinding(
      env,
      "payout_unmatched",
      `${row.import_id}:${row.line_no}`,
      row.payment_id ?? "",
    );
  }
}

function periodEndMs(period: string): number {
  const [yearStr, monthStr] = period.split("-");
  const year = Number(yearStr);
  const month = Number(monthStr);
  return Date.UTC(year, month, 0, 23, 59, 59, 999);
}

async function checkPaymentNotInPayout(env: ReconciliationEnv): Promise<void> {
  const imports = await env.DB.prepare(
    `SELECT period FROM payout_import`,
  ).all<{ period: string }>();
  const periods = new Set((imports.results ?? []).map((row) => row.period));
  if (periods.size === 0) {
    return;
  }

  const payoutPayments = new Set<string>();
  const paymentPayoutPeriods = new Map<string, Set<string>>();
  const payoutRows = await env.DB.prepare(
    `SELECT pl.payment_id, pi.period
     FROM payout_line pl
     INNER JOIN payout_import pi ON pi.import_id = pl.import_id
     WHERE pl.kind = 'payment' AND pl.payment_id IS NOT NULL`,
  ).all<{ payment_id: string; period: string }>();
  for (const row of payoutRows.results ?? []) {
    payoutPayments.add(`${row.period}:${row.payment_id}`);
    const periods = paymentPayoutPeriods.get(row.payment_id) ?? new Set<string>();
    periods.add(row.period);
    paymentPayoutPeriods.set(row.payment_id, periods);
  }

  const payments = await env.DB.prepare(
    `SELECT payment_id, paid_at FROM payment`,
  ).all<{ payment_id: string; paid_at: string }>();

  for (const payment of payments.results ?? []) {
    const paidMs = Date.parse(payment.paid_at);
    if (Number.isNaN(paidMs)) {
      continue;
    }
    for (const period of periods) {
      const endMs = periodEndMs(period);
      if (paidMs > endMs - SEVEN_DAYS_MS) {
        continue;
      }
      if (payoutPayments.has(`${period}:${payment.payment_id}`)) {
        continue;
      }
      const earlierPeriods = paymentPayoutPeriods.get(payment.payment_id);
      if (earlierPeriods !== undefined) {
        let appearedInEarlierPeriod = false;
        for (const earlierPeriod of earlierPeriods) {
          if (earlierPeriod < period) {
            appearedInEarlierPeriod = true;
            break;
          }
        }
        if (appearedInEarlierPeriod) {
          continue;
        }
      }
      await insertFinding(
        env,
        "payment_not_in_payout",
        payment.payment_id,
        period,
      );
    }
  }
}

async function checkUnrecordedReversal(env: ReconciliationEnv): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT import_id, line_no, kind, payment_id
     FROM payout_line WHERE kind IN ('refund', 'chargeback')`,
  ).all<{
    import_id: string;
    line_no: number;
    kind: string;
    payment_id: string | null;
  }>();

  for (const row of rows.results ?? []) {
    if (row.payment_id !== null) {
      const reversal = await env.DB.prepare(
        `SELECT 1 FROM reversal WHERE payment_id = ?`,
      )
        .bind(row.payment_id)
        .first();
      if (reversal !== null) {
        continue;
      }
    }
    await insertFinding(
      env,
      "unrecorded_reversal",
      `${row.import_id}:${row.line_no}`,
      row.payment_id ?? "",
    );
  }
}

async function checkCallbackWithoutConfirmation(
  env: ReconciliationEnv,
): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT notification_id, checkout_id, body_r2_key, hmac_valid
     FROM notification WHERE hmac_valid = 1`,
  ).all<{
    notification_id: string;
    checkout_id: string | null;
    body_r2_key: string;
    hmac_valid: number;
  }>();

  for (const row of rows.results ?? []) {
    const object = await env.R2.get(row.body_r2_key);
    if (object === undefined || object === null) {
      continue;
    }
    const body = await object.text();
    const parsed = body.startsWith("{")
      ? await parseStoredPaymobNotification(env as PaymobAdapterEnv, body)
      : { authentic: false, events: [] as [] };
    if (!parsed.authentic) {
      continue;
    }
    const succeeded = parsed.events.some(
      (event) => event.kind === "payment_succeeded",
    );
    if (!succeeded) {
      continue;
    }
    const checkoutId = row.checkout_id;
    if (checkoutId === null || checkoutId.length === 0) {
      await insertFinding(
        env,
        "callback_without_confirmation",
        row.notification_id,
        "",
      );
      continue;
    }
    const payment = await env.DB.prepare(
      `SELECT confirmation_inquiry_id FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ confirmation_inquiry_id: string }>();
    if (
      payment !== null &&
      payment.confirmation_inquiry_id.length > 0
    ) {
      continue;
    }
    await insertFinding(
      env,
      "callback_without_confirmation",
      row.notification_id,
      checkoutId,
    );
  }
}

async function clinicsWithRecentCoverageEvents(
  env: ReconciliationEnv,
): Promise<Set<string>> {
  const nowMs = await clockNowMs(env);
  const cutoffMs = nowMs - ONE_DAY_MS;
  const orgIds = new Set<string>();
  let after = 0;
  let hasMore = true;

  while (hasMore) {
    const envelope = await env.PLATFORM.readCoverageEvents({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      after,
      limit: 200,
    });
    if (envelope.result !== "ok" || typeof envelope.detail !== "string") {
      break;
    }
    const page = JSON.parse(envelope.detail) as {
      events?: Array<Record<string, unknown>>;
      next_after?: number;
      has_more?: boolean;
    };
    for (const event of page.events ?? []) {
      const at = event.at;
      const orgId = event.org_id;
      if (typeof at !== "string" || typeof orgId !== "string") {
        continue;
      }
      const eventMs = Date.parse(at);
      if (!Number.isNaN(eventMs) && eventMs >= cutoffMs && eventMs <= nowMs) {
        orgIds.add(orgId);
      }
    }
    if (typeof page.next_after === "number") {
      after = page.next_after;
    }
    hasMore = page.has_more === true;
  }

  return orgIds;
}

function canonicalEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false;
  }
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) {
      return false;
    }
  }
  return true;
}

function receiptObject(value: unknown): Record<string, unknown> | null {
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value) as unknown;
      if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
      return null;
    } catch {
      return null;
    }
  }
  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

async function checkFeedDivergence(env: ReconciliationEnv): Promise<void> {
  const orgIds = await clinicsWithRecentCoverageEvents(env);
  for (const orgId of orgIds) {
    const stored = await env.DB.prepare(
      `SELECT snapshot FROM coverage_view WHERE org_id = ?`,
    )
      .bind(orgId)
      .first<{ snapshot: string }>();
    if (stored === null) {
      continue;
    }

    const coverage = await env.PLATFORM.getCoverage({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      org_id: orgId,
    });
    if (coverage.result !== "ok" || typeof coverage.detail !== "string") {
      continue;
    }
    const detail = JSON.parse(coverage.detail) as {
      snapshot?: Record<string, unknown>;
    };
    const liveSnapshot = detail.snapshot ?? {};
    const storedSnapshot = JSON.parse(stored.snapshot) as Record<string, unknown>;
    if (
      canonicalEqual(
        canonicalize(storedSnapshot),
        canonicalize(liveSnapshot),
      )
    ) {
      continue;
    }
    await insertFinding(env, "feed_divergence", orgId, "");
  }
}

async function checkReceiptMismatch(env: ReconciliationEnv): Promise<void> {
  const grants = await parsePlatformGrants(env);
  if (grants === null) {
    return;
  }
  const grantsById = new Map<string, PlatformGrant>();
  for (const grant of grants) {
    const grantId = String(grant.grant_id ?? "");
    if (grantId.length > 0) {
      grantsById.set(grantId, grant);
    }
  }

  const rows = await env.DB.prepare(
    `SELECT go.grant_id, go.result, go.receipt, gr.source_kind
     FROM grant_outcome go
     INNER JOIN grant_request gr ON gr.grant_id = go.grant_id
     WHERE go.result IN ('applied', 'already_applied')
       AND gr.source_kind != 'transfer'`,
  ).all<{
    grant_id: string;
    result: string;
    receipt: string;
    source_kind: string;
  }>();

  for (const row of rows.results ?? []) {
    const platformGrant = grantsById.get(row.grant_id);
    if (platformGrant === undefined) {
      await insertFinding(env, "receipt_mismatch", row.grant_id, "");
      continue;
    }
    const aboReceipt = receiptObject(row.receipt);
    const platformReceipt = receiptObject(platformGrant.receipt);
    if (aboReceipt === null || platformReceipt === null) {
      await insertFinding(env, "receipt_mismatch", row.grant_id, "");
      continue;
    }
    if (
      !canonicalEqual(
        canonicalize(aboReceipt),
        canonicalize(platformReceipt),
      )
    ) {
      await insertFinding(env, "receipt_mismatch", row.grant_id, "");
    }
  }
}

export async function runReconciliation(env: ReconciliationEnv): Promise<void> {
  await checkPaymentWithoutGrant(env);
  await checkGrantWithoutPayment(env);
  await checkGrantWithoutOperatorAction(env);
  await checkTransferWithoutAuthorisation(env);
  await checkReversalNotApplied(env);
  await checkPayoutUnmatched(env);
  await checkPaymentNotInPayout(env);
  await checkUnrecordedReversal(env);
  await checkCallbackWithoutConfirmation(env);
  await checkFeedDivergence(env);
  await checkReceiptMismatch(env);
}
