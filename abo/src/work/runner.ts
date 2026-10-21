import { canonicalize, grantIdPaid, humanRef, sha256Hex, ulid } from "vendor-contracts";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import { raiseAlert } from "../alert/index.js";
import {
  PAYMOB_ADAPTER_VERSION,
  PAYMOB_PROVIDER_ID,
  providerForId,
  type ProviderRegistryEnv,
} from "../provider/registry.js";
import type { InquireResult, ProviderTxn } from "../provider/port.js";
import {
  recordReversalFromProviderTxn,
  type ReversalEnv,
} from "./reversal.js";
import { claimRawEvidence, putClaimedRawEvidence } from "../evidence/raw.js";

const LEASE_MS = 60_000;
const MIN_BACKOFF_MS = 60_000;
const MAX_BACKOFF_MS = 15 * 60_000;
const STALE_CONFIRM_MS = 5 * 60_000;
const CONFIRM_BATCH_LIMIT = 50;

export type WorkRunnerEnv = ProviderRegistryEnv &
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
  lease_token: string | null;
  last_error: string | null;
  opened_at: string;
};

export type CheckoutRow = {
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
  checkout_id?: string | null;
  disposition?: string;
  provider_txn_id?: string | null;
};

async function newId(env: WorkRunnerEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

function backoffMs(attempts: number): number {
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
  const leaseToken = crypto.randomUUID();

  const leased = await env.DB.prepare(
    `UPDATE work
     SET lease_until = ?, lease_token = ?
     WHERE work_id = ?
       AND state = 'open'
       AND (lease_until IS NULL OR lease_until <= ?)
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)`,
  )
    .bind(leaseUntil, leaseToken, workId, nowIso, nowIso)
    .run();
  if ((leased.meta.changes ?? 0) === 0) {
    return null;
  }

  return env.DB.prepare(
    `SELECT work_id, kind, subject_id, dedupe_key, state, attempts,
            next_attempt_at, lease_until, lease_token, last_error, opened_at
     FROM work WHERE work_id = ? AND lease_until = ? AND lease_token = ?`,
  )
    .bind(workId, leaseUntil, leaseToken)
    .first<WorkRow>();
}

async function releaseLeaseRetry(
  env: WorkRunnerEnv,
  workId: string,
  leaseToken: string,
  attempts: number,
  lastError: string,
): Promise<void> {
  const nowMs = await clockNowMs(env);
  const nextAttempt = new Date(nowMs + backoffMs(attempts)).toISOString();
  await env.DB.prepare(
    `UPDATE work
     SET attempts = ?, next_attempt_at = ?, lease_until = NULL, lease_token = NULL, last_error = ?
     WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
  )
    .bind(attempts, nextAttempt, lastError, workId, leaseToken)
    .run();
}

async function leaseStillHeld(
  env: WorkRunnerEnv,
  workId: string,
  leaseToken: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
  )
    .bind(workId, leaseToken)
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
  leaseToken: string,
): Promise<boolean> {
  const result = await env.DB.prepare(
    `UPDATE work SET state = 'done', lease_until = NULL, lease_token = NULL, last_error = NULL
     WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
  )
    .bind(workId, leaseToken)
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
    `SELECT notification_id, body_r2_key, body_sha256, channel, provider_txn_id
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
  if (notification.provider_txn_id != null) {
    return notification.provider_txn_id;
  }
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
  lease: { workId: string; token: string },
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
  return [
    env.DB.prepare(
      `INSERT INTO checkout_event (
         checkout_id, kind, source, ref, actor, at, contract_version
       ) SELECT ?, ?, 'system', ?, 'system', ?, ?
       WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)`,
    ).bind(
      row.checkout_id,
      row.kind,
      row.ref,
      row.at,
      row.contract_version,
      lease.workId,
      lease.token,
    ),
    await insertFencedFactLog(
      env,
      "checkout_event",
      `${row.checkout_id}:${row.kind}:${row.at}`,
      canonicalRow,
      createdAt,
      lease.workId,
      lease.token,
    ),
  ];
}

async function appendPaidTransition(
  env: WorkRunnerEnv,
  checkout: CheckoutRow,
  reference: string,
  at: string,
  workId: string,
  leaseToken: string,
): Promise<D1PreparedStatement[]> {
  const canonicalRow = {
    checkout_id: checkout.checkout_id,
    kind: "paid",
    source: "system",
    ref: reference,
    actor: "system",
    at,
    contract_version: checkout.contract_version,
  };
  const rowJsonBytes = canonicalize(canonicalRow);
  const rowJson = new TextDecoder().decode(rowJsonBytes);
  const rowSha256 = await sha256Hex(rowJsonBytes);
  const firstPaidTransition = `EXISTS (
      SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?
    ) AND NOT EXISTS (
      SELECT 1 FROM checkout_status
      WHERE checkout_id = ? AND state IN ('paid', 'paid_late')
    )`;
  return [
    env.DB.prepare(
      `INSERT INTO checkout_event (
         checkout_id, kind, source, ref, actor, at, contract_version
       ) SELECT ?, 'paid', 'system', ?, 'system', ?, ?
       WHERE ${firstPaidTransition}`,
    ).bind(
      checkout.checkout_id,
      reference,
      at,
      checkout.contract_version,
      workId,
      leaseToken,
      checkout.checkout_id,
    ),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
       SELECT 'checkout_event', ?, ?, ?, ?
       WHERE ${firstPaidTransition}`,
    ).bind(
      `${checkout.checkout_id}:paid:${at}`,
      rowSha256,
      rowJson,
      at,
      workId,
      leaseToken,
      checkout.checkout_id,
    ),
  ];
}

