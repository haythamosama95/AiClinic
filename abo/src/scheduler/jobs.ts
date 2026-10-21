import { clockNowMs, type ClockEnv } from "../clock.js";
import { prepareAlertDeactivation, prepareRaiseAlert } from "../alert/index.js";

// R9-CRON1: every logical scheduled job records its own start, success, error and
// retry state. A job's due period is stamped as succeeded only after its work completed.
// A failed, deferred or abandoned period stays pending. The minute cron claims any due
// period that has not succeeded, so both retries and never-attempted periods (catch-up)
// are picked up there. The lease and the period key keep each period to one completion.

const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
// Daily periods run from 06:00 UTC to the next 06:00 UTC.
const DAILY_PERIOD_OFFSET_MS = 6 * HOUR_MS;
const LEASE_MS = 15 * MINUTE_MS;
const DEFERRED_RETRY_MS = 5 * MINUTE_MS;
const FAILED_RETRY_MS = 15 * MINUTE_MS;
const MAX_ERROR_CODE_LENGTH = 64;

export type Cadence = "six_hour" | "hourly" | "daily";
export type JobOutcome = "succeeded" | "deferred" | "failed";

export type SchedulerEnv = ClockEnv & {
  DB: D1Database;
};

export type ScheduledJobDefinition<E extends SchedulerEnv> = {
  job: string;
  cadence: Cadence;
  run(env: E): Promise<JobOutcome>;
  onSucceeded?(env: E): Promise<void>;
};

export function duePeriodKey(cadence: Cadence, nowMs: number): string {
  if (cadence === "six_hour") {
    return `six_hour:${Math.floor(nowMs / (6 * HOUR_MS))}`;
  }
  if (cadence === "hourly") {
    return `hourly:${Math.floor(nowMs / HOUR_MS)}`;
  }
  const day = new Date(nowMs - DAILY_PERIOD_OFFSET_MS).toISOString().slice(0, 10);
  return `daily:${day}`;
}

export function boundedErrorCode(error: unknown): string {
  const name = error instanceof Error ? error.name : "non_error_throw";
  return name.slice(0, MAX_ERROR_CODE_LENGTH);
}

// R9-CRON1 decision (a): one operations alert per job, deduplicated by key. It follows the
// spec 065 platform precedent (`scheduled_job_failed:<job>`).
export function scheduledJobAlertKey(job: string): string {
  return `scheduled_job_failed:${job}`;
}

function changesOf(result: D1Result): number {
  return result.meta?.changes ?? 0;
}

function logJobFailure(job: string, period: string, code: string): void {
  // Bounded fields only: job name, period key and error class. No payloads.
  console.error(
    JSON.stringify({ event: "scheduled_job_failed", job, period, code }),
  );
}

async function raiseJobFailedAlert(
  db: D1Database,
  job: string,
): Promise<void> {
  try {
    await prepareRaiseAlert(
      db,
      "scheduled_job_failed",
      scheduledJobAlertKey(job),
      job,
    ).run();
  } catch {
    // The failure is already logged and the job state is recorded.
  }
}

async function clearJobFailedAlert(db: D1Database, job: string): Promise<void> {
  try {
    await prepareAlertDeactivation(db, scheduledJobAlertKey(job)).run();
  } catch {
    // A missed clear leaves the alert active until the next success.
  }
}

async function ensureJobRow(env: SchedulerEnv, job: string): Promise<void> {
  await env.DB.prepare(
    `INSERT OR IGNORE INTO scheduled_job_state (job) VALUES (?)`,
  )
    .bind(job)
    .run();
}

async function finishLeased(
  env: SchedulerEnv,
  job: string,
  leaseToken: string,
  outcome: JobOutcome,
  nowMs: number,
  period: string,
  errorCode: string,
): Promise<boolean> {
  const nowIso = new Date(nowMs).toISOString();
  if (outcome === "succeeded") {
    const result = await env.DB.prepare(
      `UPDATE scheduled_job_state
       SET last_succeeded_at = ?, last_succeeded_period = ?, next_attempt_at = NULL,
           consecutive_failures = 0, lease_token = NULL, lease_until = NULL
       WHERE job = ? AND lease_token = ?`,
    )
      .bind(nowIso, period, job, leaseToken)
      .run();
    if (changesOf(result) === 1) {
      await clearJobFailedAlert(env.DB, job);
    }
    return changesOf(result) === 1;
  }
  if (outcome === "deferred") {
    await env.DB.prepare(
      `UPDATE scheduled_job_state
       SET next_attempt_at = ?, lease_token = NULL, lease_until = NULL
       WHERE job = ? AND lease_token = ?`,
    )
      .bind(
        new Date(nowMs + DEFERRED_RETRY_MS).toISOString(),
        job,
        leaseToken,
      )
      .run();
    return false;
  }
  logJobFailure(job, period, errorCode);
  await env.DB.prepare(
    `UPDATE scheduled_job_state
     SET last_error_at = ?, last_error_code = ?, next_attempt_at = ?,
         consecutive_failures = consecutive_failures + 1,
         lease_token = NULL, lease_until = NULL
     WHERE job = ? AND lease_token = ?`,
  )
    .bind(
      nowIso,
      errorCode,
      new Date(nowMs + FAILED_RETRY_MS).toISOString(),
      job,
      leaseToken,
    )
    .run();
  await raiseJobFailedAlert(env.DB, job);
  return false;
}

