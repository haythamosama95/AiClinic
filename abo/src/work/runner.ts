import { canonicalize, humanRef, sha256Hex, ulid } from "vendor-contracts";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import { raiseAlert } from "../alert/index.js";
import { PAYMOB_PROVIDER_ID, providerForId } from "../provider/registry.js";
import type { PaymobAdapterEnv } from "../provider/paymob/adapter.js";
import type { ProviderTxn } from "../provider/port.js";
import { PAYMOB_ADAPTER_VERSION } from "../provider/paymob/adapter.js";
import {
  recordReversalFromProviderTxn,
  type ReversalEnv,
} from "./reversal.js";

const LEASE_MS = 60_000;
const MIN_BACKOFF_MS = 60_000;
const MAX_BACKOFF_MS = 15 * 60_000;
const STALE_CONFIRM_MS = 5 * 60_000;
const CONFIRM_BATCH_LIMIT = 50;

export type WorkRunnerEnv = PaymobAdapterEnv &
  ClockEnv & {
    R2: R2Bucket;
    TEST_CLOCK?: string;
  };

type WorkRow = {
  work_id: string;
  kind: string;
  subject_id: string;
  dedupe_key: string;
  state: string;
  attempts: number;
  next_attempt_at: string | null;
  lease_until: string | null;
  last_error: string | null;
  opened_at: string;
};

type CheckoutRow = {
  checkout_id: string;
  org_id: string;
  offer_id: string;
  offer_version: number;
  charged_price_minor: number;
  currency: string;
  billing_contact_version: number;
  opened_with_coverage_through: string | null;
  contract_version: number;
};

type NotificationRow = {
  notification_id: string;
  body_r2_key: string;
  body_sha256: string;
  channel: string;
};

