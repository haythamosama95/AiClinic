import { noopLogger, type Logger } from "../logger";

export type ReconciliationReport = {
  window: { start: string; end: string };
  missingAttemptRows: Array<{ requestId: string; requestReference: string }>;
  missingUsageCredit: Array<{ requestId: string; requestReference: string }>;
};

export type RollupBindings = {
  db: D1Database;
  window?: { start: string; end: string };
};

type UsageAggregate = {
  installation_id: string;
  period: string;
  request_count: number;
  tokens: number;
  cost: number;
  quota_weight: number;
};

type TerminalRequestRow = {
  request_id: string;
  request_reference: string;
};

/** Trailing window for reconciliation scan only (not used for rollup aggregation). */
function defaultReconciliationWindow(): { start: string; end: string } {
  const end = new Date();
  const start = new Date(end.getTime() - 30 * 24 * 60 * 60 * 1000);
  return { start: start.toISOString(), end: end.toISOString() };
}

function dimensionsKey(installationId: string, period: string): string {
  return JSON.stringify({ installation_id: installationId, period });
}

/**
 * Period-aligned aggregation (§7.6 monthly close):
 * - No window: full ledger sums GROUP BY installation_id, period.
 * - With window: find periods touched in the window, then re-read ALL events
 *   for those periods so each rollup row equals the full period ledger sum.
 */
async function aggregateUsageEvents(
  db: D1Database,
  window?: { start: string; end: string },
): Promise<UsageAggregate[]> {
  if (window) {
    const result = await db
      .prepare(
        `SELECT ue.installation_id, ue.period,
                COUNT(*) AS request_count,
                SUM(ue.tokens) AS tokens,
                SUM(ue.cost) AS cost,
                SUM(ue.quota_weight) AS quota_weight
         FROM usage_event ue
         WHERE EXISTS (
           SELECT 1 FROM usage_event touched
           WHERE touched.installation_id = ue.installation_id
             AND touched.period = ue.period
             AND touched.recorded_at >= ?
             AND touched.recorded_at <= ?
         )
         GROUP BY ue.installation_id, ue.period`,
      )
      .bind(window.start, window.end)
      .all<UsageAggregate>();

    return result.results ?? [];
  }

  const result = await db
    .prepare(
      `SELECT installation_id, period,
              COUNT(*) AS request_count,
              SUM(tokens) AS tokens,
              SUM(cost) AS cost,
              SUM(quota_weight) AS quota_weight
       FROM usage_event
       GROUP BY installation_id, period`,
    )
    .all<UsageAggregate>();

  return result.results ?? [];
}

export async function runRollup(
  bindings: RollupBindings,
  logger: Logger = noopLogger,
): Promise<{ rollupsWritten: number }> {
  logger.info("rollup_start", {
    window_start: bindings.window?.start,
    window_end: bindings.window?.end,
  });

  const aggregates = await aggregateUsageEvents(bindings.db, bindings.window);

  let rollupsWritten = 0;
  for (const agg of aggregates) {
    const dims = dimensionsKey(agg.installation_id, agg.period);
    const rollupId = await crypto.subtle
      .digest("SHA-256", new TextEncoder().encode(dims))
      .then((buf) =>
        Array.from(new Uint8Array(buf))
          .map((b) => b.toString(16).padStart(2, "0"))
          .join(""),
      );

    await bindings.db
      .prepare(
        `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost, quota_weight)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(rollup_id) DO UPDATE SET
           request_count = excluded.request_count,
           tokens = excluded.tokens,
           cost = excluded.cost,
           quota_weight = excluded.quota_weight`,
      )
      .bind(
        rollupId,
        dims,
        agg.request_count,
        agg.tokens,
        agg.cost,
        agg.quota_weight,
      )
      .run();
    rollupsWritten += 1;
  }

  logger.info("rollup_complete", { rollups_written: rollupsWritten });
  return { rollupsWritten };
}

/** Request-centric: LEFT JOIN usage_event ON request_id. Aged usage rows
 *  with nulled request_id (journal retention) can never match, so coverage
 *  shrinks with age by design. */
export async function runReconciliation(
  bindings: RollupBindings,
  logger: Logger = noopLogger,
): Promise<ReconciliationReport> {
  const window = bindings.window ?? defaultReconciliationWindow();

  logger.info("reconcile_start", {
    window_start: window.start,
    window_end: window.end,
  });

  const missingAttempts = await bindings.db
    .prepare(
      `SELECT r.request_id, r.request_reference
       FROM ai_request r
       LEFT JOIN ai_attempt a ON a.request_id = r.request_id
       WHERE r.state IN ('Completed', 'Failed')
         AND r.completed_at >= ? AND r.completed_at <= ?
         AND a.attempt_id IS NULL`,
    )
    .bind(window.start, window.end)
    .all<TerminalRequestRow>();

  const missingUsage = await bindings.db
    .prepare(
      `SELECT r.request_id, r.request_reference
       FROM ai_request r
       LEFT JOIN usage_event u ON u.request_id = r.request_id
       WHERE r.state IN ('Completed', 'Failed', 'Cancelled')
         AND r.completed_at >= ? AND r.completed_at <= ?
         AND u.usage_event_id IS NULL`,
    )
    .bind(window.start, window.end)
    .all<TerminalRequestRow>();

  const report: ReconciliationReport = {
    window,
    missingAttemptRows: (missingAttempts.results ?? []).map((row) => ({
      requestId: row.request_id,
      requestReference: row.request_reference,
    })),
    missingUsageCredit: (missingUsage.results ?? []).map((row) => ({
      requestId: row.request_id,
      requestReference: row.request_reference,
    })),
  };

  logger.info("reconcile_complete", {
    missing_attempt_rows: report.missingAttemptRows.length,
    missing_usage_credit: report.missingUsageCredit.length,
  });

  return report;
}

export function logReconciliationReport(
  result: { rollupsWritten: number; report: ReconciliationReport },
  logger: Logger = noopLogger,
): void {
  logger.info("usage_rollup_reconciliation", {
    rollups_written: result.rollupsWritten,
    missing_attempt_rows: result.report.missingAttemptRows.length,
    missing_usage_credit: result.report.missingUsageCredit.length,
    window: result.report.window,
    report: result.report,
  });
}

export async function runRollupAndReconciliation(
  bindings: RollupBindings,
  logger: Logger = noopLogger,
): Promise<{ rollupsWritten: number; report: ReconciliationReport }> {
  const rollup = await runRollup(bindings, logger);
  const report = await runReconciliation(bindings, logger);
  return { rollupsWritten: rollup.rollupsWritten, report };
}
