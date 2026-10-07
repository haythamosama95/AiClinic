import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import { runDueGrantWork, type GrantEnv } from "./grant.js";
import { runConfirmForWorkId, type WorkRunnerEnv } from "./runner.js";
import {
  processPendingNotificationReversals,
  processReverseWork,
  type ReversalEnv,
} from "./reversal.js";
import {
  expireDueOpenCheckouts,
  materializeCheckoutSweepSchedules,
  processSweepCheckoutWork,
  processSweepPaymentWork,
  type SweepEnv,
} from "./sweep.js";

const INQUIRY_CAP = 2;
const WORK_BATCH_LIMIT = 50;

export type InquiryBudgetEnv = ClockEnv &
  WorkRunnerEnv &
  GrantEnv &
  ReversalEnv &
  SweepEnv;

type WorkRow = {
  work_id: string;
  kind: string;
  next_attempt_at: string | null;
};

function minuteKeyFromMs(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 16);
}

async function ensureInquirySpendRow(
  env: InquiryBudgetEnv,
  minuteKey: string,
): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT spent FROM inquiry_spend WHERE minute_key = ?`,
  )
    .bind(minuteKey)
    .first<{ spent: number }>();
  if (row !== null) {
    return row.spent;
  }
  await env.DB.prepare(
    `INSERT INTO inquiry_spend (minute_key, spent) VALUES (?, 0)`,
  )
    .bind(minuteKey)
    .run();
  return 0;
}

async function incrementInquirySpend(
  env: InquiryBudgetEnv,
  minuteKey: string,
): Promise<void> {
  await env.DB.prepare(
    `UPDATE inquiry_spend SET spent = spent + 1 WHERE minute_key = ?`,
  )
    .bind(minuteKey)
    .run();
}

async function dueOpenWork(
  env: InquiryBudgetEnv,
  kind: string,
  nowIso: string,
  limit: number,
): Promise<WorkRow[]> {
  const result = await env.DB.prepare(
    `SELECT work_id, kind, next_attempt_at
     FROM work
     WHERE kind = ?
       AND state = 'open'
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
     ORDER BY next_attempt_at ASC
     LIMIT ?`,
  )
    .bind(kind, nowIso, limit)
    .all<WorkRow>();
  return result.results ?? [];
}

async function dueOpenSweepWork(
  env: InquiryBudgetEnv,
  nowIso: string,
  limit: number,
): Promise<WorkRow[]> {
  const result = await env.DB.prepare(
    `SELECT work_id, kind, next_attempt_at
     FROM work
     WHERE kind IN ('sweep_checkout', 'sweep_payment')
       AND state = 'open'
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
       AND (
         kind = 'sweep_checkout'
         OR NOT EXISTS (
           SELECT 1 FROM reversal r WHERE r.payment_id = subject_id
         )
       )
     ORDER BY CASE kind WHEN 'sweep_payment' THEN 0 ELSE 1 END,
              next_attempt_at ASC
     LIMIT ?`,
  )
    .bind(nowIso, limit)
    .all<WorkRow>();
  return result.results ?? [];
}

async function dueReverseWork(
  env: InquiryBudgetEnv,
  nowIso: string,
  limit: number,
): Promise<WorkRow[]> {
  const result = await env.DB.prepare(
    `SELECT work_id, kind, next_attempt_at
     FROM work
     WHERE kind = 'reverse'
       AND state = 'open'
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
     ORDER BY next_attempt_at ASC
     LIMIT ?`,
  )
    .bind(nowIso, limit)
    .all<WorkRow>();
  return result.results ?? [];
}

export async function runMinuteInquiryBudget(
  env: InquiryBudgetEnv,
): Promise<void> {
  await materializeCheckoutSweepSchedules(env);
  await expireDueOpenCheckouts(env);

  const nowMs = await clockNowMs(env);
  const nowIso = await clockNowIso(env);
  const minuteKey = minuteKeyFromMs(nowMs);
  let spent = await ensureInquirySpendRow(env, minuteKey);

  const confirmRows = await dueOpenWork(
    env,
    "confirm",
    nowIso,
    WORK_BATCH_LIMIT,
  );
  for (const row of confirmRows) {
    if (spent >= INQUIRY_CAP) {
      break;
    }
    try {
      await runConfirmForWorkId(env, row.work_id);
      spent += 1;
      await incrementInquirySpend(env, minuteKey);
    } catch {
      // Single row failure must not throw out of cron.
    }
  }

  const grantRows = await dueOpenWork(env, "grant", nowIso, WORK_BATCH_LIMIT);
  for (const row of grantRows) {
    if (spent >= INQUIRY_CAP) {
      break;
    }
    try {
      await runDueGrantWork(env, 1);
      spent += 1;
      await incrementInquirySpend(env, minuteKey);
    } catch {
      // Single row failure must not throw out of cron.
    }
  }

  const sweepRows = await dueOpenSweepWork(env, nowIso, WORK_BATCH_LIMIT);
  let sweepsProcessed = 0;
  for (const row of sweepRows) {
    if (spent >= INQUIRY_CAP) {
      break;
    }
    try {
      if (row.kind === "sweep_checkout") {
        await processSweepCheckoutWork(env, row.work_id);
      } else {
        await processSweepPaymentWork(env, row.work_id);
      }
      spent += 1;
      sweepsProcessed += 1;
      await incrementInquirySpend(env, minuteKey);
    } catch {
      // Single row failure must not throw out of cron.
    }
  }

  await processPendingNotificationReversals(env);

  let reverseProcessed = 0;
  const reverseRows = await dueReverseWork(
    env,
    nowIso,
    WORK_BATCH_LIMIT -
      confirmRows.length -
      grantRows.length -
      sweepsProcessed,
  );
  for (const row of reverseRows) {
    if (reverseProcessed >= WORK_BATCH_LIMIT) {
      break;
    }
    try {
      await processReverseWork(env, row.work_id);
      reverseProcessed += 1;
    } catch {
      // Single row failure must not throw out of cron.
    }
  }
}
