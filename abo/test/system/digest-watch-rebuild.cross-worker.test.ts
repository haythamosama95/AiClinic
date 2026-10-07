/**
 * P4.11 — daily digest, platform watch, housekeeping, and ABO rebuild (H-XW),
 * E2E-P4.11-01 through E2E-P4.11-07.
 */

import { env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  CHANNEL_VERSIONS,
  grantIdComp,
  grantIdPaid,
  grantIdTransfer,
  sha256Hex,
} from "vendor-contracts";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import notifyWorkMigrationSql from "../../migrations/0003_notify_work.sql?raw";
import grantMigrationSql from "../../migrations/0004_grant.sql?raw";
import reversalMigrationSql from "../../migrations/0005_reversal.sql?raw";
import operatorActionMigrationSql from "../../migrations/0006_operator_action.sql?raw";
import hpActionsMigrationSql from "../../migrations/0007_hp_actions.sql?raw";
import reconciliationMigrationSql from "../../migrations/0008_reconciliation.sql?raw";
import {
  applySql,
  clearCapturedEmails,
  clearCapturedHeartbeatFetches,
  getCapturedEmails,
  getCapturedHeartbeatFetches,
  harnessState,
  newIssuer,
  pinIssuer,
  runScheduled,
  sendEmailBinding,
} from "./harness";
import {
  drainPlatformDurableObjects,
  resetCrossWorkerHarness,
  setClock,
  setupCrossWorkerHarness,
} from "./cross-worker-harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const VENDOR_OPERATOR_EMAIL = "operator@vendor.test";
const DIGEST_OPERATOR = "digest.operator@vendor.test";
const PLAN_ID = "plan-pro";
const PLAN_VERSION = 1;
const ALLOWANCE_CREDITS = 100;

const ORG_DIGEST = "a4110001-0001-4011-8011-000000000001";
const BASE_CLOCK = "2026-06-15T06:00:00.000Z";
const BACKEND_LAST_PULL = "2026-06-15T05:54:00.000Z";
const DAILY_JOB_STAMP = "2026-06-14T06:00:00.000Z";
const HOURLY_JOB_STAMP = "2026-06-15T05:00:00.000Z";
const MINUTE_JOB_STAMP = "2026-06-15T05:59:00.000Z";

const DIGEST_WATCH_SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS scheduled_job_run (
  job TEXT PRIMARY KEY,
  last_run_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS seen_operator_credential (
  credential_id TEXT NOT NULL,
  public_key_cose TEXT NOT NULL,
  alg TEXT NOT NULL,
  PRIMARY KEY (credential_id, public_key_cose, alg)
);
CREATE TABLE IF NOT EXISTS channel_version_seen (
  channel TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  received INTEGER NOT NULL,
  unsupported INTEGER NOT NULL,
  PRIMARY KEY (channel, contract_version)
);
`;

declare module "cloudflare:test" {
  interface ProvidedEnv {
    PLATFORM_DB: D1Database;
    HEARTBEAT_URL: string;
    ISSUER_ID: string;
    ALERT_EMAIL_TO: string;
  }
}

function addDays(isoUtc: string, days: number): string {
  return new Date(Date.parse(isoUtc) + days * 24 * 60 * 60_000).toISOString();
}

function addHours(isoUtc: string, hours: number): string {
  return new Date(Date.parse(isoUtc) + hours * 60 * 60_000).toISOString();
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

async function ensureMigrations(): Promise<void> {
  for (const sql of [
    checkoutMigrationSql,
    notifyWorkMigrationSql,
    grantMigrationSql,
    reversalMigrationSql,
    operatorActionMigrationSql,
    hpActionsMigrationSql,
    reconciliationMigrationSql,
  ]) {
    try {
      await applySql(sql);
    } catch {
      // Migration not present yet.
    }
  }
}

async function ensureDigestWatchMigration(): Promise<void> {
  await applySql(DIGEST_WATCH_SCHEMA_SQL);
  try {
    await env.DB.prepare(`ALTER TABLE fact_log ADD COLUMN row_json TEXT`).run();
  } catch {
    // Column already present.
  }
}

async function seedBackendFeedPull(lastPullAt: string): Promise<void> {
  await env.PLATFORM_DB.prepare(
    `INSERT INTO feed_consumer (consumer, last_pull_at, last_cursor)
     VALUES ('backend-feed', ?, 42)
     ON CONFLICT(consumer) DO UPDATE SET
       last_pull_at = excluded.last_pull_at,
       last_cursor = excluded.last_cursor`,
  )
    .bind(lastPullAt)
    .run();
}

async function rowExists(
  table: string,
  idColumn: string,
  id: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 AS ok FROM ${table} WHERE ${idColumn} = ?`,
  )
    .bind(id)
    .first<{ ok: number }>();
  return row !== null;
}