async function insertFencedFactLog(
  env: WorkRunnerEnv,
  table: string,
  key: string,
  canonicalRow: Record<string, unknown>,
  createdAt: string,
  workId: string,
  leaseToken: string,
): Promise<D1PreparedStatement> {
  const rowJsonBytes = canonicalize(canonicalRow);
  const rowJson = new TextDecoder().decode(rowJsonBytes);
  const rowSha256 = await sha256Hex(rowJsonBytes);
  return env.DB.prepare(
    `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
     SELECT ?, ?, ?, ?, ?
     WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)`,
  ).bind(table, key, rowSha256, rowJson, createdAt, workId, leaseToken);
}

async function persistInquiryResult(
  env: WorkRunnerEnv,
  input: {
    work: WorkRow;
    leaseToken: string;
    checkout: CheckoutRow;
    subject: string;
    normalizedState: string;
    cumulativeReversedMinor: number;
    at: string;
    evidence: InquireResult["evidence"];
  },
): Promise<{
  inquiryId: string;
  evidenceSha256: string;
  statements: D1PreparedStatement[];
} | null> {
  // Legacy empty-hash/fake-ID rows are not evidence. A current authenticated
  // answer is required before any payment can reference an inquiry identity.
  const decisive = input.evidence?.filter((entry) => entry.role === "transaction").at(-1);
  if (decisive === undefined || decisive.raw_body.length === 0 ||
      await sha256Hex(new TextEncoder().encode(decisive.raw_body)) !== decisive.sha256) {
    return null;
  }
  const previous = await env.DB.prepare(
    `SELECT inquiry_id, raw_r2_key, raw_sha256
     FROM inquiry_result
     WHERE subject = ? AND normalized_state = ? AND cumulative_reversed_minor = ?
     ORDER BY at DESC LIMIT 1`,
  ).bind(input.subject, input.normalizedState, input.cumulativeReversedMinor)
    .first<{ inquiry_id: string; raw_r2_key: string; raw_sha256: string }>();
  if (previous !== null && previous.raw_sha256 === decisive.sha256 &&
      /^[a-f0-9]{64}$/u.test(previous.raw_sha256)) {
    return {
      inquiryId: previous.inquiry_id,
      evidenceSha256: previous.raw_sha256,
      statements: [],
    };
  }
  const inquiryId = await newId(env);
  const candidateKey = `evidence/inquiry/${inquiryId}`;
  const contact = await env.DB.prepare(
    `SELECT erasure_generation, erased_at FROM billing_contact
     WHERE org_id = ? AND version = ?`,
  ).bind(input.checkout.org_id, input.checkout.billing_contact_version)
    .first<{ erasure_generation: number; erased_at: string | null }>();
  if (contact === null) {
    return null;
  }
  let rawR2Key = "";
  if (contact.erased_at === null) {
    const claim = {
      evidenceId: inquiryId,
      orgId: input.checkout.org_id,
      checkoutId: input.checkout.checkout_id,
      kind: "inquiry" as const,
      r2Key: candidateKey,
      sha256: decisive.sha256,
      expectedGeneration: contact.erasure_generation,
    };
    const generation = await claimRawEvidence(env, claim);
    let rawRetained = false;
    if (generation !== null) {
      rawRetained = await putClaimedRawEvidence(
        env,
        claim,
        generation,
        decisive.raw_body,
      );
    }
    if (!rawRetained) {
      const fence = await env.DB.prepare(
        `SELECT generation FROM org_erasure_fence WHERE org_id = ?`,
      ).bind(input.checkout.org_id).first<{ generation: number }>();
      // A newer immutable fence deliberately blocks raw retention. Keep only
      // the normalized outcome/hash below; ordinary claim/upload failures
      // remain retryable and never become evidence by themselves.
      if (fence === null || fence.generation <= contact.erasure_generation) {
        return null;
      }
    } else {
      rawR2Key = candidateKey;
    }
  }
  const canonicalRow = {
    inquiry_id: inquiryId,
    subject: input.subject,
    normalized_state: input.normalizedState,
    cumulative_reversed_minor: input.cumulativeReversedMinor,
    raw_r2_key: rawR2Key,
    raw_sha256: decisive.sha256,
    at: input.at,
    adapter_version: PAYMOB_ADAPTER_VERSION,
  };
  const statements = [
    env.DB.prepare(
      `INSERT INTO inquiry_result (
         inquiry_id, subject, normalized_state, cumulative_reversed_minor,
         raw_r2_key, raw_sha256, at, adapter_version
       ) SELECT ?, ?, ?, ?, ?, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)`,
    ).bind(
      inquiryId, input.subject, input.normalizedState, input.cumulativeReversedMinor,
      rawR2Key, decisive.sha256, input.at, PAYMOB_ADAPTER_VERSION,
      input.work.work_id, input.leaseToken,
    ),
    await insertFencedFactLog(
      env,
      "inquiry_result",
      inquiryId,
      canonicalRow,
      input.at,
      input.work.work_id,
      input.leaseToken,
    ),
  ];
  return { inquiryId, evidenceSha256: decisive.sha256, statements };
}

async function classificationForPayment(
  env: WorkRunnerEnv,
  checkout: CheckoutRow,
): Promise<"likely_duplicate" | "late" | "normal"> {
  const status = await checkoutStatusState(env, checkout.checkout_id);
  if (status === "expired" || status === "cancelled") {
    return "late";
  }
  const prior = await env.DB.prepare(
    `SELECT 1
     FROM payment p
     INNER JOIN checkout c ON c.checkout_id = p.checkout_id
     WHERE p.org_id = ?
       AND c.opened_with_coverage_through IS ?
     LIMIT 1`,
  )
    .bind(checkout.org_id, checkout.opened_with_coverage_through)
    .first();
  return prior === null ? "normal" : "likely_duplicate";
}

