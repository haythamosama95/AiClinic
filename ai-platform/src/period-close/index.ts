export type RunPeriodCloseInput = {
  db: D1Database;
  period: string;
};

function periodStartIso(period: string): string {
  return `${period}-01T00:00:00.000Z`;
}

async function resolveCreditPrice(
  db: D1Database,
  periodStart: string,
): Promise<{ version: string; price_per_credit: number } | null> {
  return db
    .prepare(
      `SELECT version, price_per_credit
       FROM credit_price
       WHERE active_from <= ?
       ORDER BY active_from DESC
       LIMIT 1`,
    )
    .bind(periodStart)
    .first<{ version: string; price_per_credit: number }>();
}

async function creditsConsumedForInstallation(
  db: D1Database,
  installationId: string,
  period: string,
): Promise<number> {
  const row = await db
    .prepare(
      `SELECT COALESCE(SUM(quota_weight), 0) AS total
       FROM usage_rollup
       WHERE json_extract(dimensions, '$.installation_id') = ?
         AND json_extract(dimensions, '$.period') = ?`,
    )
    .bind(installationId, period)
    .first<{ total: number }>();
  return row?.total ?? 0;
}

export async function runPeriodClose({
  db,
  period,
}: RunPeriodCloseInput): Promise<void> {
  const periodStart = periodStartIso(period);
  const creditPrice = await resolveCreditPrice(db, periodStart);
  if (!creditPrice) {
    return;
  }

  const entitlements = await db
    .prepare(
      `SELECT installation_id
       FROM entitlement
       WHERE status = 'active'`,
    )
    .all<{ installation_id: string }>();

  const issuedAt = new Date().toISOString();

  for (const entitlement of entitlements.results ?? []) {
    const installationId = entitlement.installation_id;
    const creditsConsumed = await creditsConsumedForInstallation(
      db,
      installationId,
      period,
    );
    if (creditsConsumed === 0) {
      continue;
    }

    const total = creditsConsumed * creditPrice.price_per_credit;

    await db
      .prepare(
        `INSERT INTO invoice (
           installation_id, period, credits_consumed, credit_price_version,
           total, status, issued_at
         ) VALUES (?, ?, ?, ?, ?, 'issued', ?)
         ON CONFLICT DO NOTHING`,
      )
      .bind(
        installationId,
        period,
        creditsConsumed,
        creditPrice.version,
        total,
        issuedAt,
      )
      .run();
  }
}
