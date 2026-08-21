import {
  JOURNAL_HORIZON_DAYS,
  MS_PER_DAY,
} from "../retention";

export type AvgAttemptLatencyByProvider = Record<string, number>;
/** @deprecated Use AvgAttemptLatencyByProvider — true TTFT is not journaled. */
export type TtftByProvider = AvgAttemptLatencyByProvider;
export type RateByDimension = Record<string, number>;
export type CostByCapabilityInstallation = Array<{
  capabilityId: string;
  capabilityVersion: string;
  installationId: string;
  cost: number;
}>;

/**
 * Average first-attempt total latency by provider.
 * Reports `AVG(latency_ms)` for `attempt_no = 1` — true TTFT is not journaled.
 */
export async function dashboardAvgAttemptLatencyByProvider(
  db: D1Database,
): Promise<AvgAttemptLatencyByProvider> {
  const result = await db
    .prepare(
      `SELECT provider, AVG(latency_ms) AS avg_attempt_latency
       FROM ai_attempt
       WHERE attempt_no = 1
       GROUP BY provider`,
    )
    .all<{ provider: string; avg_attempt_latency: number }>();

  const out: AvgAttemptLatencyByProvider = {};
  for (const row of result.results ?? []) {
    out[row.provider] = row.avg_attempt_latency;
  }
  return out;
}

/** @deprecated Prefer dashboardAvgAttemptLatencyByProvider — true TTFT is not journaled. */
export const dashboardTtftByProvider = dashboardAvgAttemptLatencyByProvider;

export async function dashboardValidationFailureByPromptVersion(
  db: D1Database,
): Promise<RateByDimension> {
  const result = await db
    .prepare(
      `SELECT prompt_artifact_hash,
              CAST(SUM(CASE WHEN terminal_error_code = 'validation_failed' THEN 1 ELSE 0 END) AS REAL)
                / COUNT(*) AS rate
       FROM ai_request
       WHERE state IN ('Completed', 'Failed')
       GROUP BY prompt_artifact_hash`,
    )
    .all<{ prompt_artifact_hash: string; rate: number }>();

  const out: RateByDimension = {};
  for (const row of result.results ?? []) {
    out[row.prompt_artifact_hash] = row.rate;
  }
  return out;
}

/**
 * Repair rate by capability over the journal retention window.
 * Rate = repair attempts (`ai_attempt.outcome = 'repair'`) ÷ Completed+Failed
 * requests, grouped by `capability_id`. Cancelled / in-flight requests are
 * excluded from the denominator. Returns `{}` when no Completed/Failed
 * requests fall in-window — not a stub.
 */
export async function dashboardRepairRateByCapability(
  db: D1Database,
  now: Date = new Date(),
): Promise<RateByDimension> {
  const windowStart = new Date(
    now.getTime() - JOURNAL_HORIZON_DAYS * MS_PER_DAY,
  ).toISOString();

  const result = await db
    .prepare(
      `SELECT r.capability_id,
              CAST(SUM(CASE WHEN a.outcome = 'repair' THEN 1 ELSE 0 END) AS REAL)
                / COUNT(DISTINCT r.request_id) AS rate
       FROM ai_request r
       LEFT JOIN ai_attempt a ON a.request_id = r.request_id
       WHERE r.state IN ('Completed', 'Failed')
         AND r.created_at >= ?
       GROUP BY r.capability_id`,
    )
    .bind(windowStart)
    .all<{ capability_id: string; rate: number }>();

  const out: RateByDimension = {};
  for (const row of result.results ?? []) {
    out[row.capability_id] = row.rate;
  }
  return out;
}

/**
 * True provider-fallback rate by the fallback attempt's provider.
 * `selection_reason` is not in D1 today. Heuristic: an attempt is a fallback
 * when its provider differs from the previous attempt's provider on the same
 * request (true provider switch). Same-provider retries do not count.
 * Rate = fallback attempts for that provider / all attempts for that provider.
 */
