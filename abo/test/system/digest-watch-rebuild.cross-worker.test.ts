/**
 * P4.11 — daily digest, platform watch, housekeeping, and ABO rebuild (H-XW),
 * E2E-P4.11-01 through E2E-P4.11-07.
 */

import rebuildRunbookMd from "../../REBUILD.md?raw";
import { env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  canonicalize,
  CHANNEL_VERSIONS,
  grantIdComp,
  grantIdPaid,
  grantIdTransfer,
  sha256Hex,
} from "vendor-contracts";
import {
  createSoftwareAuthenticator,
  createPlatformReceiptSigner,
  type SoftwareAuthenticator,
} from "vendor-contracts/testkit";
import offersFixture from "../../fixtures/offers.json";
import successFixture from "../fixtures/paymob/success.json";
import recordsMigrationSql from "../../migrations/0001_records.sql?raw";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import notifyWorkMigrationSql from "../../migrations/0003_notify_work.sql?raw";
import grantMigrationSql from "../../migrations/0004_grant.sql?raw";
import reversalMigrationSql from "../../migrations/0005_reversal.sql?raw";
import operatorActionMigrationSql from "../../migrations/0006_operator_action.sql?raw";
import hpActionsMigrationSql from "../../migrations/0007_hp_actions.sql?raw";
import digestWatchMigrationSql from "../../migrations/0009_digest_watch.sql?raw";
import acceptedCommandsErasureFenceMigrationSql from "../../migrations/0012_accepted_commands_erasure_fence.sql?raw";
import notificationProviderTxnIdMigrationSql from "../../migrations/0013_notification_provider_txn_id.sql?raw";
import grantOutcomeEventsMigrationSql from "../../migrations/0014_grant_outcome_events.sql?raw";
import reversalRequestMigrationSql from "../../migrations/0015_reversal_request.sql?raw";
import reconciliationMigrationSql from "../../migrations/0008_reconciliation.sql?raw";
import workLeaseTokenMigrationSql from "../../migrations/0010_work_lease_token.sql?raw";
import checkoutCreationAttemptsMigrationSql from "../../migrations/0011_checkout_creation_attempts.sql?raw";
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
import { appendOffer, loadOffersFixture } from "../../src/records/append";
import { resolveHistoricalCheckoutTimestamp } from "../../src/rebuild";
import { exportFacts } from "../../src/records/export";
import {
  commandFactStatements,
  hasForbiddenCommandFactSecret,
} from "../../src/records/command-facts";
import {
  applySql,
  billingFetch,
  clearCapturedEmails,
  clearCapturedHeartbeatFetches,
  getCapturedEmails,
  getCapturedHeartbeatFetches,
  harnessClockNowSeconds,
  harnessState,
  mintBilling,
  newIssuer,
  pinIssuer,
  runScheduled,
  scriptPaymobInquiry,
  sendEmailBinding,
  setD1BatchThrows,
  setSendEmailThrows,
  tableCount,
} from "./harness";
import {
  drainPlatformDurableObjects,
  getLastPaymobIntentionBody,
  mintVendorAccessJwt,
  platformCall,
  resetCrossWorkerHarness,
  scriptPaymobStub,
  setClock,
  setupCrossWorkerHarness,
  syncPlatformGrantLedger,
} from "./cross-worker-harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const VENDOR_OPERATOR_EMAIL = "operator@vendor.test";
const DIGEST_OPERATOR = "digest.operator@vendor.test";
const PLAN_ID = "plan-pro";
const PLAN_VERSION = 1;
const ALLOWANCE_CREDITS = 100;

const ORG_DIGEST = "a4110001-0001-4011-8011-000000000001";
const ORG_REBUILD = "a4110002-0002-4011-8011-000000000002";
const BASE_CLOCK = "2026-06-15T06:00:00.000Z";
const CAPABILITY_ID = "clinic.visit_summary";
const POLICY_ID = "standard";
const POLICY_VERSION = "1";
const PAID_PAYMOB_TXN_ID = 941105;
const GAP_PAYMOB_TXN_ID = 941106;
const RESUME_PAYMOB_TXN_ID = 941107;
const RESUME_INSTALLATION_ID = "a4110028-0028-4028-8028-000000000028";
const EXTRA_ISSUER_KID = "watch-extra-issuer-kid";
const EXTRA_CREDENTIAL_ID = "watch-extra-credential-id";
const BACKEND_LAST_PULL = "2026-06-15T05:54:00.000Z";
const DAILY_JOB_STAMP = "2026-06-14T06:00:00.000Z";
const HOURLY_JOB_STAMP = "2026-06-15T05:00:00.000Z";
const MINUTE_JOB_STAMP = "2026-06-15T05:59:00.000Z";

let wipedHarnessClockIso: string | null = null;
let wipedHarnessIssuerPins: Array<{ kid: string; public_key: string }> = [];

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

type OffersFixtureExpectations = {
  offer_id: string;
  version: number;
  terms: { version: number; text: string };
};

type PaymobCallbackObj = {
  amount_cents: string | number;
  created_at: string;
  currency: string;
  error_occured: boolean;
  has_parent_transaction: boolean;
  id: number | string;
  integration_id: number | string;
  is_3d_secure: boolean;
  is_auth: boolean;
  is_capture: boolean;
  is_refunded: boolean;
  is_standalone_payment: boolean;
  is_voided: boolean;
  order: { id: number | string };
  owner: number | string;
  pending: boolean;
  source_data: {
    pan: string;
    sub_type: string;
    type: string;
  };
  success: boolean;
};

type PaymobCallbackFixture = {
  type: string;
  obj: PaymobCallbackObj;
};

type AboGrantKey = {
  kid: string;
  pkcs8: string;
  public_key: string;
};

type HpOperation = {
  op: string;
  params: Record<string, unknown>;
  actor_email: string;
  issued_at: string;
  nonce: string;
  contract_version: number;
};

const PAYMOB_HMAC_FIELDS = [
  "amount_cents",
  "created_at",
  "currency",
  "error_occured",
  "has_parent_transaction",
  "id",
  "integration_id",
  "is_3d_secure",
  "is_auth",
  "is_capture",
  "is_refunded",
  "is_standalone_payment",
  "is_voided",
  "order.id",
  "owner",
  "pending",
  "source_data.pan",
  "source_data.sub_type",
  "source_data.type",
  "success",
] as const;

let clinicIssuer: Awaited<ReturnType<typeof newIssuer>> | null = null;

declare module "cloudflare:test" {
  interface ProvidedEnv {
    PLATFORM_DB: D1Database;
    HEARTBEAT_URL: string;
    ISSUER_ID: string;
    ALERT_EMAIL_TO: string;
    ABO_GRANT_KEY: string;
    ACCESS_AUD: string;
    WEBAUTHN_RP_ID: string;
    WEBAUTHN_ORIGIN: string;
    PAYMOB_HMAC_SECRET: string;
  }
}

function addDays(isoUtc: string, days: number): string {
  return new Date(Date.parse(isoUtc) + days * 24 * 60 * 60_000).toISOString();
}

function addHours(isoUtc: string, hours: number): string {
  return new Date(Date.parse(isoUtc) + hours * 60 * 60_000).toISOString();
}

function addMinutes(isoUtc: string, minutes: number): string {
  return new Date(Date.parse(isoUtc) + minutes * 60_000).toISOString();
}

function parseAboGrantKey(): AboGrantKey {
  return JSON.parse(env.ABO_GRANT_KEY) as AboGrantKey;
}

function encodeVendorAssertion(assertion: {
  alg: "ES256" | "EdDSA";
  authenticatorData: Uint8Array;
  clientDataJSON: Uint8Array;
  signature: Uint8Array;
}): Record<string, string> {
  return {
    alg: assertion.alg,
    authenticator_data: base64UrlEncode(assertion.authenticatorData),
    client_data_json: base64UrlEncode(assertion.clientDataJSON),
    signature: base64UrlEncode(assertion.signature),
  };
}

function encodeVendorAttestation(attestation: {
  alg: "ES256" | "EdDSA";
  publicKey: Uint8Array;
}): { alg: "ES256" | "EdDSA"; public_key: string } {
  return {
    alg: attestation.alg,
    public_key: base64UrlEncode(attestation.publicKey),
  };
}

function fakePolicyTarget(modelId = "fake-v1"): Record<string, unknown> {
  return {
    provider_id: "fake",
    model_id: modelId,
    features: {
      structured_output: false,
      min_context_window: 32_000,
      languages: ["en"],
      latency_class: "standard",
      cost_class: "standard",
    },
    max_attempts: 1,
    timeout_ms: 30_000,
  };
}

function fakePolicyDocument(): Record<string, unknown> {
  return {
    schema_version: 1,
    policy_id: POLICY_ID,
    policy_version: Number(POLICY_VERSION),
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules: [
      {
        rule_id: "catch-all",
        match: {},
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: ["en"],
        },
        targets: [fakePolicyTarget()],
      },
    ],
    overrides: [],
  };
}

function hmacFieldValue(obj: PaymobCallbackObj, field: string): string {
  if (field === "order.id") {
    return String(obj.order.id);
  }
  if (field === "source_data.pan") {
    return String(obj.source_data.pan);
  }
  if (field === "source_data.sub_type") {
    return String(obj.source_data.sub_type);
  }
  if (field === "source_data.type") {
    return String(obj.source_data.type);
  }
  const raw = obj[field as keyof PaymobCallbackObj];
  if (typeof raw === "boolean") {
    return raw ? "true" : "false";
  }
  return String(raw);
}

function successFixtureWithTxnId(txnId: number): PaymobCallbackFixture {
  const base = successFixture as PaymobCallbackFixture;
  return {
    type: base.type,
    obj: { ...base.obj, id: txnId },
  };
}

function successFixtureWithAmount(
  amountMinor: number,
  txnId?: number,
  orderId?: string | number,
): PaymobCallbackFixture {
  const base =
    txnId !== undefined
      ? successFixtureWithTxnId(txnId)
      : (successFixture as PaymobCallbackFixture);
  return {
    type: base.type,
    obj: {
      ...base.obj,
      amount_cents: String(amountMinor),
      ...(orderId === undefined ? {} : { order: { id: orderId } }),
    },
  };
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
    digestWatchMigrationSql,
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
  ]) {
    await applySql(sql);
  }
}

async function ensureDigestWatchMigration(): Promise<void> {
  await applySql(DIGEST_WATCH_SCHEMA_SQL);
  const factColumns = await env.DB.prepare(`PRAGMA table_info(fact_log)`).all<{
    name: string;
  }>();
  const checkoutColumns = await env.DB.prepare(`PRAGMA table_info(checkout)`).all<{
    name: string;
  }>();
  const recoveryTable = await env.DB.prepare(
    `SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'rebuild_inquiry_attempt'`,
  ).first<{ name: string }>();
  expect(factColumns.results?.some((column) => column.name === "row_json"))
    .toBe(true);
  expect(checkoutColumns.results?.some((column) => column.name === "created_at_provenance"))
    .toBe(true);
  expect(recoveryTable?.name).toBe("rebuild_inquiry_attempt");
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

async function signPaymobObj(
  secret: string,
  obj: PaymobCallbackObj,
): Promise<string> {
  const concatenated = PAYMOB_HMAC_FIELDS.map((field) =>
    hmacFieldValue(obj, field),
  ).join("");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(concatenated),
  );
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function seedOffersCatalogueFixture(): Promise<OffersFixtureExpectations | null> {
  const fixture = offersFixture as {
    expectations?: OffersFixtureExpectations;
  };
  if (fixture.expectations === undefined) return null;
  try {
    await loadOffersFixture(fixture);
  } catch (cause) {
    throw new Error(
      "seedOffersCatalogueFixture failed while loading terms/offers into D1/R2",
      { cause },
    );
  }
  return fixture.expectations;
}

async function registerAboGrantKeyOnPlatform(): Promise<void> {
  const aboKey = parseAboGrantKey();
  const notBefore = "2020-01-01T00:00:00.000Z";
  const notAfter = "2099-01-01T00:00:00.000Z";
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO service_key
       (kid, service, public_key, status, not_before, not_after, registered_by, assertion_sha256)
     VALUES (?, 'abo', ?, 'active', ?, ?, ?, 'harness')`,
  )
    .bind(aboKey.kid, aboKey.public_key, notBefore, notAfter, VENDOR_OPERATOR_EMAIL)
    .run();
}

async function publishPlanProOnPlatform(): Promise<void> {
  const existing = await env.PLATFORM_DB.prepare(
    `SELECT 1 AS present FROM plan_version WHERE plan_id = ? AND version = ?`,
  )
    .bind(PLAN_ID, PLAN_VERSION)
    .first<{ present: number }>();
  if (existing?.present) {
    await env.PLATFORM_DB.prepare(
      `UPDATE plan_version SET status = 'published' WHERE plan_id = ? AND version = ?`,
    )
      .bind(PLAN_ID, PLAN_VERSION)
      .run();
    return;
  }
  await env.PLATFORM_DB.prepare(
    `INSERT INTO plan_version (
       plan_id, version, display_name, capabilities, max_cost_class,
       concurrency_limit, max_allowance_per_month, status, published_by,
       assertion_sha256
     ) VALUES (?, ?, ?, ?, ?, ?, ?, 'published', ?, 'harness')`,
  )
    .bind(
      PLAN_ID,
      PLAN_VERSION,
      "Clinic Pro",
      JSON.stringify([CAPABILITY_ID]),
      "2",
      4,
      ALLOWANCE_CREDITS,
      VENDOR_OPERATOR_EMAIL,
    )
    .run();
}

async function registerClinicIssuerKey(): Promise<void> {
  if (clinicIssuer !== null) {
    return;
  }
  const issuer = await newIssuer();
  await pinIssuer(issuer.kid, issuer.publicKey);
  const rawPublicKey = await crypto.subtle.exportKey("raw", issuer.publicKey);
  const publicKeyB64 = base64UrlEncode(new Uint8Array(rawPublicKey));
  const notBefore = "2020-01-01T00:00:00.000Z";
  const notAfter = "2099-01-01T00:00:00.000Z";
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO issuer_key
       (kid, issuer, public_key, status, not_before, not_after, registered_by, assertion_sha256)
     VALUES (?, ?, ?, 'active', ?, ?, ?, 'harness')`,
  )
    .bind(issuer.kid, env.ISSUER_ID, publicKeyB64, notBefore, notAfter, VENDOR_OPERATOR_EMAIL)
    .run();
  clinicIssuer = issuer;
}

