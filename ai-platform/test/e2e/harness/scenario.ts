import { runInDurableObject } from "cloudflare:test";
import { generateTestKeypair } from "./crypto";
import {
  canaryPolicy,
  DEFAULT_ENTITLE_PAYLOAD,
  newClinic,
  entitleInstallation,
  fakePolicyDocument,
  promotePolicy,
  publishPolicy,
  type EntitlePayload,
} from "./control";
import { seedSql } from "./d1";
import { env, CAPABILITY_ID, POLICY_ID, POLICY_VERSION } from "./env";
import { gatewayObjectJson } from "./gateway-object";
import type { Scenario } from "./types";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

function e2eActiveTermId(installationId: string): string {
  return `term-${installationId.slice(0, 8)}`;
}

function sqlLiteral(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

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

/** HTTP admission reads the DO hot/term tables; entitle alone does not populate them. */
export async function ensureE2eQuotaDoCoverage(
  scenario: Scenario,
  entitle: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<void> {
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
             ${sqlLiteral(planSnapshot)}, ${entitle.request_quota},
             NULL, 'month', 1, 0, 'proportional',
             ${sqlLiteral(entitle.period_start)}, ${sqlLiteral(entitle.period_start)},
             ${sqlLiteral(entitle.period_end)}, NULL, NULL
           )`,
        );
      }
    },
  );
}

export type { Scenario };

export async function newScenario(): Promise<Scenario> {
  const kid = crypto.randomUUID();
  const keypair = await generateTestKeypair(kid);
  return {
    installationId: crypto.randomUUID(),
    orgId: crypto.randomUUID(),
    branchId: crypto.randomUUID(),
    actorId: crypto.randomUUID(),
    kid,
    keypair,
  };
}

/**
 * Issuer-token clinic setup (`newClinic`) + entitle + publish/promote a
 * fake-provider routing policy. Use this to build prior state for clinic-facing
 * journeys. Not `[SEED]`.
 */
export async function provisionHappyPath(
  scenario?: Scenario,
  entitle: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<Scenario> {
  const ready = scenario ?? (await newScenario());
  await newClinic(ready);
  const entitled = await entitleInstallation(ready, entitle);
  if (entitled.status !== 200) {
    throw new Error(
      `provisionHappyPath: entitle failed (${entitled.status}): ${entitled.text}`,
    );
  }
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  if (published.status !== 200) {
    throw new Error(
      `provisionHappyPath: publish failed (${published.status}): ${published.text}`,
    );
  }
  const promoted = await promotePolicy(POLICY_ID, POLICY_VERSION);
  if (promoted.status !== 200) {
    throw new Error(
      `provisionHappyPath: promote failed (${promoted.status}): ${promoted.text}`,
    );
  }
  await ensureE2eCoverageMirror(ready);
  await ensureE2eQuotaDoCoverage(ready, entitle);
  return ready;
}

export { CAPABILITY_ID, canaryPolicy };
