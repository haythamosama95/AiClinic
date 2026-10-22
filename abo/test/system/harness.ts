/**
 * H-ABO system-test harness (P4.1).
 */

import { env, SELF } from "cloudflare:test";
import { createIssuer } from "vendor-contracts/testkit";
import recordsMigrationSql from "../../migrations/0001_records.sql?raw";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import notifyWorkMigrationSql from "../../migrations/0003_notify_work.sql?raw";
import grantMigrationSql from "../../migrations/0004_grant.sql?raw";
import reversalMigrationSql from "../../migrations/0005_reversal.sql?raw";
import operatorActionMigrationSql from "../../migrations/0006_operator_action.sql?raw";
import hpActionsMigrationSql from "../../migrations/0007_hp_actions.sql?raw";
import reconciliationMigrationSql from "../../migrations/0008_reconciliation.sql?raw";
import digestWatchMigrationSql from "../../migrations/0009_digest_watch.sql?raw";
import workLeaseTokenMigrationSql from "../../migrations/0010_work_lease_token.sql?raw";
import checkoutCreationAttemptsMigrationSql from "../../migrations/0011_checkout_creation_attempts.sql?raw";
import acceptedCommandsErasureFenceMigrationSql from "../../migrations/0012_accepted_commands_erasure_fence.sql?raw";
import notificationProviderTxnIdMigrationSql from "../../migrations/0013_notification_provider_txn_id.sql?raw";
import grantOutcomeEventsMigrationSql from "../../migrations/0014_grant_outcome_events.sql?raw";
import reversalRequestMigrationSql from "../../migrations/0015_reversal_request.sql?raw";
import rebuildCheckpointMigrationSql from "../../migrations/0016_rebuild_checkpoint.sql?raw";
import commandRecoveryFactsMigrationSql from "../../migrations/0017_command_recovery_facts.sql?raw";
import rebuildPublicationFenceMigrationSql from "../../migrations/0018_rebuild_publication_fence.sql?raw";
import secretlessCreatedAttemptsMigrationSql from "../../migrations/0019_secretless_created_attempts.sql?raw";
import recoveryProvenanceAndInquiriesMigrationSql from "../../migrations/0020_recovery_provenance_and_inquiries.sql?raw";
import scheduledJobStateMigrationSql from "../../migrations/0021_scheduled_job_state.sql?raw";
import findingIdentityMigrationSql from "../../migrations/0022_finding_identity.sql?raw";
import payoutImportFileIdentityMigrationSql from "../../migrations/0023_payout_import_file_identity.sql?raw";
import payoutLineReversalIdentityMigrationSql from "../../migrations/0024_payout_line_reversal_identity.sql?raw";
import reversalProviderIdentityMigrationSql from "../../migrations/0025_reversal_provider_identity.sql?raw";
import payoutReversalManualLinkMigrationSql from "../../migrations/0026_payout_reversal_manual_link.sql?raw";

const ABO_LEGACY_MIGRATION_SQL: string[] = [
  recordsMigrationSql,
  checkoutMigrationSql,
  notifyWorkMigrationSql,
  grantMigrationSql,
  reversalMigrationSql,
  operatorActionMigrationSql,
  hpActionsMigrationSql,
  reconciliationMigrationSql,
  digestWatchMigrationSql,
];
const ABO_MIGRATION_SQL: string[] = [
  ...ABO_LEGACY_MIGRATION_SQL,
  workLeaseTokenMigrationSql,
  checkoutCreationAttemptsMigrationSql,
  acceptedCommandsErasureFenceMigrationSql,
  notificationProviderTxnIdMigrationSql,
  grantOutcomeEventsMigrationSql,
  reversalRequestMigrationSql,
  rebuildCheckpointMigrationSql,
  commandRecoveryFactsMigrationSql,
  rebuildPublicationFenceMigrationSql,
  secretlessCreatedAttemptsMigrationSql,
  recoveryProvenanceAndInquiriesMigrationSql,
  scheduledJobStateMigrationSql,
  findingIdentityMigrationSql,
  payoutImportFileIdentityMigrationSql,
  payoutLineReversalIdentityMigrationSql,
  reversalProviderIdentityMigrationSql,
  payoutReversalManualLinkMigrationSql,
];

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

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    BILLING_HOST: string;
    OPS_HOST: string;
    HEARTBEAT_URL: string;
    HEARTBEAT_URL_MINUTE?: string;
    HEARTBEAT_URL_DIGEST?: string;
    ALERT_EMAIL_TO: string;
    ISSUER_ID: string;
    ISSUER_KEYS: string;
    CLOUDFLARE_ACCOUNT_ID: string;
    R2_BUCKET_NAME: string;
    R2_LOCK_READ_TOKEN: string;
    TEST_CLOCK: string;
    PAYMOB_STUB: Fetcher;
    PAYMOB_BASE_URL: string;
    PAYMOB_HMAC_SECRET: string;
    PAYMOB_API_KEY: string;
    SEND_EMAIL: {
      send(message: {
        from: string;
        to: string;
        subject: string;
        text: string;
      }): Promise<void>;
    };
  }
}

