import { CHANNEL_VERSIONS, sha256Hex, ulid } from "vendor-contracts";
import { raiseAlert } from "../alert/index.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import { PAYMOB_PROVIDER_ID, providerForId } from "../provider/registry.js";
import type { PaymobAdapterEnv } from "../provider/paymob/adapter.js";
import { runConfirmForWorkId, type WorkRunnerEnv } from "./runner.js";
import {
  recordReversalFromProviderTxn,
  type ReversalEnv,
} from "./reversal.js";

const CHECKOUT_OFFSETS_MS = [
  2 * 60_000,
  5 * 60_000,
  10 * 60_000,
  20 * 60_000,
];
const TEN_MINUTES_MS = 10 * 60 * 1000;
const ONE_DAY_MS = 24 * 60 * 60_000;
const SEVEN_DAYS_MS = 7 * ONE_DAY_MS;
const POST_EXPIRY_OFFSETS_MS = [ONE_DAY_MS, 3 * ONE_DAY_MS, SEVEN_DAYS_MS];

export type SweepEnv = PaymobAdapterEnv &
  ClockEnv &
  WorkRunnerEnv &
  ReversalEnv & {
    R2: R2Bucket;
  };

export type SweepProcessResult = {
  inquired: boolean;
};

type CheckoutRow = {
  checkout_id: string;
  expires_at: string;
};

type OpenedEvent = {
  at: string;
};

async function newId(env: SweepEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

async function openedEventAt(
  env: SweepEnv,
  checkoutId: string,
): Promise<OpenedEvent | null> {
  return env.DB.prepare(
    `SELECT at FROM checkout_event WHERE checkout_id = ? AND kind = 'opened'`,
  )
    .bind(checkoutId)
    .first<OpenedEvent>();
}

async function checkoutStatus(
  env: SweepEnv,
  checkoutId: string,
): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT state FROM checkout_status WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ state: string }>();
  return row?.state ?? null;
}

async function loadCheckout(
  env: SweepEnv,
  checkoutId: string,
): Promise<CheckoutRow | null> {
  return env.DB.prepare(
    `SELECT checkout_id, expires_at FROM checkout WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<CheckoutRow>();
}

async function insertSweepWorkRow(
  env: SweepEnv,
  kind: "sweep_checkout" | "sweep_payment",
  subjectId: string,
  dedupeKey: string,
  nextAttemptAt: string,
): Promise<void> {
  const existing = await env.DB.prepare(
    `SELECT work_id FROM work WHERE dedupe_key = ?`,
  )
    .bind(dedupeKey)
    .first();
  if (existing !== null) {
    return;
  }
  const nowIso = await clockNowIso(env);
  const workId = await newId(env);
  await env.DB.prepare(
    `INSERT INTO work (
       work_id, kind, subject_id, dedupe_key, state, attempts,
       next_attempt_at, lease_until, last_error, opened_at
     ) VALUES (?, ?, ?, ?, 'open', 0, ?, NULL, NULL, ?)`,
  )
    .bind(workId, kind, subjectId, dedupeKey, nextAttemptAt, nowIso)
    .run();
}

function offsetIso(baseIso: string, offsetMs: number): string {
  return new Date(Date.parse(baseIso) + offsetMs).toISOString();
}

export async function scheduleCheckoutSweepRows(
  env: SweepEnv,
  checkoutId: string,
): Promise<void> {
  const opened = await openedEventAt(env, checkoutId);
  const checkout = await loadCheckout(env, checkoutId);
  if (opened === null || checkout === null) {
    return;
  }

  const openedMs = Date.parse(opened.at);
  const expiresMs = Date.parse(checkout.expires_at);

  for (const offsetMs of CHECKOUT_OFFSETS_MS) {
    const dueMs = openedMs + offsetMs;
    if (dueMs <= expiresMs) {
      await insertSweepWorkRow(
        env,
        "sweep_checkout",
        checkoutId,
        `sweep_checkout:${checkoutId}:${offsetMs}`,
        new Date(dueMs).toISOString(),
      );
    }
  }

  let rolling = openedMs + 20 * 60_000;
  while (rolling + TEN_MINUTES_MS < expiresMs) {
    rolling += TEN_MINUTES_MS;
    await insertSweepWorkRow(
      env,
      "sweep_checkout",
      checkoutId,
      `sweep_checkout:${checkoutId}:${rolling - openedMs}`,
      new Date(rolling).toISOString(),
    );
  }

  await insertSweepWorkRow(
    env,
    "sweep_checkout",
    checkoutId,
    `sweep_checkout:${checkoutId}:${expiresMs - openedMs}`,
    checkout.expires_at,
  );

  const status = await checkoutStatus(env, checkoutId);
  if (status === "expired" || status === "cancelled") {
    for (const offsetMs of POST_EXPIRY_OFFSETS_MS) {
      await insertSweepWorkRow(
        env,
        "sweep_checkout",
        checkoutId,
        `sweep_checkout:${checkoutId}:post:${offsetMs}`,
        offsetIso(checkout.expires_at, offsetMs),
      );
    }
  }
}

export async function materializeCheckoutSweepSchedules(
  env: SweepEnv,
): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT c.checkout_id
     FROM checkout c
     INNER JOIN checkout_status cs ON cs.checkout_id = c.checkout_id
     WHERE cs.state IN ('open', 'expired', 'cancelled')`,
  ).all<{ checkout_id: string }>();

  for (const row of rows.results ?? []) {
    await scheduleCheckoutSweepRows(env, row.checkout_id);
  }
}

