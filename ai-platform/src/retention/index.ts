import type { Envelope } from "../journal";

export const DIAGNOSTIC_BASELINE_DAYS = 7;
export const JOURNAL_HORIZON_DAYS = 90;
export const LEDGER_HORIZON_DAYS = 2555;

export const MS_PER_DAY = 24 * 60 * 60 * 1000;

export type RetentionClassResolver = (
  capabilityId: string,
  capabilityVersion: string,
) => string;

export function defaultRetentionClassResolver(): RetentionClassResolver {
  return () => "diagnostic_7d";
}

/** Parse manifest `retentionClass` (e.g. `diagnostic_30d`) into horizon days. */
export function parseDiagnosticHorizonDays(retentionClass: string): number {
  const match = /^diagnostic_(\d+)d$/i.exec(retentionClass.trim());
  if (match) {
    return Number.parseInt(match[1], 10);
  }
  return DIAGNOSTIC_BASELINE_DAYS;
}

export function diagnosticHorizonMs(retentionClass: string): number {
  return parseDiagnosticHorizonDays(retentionClass) * MS_PER_DAY;
}

export function isWithinDiagnosticRetention(
  timestampIso: string,
  retentionClass: string,
  now: Date = new Date(),
): boolean {
  const horizonMs = diagnosticHorizonMs(retentionClass);
  const ageMs = now.getTime() - Date.parse(timestampIso);
  return ageMs <= horizonMs;
}

type RetentionBindings = {
  db: D1Database;
  r2: R2Bucket;
  now?: Date;
  resolveRetentionClass?: RetentionClassResolver;
};

type RequestRetentionRow = {
  request_id: string;
  capability_id: string;
  capability_version: string;
  created_at: string;
  completed_at: string | null;
  payload_pointer: string | null;
};

function referenceTimestamp(row: RequestRetentionRow): string {
  return row.completed_at ?? row.created_at;
}

async function writePurgeAudit(
  db: D1Database,
  operatorId: string,
  action: string,
  target: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, ?, ?, NULL, NULL, ?)`,
    )
    .bind(crypto.randomUUID(), operatorId, action, target, new Date().toISOString())
    .run();
}

export async function runRetentionPurge(
  bindings: RetentionBindings,
): Promise<{
  diagnosticDeleted: number;
  journalDeleted: number;
  ledgerDeleted: number;
}> {
  const now = bindings.now ?? new Date();
  const resolveRetentionClass =
    bindings.resolveRetentionClass ?? defaultRetentionClassResolver();
  const { db, r2 } = bindings;

  const journalCutoff = new Date(
    now.getTime() - JOURNAL_HORIZON_DAYS * MS_PER_DAY,
  ).toISOString();
  const ledgerCutoff = new Date(
    now.getTime() - LEDGER_HORIZON_DAYS * MS_PER_DAY,
  ).toISOString();

  let diagnosticDeleted = 0;

  const requestRows = await db
    .prepare(
      `SELECT request_id, capability_id, capability_version, created_at,
              completed_at, payload_pointer
       FROM ai_request
       WHERE payload_pointer IS NOT NULL`,
    )
    .all<RequestRetentionRow>();

  for (const row of requestRows.results ?? []) {
    const retentionClass = resolveRetentionClass(
      row.capability_id,
      row.capability_version,
    );
    const horizonMs = diagnosticHorizonMs(retentionClass);
    const refTime = referenceTimestamp(row);
    const ageMs = now.getTime() - Date.parse(refTime);
    if (ageMs > horizonMs && row.payload_pointer) {
      await r2.delete(row.payload_pointer);
      await db
        .prepare(
          `UPDATE ai_request SET payload_pointer = NULL WHERE request_id = ?`,
        )
        .bind(row.request_id)
        .run();
      diagnosticDeleted += 1;
    }
  }

  const journalResult = await db
    .prepare(
      `DELETE FROM ai_attempt
       WHERE request_id IN (
         SELECT request_id FROM ai_request WHERE created_at < ?
       )`,
    )
    .bind(journalCutoff)
    .run();

  const journalRequestResult = await db
    .prepare(
      `DELETE FROM ai_request
       WHERE created_at < ?
         AND request_id NOT IN (SELECT request_id FROM usage_event)`,
    )
    .bind(journalCutoff)
    .run();

  const journalDeleted =
    (journalResult.meta.changes ?? 0) + (journalRequestResult.meta.changes ?? 0);

  const ledgerUsageEvent = await db
    .prepare(`DELETE FROM usage_event WHERE recorded_at < ?`)
    .bind(ledgerCutoff)
    .run();

  const ledgerOrphanRequests = await db
    .prepare(
      `DELETE FROM ai_request
       WHERE created_at < ?
         AND request_id NOT IN (SELECT request_id FROM usage_event)`,
    )
    .bind(journalCutoff)
    .run();

  const rollupRows = await db
    .prepare(`SELECT rollup_id, dimensions FROM usage_rollup`)
    .all<{ rollup_id: string; dimensions: string }>();

  let rollupDeleted = 0;
  const ledgerCutoffDate = ledgerCutoff.slice(0, 7);
  for (const rollup of rollupRows.results ?? []) {
    try {
      const dims = JSON.parse(rollup.dimensions) as { period?: string };
      if (dims.period && dims.period < ledgerCutoffDate) {
        await db
          .prepare(`DELETE FROM usage_rollup WHERE rollup_id = ?`)
          .bind(rollup.rollup_id)
          .run();
        rollupDeleted += 1;
      }
    } catch {
      // skip malformed dimensions
    }
  }

  const ledgerAudit = await db
    .prepare(`DELETE FROM control_audit WHERE recorded_at < ?`)
    .bind(ledgerCutoff)
    .run();
  const ledgerGrant = await db
    .prepare(`DELETE FROM capability_grant WHERE changed_at < ?`)
    .bind(ledgerCutoff)
    .run();

  const ledgerDeleted =
    (ledgerUsageEvent.meta.changes ?? 0) +
    (ledgerOrphanRequests.meta.changes ?? 0) +
    rollupDeleted +
    (ledgerAudit.meta.changes ?? 0) +
    (ledgerGrant.meta.changes ?? 0);

  return { diagnosticDeleted, journalDeleted, ledgerDeleted };
}

export async function purgeByInstallationId(
  installationId: string,
  operatorId: string,
  bindings: { db: D1Database; r2: R2Bucket },
): Promise<void> {
  const { db, r2 } = bindings;

  const requests = await db
    .prepare(
      `SELECT request_id, payload_pointer FROM ai_request WHERE installation_id = ?`,
    )
    .bind(installationId)
    .all<{ request_id: string; payload_pointer: string | null }>();

  for (const row of requests.results ?? []) {
    if (row.payload_pointer) {
      await r2.delete(row.payload_pointer);
    }
  }

  await db.batch([
    db.prepare(
      `DELETE FROM ai_attempt
       WHERE request_id IN (
         SELECT request_id FROM ai_request WHERE installation_id = ?
       )`,
    ).bind(installationId),
    db.prepare(
      `DELETE FROM usage_event WHERE installation_id = ?`,
    ).bind(installationId),
    db.prepare(
      `DELETE FROM ai_request WHERE installation_id = ?`,
    ).bind(installationId),
  ]);

  await writePurgeAudit(db, operatorId, "purge_installation", installationId);
}

export type { Envelope };
