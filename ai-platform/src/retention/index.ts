import { load } from "../manifest";
import type { Envelope } from "../journal";
import { noopLogger, type Logger } from "../logger";
/**
 * Bundled published manifests (eager static imports — Workers runtime has no
 * `import.meta.glob`). Add each new `manifests/published/*.json` here so
 * retentionClass stays resolvable without a D1 read.
 */
import visitSummaryPublished from "../../manifests/published/clinic.visit_summary@1.0.0.json";

export const DIAGNOSTIC_BASELINE_DAYS = 7;
/** Enforced diagnostic-horizon band (§7.7 days-to-weeks; ≤ journal horizon). */
export const DIAGNOSTIC_HORIZON_MIN_DAYS = 1;
export const DIAGNOSTIC_HORIZON_MAX_DAYS = 90;
export const JOURNAL_HORIZON_DAYS = 90;
export const LEDGER_HORIZON_DAYS = 2555;
/** Months-class horizon for `platform_counter` (§7.7) — aligned with journal. */
export const COUNTER_HORIZON_DAYS = JOURNAL_HORIZON_DAYS;

export const MS_PER_DAY = 24 * 60 * 60 * 1000;

export type RetentionClassResolver = (
  capabilityId: string,
  capabilityVersion: string,
) => string;

/** Constant fallback for unknown capabilities / optional override injection. */
export function defaultRetentionClassResolver(): RetentionClassResolver {
  return () => "diagnostic_7d";
}

const PUBLISHED_MANIFEST_JSON: ReadonlyArray<Record<string, unknown>> = [
  visitSummaryPublished as Record<string, unknown>,
];

function envelopeObjectKey(requestId: string): string {
  return `request/${requestId}/envelope`;
}

/**
 * Diagnostic R2-scan prefilter days = min(published horizons, baseline, band min).
 * The band minimum (1d) keeps short legal classes eligible for the per-row check.
 */
export function minPublishedDiagnosticHorizonDays(): number {
  let minDays = DIAGNOSTIC_BASELINE_DAYS;
  for (const json of PUBLISHED_MANIFEST_JSON) {
    const governance = json.Governance;
    if (
      typeof governance === "object" &&
      governance !== null &&
      "retentionClass" in governance
    ) {
      const days = parseDiagnosticHorizonDays(
        String((governance as { retentionClass: unknown }).retentionClass),
      );
      minDays = Math.min(minDays, days);
    }
  }
  return Math.min(minDays, DIAGNOSTIC_HORIZON_MIN_DAYS);
}