type DigestScenario = {
  paidGrantId: string;
  complimentaryGrantId: string;
  adjustmentGrantId: string;
  transferGrantId: string;
  openFindingId: string;
  parkedWorkId: string;
  openAlertKey: string;
  exportLagFactSeq: number;
};

async function buildGrantEnvelope(input: {
  grantId: string;
  orgId: string;
  sourceKind: "paid" | "complimentary" | "transfer";
  operatorEmail: string;
  reason: string;
  dayCount: number;
  adjustment?: Record<string, unknown>;
}): Promise<string> {
  const contentSha256 = await sha256Hex(
    new TextEncoder().encode(input.grantId),
  );
  const envelope: Record<string, unknown> = {
    contract_version: CONTRACT_VERSION,
    grant_id: input.grantId,
    org_id: input.orgId,
    kind: input.adjustment ? "term_adjustment" : "term",
    placement: "queue",
    source: {
      kind: input.sourceKind,
      ref: input.grantId,
      operator_email: input.operatorEmail,
      reason: input.reason,
    },
    plan: { plan_id: PLAN_ID, plan_version: PLAN_VERSION },
    duration: { unit: "day", count: input.dayCount },
    allowance_credits: ALLOWANCE_CREDITS,
    grace: { days: 7, cap_rule: "proportional" },
    evidence: {
      content_sha256: contentSha256,
      approvals: [{ credential_id: "digest-cred", assertion: "stub" }],
    },
  };
  if (input.adjustment !== undefined) {
    envelope.adjustment = input.adjustment;
  }
  return JSON.stringify(envelope);
}

