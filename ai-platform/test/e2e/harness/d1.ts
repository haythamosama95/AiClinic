import migrationSql from "../../../migrations/20260731120000_platform_schema.sql?raw";
import capabilityGrantLifecycleSql from "../../../migrations/20260802100000_capability_grant_lifecycle.sql?raw";
import canaryMigrationSql from "../../../migrations/20260803100000_routing_policy_canary.sql?raw";
import tokenContractMigrationSql from "../../../migrations/20260803120000_token_contract.sql?raw";
import retentionIndexesSql from "../../../migrations/20260805120000_f3_retention_indexes.sql?raw";
import conversationIndexSql from "../../../migrations/20260805180000_h3_conversation_index.sql?raw";
import statusMigrationSql from "../../../migrations/20260805190000_routing_policy_status.sql?raw";
import killSwitchMigrationSql from "../../../migrations/20260807120000_kill_switch.sql?raw";
import graceQueueMigrationSql from "../../../migrations/20260821120000_grace_admission_queue.sql?raw";
import entitlementUniqueSql from "../../../migrations/20260821130000_entitlement_installation_unique.sql?raw";
import { isolateConfigCache } from "../../../src/config-cache";
import { env, PLATFORM_TABLES } from "./env";

/** Real SQL files under `ai-platform/migrations/`, in filename order. */
export const MIGRATION_SQL: readonly string[] = [
  migrationSql,
  capabilityGrantLifecycleSql,
  canaryMigrationSql,
  tokenContractMigrationSql,
  retentionIndexesSql,
  conversationIndexSql,
  statusMigrationSql,
  killSwitchMigrationSql,
  graceQueueMigrationSql,
  entitlementUniqueSql,
];

const TOKEN_CONTRACT_SEED = {
  ver: "1",
  added_at: "2026-08-03T00:00:00.000Z",
  changed_by: "seed",
} as const;

function splitSqlStatements(sql: string): string[] {
  return sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);
}

function isIgnorableBootstrapError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return /already exists|UNIQUE constraint failed|duplicate column/i.test(
    message,
  );
}

export async function applySql(db: D1Database, sql: string): Promise<void> {
  for (const statement of splitSqlStatements(sql)) {
    try {
      await db.prepare(statement).run();
    } catch (error) {
      if (isIgnorableBootstrapError(error)) {
        continue;
      }
      throw error;
    }
  }
}

/**
 * Apply the real migration chain to `db` (default: pool `env.DB`).
 * Idempotent across isolate reuse: already-applied CREATE/INSERT is skipped.
 */
export async function applyAllMigrations(
  db: D1Database = env.DB,
): Promise<void> {
  for (const sql of MIGRATION_SQL) {
    await applySql(db, sql);
  }
}

export async function listTableNames(
  db: D1Database = env.DB,
): Promise<string[]> {
  const result = await db
    .prepare(
      `SELECT name FROM sqlite_master
       WHERE type='table' AND name NOT LIKE 'sqlite_%'
       ORDER BY name`,
    )
    .all<{ name: string }>();
  return (result.results ?? []).map((row) => row.name);
}

async function reseedTokenContract(db: D1Database): Promise<void> {
  await db
    .prepare(
      `INSERT OR IGNORE INTO token_contract (ver, added_at, retired_at, changed_by)
       VALUES (?, ?, NULL, ?)`,
    )
    .bind(
      TOKEN_CONTRACT_SEED.ver,
      TOKEN_CONTRACT_SEED.added_at,
      TOKEN_CONTRACT_SEED.changed_by,
    )
    .run();
}