async function newId(env: WorkRunnerEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

function backoffMs(env: WorkRunnerEnv, attempts: number): number {
  if (env.TEST_CLOCK === "1") {
    return 0;
  }
  const exponent = Math.max(0, attempts - 1);
  return Math.min(MAX_BACKOFF_MS, MIN_BACKOFF_MS * 2 ** exponent);
}

async function takeWork(
  env: WorkRunnerEnv,
  workId: string,
): Promise<WorkRow | null> {
  const nowMs = await clockNowMs(env);
  const nowIso = new Date(nowMs).toISOString();
  const leaseUntil = new Date(nowMs + LEASE_MS).toISOString();

  const leased = await env.DB.prepare(
    `UPDATE work
     SET lease_until = ?
     WHERE work_id = ?
       AND state = 'open'
       AND (lease_until IS NULL OR lease_until <= ?)
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)`,
  )
    .bind(leaseUntil, workId, nowIso, nowIso)
    .run();
  if ((leased.meta.changes ?? 0) === 0) {
    return null;
  }

  return env.DB.prepare(
    `SELECT work_id, kind, subject_id, dedupe_key, state, attempts,
            next_attempt_at, lease_until, last_error, opened_at
     FROM work WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(workId, leaseUntil)
    .first<WorkRow>();
}

async function releaseLeaseRetry(
  env: WorkRunnerEnv,
  workId: string,
  leaseUntil: string,
  attempts: number,
  lastError: string,
): Promise<void> {
  const nowMs = await clockNowMs(env);
  const nextAttempt = new Date(nowMs + backoffMs(env, attempts)).toISOString();
  await env.DB.prepare(
    `UPDATE work
     SET attempts = ?, next_attempt_at = ?, lease_until = NULL, last_error = ?
     WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(attempts, nextAttempt, lastError, workId, leaseUntil)
    .run();
}

async function leaseStillHeld(
  env: WorkRunnerEnv,
  workId: string,
  leaseUntil: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM work WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(workId, leaseUntil)
    .first();
  return row !== null;
}

function paymobStateSeenKey(
  txnId: string,
  normalizedState: string,
  cumulativeReversedMinor: number,
): string {
  return `paymob|${txnId}|${normalizedState}|${cumulativeReversedMinor}`;
}

async function markWorkDone(
  env: WorkRunnerEnv,
  workId: string,
  leaseUntil: string,
): Promise<boolean> {
  const result = await env.DB.prepare(
    `UPDATE work SET state = 'done', lease_until = NULL, last_error = NULL
     WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(workId, leaseUntil)
    .run();
  return (result.meta.changes ?? 0) > 0;
}

async function loadCheckout(
  env: WorkRunnerEnv,
  checkoutId: string,
): Promise<CheckoutRow | null> {
  return env.DB.prepare(
    `SELECT checkout_id, org_id, offer_id, offer_version, charged_price_minor,
            currency, billing_contact_version, opened_with_coverage_through,
            contract_version
     FROM checkout WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<CheckoutRow>();
}

async function checkoutStatusState(
  env: WorkRunnerEnv,
  checkoutId: string,
): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT state FROM checkout_status WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ state: string }>();
  return row?.state ?? null;
}

async function latestNotificationForCheckout(
  env: WorkRunnerEnv,
  checkoutId: string,
): Promise<NotificationRow | null> {
  return env.DB.prepare(
    `SELECT notification_id, body_r2_key, body_sha256, channel
     FROM notification
     WHERE checkout_id = ?
     ORDER BY notification_id DESC
     LIMIT 1`,
  )
    .bind(checkoutId)
    .first<NotificationRow>();
}

async function paymobTxnIdFromNotification(
  env: WorkRunnerEnv,
  notification: NotificationRow,
): Promise<string | null> {
  const object = await env.R2.get(notification.body_r2_key);
  if (object === null) {
    return null;
  }
  const body = await object.text();
  try {
    if (notification.channel === "processed") {
      const parsed = JSON.parse(body) as { obj?: { id?: string | number } };
      return parsed.obj?.id === undefined ? null : String(parsed.obj.id);
    }
    const params = new URLSearchParams(body);
    const id = params.get("id");
    return id === null ? null : id;
  } catch {
    return null;
  }
}

async function appendCheckoutEvent(
  env: WorkRunnerEnv,
  row: {
    checkout_id: string;
    kind: string;
    ref: string;
    at: string;
    contract_version: number;
  },
  createdAt: string,
): Promise<D1PreparedStatement[]> {
  const canonicalRow = {
    checkout_id: row.checkout_id,
    kind: row.kind,
    source: "system",
    ref: row.ref,
    actor: "system",
    at: row.at,
    contract_version: row.contract_version,
  };
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
  return [
    env.DB.prepare(
      `INSERT INTO checkout_event (
         checkout_id, kind, source, ref, actor, at, contract_version
       ) VALUES (?, ?, 'system', ?, 'system', ?, ?)`,
    ).bind(
      row.checkout_id,
      row.kind,
      row.ref,
      row.at,
      row.contract_version,
    ),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind(
      "checkout_event",
      `${row.checkout_id}:${row.kind}:${row.at}`,
      rowSha256,
      createdAt,
    ),
  ];
}

async function shouldWriteInquiryResult(
  env: WorkRunnerEnv,
  subject: string,
  normalizedState: string,
  cumulativeReversedMinor: number,
): Promise<boolean> {
  const latest = await env.DB.prepare(
    `SELECT normalized_state, cumulative_reversed_minor
     FROM inquiry_result
     WHERE subject = ?
     ORDER BY at DESC
     LIMIT 1`,
  )
    .bind(subject)
    .first<{ normalized_state: string; cumulative_reversed_minor: number }>();
  if (latest === null) {
    return true;
  }
  return (
    latest.normalized_state !== normalizedState ||
    latest.cumulative_reversed_minor !== cumulativeReversedMinor
  );
}

async function classificationForPayment(
  env: WorkRunnerEnv,
  checkout: CheckoutRow,
): Promise<"likely_duplicate" | "late" | "normal"> {
  const status = await checkoutStatusState(env, checkout.checkout_id);
  if (status === "expired" || status === "cancelled") {
    return "late";
  }
  if (checkout.opened_with_coverage_through === null) {
    return "normal";
  }
  const prior = await env.DB.prepare(
    `SELECT 1
     FROM payment p
     INNER JOIN checkout c ON c.checkout_id = p.checkout_id
     WHERE p.org_id = ?
       AND c.opened_with_coverage_through = ?
       AND p.checkout_id != ?
     LIMIT 1`,
  )
    .bind(
      checkout.org_id,
      checkout.opened_with_coverage_through,
      checkout.checkout_id,
    )
    .first();
  return prior === null ? "normal" : "likely_duplicate";
}

function paymobStateSeenInsert(
  env: WorkRunnerEnv,
  dedupeKey: string,
  createdAt: string,
): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO paymob_state_seen (dedupe_key, source, first_seen_at)
     VALUES (?, 'confirm', ?)
     ON CONFLICT(dedupe_key) DO NOTHING`,
  ).bind(dedupeKey, createdAt);
}

async function confirmAttemptDeclined(
  env: WorkRunnerEnv,
  work: WorkRow,
  checkout: CheckoutRow,
  notificationId: string,
  leaseUntil: string,
  stateSeenKey: string,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const statements = await appendCheckoutEvent(
    env,
    {
      checkout_id: checkout.checkout_id,
      kind: "attempt_declined",
      ref: notificationId,
      at: nowIso,
      contract_version: checkout.contract_version,
    },
    nowIso,
  );
  statements.push(
    env.DB.prepare(
      `UPDATE checkout_status SET last_event_at = ? WHERE checkout_id = ?`,
    ).bind(nowIso, checkout.checkout_id),
  );
  statements.push(paymobStateSeenInsert(env, stateSeenKey, nowIso));
  statements.push(
    env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL, last_error = NULL
       WHERE work_id = ? AND lease_until = ?`,
    ).bind(work.work_id, leaseUntil),
  );
  const results = await env.DB.batch(statements);
  const workIdx = statements.length - 1;
  if ((results[workIdx]?.meta.changes ?? 0) === 0) {
    throw new Error("lease_lost");
  }
}