async function seedDigestScenario(): Promise<DigestScenario> {
  const checkoutOpenedAt = addHours(BASE_CLOCK, -12);
  const paymentPaidAt = addHours(BASE_CLOCK, -10);
  const checkoutId = "01JDIGESTCHECKOUT00001";
  const paymentId = await grantIdPaid("pay-digest-0001");
  const paidGrantId = await grantIdPaid(paymentId);
  const complimentaryGrantId = await grantIdComp("digest-comp-01");
  const adjustmentGrantId = await grantIdComp("digest-adj-01");
  const transferId = crypto.randomUUID();
  const transferGrantId = await grantIdTransfer(transferId, 0);
  const openFindingId = "finding-digest-open-01";
  const parkedWorkId = "work-digest-parked-01";
  const openAlertKey = "AL-99:digest-open";

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO checkout (
         checkout_id, reference, org_id, created_by_sub, billing_token_jti,
         client_request_id, offer_id, offer_version, plan_id, plan_version,
         term_unit, term_count, allowance_credits, grace_days, grace_cap_rule,
         list_price_minor, charged_price_minor, adjustment_id, currency,
         terms_version, billing_contact_version, billing_contact_sha256,
         opened_with_coverage_through, coverage_source, provider_id, initiator,
         expires_at, contract_version
       ) VALUES (?, 'ref-digest', ?, 'sub-digest', 'jti-digest', 'req-digest',
         'offer-digest', 1, ?, ?, 'month', 1, ?, 7, 'proportional',
         10000, 10000, NULL, 'EGP', 1, 1, 'sha-contact', NULL, 'none',
         'paymob', 'clinic', ?, ?)`,
    ).bind(
      checkoutId,
      ORG_DIGEST,
      PLAN_ID,
      PLAN_VERSION,
      ALLOWANCE_CREDITS,
      addHours(BASE_CLOCK, 24),
      CONTRACT_VERSION,
    ),
    env.DB.prepare(
      `INSERT INTO checkout_event (
         checkout_id, kind, source, ref, actor, at, contract_version
       ) VALUES (?, 'opened', 'clinic', 'ref-digest', 'sub-digest', ?, ?)`,
    ).bind(checkoutId, checkoutOpenedAt, CONTRACT_VERSION),
    env.DB.prepare(
      `INSERT INTO checkout_status (checkout_id, state, last_event_at)
       VALUES (?, 'open', ?)`,
    ).bind(checkoutId, checkoutOpenedAt),
    env.DB.prepare(
      `INSERT INTO payment (
         payment_id, reference, org_id, checkout_id, provider_id, amount_minor,
         currency, paid_at, confirmed_at, confirmation_inquiry_id, offer_id,
         offer_version, billing_contact_version, classification, disposition,
         mismatch_detail, evidence_sha256
       ) VALUES (?, 'pay-ref', ?, ?, 'paymob', 10000, 'EGP', ?, ?, 'inq-1',
         'offer-digest', 1, 1, 'standard', 'matched', NULL, 'sha-evidence')`,
    ).bind(paymentId, ORG_DIGEST, checkoutId, paymentPaidAt, paymentPaidAt),
    env.DB.prepare(
      `INSERT INTO grant_request (
         grant_id, org_id, source_kind, source_ref, envelope, envelope_sha256, assertion
       ) VALUES (?, ?, 'paid', ?, ?, 'sha-paid', NULL)`,
    ).bind(
      paidGrantId,
      ORG_DIGEST,
      paymentId,
      await buildGrantEnvelope({
        grantId: paidGrantId,
        orgId: ORG_DIGEST,
        sourceKind: "paid",
        operatorEmail: DIGEST_OPERATOR,
        reason: "paid digest reason",
        dayCount: 30,
      }),
    ),
    env.DB.prepare(
      `INSERT INTO grant_request (
         grant_id, org_id, source_kind, source_ref, envelope, envelope_sha256, assertion
       ) VALUES (?, ?, 'complimentary', ?, ?, 'sha-comp', NULL)`,
    ).bind(
      complimentaryGrantId,
      ORG_DIGEST,
      "digest-comp-01",
      await buildGrantEnvelope({
        grantId: complimentaryGrantId,
        orgId: ORG_DIGEST,
        sourceKind: "complimentary",
        operatorEmail: DIGEST_OPERATOR,
        reason: "complimentary digest reason",
        dayCount: 14,
      }),
    ),
    env.DB.prepare(
      `INSERT INTO grant_request (
         grant_id, org_id, source_kind, source_ref, envelope, envelope_sha256, assertion
       ) VALUES (?, ?, 'complimentary', ?, ?, 'sha-adj', NULL)`,
    ).bind(
      adjustmentGrantId,
      ORG_DIGEST,
      "digest-adj-01",
      await buildGrantEnvelope({
        grantId: adjustmentGrantId,
        orgId: ORG_DIGEST,
        sourceKind: "complimentary",
        operatorEmail: DIGEST_OPERATOR,
        reason: "adjustment digest reason",
        dayCount: 21,
        adjustment: { extend_days: 7 },
      }),
    ),
    env.DB.prepare(
      `INSERT INTO grant_request (
         grant_id, org_id, source_kind, source_ref, envelope, envelope_sha256, assertion
       ) VALUES (?, ?, 'transfer', ?, ?, 'sha-transfer', NULL)`,
    ).bind(
      transferGrantId,
      ORG_DIGEST,
      transferId,
      await buildGrantEnvelope({
        grantId: transferGrantId,
        orgId: ORG_DIGEST,
        sourceKind: "transfer",
        operatorEmail: DIGEST_OPERATOR,
        reason: "transfer digest reason",
        dayCount: 30,
      }),
    ),
    env.DB.prepare(
      `INSERT INTO reversal (
         reversal_id, payment_id, reference, amount_minor, kind, is_full,
         source, cumulative_reversed_minor, detected_via, recorded_by,
         evidence_sha256, effect, dedupe_key
       ) VALUES (?, ?, 'rev-ref', 1000, 'refund', 0, 'provider', 1000,
         'inquiry', 'harness', 'sha-rev', 'partial', 'dedupe-digest-rev')`,
    ).bind("reversal-digest-01", paymentId),
    env.DB.prepare(
      `INSERT INTO finding (finding_id, kind, subject, detail, detected_at)
       VALUES (?, 'digest_probe', 'payment', 'open finding for digest', ?)`,
    ).bind(openFindingId, addHours(BASE_CLOCK, -2)),
    env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, last_error, opened_at
       ) VALUES (?, 'confirm', ?, 'dedupe-digest-work', 'open', 0, NULL, NULL, NULL, ?)`,
    ).bind(parkedWorkId, checkoutId, addHours(BASE_CLOCK, -1)),
    env.DB.prepare(
      `INSERT INTO alert (
         alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id
       ) VALUES (?, 'AL-99', 1, 0, ?, NULL, 'digest-open-alert')`,
    ).bind(openAlertKey, addHours(BASE_CLOCK, -3)),
    env.DB.prepare(
      `INSERT INTO scheduled_job_run (job, last_run_at) VALUES ('0 6 * * *', ?)`,
    ).bind(DAILY_JOB_STAMP),
    env.DB.prepare(
      `INSERT INTO scheduled_job_run (job, last_run_at) VALUES ('0 * * * *', ?)`,
    ).bind(HOURLY_JOB_STAMP),
    env.DB.prepare(
      `INSERT INTO scheduled_job_run (job, last_run_at) VALUES ('* * * * *', ?)`,
    ).bind(MINUTE_JOB_STAMP),
    env.DB.prepare(
      `INSERT INTO channel_version_seen (
         channel, contract_version, received, unsupported
       ) VALUES ('aboClinic', ?, 12, 2)`,
    ).bind(CONTRACT_VERSION),
    env.DB.prepare(
      `INSERT INTO channel_version_seen (
         channel, contract_version, received, unsupported
       ) VALUES ('aboConsole', ?, 8, 1)`,
    ).bind(CONTRACT_VERSION),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at)
       VALUES ('offer', 'offer-digest-lag', 'sha-lag', ?)`,
    ).bind(addHours(BASE_CLOCK, -3)),
  ]);

  const exportLagRow = await env.DB.prepare(
    `SELECT fact_seq FROM fact_log ORDER BY fact_seq DESC LIMIT 1`,
  ).first<{ fact_seq: number }>();

  await seedBackendFeedPull(BACKEND_LAST_PULL);

  return {
    paidGrantId,
    complimentaryGrantId,
    adjustmentGrantId,
    transferGrantId,
    openFindingId,
    parkedWorkId,
    openAlertKey,
    exportLagFactSeq: exportLagRow?.fact_seq ?? 0,
  };
}

function digestEmails(): ReadonlyArray<{
  from: string;
  to: string;
  subject: string;
  text: string;
}> {
  return getCapturedEmails().filter((message) => message.subject === "digest");
}

function emailsWithCode(code: string): ReadonlyArray<{
  from: string;
  to: string;
  subject: string;
  text: string;
}> {
  return getCapturedEmails().filter((message) => message.subject === code);
}

async function registerIssuerKeyExpiringInDays(
  daysAhead: number,
  kid = "digest-expiring-kid",
): Promise<void> {
  const issuer = await newIssuer();
  await pinIssuer(kid, issuer.publicKey);
  const rawPublicKey = await crypto.subtle.exportKey("raw", issuer.publicKey);
  const publicKeyB64 = base64UrlEncode(new Uint8Array(rawPublicKey));
  const notBefore = addDays(BASE_CLOCK, -30);
  const notAfter = addDays(BASE_CLOCK, daysAhead);
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO issuer_key
       (kid, issuer, public_key, status, not_before, not_after, registered_by, assertion_sha256)
     VALUES (?, ?, ?, 'active', ?, ?, ?, 'harness')`,
  )
    .bind(kid, env.ISSUER_ID, publicKeyB64, notBefore, notAfter, VENDOR_OPERATOR_EMAIL)
    .run();
}