export const BILLING_ORIGIN = `https://${env.BILLING_HOST}`;
export const OPS_ORIGIN = `https://${env.OPS_HOST}`;

const DEFAULT_LOCK_BODY = {
  success: true,
  result: {
    rules: [
      {
        enabled: true,
        condition: { type: "Indefinite" },
        prefix: "ledger/",
      },
    ],
  },
};

let lockRulesBody: unknown = DEFAULT_LOCK_BODY;
let lockMockReady = false;

const heartbeatHarness = {
  capturedFetches: [] as string[],
  fetchThrows: false,
  interceptReady: false,
};

export const harnessState = {
  capturedEmails: [] as Array<{
    from: string;
    to: string;
    subject: string;
    text: string;
  }>,
  sendEmailThrows: false,
};

export const sendEmailBinding = {
  async send(message: {
    from: string;
    to: string;
    subject: string;
    text: string;
  }): Promise<void> {
    if (harnessState.sendEmailThrows) {
      throw new Error("send_email failure injected by harness");
    }
    harnessState.capturedEmails.push({ ...message });
  },
};

function splitSqlStatements(sql: string): string[] {
  const statements: string[] = [];
  let start = 0;
  let index = 0;
  let beginDepth = 0;
  let caseDepth = 0;

  const pushStatement = (end: number): void => {
    const chunk = sql.slice(start, end).trim();
    if (chunk.length > 0) {
      statements.push(chunk);
    }
    start = end;
  };

  while (index < sql.length) {
    const char = sql[index];
    const next = sql[index + 1];
    if (char === "'" || char === '"' || char === "`" || char === "[") {
      const quoteEnd = char === "[" ? "]" : char;
      index += 1;
      while (index < sql.length) {
        if (sql[index] === quoteEnd) {
          if (quoteEnd !== "]" && sql[index + 1] === quoteEnd) {
            index += 2;
            continue;
          }
          index += 1;
          break;
        }
        index += 1;
      }
      continue;
    }
    if (char === "-" && next === "-") {
      index += 2;
      while (index < sql.length && sql[index] !== "\n") index += 1;
      continue;
    }
    if (char === "/" && next === "*") {
      index += 2;
      while (
        index < sql.length &&
        !(sql[index] === "*" && sql[index + 1] === "/")
      ) {
        index += 1;
      }
      index = Math.min(sql.length, index + 2);
      continue;
    }
    if (/[A-Za-z_]/.test(char)) {
      const wordStart = index;
      index += 1;
      while (index < sql.length && /[A-Za-z0-9_$]/.test(sql[index])) index += 1;
      const word = sql.slice(wordStart, index).toUpperCase();
      if (word === "BEGIN") beginDepth += 1;
      else if (word === "CASE") caseDepth += 1;
      else if (word === "END") {
        if (caseDepth > 0) caseDepth -= 1;
        else if (beginDepth > 0) {
          beginDepth -= 1;
          if (beginDepth === 0) {
            let end = index;
            while (end < sql.length && /\s/.test(sql[end])) end += 1;
            if (sql[end] === ";") pushStatement(end + 1);
          }
        }
      }
      continue;
    }
    if (char === ";" && beginDepth === 0) {
      index += 1;
      pushStatement(index);
      continue;
    }
    index += 1;
  }

  pushStatement(sql.length);
  return statements;
}

export async function applySql(sql: string): Promise<void> {
  for (const statement of splitSqlStatements(sql)) {
    try {
      await env.DB.prepare(statement).run();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!/already exists/i.test(message)) {
        throw error;
      }
    }
  }
}