async function setupPromotedRoutingPolicy(): Promise<void> {
  const document = fakePolicyDocument();
  const contentPointer = `control/routing-policy/${POLICY_ID}/${POLICY_VERSION}.json`;
  await env.R2.put(contentPointer, JSON.stringify(document), {
    httpMetadata: { contentType: "application/json" },
  });
  const now = "2026-06-01T12:00:00.000Z";
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO routing_policy (
       policy_id, version, content_pointer, active_from, activated_by, status
     ) VALUES (?, ?, ?, ?, ?, 'active')`,
  )
    .bind(POLICY_ID, POLICY_VERSION, contentPointer, now, VENDOR_OPERATOR_EMAIL)
    .run();
}

async function clearRebuildLedgerArtifacts(): Promise<void> {
  for (const prefix of ["ledger/", "ledger-manifest/"]) {
    const keys: string[] = [];
    let cursor: string | undefined;
    let truncated = true;
    while (truncated) {
      const listed = await env.R2.list({ prefix, cursor });
      keys.push(...listed.objects.map((object) => object.key));
      truncated = listed.truncated;
      cursor = listed.truncated ? listed.cursor : undefined;
    }

    for (let offset = 0; offset < keys.length; offset += 1000) {
      await env.R2.delete(keys.slice(offset, offset + 1000));
    }
  }
}

async function wipePlatformD1(): Promise<void> {
  const objects = await env.PLATFORM_DB.prepare(
    `SELECT name, type FROM sqlite_master
     WHERE type IN ('table', 'trigger', 'view')
       AND name NOT LIKE 'sqlite_%'
       AND name NOT LIKE '_cf_%'
     ORDER BY rowid DESC`,
  ).all<{ name: string; type: string }>();
  const rows = objects.results ?? [];
  for (const row of rows) {
    if (row.type === "trigger") {
      await env.PLATFORM_DB.prepare(`DROP TRIGGER IF EXISTS ${row.name}`).run();
    }
  }
  for (const row of rows) {
    if (row.type === "view") {
      await env.PLATFORM_DB.prepare(`DROP VIEW IF EXISTS ${row.name}`).run();
    }
  }
  for (const row of rows) {
    if (row.type === "table") {
      await env.PLATFORM_DB.prepare(`DROP TABLE IF EXISTS ${row.name}`).run();
    }
  }
}

async function setupRebuildHarness(options?: {
  freshPlatformState?: boolean;
}): Promise<OffersFixtureExpectations> {
  if (options?.freshPlatformState === true) {
    await wipePlatformD1();
    await setupCrossWorkerHarness();
    await setClock(BASE_CLOCK);
  }
  // Catalogue and fact rows are append-only, so the ordinary per-case reset
  // cannot isolate the shared offers fixture. Clear its ledger objects and
  // recreate suite-local D1 before loading it so each case seeds it once.
  await clearRebuildLedgerArtifacts();
  await wipeAboD1();
  await reapplyAboSchema();
  const expectations = await seedOffersCatalogueFixture();
  expect(expectations).not.toBeNull();
  await registerAboGrantKeyOnPlatform();
  await publishPlanProOnPlatform();
  await registerClinicIssuerKey();
  await setupPromotedRoutingPolicy();
  return expectations!;
}

async function ensureGrantTenantBinding(
  orgId: string,
  installationId = crypto.randomUUID(),
): Promise<void> {
  const existing = await env.PLATFORM_DB.prepare(
    `SELECT installation_id FROM tenant_binding
     WHERE org_id = ? AND status = 'active'`,
  )
    .bind(orgId)
    .first<{ installation_id: string }>();
  if (existing?.installation_id) {
    return;
  }
  const createdAt = "2026-06-01T12:00:00.000Z";
  await env.PLATFORM_DB.batch([
    env.PLATFORM_DB.prepare(
      `INSERT INTO installation (
         installation_id, org_id, status, display_name, region, enrolled_at
       ) VALUES (?, ?, 'active', '', '', ?)`,
    ).bind(installationId, orgId, createdAt),
    env.PLATFORM_DB.prepare(
      `INSERT INTO tenant_binding (
         org_id, installation_id, epoch, status, retired_at, reason, created_at
       ) VALUES (?, ?, 1, 'active', NULL, NULL, ?)`,
    ).bind(orgId, installationId, createdAt),
  ]);
}

async function harnessNowSeconds(): Promise<number> {
  const row = await env.PLATFORM_DB.prepare(
    `SELECT now_iso FROM harness_test_clock WHERE id = 'default'`,
  ).first<{ now_iso: string }>();
  if (row?.now_iso) {
    const parsed = Date.parse(row.now_iso);
    if (!Number.isNaN(parsed)) {
      return Math.floor(parsed / 1000);
    }
  }
  return Math.floor(Date.now() / 1000);
}

async function currentHarnessClockIso(): Promise<string> {
  const row = await env.DB.prepare(
    `SELECT now_iso FROM harness_test_clock WHERE id = 'default'`,
  ).first<{ now_iso: string }>();
  return row?.now_iso ?? BASE_CLOCK;
}

async function administratorHeaders(
  org: string,
): Promise<Record<string, string>> {
  const issuer = clinicIssuer ?? (await newIssuer());
  if (clinicIssuer === null) {
    await pinIssuer(issuer.kid, issuer.publicKey);
    clinicIssuer = issuer;
  }
  const now = await harnessClockNowSeconds();
  const token = await mintBilling(issuer, {
    sub: "admin-sub",
    org,
    role: "administrator",
    branch: "branch-test",
    iat: now,
    exp: now + 300,
    jti: crypto.randomUUID(),
  });
  return {
    authorization: `Bearer ${token}`,
    "Abo-Contract-Version": "1",
    "content-type": "application/json",
  };
}

async function putBillingContact(org: string): Promise<void> {
  const response = await billingFetch("/v1/billing-contact", {
    method: "PUT",
    headers: await administratorHeaders(org),
    body: JSON.stringify({
      client_request_id: `req-contact-${org}`,
      name: "Clinic Admin",
      email: "admin@clinic.test",
      phone: "+201001234567",
    }),
  });
  await response.text();
  expect(response.status).toBe(200);
}

async function postCheckout(
  org: string,
  expectations: OffersFixtureExpectations,
  clientRequestId: string,
): Promise<{ checkoutId: string; reference: string }> {
  const response = await billingFetch("/v1/checkouts", {
    method: "POST",
    headers: await administratorHeaders(org),
    body: JSON.stringify({
      client_request_id: clientRequestId,
      offer_id: expectations.offer_id,
      offer_version: expectations.version,
      terms_version: expectations.terms.version,
    }),
  });
  expect(response.status).toBe(201);
  const body = (await response.json()) as Record<string, unknown>;
  return {
    checkoutId: String(body.checkout_id),
    reference: String(body.reference),
  };
}

async function chargedPriceMinorForCheckout(checkoutId: string): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT charged_price_minor FROM checkout WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ charged_price_minor: number }>();
  expect(row).not.toBeNull();
  return row!.charged_price_minor;
}

async function scriptPaymobAmount(amountMinor: number): Promise<void> {
  await env.PAYMOB_STUB.fetch("http://paymob.stub/__script", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ amount_cents: String(amountMinor) }),
  });
}

async function syncPaymobForCheckout(checkoutId: string): Promise<number> {
  const chargedPrice = await chargedPriceMinorForCheckout(checkoutId);
  await scriptPaymobAmount(chargedPrice);
  await scriptPaymobInquiry("bound_success");
  return chargedPrice;
}

async function postPaymobProcessedCallback(
  fixture: PaymobCallbackFixture,
  options?: {
    txnId?: number;
    amountMinor?: number;
    orderId?: string | number;
  },
): Promise<Response> {
  const bodyFixture =
    options?.amountMinor !== undefined
      ? successFixtureWithAmount(options.amountMinor, options.txnId, options.orderId)
      : options?.txnId !== undefined
        ? successFixtureWithTxnId(options.txnId)
        : fixture;
  const selectedFixture = options?.orderId !== undefined && options.amountMinor === undefined
    ? { type: bodyFixture.type, obj: { ...bodyFixture.obj, order: { id: options.orderId } } }
    : bodyFixture;
  const body = JSON.stringify({ type: selectedFixture.type, obj: selectedFixture.obj });
  const hmac = await signPaymobObj(env.PAYMOB_HMAC_SECRET, selectedFixture.obj);
  return billingFetch(`/notify/paymob?hmac=${encodeURIComponent(hmac)}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": "203.0.113.10",
    },
    body,
  });
}

async function paymentIdForCheckout(checkoutId: string): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT payment_id FROM payment WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ payment_id: string }>();
  return row?.payment_id ?? null;
}

async function runGrantStep(orgId: string): Promise<void> {
  const { runDueGrantWork } = await import("../../src/work/grant");
  await runScheduled("* * * * *");
  await runDueGrantWork(env as never);
  await syncPlatformGrantLedger(orgId);
  await drainPlatformDurableObjects();
}

async function paidCheckoutWithGrant(
  org: string,
  expectations: OffersFixtureExpectations,
  txnId: number,
  clientRequestId: string,
): Promise<{ checkoutId: string; paymentId: string }> {
  await putBillingContact(org);
  await ensureGrantTenantBinding(org);
  const { checkoutId } = await postCheckout(org, expectations, clientRequestId);
  const chargedPrice = await syncPaymobForCheckout(checkoutId);
  const intake = await postPaymobProcessedCallback(
    successFixture as PaymobCallbackFixture,
    { txnId, amountMinor: chargedPrice },
  );
  expect(intake.status).toBe(200);
  await runGrantStep(org);
  const paymentId = await paymentIdForCheckout(checkoutId);
  expect(paymentId).not.toBeNull();
  return { checkoutId, paymentId: paymentId! };
}

async function gapCheckoutWithIntentionOnly(
  org: string,
  expectations: OffersFixtureExpectations,
  clientRequestId: string,
): Promise<string> {
  await putBillingContact(org);
  await ensureGrantTenantBinding(org);
  const { checkoutId } = await postCheckout(org, expectations, clientRequestId);
  await syncPaymobForCheckout(checkoutId);
  return checkoutId;
}

async function exportLedgerFacts(platformPublicKeys?: string): Promise<void> {
  await runScheduled("* * * * *");
  await exportFacts({
    ...env,
    PLATFORM_PUBLIC_KEYS: platformPublicKeys ?? env.PLATFORM_PUBLIC_KEYS,
  });
}

async function wipeAboD1(): Promise<void> {
  const harnessClock = await env.DB.prepare(
    `SELECT now_iso FROM harness_test_clock WHERE id = 'default'`,
  ).first<{ now_iso: string }>();
  wipedHarnessClockIso = harnessClock?.now_iso ?? null;
  const issuerPins = await env.DB.prepare(
    `SELECT kid, public_key FROM harness_issuer_pin`,
  ).all<{ kid: string; public_key: string }>();
  wipedHarnessIssuerPins = issuerPins.results ?? [];
  const objects = await env.DB.prepare(
    `SELECT name, type FROM sqlite_master
     WHERE type IN ('table', 'trigger', 'view', 'index')
       AND name NOT LIKE 'sqlite_%'
       AND name NOT LIKE '_cf_%'`,
  ).all<{ name: string; type: string }>();
  for (const row of objects.results ?? []) {
    if (row.type === "trigger") {
      await env.DB.prepare(`DROP TRIGGER IF EXISTS ${row.name}`).run();
    }
  }
  for (const row of objects.results ?? []) {
    if (row.type === "view") {
      await env.DB.prepare(`DROP VIEW IF EXISTS ${row.name}`).run();
    }
  }
  // RM09's attempt projections reference checkout, so drop them first rather
  // than relying on sqlite_master enumeration order.
  // 0024/0025 child tables reference `reversal` and payout lines; drop them
  // before the generic loop so the parent `reversal` table can be dropped.
  for (const tableName of [
    "payout_reversal_link",
    "reversal_provider_identity",
    "payout_line_reversal",
    "rebuild_inquiry_attempt",
    "paymob_intention_attempt_event",
    "paymob_intention_attempt",
  ]) {
    if ((objects.results ?? []).some((row) => row.type === "table" && row.name === tableName)) {
      await env.DB.prepare(`DROP TABLE IF EXISTS ${tableName}`).run();
    }
  }
  for (const row of objects.results ?? []) {
    if (row.type === "table") {
      await env.DB.prepare(`DROP TABLE IF EXISTS ${row.name}`).run();
    }
  }
  for (const row of objects.results ?? []) {
    if (row.type === "index") {
      await env.DB.prepare(`DROP INDEX IF EXISTS ${row.name}`).run();
    }
  }
}

async function reapplyAboSchema(): Promise<void> {
  await applySql(recordsMigrationSql);
  await ensureMigrations();
  await ensureDigestWatchMigration();
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
  await env.DB.prepare(
    `INSERT OR REPLACE INTO harness_test_clock (id, now_iso) VALUES ('default', ?)`,
  ).bind(wipedHarnessClockIso ?? new Date().toISOString()).run();
  for (const pin of wipedHarnessIssuerPins) {
    await env.DB.prepare(
      `INSERT OR REPLACE INTO harness_issuer_pin (kid, public_key) VALUES (?, ?)`,
    ).bind(pin.kid, pin.public_key).run();
  }
  wipedHarnessClockIso = null;
  wipedHarnessIssuerPins = [];
}

function readRebuildRunbook(): string {
  return rebuildRunbookMd;
}

