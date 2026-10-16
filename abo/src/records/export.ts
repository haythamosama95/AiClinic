import { canonicalize } from "vendor-contracts";
import { clockNowIso, type ClockEnv } from "../clock.js";

export type ExportEnv = ClockEnv & {
  DB: D1Database;
  R2: R2Bucket;
};

type PendingFact = {
  fact_seq: number;
  table: string;
  key: string;
  row_sha256: string;
  row_json: string | null;
};

async function listPendingFacts(db: D1Database): Promise<PendingFact[]> {
  const result = await db
    .prepare(
      `SELECT fl.fact_seq, fl."table", fl.key, fl.row_sha256, fl.row_json
       FROM fact_log fl
       LEFT JOIN fact_export fe ON fl.fact_seq = fe.fact_seq
       WHERE fe.fact_seq IS NULL
       ORDER BY fl.fact_seq ASC`,
    )
    .all<PendingFact>();
  return result.results ?? [];
}

function ledgerLinePayload(row: PendingFact): string {
  const line: Record<string, unknown> = {
    fact_seq: row.fact_seq,
    table: row.table,
    key: row.key,
    row_sha256: row.row_sha256,
  };
  if (row.row_json != null && row.row_json.length > 0) {
    line.row = JSON.parse(row.row_json);
  }
  return canonicalize(line);
}

export async function exportFacts(env: ExportEnv): Promise<void> {
  const pending = await listPendingFacts(env.DB);
  for (const row of pending) {
    const payload = ledgerLinePayload(row);
    const objectKey = `ledger/${row.fact_seq}.ndjson`;
    try {
      await env.R2.put(objectKey, payload);
    } catch {
      return;
    }
    const exportedAt = await clockNowIso(env);
    await env.DB.prepare(
      `INSERT INTO fact_export (fact_seq, exported_at) VALUES (?, ?)`,
    )
      .bind(row.fact_seq, exportedAt)
      .run();
  }
}