export type PaymentConfirmationDecision = {
  disposition: "grant" | "withheld_mismatch";
  mismatchDetail: string | null;
};

/** Shared financial rule used by live confirmation and rebuild ingestion. */
export function decidePaymentConfirmation(
  checkout: CheckoutRow,
  txn: ProviderTxn,
): PaymentConfirmationDecision {
  if (txn.kind !== "payment_succeeded" || txn.checkout_id !== checkout.checkout_id) {
    throw new Error("payment_confirmation_identity_conflict");
  }
  if (
    Number.isSafeInteger(txn.amount_minor) && txn.amount_minor === checkout.charged_price_minor &&
    txn.currency === checkout.currency
  ) {
    return { disposition: "grant", mismatchDetail: null };
  }
  return {
    disposition: "withheld_mismatch",
    mismatchDetail: JSON.stringify({
      expected_amount_minor: checkout.charged_price_minor,
      expected_currency: checkout.currency,
      actual_amount_minor: txn.amount_minor,
      actual_currency: txn.currency,
    }),
  };
}

async function originalOrderMatches(
  env: WorkRunnerEnv,
  checkoutId: string,
  txn: ProviderTxn,
): Promise<boolean> {
  if (txn.checkout_id !== checkoutId || typeof txn.provider_order_id !== "string") {
    return false;
  }
  const row = await env.DB.prepare(
    `SELECT 1 FROM paymob_intention_attempt
     WHERE checkout_id = ? AND order_id = ? AND state = 'created' LIMIT 1`,
  ).bind(checkoutId, txn.provider_order_id).first();
  return row !== null;
}

function mismatchAlertStatement(
  env: WorkRunnerEnv,
  checkoutId: string,
): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO alert (
       alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id
     ) VALUES (?, 'AL-05', 1, 1, NULL, NULL, ?)
     ON CONFLICT(alert_key) DO UPDATE SET
       active = 1,
       unsent = CASE
         WHEN alert.active = 0 OR alert.unsent = 1 OR alert.last_sent_at IS NULL THEN 1
         ELSE alert.unsent
       END,
       code = 'AL-05', detail_id = excluded.detail_id`,
  ).bind(`AL-05:mismatch:${checkoutId}`, checkoutId);
}

function paymobStateSeenInsert(
  env: WorkRunnerEnv,
  dedupeKey: string,
  createdAt: string,
  workId: string,
  leaseToken: string,
): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO paymob_state_seen (dedupe_key, source, first_seen_at)
     SELECT ?, 'confirm', ?
     WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)
     ON CONFLICT(dedupe_key) DO NOTHING`,
  ).bind(dedupeKey, createdAt, workId, leaseToken);
}

async function confirmAttemptDeclined(
  env: WorkRunnerEnv,
  work: WorkRow,
  checkout: CheckoutRow,
  notificationId: string,
  leaseToken: string,
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
    { workId: work.work_id, token: leaseToken },
  );
  statements.push(
    env.DB.prepare(
      `UPDATE checkout_status SET last_event_at = ? WHERE checkout_id = ?
       AND EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)`,
    ).bind(nowIso, checkout.checkout_id, work.work_id, leaseToken),
  );
  statements.push(paymobStateSeenInsert(env, stateSeenKey, nowIso, work.work_id, leaseToken));
  statements.push(
    env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL, lease_token = NULL, last_error = NULL
       WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
    ).bind(work.work_id, leaseToken),
  );
  const results = await env.DB.batch(statements);
  const workIdx = statements.length - 1;
  if ((results[workIdx]?.meta.changes ?? 0) === 0) {
    throw new Error("lease_lost");
  }
}

