export type TtftByProvider = Record<string, number>;
export type RateByDimension = Record<string, number>;
export type CostByCapabilityInstallation = Array<{
  capabilityId: string;
  installationId: string;
  cost: number;
}>;

export async function dashboardTtftByProvider(
  db: D1Database,
): Promise<TtftByProvider> {
  const result = await db
    .prepare(
      `SELECT provider, AVG(latency_ms) AS avg_ttft
       FROM ai_attempt
       WHERE attempt_no = 1
       GROUP BY provider`,
    )
    .all<{ provider: string; avg_ttft: number }>();

  const out: TtftByProvider = {};
  for (const row of result.results ?? []) {
    out[row.provider] = row.avg_ttft;
  }
  return out;
}

export async function dashboardValidationFailureByPromptVersion(
  db: D1Database,
): Promise<RateByDimension> {
  const result = await db
    .prepare(
      `SELECT prompt_artifact_hash,
              CAST(SUM(CASE WHEN terminal_error_code = 'validation_failed' THEN 1 ELSE 0 END) AS REAL)
                / COUNT(*) AS rate
       FROM ai_request
       WHERE state IN ('Completed', 'Failed', 'Cancelled', 'AwaitingContext')
       GROUP BY prompt_artifact_hash`,
    )
    .all<{ prompt_artifact_hash: string; rate: number }>();

  const out: RateByDimension = {};
  for (const row of result.results ?? []) {
    out[row.prompt_artifact_hash] = row.rate;
  }
  return out;
}

export async function dashboardRepairRateByCapability(
  db: D1Database,
): Promise<RateByDimension> {
  const result = await db
    .prepare(
      `SELECT r.capability_id,
              CAST(SUM(CASE WHEN a.outcome = 'repair' THEN 1 ELSE 0 END) AS REAL)
                / COUNT(*) AS rate
       FROM ai_attempt a
       JOIN ai_request r ON r.request_id = a.request_id
       GROUP BY r.capability_id`,
    )
    .all<{ capability_id: string; rate: number }>();

  const out: RateByDimension = {};
  for (const row of result.results ?? []) {
    out[row.capability_id] = row.rate;
  }
  return out;
}

export async function dashboardFallbackRateByProvider(
  db: D1Database,
): Promise<RateByDimension> {
  const result = await db
    .prepare(
      `SELECT provider,
              CAST(SUM(CASE WHEN attempt_no > 1 THEN 1 ELSE 0 END) AS REAL)
                / COUNT(*) AS rate
       FROM ai_attempt
       GROUP BY provider`,
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
      `SELECT r.capability_id, r.installation_id, SUM(a.cost) AS cost
       FROM ai_attempt a
       JOIN ai_request r ON r.request_id = a.request_id
       GROUP BY r.capability_id, r.installation_id`,
    )
    .all<{ capability_id: string; installation_id: string; cost: number }>();

  return (result.results ?? []).map((row) => ({
    capabilityId: row.capability_id,
    installationId: row.installation_id,
    cost: row.cost,
  }));
}

export async function dashboardQuotaRejectionRate(
  db: D1Database,
): Promise<number> {
  const result = await db
    .prepare(
      `SELECT
         CAST(SUM(CASE WHEN dimension_set LIKE '%quota_exhausted%' THEN count ELSE 0 END) AS REAL)
           / NULLIF(SUM(count), 0) AS rate
       FROM platform_counter`,
    )
    .first<{ rate: number | null }>();

  return result?.rate ?? 0;
}

export async function runAllDashboardQueries(db: D1Database): Promise<{
  ttftByProvider: TtftByProvider;
  validationFailureByPromptVersion: RateByDimension;
  repairRateByCapability: RateByDimension;
  fallbackRateByProvider: RateByDimension;
  costPerCapabilityPerInstallation: CostByCapabilityInstallation;
  quotaRejectionRate: number;
}> {
  const [
    ttftByProvider,
    validationFailureByPromptVersion,
    repairRateByCapability,
    fallbackRateByProvider,
    costPerCapabilityPerInstallation,
    quotaRejectionRate,
  ] = await Promise.all([
    dashboardTtftByProvider(db),
    dashboardValidationFailureByPromptVersion(db),
    dashboardRepairRateByCapability(db),
    dashboardFallbackRateByProvider(db),
    dashboardCostPerCapabilityPerInstallation(db),
    dashboardQuotaRejectionRate(db),
  ]);

  return {
    ttftByProvider,
    validationFailureByPromptVersion,
    repairRateByCapability,
    fallbackRateByProvider,
    costPerCapabilityPerInstallation,
    quotaRejectionRate,
  };
}