export async function applyAllAboMigrations(): Promise<void> {
  await applyMigrations(ABO_MIGRATION_SQL);
}

/** Apply the schema immediately before the work-lease-token forward migration. */
export async function applyLegacyAboMigrations(): Promise<void> {
  await applyMigrations(ABO_LEGACY_MIGRATION_SQL);
}

async function applyMigrations(migrations: readonly string[]): Promise<void> {
  for (const sql of migrations) {
    try {
      await applySql(sql);
    } catch {
      // Migration not added yet.
    }
  }
}

export async function applyRecordsMigration(): Promise<void> {
  await applyAllAboMigrations();
}

async function ensureHarnessSchema(): Promise<void> {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS harness_test_clock (
       id TEXT PRIMARY KEY,
       now_iso TEXT NOT NULL
     )`,
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS harness_issuer_pin (
       kid TEXT PRIMARY KEY,
       public_key TEXT NOT NULL
     )`,
  ).run();
}

export async function setClock(isoUtc: string): Promise<void> {
  await ensureHarnessSchema();
  await env.DB.prepare(
    `INSERT OR REPLACE INTO harness_test_clock (id, now_iso) VALUES ('default', ?)`,
  )
    .bind(isoUtc)
    .run();
}

/**
 * Seconds on the ABO harness clock (the same `harness_test_clock` row the
 * worker's `clockNowMs` reads), falling back to wall time. Billing tokens must
 * be minted relative to this clock so `authenticateBilling` accepts them
 * regardless of any fixed clock a test installs (R1-C1).
 */