export async function recordPaidConfirmation(
  env: WorkRunnerEnv,
  input: {
    work: WorkRow;
    leaseToken: string;
    leadingStatements: D1PreparedStatement[];
    checkout: CheckoutRow;
    confirmedTxn: ProviderTxn;
    inquiryId: string;
    evidenceSha256: string;
    nowIso: string;
    paymobTxnId?: string | null;
  },
): Promise<boolean> {
  if (!(await originalOrderMatches(env, input.checkout.checkout_id, input.confirmedTxn))) {
    throw new Error("payment_confirmation_original_order_unbound");
  }
  if (decidePaymentConfirmation(input.checkout, input.confirmedTxn).disposition !== "grant") {
    throw new Error("payment_confirmation_withheld_mismatch");
  }
  const paymentId = input.confirmedTxn.payment_id;
  const existing = await env.DB.prepare(
    `SELECT checkout_id, provider_id, amount_minor, currency, disposition
     FROM payment WHERE payment_id = ?`,
  )
    .bind(paymentId)
    .first<{ checkout_id: string; provider_id: string; amount_minor: number; currency: string; disposition: string }>();
  if (existing !== null) {
    if (
      existing.checkout_id !== input.checkout.checkout_id ||
      existing.provider_id !== PAYMOB_PROVIDER_ID ||
      existing.amount_minor !== input.confirmedTxn.amount_minor ||
      existing.currency !== input.confirmedTxn.currency
    ) {
      throw new Error("payment_identity_conflict");
    }
    const statements: D1PreparedStatement[] = [...input.leadingStatements];
    if (existing.disposition === "grant") {
      const grantId = await grantIdPaid(paymentId);
      const applied = await env.DB.prepare(
        `SELECT 1 FROM grant_outcome_event WHERE grant_id = ? AND terminal = 1`,
      )
        .bind(grantId)
        .first();
      if (applied === null) {
        const grantWorkId = await newId(env);
        statements.push(
          env.DB.prepare(
            `INSERT INTO work (
               work_id, kind, subject_id, dedupe_key, state, attempts,
               next_attempt_at, lease_until, lease_token, last_error, opened_at
             ) SELECT ?, 'grant', ?, ?, 'open', 0, ?, NULL, NULL, NULL, ?
             WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)
             ON CONFLICT(dedupe_key) DO UPDATE SET
               state = 'open', attempts = 0, next_attempt_at = excluded.next_attempt_at,
               lease_until = NULL, lease_token = NULL, last_error = NULL
             WHERE work.state IN ('done', 'parked')`,
          ).bind(grantWorkId, paymentId, `grant:${paymentId}`, input.nowIso, input.nowIso, input.work.work_id, input.leaseToken),
        );
      }
    }
    statements.push(
      env.DB.prepare(
        `UPDATE work SET state = 'done', lease_until = NULL, lease_token = NULL, last_error = NULL
         WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
      ).bind(input.work.work_id, input.leaseToken),
    );
    const results = await env.DB.batch(statements);
    if ((results[statements.length - 1]?.meta.changes ?? 0) === 0) {
      throw new Error("lease_lost");
    }
    return false;
  }

  const reference = humanRef("PAY", paymentId);
  const classification = await classificationForPayment(env, input.checkout);
  const paidCheckoutState =
    classification === "late" ? "paid_late" : "paid";

  const paymentCanonical = {
    payment_id: paymentId,
    reference,
    org_id: input.checkout.org_id,
    checkout_id: input.checkout.checkout_id,
    provider_id: PAYMOB_PROVIDER_ID,
    amount_minor: input.confirmedTxn.amount_minor,
    currency: input.confirmedTxn.currency,
    paid_at: input.confirmedTxn.occurred_at,
    confirmed_at: input.nowIso,
    confirmation_inquiry_id: input.inquiryId,
    offer_id: input.checkout.offer_id,
    offer_version: input.checkout.offer_version,
    billing_contact_version: input.checkout.billing_contact_version,
    classification,
    disposition: "grant",
    mismatch_detail: null,
    evidence_sha256: input.evidenceSha256,
  };
  const grantWorkId = await newId(env);
  const statements: D1PreparedStatement[] = [
    ...input.leadingStatements,
    env.DB.prepare(
      `INSERT INTO payment (
         payment_id, reference, org_id, checkout_id, provider_id, amount_minor,
         currency, paid_at, confirmed_at, confirmation_inquiry_id, offer_id,
         offer_version, billing_contact_version, classification, disposition,
         mismatch_detail, evidence_sha256
       ) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)`,
    ).bind(
      paymentId,
      reference,
      input.checkout.org_id,
      input.checkout.checkout_id,
      PAYMOB_PROVIDER_ID,
      input.confirmedTxn.amount_minor,
      input.confirmedTxn.currency,
      input.confirmedTxn.occurred_at,
      input.nowIso,
      input.inquiryId,
      input.checkout.offer_id,
      input.checkout.offer_version,
      input.checkout.billing_contact_version,
      classification,
      "grant",
      null,
      input.evidenceSha256,
      input.work.work_id,
      input.leaseToken,
    ),
    await insertFencedFactLog(
      env,
      "payment",
      paymentId,
      paymentCanonical,
      input.nowIso,
      input.work.work_id,
      input.leaseToken,
    ),
    ...(await appendPaidTransition(
      env,
      input.checkout,
      reference,
      input.nowIso,
      input.work.work_id,
      input.leaseToken,
    )),
    env.DB.prepare(
      `UPDATE checkout_status SET state = ?, last_event_at = ? WHERE checkout_id = ?
       AND EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)`,
    ).bind(paidCheckoutState, input.nowIso, input.checkout.checkout_id, input.work.work_id, input.leaseToken),
    env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, last_error, opened_at
       ) SELECT ?, 'grant', ?, ?, 'open', 0, ?, NULL, NULL, ?
       WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)
       ON CONFLICT(dedupe_key) DO NOTHING`,
    ).bind(
      grantWorkId,
      paymentId,
      `grant:${paymentId}`,
      input.nowIso,
      input.nowIso,
      input.work.work_id,
      input.leaseToken,
    ),
  ];

  const txnId = input.confirmedTxn.provider_txn_id ?? input.paymobTxnId;
  const orderId = input.confirmedTxn.provider_order_id;
  if (txnId !== null && txnId !== undefined && orderId !== undefined) {
    statements.push(
      env.DB.prepare(
        `INSERT INTO paymob_txn (
           txn_id, order_id, checkout_id, payment_id, parent_txn_id, last_state_key
         ) SELECT ?, ?, ?, ?, ?, ?
         WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)
         ON CONFLICT(txn_id) DO UPDATE SET
           payment_id = excluded.payment_id,
           parent_txn_id = excluded.parent_txn_id,
           last_state_key = excluded.last_state_key`,
      ).bind(
        txnId,
        orderId,
        input.checkout.checkout_id,
        paymentId,
        input.confirmedTxn.provider_parent_txn_id ?? null,
        input.confirmedTxn.dedupe_key,
        input.work.work_id,
        input.leaseToken,
      ),
    );
  }

  statements.push(
    env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL, lease_token = NULL, last_error = NULL
       WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
    ).bind(input.work.work_id, input.leaseToken),
  );
  const results = await env.DB.batch(statements);
  if ((results[statements.length - 1]?.meta.changes ?? 0) === 0) {
    throw new Error("lease_lost");
  }
  if (classification === "likely_duplicate") {
    await raiseAlert(
      env,
      "AL-09",
      `AL-09:${input.checkout.checkout_id}`,
      input.checkout.checkout_id,
    );
  }
  if (classification === "late") {
    await raiseAlert(
      env,
      "AL-08",
      `AL-08:${input.checkout.checkout_id}`,
      input.checkout.checkout_id,
    );
  }
  return true;
}

