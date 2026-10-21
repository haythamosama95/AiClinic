import migrationSql from "../../../migrations/20260731120000_platform_schema.sql?raw";
import capabilityGrantLifecycleSql from "../../../migrations/20260802100000_capability_grant_lifecycle.sql?raw";
import canaryMigrationSql from "../../../migrations/20260803100000_routing_policy_canary.sql?raw";
import tokenContractMigrationSql from "../../../migrations/20260803120000_token_contract.sql?raw";
import retentionIndexesSql from "../../../migrations/20260805120000_f3_retention_indexes.sql?raw";
import conversationIndexSql from "../../../migrations/20260805180000_h3_conversation_index.sql?raw";
import statusMigrationSql from "../../../migrations/20260805190000_routing_policy_status.sql?raw";
import killSwitchMigrationSql from "../../../migrations/20260807120000_kill_switch.sql?raw";
import fallbackAdmissionFeedMigrationSql from "../../../migrations/20261006160000_fallback_admission_feed.sql?raw";
import rm24FallbackAdmissionIdentityMigrationSql from "../../../migrations/20261020120000_rm24_fallback_admission_identity.sql?raw";
import rm25FallbackSettlementSql from "../../../migrations/20261020130000_rm25_fallback_settlement.sql?raw";
import entitlementUniqueSql from "../../../migrations/20260821130000_entitlement_installation_unique.sql?raw";
import planCatalogueSql from "../../../migrations/20260911120000_plan_catalogue.sql?raw";
import quotaWeightMigrationSql from "../../../migrations/20260911180000_usage_rollup_quota_weight.sql?raw";
import invoiceMigrationSql from "../../../migrations/20260911200000_invoice.sql?raw";
import operatorCredentialMigrationSql from "../../../migrations/20261003120000_operator_credential_and_platform_alert.sql?raw";
import issuerKeyTenantBindingMigrationSql from "../../../migrations/20261003130000_issuer_key_tenant_binding.sql?raw";
import planVersionPaidGrantCoverageMigrationSql from "../../../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import usageTermMigrationSql from "../../../migrations/20261006120000_usage_term.sql?raw";
import ceilingPolicyMigrationSql from "../../../migrations/20261006130000_ceiling_policy.sql?raw";
import grantVoidMigrationSql from "../../../migrations/20261006140000_grant_void.sql?raw";
import transferMigrationSql from "../../../migrations/20261006150000_transfer.sql?raw";
import dropInvoicingSql from "../../../migrations/20261006170000_drop_invoicing.sql?raw";
import dropPlanEntitlementSql from "../../../migrations/20261006170100_drop_plan_entitlement.sql?raw";
import idempotencyFingerprintSql from "../../../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
import malformedIssuerKeyCleanupSql from "../../../migrations/20261018120000_r1_c3_malformed_issuer_key_cleanup.sql?raw";
import tenantCreationCapTriggerSql from "../../../migrations/20261018120100_r1_c2_tenant_creation_cap_trigger.sql?raw";
import grantClaimsSql from "../../../migrations/20261019120000_r4_pg1_global_grant_claims.sql?raw";
import acceptedGrantCommandsSql from "../../../migrations/20261019130000_r4_pg3_accepted_grant_commands.sql?raw";
import rm18CeilingClaimsSql from "../../../migrations/20261019140000_rm18_complimentary_ceiling_claims.sql?raw";
import r6Pt1ReversalRoutesSql from "../../../migrations/20261019150000_r6_pt1_reversal_routes.sql?raw";
import r6Pt1TransferRouteManifestSql from "../../../migrations/20261019160000_r6_pt1_transfer_route_manifest.sql?raw";
import r6Rm26TransferPreparationSql from "../../../migrations/20261020140000_r6_rm26_transfer_preparation.sql?raw";
import rm27DurableDeletionSql from "../../../migrations/20261020150000_rm27_durable_deletion.sql?raw";
import { splitSqlStatements } from "../../split-sql-statements";
import { isolateConfigCache } from "../../../src/config-cache";
import { clearE2eIssuerRegistry } from "./aat";
import { resetCoverClinicBootstrap } from "./cover";
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
  entitlementUniqueSql,
  planCatalogueSql,
  quotaWeightMigrationSql,
  invoiceMigrationSql,
  operatorCredentialMigrationSql,
  issuerKeyTenantBindingMigrationSql,
  planVersionPaidGrantCoverageMigrationSql,
  usageTermMigrationSql,
  ceilingPolicyMigrationSql,
  grantVoidMigrationSql,
  transferMigrationSql,
  fallbackAdmissionFeedMigrationSql,
  rm24FallbackAdmissionIdentityMigrationSql,
  rm25FallbackSettlementSql,
  dropInvoicingSql,
  dropPlanEntitlementSql,
  idempotencyFingerprintSql,
  malformedIssuerKeyCleanupSql,
  tenantCreationCapTriggerSql,
  grantClaimsSql,
  acceptedGrantCommandsSql,
  rm18CeilingClaimsSql,
  r6Pt1ReversalRoutesSql,
  r6Pt1TransferRouteManifestSql,
  r6Rm26TransferPreparationSql,
  rm27DurableDeletionSql,
];