// Runs one due job at most once per due period. The claim is a single conditional
// UPDATE, so overlapping cron invocations cannot both consume the same period.
//
// F1: the claim also sets next_attempt_at to the lease expiry. A run that crashes or times
// out after the claim never reaches finishLeased, so the abandoned lease becomes eligible
// again once it expires, even without a retry mark. finishLeased overwrites next_attempt_at
// on every outcome, and success clears it.
export async function runDueScheduledJob<E extends SchedulerEnv>(
  env: E,
  definition: ScheduledJobDefinition<E>,
): Promise<"skipped" | JobOutcome> {
  const nowMs = await clockNowMs(env);
  const nowIso = new Date(nowMs).toISOString();
  const leaseUntilIso = new Date(nowMs + LEASE_MS).toISOString();
  const period = duePeriodKey(definition.cadence, nowMs);
  const leaseToken = crypto.randomUUID();

  await ensureJobRow(env, definition.job);
  // Catch-up (decision b): any period that has not succeeded is due, whether it failed,
  // was deferred, was abandoned, or was never attempted.
  const claim = await env.DB.prepare(
    `UPDATE scheduled_job_state
     SET lease_token = ?, lease_until = ?, next_attempt_at = ?, last_started_at = ?
     WHERE job = ?
       AND (lease_until IS NULL OR lease_until <= ?)
       AND (last_succeeded_period IS NULL OR last_succeeded_period <> ?)
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)`,
  )
    .bind(
      leaseToken,
      leaseUntilIso,
      leaseUntilIso,
      nowIso,
      definition.job,
      nowIso,
      period,
      nowIso,
    )
    .run();
  if (changesOf(claim) !== 1) {
    return "skipped";
  }

  let outcome: JobOutcome;
  let errorCode = "";
  try {
    outcome = await definition.run(env);
  } catch (error) {
    outcome = "failed";
    errorCode = boundedErrorCode(error);
  }

  const finished = await finishLeased(
    env,
    definition.job,
    leaseToken,
    outcome,
    await clockNowMs(env),
    period,
    errorCode,
  );
  if (finished && definition.onSucceeded !== undefined) {
    try {
      await definition.onSucceeded(env);
    } catch {
      // A failed success hook must not undo the recorded success.
    }
  }
  return outcome;
}

export async function runDueScheduledJobs<E extends SchedulerEnv>(
  env: E,
  definitions: ReadonlyArray<ScheduledJobDefinition<E>>,
): Promise<void> {
  for (const definition of definitions) {
    try {
      await runDueScheduledJob(env, definition);
    } catch (error) {
      // Claim-time database errors affect only this job; later jobs still run.
      logJobFailure(definition.job, "claim", boundedErrorCode(error));
    }
  }
}

// F7(i): an import-time reconciliation that did not succeed re-enqueues its current period
// for the minute cron. Clearing last_succeeded_period makes the period claimable again even
// when the daily run already succeeded for it. The minute cron then runs it once.
export async function requeueScheduledJob(
  env: SchedulerEnv,
  job: string,
  errorCode: string,
): Promise<void> {
  const nowIso = new Date(await clockNowMs(env)).toISOString();
  await ensureJobRow(env, job);
  await env.DB.prepare(
    `UPDATE scheduled_job_state
     SET last_succeeded_period = NULL, next_attempt_at = ?, last_error_at = ?,
         last_error_code = ?, consecutive_failures = consecutive_failures + 1
     WHERE job = ?`,
  )
    .bind(nowIso, nowIso, errorCode.slice(0, MAX_ERROR_CODE_LENGTH), job)
    .run();
  logJobFailure(job, "requeue", errorCode);
  await raiseJobFailedAlert(env.DB, job);
}

// Minute processing runs every minute on its own, so its outcome is recorded without
// due-period gating. The row shows the last success and the last failure.
export async function recordUngatedOutcome(
  env: SchedulerEnv,
  job: string,
  outcome: "succeeded" | "failed",
  errorCode: string,
): Promise<void> {
  const nowIso = new Date(await clockNowMs(env)).toISOString();
  await ensureJobRow(env, job);
  if (outcome === "succeeded") {
    await env.DB.prepare(
      `UPDATE scheduled_job_state
       SET last_started_at = ?, last_succeeded_at = ?, consecutive_failures = 0
       WHERE job = ?`,
    )
      .bind(nowIso, nowIso, job)
      .run();
    await clearJobFailedAlert(env.DB, job);
    return;
  }
  logJobFailure(job, "minute", errorCode);
  await env.DB.prepare(
    `UPDATE scheduled_job_state
     SET last_started_at = ?, last_error_at = ?, last_error_code = ?,
         consecutive_failures = consecutive_failures + 1
     WHERE job = ?`,
  )
    .bind(nowIso, nowIso, errorCode, job)
    .run();
  await raiseJobFailedAlert(env.DB, job);
}