/**
 * Rebuild can discover a succeeded provider transaction that has no callback
 * work row because the local database was wiped. Give that one replay an
 * in-batch lease row: the leading INSERT and all lease-fenced payment writes
 * are committed atomically, so no synthetic confirm item survives a failure.
 */
export async function recordRebuiltPaidConfirmation(
  env: WorkRunnerEnv,
  input: {
    checkout: CheckoutRow;
    confirmedTxn: ProviderTxn;
    inquiry: InquireResult;
    nowIso: string;
    paymobTxnId?: string | null;
  },
): Promise<boolean> {
  if (!(await originalOrderMatches(env, input.checkout.checkout_id, input.confirmedTxn))) {
    return false;
  }
  const existingPayment = await env.DB.prepare(
    `SELECT 1 FROM payment WHERE payment_id = ?`,
  )
    .bind(input.confirmedTxn.payment_id)
    .first();
  if (existingPayment !== null) {
    return false;
  }
  const workId = await newId(env);
  const leaseToken = crypto.randomUUID();
  const dedupeKey = `rebuild-confirm:${input.confirmedTxn.payment_id}:${workId}`;
  const work: WorkRow = {
    work_id: workId,
    kind: "confirm",
    subject_id: input.checkout.checkout_id,
    dedupe_key: dedupeKey,
    state: "open",
    attempts: 0,
    next_attempt_at: null,
    lease_until: input.nowIso,
    lease_token: leaseToken,
    last_error: null,
    opened_at: input.nowIso,
  };
  const leadingStatements = [
    env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, lease_token, last_error, opened_at
       ) VALUES (?, 'confirm', ?, ?, 'open', 0, NULL, ?, ?, NULL, ?)`,
    ).bind(workId, input.checkout.checkout_id, dedupeKey, input.nowIso, leaseToken, input.nowIso),
  ];
  const cumulativeReversed = input.confirmedTxn.reversal?.cumulative_reversed_minor ?? 0;
  const inquiryEvidence = await persistInquiryResult(env, {
    work,
    leaseToken,
    checkout: input.checkout,
    subject: `checkout:${input.checkout.checkout_id}`,
    normalizedState: input.confirmedTxn.kind,
    cumulativeReversedMinor: cumulativeReversed,
    at: input.nowIso,
    evidence: input.inquiry.evidence,
  });
  if (inquiryEvidence === null) {
    return false;
  }
  leadingStatements.push(...inquiryEvidence.statements);
  const decision = decidePaymentConfirmation(input.checkout, input.confirmedTxn);
  if (decision.disposition === "withheld_mismatch") {
    const paymentId = input.confirmedTxn.payment_id;
    const reference = humanRef("PAY", paymentId);
    const classification = await classificationForPayment(env, input.checkout);
    const paymentCanonical = {
      payment_id: paymentId,
      reference,
      org_id: input.checkout.org_id,
      checkout_id: input.checkout.checkout_id,
      provider_id: PAYMOB_PROVIDER_ID,
      amount_minor: input.confirmedTxn.amount_minor,
      currency: input.confirmedTxn.currency,
      paid_at: input.confirmedTxn.occurred_at,
      confirmed_at: input.nowIso,
      confirmation_inquiry_id: inquiryEvidence.inquiryId,
      offer_id: input.checkout.offer_id,
      offer_version: input.checkout.offer_version,
      billing_contact_version: input.checkout.billing_contact_version,
      classification,
      disposition: "withheld_mismatch",
      mismatch_detail: decision.mismatchDetail,
      evidence_sha256: inquiryEvidence.evidenceSha256,
    };
    const paymentFactStatement = await insertFencedFactLog(
      env, "payment", paymentId, paymentCanonical, input.nowIso, workId, leaseToken,
    );
    const result = await env.DB.batch([
      ...leadingStatements,
      env.DB.prepare(
        `INSERT INTO payment (
           payment_id, reference, org_id, checkout_id, provider_id, amount_minor,
           currency, paid_at, confirmed_at, confirmation_inquiry_id, offer_id,
           offer_version, billing_contact_version, classification, disposition,
           mismatch_detail, evidence_sha256
         ) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
         WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)`,
      ).bind(
        paymentId, reference, input.checkout.org_id, input.checkout.checkout_id,
        PAYMOB_PROVIDER_ID, input.confirmedTxn.amount_minor, input.confirmedTxn.currency,
        input.confirmedTxn.occurred_at, input.nowIso, inquiryEvidence.inquiryId,
        input.checkout.offer_id, input.checkout.offer_version,
        input.checkout.billing_contact_version, classification, "withheld_mismatch",
        decision.mismatchDetail, inquiryEvidence.evidenceSha256, workId, leaseToken,
      ),
      paymentFactStatement,
      mismatchAlertStatement(env, input.checkout.checkout_id),
      env.DB.prepare(
        `UPDATE work SET state = 'done', lease_until = NULL, lease_token = NULL
         WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
      ).bind(workId, leaseToken),
    ]);
    if ((result.at(-1)?.meta.changes ?? 0) === 0) {
      throw new Error("lease_lost");
    }
    return true;
  }
  return recordPaidConfirmation(env, {
    ...input,
    inquiryId: inquiryEvidence.inquiryId,
    evidenceSha256: inquiryEvidence.evidenceSha256,
    work,
    leaseToken,
    leadingStatements,
  });
}