const TOKEN_CONTRACT_V2_SEED = {
  ver: "2",
  added_at: "2026-10-03T13:00:00.000Z",
  changed_by: "seed",
} as const;

const TOKEN_CONTRACT_V1_SEED = {
  ver: "1",
  added_at: "2026-08-03T00:00:00.000Z",
  retired_at: "2026-10-03T13:00:00.000Z",
  changed_by: "seed",
} as const;

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
  await db.batch([
    db.prepare(
      `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
       VALUES (?, ?, NULL, ?)`,
    ).bind(
      TOKEN_CONTRACT_V2_SEED.ver,
      TOKEN_CONTRACT_V2_SEED.added_at,
      TOKEN_CONTRACT_V2_SEED.changed_by,
    ),
    db.prepare(
      `INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
       VALUES (?, ?, ?, ?)`,
    ).bind(
      TOKEN_CONTRACT_V1_SEED.ver,
      TOKEN_CONTRACT_V1_SEED.added_at,
      TOKEN_CONTRACT_V1_SEED.retired_at,
      TOKEN_CONTRACT_V1_SEED.changed_by,
    ),
  ]);
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
    db.prepare("DROP TRIGGER IF EXISTS grant_claim_no_delete"),
    db.prepare("DROP TRIGGER IF EXISTS complimentary_ceiling_claim_no_delete_guard"),
    db.prepare("DROP TRIGGER IF EXISTS ceiling_policy_command_no_delete"),
    db.prepare("DROP TRIGGER IF EXISTS live_value_route_no_delete"),
    db.prepare("DROP TRIGGER IF EXISTS reversal_command_no_delete"),
    db.prepare("DELETE FROM grant_claim"),
    db.prepare("DELETE FROM complimentary_ceiling_claim"),
    db.prepare("DELETE FROM complimentary_ceiling_claim_backfill"),
    db.prepare("DELETE FROM ceiling_policy_command"),
    db.prepare("DELETE FROM grant_claim_dispute"),
    db.prepare("DELETE FROM grant_claim_backfill"),
    db.prepare("DELETE FROM reversal_command"),
    db.prepare("DELETE FROM deletion_command"),
    db.prepare("DELETE FROM transfer_route_quarantine"),
    db.prepare("DELETE FROM transfer_route_manifest"),
    db.prepare("DELETE FROM live_value_route"),
    db.prepare("DROP TRIGGER IF EXISTS grant_tombstone_no_delete"),
    db.prepare("DROP TRIGGER IF EXISTS grant_tombstone_no_update"),
    db.prepare("DELETE FROM grant_tombstone"),
    db.prepare(`CREATE TRIGGER grant_claim_no_delete
      BEFORE DELETE ON grant_claim
      BEGIN
        SELECT RAISE(ABORT, 'grant_claim is append-only');
      END`),
    db.prepare(`CREATE TRIGGER grant_tombstone_no_update
      BEFORE UPDATE ON grant_tombstone
      BEGIN
        SELECT RAISE(ABORT, 'grant tombstone is immutable');
      END`),
    db.prepare(`CREATE TRIGGER grant_tombstone_no_delete
      BEFORE DELETE ON grant_tombstone
      BEGIN
        SELECT RAISE(ABORT, 'grant tombstone is permanent');
      END`),
    db.prepare(`CREATE TRIGGER live_value_route_no_delete
      BEFORE DELETE ON live_value_route
      BEGIN
        SELECT RAISE(ABORT, 'live value route is permanent');
      END`),
    db.prepare(`CREATE TRIGGER reversal_command_no_delete
      BEFORE DELETE ON reversal_command
      BEGIN
        SELECT RAISE(ABORT, 'reversal command is permanent');
      END`),
    db.prepare(`CREATE TRIGGER complimentary_ceiling_claim_no_delete_guard
      BEFORE DELETE ON complimentary_ceiling_claim
      BEGIN
        SELECT RAISE(ABORT, 'complimentary_ceiling_claim is append-only');
      END`),
    db.prepare(`CREATE TRIGGER ceiling_policy_command_no_delete
      BEFORE DELETE ON ceiling_policy_command
      BEGIN
        SELECT RAISE(ABORT, 'ceiling_policy_command is append-only');
      END`),
  ]);
  await db.batch([
    db.prepare("DELETE FROM assertion_used"),
    db.prepare("DELETE FROM platform_alert"),
    db.prepare("DELETE FROM operator_credential"),
    db.prepare("DELETE FROM control_audit"),
    db.prepare("DELETE FROM fallback_admission"),
    db.prepare("DELETE FROM feed_consumer"),
    db.prepare("DELETE FROM platform_counter"),
    db.prepare("DELETE FROM usage_rollup"),
    db.prepare("DELETE FROM usage_event"),
    db.prepare("DELETE FROM ai_attempt"),
    db.prepare("DELETE FROM ai_request"),
    db.prepare("DELETE FROM capability_grant"),
    db.prepare("DELETE FROM routing_policy"),
    db.prepare("DELETE FROM kill_switch"),
    db.prepare("DELETE FROM coverage_event"),
    db.prepare("DELETE FROM grant_ledger"),
    db.prepare("DELETE FROM ceiling_policy WHERE version > 1"),
    db.prepare(`UPDATE ceiling_policy SET
      per_grant_max_days = 31,
      per_grant_max_allowance_months = 1,
      window_days = 90,
      window_max_days = 62,
      window_max_allowance_months = 2,
      max_paid_grace_days = 7,
      paid_cap_rule = 'proportional',
      set_by = '', assertion_sha256 = '' WHERE version = 1`),
    db.prepare("DELETE FROM grant_void"),
    db.prepare("DELETE FROM coverage_mirror"),
    db.prepare("DELETE FROM plan_version"),
    db.prepare("DELETE FROM service_key"),
    db.prepare("DELETE FROM tenant_binding"),
    db.prepare("DELETE FROM issuer_key"),
    db.prepare("DELETE FROM installation"),
    db.prepare("DELETE FROM token_contract"),
  ]);
  await reseedTokenContract(db);
  await resetR2();
  isolateConfigCache.clear();
  clearE2eIssuerRegistry();
  resetCoverClinicBootstrap();
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
  const binding = await queryOne<{
    org_id: string;
    status: string;
  }>(
    "SELECT org_id, status FROM tenant_binding WHERE installation_id = ?",
    [installationId],
  );
  if (!binding) {
    return null;
  }
  const mirror = await queryOne<{ term_snapshot: string; state: string }>(
    "SELECT term_snapshot, state FROM coverage_mirror WHERE installation_id = ?",
    [installationId],
  );
  if (!mirror) {
    return {
      entitlement_id: installationId,
      installation_id: installationId,
      plan: "professional",
      period_start: "2026-01-01T00:00:00.000Z",
      period_end: "2027-01-01T00:00:00.000Z",
      request_quota: 0,
      token_budget: 0,
      cost_budget: 0,
      allowed_capabilities: "[]",
      soft_threshold: 0,
      status: "pending",
    };
  }
  let capabilities = ["clinic.visit_summary"];
  try {
    const snapshot = JSON.parse(mirror.term_snapshot) as {
      capabilities?: string[];
    };
    if (Array.isArray(snapshot.capabilities)) {
      capabilities = snapshot.capabilities;
    }
  } catch {
    // keep default
  }
  const active = mirror.state === "active";
  return {
    entitlement_id: installationId,
    installation_id: installationId,
    plan: "professional",
    period_start: "2026-01-01T00:00:00.000Z",
    period_end: "2027-01-01T00:00:00.000Z",
    request_quota: active ? 1000 : 0,
    token_budget: active ? 500000 : 0,
    cost_budget: active ? 50 : 0,
    allowed_capabilities: JSON.stringify(capabilities),
    soft_threshold: active ? 0.8 : 0,
    status: active ? "active" : "pending",
  };
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
 * Re-inserts the migration `token_contract` seed row (`ver='1'`) and the
 * catalogue `plan` rows (`standard`, `professional`, `starter`, `enterprise`).
 * Call from `beforeEach`.
 */
export async function resetE2eState(): Promise<void> {
  await resetPlatformState();
}

export function clearConfigCache(): void {
  isolateConfigCache.clear();
}
