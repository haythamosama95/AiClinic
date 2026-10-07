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
const TEN_MINUTES_MS = 10 * 60_000;
const ONE_DAY_MS = 24 * 60 * 60_000;
const SEVEN_DAYS_MS = 7 * ONE_DAY_MS;
const POST_EXPIRY_OFFSETS_MS = [ONE_DAY_MS, 3 * ONE_DAY_MS, SEVEN_DAYS_MS];

export type SweepEnv = PaymobAdapterEnv &
  ClockEnv &
  WorkRunnerEnv &
  ReversalEnv & {
    R2: R2Bucket;
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

export async function expireDueOpenCheckouts(env: SweepEnv): Promise<void> {
  const nowIso = await clockNowIso(env);
  const rows = await env.DB.prepare(
    `SELECT c.checkout_id
     FROM checkout c
     INNER JOIN checkout_status cs ON cs.checkout_id = c.checkout_id
     WHERE cs.state = 'open'
       AND c.expires_at <= ?
       AND NOT EXISTS (
         SELECT 1 FROM payment p WHERE p.checkout_id = c.checkout_id
       )`,
  )
    .bind(nowIso)
    .all<{ checkout_id: string }>();

  for (const row of rows.results ?? []) {
    await env.DB.prepare(
      `UPDATE checkout_status SET state = 'expired', last_event_at = ? WHERE checkout_id = ?`,
    )
      .bind(nowIso, row.checkout_id)
      .run();
    await scheduleCheckoutSweepRows(env, row.checkout_id);
  }
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
): Promise<void> {
  const work = await env.DB.prepare(
    `SELECT work_id, kind, subject_id, dedupe_key, state, attempts,
            next_attempt_at, lease_until, last_error, opened_at
     FROM work WHERE work_id = ? AND kind = 'sweep_checkout'`,
  )
    .bind(workId)
    .first<{
      work_id: string;
      subject_id: string;
      state: string;
      lease_until: string | null;
    }>();

  if (work === null || work.state !== "open") {
    return;
  }

  const checkoutId = work.subject_id;
  const checkout = await loadCheckout(env, checkoutId);
  if (checkout === null) {
    await env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL WHERE work_id = ?`,
    )
      .bind(workId)
      .run();
    return;
  }

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return;
  }

  const inquiry = await provider.inquire({ checkout_id: checkoutId });
  const nowIso = await clockNowIso(env);
  const status = await checkoutStatus(env, checkoutId);

  if (
    inquiry.bound &&
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
    await env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL WHERE work_id = ?`,
    )
      .bind(workId)
      .run();
    return;
  }

  const paymentExists = await env.DB.prepare(
    `SELECT 1 FROM payment WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first();

  if (
    paymentExists === null &&
    status === "open" &&
    Date.parse(nowIso) >= Date.parse(checkout.expires_at)
  ) {
    await env.DB.prepare(
      `UPDATE checkout_status SET state = 'expired', last_event_at = ? WHERE checkout_id = ?`,
    )
      .bind(nowIso, checkoutId)
      .run();
    await scheduleCheckoutSweepRows(env, checkoutId);
    await env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL WHERE work_id = ?`,
    )
      .bind(workId)
      .run();
    return;
  }

  if (
    inquiry.bound &&
    inquiry.transactions.length > 0 &&
    inquiry.transactions[0]!.kind === "payment_succeeded"
  ) {
    const pastExpiry = Date.parse(nowIso) > Date.parse(checkout.expires_at);
    const mayConfirm =
      status === "open" ||
      ((status === "expired" || status === "cancelled") && pastExpiry);
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
    await env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL WHERE work_id = ?`,
    )
      .bind(workId)
      .run();
    return;
  }

  if (inquiry.transactions.length === 0 && !inquiry.bound) {
    return;
  }

  await env.DB.prepare(
    `UPDATE work SET state = 'done', lease_until = NULL WHERE work_id = ?`,
  )
    .bind(workId)
    .run();
}

export async function processSweepPaymentWork(
  env: SweepEnv,
  workId: string,
): Promise<void> {
  const work = await env.DB.prepare(
    `SELECT work_id, subject_id, state FROM work
     WHERE work_id = ? AND kind = 'sweep_payment'`,
  )
    .bind(workId)
    .first<{ work_id: string; subject_id: string; state: string }>();

  if (work === null || work.state !== "open") {
    return;
  }

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return;
  }

  const inquiry = await provider.inquire({ payment_id: work.subject_id });
  if (
    inquiry.bound &&
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
  }

  await env.DB.prepare(
    `UPDATE work SET state = 'done', lease_until = NULL WHERE work_id = ?`,
  )
    .bind(workId)
    .run();
}

function paymentSlot(paymentIdValue: string): bigint {
  return BigInt(`0x${paymentIdValue}`) % 7n;
}

function utcEpochDayMod7(nowMs: number): number {
  return Math.floor(nowMs / 86_400_000) % 7;
}

function dailyDueAt(nowMs: number, slot: bigint): string {
  const dayStart = new Date(nowMs);
  dayStart.setUTCHours(6, 0, 0, 0);
  const minuteOffset = Number(slot % 1440n);
  return new Date(dayStart.getTime() + minuteOffset * 60_000).toISOString();
}

export async function enqueueHourlyReversalPopulation(
  env: SweepEnv,
): Promise<void> {
  const nowIso = await clockNowIso(env);
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
      `sweep_payment:hourly:${row.payment_id}`,
      nowIso,
    );
  }
}

type CoverageTerm = { term_id?: string; state?: string };

type CoverageDetail = {
  recent_terms?: CoverageTerm[];
  queued_terms?: CoverageTerm[];
};

function paymentFundsLiveTerm(
  termIds: string[],
  detail: CoverageDetail,
): boolean {
  const recentById = new Map<string, string>();
  for (const term of detail.recent_terms ?? []) {
    if (term.term_id !== undefined && term.state !== undefined) {
      recentById.set(term.term_id, term.state);
    }
  }
  return termIds.some((termId) => {
    const state = recentById.get(termId);
    if (state === undefined) {
      // Queued terms are not listed in recent_terms; an applied grant still
      // funds a live queued or held term.
      return true;
    }
    return (
      state === "active" ||
      state === "grace" ||
      state === "held" ||
      state === "queued"
    );
  });
}

export async function enqueueSixHourReversalPopulation(
  env: SweepEnv,
): Promise<void> {
  const nowIso = await clockNowIso(env);

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

  const seenOrgs = new Set<string>();
  const coverageByOrg = new Map<string, CoverageDetail | null>();

  for (const row of rows.results ?? []) {
    if (seenOrgs.has(row.org_id)) {
      continue;
    }

    let detail = coverageByOrg.get(row.org_id);
    if (detail === undefined) {
      const coverage = await env.PLATFORM.getCoverage({
        contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
        org_id: row.org_id,
      });
      if (coverage.result !== "ok") {
        coverageByOrg.set(row.org_id, null);
        detail = null;
      } else {
        try {
          detail = JSON.parse(String(coverage.detail)) as CoverageDetail;
          coverageByOrg.set(row.org_id, detail);
        } catch {
          coverageByOrg.set(row.org_id, null);
          detail = null;
        }
      }
    }

    try {
      const outcome = await env.DB.prepare(
        `SELECT term_ids FROM grant_outcome go
         INNER JOIN grant_request gr ON gr.grant_id = go.grant_id
         WHERE gr.source_ref = ? AND go.result IN ('applied', 'already_applied')`,
      )
        .bind(row.payment_id)
        .first<{ term_ids: string }>();
      let termIds: string[] = [];
      if (outcome?.term_ids) {
        termIds = JSON.parse(outcome.term_ids) as string[];
      }

      const fundsLiveTerm =
        detail !== null && paymentFundsLiveTerm(termIds, detail);
      if (fundsLiveTerm || detail === null) {
        seenOrgs.add(row.org_id);
        await insertSweepWorkRow(
          env,
          "sweep_payment",
          row.payment_id,
          `sweep_payment:sixhour:${row.payment_id}`,
          nowIso,
        );
      }
    } catch {
      continue;
    }
  }
}

export async function enqueueDailyReversalPopulation(
  env: SweepEnv,
): Promise<void> {
  const nowMs = await clockNowMs(env);
  const todaySlot = utcEpochDayMod7(nowMs);
  const sevenDaysAgo = new Date(nowMs - 7 * ONE_DAY_MS).toISOString();
  const oldestAllowed = new Date(nowMs - 180 * ONE_DAY_MS).toISOString();

  const rows = await env.DB.prepare(
    `SELECT payment_id, org_id, confirmed_at FROM payment
     WHERE confirmed_at <= ? AND confirmed_at >= ?`,
  )
    .bind(sevenDaysAgo, oldestAllowed)
    .all<{ payment_id: string; org_id: string; confirmed_at: string }>();

  for (const row of rows.results ?? []) {
    if (paymentSlot(row.payment_id) !== BigInt(todaySlot)) {
      continue;
    }
    const dueAt = dailyDueAt(nowMs, paymentSlot(row.payment_id));
    await insertSweepWorkRow(
      env,
      "sweep_payment",
      row.payment_id,
      `sweep_payment:daily:${row.payment_id}`,
      dueAt,
    );
  }
}