async function resetR2(): Promise<void> {
  let cursor: string | undefined;
  do {
    const page = await env.R2.list(
      cursor ? { cursor } : undefined,
    );
    if (page.objects.length > 0) {
      await Promise.all(page.objects.map((object) => env.R2.delete(object.key)));
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
}

export async function resetPlatformState(): Promise<void> {
  const db = env.DB;
  await db.batch([
    db.prepare("DELETE FROM control_audit"),
    db.prepare("DELETE FROM grace_admission_queue"),
    db.prepare("DELETE FROM platform_counter"),
    db.prepare("DELETE FROM usage_rollup"),
    db.prepare("DELETE FROM usage_event"),
    db.prepare("DELETE FROM ai_attempt"),
    db.prepare("DELETE FROM ai_request"),
    db.prepare("DELETE FROM capability_grant"),
    db.prepare("DELETE FROM routing_policy"),
    db.prepare("DELETE FROM kill_switch"),
    db.prepare("DELETE FROM entitlement"),
    db.prepare("DELETE FROM installation_key"),
    db.prepare("DELETE FROM installation"),
    db.prepare("DELETE FROM token_contract"),
  ]);
  await reseedTokenContract(db);
  await resetR2();
  isolateConfigCache.clear();
}

/**
 * Direct D1 writes. Call ONLY when a scenario's Journey setup says `[SEED]`.
 * Do not use this to skip earlier-stage operations the catalog expects to run
 * through the real enroll/entitle/publish paths.
 */
export async function seedSql(
  statements: Array<{ sql: string; params?: unknown[] }>,
  db: D1Database = env.DB,
): Promise<void> {
  for (const statement of statements) {
    const prepared = db.prepare(statement.sql);
    if (statement.params && statement.params.length > 0) {
      await prepared.bind(...statement.params).run();
    } else {
      await prepared.run();
    }
  }
}

export async function queryOne<T extends Record<string, unknown>>(
  sql: string,
  params: unknown[] = [],
  db: D1Database = env.DB,
): Promise<T | null> {
  return db.prepare(sql).bind(...params).first<T>();
}

export async function queryAll<T extends Record<string, unknown>>(
  sql: string,
  params: unknown[] = [],
  db: D1Database = env.DB,
): Promise<T[]> {
  const result = await db.prepare(sql).bind(...params).all<T>();
  return result.results ?? [];
}

export async function count(
  table: string,
  where?: string,
  params: unknown[] = [],
  db: D1Database = env.DB,
): Promise<number> {
  const sql = where
    ? `SELECT COUNT(*) AS c FROM ${table} WHERE ${where}`
    : `SELECT COUNT(*) AS c FROM ${table}`;
  const row = await db.prepare(sql).bind(...params).first<{ c: number }>();
  return row?.c ?? 0;
}

export async function getAiRequest(
  ref: string,
): Promise<Record<string, unknown> | null> {
  return queryOne(
    "SELECT * FROM ai_request WHERE request_reference = ?",
    [ref],
  );
}

export async function getAttempts(
  requestId: string,
): Promise<Record<string, unknown>[]> {
  return queryAll(
    "SELECT * FROM ai_attempt WHERE request_id = ? ORDER BY attempt_no",
    [requestId],
  );
}

export async function getUsageEvents(
  requestId: string,
): Promise<Record<string, unknown>[]> {
  return queryAll("SELECT * FROM usage_event WHERE request_id = ?", [
    requestId,
  ]);
}

export async function getEntitlement(
  installationId: string,
): Promise<Record<string, unknown> | null> {
  return queryOne("SELECT * FROM entitlement WHERE installation_id = ?", [
    installationId,
  ]);
}

export async function getGrants(
  scope: string,
): Promise<Record<string, unknown>[]> {
  return queryAll(
    "SELECT * FROM capability_grant WHERE scope = ? ORDER BY changed_at",
    [scope],
  );
}

export async function getAudits(
  action: string,
  target: string,
): Promise<Record<string, unknown>[]> {
  return queryAll(
    "SELECT * FROM control_audit WHERE action = ? AND target = ? ORDER BY recorded_at",
    [action, target],
  );
}

export async function getRoutingPolicy(
  policyId: string,
  version: string,
): Promise<Record<string, unknown> | null> {
  return queryOne(
    "SELECT * FROM routing_policy WHERE policy_id = ? AND version = ?",
    [policyId, version],
  );
}

export async function getR2Json(key: string): Promise<Record<string, unknown>> {
  const object = await env.R2.get(key);
  if (!object) {
    throw new Error(`R2 object not found: ${key}`);
  }
  return JSON.parse(await object.text()) as Record<string, unknown>;
}

export async function r2Exists(key: string): Promise<boolean> {
  const object = await env.R2.head(key);
  return object !== null;
}

export const d1 = {
  queryOne,
  queryAll,
  count,
  getAiRequest,
  getAttempts,
  getUsageEvents,
  getEntitlement,
  getGrants,
  getAudits,
  getRoutingPolicy,
  applySql,
  applyAllMigrations,
  resetPlatformState,
  seedSql,
  listTableNames,
};

export { PLATFORM_TABLES };

/**
 * Isolate boot + empty-airport baseline. Call from `beforeAll`.
 * Does not seed business rows.
 */
export async function bootstrapE2e(): Promise<void> {
  await applyAllMigrations();
  isolateConfigCache.clear();
}

/**
 * Wipe D1 business tables, R2 objects, and the isolate config cache.
 * Re-inserts the migration `token_contract` seed row (`ver='1'`).
 * Call from `beforeEach`.
 */
export async function resetE2eState(): Promise<void> {
  await resetPlatformState();
}

export function clearConfigCache(): void {
  isolateConfigCache.clear();
}
