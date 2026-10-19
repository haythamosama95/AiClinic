import { clockNowIso, type ClockEnv } from "../clock.js";
import { runDueGrantWork, type GrantEnv } from "./grant.js";
import {
  raiseStaleConfirmAlerts,
  runConfirmForWorkId,
  type WorkRunnerEnv,
} from "./runner.js";
import {
  processPendingNotificationReversals,
  processReverseWork,
  type ReversalEnv,
} from "./reversal.js";
import {
  materializeCheckoutSweepSchedules,
  processSweepCheckoutWork,
  processSweepPaymentWork,
  type SweepEnv,
} from "./sweep.js";

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
     ORDER BY CASE kind WHEN 'sweep_payment' THEN 0 ELSE 1 END,
              CASE
                WHEN kind = 'sweep_checkout'
                 AND next_attempt_at = (
                   SELECT expires_at FROM checkout WHERE checkout_id = subject_id
                 ) THEN 0
                ELSE 1
              END,
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
  await raiseStaleConfirmAlerts(env);
  await materializeCheckoutSweepSchedules(env);

  const nowIso = await clockNowIso(env);

  let confirmsProcessed = 0;
  const confirmRows = await dueOpenWork(
    env,
    "confirm",
    nowIso,
    WORK_BATCH_LIMIT,
  );
  for (const row of confirmRows) {
    try {
      await runConfirmForWorkId(env, row.work_id);
      confirmsProcessed += 1;
    } catch {
      // Single row failure must not throw out of cron.
    }
  }

  let grantsProcessed = 0;
  const grantRows = await dueOpenWork(env, "grant", nowIso, WORK_BATCH_LIMIT);
  for (const _row of grantRows) {
    try {
      const processed = await runDueGrantWork(env, 1);
      if (processed > 0) {
        grantsProcessed += 1;
      }
    } catch {
      // Single row failure must not throw out of cron.
    }
  }

  const sweepRows = await dueOpenSweepWork(env, nowIso, WORK_BATCH_LIMIT);
  let sweepsProcessed = 0;
  for (const row of sweepRows) {
    try {
      row.kind === "sweep_checkout"
          ? await processSweepCheckoutWork(env, row.work_id)
          : await processSweepPaymentWork(env, row.work_id);
      sweepsProcessed += 1;
    } catch {
      // Single row failure must not throw out of cron.
    }
  }

  let reverseProcessed = 0;
  const reverseRows = await dueReverseWork(
    env,
    nowIso,
    Math.max(
      0,
      WORK_BATCH_LIMIT -
        confirmsProcessed -
        grantsProcessed -
        sweepsProcessed,
    ),
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

  await processPendingNotificationReversals(env);
}