async function seedExtraUnpinnedIssuerKey(): Promise<string> {
  const issuer = await newIssuer();
  const rawPublicKey = await crypto.subtle.exportKey("raw", issuer.publicKey);
  const publicKeyB64 = base64UrlEncode(new Uint8Array(rawPublicKey));
  const notBefore = "2020-01-01T00:00:00.000Z";
  const notAfter = "2099-01-01T00:00:00.000Z";
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO issuer_key
       (kid, issuer, public_key, status, not_before, not_after, registered_by, assertion_sha256)
     VALUES (?, ?, ?, 'active', ?, ?, ?, 'harness')`,
  )
    .bind(
      EXTRA_ISSUER_KID,
      env.ISSUER_ID,
      publicKeyB64,
      notBefore,
      notAfter,
      VENDOR_OPERATOR_EMAIL,
    )
    .run();
  return EXTRA_ISSUER_KID;
}

async function seedExtraUnannouncedOperatorCredential(): Promise<{
  credentialId: string;
  publicKeyCose: string;
  alg: string;
}> {
  const authenticator = await createSoftwareAuthenticator("EdDSA");
  const attestation = encodeVendorAttestation(await authenticator.attest());
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO operator_credential
       (credential_id, operator_email, public_key_cose, alg, status, activates_at, approved_by, revoked_by)
     VALUES (?, ?, ?, ?, 'active', ?, NULL, NULL)`,
  )
    .bind(
      EXTRA_CREDENTIAL_ID,
      VENDOR_OPERATOR_EMAIL,
      attestation.public_key,
      attestation.alg,
      "2020-01-01T00:00:00.000Z",
    )
    .run();
  return {
    credentialId: EXTRA_CREDENTIAL_ID,
    publicKeyCose: attestation.public_key,
    alg: attestation.alg,
  };
}

async function clearWatchAlertSeeds(): Promise<void> {
  await env.PLATFORM_DB.prepare(
    `DELETE FROM issuer_key WHERE kid = ?`,
  )
    .bind(EXTRA_ISSUER_KID)
    .run();
  await env.PLATFORM_DB.prepare(
    `DELETE FROM operator_credential WHERE credential_id IN (?, ?)`,
  )
    .bind(EXTRA_CREDENTIAL_ID, "watch-remembered-credential-id")
    .run();
}

async function seedActiveOperatorCredential(
  authenticator: SoftwareAuthenticator,
  credentialId = crypto.randomUUID(),
): Promise<string> {
  const attestation = encodeVendorAttestation(await authenticator.attest());
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO operator_credential
       (credential_id, operator_email, public_key_cose, alg, status, activates_at, approved_by, revoked_by)
     VALUES (?, ?, ?, ?, 'active', ?, NULL, NULL)`,
  )
    .bind(
      credentialId,
      VENDOR_OPERATOR_EMAIL,
      attestation.public_key,
      attestation.alg,
      "2020-01-01T00:00:00.000Z",
    )
    .run();
  return credentialId;
}

async function registerOperatorCredentialWithSigner(input: {
  credentialId: string;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  attestationAuthenticator: SoftwareAuthenticator;
  accessJwt: string;
}): Promise<Record<string, unknown>> {
  const attestation = encodeVendorAttestation(
    await input.attestationAuthenticator.attest(),
  );
  const issuedAt = await currentHarnessClockIso();
  const operation: HpOperation = {
    op: "registerOperatorCredential",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      credential_id: input.credentialId,
      attestation,
      signer_credential_id: input.signerCredentialId,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: issuedAt,
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
  const assertion = encodeVendorAssertion(
    await input.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  return platformCall(
    "registerOperatorCredential",
    {
      contract_version: CONTRACT_VERSION,
      credential_id: input.credentialId,
      attestation,
      signer_credential_id: input.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt: input.accessJwt },
  );
}

async function seedSeenOperatorCredential(detail: Record<string, unknown>): Promise<void> {
  await env.DB.prepare(
    `INSERT OR IGNORE INTO seen_operator_credential (
       credential_id, public_key_cose, alg
     ) VALUES (?, ?, ?)`,
  )
    .bind(
      String(detail.credential_id),
      String(detail.public_key_cose),
      String(detail.alg),
    )
    .run();
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
  // Append-only triggers block the harness reset from clearing checkout rows,
  // so a second seed in the same file must start from a fresh schema.
  await wipeAboD1();
  await reapplyAboSchema();
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
       ) VALUES (?, 'confirm', ?, 'dedupe-digest-work', 'parked', 0, NULL, NULL, NULL, ?)`,
    ).bind(parkedWorkId, checkoutId, addHours(BASE_CLOCK, -1)),
    env.DB.prepare(
      `INSERT INTO alert (
         alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id
       ) VALUES (?, 'AL-99', 1, 0, ?, NULL, 'digest-open-alert')`,
    ).bind(openAlertKey, addHours(BASE_CLOCK, -3)),
    // R9-CRON1: job success is recorded per logical job, not per cron string.
    env.DB.prepare(
      `INSERT INTO scheduled_job_state (job, last_started_at, last_succeeded_at)
       VALUES ('digest', ?, ?)`,
    ).bind(DAILY_JOB_STAMP, DAILY_JOB_STAMP),
    env.DB.prepare(
      `INSERT INTO scheduled_job_state (job, last_started_at, last_succeeded_at)
       VALUES ('hourly_watch', ?, ?)`,
    ).bind(HOURLY_JOB_STAMP, HOURLY_JOB_STAMP),
    env.DB.prepare(
      `INSERT INTO scheduled_job_state (job, last_started_at, last_succeeded_at)
       VALUES ('minute_processing', ?, ?)`,
    ).bind(MINUTE_JOB_STAMP, MINUTE_JOB_STAMP),
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

type ScheduledJobRow = {
  last_succeeded_period: string | null;
  last_error_at: string | null;
  next_attempt_at: string | null;
  lease_token: string | null;
  lease_until: string | null;
  last_started_at: string | null;
};

async function scheduledJobRow(job: string): Promise<ScheduledJobRow> {
  const row = await env.DB.prepare(
    `SELECT last_succeeded_period, last_error_at, next_attempt_at,
            lease_token, lease_until, last_started_at
     FROM scheduled_job_state WHERE job = ?`,
  )
    .bind(job)
    .first<ScheduledJobRow>();
  if (row === null) {
    throw new Error(`scheduled_job_state row missing for ${job}`);
  }
  return row;
}

async function scheduledJobAlertRow(
  job: string,
): Promise<{ active: number; unsent: number } | null> {
  return env.DB.prepare(
    `SELECT active, unsent FROM alert WHERE alert_key = ?`,
  )
    .bind(`scheduled_job_failed:${job}`)
    .first<{ active: number; unsent: number }>();
}

