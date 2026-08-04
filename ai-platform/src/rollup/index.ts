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

function defaultWindow(): { start: string; end: string } {
  const end = new Date();
  const start = new Date(end.getTime() - 30 * 24 * 60 * 60 * 1000);
  return { start: start.toISOString(), end: end.toISOString() };
}

function dimensionsKey(installationId: string, period: string): string {
  return JSON.stringify({ installation_id: installationId, period });
}

async function aggregateUsageEvents(
  db: D1Database,
  window: { start: string; end: string },
): Promise<UsageAggregate[]> {
  const result = await db
    .prepare(
      `SELECT installation_id, period,
              COUNT(*) AS request_count,
              SUM(tokens) AS tokens,
              SUM(cost) AS cost
       FROM usage_event
       WHERE recorded_at >= ? AND recorded_at <= ?
       GROUP BY installation_id, period`,
    )
    .bind(window.start, window.end)
    .all<UsageAggregate>();

  return result.results ?? [];
}

export async function runRollup(
  bindings: RollupBindings,
): Promise<{ rollupsWritten: number }> {
  const window = bindings.window ?? defaultWindow();
  const aggregates = await aggregateUsageEvents(bindings.db, window);

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
  const window = bindings.window ?? defaultWindow();

  const terminalRequests = await bindings.db
    .prepare(
      `SELECT request_id, request_reference
       FROM ai_request
       WHERE state IN ('Completed', 'Failed', 'Cancelled', 'AwaitingContext')
         AND completed_at >= ? AND completed_at <= ?`,
    )
    .bind(window.start, window.end)
    .all<TerminalRequestRow>();

  const missingAttemptRows: ReconciliationReport["missingAttemptRows"] = [];
  const missingUsageCredit: ReconciliationReport["missingUsageCredit"] = [];

  for (const req of terminalRequests.results ?? []) {
    const attemptCount = await bindings.db
      .prepare(`SELECT COUNT(*) AS count FROM ai_attempt WHERE request_id = ?`)
      .bind(req.request_id)
      .first<{ count: number }>();

    if ((attemptCount?.count ?? 0) === 0) {
      missingAttemptRows.push({
        requestId: req.request_id,
        requestReference: req.request_reference,
      });
    }

    const usageCount = await bindings.db
      .prepare(`SELECT COUNT(*) AS count FROM usage_event WHERE request_id = ?`)
      .bind(req.request_id)
      .first<{ count: number }>();

    if ((usageCount?.count ?? 0) === 0) {
      missingUsageCredit.push({
        requestId: req.request_id,
        requestReference: req.request_reference,
      });
    }
  }

  return {
    window,
    missingAttemptRows,
    missingUsageCredit,
  };
}

export async function runRollupAndReconciliation(
  bindings: RollupBindings,
): Promise<{ rollupsWritten: number; report: ReconciliationReport }> {
  const rollup = await runRollup(bindings);
  const report = await runReconciliation(bindings);
  return { rollupsWritten: rollup.rollupsWritten, report };
}