export function createManifestRetentionClassResolver(): RetentionClassResolver {
  const byKey = new Map<string, string>();
  for (const json of PUBLISHED_MANIFEST_JSON) {
    const manifest = load(json);
    const key = `${manifest.Identity.capabilityId}@${manifest.Identity.version}`;
    byKey.set(key, String(manifest.Governance.retentionClass));
  }
  return (capabilityId, capabilityVersion) =>
    byKey.get(`${capabilityId}@${capabilityVersion}`) ?? "diagnostic_7d";
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
  logger?: Logger;
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
  counterDeleted: number;
}> {
  const now = bindings.now ?? new Date();
  const logger = bindings.logger ?? noopLogger;
  const resolveRetentionClass =
    bindings.resolveRetentionClass ?? defaultRetentionClassResolver();
  const { db, r2 } = bindings;

  const journalCutoff = new Date(
    now.getTime() - JOURNAL_HORIZON_DAYS * MS_PER_DAY,
  ).toISOString();
  const ledgerCutoff = new Date(
    now.getTime() - LEDGER_HORIZON_DAYS * MS_PER_DAY,
  ).toISOString();
  const counterCutoff = new Date(
    now.getTime() - COUNTER_HORIZON_DAYS * MS_PER_DAY,
  ).toISOString();
  // Prefilter at min(diagnostic horizons): published min ∩ baseline, floored
  // by the 1d band min so short classes are never skipped by a 7d gate.
  const diagnosticScanCutoff = new Date(
    now.getTime() - minPublishedDiagnosticHorizonDays() * MS_PER_DAY,
  ).toISOString();

  let diagnosticDeleted = 0;

  const requestRows = await db
    .prepare(
      `SELECT request_id, capability_id, capability_version, created_at,
              completed_at, payload_pointer
       FROM ai_request
       WHERE payload_pointer IS NOT NULL
         AND COALESCE(completed_at, created_at) < ?`,
    )
    .bind(diagnosticScanCutoff)
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

  // Journal purge: delete R2 envelopes before dropping rows so long diagnostic
  // classes cannot orphan PII objects after the 90d journal cutoff.
  const journalExpired = await db
    .prepare(
      `SELECT request_id, payload_pointer FROM ai_request WHERE created_at < ?`,
    )
    .bind(journalCutoff)
    .all<{ request_id: string; payload_pointer: string | null }>();

  for (const row of journalExpired.results ?? []) {
    await r2.delete(
      row.payload_pointer ?? envelopeObjectKey(row.request_id),
    );
  }

  await db
    .prepare(
      `UPDATE usage_event SET request_id = NULL
       WHERE request_id IN (
         SELECT request_id FROM ai_request WHERE created_at < ?
       )`,
    )
    .bind(journalCutoff)
    .run();

  const journalAttemptResult = await db
    .prepare(
      `DELETE FROM ai_attempt
       WHERE request_id IN (
         SELECT request_id FROM ai_request WHERE created_at < ?
       )`,
    )
    .bind(journalCutoff)
    .run();

  const journalRequestResult = await db
    .prepare(`DELETE FROM ai_request WHERE created_at < ?`)
    .bind(journalCutoff)
    .run();

  const journalDeleted =
    (journalAttemptResult.meta.changes ?? 0) +
    (journalRequestResult.meta.changes ?? 0);

  const ledgerUsageEvent = await db
    .prepare(`DELETE FROM usage_event WHERE recorded_at < ?`)
    .bind(ledgerCutoff)
    .run();

  const ledgerCutoffPeriod = ledgerCutoff.slice(0, 7);
  const ledgerRollup = await db
    .prepare(
      `DELETE FROM usage_rollup
       WHERE json_extract(dimensions, '$.period') < ?`,
    )
    .bind(ledgerCutoffPeriod)
    .run();

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
    (ledgerRollup.meta.changes ?? 0) +
    (ledgerAudit.meta.changes ?? 0) +
    (ledgerGrant.meta.changes ?? 0);

  const counterResult = await db
    .prepare(`DELETE FROM platform_counter WHERE time_bucket < ?`)
    .bind(counterCutoff)
    .run();
  const counterDeleted = counterResult.meta.changes ?? 0;

  logger.info("retention_purge_complete", {
    diagnostic_deleted: diagnosticDeleted,
    journal_deleted: journalDeleted,
    ledger_deleted: ledgerDeleted,
    counter_deleted: counterDeleted,
  });

  return { diagnosticDeleted, journalDeleted, ledgerDeleted, counterDeleted };
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

  // Always delete by the derived C3 key so mid-sequence NULL pointers cannot
  // leave PII envelopes behind after an installation purge.
  for (const row of requests.results ?? []) {
    await r2.delete(envelopeObjectKey(row.request_id));
  }

  const installationScope = `installation:${installationId}`;

  // Decision: purge-by-installation-id is the store half of installation
  // deletion recovery (§7.7). It removes identity + commercial footprint
  // (`installation_key`, `entitlement`, `installation`) in addition to
  // journal/ledger/counter/grant rows — not deferred to B2 lifecycle alone.
  await db.batch([
    db
      .prepare(
        `DELETE FROM ai_attempt
         WHERE request_id IN (
           SELECT request_id FROM ai_request WHERE installation_id = ?
         )`,
      )
      .bind(installationId),
    db.prepare(`DELETE FROM usage_event WHERE installation_id = ?`).bind(
      installationId,
    ),
    db.prepare(`DELETE FROM ai_request WHERE installation_id = ?`).bind(
      installationId,
    ),
    db
      .prepare(
        `DELETE FROM usage_rollup
         WHERE json_extract(dimensions, '$.installation_id') = ?`,
      )
      .bind(installationId),
    db
      .prepare(
        `DELETE FROM platform_counter
         WHERE json_extract(dimension_set, '$.installation_id') = ?`,
      )
      .bind(installationId),
    db
      .prepare(`DELETE FROM capability_grant WHERE scope = ?`)
      .bind(installationScope),
    db
      .prepare(`DELETE FROM installation_key WHERE installation_id = ?`)
      .bind(installationId),
    db
      .prepare(`DELETE FROM entitlement WHERE installation_id = ?`)
      .bind(installationId),
    db
      .prepare(`DELETE FROM installation WHERE installation_id = ?`)
      .bind(installationId),
  ]);

  await writePurgeAudit(db, operatorId, "purge_installation", installationId);
}

export type { Envelope };