export async function harnessClockNowSeconds(): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT now_iso FROM harness_test_clock WHERE id = 'default'`,
    ).first<{ now_iso: string }>();
    if (row?.now_iso) {
      const parsed = Date.parse(row.now_iso);
      if (!Number.isNaN(parsed)) {
        return Math.floor(parsed / 1000);
      }
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!/no such table/i.test(message)) {
      throw error;
    }
  }
  return Math.floor(Date.now() / 1000);
}

export async function pinIssuer(
  kid: string,
  publicKey: CryptoKey,
): Promise<void> {
  await ensureHarnessSchema();
  const raw = await crypto.subtle.exportKey("raw", publicKey);
  const publicKeyB64 = base64UrlEncode(new Uint8Array(raw));
  await env.DB.prepare(
    `INSERT OR REPLACE INTO harness_issuer_pin (kid, public_key) VALUES (?, ?)`,
  )
    .bind(kid, publicKeyB64)
    .run();
}

export function billingFetch(
  path: string,
  init?: RequestInit,
): Promise<Response> {
  return SELF.fetch(
    new Request(`${BILLING_ORIGIN}${path}`, {
      ...init,
      headers: init?.headers,
    }),
  );
}

export function opsFetch(path: string, init?: RequestInit): Promise<Response> {
  return SELF.fetch(
    new Request(`${OPS_ORIGIN}${path}`, {
      ...init,
      headers: init?.headers,
    }),
  );
}

export async function newIssuer() {
  return createIssuer({ issuerId: env.ISSUER_ID });
}

export async function mintBilling(
  issuer: Awaited<ReturnType<typeof newIssuer>>,
  claims: {
    sub: string;
    org: string;
    role: string;
    branch: string;
    iat: number;
    exp: number;
    jti: string;
  },
): Promise<string> {
  return issuer.mintBilling(claims);
}

export async function mintAi(
  issuer: Awaited<ReturnType<typeof newIssuer>>,
  claims: {
    sub: string;
    org: string;
    role: string;
    branch: string;
    scopes: string[];
    iat: number;
    exp: number;
    jti: string;
  },
): Promise<string> {
  return issuer.mintAi(claims);
}

export async function r2Put(key: string, body: string): Promise<void> {
  await env.R2.put(key, body);
}

export async function r2GetText(key: string): Promise<string | null> {
  const object = await env.R2.get(key);
  if (!object) {
    return null;
  }
  return object.text();
}

export function setLockRulesBody(body: unknown): void {
  lockRulesBody = body;
}

async function ensureLockRulesMock(): Promise<void> {
  if (lockMockReady) {
    return;
  }
  const { fetchMock } = await import("cloudflare:test");
  const accountId = env.CLOUDFLARE_ACCOUNT_ID;
  const bucketName = env.R2_BUCKET_NAME;
  const path = `/client/v4/accounts/${accountId}/r2/buckets/${bucketName}/lock`;
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock
    .get("https://api.cloudflare.com")
    .intercept({ path, method: "GET" })
    .reply(() => ({
      statusCode: 200,
      data: JSON.stringify(lockRulesBody),
    }))
    .persist();
  lockMockReady = true;
}

// R9-CRON1 / RT2: every configured stream URL is intercepted, so a capture names the stream
// that pinged. The shared HEARTBEAT_URL is included as the fallback.
function configuredHeartbeatUrls(): string[] {
  const urls = [
    env.HEARTBEAT_URL,
    env.HEARTBEAT_URL_MINUTE,
    env.HEARTBEAT_URL_DIGEST,
  ].filter((url): url is string => typeof url === "string" && url.length > 0);
  return [...new Set(urls)];
}

async function ensureHeartbeatFetchMock(): Promise<void> {
  if (heartbeatHarness.interceptReady) {
    return;
  }
  const { fetchMock } = await import("cloudflare:test");
  await ensureLockRulesMock();
  for (const heartbeatUrl of configuredHeartbeatUrls()) {
    const parsed = new URL(heartbeatUrl);
    fetchMock
      .get(parsed.origin)
      .intercept({ path: parsed.pathname, method: "GET" })
      .reply(() => {
        heartbeatHarness.capturedFetches.push(heartbeatUrl);
        if (heartbeatHarness.fetchThrows) {
          throw new Error("heartbeat fetch failure injected by harness");
        }
        return { statusCode: 200, data: "ok" };
      })
      .persist();
  }
  heartbeatHarness.interceptReady = true;
}

export function setSendEmailThrows(throws: boolean): void {
  harnessState.sendEmailThrows = throws;
}

export function setHeartbeatFetchThrows(throws: boolean): void {
  heartbeatHarness.fetchThrows = throws;
}

export function clearCapturedHeartbeatFetches(): void {
  heartbeatHarness.capturedFetches.length = 0;
}

export function getCapturedHeartbeatFetches(): ReadonlyArray<string> {
  return heartbeatHarness.capturedFetches;
}

export function clearCapturedEmails(): void {
  harnessState.capturedEmails.length = 0;
}

export function getCapturedEmails(): ReadonlyArray<{
  from: string;
  to: string;
  subject: string;
  text: string;
}> {
  return harnessState.capturedEmails;
}

let paymobMockReady = false;
let intakeR2PutThrows = false;
let intakeR2PutAfterHook: (() => Promise<void>) | null = null;
let d1BatchThrows = false;
let d1SuccessfulBatchesBeforeThrow = 0;
let r2PutWrapped = false;
let dbBatchWrapped = false;

export type PaymobInquiryScript =
  | "bound_success"
  | "unbound"
  | "amount_mismatch"
  | "currency_mismatch"
  | "reversed"
  | "pending"
  | "timeout"
  | "rate_limit";

async function ensurePaymobFetchMock(): Promise<void> {
  if (paymobMockReady) {
    return;
  }
  const { fetchMock } = await import("cloudflare:test");
  const baseUrl = env.PAYMOB_BASE_URL;
  const origin = new URL(baseUrl).origin;
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock
    .get(origin)
    .intercept({ path: () => true, method: () => true })
    .reply(async (opts) => {
      try {
        const pathPart = typeof opts.path === "string" ? opts.path : "/";
        const target = new URL(pathPart, baseUrl).toString();
        const response = await env.PAYMOB_STUB.fetch(target, {
          method: opts.method,
          headers: opts.headers as HeadersInit | undefined,
          body: opts.body as BodyInit | undefined,
          signal: opts.signal as AbortSignal | undefined,
        });
        const data = await response.arrayBuffer();
        return {
          statusCode: response.status,
          data: new TextDecoder().decode(data),
        };
      } catch {
        return { statusCode: 502, data: "paymob stub forward failed" };
      }
    })
    .persist();
  paymobMockReady = true;
}

function ensureR2PutWrapper(): void {
  if (r2PutWrapped) {
    return;
  }
  const originalPut = env.R2.put.bind(env.R2);
  env.R2.put = async (
    key: string,
    value:
      | ReadableStream
      | ArrayBuffer
      | ArrayBufferView
      | string
      | null
      | Blob,
    options?: R2PutOptions,
  ): Promise<R2Object | null> => {
    if (intakeR2PutThrows) {
      intakeR2PutThrows = false;
      throw new Error("R2 put failure injected by harness");
    }
    const result = await originalPut(key, value, options);
    const afterHook = intakeR2PutAfterHook;
    intakeR2PutAfterHook = null;
    if (afterHook !== null) await afterHook();
    return result;
  };
  r2PutWrapped = true;
}

function ensureD1BatchWrapper(): void {
  if (dbBatchWrapped) {
    return;
  }
  const originalBatch = env.DB.batch.bind(env.DB);
  env.DB.batch = async (
    statements: D1PreparedStatement[],
  ): Promise<D1Result[]> => {
    if (d1BatchThrows) {
      if (d1SuccessfulBatchesBeforeThrow === 0) {
        d1BatchThrows = false;
        throw new Error("D1 batch failure injected by harness");
      }
      d1SuccessfulBatchesBeforeThrow -= 1;
    }
    return originalBatch(statements);
  };
  dbBatchWrapped = true;
}

export function setIntakeR2PutThrows(active: boolean): void {
  intakeR2PutThrows = active;
  ensureR2PutWrapper();
}

export function setIntakeR2PutAfterHook(hook: (() => Promise<void>) | null): void {
  intakeR2PutAfterHook = hook;
  ensureR2PutWrapper();
}

export function setD1BatchThrows(
  active: boolean,
  successfulBatchesBeforeThrow = 0,
): void {
  d1BatchThrows = active;
  d1SuccessfulBatchesBeforeThrow = active
    ? Math.max(0, Math.floor(successfulBatchesBeforeThrow))
    : 0;
  ensureD1BatchWrapper();
}

export async function scriptPaymobInquiry(
  script: PaymobInquiryScript,
  amountCents?: number | string,
  refundedAmountCents?: number | string,
): Promise<void> {
  await env.PAYMOB_STUB.fetch("http://paymob.stub/__script", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      inquiry: script,
      amount_cents: amountCents,
      refunded_amount_cents: refundedAmountCents,
    }),
  });
}

export async function runScheduled(cron: string): Promise<void> {
  await ensureHeartbeatFetchMock();
  const workerModule = await import("../../src/worker");
  await workerModule.default.scheduled(
    { cron, scheduledTime: Date.now(), noRetry() { } },
    env as never,
    {} as ExecutionContext,
  );
}

export async function tableCount(table: string): Promise<number> {
  try {
    const row = await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first<{
      n: number;
    }>();
    return row?.n ?? 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return 0;
    }
    throw error;
  }
}

export async function setupHarness(): Promise<void> {
  await applyRecordsMigration();
  await ensureHarnessSchema();
  await ensureHeartbeatFetchMock();
  await ensurePaymobFetchMock();
  Object.assign(env.SEND_EMAIL, sendEmailBinding);
  lockRulesBody = DEFAULT_LOCK_BODY;
  harnessState.sendEmailThrows = false;
  heartbeatHarness.fetchThrows = false;
  intakeR2PutThrows = false;
  intakeR2PutAfterHook = null;
  d1BatchThrows = false;
  d1SuccessfulBatchesBeforeThrow = 0;
  clearCapturedEmails();
  clearCapturedHeartbeatFetches();
  await setClock(new Date().toISOString());
  try {
    await scriptPaymobInquiry("bound_success");
  } catch {
    // PAYMOB_STUB binding not configured yet.
  }
}

export async function resetHarnessState(): Promise<void> {
  await setupHarness();
  await env.DB.prepare("DELETE FROM harness_test_clock").run();
  await env.DB.prepare("DELETE FROM harness_issuer_pin").run();
  for (const table of [
    "scheduled_job_state",
    "housekeeping_r2_cursor",
    "finding_identity",
    "token_use",
    "billing_contact",
    "org_erasure_fence",
    "raw_evidence_registry",
    "raw_evidence_cleanup_outbox",
  ]) {
    try {
      await env.DB.prepare(`DELETE FROM ${table}`).run();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!/no such table/i.test(message)) {
        throw error;
      }
    }
  }
  await setClock(new Date().toISOString());
}