/** Persist an authenticated recovery inquiry even when it does not prove payment. */
export async function recordRebuiltInquiryEvidence(
  env: WorkRunnerEnv,
  input: {
    checkout: CheckoutRow;
    txn: ProviderTxn;
    inquiry: InquireResult;
    nowIso: string;
  },
): Promise<{ inquiryId: string; evidenceSha256: string } | null> {
  const evidenceHash = input.inquiry.evidence
    ?.filter((entry) => entry.role === "transaction").at(-1)?.sha256;
  if (evidenceHash === undefined || !/^[a-f0-9]{64}$/u.test(evidenceHash)) return null;
  const workId = await newId(env);
  const leaseToken = crypto.randomUUID();
  const dedupeKey = `rebuild-inquiry:${input.checkout.checkout_id}:${input.txn.kind}:${input.txn.dedupe_key}:${evidenceHash}`;
  const work: WorkRow = {
    work_id: workId,
    kind: "confirm",
    subject_id: input.checkout.checkout_id,
    dedupe_key: dedupeKey,
    state: "open",
    attempts: 0,
    next_attempt_at: input.nowIso,
    lease_until: input.nowIso,
    lease_token: leaseToken,
    last_error: null,
    opened_at: input.nowIso,
  };
  const stored = await persistInquiryResult(env, {
    work,
    leaseToken,
    checkout: input.checkout,
    subject: `checkout:${input.checkout.checkout_id}`,
    normalizedState: input.txn.kind,
    cumulativeReversedMinor: input.txn.reversal?.cumulative_reversed_minor ?? 0,
    at: input.nowIso,
    evidence: input.inquiry.evidence,
  });
  if (stored === null) return null;
  if (stored.statements.length === 0) {
    return { inquiryId: stored.inquiryId, evidenceSha256: stored.evidenceSha256 };
  }
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, lease_token, last_error, opened_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      work.work_id, work.kind, work.subject_id, work.dedupe_key, work.state,
      work.attempts, work.next_attempt_at, work.lease_until, work.lease_token,
      work.last_error, work.opened_at,
    ),
    ...stored.statements,
    env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL, lease_token = NULL
       WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
    ).bind(workId, leaseToken),
  ]);
  return { inquiryId: stored.inquiryId, evidenceSha256: stored.evidenceSha256 };
}

async function confirmSuccessBatch(
  env: WorkRunnerEnv,
  work: WorkRow,
  checkout: CheckoutRow,
  notification: NotificationRow,
  leaseToken: string,
  authoritativeInquiry?: InquireResult,
): Promise<void> {
  if (!(await leaseStillHeld(env, work.work_id, leaseToken))) {
    return;
  }

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    throw new Error("provider_missing");
  }

  const paymobTxnId = await paymobTxnIdFromNotification(env, notification);
  const inquiry = authoritativeInquiry ?? await provider.inquire({
    checkout_id: checkout.checkout_id,
    paymob_txn_id: paymobTxnId ?? undefined,
  });
  if (inquiry.deferred) {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseToken,
      work.attempts + 1,
      "inquiry_deferred",
    );
    return;
  }
  if (!inquiry.bound) {
    await raiseAlert(
      env,
      "AL-05",
      `AL-05:unbound:${checkout.checkout_id}`,
      checkout.checkout_id,
    );
    await markWorkDone(env, work.work_id, leaseToken);
    return;
  }

  if (inquiry.discovery_unavailable) {
    await raiseAlert(
      env,
      "AL-03",
      `AL-03:discovery:${checkout.checkout_id}`,
      checkout.checkout_id,
    );
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseToken,
      work.attempts + 1,
      "discovery_unavailable",
    );
    return;
  }

  if (inquiry.transactions.length === 0) {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseToken,
      work.attempts + 1,
      "inquiry_retry",
    );
    return;
  }

  const confirmedTxn = inquiry.transactions[0]!;
  const effectiveKind = confirmedTxn.kind;

  if (effectiveKind === "payment_pending") {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseToken,
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
  if (existingState !== null && effectiveKind !== "payment_succeeded") {
    await markWorkDone(env, work.work_id, leaseToken);
    return;
  }

  if (effectiveKind === "payment_failed") {
    await confirmAttemptDeclined(
      env,
      work,
      checkout,
      notification.notification_id,
      leaseToken,
      stateSeenKey,
    );
    return;
  }

  const normalizedState = effectiveKind;
  const subject = `checkout:${checkout.checkout_id}`;
  const nowIso = await clockNowIso(env);
  const inquiryEvidence = await persistInquiryResult(env, {
    work,
    leaseToken,
    checkout,
    subject,
    normalizedState,
    cumulativeReversedMinor: cumulativeReversed,
    at: nowIso,
    evidence: inquiry.evidence,
  });
  if (inquiryEvidence === null) {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseToken,
      work.attempts + 1,
      "inquiry_evidence_unavailable",
    );
    return;
  }
  const inquiryId = inquiryEvidence.inquiryId;
  const inquirySha = inquiryEvidence.evidenceSha256;
  const statements: D1PreparedStatement[] = [
    paymobStateSeenInsert(env, stateSeenKey, nowIso, work.work_id, leaseToken),
    ...inquiryEvidence.statements,
  ];

  if (effectiveKind === "reversal") {
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
    statements.push(
      env.DB.prepare(
        `INSERT INTO payment (
           payment_id, reference, org_id, checkout_id, provider_id, amount_minor,
           currency, paid_at, confirmed_at, confirmation_inquiry_id, offer_id,
           offer_version, billing_contact_version, classification, disposition,
           mismatch_detail, evidence_sha256
         ) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
         WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)`,
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
        work.work_id,
        leaseToken,
      ),
      await insertFencedFactLog(env, "payment", paymentId, paymentCanonical, nowIso, work.work_id, leaseToken),
    );
    const reversalTxnId = confirmedTxn.provider_txn_id;
    const reversalOrderId = confirmedTxn.provider_order_id;
    if (reversalTxnId !== undefined && reversalOrderId !== undefined) {
      statements.push(
        env.DB.prepare(
          `INSERT INTO paymob_txn (
             txn_id, order_id, checkout_id, payment_id, parent_txn_id, last_state_key
           ) SELECT ?, ?, ?, ?, ?, ?
           WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)
           ON CONFLICT(txn_id) DO UPDATE SET
             payment_id = excluded.payment_id,
             parent_txn_id = excluded.parent_txn_id,
             last_state_key = excluded.last_state_key`,
        ).bind(
          reversalTxnId,
          reversalOrderId,
          checkout.checkout_id,
          paymentId,
          confirmedTxn.provider_parent_txn_id ?? null,
          confirmedTxn.dedupe_key,
          work.work_id,
          leaseToken,
        ),
      );
    }
    statements.push(
      env.DB.prepare(
        `UPDATE work SET state = 'done', lease_until = NULL, lease_token = NULL, last_error = NULL
         WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
      ).bind(work.work_id, leaseToken),
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

  if (!(await originalOrderMatches(env, checkout.checkout_id, confirmedTxn))) {
    await raiseAlert(
      env,
      "AL-05",
      `AL-05:unbound:${checkout.checkout_id}`,
      checkout.checkout_id,
    );
    await markWorkDone(env, work.work_id, leaseToken);
    return;
  }
  const paymentDecision = decidePaymentConfirmation(checkout, confirmedTxn);
  if (paymentDecision.disposition === "withheld_mismatch") {
    const paymentId = confirmedTxn.payment_id;
    const reference = humanRef("PAY", paymentId);
    const mismatchDetail = paymentDecision.mismatchDetail;
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
    statements.push(
      env.DB.prepare(
        `INSERT INTO payment (
           payment_id, reference, org_id, checkout_id, provider_id, amount_minor,
           currency, paid_at, confirmed_at, confirmation_inquiry_id, offer_id,
           offer_version, billing_contact_version, classification, disposition,
           mismatch_detail, evidence_sha256
         ) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
         WHERE EXISTS (SELECT 1 FROM work WHERE work_id = ? AND state = 'open' AND lease_token = ?)`,
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
        work.work_id,
        leaseToken,
      ),
      await insertFencedFactLog(env, "payment", paymentId, paymentCanonical, nowIso, work.work_id, leaseToken),
    );
    statements.push(
      mismatchAlertStatement(env, checkout.checkout_id),
      env.DB.prepare(
        `UPDATE work SET state = 'done', lease_until = NULL, lease_token = NULL, last_error = NULL
         WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
      ).bind(work.work_id, leaseToken),
    );
    const mismatchResults = await env.DB.batch(statements);
    const mismatchWorkIdx = statements.length - 1;
    if ((mismatchResults[mismatchWorkIdx]?.meta.changes ?? 0) === 0) {
      throw new Error("lease_lost");
    }
    return;
  }

  await recordPaidConfirmation(env, {
    work,
    leaseToken,
    leadingStatements: statements,
    checkout,
    confirmedTxn,
    inquiryId,
    evidenceSha256: notification.body_sha256,
    nowIso,
    paymobTxnId,
  });
}