async function markSweepWorkDone(env: SweepEnv, workId: string): Promise<void> {
  await env.DB.prepare(
    `UPDATE work SET state = 'done', lease_until = NULL WHERE work_id = ?`,
  )
    .bind(workId)
    .run();
}

async function hasHmacValidNotification(
  env: SweepEnv,
  checkoutId: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM notification
     WHERE checkout_id = ? AND hmac_valid = 1
     LIMIT 1`,
  )
    .bind(checkoutId)
    .first();
  return row !== null;
}

async function ensureConfirmWorkForCheckout(
  env: SweepEnv,
  checkoutId: string,
): Promise<string | null> {
  const existing = await env.DB.prepare(
    `SELECT work_id FROM work
     WHERE kind = 'confirm' AND subject_id = ? AND state = 'open'
     ORDER BY opened_at ASC LIMIT 1`,
  )
    .bind(checkoutId)
    .first<{ work_id: string }>();
  if (existing !== null) {
    return existing.work_id;
  }

  const dedupeKey = `confirm-schedule:${checkoutId}`;
  const scheduled = await env.DB.prepare(
    `SELECT work_id FROM work WHERE dedupe_key = ?`,
  )
    .bind(dedupeKey)
    .first<{ work_id: string }>();
  if (scheduled !== null) {
    return scheduled.work_id;
  }

  const nowIso = await clockNowIso(env);
  const workId = await newId(env);
  await env.DB.prepare(
    `INSERT INTO work (
       work_id, kind, subject_id, dedupe_key, state, attempts,
       next_attempt_at, lease_until, last_error, opened_at
     ) VALUES (?, 'confirm', ?, ?, 'open', 0, ?, NULL, NULL, ?)`,
  )
    .bind(workId, checkoutId, dedupeKey, nowIso, nowIso)
    .run();
  return workId;
}

export async function processSweepCheckoutWork(
  env: SweepEnv,
  workId: string,
): Promise<SweepProcessResult> {
  const work = await env.DB.prepare(
    `SELECT work_id, kind, subject_id, dedupe_key, state, attempts,
            next_attempt_at, lease_until, last_error, opened_at
     FROM work WHERE work_id = ? AND kind = 'sweep_checkout'`,
  )
    .bind(workId)
    .first<{
      work_id: string;
      subject_id: string;
      dedupe_key: string;
      state: string;
      next_attempt_at: string | null;
      lease_until: string | null;
    }>();

  if (work === null || work.state !== "open") {
    return { inquired: false };
  }

  const checkoutId = work.subject_id;
  const checkout = await loadCheckout(env, checkoutId);
  if (checkout === null) {
    await markSweepWorkDone(env, workId);
    return { inquired: false };
  }

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return { inquired: false };
  }

  const inquiry = await provider.inquire({ checkout_id: checkoutId });
  const nowIso = await clockNowIso(env);
  const status = await checkoutStatus(env, checkoutId);
  const isExpirySweep = work.next_attempt_at === checkout.expires_at;

  if (!inquiry.bound) {
    return { inquired: false };
  }

  if (
    inquiry.transactions.length > 0 &&
    inquiry.transactions[0]!.kind === "reversal"
  ) {
    const txn = inquiry.transactions[0]!;
    const evidenceSha = await sha256Hex(
      new TextEncoder().encode(JSON.stringify(txn)),
    );
    const paymentRow = await env.DB.prepare(
      `SELECT payment_id FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ payment_id: string }>();
    await recordReversalFromProviderTxn(
      env,
      txn,
      "inquiry",
      evidenceSha,
      paymentRow?.payment_id,
    );
    await markSweepWorkDone(env, workId);
    return { inquired: true };
  }

  const paymentExists = await env.DB.prepare(
    `SELECT 1 FROM payment WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first();

  const atOrPastExpiry =
    Date.parse(nowIso) >= Date.parse(checkout.expires_at);
  const strictlyPastExpiry =
    Date.parse(nowIso) > Date.parse(checkout.expires_at);
  const hasSucceededInquiry =
    inquiry.transactions.length > 0 &&
    inquiry.transactions[0]!.kind === "payment_succeeded";

  if (
    paymentExists === null &&
    status === "open" &&
    isExpirySweep &&
    atOrPastExpiry &&
    (!hasSucceededInquiry || !strictlyPastExpiry)
  ) {
    await env.DB.prepare(
      `UPDATE checkout_status SET state = 'expired', last_event_at = ? WHERE checkout_id = ?`,
    )
      .bind(nowIso, checkoutId)
      .run();
    await scheduleCheckoutSweepRows(env, checkoutId);
    await markSweepWorkDone(env, workId);
    return { inquired: true };
  }

  if (hasSucceededInquiry) {
    const beforeExpiry = Date.parse(nowIso) < Date.parse(checkout.expires_at);
    const mayConfirm =
      (status === "open" && beforeExpiry && !isExpirySweep) ||
      (status === "open" && isExpirySweep && strictlyPastExpiry) ||
      ((status === "expired" || status === "cancelled") && strictlyPastExpiry);
    if (mayConfirm) {
      const confirmWorkId = await ensureConfirmWorkForCheckout(env, checkoutId);
      if (confirmWorkId !== null) {
        await runConfirmForWorkId(env, confirmWorkId);
        const paymentRow = await env.DB.prepare(
          `SELECT payment_id FROM payment WHERE checkout_id = ?`,
        )
          .bind(checkoutId)
          .first<{ payment_id: string }>();
        if (
          paymentRow !== null &&
          !(await hasHmacValidNotification(env, checkoutId))
        ) {
          await raiseAlert(
            env,
            "AL-03",
            `AL-03:${paymentRow.payment_id}`,
            paymentRow.payment_id,
          );
        }
      }
    }
    await markSweepWorkDone(env, workId);
    return { inquired: true };
  }

  if (inquiry.transactions.length === 0) {
    if (!isExpirySweep) {
      await markSweepWorkDone(env, workId);
    }
    return { inquired: true };
  }

  await markSweepWorkDone(env, workId);
  return { inquired: true };
}

export async function processSweepPaymentWork(
  env: SweepEnv,
  workId: string,
): Promise<SweepProcessResult> {
  const work = await env.DB.prepare(
    `SELECT work_id, subject_id, state FROM work
     WHERE work_id = ? AND kind = 'sweep_payment'`,
  )
    .bind(workId)
    .first<{ work_id: string; subject_id: string; state: string }>();

  if (work === null || work.state !== "open") {
    return { inquired: false };
  }

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return { inquired: false };
  }

  const inquiry = await provider.inquire({ payment_id: work.subject_id });
  if (!inquiry.bound) {
    return { inquired: false };
  }

  if (
    inquiry.transactions.length > 0 &&
    inquiry.transactions[0]!.kind === "reversal"
  ) {
    const txn = inquiry.transactions[0]!;
    const evidenceSha = await sha256Hex(
      new TextEncoder().encode(JSON.stringify(txn)),
    );
    await recordReversalFromProviderTxn(
      env,
      txn,
      "inquiry",
      evidenceSha,
      work.subject_id,
    );
    await markSweepWorkDone(env, workId);
    return { inquired: true };
  }

  if (inquiry.transactions.length === 0) {
    return { inquired: true };
  }

  await markSweepWorkDone(env, workId);
  return { inquired: true };
}

function paymentDaySlot(paymentIdValue: string): bigint {
  return BigInt(`0x${paymentIdValue}`) % 7n;
}

function paymentMinuteOffset(paymentIdValue: string): number {
  return Number(BigInt(`0x${paymentIdValue}`) % 1440n);
}

function utcEpochDayMod7(nowMs: number): number {
  return Math.floor(nowMs / 86_400_000) % 7;
}

function dailyDueAt(nowMs: number, paymentIdValue: string): string {
  const dayStart = new Date(nowMs);
  dayStart.setUTCHours(6, 0, 0, 0);
  const minuteOffset = paymentMinuteOffset(paymentIdValue);
  return new Date(dayStart.getTime() + minuteOffset * 60_000).toISOString();
}

function hourBucketKey(nowIso: string): string {
  return nowIso.slice(0, 13);
}

function sixHourBucketKey(nowMs: number): string {
  const bucket = Math.floor(nowMs / (6 * 60 * 60_000));
  return String(bucket);
}

function dayBucketKey(nowMs: number): string {
  const day = new Date(nowMs);
  day.setUTCHours(0, 0, 0, 0);
  return day.toISOString().slice(0, 10);
}

export async function enqueueHourlyReversalPopulation(
  env: SweepEnv,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const hourKey = hourBucketKey(nowIso);
  const sevenDaysAgo = new Date(
    Date.parse(nowIso) - 7 * ONE_DAY_MS,
  ).toISOString();

  const rows = await env.DB.prepare(
    `SELECT p.payment_id
     FROM payment p
     WHERE p.confirmed_at >= ?
        OR NOT EXISTS (
          SELECT 1 FROM grant_outcome go
          INNER JOIN grant_request gr ON gr.grant_id = go.grant_id
          WHERE gr.source_ref = p.payment_id
            AND go.result IN ('applied', 'already_applied')
        )`,
  )
    .bind(sevenDaysAgo)
    .all<{ payment_id: string }>();

  for (const row of rows.results ?? []) {
    await insertSweepWorkRow(
      env,
      "sweep_payment",
      row.payment_id,
      `sweep_payment:hourly:${row.payment_id}:${hourKey}`,
      nowIso,
    );
  }
}

type CoverageTerm = {
  term_id?: string;
  state?: string;
  ends_at?: string;
  grace_ends_at?: string;
};

type CoverageDetail = {
  snapshot?: { terms?: CoverageTerm[] };
  terms?: CoverageTerm[];
  recent_terms?: CoverageTerm[];
  queued_terms?: CoverageTerm[];
};

function coverageTermsById(detail: CoverageDetail): Map<string, CoverageTerm> {
  const termsById = new Map<string, CoverageTerm>();
  for (const term of [
    ...(detail.snapshot?.terms ?? []),
    ...(detail.terms ?? []),
    ...(detail.recent_terms ?? []),
    ...(detail.queued_terms ?? []),
  ]) {
    if (term.term_id !== undefined) {
      termsById.set(term.term_id, term);
    }
  }
  return termsById;
}

function parseTermTime(iso: string | undefined): number | null {
  if (iso === undefined || iso === "") {
    return null;
  }
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? null : ms;
}

function termFundsLiveAt(term: CoverageTerm, nowMs: number): boolean {
  const state = term.state;
  if (state === undefined || state === "ended" || state === "exhausted") {
    return false;
  }
  if (state === "held" || state === "queued") {
    return true;
  }
  if (state === "grace") {
    const graceEnd = parseTermTime(term.grace_ends_at);
    return graceEnd === null || graceEnd > nowMs;
  }
  if (state === "active") {
    const endsAt = parseTermTime(term.ends_at);
    if (endsAt !== null && endsAt <= nowMs) {
      const graceEnd = parseTermTime(term.grace_ends_at);
      return graceEnd !== null && graceEnd > nowMs;
    }
    return true;
  }
  return false;
}

function paymentFundsLiveTermForEnqueue(
  termIds: string[],
  detail: CoverageDetail,
  nowMs: number,
): boolean {
  const termsById = coverageTermsById(detail);
  return termIds.some((termId) => {
    const term = termsById.get(termId);
    if (term === undefined) {
      // Grant applied but term not listed yet (queued/held) — still inquire.
      return true;
    }
    return termFundsLiveAt(term, nowMs);
  });
}

async function grantTermIdsForPayment(
  env: SweepEnv,
  paymentIdValue: string,
): Promise<string[]> {
  const outcome = await env.DB.prepare(
    `SELECT term_ids FROM grant_outcome go
     INNER JOIN grant_request gr ON gr.grant_id = go.grant_id
     WHERE gr.source_ref = ? AND go.result IN ('applied', 'already_applied')`,
  )
    .bind(paymentIdValue)
    .first<{ term_ids: string }>();
  if (outcome?.term_ids === undefined) {
    return [];
  }
  try {
    return JSON.parse(outcome.term_ids) as string[];
  } catch {
    return [];
  }
}

async function paymentQualifiesForHourly(
  env: SweepEnv,
  paymentIdValue: string,
  confirmedAt: string,
  sevenDaysAgo: string,
): Promise<boolean> {
  if (confirmedAt >= sevenDaysAgo) {
    return true;
  }
  const applied = await env.DB.prepare(
    `SELECT 1 FROM grant_outcome go
     INNER JOIN grant_request gr ON gr.grant_id = go.grant_id
     WHERE gr.source_ref = ?
       AND go.result IN ('applied', 'already_applied')`,
  )
    .bind(paymentIdValue)
    .first();
  return applied === null;
}

async function loadCoverageDetail(
  env: SweepEnv,
  orgId: string,
  coverageByOrg: Map<string, CoverageDetail | null>,
): Promise<CoverageDetail | null> {
  let detail = coverageByOrg.get(orgId);
  if (detail !== undefined) {
    return detail;
  }
  const coverage = await env.PLATFORM.getCoverage({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    org_id: orgId,
  });
  if (coverage.result !== "ok") {
    coverageByOrg.set(orgId, null);
    return null;
  }
  try {
    detail = JSON.parse(String(coverage.detail)) as CoverageDetail;
    coverageByOrg.set(orgId, detail);
    return detail;
  } catch {
    coverageByOrg.set(orgId, null);
    return null;
  }
}

export async function enqueueSixHourReversalPopulation(
  env: SweepEnv,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const nowMs = await clockNowMs(env);
  const bucketKey = sixHourBucketKey(nowMs);

  const rows = await env.DB.prepare(
    `SELECT p.payment_id, p.org_id
     FROM payment p
     INNER JOIN grant_request gr ON gr.source_ref = p.payment_id
     INNER JOIN grant_outcome go ON go.grant_id = gr.grant_id
       AND go.result IN ('applied', 'already_applied')
     WHERE NOT EXISTS (
       SELECT 1 FROM reversal r WHERE r.payment_id = p.payment_id
     )
     ORDER BY p.confirmed_at ASC, p.checkout_id ASC`,
  ).all<{ payment_id: string; org_id: string }>();

  const coverageByOrg = new Map<string, CoverageDetail | null>();
  const seenOrgs = new Set<string>();

  const enqueueSixHourRow = async (paymentId: string, orgId: string) => {
    if (seenOrgs.has(orgId)) {
      return;
    }
    seenOrgs.add(orgId);
    await insertSweepWorkRow(
      env,
      "sweep_payment",
      paymentId,
      `sweep_payment:sixhour:${paymentId}:${bucketKey}`,
      nowIso,
    );
  };

  for (const row of rows.results ?? []) {
    if (seenOrgs.has(row.org_id)) {
      continue;
    }
    const termIds = await grantTermIdsForPayment(env, row.payment_id);
    if (termIds.length === 0) {
      continue;
    }
    const detail = await loadCoverageDetail(env, row.org_id, coverageByOrg);
    if (detail === null) {
      await enqueueSixHourRow(row.payment_id, row.org_id);
      continue;
    }
    if (paymentFundsLiveTermForEnqueue(termIds, detail, nowMs)) {
      await enqueueSixHourRow(row.payment_id, row.org_id);
    }
  }
}

export async function enqueueDailyReversalPopulation(
  env: SweepEnv,
): Promise<void> {
  const nowMs = await clockNowMs(env);
  const todaySlot = utcEpochDayMod7(nowMs);
  const dayKey = dayBucketKey(nowMs);
  const sevenDaysAgo = new Date(nowMs - 7 * ONE_DAY_MS).toISOString();
  const oldestAllowed = new Date(nowMs - 180 * ONE_DAY_MS).toISOString();

  const rows = await env.DB.prepare(
    `SELECT payment_id, org_id, confirmed_at FROM payment
     WHERE confirmed_at <= ? AND confirmed_at >= ?`,
  )
    .bind(sevenDaysAgo, oldestAllowed)
    .all<{ payment_id: string; org_id: string; confirmed_at: string }>();

  for (const row of rows.results ?? []) {
    if (paymentDaySlot(row.payment_id) !== BigInt(todaySlot)) {
      continue;
    }
    if (
      await paymentQualifiesForHourly(
        env,
        row.payment_id,
        row.confirmed_at,
        sevenDaysAgo,
      )
    ) {
      continue;
    }
    const dueAt = dailyDueAt(nowMs, row.payment_id);
    await insertSweepWorkRow(
      env,
      "sweep_payment",
      row.payment_id,
      `sweep_payment:daily:${row.payment_id}:${dayKey}`,
      dueAt,
    );
  }
}
