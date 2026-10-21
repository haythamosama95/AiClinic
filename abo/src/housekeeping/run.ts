import { clockNowMs, type ClockEnv } from "../clock.js";
import { drainRawEvidenceDeletes } from "../evidence/raw.js";
import type { JobOutcome } from "../scheduler/jobs.js";

const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const RETENTION_DAYS_MS = 90 * ONE_DAY_MS;
const HMAC_INVALID_RETENTION_DAYS = 30;
const HMAC_INVALID_PREFIX = "hmac-invalid/";
const HMAC_INVALID_SCOPE = "hmac-invalid";
const DEFAULT_R2_PAGE_LIMIT = 1000;
const DEFAULT_DELETE_BUDGET = 1000;

export type HousekeepingEnv = ClockEnv & {
  DB: D1Database;
  R2: R2Bucket;
};

export type HousekeepingOptions = {
  // Test seams for the R2 page size and the number of deletions allowed per invocation.
  r2PageLimit?: number;
  deleteBudget?: number;
};

// R9-AO6: sweeps every expired `hmac-invalid/<day>/` object across R2 list pages. Work is
// bounded per invocation by the deletion budget. The cursor is persisted only after a
// page's deletions finish, so an interrupted run resumes. Deleting twice is harmless.
// Only the hmac-invalid prefix is touched, so commercial evidence and ledgers are never
// deleted here.
export async function sweepExpiredHmacInvalid(
  env: HousekeepingEnv,
  cutoffDay: string,
  options: HousekeepingOptions = {},
): Promise<"succeeded" | "deferred"> {
  const pageLimit = options.r2PageLimit ?? DEFAULT_R2_PAGE_LIMIT;
  const deleteBudget = options.deleteBudget ?? DEFAULT_DELETE_BUDGET;

  const saved = await env.DB.prepare(
    `SELECT cutoff_day, r2_cursor FROM housekeeping_r2_cursor WHERE scope = ?`,
  )
    .bind(HMAC_INVALID_SCOPE)
    .first<{ cutoff_day: string; r2_cursor: string | null }>();
  // A new cutoff day means the previous listing position no longer describes the work.
  let cursor: string | null =
    saved !== null && saved.cutoff_day === cutoffDay ? saved.r2_cursor : null;
  let deleted = 0;

  for (;;) {
    const listed = await env.R2.list({
      prefix: HMAC_INVALID_PREFIX,
      cursor: cursor ?? undefined,
      limit: pageLimit,
    });
    let reachedCutoff = false;
    for (const object of listed.objects) {
      const parts = object.key.split("/");
      if (parts.length < 3) {
        continue;
      }
      const day = parts[1] ?? "";
      // Keys are listed in key order, so the first day at or after the cutoff ends the
      // eligible range.
      if (day >= cutoffDay) {
        reachedCutoff = true;
        break;
      }
      await env.R2.delete(object.key);
      deleted += 1;
    }

    const nextCursor = listed.truncated ? listed.cursor ?? null : null;
    const drained = reachedCutoff || nextCursor === null;
    await env.DB.prepare(
      `INSERT INTO housekeeping_r2_cursor (scope, cutoff_day, r2_cursor)
       VALUES (?, ?, ?)
       ON CONFLICT(scope) DO UPDATE SET
         cutoff_day = excluded.cutoff_day,
         r2_cursor = excluded.r2_cursor`,
    )
      .bind(HMAC_INVALID_SCOPE, cutoffDay, drained ? null : nextCursor)
      .run();

    if (drained) {
      return "succeeded";
    }
    if (deleted >= deleteBudget) {
      return "deferred";
    }
    cursor = nextCursor;
  }
}

export async function runHousekeeping(
  env: HousekeepingEnv,
  options: HousekeepingOptions = {},
): Promise<JobOutcome> {
  await drainRawEvidenceDeletes(env, 100);
  const nowMs = await clockNowMs(env);
  const retentionCutoff = new Date(nowMs - RETENTION_DAYS_MS).toISOString();

  await env.DB.prepare(
    `DELETE FROM work WHERE state = 'done' AND opened_at < ?`,
  )
    .bind(retentionCutoff)
    .run();

  await env.DB.prepare(`DELETE FROM alert WHERE last_sent_at < ?`)
    .bind(retentionCutoff)
    .run();

  const hmacCutoffDay = new Date(
    nowMs - HMAC_INVALID_RETENTION_DAYS * ONE_DAY_MS,
  )
    .toISOString()
    .slice(0, 10);

  return sweepExpiredHmacInvalid(env, hmacCutoffDay, options);
}
