/**
 * P4.11 — daily digest, platform watch, housekeeping, and ABO rebuild (H-XW),
 * E2E-P4.11-01 through E2E-P4.11-07.
 */

import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  CHANNEL_VERSIONS,
  grantIdComp,
  grantIdPaid,
  grantIdTransfer,
  sha256Hex,
} from "vendor-contracts";
import {
  createSoftwareAuthenticator,
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
import reconciliationMigrationSql from "../../migrations/0008_reconciliation.sql?raw";
import { loadOffersFixture } from "../../src/records/append";
import { exportFacts } from "../../src/records/export";
import {
  applySql,
  billingFetch,
  clearCapturedEmails,
  clearCapturedHeartbeatFetches,
  getCapturedEmails,
  getCapturedHeartbeatFetches,
  harnessState,
  mintBilling,
  newIssuer,
  pinIssuer,
  runScheduled,
  scriptPaymobInquiry,
  sendEmailBinding,
  setSendEmailThrows,
} from "./harness";
import {
  drainPlatformDurableObjects,
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
const EXTRA_ISSUER_KID = "watch-extra-issuer-kid";
const EXTRA_CREDENTIAL_ID = "watch-extra-credential-id";
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

const testDir = path.dirname(fileURLToPath(import.meta.url));
const aboRoot = path.resolve(testDir, "../..");

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
): PaymobCallbackFixture {
  const base =
    txnId !== undefined
      ? successFixtureWithTxnId(txnId)
      : (successFixture as PaymobCallbackFixture);
  return {
    type: base.type,
    obj: { ...base.obj, amount_cents: String(amountMinor) },
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
  try {
    const fixture = offersFixture as {
      expectations?: OffersFixtureExpectations;
    };
    await loadOffersFixture(fixture);
    return fixture.expectations ?? null;
  } catch {
    return null;
  }
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

async function setupRebuildHarness(): Promise<OffersFixtureExpectations> {
  const expectations = await seedOffersCatalogueFixture();
  expect(expectations).not.toBeNull();
  await registerAboGrantKeyOnPlatform();
  await publishPlanProOnPlatform();
  await registerClinicIssuerKey();
  await setupPromotedRoutingPolicy();
  return expectations!;
}

async function ensureGrantTenantBinding(orgId: string): Promise<void> {
  const existing = await env.PLATFORM_DB.prepare(
    `SELECT installation_id FROM tenant_binding
     WHERE org_id = ? AND status = 'active'`,
  )
    .bind(orgId)
    .first<{ installation_id: string }>();
  if (existing?.installation_id) {
    return;
  }
  const installationId = crypto.randomUUID();
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
  const now = await harnessNowSeconds();
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
  },
): Promise<Response> {
  const bodyFixture =
    options?.amountMinor !== undefined
      ? successFixtureWithAmount(options.amountMinor, options.txnId)
      : options?.txnId !== undefined
        ? successFixtureWithTxnId(options.txnId)
        : fixture;
  const body = JSON.stringify({
    type: bodyFixture.type,
    obj: bodyFixture.obj,
  });
  const hmac = await signPaymobObj(env.PAYMOB_HMAC_SECRET, bodyFixture.obj);
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

async function exportLedgerFacts(): Promise<void> {
  await runScheduled("* * * * *");
  await exportFacts(env);
}

async function wipeAboD1(): Promise<void> {
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
}

async function openFindingCount(): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n
       FROM finding f
       LEFT JOIN finding_resolution fr ON f.finding_id = fr.finding_id
       WHERE fr.finding_id IS NULL`,
    ).first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function readRebuildRunbook(): Promise<string> {
  try {
    return await readFile(path.join(aboRoot, "REBUILD.md"), "utf8");
  } catch {
    return "";
  }
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
    clinicIssuer = null;
    await resetCrossWorkerHarness();
    await setupCrossWorkerHarness();
    await ensureMigrations();
    await ensureDigestWatchMigration();
    await scriptPaymobStub("ok");
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

  it("E2E-P4.11-06 FM-19: wipe the ABO D1 → replay ledger/ → facts and status restored; gap re-inquired; a payment with no grant gets one → already_applied; reconciliation clean", async () => {
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

    await wipeAboD1();
    await reapplyAboSchema();

    const { rebuildAbo } = await import("../../src/rebuild.js");
    await scriptPaymobInquiry("bound_success");
    await rebuildAbo(env as never, {
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

    const gapPaymentId = await paymentIdForCheckout(gapCheckoutId);
    expect(gapPaymentId).not.toBeNull();
    const gapGrantId = await grantIdPaid(gapPaymentId!);
    const grantOutcome = await env.DB.prepare(
      `SELECT result FROM grant_outcome WHERE grant_id = ?`,
    )
      .bind(gapGrantId)
      .first<{ result: string }>();
    expect(grantOutcome?.result).toBe("already_applied");
    expect(paidPaymentBefore?.payment_id).toBe(paid.paymentId);
    expect(await openFindingCount()).toBe(0);

    const runbook = await readRebuildRunbook();
    expect(runbook).toContain("provider transaction references");
    expect(runbook.toLowerCase()).toContain("dashboard export");
  });
});