async function processConfirmWork(
  env: WorkRunnerEnv,
  work: WorkRow,
  authoritativeInquiry?: InquireResult,
): Promise<{ inquired: boolean }> {
  const leaseToken = work.lease_token;
  if (leaseToken === null) {
    return { inquired: false };
  }

  const checkout = await loadCheckout(env, work.subject_id);
  if (checkout === null) {
    await markWorkDone(env, work.work_id, leaseToken);
    return { inquired: false };
  }

  const notification =
    work.dedupe_key.startsWith("confirm:")
      ? await env.DB.prepare(
          `SELECT notification_id, body_r2_key, body_sha256, channel, provider_txn_id
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
    const manualTxnId = /^confirm:manual:[^:]+:(\d+)$/u.exec(work.dedupe_key)?.[1];
    const inquiry = authoritativeInquiry ?? await provider.inquire({
      checkout_id: checkout.checkout_id,
      paymob_txn_id: manualTxnId,
    });
    if (inquiry.deferred) {
      await releaseLeaseRetry(
        env,
        work.work_id,
        leaseToken,
        work.attempts + 1,
        "inquiry_deferred",
      );
      return { inquired: false };
    }
    if (!inquiry.bound && inquiry.transactions.length === 0) {
      await releaseLeaseRetry(
        env,
        work.work_id,
        leaseToken,
        work.attempts + 1,
        "no_notification",
      );
      return { inquired: false };
    }
    if (inquiry.discovery_unavailable) {
      await raiseAlert(
        env,
        "AL-03",
        `AL-03:discovery:${checkout.checkout_id}`,
        checkout.checkout_id,
      );
      await releaseLeaseRetry(
        env,
        work.work_id,
        leaseToken,
        work.attempts + 1,
        "discovery_unavailable",
      );
      return { inquired: true };
    }
    if (inquiry.transactions.length === 0) {
      await releaseLeaseRetry(
        env,
        work.work_id,
        leaseToken,
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
      provider_txn_id: manualTxnId,
    };
    await confirmSuccessBatch(
      env,
      work,
      checkout,
      syntheticNotification,
      leaseToken,
      inquiry,
    );
    return { inquired: true };
  }

  if (notification.body_r2_key.length === 0) {
    await confirmSuccessBatch(
      env,
      work,
      checkout,
      notification,
      leaseToken,
      authoritativeInquiry,
    );
    return { inquired: true };
  }

  const paymobTxnId = await paymobTxnIdFromNotification(env, notification);
  if (paymobTxnId === null) {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseToken,
      work.attempts + 1,
      "parse_failed",
    );
    return { inquired: false };
  }

  try {
    const sameTxnInquiry =
      authoritativeInquiry?.transactions.some(
        (txn) => txn.provider_txn_id === paymobTxnId,
      ) === true
        ? authoritativeInquiry
        : undefined;
    await confirmSuccessBatch(
      env,
      work,
      checkout,
      notification,
      leaseToken,
      sameTxnInquiry,
    );
    return { inquired: true };
  } catch {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseToken,
      work.attempts + 1,
      "batch_failed",
    );
    return { inquired: true };
  }
}

export async function runConfirmForWorkId(
  env: WorkRunnerEnv,
  workId: string,
  authoritativeInquiry?: InquireResult,
): Promise<{ inquired: boolean }> {
  const work = await takeWork(env, workId);
  if (work === null || work.kind !== "confirm") {
    return { inquired: false };
  }
  const leaseToken = work.lease_token;
  if (leaseToken === null) {
    return { inquired: false };
  }
  try {
    return await processConfirmWork(env, work, authoritativeInquiry);
  } catch {
    await releaseLeaseRetry(
      env,
      work.work_id,
      leaseToken,
      work.attempts + 1,
      "batch_failed",
    );
    return { inquired: false };
  }
}

export async function raiseStaleConfirmAlerts(env: WorkRunnerEnv): Promise<void> {
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

/**
 * Reopen an enqueued notification's original confirm work when an older build
 * left the body claim without its work, or committed a success marker before
 * its payment. The notification only schedules a fresh authoritative inquiry;
 * callback text is never used to create payment value.
 */
async function recoverMissingConfirmWork(env: WorkRunnerEnv): Promise<void> {
  const notifications = await env.DB.prepare(
    `SELECT notification_id, body_r2_key, body_sha256, channel, checkout_id, disposition,
            provider_txn_id
     FROM notification
     WHERE disposition = 'enqueued' AND checkout_id IS NOT NULL`,
  ).all<NotificationRow>();

  for (const notification of notifications.results ?? []) {
    const dedupeKey = `confirm:${notification.notification_id}`;
    const existingWork = await env.DB.prepare(
      `SELECT work_id, state FROM work WHERE dedupe_key = ?`,
    )
      .bind(dedupeKey)
      .first<{ work_id: string; state: string }>();
    let needsRecovery = existingWork === null;

    const txnId = await paymobTxnIdFromNotification(env, notification);
    if (txnId !== null) {
      const successSeen = await env.DB.prepare(
        `SELECT 1 FROM paymob_state_seen WHERE dedupe_key = ?`,
      )
        .bind(paymobStateSeenKey(txnId, "payment_succeeded", 0))
        .first();
      if (successSeen !== null) {
        const mapped = await env.DB.prepare(
          `SELECT payment_id FROM paymob_txn WHERE txn_id = ?`,
        )
          .bind(txnId)
          .first<{ payment_id: string | null }>();
        const payment = mapped?.payment_id
          ? await env.DB.prepare(
              `SELECT disposition FROM payment WHERE payment_id = ?`,
            )
              .bind(mapped.payment_id)
              .first<{ disposition: string }>()
          : null;
        if (payment === null) {
          needsRecovery = true;
        } else {
          needsRecovery = false;
        }
        if (payment?.disposition === "grant") {
          const grantId = await grantIdPaid(mapped!.payment_id);
          const outcome = await env.DB.prepare(
            `SELECT 1 FROM grant_outcome_event WHERE grant_id = ? AND terminal = 1`,
          )
            .bind(grantId)
            .first();
          const grantWork = await env.DB.prepare(
            `SELECT 1 FROM work WHERE dedupe_key = ?`,
          )
            .bind(`grant:${mapped!.payment_id}`)
            .first();
          if (outcome === null && grantWork === null) {
            const grantWorkId = await newId(env);
            const nowIso = await clockNowIso(env);
            await env.DB.prepare(
              `INSERT INTO work (
                 work_id, kind, subject_id, dedupe_key, state, attempts,
                 next_attempt_at, lease_until, lease_token, last_error, opened_at
               ) VALUES (?, 'grant', ?, ?, 'open', 0, ?, NULL, NULL, NULL, ?)
               ON CONFLICT(dedupe_key) DO NOTHING`,
            )
              .bind(grantWorkId, mapped!.payment_id, `grant:${mapped!.payment_id}`, nowIso, nowIso)
              .run();
          } else if (outcome === null) {
            await env.DB.prepare(
              `UPDATE work SET state = 'open', next_attempt_at = ?, lease_until = NULL,
                   lease_token = NULL, last_error = NULL
               WHERE dedupe_key = ? AND kind = 'grant' AND state IN ('done', 'parked')`,
            )
              .bind(await clockNowIso(env), `grant:${mapped!.payment_id}`)
              .run();
          }
        }
      }
    }

    if (!needsRecovery) {
      continue;
    }
    const workId = await newId(env);
    const nowIso = await clockNowIso(env);
    await env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, lease_token, last_error, opened_at
       ) VALUES (?, 'confirm', ?, ?, 'open', 0, ?, NULL, NULL, NULL, ?)
       ON CONFLICT(dedupe_key) DO UPDATE SET
         state = 'open', attempts = 0, next_attempt_at = excluded.next_attempt_at,
         lease_until = NULL, lease_token = NULL, last_error = NULL
       WHERE work.state IN ('done', 'parked')`,
    )
      .bind(
        workId,
        notification.checkout_id!,
        dedupeKey,
        nowIso,
        nowIso,
      )
      .run();
  }
}

export async function runDueConfirmWork(
  env: WorkRunnerEnv,
  limit = CONFIRM_BATCH_LIMIT,
): Promise<void> {
  await recoverMissingConfirmWork(env);
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