let digestSendAttempts = 0;

function installDigestRetrySendBinding(): void {
  digestSendAttempts = 0;
  Object.assign(env.SEND_EMAIL, {
    async send(message: {
      from: string;
      to: string;
      subject: string;
      text: string;
    }): Promise<void> {
      if (message.subject === "digest") {
        digestSendAttempts += 1;
        if (digestSendAttempts === 1) {
          throw new Error("digest send failure injected by test");
        }
      }
      await sendEmailBinding.send(message);
    },
  });
}

describe("P4.11 digest, watch, housekeeping, rebuild (H-XW)", () => {
  beforeEach(async () => {
    await resetCrossWorkerHarness();
    await setupCrossWorkerHarness();
    await ensureMigrations();
    await ensureDigestWatchMigration();
    clearCapturedEmails();
    clearCapturedHeartbeatFetches();
    setSendEmailThrows(false);
    harnessState.sendEmailThrows = false;
    Object.assign(env.SEND_EMAIL, sendEmailBinding);
    await setClock(BASE_CLOCK);
  });

  afterEach(async () => {
    await drainPlatformDurableObjects();
  });

  it("E2E-P4.11-01 Digest after a scripted day lists the counts, every grant, open findings, job last-runs, export lag and version counts", async () => {
    const scenario = await seedDigestScenario();
    clearCapturedEmails();

    await runScheduled("0 6 * * *");

    expect(digestEmails()).toHaveLength(1);
    const body = digestEmails()[0]!.text;
    expect(body).toContain(scenario.paidGrantId);
    expect(body).toContain(scenario.complimentaryGrantId);
    expect(body).toContain(scenario.adjustmentGrantId);
    expect(body).toContain(scenario.transferGrantId);
    expect(body).toContain(DIGEST_OPERATOR);
    expect(body).toContain("complimentary digest reason");
    expect(body).toContain("adjustment digest reason");
    expect(body).toContain("transfer digest reason");
    expect(body).toContain("14");
    expect(body).toContain("21");
    expect(body).toContain(String(ALLOWANCE_CREDITS));
    expect(body).toContain(scenario.openFindingId);
    expect(body).toContain(scenario.parkedWorkId);
    expect(body).toContain(scenario.openAlertKey);
    expect(body).toContain(DAILY_JOB_STAMP);
    expect(body).toContain(HOURLY_JOB_STAMP);
    expect(body).toContain(MINUTE_JOB_STAMP);
    expect(body).toContain(BACKEND_LAST_PULL);
    expect(body).toContain(String(scenario.exportLagFactSeq));
    expect(body).toContain("aboClinic");
    expect(body).toContain("aboConsole");
    expect(body).toContain("12");
    expect(body).toContain("2");
    expect(body).toContain("8");
    expect(body).toContain("1");
  });

  it("E2E-P4.11-02 A25/FM-17: issuer key not_after within 29 days → AL-14 daily", async () => {
    await registerIssuerKeyExpiringInDays(29);
    clearCapturedEmails();

    await runScheduled("0 6 * * *");
    expect(emailsWithCode("AL-14").length).toBeGreaterThanOrEqual(1);

    await setClock(addDays(BASE_CLOCK, 1));
    clearCapturedEmails();
    await runScheduled("0 6 * * *");
    expect(emailsWithCode("AL-14").length).toBe(1);
  });

  it("E2E-P4.11-05 The ABO daily 06:00 UTC scheduled() cron (0 6 * * *) deletes 91-day-old done work rows and sent alerts; facts untouched", async () => {
    const oldOpenedAt = addDays(BASE_CLOCK, -91);
    const oldSentAt = addDays(BASE_CLOCK, -91);
    const workId = "work-digest-housekeeping-01";
    const alertKey = "AL-99:housekeeping-old";
    const factKey = "fact-digest-housekeeping-01";

    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO work (
           work_id, kind, subject_id, dedupe_key, state, attempts,
           next_attempt_at, lease_until, last_error, opened_at
         ) VALUES (?, 'confirm', 'chk-old', 'dedupe-housekeeping-work', 'done', 1,
           NULL, NULL, NULL, ?)`,
      ).bind(workId, oldOpenedAt),
      env.DB.prepare(
        `INSERT INTO alert (
           alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id
         ) VALUES (?, 'AL-99', 0, 0, ?, NULL, 'old-alert')`,
      ).bind(alertKey, oldSentAt),
      env.DB.prepare(
        `INSERT INTO fact_log ("table", key, row_sha256, created_at)
         VALUES ('payment', ?, 'sha-fact-housekeeping', ?)`,
      ).bind(factKey, oldOpenedAt),
    ]);

    await runScheduled("0 6 * * *");

    expect(await rowExists("work", "work_id", workId)).toBe(false);
    expect(await rowExists("alert", "alert_key", alertKey)).toBe(false);
    expect(await rowExists("fact_log", "key", factKey)).toBe(true);
  });

  it("E2E-P4.11-07 Digest send failure retried; daily heartbeat ping sent", async () => {
    await seedDigestScenario();
    installDigestRetrySendBinding();
    clearCapturedEmails();
    clearCapturedHeartbeatFetches();

    await runScheduled("0 6 * * *");

    expect(digestSendAttempts).toBe(2);
    expect(digestEmails()).toHaveLength(1);
    expect(getCapturedHeartbeatFetches()).toContain(env.HEARTBEAT_URL);
  });
});