async function confirmSuccessBatch(
  env: WorkRunnerEnv,
  work: WorkRow,
  checkout: CheckoutRow,
  notification: NotificationRow,
  leaseUntil: string,
): Promise<void> {
  if (!(await leaseStillHeld(env, work.work_id, leaseUntil))) {
    return;
  }

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    throw new Error("provider_missing");
  }

  const paymobTxnId = await paymobTxnIdFromNotification(env, notification);
  const inquiry = await provider.inquire({
    checkout_id: checkout.checkout_id,
    paymob_txn_id: paymobTxnId ?? undefined,
  });
  if (!inquiry.bound) {
    await raiseAlert(
      env,
      "AL-05",
      `AL-05:unbound:${checkout.checkout_id}`,
      checkout.checkout_id,
    );
    await markWorkDone(env, work.work_id, leaseUntil);
    return;
  }

  if (inquiry.transactions.length === 0) {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseUntil,
      work.attempts + 1,
      "inquiry_retry",
    );
    return;
  }

  const confirmedTxn = inquiry.transactions[0]!;
  const effectiveKind = confirmedTxn.kind;

  const checkoutState = await checkoutStatusState(env, checkout.checkout_id);
  if (checkoutState === "paid" && effectiveKind === "payment_succeeded") {
    await markWorkDone(env, work.work_id, leaseUntil);
    return;
  }

  if (effectiveKind === "payment_pending") {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseUntil,
      work.attempts + 1,
      "pending",
    );
    return;
  }

  const cumulativeReversed =
    confirmedTxn.reversal?.cumulative_reversed_minor ?? 0;
  const providerTxnId =
    confirmedTxn.provider_txn_id ?? paymobTxnId ?? "unknown";
  const stateSeenKey = paymobStateSeenKey(
    providerTxnId,
    effectiveKind,
    cumulativeReversed,
  );
  const existingState = await env.DB.prepare(
    `SELECT 1 FROM paymob_state_seen WHERE dedupe_key = ?`,
  )
    .bind(stateSeenKey)
    .first();
  if (existingState !== null) {
    await markWorkDone(env, work.work_id, leaseUntil);
    return;
  }

  if (effectiveKind === "payment_failed") {
    await confirmAttemptDeclined(
      env,
      work,
      checkout,
      notification.notification_id,
      leaseUntil,
      stateSeenKey,
    );
    return;
  }

  const normalizedState = effectiveKind;
  const subject = `checkout:${checkout.checkout_id}`;
  const nowIso = await clockNowIso(env);
  const inquiryId = await newId(env);
  const inquiryKey = `evidence/inquiry/${inquiryId}`;
  const inquiryJson = JSON.stringify(confirmedTxn);
  await env.R2.put(inquiryKey, inquiryJson);
  const inquirySha = await sha256Hex(new TextEncoder().encode(inquiryJson));

  const statements: D1PreparedStatement[] = [
    paymobStateSeenInsert(env, stateSeenKey, nowIso),
  ];

  if (
    await shouldWriteInquiryResult(
      env,
      subject,
      normalizedState,
      cumulativeReversed,
    )
  ) {
    statements.push(
      env.DB.prepare(
        `INSERT INTO inquiry_result (
           inquiry_id, subject, normalized_state, cumulative_reversed_minor,
           raw_r2_key, raw_sha256, at, adapter_version
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        inquiryId,
        subject,
        normalizedState,
        cumulativeReversed,
        inquiryKey,
        inquirySha,
        nowIso,
        PAYMOB_ADAPTER_VERSION,
      ),
    );
  }

  if (effectiveKind === "reversal") {
    if (confirmedTxn.reversal?.is_full !== true) {
      await releaseLeaseRetry(
        env,
        work.work_id,
        leaseUntil,
        work.attempts + 1,
        "partial_reversal",
      );
      return;
    }
    const paymentId = confirmedTxn.payment_id;
    const reference = humanRef("PAY", paymentId);
    const classification = await classificationForPayment(env, checkout);
    const paymentCanonical = {
      payment_id: paymentId,
      reference,
      org_id: checkout.org_id,
      checkout_id: checkout.checkout_id,
      provider_id: PAYMOB_PROVIDER_ID,
      amount_minor: confirmedTxn.amount_minor,
      currency: confirmedTxn.currency,
      paid_at: confirmedTxn.occurred_at,
      confirmed_at: nowIso,
      confirmation_inquiry_id: inquiryId,
      offer_id: checkout.offer_id,
      offer_version: checkout.offer_version,
      billing_contact_version: checkout.billing_contact_version,
      classification,
      disposition: "reversed_before_grant",
      mismatch_detail: null,
      evidence_sha256: notification.body_sha256,
    };
    const paymentSha = await sha256Hex(canonicalize(paymentCanonical));
    statements.push(
      env.DB.prepare(
        `INSERT INTO payment (
           payment_id, reference, org_id, checkout_id, provider_id, amount_minor,
           currency, paid_at, confirmed_at, confirmation_inquiry_id, offer_id,
           offer_version, billing_contact_version, classification, disposition,
           mismatch_detail, evidence_sha256
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        paymentId,
        reference,
        checkout.org_id,
        checkout.checkout_id,
        PAYMOB_PROVIDER_ID,
        confirmedTxn.amount_minor,
        confirmedTxn.currency,
        confirmedTxn.occurred_at,
        nowIso,
        inquiryId,
        checkout.offer_id,
        checkout.offer_version,
        checkout.billing_contact_version,
        classification,
        "reversed_before_grant",
        null,
        notification.body_sha256,
      ),
      env.DB.prepare(
        `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
      ).bind("payment", paymentId, paymentSha, nowIso),
    );
    statements.push(
      env.DB.prepare(
        `UPDATE work SET state = 'done', lease_until = NULL, last_error = NULL
         WHERE work_id = ? AND lease_until = ?`,
      ).bind(work.work_id, leaseUntil),
    );
    const reversalResults = await env.DB.batch(statements);
    const reversalWorkIdx = statements.length - 1;
    if ((reversalResults[reversalWorkIdx]?.meta.changes ?? 0) === 0) {
      throw new Error("lease_lost");
    }
    await recordReversalFromProviderTxn(
      env as WorkRunnerEnv & ReversalEnv,
      confirmedTxn,
      "inquiry",
      inquirySha,
      paymentId,
    );
    return;
  }

  if (
    confirmedTxn.amount_minor !== checkout.charged_price_minor ||
    confirmedTxn.currency !== checkout.currency
  ) {
    const paymentId = confirmedTxn.payment_id;
    const reference = humanRef("PAY", paymentId);
    const mismatchDetail = JSON.stringify({
      expected_amount_minor: checkout.charged_price_minor,
      expected_currency: checkout.currency,
      actual_amount_minor: confirmedTxn.amount_minor,
      actual_currency: confirmedTxn.currency,
    });
    const classification = await classificationForPayment(env, checkout);
    const paymentCanonical = {
      payment_id: paymentId,
      reference,
      org_id: checkout.org_id,
      checkout_id: checkout.checkout_id,
      provider_id: PAYMOB_PROVIDER_ID,
      amount_minor: confirmedTxn.amount_minor,
      currency: confirmedTxn.currency,
      paid_at: confirmedTxn.occurred_at,
      confirmed_at: nowIso,
      confirmation_inquiry_id: inquiryId,
      offer_id: checkout.offer_id,
      offer_version: checkout.offer_version,
      billing_contact_version: checkout.billing_contact_version,
      classification,
      disposition: "withheld_mismatch",
      mismatch_detail: mismatchDetail,
      evidence_sha256: notification.body_sha256,
    };
    const paymentSha = await sha256Hex(canonicalize(paymentCanonical));
    statements.push(
      env.DB.prepare(
        `INSERT INTO payment (
           payment_id, reference, org_id, checkout_id, provider_id, amount_minor,
           currency, paid_at, confirmed_at, confirmation_inquiry_id, offer_id,
           offer_version, billing_contact_version, classification, disposition,
           mismatch_detail, evidence_sha256
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        paymentId,
        reference,
        checkout.org_id,
        checkout.checkout_id,
        PAYMOB_PROVIDER_ID,
        confirmedTxn.amount_minor,
        confirmedTxn.currency,
        confirmedTxn.occurred_at,
        nowIso,
        inquiryId,
        checkout.offer_id,
        checkout.offer_version,
        checkout.billing_contact_version,
        classification,
        "withheld_mismatch",
        mismatchDetail,
        notification.body_sha256,
      ),
      env.DB.prepare(
        `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
      ).bind("payment", paymentId, paymentSha, nowIso),
    );
    await raiseAlert(
      env,
      "AL-05",
      `AL-05:mismatch:${checkout.checkout_id}`,
      checkout.checkout_id,
    );
    statements.push(
      env.DB.prepare(
        `UPDATE work SET state = 'done', lease_until = NULL, last_error = NULL
         WHERE work_id = ? AND lease_until = ?`,
      ).bind(work.work_id, leaseUntil),
    );
    const mismatchResults = await env.DB.batch(statements);
    const mismatchWorkIdx = statements.length - 1;
    if ((mismatchResults[mismatchWorkIdx]?.meta.changes ?? 0) === 0) {
      throw new Error("lease_lost");
    }
    return;
  }

  const paymentId = confirmedTxn.payment_id;
  const reference = humanRef("PAY", paymentId);
  const classification = await classificationForPayment(env, checkout);
  if (classification === "likely_duplicate") {
    await raiseAlert(
      env,
      "AL-09",
      `AL-09:${checkout.checkout_id}`,
      checkout.checkout_id,
    );
  }
  if (classification === "late") {
    await raiseAlert(env, "AL-08", `AL-08:${checkout.checkout_id}`, checkout.checkout_id);
  }
  const paidCheckoutState =
    classification === "late" ? "paid_late" : "paid";

  const paymentCanonical = {
    payment_id: paymentId,
    reference,
    org_id: checkout.org_id,
    checkout_id: checkout.checkout_id,
    provider_id: PAYMOB_PROVIDER_ID,
    amount_minor: confirmedTxn.amount_minor,
    currency: confirmedTxn.currency,
    paid_at: confirmedTxn.occurred_at,
    confirmed_at: nowIso,
    confirmation_inquiry_id: inquiryId,
    offer_id: checkout.offer_id,
    offer_version: checkout.offer_version,
    billing_contact_version: checkout.billing_contact_version,
    classification,
    disposition: "grant",
    mismatch_detail: null,
    evidence_sha256: notification.body_sha256,
  };
  const paymentSha = await sha256Hex(canonicalize(paymentCanonical));
  const grantWorkId = await newId(env);

  statements.push(
    env.DB.prepare(
      `INSERT INTO payment (
         payment_id, reference, org_id, checkout_id, provider_id, amount_minor,
         currency, paid_at, confirmed_at, confirmation_inquiry_id, offer_id,
         offer_version, billing_contact_version, classification, disposition,
         mismatch_detail, evidence_sha256
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      paymentId,
      reference,
      checkout.org_id,
      checkout.checkout_id,
      PAYMOB_PROVIDER_ID,
      confirmedTxn.amount_minor,
      confirmedTxn.currency,
      confirmedTxn.occurred_at,
      nowIso,
      inquiryId,
      checkout.offer_id,
      checkout.offer_version,
      checkout.billing_contact_version,
      classification,
      "grant",
      null,
      notification.body_sha256,
    ),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind("payment", paymentId, paymentSha, nowIso),
  );
  statements.push(
    ...(await appendCheckoutEvent(
      env,
      {
        checkout_id: checkout.checkout_id,
        kind: "paid",
        ref: reference,
        at: nowIso,
        contract_version: checkout.contract_version,
      },
      nowIso,
    )),
  );
  statements.push(
    env.DB.prepare(
      `UPDATE checkout_status SET state = ?, last_event_at = ? WHERE checkout_id = ?`,
    ).bind(paidCheckoutState, nowIso, checkout.checkout_id),
  );
  statements.push(
    env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, last_error, opened_at
       ) VALUES (?, 'grant', ?, ?, 'open', 0, ?, NULL, NULL, ?)`,
    ).bind(
      grantWorkId,
      paymentId,
      `grant:${paymentId}`,
      nowIso,
      nowIso,
    ),
  );
  const txnId = confirmedTxn.provider_txn_id ?? paymobTxnId;
  if (txnId !== null && txnId !== undefined) {
    const intention = await env.DB.prepare(
      `SELECT order_id FROM paymob_intention WHERE checkout_id = ?`,
    )
      .bind(checkout.checkout_id)
      .first<{ order_id: string }>();
    statements.push(
      env.DB.prepare(
        `INSERT INTO paymob_txn (
           txn_id, order_id, checkout_id, payment_id, parent_txn_id, last_state_key
         ) VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(txn_id) DO UPDATE SET
           payment_id = excluded.payment_id,
           parent_txn_id = excluded.parent_txn_id,
           last_state_key = excluded.last_state_key`,
      ).bind(
        txnId,
        intention?.order_id ?? "",
        checkout.checkout_id,
        paymentId,
        confirmedTxn.provider_parent_txn_id ?? null,
        confirmedTxn.dedupe_key,
      ),
    );
  }
  statements.push(
    env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL, last_error = NULL
       WHERE work_id = ? AND lease_until = ?`,
    ).bind(work.work_id, leaseUntil),
  );

  const grantResults = await env.DB.batch(statements);
  const grantWorkIdx = statements.length - 1;
  if ((grantResults[grantWorkIdx]?.meta.changes ?? 0) === 0) {
    throw new Error("lease_lost");
  }
}

async function processConfirmWork(
  env: WorkRunnerEnv,
  work: WorkRow,
): Promise<{ inquired: boolean }> {
  const leaseUntil = work.lease_until;
  if (leaseUntil === null) {
    return { inquired: false };
  }

  const checkout = await loadCheckout(env, work.subject_id);
  if (checkout === null) {
    await markWorkDone(env, work.work_id, leaseUntil);
    return { inquired: false };
  }

  const notification =
    work.dedupe_key.startsWith("confirm:")
      ? await env.DB.prepare(
          `SELECT notification_id, body_r2_key, body_sha256, channel
           FROM notification
           WHERE notification_id = ?`,
        )
          .bind(work.dedupe_key.slice("confirm:".length))
          .first<NotificationRow>()
      : await latestNotificationForCheckout(env, checkout.checkout_id);

  if (notification === null) {
    const provider = providerForId(env, PAYMOB_PROVIDER_ID);
    if (provider === null) {
      return { inquired: false };
    }
    const inquiry = await provider.inquire({ checkout_id: checkout.checkout_id });
    if (!inquiry.bound && inquiry.transactions.length === 0) {
      await releaseLeaseRetry(
        env,
        work.work_id,
        leaseUntil,
        work.attempts + 1,
        "no_notification",
      );
      return { inquired: false };
    }
    if (inquiry.transactions.length === 0) {
      await releaseLeaseRetry(
        env,
        work.work_id,
        leaseUntil,
        work.attempts + 1,
        "inquiry_retry",
      );
      return { inquired: true };
    }
    const syntheticNotification: NotificationRow = {
      notification_id: "synthetic",
      body_r2_key: "",
      body_sha256: await sha256Hex(new TextEncoder().encode("")),
      channel: "processed",
    };
    await confirmSuccessBatch(
      env,
      work,
      checkout,
      syntheticNotification,
      leaseUntil,
    );
    return { inquired: true };
  }

  if (notification.body_r2_key.length === 0) {
    await confirmSuccessBatch(
      env,
      work,
      checkout,
      notification,
      leaseUntil,
    );
    return { inquired: true };
  }

  const paymobTxnId = await paymobTxnIdFromNotification(env, notification);
  if (paymobTxnId === null) {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseUntil,
      work.attempts + 1,
      "parse_failed",
    );
    return { inquired: false };
  }

  try {
    await confirmSuccessBatch(
      env,
      work,
      checkout,
      notification,
      leaseUntil,
    );
    return { inquired: true };
  } catch {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseUntil,
      work.attempts + 1,
      "batch_failed",
    );
    return { inquired: true };
  }
}

