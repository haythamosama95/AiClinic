import { canonicalize, sha256Hex } from "vendor-contracts";
import { clockNowIso, type ClockEnv } from "../clock.js";
import { assertAboRecoveryPublished } from "../recovery-fence.js";

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
  created_at: string;
};

async function listPendingFacts(db: D1Database): Promise<PendingFact[]> {
  const result = await db
    .prepare(
      `SELECT fl.fact_seq, fl."table", fl.key, fl.row_sha256, fl.row_json, fl.created_at
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
    payload_version: 2,
    fact_seq: row.fact_seq,
    table: row.table,
    key: row.key,
    row_sha256: row.row_sha256,
    fact_created_at: row.created_at,
  };
  if (row.row_json != null && row.row_json.length > 0) {
    line.row = JSON.parse(row.row_json);
  }
  return canonicalize(line);
}

async function validateFact(row: PendingFact): Promise<void> {
  if (row.row_json == null || row.row_json.length === 0) {
    throw new Error(`ledger_fact_missing_canonical_row:${row.fact_seq}`);
  }
  const parsed = JSON.parse(row.row_json) as Record<string, unknown>;
  if (
    row.table === "paymob_intention" ||
    (row.table === "paymob_intention_attempt_event" && Object.hasOwn(parsed, "client_secret"))
  ) {
    throw new Error(`ledger_adapter_secret_requires_historical_stop:${row.fact_seq}`);
  }
  const canonical = new TextDecoder().decode(canonicalize(parsed));
  if (canonical !== row.row_json || await sha256Hex(canonicalize(parsed)) !== row.row_sha256) {
    throw new Error(`ledger_fact_hash_conflict:${row.fact_seq}`);
  }
  if (row.table === "command_recovery_fact") {
    const payloadJson = parsed.payload_json;
    const payloadHash = parsed.payload_sha256;
    if (typeof payloadJson !== "string" || typeof payloadHash !== "string") {
      throw new Error(`ledger_command_fact_invalid:${row.fact_seq}`);
    }
    const commandPayload = JSON.parse(payloadJson) as Record<string, unknown>;
    const commandCanonical = new TextDecoder().decode(canonicalize(commandPayload));
    if (
      commandCanonical !== payloadJson ||
      await sha256Hex(canonicalize(commandPayload)) !== payloadHash ||
      containsRecoverySecret(commandPayload)
    ) {
      throw new Error(`ledger_command_fact_invalid:${row.fact_seq}`);
    }
  }
}

function containsRecoverySecret(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsRecoverySecret);
  if (typeof value === "string") {
    const text = value.trim();
    if (/^Bearer\s+\S+/iu.test(text) || /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/u.test(text)) return true;
    if ((text.startsWith("{") && text.endsWith("}")) || (text.startsWith("[") && text.endsWith("]"))) {
      try { return containsRecoverySecret(JSON.parse(text) as unknown); } catch { return false; }
    }
    return false;
  }
  if (typeof value !== "object" || value === null) return false;
  for (const [key, item] of Object.entries(value)) {
    if (/^(access_jwt|jwt|client_secret|email|phone|name|contact|signed_operation_json|signed_assertion_json)$/iu.test(key)) return true;
    if (containsRecoverySecret(item)) return true;
  }
  return false;
}

export async function exportFacts(env: ExportEnv): Promise<void> {
  await assertAboRecoveryPublished(env);
  const pending = await listPendingFacts(env.DB);
  for (const row of pending) {
    await validateFact(row);
    const payload = ledgerLinePayload(row);
    const objectKey = `ledger/${row.fact_seq}.ndjson`;
    const prior = await env.R2.get(objectKey);
    if (prior !== null) {
      if (await prior.text() !== payload) {
        throw new Error(`ledger_object_conflict:${objectKey}`);
      }
    } else {
      await env.R2.put(objectKey, payload);
    }
    const exportedAt = await clockNowIso(env);
    await env.DB.prepare(
      `INSERT INTO fact_export (fact_seq, exported_at) VALUES (?, ?)
       ON CONFLICT(fact_seq) DO NOTHING`,
    )
      .bind(row.fact_seq, exportedAt)
      .run();
  }

  const range = await env.DB.prepare(
    `SELECT COALESCE(MAX(fact_seq), 0) AS high_water,
            COUNT(*) AS fact_count,
            MIN(fact_seq) AS low_water
     FROM fact_log`,
  ).first<{ high_water: number; fact_count: number; low_water: number | null }>();
  if (range === null || range.high_water === 0) {
    return;
  }
  if (range.low_water !== 1 || range.fact_count !== range.high_water) {
    throw new Error("ledger_fact_sequence_gap");
  }
  const unexported = await env.DB.prepare(
    `SELECT fact_seq FROM fact_log fl
     LEFT JOIN fact_export fe ON fe.fact_seq = fl.fact_seq
     WHERE fe.fact_seq IS NULL LIMIT 1`,
  ).first<{ fact_seq: number }>();
  if (unexported !== null) {
    throw new Error(`ledger_manifest_incomplete:${unexported.fact_seq}`);
  }

  const exported = await env.DB.prepare(
    `SELECT fl.fact_seq, fl."table", fl.key, fl.row_sha256, fl.row_json, fl.created_at
     FROM fact_log fl INNER JOIN fact_export fe ON fe.fact_seq = fl.fact_seq
     ORDER BY fl.fact_seq ASC`,
  ).all<PendingFact>();
  for (const row of exported.results ?? []) {
    await validateFact(row);
    const key = `ledger/${row.fact_seq}.ndjson`;
    const existing = await env.R2.get(key);
    const expected = ledgerLinePayload(row);
    if (existing === null || await existing.text() !== expected) {
      throw new Error(`ledger_object_conflict:${key}`);
    }
  }

  // Append-only high-water markers make the exported prefix explicit. A
  // stable body lets an interrupted repeat acknowledge the exact same marker.
  const manifest = JSON.stringify({ payload_version: 1, exported_through: range.high_water });
  const manifestKey = `ledger-manifest/${range.high_water}.json`;
  const priorManifest = await env.R2.get(manifestKey);
  if (priorManifest !== null) {
    if (await priorManifest.text() !== manifest) {
      throw new Error(`ledger_manifest_conflict:${manifestKey}`);
    }
  } else {
    await env.R2.put(manifestKey, manifest);
  }
}
