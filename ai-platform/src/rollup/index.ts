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
};

type TerminalRequestRow = {
  request_id: string;
  request_reference: string;
};

const TERMINAL_STATES = `('Completed', 'Failed', 'Cancelled', 'AwaitingContext')`;

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
                SUM(ue.cost) AS cost
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
              SUM(cost) AS cost
       FROM usage_event
       GROUP BY installation_id, period`,
    )
    .all<UsageAggregate>();

  return result.results ?? [];
}

export async function runRollup(
  bindings: RollupBindings,
): Promise<{ rollupsWritten: number }> {
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
        `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(rollup_id) DO UPDATE SET
           request_count = excluded.request_count,
           tokens = excluded.tokens,
           cost = excluded.cost`,
      )
      .bind(
        rollupId,
        dims,
        agg.request_count,
        agg.tokens,
        agg.cost,
      )
      .run();
    rollupsWritten += 1;
  }

  return { rollupsWritten };
}

export async function runReconciliation(
  bindings: RollupBindings,
): Promise<ReconciliationReport> {
  const window = bindings.window ?? defaultReconciliationWindow();

  const missingAttempts = await bindings.db
    .prepare(
      `SELECT r.request_id, r.request_reference
       FROM ai_request r
       LEFT JOIN ai_attempt a ON a.request_id = r.request_id
       WHERE r.state IN ${TERMINAL_STATES}
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
       WHERE r.state IN ${TERMINAL_STATES}
         AND r.completed_at >= ? AND r.completed_at <= ?
         AND u.usage_event_id IS NULL`,
    )
    .bind(window.start, window.end)
    .all<TerminalRequestRow>();

  return {
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
}

export function logReconciliationReport(
  result: { rollupsWritten: number; report: ReconciliationReport },
  log: (line: string) => void = console.log,
): void {
  log(
    JSON.stringify({
      level: "info",
      message: "usage_rollup_reconciliation",
      rollups_written: result.rollupsWritten,
      missing_attempt_rows: result.report.missingAttemptRows.length,
      missing_usage_credit: result.report.missingUsageCredit.length,
      window: result.report.window,
      report: result.report,
    }),
  );
}

export async function runRollupAndReconciliation(
  bindings: RollupBindings,
): Promise<{ rollupsWritten: number; report: ReconciliationReport }> {
  const rollup = await runRollup(bindings);
  const report = await runReconciliation(bindings);
  return { rollupsWritten: rollup.rollupsWritten, report };
}