export async function runConfirmForWorkId(
  env: WorkRunnerEnv,
  workId: string,
): Promise<{ inquired: boolean }> {
  const work = await takeWork(env, workId);
  if (work === null || work.kind !== "confirm") {
    return { inquired: false };
  }
  const leaseUntil = work.lease_until;
  if (leaseUntil === null) {
    return { inquired: false };
  }
  try {
    return await processConfirmWork(env, work);
  } catch {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseUntil,
      work.attempts + 1,
      "batch_failed",
    );
    return { inquired: false };
  }
}

async function raiseStaleConfirmAlerts(env: WorkRunnerEnv): Promise<void> {
  const nowMs = await clockNowMs(env);
  const rows = await env.DB.prepare(
    `SELECT work_id, opened_at FROM work WHERE kind = 'confirm' AND state = 'open'`,
  ).all<{ work_id: string; opened_at: string }>();

  for (const row of rows.results ?? []) {
    const openedMs = Date.parse(row.opened_at);
    if (nowMs - openedMs > STALE_CONFIRM_MS) {
      await raiseAlert(env, "AL-01", `AL-01:${row.work_id}`, row.work_id);
    }
  }
}

export async function runDueConfirmWork(
  env: WorkRunnerEnv,
  limit = CONFIRM_BATCH_LIMIT,
): Promise<void> {
  await raiseStaleConfirmAlerts(env);
  const nowIso = await clockNowIso(env);
  const due = await env.DB.prepare(
    `SELECT work_id FROM work
     WHERE kind = 'confirm'
       AND state = 'open'
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
     ORDER BY next_attempt_at ASC
     LIMIT ?`,
  )
    .bind(nowIso, limit)
    .all<{ work_id: string }>();

  for (const row of due.results ?? []) {
    try {
      await runConfirmForWorkId(env, row.work_id);
    } catch {
      // Single row failure must not throw out of cron.
    }
  }
}