async function scheduledJobAlertCount(job: string): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM alert WHERE alert_key = ?`,
  )
    .bind(`scheduled_job_failed:${job}`)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

// R9-CRON1 failure injection: the real platform binding, except that the named reads are
// refused. The job code then sees a refused read, which is the same path a live refusal takes.
function platformRefusing(methods: ReadonlyArray<string>): unknown {
  const real = env.PLATFORM as unknown as Record<
    string,
    (...args: unknown[]) => unknown
  >;
  return new Proxy(
    {},
    {
      get(_target, prop) {
        if (typeof prop !== "string") {
          return undefined;
        }
        if (methods.includes(prop)) {
          return async () => ({ result: "refused", detail: "" });
        }
        return (...args: unknown[]) => real[prop]!(...args);
      },
    },
  );
}

function envWithPlatform(platform: unknown): never {
  return { ...env, PLATFORM: platform } as never;
}

function pauseMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
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
  it("R9-REC1 isolated schema reapply installs migration 0009 before recovery provenance", async () => {
    await wipeAboD1();
    await reapplyAboSchema();
  });

  it("R9-REC1 rejects missing and expiry-inferred checkout timestamps during recovery", () => {
    expect(() => resolveHistoricalCheckoutTimestamp({
      checkoutId: "checkout-r9-missing-time",
      createdAt: null,
      provenance: "legacy_unknown",
      factCreatedAt: "",
    })).toThrow("checkout_timestamp_unrecoverable:checkout-r9-missing-time");
    expect(() => resolveHistoricalCheckoutTimestamp({
      checkoutId: "checkout-r9-expiry-time",
      createdAt: "2026-06-01T11:30:00.000Z",
      provenance: "expiry_inferred",
      factCreatedAt: "2026-06-01T12:00:00.000Z",
    })).toThrow("checkout_timestamp_inferred_from_expiry:checkout-r9-expiry-time");
    expect(resolveHistoricalCheckoutTimestamp({
      checkoutId: "checkout-r9-recorded-time",
      createdAt: "2026-06-01T12:00:00.000Z",
      provenance: "recorded",
      factCreatedAt: "2026-06-01T12:00:00.000Z",
    })).toEqual({
      createdAt: "2026-06-01T12:00:00.000Z",
      provenance: "recorded",
    });
  });

  it("R9-REC1 rejects unknown command recovery payload versions before replay", async () => {
    await setupRebuildHarness();
    const commandId = "cmd-r9-unknown-payload-version";
    await env.DB.batch(await commandFactStatements(env, {
      commandId,
      kind: "command_intent",
      payload: {
        payload_version: 1,
        command_id: commandId,
        method: "erase_contact",
        subject_id: ORG_REBUILD,
        actor_email: VENDOR_OPERATOR_EMAIL,
        erasure_generation: 1,
        scope_contact_versions: [],
        acceptance_cutoff: "2026-06-15T06:00:00.000Z",
      },
      createdAt: "2026-06-15T06:00:00.000Z",
    }));
    await exportLedgerFacts();
    const objects = await env.R2.list({ prefix: "ledger/" });
    let payloadKey: string | undefined;
    for (const object of objects.objects) {
      const stored = await env.R2.get(object.key);
      if (stored === null) continue;
      const line = JSON.parse(await stored.text()) as Record<string, unknown>;
      const row = line.row as Record<string, unknown> | undefined;
      if (row?.command_id !== commandId) continue;
      const payload = JSON.parse(String(row.payload_json)) as Record<string, unknown>;
      payload.payload_version = 99;
      const payloadJson = new TextDecoder().decode(canonicalize(payload));
      const payloadSha = await sha256Hex(canonicalize(payload));
      const factId = await sha256Hex(canonicalize({
        command_id: commandId,
        fact_kind: row.fact_kind,
        payload_sha256: payloadSha,
      }));
      const changedRow = {
        ...row,
        fact_id: factId,
        payload_json: payloadJson,
        payload_sha256: payloadSha,
      };
      line.key = factId;
      line.row = changedRow;
      line.row_sha256 = await sha256Hex(canonicalize(changedRow));
      payloadKey = object.key;
      await env.R2.put(object.key, new TextDecoder().decode(canonicalize(line)));
      break;
    }
    expect(payloadKey).toBeDefined();

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    await expect(rebuildAbo(env as never, { providerTransactionReferences: [] }))
      .rejects.toThrow(/ledger_command_fact_invalid/u);
    expect(await tableCount("fact_log")).toBe(0);
  });

  beforeEach(async () => {
    clinicIssuer = null;
    await resetCrossWorkerHarness();
    await setupCrossWorkerHarness();
    await ensureDigestWatchMigration();
    await scriptPaymobStub("ok");
    await env.PAYMOB_STUB.fetch("http://paymob.stub/__script", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ intention_order_id: "9001" }),
    });
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

  it("R9-CRON1 failed digest send stays pending with no digest heartbeat, and one minute retry completes it once", async () => {
    await seedDigestScenario();
    clearCapturedEmails();
    clearCapturedHeartbeatFetches();
    setSendEmailThrows(true);

    await runScheduled("0 6 * * *");

    const failed = await env.DB.prepare(
      `SELECT last_succeeded_period, last_error_code, next_attempt_at
       FROM scheduled_job_state WHERE job = 'digest'`,
    ).first<{
      last_succeeded_period: string | null;
      last_error_code: string | null;
      next_attempt_at: string | null;
    }>();
    expect(failed?.last_succeeded_period ?? null).toBeNull();
    expect(failed?.last_error_code).toBeTruthy();
    expect(failed?.next_attempt_at).not.toBeNull();
    // R9-CRON1 / RT2: the digest success stream is pinged only after the send is acknowledged.
    expect(getCapturedHeartbeatFetches()).not.toContain(env.HEARTBEAT_URL_DIGEST);
    expect(digestEmails()).toHaveLength(0);

    setSendEmailThrows(false);
    await setClock(addMinutes(BASE_CLOCK, 16));
    await runScheduled("* * * * *");
    expect(digestEmails()).toHaveLength(1);
    // R9-CRON1 / RT2 (was HEARTBEAT_URL): the digest success is the abo_daily_digest stream.
    expect(getCapturedHeartbeatFetches()).toContain(env.HEARTBEAT_URL_DIGEST);

    const completed = await env.DB.prepare(
      `SELECT last_succeeded_period, next_attempt_at
       FROM scheduled_job_state WHERE job = 'digest'`,
    ).first<{ last_succeeded_period: string | null; next_attempt_at: string | null }>();
    expect(completed?.last_succeeded_period).not.toBeNull();
    expect(completed?.next_attempt_at).toBeNull();

    clearCapturedEmails();
    await runScheduled("* * * * *");
    expect(digestEmails()).toHaveLength(0);
  });

  it("R9-CRON1 a live lease blocks an overlapping run of the same due period", async () => {
    await seedDigestScenario();
    clearCapturedEmails();
    await env.DB.prepare(
      `INSERT INTO scheduled_job_state (job, lease_token, lease_until)
       VALUES ('digest', 'overlapping-run', ?)
       ON CONFLICT(job) DO UPDATE SET
         lease_token = excluded.lease_token,
         lease_until = excluded.lease_until`,
    )
      .bind(addHours(BASE_CLOCK, 1))
      .run();

    await runScheduled("0 6 * * *");

    expect(digestEmails()).toHaveLength(0);
    const row = await env.DB.prepare(
      `SELECT lease_token FROM scheduled_job_state WHERE job = 'digest'`,
    ).first<{ lease_token: string | null }>();
    expect(row?.lease_token).toBe("overlapping-run");
  });

  // The next three tests inject failures at the job-state level: the job runs through
  // runDueScheduledJob with the real job code and a refused platform read. Only the failing
  // run is injected this way. The minute retry runs through the real minute cron.
  it("R9-CRON1 reconciliation failure leaves the period pending and the minute retry completes it once", async () => {
    await seedDigestScenario();
    const { runDueScheduledJob } = await import("../../src/scheduler/jobs.js");
    const { runReconciliation } = await import("../../src/reconciliation/run.js");

    const outcome = await runDueScheduledJob(
      envWithPlatform(platformRefusing(["listGrants"])),
      {
        job: "reconciliation",
        cadence: "daily",
        run: (scoped) => runReconciliation(scoped as never),
      },
    );
    expect(outcome).toBe("failed");
    const pending = await scheduledJobRow("reconciliation");
    expect(pending.last_succeeded_period).toBeNull();
    expect(pending.last_error_at).not.toBeNull();
    expect(pending.next_attempt_at).not.toBeNull();
    expect((await scheduledJobAlertRow("reconciliation"))?.active).toBe(1);

    await setClock(addMinutes(BASE_CLOCK, 16));
    await runScheduled("* * * * *");
    const completed = await scheduledJobRow("reconciliation");
    expect(completed.last_succeeded_period).not.toBeNull();
    expect(completed.next_attempt_at).toBeNull();
    expect((await scheduledJobAlertRow("reconciliation"))?.active).toBe(0);

    const startedAt = completed.last_started_at;
    await runScheduled("* * * * *");
    expect((await scheduledJobRow("reconciliation")).last_started_at).toBe(startedAt);
  });

  it("R9-CRON1 watch failure leaves the period pending", async () => {
    await seedDigestScenario();
    const { runDueScheduledJob } = await import("../../src/scheduler/jobs.js");
    const { runHourlyWatch } = await import("../../src/watch/hourly.js");

    const outcome = await runDueScheduledJob(
      envWithPlatform(platformRefusing(["feedConsumerHealth"])),
      {
        job: "hourly_watch",
        cadence: "hourly",
        run: (scoped) => runHourlyWatch(scoped as never),
      },
    );
    expect(outcome).not.toBe("succeeded");
    const pending = await scheduledJobRow("hourly_watch");
    expect(pending.last_succeeded_period).toBeNull();
    expect(pending.next_attempt_at).not.toBeNull();

    await setClock(addMinutes(BASE_CLOCK, 16));
    await runScheduled("* * * * *");
    const completed = await scheduledJobRow("hourly_watch");
    expect(completed.last_succeeded_period).not.toBeNull();
    expect(completed.next_attempt_at).toBeNull();
  });

  it("R9-CRON1 abandoned lease after a crash is retried by the minute cron", async () => {
    await seedDigestScenario();
    const { runDueScheduledJob } = await import("../../src/scheduler/jobs.js");
    clearCapturedEmails();

    // The run claims the digest period and never finishes, as a crash or timeout would.
    void runDueScheduledJob(env as never, {
      job: "digest",
      cadence: "daily",
      run: () => new Promise<never>(() => {}),
    });
    await pauseMs(200);
    const crashed = await scheduledJobRow("digest");
    expect(crashed.lease_token).not.toBeNull();
    // F1: the claim sets next_attempt_at to the lease expiry, so the abandoned lease is retryable.
    expect(crashed.next_attempt_at).toBe(crashed.lease_until);

    await setClock(addMinutes(BASE_CLOCK, 5));
    await runScheduled("* * * * *");
    expect(digestEmails()).toHaveLength(0);

    await setClock(addMinutes(BASE_CLOCK, 16));
    await runScheduled("* * * * *");
    expect(digestEmails()).toHaveLength(1);
    const done = await scheduledJobRow("digest");
    expect(done.last_succeeded_period).not.toBeNull();
    expect(done.lease_token).toBeNull();
    expect(done.next_attempt_at).toBeNull();
  });

  it("R9-CRON1 a never-attempted daily period is not started by the minute cron", async () => {
    await seedDigestScenario();
    clearCapturedEmails();

    // Side 1: the 06:00 tick for this period never ran, so the period was never attempted.
    // Minute ticks after the gap must not start it.
    await setClock(addMinutes(BASE_CLOCK, 60));
    await runScheduled("* * * * *");
    await runScheduled("* * * * *");
    expect(digestEmails()).toHaveLength(0);
    const untouched = await scheduledJobRow("digest");
    expect(untouched.last_succeeded_period).toBeNull();
    expect(untouched.next_attempt_at).toBeNull();

    // Side 2: the next scheduled 06:00 tick runs its own period.
    clearCapturedEmails();
    await setClock(addHours(BASE_CLOCK, 24));
    await runScheduled("0 6 * * *");
    expect(digestEmails()).toHaveLength(1);
    expect((await scheduledJobRow("digest")).last_succeeded_period).not.toBeNull();
  });

  it("R9-CRON1 scheduled_job_failed alert is raised once per job and deduplicated", async () => {
    await seedDigestScenario();
    clearCapturedEmails();
    // Every digest send fails. Alert emails still go through.
    Object.assign(env.SEND_EMAIL, {
      async send(message: { from: string; to: string; subject: string; text: string }): Promise<void> {
        if (message.subject === "digest") {
          throw new Error("digest send failure injected by test");
        }
        await sendEmailBinding.send(message);
      },
    });
    const digestAlertEmails = (): number =>
      getCapturedEmails().filter(
        (message) => message.text === "scheduled_job_failed digest",
      ).length;

    await runScheduled("0 6 * * *");
    expect(await scheduledJobAlertCount("digest")).toBe(1);
    expect(await scheduledJobAlertRow("digest")).toMatchObject({ active: 1, unsent: 0 });
    expect(digestAlertEmails()).toBe(1);

    await setClock(addMinutes(BASE_CLOCK, 16));
    await runScheduled("* * * * *");
    expect(await scheduledJobAlertCount("digest")).toBe(1);
    expect(digestAlertEmails()).toBe(1);

    Object.assign(env.SEND_EMAIL, sendEmailBinding);
    await setClock(addMinutes(BASE_CLOCK, 32));
    await runScheduled("* * * * *");
    expect(await scheduledJobAlertRow("digest")).toMatchObject({ active: 0, unsent: 0 });
    expect(await scheduledJobAlertCount("digest")).toBe(1);
  });

  it("R9-CRON1 minute and digest producers ping their own configured stream URLs", async () => {
    await seedDigestScenario();
    clearCapturedHeartbeatFetches();

    await runScheduled("0 6 * * *");
    expect(getCapturedHeartbeatFetches()).toContain(env.HEARTBEAT_URL_DIGEST);
    expect(getCapturedHeartbeatFetches()).not.toContain(env.HEARTBEAT_URL_MINUTE);

    clearCapturedHeartbeatFetches();
    await runScheduled("* * * * *");
    expect(getCapturedHeartbeatFetches()).toContain(env.HEARTBEAT_URL_MINUTE);
    expect(getCapturedHeartbeatFetches()).not.toContain(env.HEARTBEAT_URL_DIGEST);
  });

  it("rebuild throws reconciliation_incomplete when reconciliation is not succeeded", async () => {
    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    // R9-CRON1 decision (d): an incomplete reconciliation is not a verified rebuild. The grant
    // listing is refused, so the reconciliation that rebuild runs last returns failed.
    await expect(
      rebuildAbo(envWithPlatform(platformRefusing(["listGrants"])), {
        providerTransactionReferences: [],
      }),
    ).rejects.toThrow(/reconciliation_incomplete/u);
  });

  it("R9-AO6 expired hmac-invalid objects are removed across R2 pages and resume after an interrupted run", async () => {
    await setClock(BASE_CLOCK);
    const dayAt = (offsetDays: number): string =>
      addDays(BASE_CLOCK, offsetDays).slice(0, 10);
    const expired = [-33, -32, -31].map(
      (offset) => `hmac-invalid/${dayAt(offset)}/expired-${-offset}`,
    );
    const kept = [
      `hmac-invalid/${dayAt(-30)}/cutoff-day`,
      `hmac-invalid/${dayAt(-1)}/recent`,
    ];
    const outsidePrefix = "evidence/keep-raw-proof";
    for (const key of [...expired, ...kept, outsidePrefix]) {
      await env.R2.put(key, "body");
    }
    const { runHousekeeping } = await import("../../src/housekeeping/run.js");

    const first = await runHousekeeping(env as never, {
      r2PageLimit: 2,
      deleteBudget: 2,
    });
    expect(first).toBe("deferred");
    const second = await runHousekeeping(env as never, {
      r2PageLimit: 2,
      deleteBudget: 2,
    });
    expect(second).toBe("succeeded");

    for (const key of expired) {
      expect(await env.R2.head(key)).toBeNull();
    }
    for (const key of [...kept, outsidePrefix]) {
      expect(await env.R2.head(key)).not.toBeNull();
    }
  });

  it("R9-AO5 a valid fresh feed health result clears a previously active AL-15", async () => {
    await seedBackendFeedPull(addMinutes(BASE_CLOCK, -6));
    clearCapturedEmails();
    await runScheduled("0 * * * *");
    expect(emailsWithCode("AL-15").length).toBeGreaterThanOrEqual(1);

    await seedBackendFeedPull(addMinutes(addHours(BASE_CLOCK, 1), -1));
    await setClock(addHours(BASE_CLOCK, 1));
    await runScheduled("0 * * * *");

    const row = await env.DB.prepare(
      `SELECT active, unsent FROM alert WHERE alert_key = 'AL-15:feed'`,
    ).first<{ active: number; unsent: number }>();
    expect(row?.active).toBe(0);
    expect(row?.unsent).toBe(0);
  });

  it("E2E-P4.11-07 R9-CRON1 Digest send failure retried; daily digest stream ping sent", async () => {
    await seedDigestScenario();
    installDigestRetrySendBinding();
    clearCapturedEmails();
    clearCapturedHeartbeatFetches();

    await runScheduled("0 6 * * *");

    expect(digestSendAttempts).toBe(2);
    expect(digestEmails()).toHaveLength(1);
    // R9-CRON1 / RT2 (was HEARTBEAT_URL): the digest success is the abo_daily_digest stream.
    expect(getCapturedHeartbeatFetches()).toContain(env.HEARTBEAT_URL_DIGEST);
  });

  it("E2E-P4.11-03 FM-10: feed_consumer stale for 6 min → AL-15 hourly", async () => {
    await seedBackendFeedPull(addMinutes(BASE_CLOCK, -6));
    clearCapturedEmails();

    await runScheduled("0 * * * *");
    expect(emailsWithCode("AL-15").length).toBeGreaterThanOrEqual(1);

    await setClock(addHours(BASE_CLOCK, 1));
    clearCapturedEmails();
    await runScheduled("0 * * * *");
    expect(emailsWithCode("AL-15").length).toBe(1);
  });

  it("E2E-P4.11-04 AD-9: extra issuer kid and unannounced operator credential → AL-22", async () => {
    await registerClinicIssuerKey();
    const extraKid = await seedExtraUnpinnedIssuerKey();
    const extraCredential = await seedExtraUnannouncedOperatorCredential();
    clearCapturedEmails();

    await runScheduled("0 * * * *");

    const al22Emails = emailsWithCode("AL-22");
    expect(al22Emails.length).toBeGreaterThanOrEqual(2);
    expect(
      al22Emails.some((email) => email.text.includes(extraKid)),
    ).toBe(true);
    expect(
      al22Emails.some((email) =>
        email.text.includes(extraCredential.credentialId),
      ),
    ).toBe(true);

    await clearWatchAlertSeeds();
    const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const signerCredentialId = await seedActiveOperatorCredential(
      signerAuthenticator,
    );
    const rememberedAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const rememberedCredentialId = "watch-remembered-credential-id";
    const accessJwt = await mintVendorAccessJwt();
    const registered = await registerOperatorCredentialWithSigner({
      credentialId: rememberedCredentialId,
      signerCredentialId,
      signerAuthenticator,
      attestationAuthenticator: rememberedAuthenticator,
      accessJwt,
    });
    expect(registered.result).toBe("ok");
    const detail = JSON.parse(String(registered.detail)) as Record<string, unknown>;
    await seedSeenOperatorCredential(detail);
    await setClock(String(detail.activates_at));

    clearCapturedEmails();
    await runScheduled("0 * * * *");
    expect(
      emailsWithCode("AL-22").filter((email) =>
        email.text.includes(rememberedCredentialId),
      ),
    ).toHaveLength(0);
  });

  it("R9-REC2/R9-REC3 restores due grant work once against its original provider order", async () => {
    const expectations = await setupRebuildHarness();
    const paid = await paidCheckoutWithGrant(
      ORG_REBUILD,
      expectations,
      PAID_PAYMOB_TXN_ID,
      "req-rebuild-paid",
    );
    const gapCheckoutId = await gapCheckoutWithIntentionOnly(
      ORG_REBUILD,
      expectations,
      "req-rebuild-gap",
    );
    await exportLedgerFacts();

    const paidCheckoutBefore = await env.DB.prepare(
      `SELECT checkout_id, state FROM checkout_status WHERE checkout_id = ?`,
    )
      .bind(paid.checkoutId)
      .first<{ checkout_id: string; state: string }>();
    const paidPaymentBefore = await env.DB.prepare(
      `SELECT payment_id FROM payment WHERE payment_id = ?`,
    )
      .bind(paid.paymentId)
      .first<{ payment_id: string }>();
    const ledgerListed = await env.R2.list({ prefix: "ledger/" });
    expect(ledgerListed.objects.length).toBeGreaterThan(0);
    const providerLedger = await Promise.all(
      ledgerListed.objects.map(async (object) => {
        const body = await env.R2.get(object.key);
        return JSON.parse(await body!.text()) as {
          table: string;
          row?: Record<string, unknown>;
        };
      }),
    );
    expect(providerLedger.some((line) => line.table === "paymob_intention")).toBe(false);
    expect(providerLedger
      .filter((line) => line.table === "paymob_intention_attempt_event")
      .every((line) => !Object.hasOwn(line.row ?? {}, "client_secret")))
      .toBe(true);

    const gapOrderBefore = await env.DB.prepare(
      `SELECT order_id FROM paymob_intention_attempt WHERE checkout_id = ? AND state = 'created'`,
    )
      .bind(gapCheckoutId)
      .first<{ order_id: string }>();
    expect(gapOrderBefore?.order_id).toBeTruthy();

    await wipeAboD1();
    await reapplyAboSchema();
    expect(await tableCount("billing_contact")).toBe(0);

    const { rebuildAbo } = await import("../../src/rebuild.js");
    await scriptPaymobInquiry("bound_success");
    const platform = env.PLATFORM;
    const rebuildPlatform = {
      grant: async (args: Record<string, unknown>) => {
        const result = await platform.grant(args);
        if (result.result === "applied" || result.result === "already_applied") {
          await syncPlatformGrantLedger(ORG_REBUILD);
          await drainPlatformDurableObjects();
          await exportFacts(env);
        }
        return result;
      },
      listGrants: (args: Record<string, unknown>) => platform.listGrants(args),
      readCoverageEvents: (args: Record<string, unknown>) =>
        platform.readCoverageEvents(args),
      getCoverage: (args: Record<string, unknown>) => platform.getCoverage(args),
    };
    await rebuildAbo({ ...env, PLATFORM: rebuildPlatform } as never, {
      providerTransactionReferences: [String(GAP_PAYMOB_TXN_ID)],
    });

    const restoredPaidCheckout = await env.DB.prepare(
      `SELECT state FROM checkout_status WHERE checkout_id = ?`,
    )
      .bind(paid.checkoutId)
      .first<{ state: string }>();
    expect(restoredPaidCheckout?.state).toBe(paidCheckoutBefore?.state);
    expect(
      await rowExists("payment", "payment_id", paid.paymentId),
    ).toBe(true);
    expect(await tableCount("billing_contact")).toBe(0);
    const restoredPaymentLineage = await env.DB.prepare(
      `SELECT confirmation_inquiry_id FROM payment WHERE payment_id = ?`,
    ).bind(paid.paymentId).first<{ confirmation_inquiry_id: string }>();
    expect(restoredPaymentLineage?.confirmation_inquiry_id).toBeTruthy();
    expect(await rowExists(
      "inquiry_result", "inquiry_id", restoredPaymentLineage!.confirmation_inquiry_id,
    )).toBe(true);
    const retainedExistingPaymentInquiry = await env.DB.prepare(
      `SELECT outcome, decision, payment_id, inquiry_id, evidence_sha256
       FROM rebuild_inquiry_attempt
       WHERE checkout_id = ? AND payment_id = ? AND outcome = 'already_recorded'
       ORDER BY observed_at DESC LIMIT 1`,
    ).bind(paid.checkoutId, paid.paymentId).first<{
      outcome: string; decision: string; payment_id: string;
      inquiry_id: string; evidence_sha256: string;
    }>();
    expect(retainedExistingPaymentInquiry).toMatchObject({
      outcome: "already_recorded",
      decision: "existing_payment_grant_reconfirmed",
      payment_id: paid.paymentId,
      inquiry_id: restoredPaymentLineage?.confirmation_inquiry_id,
    });
    expect(retainedExistingPaymentInquiry?.evidence_sha256).toMatch(/^[a-f0-9]{64}$/u);

    const gapOrderAfter = await env.DB.prepare(
      `SELECT order_id FROM paymob_intention_attempt WHERE checkout_id = ? AND state = 'created'`,
    )
      .bind(gapCheckoutId)
      .first<{ order_id: string }>();
    expect(gapOrderAfter?.order_id).toBe(gapOrderBefore?.order_id);
    const recoveredAttempt = await env.DB.prepare(
      `SELECT state, intention_id, order_id, client_secret, expires_at
       FROM paymob_intention_attempt WHERE checkout_id = ? AND state = 'created'`,
    ).bind(gapCheckoutId).first<{
      state: string;
      intention_id: string | null;
      order_id: string | null;
      client_secret: string | null;
      expires_at: string | null;
    }>();
    expect(recoveredAttempt).toMatchObject({
      state: "created",
      intention_id: expect.any(String),
      order_id: gapOrderBefore?.order_id,
      client_secret: null,
      expires_at: expect.any(String),
    });

    const gapPaymentId = await paymentIdForCheckout(gapCheckoutId);
    expect(gapPaymentId).not.toBeNull();
    const gapGrantId = await grantIdPaid(gapPaymentId!);
    const grantOutcome = await env.DB.prepare(
      `SELECT result FROM grant_outcome WHERE grant_id = ?`,
    )
      .bind(gapGrantId)
      .first<{ result: string }>();
    expect(grantOutcome?.result).toBe("applied");
    const grantWorkBeforeRepeat = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant' AND subject_id = ?`,
    ).bind(gapPaymentId).first<{ n: number }>();
    const grantOutcomeCountBeforeRepeat = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM grant_outcome WHERE grant_id = ?`,
    ).bind(gapGrantId).first<{ n: number }>();
    await rebuildAbo({ ...env, PLATFORM: rebuildPlatform } as never, {
      providerTransactionReferences: [String(GAP_PAYMOB_TXN_ID)],
    });
    expect(await paymentIdForCheckout(gapCheckoutId)).toBe(gapPaymentId);
    expect(await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant' AND subject_id = ?`,
    ).bind(gapPaymentId).first<{ n: number }>()).toEqual(grantWorkBeforeRepeat);
    expect(await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM grant_outcome WHERE grant_id = ?`,
    ).bind(gapGrantId).first<{ n: number }>()).toEqual(grantOutcomeCountBeforeRepeat);
    expect(paidPaymentBefore?.payment_id).toBe(paid.paymentId);
    const openFindings = await env.DB.prepare(
      `SELECT f.finding_id, f.kind, f.subject, f.detail
       FROM finding f
       LEFT JOIN finding_resolution fr ON f.finding_id = fr.finding_id
       WHERE fr.finding_id IS NULL`,
    ).all<{ finding_id: string; kind: string; subject: string; detail: string }>();
    expect(
      openFindings.results ?? [],
      `FM-19 rebuild left unresolved findings for payment ${gapPaymentId}`,
    ).toEqual([]);

    const runbook = readRebuildRunbook();
    expect(runbook).toContain("provider transaction references");
    expect(runbook.toLowerCase()).toContain("dashboard export");
  });

  it("R9-REC2 missing original provider correlation is disputed without creating a replacement order", async () => {
    const expectations = await setupRebuildHarness();
    await putBillingContact(ORG_REBUILD);
    await ensureGrantTenantBinding(ORG_REBUILD);
    await scriptPaymobStub("refuse");
    const response = await billingFetch("/v1/checkouts", {
      method: "POST",
      headers: await administratorHeaders(ORG_REBUILD),
      body: JSON.stringify({
        client_request_id: "req-r9-rec2-missing-correlation",
        offer_id: expectations.offer_id,
        offer_version: expectations.version,
        terms_version: expectations.terms.version,
      }),
    });
    expect(response.status).toBe(503);
    const responseBody = await response.json() as Record<string, unknown>;
    const checkoutId = String(responseBody.checkout_id);
    await exportLedgerFacts();

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    await rebuildAbo(env as never, { providerTransactionReferences: [] });
    await rebuildAbo(env as never, { providerTransactionReferences: [] });

    const status = await env.DB.prepare(
      `SELECT state FROM checkout_status WHERE checkout_id = ?`,
    ).bind(checkoutId).first<{ state: string }>();
    expect(status?.state).toBe("disputed");
    expect(await rowExists("paymob_intention", "checkout_id", checkoutId)).toBe(false);
    const finding = await env.DB.prepare(
      `SELECT kind FROM finding WHERE subject = ? AND kind = 'rebuild_missing_provider_correlation'`,
    ).bind(checkoutId).first<{ kind: string }>();
    expect(finding?.kind).toBe("rebuild_missing_provider_correlation");
  });

  it("R9-REC2 persists deferred and unavailable inquiry outcomes without invented evidence", async () => {
    const expectations = await setupRebuildHarness();
    const checkoutId = await gapCheckoutWithIntentionOnly(
      ORG_REBUILD,
      expectations,
      "req-r9-rec2-deferred-inquiry",
    );
    await exportLedgerFacts();
    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    const testClock = await env.DB.prepare(
      `SELECT now_iso FROM harness_test_clock WHERE id = 'default'`,
    ).first<{ now_iso: string }>();
    const minuteKey = new Date(Date.parse(testClock!.now_iso)).toISOString().slice(0, 16);
    await env.DB.prepare(
      `INSERT INTO inquiry_spend (minute_key, spent) VALUES (?, 2)
       ON CONFLICT(minute_key) DO UPDATE SET spent = 2`,
    ).bind(minuteKey).run();
    await rebuildAbo(env as never, {
      providerTransactionReferences: [String(GAP_PAYMOB_TXN_ID)],
    });

    const deferred = await env.DB.prepare(
      `SELECT attempt_id, outcome, decision, provider_txn_ref, inquiry_id, evidence_sha256
       FROM rebuild_inquiry_attempt
       WHERE checkout_id = ? AND outcome = 'deferred' LIMIT 1`,
    ).bind(checkoutId).first<Record<string, unknown>>();
    expect(deferred).toMatchObject({
      outcome: "deferred",
      decision: "shared_inquiry_budget_unavailable",
      provider_txn_ref: String(GAP_PAYMOB_TXN_ID),
      inquiry_id: null,
      evidence_sha256: null,
    });
    await env.DB.prepare(
      `UPDATE inquiry_spend SET spent = 0 WHERE minute_key = ?`,
    ).bind(minuteKey).run();
    await scriptPaymobInquiry("rate_limit");
    await rebuildAbo(env as never, {
      providerTransactionReferences: [String(GAP_PAYMOB_TXN_ID)],
    });
    const unavailableResult = await env.DB.prepare(
      `SELECT attempt_id, outcome, decision, provider_txn_ref, inquiry_id, evidence_sha256
       FROM rebuild_inquiry_attempt
       WHERE checkout_id = ? AND outcome = 'unavailable' LIMIT 1`,
    ).bind(checkoutId).first<Record<string, unknown>>();
    expect(unavailableResult).toMatchObject({
      outcome: "unavailable",
      decision: "provider_inquiry_result_unavailable",
      provider_txn_ref: String(GAP_PAYMOB_TXN_ID),
      inquiry_id: null,
      evidence_sha256: null,
    });
    expect(await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM fact_log
       WHERE "table" = 'rebuild_inquiry_attempt' AND key IN (?, ?)`,
    ).bind(deferred?.attempt_id ?? "", unavailableResult?.attempt_id ?? "")
      .first<{ n: number }>()).toMatchObject({ n: 2 });
  });

  it("R9-REC1 restores secretless created attempts without redirect, provider retry, or replacement", async () => {
    const expectations = await setupRebuildHarness();
    await putBillingContact(ORG_REBUILD);
    const requestId = "req-r9-secretless-created-attempt";
    const { checkoutId } = await postCheckout(ORG_REBUILD, expectations, requestId);
    const originalProviderRequest = await getLastPaymobIntentionBody();
    await exportLedgerFacts();

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    await rebuildAbo(env as never, { providerTransactionReferences: [] });

    const recovered = await env.DB.prepare(
      `SELECT state, intention_id, order_id, client_secret, expires_at
       FROM paymob_intention_attempt WHERE checkout_id = ? AND attempt_no = 1`,
    ).bind(checkoutId).first<{
      state: string;
      intention_id: string | null;
      order_id: string | null;
      client_secret: string | null;
      expires_at: string | null;
    }>();
    expect(recovered).toMatchObject({
      state: "created",
      intention_id: expect.any(String),
      order_id: "9001",
      client_secret: null,
      expires_at: expect.any(String),
    });

    const wrongOrderCallback = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      {
        txnId: 96776,
        amountMinor: await chargedPriceMinorForCheckout(checkoutId),
        orderId: "unrelated-provider-order",
      },
    );
    expect(wrongOrderCallback.status).toBe(200);
    expect(await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM payment WHERE checkout_id = ?`,
    ).bind(checkoutId).first<{ n: number }>()).toMatchObject({ n: 0 });

    const repeat = await billingFetch("/v1/checkouts", {
      method: "POST",
      headers: await administratorHeaders(ORG_REBUILD),
      body: JSON.stringify({
        client_request_id: requestId,
        offer_id: expectations.offer_id,
        offer_version: expectations.version,
        terms_version: expectations.terms.version,
      }),
    });
    expect(repeat.status).toBe(503);
    expect(await getLastPaymobIntentionBody()).toEqual(originalProviderRequest);
    expect(await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM paymob_intention_attempt WHERE checkout_id = ?`,
    ).bind(checkoutId).first<{ n: number }>()).toMatchObject({ n: 1 });

    await setClock(new Date(Date.parse(recovered!.expires_at!) + 60_000).toISOString());
    const expiredRepeat = await billingFetch("/v1/checkouts", {
      method: "POST",
      headers: await administratorHeaders(ORG_REBUILD),
      body: JSON.stringify({
        client_request_id: requestId,
        offer_id: expectations.offer_id,
        offer_version: expectations.version,
        terms_version: expectations.terms.version,
      }),
    });
    expect(expiredRepeat.status).toBe(503);
    expect(await getLastPaymobIntentionBody()).toEqual(originalProviderRequest);
    expect(await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM paymob_intention_attempt WHERE checkout_id = ?`,
    ).bind(checkoutId).first<{ n: number }>()).toMatchObject({ n: 1 });
  });

  it("R9-REC1 migration permits only secretless created rows with complete provider identity", async () => {
    const expectations = await setupRebuildHarness();
    await putBillingContact(ORG_REBUILD);
    const { checkoutId } = await postCheckout(
      ORG_REBUILD,
      expectations,
      "req-r9-created-attempt-null-secret-constraint",
    );
    const attempt = await env.DB.prepare(
      `SELECT lease_token, lease_until, special_reference, intention_id, order_id, expires_at,
              started_at, finished_at
       FROM paymob_intention_attempt WHERE checkout_id = ? AND attempt_no = 1`,
    ).bind(checkoutId).first<Record<string, string>>();
    expect(attempt).not.toBeNull();
    await env.DB.prepare(
      `UPDATE paymob_intention_attempt SET client_secret = NULL
       WHERE checkout_id = ? AND attempt_no = 1`,
    ).bind(checkoutId).run();
    expect(await env.DB.prepare(
      `SELECT client_secret FROM paymob_intention_attempt WHERE checkout_id = ? AND attempt_no = 1`,
    ).bind(checkoutId).first<{ client_secret: string | null }>()).toMatchObject({
      client_secret: null,
    });

    const makeIncomplete = async (
      attemptNo: number,
      missing: "intention_id" | "order_id" | "expires_at",
    ): Promise<void> => {
      const values = {
        checkoutId,
        attemptNo,
        leaseToken: `incomplete-${attemptNo}`,
        leaseUntil: attempt!.lease_until,
        reference: `incomplete-${attemptNo}`,
        intentionId: missing === "intention_id" ? null : attempt!.intention_id,
        orderId: missing === "order_id" ? null : attempt!.order_id,
        expiresAt: missing === "expires_at" ? null : attempt!.expires_at,
        startedAt: attempt!.started_at,
        finishedAt: attempt!.finished_at,
      };
      await expect(env.DB.prepare(
        `INSERT INTO paymob_intention_attempt (
          checkout_id, attempt_no, state, lease_token, lease_until, special_reference,
          intention_id, order_id, client_secret, expires_at, started_at, finished_at
        ) VALUES (?, ?, 'created', ?, ?, ?, ?, ?, NULL, ?, ?, ?)`,
      ).bind(values.checkoutId, values.attemptNo, values.leaseToken, values.leaseUntil,
        values.reference, values.intentionId, values.orderId, values.expiresAt,
        values.startedAt, values.finishedAt).run()).rejects.toThrow();
    };
    await makeIncomplete(2, "intention_id");
    await makeIncomplete(3, "order_id");
    await makeIncomplete(4, "expires_at");
  });

  it("R9-REC3 recovery with an amount mismatch is withheld without grant work", async () => {
    const expectations = await setupRebuildHarness();
    await gapCheckoutWithIntentionOnly(
      ORG_REBUILD,
      expectations,
      "req-r9-rec3-recovered-mismatch",
    );
    await exportLedgerFacts();
    await wipeAboD1();
    await reapplyAboSchema();
    await scriptPaymobInquiry("amount_mismatch");

    const { rebuildAbo } = await import("../../src/rebuild.js");
    await rebuildAbo(env as never, { providerTransactionReferences: [String(GAP_PAYMOB_TXN_ID)] });

    const payment = await env.DB.prepare(
      `SELECT payment_id, disposition FROM payment LIMIT 1`,
    ).first<{ payment_id: string; disposition: string }>();
    expect(payment?.disposition).toBe("withheld_mismatch");
    expect(await tableCount("grant_request")).toBe(0);
    const grantWork = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant'`,
    ).first<{ n: number }>();
    expect(grantWork?.n).toBe(0);
    expect(await tableCount("inquiry_result")).toBe(1);
    const alert = await env.DB.prepare(
      `SELECT active FROM alert WHERE code = 'AL-05' LIMIT 1`,
    ).first<{ active: number }>();
    expect(alert?.active).toBe(1);
    const factsBeforeRepeat = await tableCount("fact_log");
    await rebuildAbo(env as never, { providerTransactionReferences: [String(GAP_PAYMOB_TXN_ID)] });
    expect(await tableCount("fact_log")).toBe(factsBeforeRepeat);
    expect(await tableCount("grant_request")).toBe(0);
    expect(await rowExists("payment", "payment_id", payment!.payment_id)).toBe(true);
  });

  it("R9-REC3 recovery with a currency mismatch is withheld without grant work", async () => {
    const expectations = await setupRebuildHarness();
    await gapCheckoutWithIntentionOnly(
      ORG_REBUILD,
      expectations,
      "req-r9-rec3-recovered-currency-mismatch",
    );
    await exportLedgerFacts();
    await wipeAboD1();
    await reapplyAboSchema();
    await scriptPaymobInquiry("currency_mismatch");

    const { rebuildAbo } = await import("../../src/rebuild.js");
    await rebuildAbo(env as never, { providerTransactionReferences: [String(GAP_PAYMOB_TXN_ID)] });

    const payment = await env.DB.prepare(
      `SELECT disposition FROM payment LIMIT 1`,
    ).first<{ disposition: string }>();
    expect(payment?.disposition).toBe("withheld_mismatch");
    expect(await tableCount("grant_request")).toBe(0);
    const grantWork = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant'`,
    ).first<{ n: number }>();
    expect(grantWork?.n).toBe(0);
    const alert = await env.DB.prepare(
      `SELECT active FROM alert WHERE code = 'AL-05' LIMIT 1`,
    ).first<{ active: number }>();
    expect(alert?.active).toBe(1);
    const factsBeforeRepeat = await tableCount("fact_log");
    await rebuildAbo(env as never, { providerTransactionReferences: [String(GAP_PAYMOB_TXN_ID)] });
    expect(await tableCount("fact_log")).toBe(factsBeforeRepeat);
    expect(await tableCount("grant_request")).toBe(0);
  });

  it("R9-REC2 interrupted reversal resumes its exact request after export and rebuild", async () => {
    const expectations = await setupRebuildHarness();
    const paid = await paidCheckoutWithGrant(
      ORG_REBUILD,
      expectations,
      PAID_PAYMOB_TXN_ID,
      "req-r9-secretless-reversal-binding",
    );
    const originalAttempt = await env.DB.prepare(
      `SELECT order_id FROM paymob_intention_attempt
       WHERE checkout_id = ? AND state = 'created' AND attempt_no = 1`,
    ).bind(paid.checkoutId).first<{ order_id: string }>();
    expect(originalAttempt?.order_id).toBe("9001");
    const originalProviderRequest = await getLastPaymobIntentionBody();
    await exportLedgerFacts();

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    await scriptPaymobInquiry("bound_success");
    await rebuildAbo(env as never, {
      providerTransactionReferences: [String(PAID_PAYMOB_TXN_ID)],
    });

    const recoveredAttempt = await env.DB.prepare(
      `SELECT state, order_id, client_secret FROM paymob_intention_attempt
       WHERE checkout_id = ? AND attempt_no = 1`,
    ).bind(paid.checkoutId).first<{
      state: string;
      order_id: string | null;
      client_secret: string | null;
    }>();
    expect(recoveredAttempt).toEqual({
      state: "created",
      order_id: originalAttempt!.order_id,
      client_secret: null,
    });
    expect(await paymentIdForCheckout(paid.checkoutId)).toBe(paid.paymentId);

    // The authenticated transaction endpoint returns an unrelated order. It
    // cannot create reversal evidence or work for the restored payment.
    await setClock(new Date(Date.parse(await currentHarnessClockIso()) + 60_000).toISOString());
    await scriptPaymobInquiry("unbound", await chargedPriceMinorForCheckout(paid.checkoutId),
      await chargedPriceMinorForCheckout(paid.checkoutId));
    await rebuildAbo(env as never, {
      providerTransactionReferences: [String(PAID_PAYMOB_TXN_ID)],
    });
    expect(await rowExists("reversal", "payment_id", paid.paymentId)).toBe(false);
    expect(await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'reverse'`,
    ).first<{ n: number }>()).toMatchObject({ n: 0 });

    // A new inquiry slot and the exact original order/transaction binding
    // permit only the existing reversal evidence path to record the reversal.
    const amount = await chargedPriceMinorForCheckout(paid.checkoutId);
    await setClock(new Date(Date.parse(await currentHarnessClockIso()) + 60_000).toISOString());
    await scriptPaymobInquiry("reversed", amount, amount);
    const platform = env.PLATFORM;
    const interruptedPlatform = {
      grant: (args: Record<string, unknown>) => platform.grant(args),
      listGrants: (args: Record<string, unknown>) => platform.listGrants(args),
      readCoverageEvents: (args: Record<string, unknown>) =>
        platform.readCoverageEvents(args),
      getCoverage: (args: Record<string, unknown>) => platform.getCoverage(args),
      voidForReversal: async () => { throw new Error("simulated_interruption"); },
    };
    await rebuildAbo({ ...env, PLATFORM: interruptedPlatform } as never, {
      providerTransactionReferences: [String(PAID_PAYMOB_TXN_ID)],
    });
    const reversal = await env.DB.prepare(
      `SELECT reversal_id, payment_id, source, detected_via, amount_minor,
              cumulative_reversed_minor, dedupe_key
       FROM reversal WHERE payment_id = ?`,
    ).bind(paid.paymentId).first<{
      reversal_id: string;
      payment_id: string;
      source: string;
      detected_via: string;
      amount_minor: number;
      cumulative_reversed_minor: number;
      dedupe_key: string;
    }>();
    expect(reversal).toMatchObject({
      payment_id: paid.paymentId,
      source: "provider",
      detected_via: "inquiry",
      amount_minor: amount,
      cumulative_reversed_minor: amount,
      dedupe_key: `paymob:${PAID_PAYMOB_TXN_ID}:reversal:${amount}`,
    });
    const reversalOutcome = await env.DB.prepare(
      `SELECT result FROM reversal_outcome WHERE reversal_id = ?`,
    ).bind(reversal!.reversal_id).first<{ result: string }>();
    expect(reversalOutcome).toBeNull();
    const requestBeforeRebuild = await env.DB.prepare(
      `SELECT reversal_id, grant_id, reason, evidence_sha256, partial,
              contract_version, canonical_body, body_sha256, created_at
       FROM reversal_request WHERE reversal_id = ?`,
    ).bind(reversal!.reversal_id).first<Record<string, unknown>>();
    expect(requestBeforeRebuild?.canonical_body).toBeTruthy();
    expect(await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM fact_log
       WHERE "table" = 'reversal_request' AND key = ?`,
    ).bind(reversal!.reversal_id).first<{ n: number }>()).toMatchObject({ n: 1 });

    await exportLedgerFacts();
    await wipeAboD1();
    await reapplyAboSchema();
    await scriptPaymobInquiry("rate_limit");
    let resumedVoidBody: Record<string, unknown> | null = null;
    const resumedPlatform = {
      grant: (args: Record<string, unknown>) => platform.grant(args),
      listGrants: (args: Record<string, unknown>) => platform.listGrants(args),
      readCoverageEvents: (args: Record<string, unknown>) =>
        platform.readCoverageEvents(args),
      getCoverage: (args: Record<string, unknown>) => platform.getCoverage(args),
      voidForReversal: async (args: Record<string, unknown>) => {
        resumedVoidBody = args;
        return platform.voidForReversal(args);
      },
    };
    await rebuildAbo({ ...env, PLATFORM: resumedPlatform } as never, {
      providerTransactionReferences: [String(PAID_PAYMOB_TXN_ID)],
    });
    const requestAfterRebuild = await env.DB.prepare(
      `SELECT reversal_id, grant_id, reason, evidence_sha256, partial,
              contract_version, canonical_body, body_sha256, created_at
       FROM reversal_request WHERE reversal_id = ?`,
    ).bind(reversal!.reversal_id).first<Record<string, unknown>>();
    expect(requestAfterRebuild).toEqual(requestBeforeRebuild);
    expect(resumedVoidBody).toMatchObject(JSON.parse(String(requestBeforeRebuild!.canonical_body)));
    const resumedOutcome = await env.DB.prepare(
      `SELECT result FROM reversal_outcome WHERE reversal_id = ?`,
    ).bind(reversal!.reversal_id).first<{ result: string }>();
    expect(resumedOutcome?.result).toMatch(/^(applied|already_applied)$/u);
    const retainedPaymentDisposition = await env.DB.prepare(
      `SELECT disposition FROM payment WHERE payment_id = ?`,
    ).bind(paid.paymentId).first<{ disposition: string }>();
    expect(retainedPaymentDisposition?.disposition).toBe("grant");
    const finalAttempt = await env.DB.prepare(
      `SELECT state, order_id, client_secret FROM paymob_intention_attempt
       WHERE checkout_id = ? AND attempt_no = 1`,
    ).bind(paid.checkoutId).first();
    expect(finalAttempt).toEqual({
      state: "created",
      order_id: originalAttempt!.order_id,
      client_secret: null,
    });
    expect(await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM paymob_intention_attempt WHERE checkout_id = ?`,
    ).bind(paid.checkoutId).first<{ n: number }>()).toMatchObject({ n: 1 });
    expect(await getLastPaymobIntentionBody()).toEqual(originalProviderRequest);
  });

  it("R9-REC2 rejected and transient platform audit facts do not complete accepted local work", async () => {
    await setupRebuildHarness();
    const commandId = "cmd-r9-local-platform-audit-recovery";
    const now = await currentHarnessClockIso();
    const later = new Date(Date.parse(now) + 1_000).toISOString();
    const operation = { op: "release_payment", actor_email: VENDOR_OPERATOR_EMAIL };
    const operationJson = new TextDecoder().decode(canonicalize(operation));
    const assertionJson = "{}";
    const argsJson = new TextDecoder().decode(canonicalize({ payment_id: "pay-r9-audit" }));
    const intent = {
      payload_version: 1,
      command_id: commandId,
      command_kind: "local_hp",
      method: "release_payment",
      subject_id: "pay-r9-audit",
      actor_email: VENDOR_OPERATOR_EMAIL,
      operation_json: operationJson,
      args_json: argsJson,
      operation_sha256: await sha256Hex(canonicalize(operation)),
      assertion_json: assertionJson,
      assertion_sha256: await sha256Hex(canonicalize({})),
      contract_version: CONTRACT_VERSION,
      accepted_at: now,
      signer_credential_id: "credential-r9-audit",
      erasure_generation: null,
      scope_max_contact_version: null,
    };
    await env.DB.batch([
      ...await commandFactStatements(env, {
        commandId,
        kind: "command_intent",
        payload: intent,
        createdAt: now,
      }),
      ...await commandFactStatements(env, {
        commandId,
        kind: "local_result",
        payload: {
          payload_version: 1,
          command_id: commandId,
          method: "release_payment",
          result: "ok",
          at: now,
        },
        createdAt: now,
      }),
      ...await commandFactStatements(env, {
        commandId,
        kind: "platform_result",
        payload: {
          payload_version: 1,
          command_id: commandId,
          phase: "platform_operator_action",
          result: "ok",
          at: now,
        },
        createdAt: now,
      }),
      ...await commandFactStatements(env, {
        commandId,
        kind: "platform_result",
        payload: {
          payload_version: 1,
          command_id: commandId,
          phase: "platform_operator_action",
          result: "transient",
          at: later,
        },
        createdAt: later,
      }),
    ]);
    await exportLedgerFacts();

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    await rebuildAbo(env as never, { providerTransactionReferences: [] });

    const recovered = await env.DB.prepare(
      `SELECT stage FROM accepted_operator_command WHERE command_id = ?`,
    ).bind(commandId).first<{ stage: string }>();
    expect(recovered?.stage).toBe("local_applied");
  });

  it("R9-REC1 preserves cancellation then records a matched late success once", async () => {
    const expectations = await setupRebuildHarness();
    await putBillingContact(ORG_REBUILD);
    const { checkoutId } = await postCheckout(
      ORG_REBUILD,
      expectations,
      "req-r9-rec1-cancelled-checkout",
    );
    const at = new Date(Date.parse(await currentHarnessClockIso()) + 10_000).toISOString();
    const event = {
      checkout_id: checkoutId,
      kind: "cancelled",
      source: "operator",
      ref: "action-r9-rec1-cancelled",
      actor: VENDOR_OPERATOR_EMAIL,
      at,
      contract_version: CONTRACT_VERSION,
    };
    const eventJson = new TextDecoder().decode(canonicalize(event));
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO checkout_event (
           checkout_id, kind, source, ref, actor, at, contract_version
         ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        event.checkout_id, event.kind, event.source, event.ref, event.actor,
        event.at, event.contract_version,
      ),
      env.DB.prepare(
        `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
         VALUES ('checkout_event', ?, ?, ?, ?)`,
      ).bind(
        `${checkoutId}:cancelled:${at}`, await sha256Hex(canonicalize(event)),
        eventJson, at,
      ),
      env.DB.prepare(
        `UPDATE checkout_status SET state = 'cancelled', last_event_at = ? WHERE checkout_id = ?`,
      ).bind(at, checkoutId),
    ]);
    await exportLedgerFacts();

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    await rebuildAbo(env as never, { providerTransactionReferences: [] });

    const status = await env.DB.prepare(
      `SELECT state FROM checkout_status WHERE checkout_id = ?`,
    ).bind(checkoutId).first<{ state: string }>();
    expect(status?.state).toBe("cancelled");
    const restoredEvent = await env.DB.prepare(
      `SELECT kind FROM checkout_event WHERE checkout_id = ? AND kind = 'cancelled'`,
    ).bind(checkoutId).first<{ kind: string }>();
    expect(restoredEvent?.kind).toBe("cancelled");
    const restoredAttempt = await env.DB.prepare(
      `SELECT state, order_id, client_secret FROM paymob_intention_attempt
       WHERE checkout_id = ? AND attempt_no = 1`,
    ).bind(checkoutId).first<{ state: string; order_id: string | null; client_secret: string | null }>();
    expect(restoredAttempt).toMatchObject({
      state: "created",
      order_id: "9001",
      client_secret: null,
    });

    await setClock(new Date(Date.parse(at) + 60_000).toISOString());
    const amountMinor = await syncPaymobForCheckout(checkoutId);
    const lateSuccess = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      { txnId: 96777, amountMinor },
    );
    expect(lateSuccess.status).toBe(200);
    await runScheduled("* * * * *");
    const lateStatus = await env.DB.prepare(
      `SELECT state FROM checkout_status WHERE checkout_id = ?`,
    ).bind(checkoutId).first<{ state: string }>();
    expect(lateStatus?.state).toBe("paid_late");
    const latePayment = await env.DB.prepare(
      `SELECT payment_id, classification, disposition FROM payment WHERE checkout_id = ?`,
    ).bind(checkoutId).first<{
      payment_id: string;
      classification: string;
      disposition: string;
    }>();
    expect(latePayment).toMatchObject({
      classification: "late",
      disposition: "grant",
    });
    const paidGrantId = await grantIdPaid(latePayment!.payment_id);
    expect(await rowExists("grant_request", "grant_id", paidGrantId)).toBe(true);
    const lateGrantWork = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant' AND subject_id = ?`,
    ).bind(latePayment!.payment_id).first<{ n: number }>();
    expect(lateGrantWork?.n).toBe(1);
    const lateAlert = await env.DB.prepare(
      `SELECT active FROM alert WHERE code = 'AL-08' AND detail_id = ?`,
    ).bind(checkoutId).first<{ active: number }>();
    expect(lateAlert?.active).toBe(1);
    await runScheduled("* * * * *");
    expect(await tableCount("grant_request")).toBe(1);
    expect(await paymentIdForCheckout(checkoutId)).toBe(latePayment!.payment_id);
  });

  it("R9-REC1 reapplies accepted erasure fences before deleting any recovered callback body", async () => {
    const expectations = await setupRebuildHarness();
    await putBillingContact(ORG_REBUILD);
    const { checkoutId } = await postCheckout(
      ORG_REBUILD,
      expectations,
      "req-r9-rec1-erased-callback-body",
    );
    const amountMinor = await syncPaymobForCheckout(checkoutId);
    const callback = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      { txnId: PAID_PAYMOB_TXN_ID, amountMinor },
    );
    expect(callback.status).toBe(200);
    const notification = await env.DB.prepare(
      `SELECT body_r2_key FROM notification WHERE checkout_id = ? LIMIT 1`,
    ).bind(checkoutId).first<{ body_r2_key: string }>();
    expect(notification?.body_r2_key).toBeTruthy();
    const retainedBodyKey = notification!.body_r2_key;
    expect(await env.R2.head(retainedBodyKey)).not.toBeNull();

    const commandId = "cmd-r9-rec1-erase-callback-body";
    const now = await currentHarnessClockIso();
    const cutoff = new Date(Date.parse(now) + 60_000).toISOString();
    await env.DB.batch(await commandFactStatements(env, {
      commandId,
      kind: "command_intent",
      payload: {
        payload_version: 1,
        command_id: commandId,
        method: "erase_contact",
        subject_id: ORG_REBUILD,
        actor_email: VENDOR_OPERATOR_EMAIL,
        erasure_generation: 7,
        scope_contact_versions: [1],
        acceptance_cutoff: cutoff,
      },
      createdAt: now,
    }));
    await exportLedgerFacts();

    await wipeAboD1();
    await reapplyAboSchema();
    expect(await env.R2.head(retainedBodyKey)).not.toBeNull();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    await rebuildAbo(env as never, { providerTransactionReferences: [] });

    expect(await env.R2.get(retainedBodyKey)).toBeNull();
    expect(await tableCount("billing_contact")).toBe(0);
    const fence = await env.DB.prepare(
      `SELECT generation FROM org_erasure_fence WHERE org_id = ?`,
    ).bind(ORG_REBUILD).first<{ generation: number }>();
    expect(fence?.generation).toBe(7);
  });

  it("R9-REC2 disputes transfer recovery without original signed authorization bytes", async () => {
    await setupRebuildHarness();
    const commandId = "cmd-r9-transfer-recovery";
    const transferId = "tr-r9-transfer-recovery";
    const orgId = ORG_REBUILD;
    const fromInstallationId = "install-r9-source";
    const toInstallationId = "install-r9-target";
    const now = await currentHarnessClockIso();
    const reserved = {
      payload_version: 1,
      command_id: commandId,
      method: "beginTransfer",
      command_kind: "relay",
      subject_id: orgId,
      actor_email: VENDOR_OPERATOR_EMAIL,
      contract_version: CONTRACT_VERSION,
      safe_args: {
        org_id: orgId,
        from_installation_id: fromInstallationId,
        reason_sha256: "a".repeat(64),
      },
      args_sha256: "b".repeat(64),
      operation_sha256: "c".repeat(64),
      assertion_sha256: "d".repeat(64),
      signer_credential_id: "credential-r9-transfer",
      signer_public_key_cose: "trusted-test-public-material",
      signer_alg: "ES256",
      accepted_at: now,
      authority_action_id: commandId,
      authority_access_jti: "jti-r9-transfer",
      reservation_state: "abo_relay_reserved",
    };
    const mapping = {
      transfer_id: transferId,
      org_id: orgId,
      from_installation_id: fromInstallationId,
      to_installation_id: toInstallationId,
      assertion_sha256: reserved.operation_sha256,
      package: null,
      created_at: now,
    };
    const beginResponse = {
      result: "ok",
      code: "",
      contract_version: CONTRACT_VERSION,
      detail: JSON.stringify(mapping),
    };
    const platformResult = {
      payload_version: 1,
      command_id: commandId,
      method: "beginTransfer",
      phase: "beginTransfer",
      subject_id: orgId,
      result: "ok",
      code: "",
      contract_version: CONTRACT_VERSION,
      response_json: new TextDecoder().decode(canonicalize(beginResponse)),
      response_sha256: await sha256Hex(canonicalize(beginResponse)),
      transfer_id: transferId,
      transfer_mapping: mapping,
      provenance: "authenticated_platform_beginTransfer_call",
      at: now,
    };
    await env.DB.batch([
      ...await commandFactStatements(env, {
        commandId,
        kind: "relay_reserved",
        payload: reserved,
        createdAt: now,
      }),
      ...await commandFactStatements(env, {
        commandId,
        kind: "platform_result",
        payload: platformResult,
        createdAt: now,
      }),
    ]);

    const terminalSigner = await createPlatformReceiptSigner();
    const terminalPublicKey = new Uint8Array(
      await crypto.subtle.exportKey("raw", terminalSigner.publicKey),
    );
    const terminalPublicKeys = JSON.stringify([{
      kid: terminalSigner.kid,
      public_key: base64UrlEncode(terminalPublicKey),
    }]);
    const terminalCommandId = "cmd-r9-transfer-terminal";
    const terminalTransferId = "tr-r9-transfer-terminal";
    const terminalOperationHash = "1".repeat(64);
    const terminalFromInstallationId = "install-r9-terminal-source";
    const terminalToInstallationId = "install-r9-terminal-target";
    const terminalReservation = {
      ...reserved,
      command_id: terminalCommandId,
      authority_action_id: terminalCommandId,
      operation_sha256: terminalOperationHash,
      assertion_sha256: "2".repeat(64),
      safe_args: {
        ...reserved.safe_args,
        from_installation_id: terminalFromInstallationId,
      },
      signer_credential_id: "credential-r9-terminal",
    };
    const terminalMapping = {
      ...mapping,
      transfer_id: terminalTransferId,
      from_installation_id: terminalFromInstallationId,
      to_installation_id: terminalToInstallationId,
      assertion_sha256: terminalOperationHash,
    };
    const terminalBeginResponse = {
      result: "ok",
      code: "",
      contract_version: CONTRACT_VERSION,
      detail: JSON.stringify(terminalMapping),
    };
    const terminalBegin = {
      ...platformResult,
      command_id: terminalCommandId,
      operation_sha256: terminalOperationHash,
      transfer_id: terminalTransferId,
      transfer_mapping: terminalMapping,
      response_json: new TextDecoder().decode(canonicalize(terminalBeginResponse)),
      response_sha256: await sha256Hex(canonicalize(terminalBeginResponse)),
    };
    const signedTransferReceipt = {
      contract_version: CONTRACT_VERSION,
      transfer_id: terminalTransferId,
      installation_id: terminalToInstallationId,
      org_id: orgId,
      result: "applied",
      term_ids: ["term-r9-terminal"],
      applied_at: now,
      ledger_seq: 8,
      envelope_sha256: "3".repeat(64),
      kid: terminalSigner.kid,
    };
    const terminalReceipt = {
      ...signedTransferReceipt,
      signature: await terminalSigner.sign(signedTransferReceipt),
    };
    const terminalResponse = {
      result: "applied",
      code: "",
      contract_version: CONTRACT_VERSION,
      receipt: terminalReceipt,
    };
    await env.DB.batch([
      ...await commandFactStatements({ ...env, PLATFORM_PUBLIC_KEYS: terminalPublicKeys }, {
        commandId: terminalCommandId,
        kind: "relay_reserved",
        payload: terminalReservation,
        createdAt: now,
      }),
      ...await commandFactStatements({ ...env, PLATFORM_PUBLIC_KEYS: terminalPublicKeys }, {
        commandId: terminalCommandId,
        kind: "platform_result",
        payload: terminalBegin,
        createdAt: now,
      }),
      ...await commandFactStatements({ ...env, PLATFORM_PUBLIC_KEYS: terminalPublicKeys }, {
        commandId: terminalCommandId,
        kind: "platform_result",
        payload: {
          payload_version: 1,
          command_id: terminalCommandId,
          method: "beginTransfer",
          phase: "transferIn",
          subject_id: terminalTransferId,
          transfer_id: terminalTransferId,
          result: "applied",
          code: "",
          contract_version: CONTRACT_VERSION,
          response_json: new TextDecoder().decode(canonicalize(terminalResponse)),
          response_sha256: await sha256Hex(canonicalize(terminalResponse)),
          provenance: "authenticated_platform_transfer_step_call",
          at: now,
        },
        createdAt: now,
      }),
    ]);
    await exportLedgerFacts(terminalPublicKeys);

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    const recoveryEnv = { ...env, PLATFORM_PUBLIC_KEYS: terminalPublicKeys };
    await rebuildAbo(recoveryEnv as never, { providerTransactionReferences: [] });

    const command = await env.DB.prepare(
      `SELECT method, operation_json, stage FROM accepted_operator_command WHERE command_id = ?`,
    ).bind(commandId).first<{ method: string; operation_json: string; stage: string }>();
    expect(command).toMatchObject({
      method: "beginTransfer",
      operation_json: "",
      stage: "awaiting_operator_auth",
    });
    const terminalCommand = await env.DB.prepare(
      `SELECT stage FROM accepted_operator_command WHERE command_id = ?`,
    ).bind(terminalCommandId).first<{ stage: string }>();
    expect(terminalCommand?.stage).toBe("complete");
    const recoveredWork = await env.DB.prepare(
      `SELECT work_id, subject_id, dedupe_key, state, last_error
       FROM work WHERE kind = 'accepted_command' AND subject_id = ?`,
    ).bind(commandId).all<{
      work_id: string;
      subject_id: string;
      dedupe_key: string;
      state: string;
      last_error: string;
    }>();
    expect(recoveredWork.results).toHaveLength(1);
    expect(recoveredWork.results?.[0]).toMatchObject({
      subject_id: commandId,
      dedupe_key: `accepted_command:${commandId}`,
      state: "awaiting_operator_auth",
      last_error: "blocked_missing_original_authorization",
    });
    const noRunnableTransferWork = await env.DB.prepare(
      `SELECT COUNT(*) AS count FROM work WHERE kind = 'transfer_step' AND subject_id = ?`,
    ).bind(transferId).first<{ count: number }>();
    expect(noRunnableTransferWork?.count).toBe(0);
    const disputed = await env.DB.prepare(
      `SELECT detail FROM finding WHERE kind = 'accepted_transfer_disputed' AND subject = ?`,
    ).bind(commandId).first<{ detail: string }>();
    expect(disputed?.detail).toContain("blocked_missing_original_authorization");
    expect(disputed?.detail).toContain(transferId);
    const blockedFact = await env.DB.prepare(
      `SELECT payload_json FROM command_recovery_fact
       WHERE command_id = ? AND fact_kind = 'local_result'
         AND json_extract(payload_json, '$.result') = 'blocked_missing_original_authorization'`,
    ).bind(commandId).first<{ payload_json: string }>();
    expect(JSON.parse(blockedFact!.payload_json)).toMatchObject({
      command_id: commandId,
      method: "beginTransfer",
      transfer_id: transferId,
      result: "blocked_missing_original_authorization",
    });
    await rebuildAbo(recoveryEnv as never, { providerTransactionReferences: [] });
    const afterSecondRebuild = await env.DB.prepare(
      `SELECT COUNT(*) AS count FROM work WHERE kind = 'accepted_command' AND dedupe_key = ?`,
    ).bind(`accepted_command:${commandId}`).first<{ count: number }>();
    expect(afterSecondRebuild?.count).toBe(1);
  });

  it("R9-REC1 tampered ledger hash stops before any replay mutation", async () => {
    const expectations = await setupRebuildHarness();
    await paidCheckoutWithGrant(
      ORG_REBUILD,
      expectations,
      PAID_PAYMOB_TXN_ID,
      "req-r9-rec1-tamper",
    );
    await exportLedgerFacts();
    const listed = await env.R2.list({ prefix: "ledger/" });
    expect(listed.objects.length).toBeGreaterThan(0);
    const firstKey = listed.objects[0]!.key;
    const stored = await env.R2.get(firstKey);
    expect(stored).not.toBeNull();
    const line = JSON.parse(await stored!.text()) as Record<string, unknown>;
    expect(line.payload_version).toBe(2);
    expect(line.fact_created_at).toBeTruthy();
    line.row_sha256 = "a".repeat(64);
    await env.R2.put(firstKey, JSON.stringify(line));

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    await expect(rebuildAbo(env as never, { providerTransactionReferences: [] }))
      .rejects.toThrow(/ledger_hash_mismatch/u);
    const rows = await env.DB.prepare(`SELECT COUNT(*) AS count FROM fact_log`)
      .first<{ count: number }>();
    expect(rows?.count).toBe(0);
  });

  it("R9-REC1 interrupted ledger replay resumes with original fact sequences", async () => {
    const expectations = await setupRebuildHarness({ freshPlatformState: true });
    await ensureGrantTenantBinding(ORG_REBUILD, RESUME_INSTALLATION_ID);
    const { paymentId } = await paidCheckoutWithGrant(
      ORG_REBUILD,
      expectations,
      RESUME_PAYMOB_TXN_ID,
      "req-r9-rec1-resume",
    );
    const grantOutcome = await env.DB.prepare(
      `SELECT result FROM grant_outcome WHERE grant_id = ?`,
    ).bind(await grantIdPaid(paymentId)).first<{ result: string }>();
    expect(grantOutcome?.result).toMatch(/^(applied|already_applied)$/u);
    await exportLedgerFacts();
    const listed = await env.R2.list({ prefix: "ledger/" });
    const originalLines = await Promise.all(listed.objects.map(async (object) => {
      const body = await env.R2.get(object.key);
      return JSON.parse(await body!.text()) as {
        fact_seq: number;
        table: string;
        key: string;
        row_sha256: string;
      };
    }));
    const originalObjects = new Map(await Promise.all(listed.objects.map(async (object) => {
      const body = await env.R2.get(object.key);
      return [object.key, await body!.text()] as const;
    })));

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    setD1BatchThrows(true, 3);
    try {
      await expect(rebuildAbo(env as never, { providerTransactionReferences: [] }))
        .rejects.toThrow(/D1 batch failure injected/u);
    } finally {
      setD1BatchThrows(false);
    }
    const interrupted = await env.DB.prepare(
      `SELECT last_fact_seq FROM rebuild_checkpoint WHERE id = 1`,
    ).first<{ last_fact_seq: number }>();
    expect(interrupted?.last_fact_seq).toBe(3);
    await expect(exportFacts(env)).rejects.toThrow(/abo_recovery_in_progress/u);
    expect((await billingFetch("/v1/offers")).status).toBe(503);
    const scheduledBeforeFence = await env.DB.prepare(
      `SELECT last_started_at, last_succeeded_at FROM scheduled_job_state
       WHERE job = 'minute_processing'`,
    ).first<{ last_started_at: string; last_succeeded_at: string }>();
    await runScheduled("* * * * *");
    const scheduledAfterFence = await env.DB.prepare(
      `SELECT last_started_at, last_succeeded_at FROM scheduled_job_state
       WHERE job = 'minute_processing'`,
    ).first<{ last_started_at: string; last_succeeded_at: string }>();
    expect(scheduledAfterFence).toEqual(scheduledBeforeFence);

    await setClock(new Date(Date.parse(BASE_CLOCK) + 6 * 60_000).toISOString());
    await rebuildAbo(env as never, { providerTransactionReferences: [] });
    const replayed = await env.DB.prepare(
      `SELECT fact_seq, "table", key, row_sha256 FROM fact_log ORDER BY fact_seq`,
    ).all<{
      fact_seq: number;
      table: string;
      key: string;
      row_sha256: string;
    }>();
    const originalFacts = originalLines
      .map(({ fact_seq, table, key, row_sha256 }) => ({ fact_seq, table, key, row_sha256 }))
      .sort((a, b) => a.fact_seq - b.fact_seq);
    expect(replayed.results.slice(0, originalFacts.length)).toEqual(originalFacts);
    expect(replayed.results.slice(originalFacts.length)).toEqual([
      expect.objectContaining({
        fact_seq: originalFacts.length + 1,
        table: "rebuild_inquiry_attempt",
      }),
    ]);

    await appendOffer(env, {
      offer_id: "offer-r9-rec1-after-rebuild",
      code: "RM28-NEXT",
      contract_version: CONTRACT_VERSION,
    });
    const maxSeq = await env.DB.prepare(`SELECT MAX(fact_seq) AS n FROM fact_log`)
      .first<{ n: number }>();
    expect(maxSeq?.n).toBe(originalLines.length + 2);
    expect(maxSeq?.n).toBe(22);
    await exportFacts(env);
    for (const [key, expectedBody] of originalObjects) {
      const retained = await env.R2.get(key);
      expect(await retained?.text()).toBe(expectedBody);
    }
    const inquiryObject = await env.R2.get(`ledger/${originalLines.length + 1}.ndjson`);
    expect(inquiryObject).not.toBeNull();
    expect(JSON.parse(await inquiryObject!.text())).toMatchObject({
      fact_seq: originalLines.length + 1,
      table: "rebuild_inquiry_attempt",
    });
    const nextObject = await env.R2.get(`ledger/${originalLines.length + 2}.ndjson`);
    expect(nextObject).not.toBeNull();
    expect(JSON.parse(await nextObject!.text())).toMatchObject({
      fact_seq: originalLines.length + 2,
      table: "offer",
      key: "offer-r9-rec1-after-rebuild",
    });
  });

  it("R9-REC1 manifest high-water rejects a missing ledger prefix even when no ledger object is listed", async () => {
    const expectations = await setupRebuildHarness();
    await paidCheckoutWithGrant(
      ORG_REBUILD,
      expectations,
      PAID_PAYMOB_TXN_ID,
      "req-r9-rec1-missing-ledger-prefix",
    );
    await exportLedgerFacts();
    const listed = await env.R2.list({ prefix: "ledger/" });
    expect(listed.objects.length).toBeGreaterThan(0);
    for (const object of listed.objects) await env.R2.delete(object.key);

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    await expect(rebuildAbo(env as never, { providerTransactionReferences: [] }))
      .rejects.toThrow(/ledger_manifest_prefix_incomplete/u);
    const rows = await env.DB.prepare(`SELECT COUNT(*) AS count FROM fact_log`)
      .first<{ count: number }>();
    expect(rows?.count).toBe(0);
  });

  it("R9-REC1 a missing sequence in the middle of the ledger stops before replay", async () => {
    const expectations = await setupRebuildHarness();
    await paidCheckoutWithGrant(
      ORG_REBUILD,
      expectations,
      PAID_PAYMOB_TXN_ID,
      "req-r9-rec1-missing-sequence",
    );
    await exportLedgerFacts();
    const listed = await env.R2.list({ prefix: "ledger/" });
    expect(listed.objects.length).toBeGreaterThan(2);
    await env.R2.delete("ledger/2.ndjson");

    await wipeAboD1();
    await reapplyAboSchema();
    const { rebuildAbo } = await import("../../src/rebuild.js");
    await expect(rebuildAbo(env as never, { providerTransactionReferences: [] }))
      .rejects.toThrow(/ledger_manifest_prefix_incomplete/u);
    const checkpoint = await env.DB.prepare(
      `SELECT last_fact_seq FROM rebuild_checkpoint WHERE id = 1`,
    ).first();
    const facts = await env.DB.prepare(`SELECT COUNT(*) AS n FROM fact_log`)
      .first<{ n: number }>();
    expect(checkpoint).toBeNull();
    expect(facts?.n).toBe(0);
  });

  it("R9-REC1 conflicting D1 business rows stop replay without overwriting the row", async () => {
    const expectations = await setupRebuildHarness();
    await paidCheckoutWithGrant(
      ORG_REBUILD,
      expectations,
      PAID_PAYMOB_TXN_ID,
      "req-r9-rec1-d1-conflict",
    );
    await exportLedgerFacts();
    const first = await env.R2.get("ledger/1.ndjson");
    expect(first).not.toBeNull();
    const line = JSON.parse(await first!.text()) as {
      fact_seq: number;
      table: string;
      row: Record<string, unknown>;
    };

    await wipeAboD1();
    await reapplyAboSchema();
    const altered = { ...line.row };
    const tableColumns = await env.DB.prepare(`PRAGMA table_info(${line.table})`)
      .all<{ name: string; pk: number }>();
    const field = tableColumns.results?.find((column) =>
      column.pk === 0 && typeof altered[column.name] === "string",
    )?.name;
    expect(field).toBeTruthy();
    altered[field!] = `${String(altered[field])}-conflict`;
    const columns = Object.keys(altered);
    await env.DB.prepare(
      `INSERT INTO ${line.table} (${columns.join(", ")}) VALUES (${columns.map(() => "?").join(", ")})`,
    ).bind(...columns.map((column) => altered[column])).run();

    const { rebuildAbo } = await import("../../src/rebuild.js");
    await expect(rebuildAbo(env as never, { providerTransactionReferences: [] }))
      .rejects.toThrow(/ledger_business_row_conflict/u);
    const retained = await env.DB.prepare(
      `SELECT * FROM ${line.table} LIMIT 1`,
    ).first<Record<string, unknown>>();
    expect(retained).not.toBeNull();
    expect(retained).toEqual(expect.objectContaining(altered));
  });

  it("R9-REC1 conflicting immutable ledger objects are rejected without overwrite", async () => {
    const expectations = await setupRebuildHarness();
    await paidCheckoutWithGrant(
      ORG_REBUILD,
      expectations,
      PAID_PAYMOB_TXN_ID,
      "req-r9-rec1-immutable-export",
    );
    await exportLedgerFacts();
    const listed = await env.R2.list({ prefix: "ledger/" });
    const key = listed.objects[0]!.key;
    const body = await env.R2.get(key);
    expect(body).not.toBeNull();
    const conflict = `${await body!.text()}\n`;
    await env.R2.put(key, conflict);

    await expect(exportFacts(env)).rejects.toThrow(/ledger_object_conflict/u);
    const retained = await env.R2.get(key);
    expect(await retained?.text()).toBe(conflict);
  });

  it("rejects JWT and signed authorization fields nested in serialized recovery payloads", async () => {
    const jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJvcGVyYXRvciJ9.signature";
    await expect(commandFactStatements(env, {
      commandId: "cmd-r9-secret-nested",
      kind: "relay_reserved",
      payload: {
        payload_version: 1,
        command_id: "cmd-r9-secret-nested",
        response_json: JSON.stringify({ nested: { access_jwt: jwt } }),
      },
      createdAt: "2026-06-01T12:00:00.000Z",
    })).rejects.toThrow(/command_recovery_fact_invalid/u);
    await expect(commandFactStatements(env, {
      commandId: "cmd-r9-signed-nested",
      kind: "relay_reserved",
      payload: {
        payload_version: 1,
        command_id: "cmd-r9-signed-nested",
        signed_operation_json: "{}",
      },
      createdAt: "2026-06-01T12:00:00.000Z",
    })).rejects.toThrow(/command_recovery_fact_invalid/u);
  });

  it("permits only a structurally bound transfer receipt signature in its declared response field", async () => {
    const signer = await createPlatformReceiptSigner();
    const receiptUnsigned = {
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      transfer_id: "tr-recovery-receipt",
      installation_id: "install-recovery-target",
      org_id: "a4110002-0002-4011-8011-000000000002",
      result: "applied",
      term_ids: ["term-recovery-1"],
      applied_at: "2026-10-20T12:00:00.000Z",
      ledger_seq: 4,
      envelope_sha256: "a".repeat(64),
    };
    const receipt = {
      ...receiptUnsigned,
      kid: signer.kid,
      signature: await signer.sign(receiptUnsigned),
    };
    const response = {
      result: "applied",
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      receipt,
    };
    const fact = {
      fact_kind: "platform_result",
      phase: "transferIn",
      provenance: "authenticated_platform_transfer_step_call",
      result: "applied",
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      transfer_id: "tr-recovery-receipt",
      response_json: JSON.stringify(response),
    };
    const rawPublicKey = new Uint8Array(await crypto.subtle.exportKey("raw", signer.publicKey));
    const platformPublicKeys = JSON.stringify([{
      kid: signer.kid,
      public_key: base64UrlEncode(rawPublicKey),
    }]);
    expect(await hasForbiddenCommandFactSecret(fact, undefined, platformPublicKeys)).toBe(false);
    expect(await hasForbiddenCommandFactSecret({
      ...fact,
      response_json: JSON.stringify({ signature: receipt.signature }),
    }, undefined, platformPublicKeys)).toBe(true);
    expect(await hasForbiddenCommandFactSecret({
      ...fact,
      transfer_id: "tr-other",
    }, undefined, platformPublicKeys)).toBe(true);
  });
});