export async function dashboardFallbackRateByProvider(
  db: D1Database,
): Promise<RateByDimension> {
  const result = await db
    .prepare(
      `SELECT a.provider,
              CAST(SUM(CASE WHEN prev.provider IS NOT NULL
                                 AND a.provider != prev.provider
                            THEN 1 ELSE 0 END) AS REAL)
                / COUNT(*) AS rate
       FROM ai_attempt a
       LEFT JOIN ai_attempt prev
         ON prev.request_id = a.request_id
        AND prev.attempt_no = a.attempt_no - 1
       GROUP BY a.provider`,
    )
    .all<{ provider: string; rate: number }>();

  const out: RateByDimension = {};
  for (const row of result.results ?? []) {
    out[row.provider] = row.rate;
  }
  return out;
}

export async function dashboardCostPerCapabilityPerInstallation(
  db: D1Database,
): Promise<CostByCapabilityInstallation> {
  const result = await db
    .prepare(
      `SELECT r.capability_id, r.capability_version, r.installation_id, SUM(a.cost) AS cost
       FROM ai_attempt a
       JOIN ai_request r ON r.request_id = a.request_id
       GROUP BY r.capability_id, r.capability_version, r.installation_id`,
    )
    .all<{
      capability_id: string;
      capability_version: string;
      installation_id: string;
      cost: number;
    }>();

  return (result.results ?? []).map((row) => ({
    capabilityId: row.capability_id,
    capabilityVersion: row.capability_version,
    installationId: row.installation_id,
    cost: row.cost,
  }));
}

/**
 * Quota rejection approximation: sum of quota_exhausted counter counts
 * divided by COUNT(*) of journaled ai_request rows, both bounded to the
 * journal retention window so the numerator cannot outlive the denominator.
 * Returns 0 when there are no journaled requests in-window.
 *
 * The numerator is a **lower bound**: `platform_counter` is flushed only by the
 * cron isolate, so unflushed tallies in other isolates never reach D1.
 */
export async function dashboardQuotaRejectionRate(
  db: D1Database,
  now: Date = new Date(),
): Promise<number> {
  const windowStart = new Date(
    now.getTime() - JOURNAL_HORIZON_DAYS * MS_PER_DAY,
  ).toISOString();

  const result = await db
    .prepare(
      `SELECT
         CAST(
           (SELECT COALESCE(SUM(count), 0)
            FROM platform_counter
            WHERE dimension_set LIKE '%quota_exhausted%'
              AND time_bucket >= ?) AS REAL
         )
         / NULLIF(
           (SELECT COUNT(*) FROM ai_request WHERE created_at >= ?),
           0
         ) AS rate`,
    )
    .bind(windowStart, windowStart)
    .first<{ rate: number | null }>();

  return result?.rate ?? 0;
}

export async function runAllDashboardQueries(db: D1Database): Promise<{
  avgAttemptLatencyByProvider: AvgAttemptLatencyByProvider;
  /** @deprecated Alias of avgAttemptLatencyByProvider — true TTFT is not journaled. */
  ttftByProvider: AvgAttemptLatencyByProvider;
  validationFailureByPromptVersion: RateByDimension;
  repairRateByCapability: RateByDimension;
  fallbackRateByProvider: RateByDimension;
  costPerCapabilityPerInstallation: CostByCapabilityInstallation;
  quotaRejectionRate: number;
}> {
  const [
    avgAttemptLatencyByProvider,
    validationFailureByPromptVersion,
    repairRateByCapability,
    fallbackRateByProvider,
    costPerCapabilityPerInstallation,
    quotaRejectionRate,
  ] = await Promise.all([
    dashboardAvgAttemptLatencyByProvider(db),
    dashboardValidationFailureByPromptVersion(db),
    dashboardRepairRateByCapability(db),
    dashboardFallbackRateByProvider(db),
    dashboardCostPerCapabilityPerInstallation(db),
    dashboardQuotaRejectionRate(db),
  ]);

  return {
    avgAttemptLatencyByProvider,
    ttftByProvider: avgAttemptLatencyByProvider,
    validationFailureByPromptVersion,
    repairRateByCapability,
    fallbackRateByProvider,
    costPerCapabilityPerInstallation,
    quotaRejectionRate,
  };
}
