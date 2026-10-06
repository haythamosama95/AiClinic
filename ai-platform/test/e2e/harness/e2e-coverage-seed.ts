import { runInDurableObject } from "cloudflare:test";
import { clearConfigCache, seedSql } from "./d1";
import { CAPABILITY_ID, env } from "./env";
import { gatewayObjectJson } from "./gateway-object";
import type { Scenario } from "./types";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

const DEFAULT_PERIOD_START = "2026-08-01T00:00:00.000Z";
const DEFAULT_PERIOD_END = "2026-09-01T00:00:00.000Z";
const DEFAULT_REQUEST_QUOTA = 1000;

function e2eActiveTermId(installationId: string): string {
  return `term-${installationId.slice(0, 8)}`;
}

function sqlLiteral(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

export type E2eQuotaSeedOptions = {
  period_start?: string;
  period_end?: string;
  request_quota?: number;
};

/** Stage-3 precheck and mirror fallback require a `coverage_mirror` row in e2e. */
export async function ensureE2eCoverageMirror(scenario: Scenario): Promise<void> {
  const hardStopAt = new Date(Date.now() + 365 * MS_PER_DAY).toISOString();
  const termId = e2eActiveTermId(scenario.installationId);
  await seedSql([
    {
      sql: `INSERT OR REPLACE INTO coverage_mirror (
              installation_id, org_id, binding_epoch, clinic_seq,
              state, suspended, hard_stop_at, term_snapshot
            ) VALUES (?, ?, 0, 0, 'active', 0, ?, ?)`,
      params: [
        scenario.installationId,
        scenario.orgId,
        hardStopAt,
        JSON.stringify({
          ref: termId,
          capabilities: [CAPABILITY_ID],
        }),
      ],
    },
  ]);
}

/** Align `coverage_mirror.term_snapshot.capabilities` with entitlement stage-5 checks. */
export async function setMirrorCapabilities(
  scenario: Scenario,
  capabilities: string[],
): Promise<void> {
  const termId = e2eActiveTermId(scenario.installationId);
  await seedSql([
    {
      sql: `UPDATE coverage_mirror SET term_snapshot = ? WHERE installation_id = ?`,
      params: [
        JSON.stringify({ ref: termId, capabilities }),
        scenario.installationId,
      ],
    },
  ]);
  clearConfigCache();
}

/** HTTP admission reads the DO hot/term tables; grant alone may not populate them synchronously. */
export async function ensureE2eQuotaDoCoverage(
  scenario: Scenario,
  opts: E2eQuotaSeedOptions = {},
): Promise<void> {
  const periodStart = opts.period_start ?? DEFAULT_PERIOD_START;
  const periodEnd = opts.period_end ?? DEFAULT_PERIOD_END;
  const requestQuota = opts.request_quota ?? DEFAULT_REQUEST_QUOTA;

  await gatewayObjectJson(scenario.installationId, { kind: "inspect" });
  const termId = e2eActiveTermId(scenario.installationId);
  const planSnapshot = JSON.stringify({
    capabilities: [CAPABILITY_ID],
    max_cost_class: "standard",
    concurrency_limit: 16,
  });

  await runInDurableObject(
    env.DO.get(env.DO.idFromName(scenario.installationId)),
    async (_instance, state) => {
      const storage = state.storage as DurableObjectStorage & {
        sql?: { exec: (query: string) => Iterable<Record<string, unknown>> };
      };
      if (!storage.sql) {
        throw new Error("quota DO sql storage unavailable for e2e seed");
      }
      const hotExists = [...storage.sql.exec("SELECT 1 AS ok FROM hot LIMIT 1")];
      if (hotExists.length === 0) {
        storage.sql.exec(
          `INSERT INTO hot (
             suspended, transferred_out_to, awaiting_transfer, transfer_pending,
             active_term_id, used, reserved, grace_base_used, reservations, replay,
             idempotency, band_emitted, binding_epoch, clinic_seq, next_alarm_at
           ) VALUES (
             0, NULL, 0, 0, ${sqlLiteral(termId)}, 0, 0, 0, '[]', '{}', '{}', '{}', 0, 0, NULL
           )`,
        );
      } else {
        storage.sql.exec(
          `UPDATE hot SET active_term_id = ${sqlLiteral(termId)}, suspended = 0`,
        );
      }
      const termExists = [
        ...storage.sql.exec(
          `SELECT 1 AS ok FROM term WHERE term_id = ${sqlLiteral(termId)} LIMIT 1`,
        ),
      ];
      if (termExists.length === 0) {
        storage.sql.exec(
          `INSERT INTO term (
             term_id, grant_id, origin_grant_id, position, state, end_reason,
             plan_snapshot, allowance, used_final, duration_unit, duration_count,
             grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at, ended_at
           ) VALUES (
             ${sqlLiteral(termId)}, 'e2e-seed', 'e2e-seed', 0, 'active', NULL,
             ${sqlLiteral(planSnapshot)}, ${requestQuota},
             NULL, 'month', 1, 0, 'proportional',
             ${sqlLiteral(periodStart)}, ${sqlLiteral(periodStart)},
             ${sqlLiteral(periodEnd)}, NULL, NULL
           )`,
        );
      }
    },
  );
}
