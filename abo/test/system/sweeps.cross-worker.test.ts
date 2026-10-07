/**
 * P4.5 — checkout sweeps E2E tests (H-XW + H-PAY), E2E-P4.5-01 through E2E-P4.5-12.
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { CHANNEL_VERSIONS, grantIdPaid } from "vendor-contracts";
import offersFixture from "../../fixtures/offers.json";
import badHmacFixture from "../fixtures/paymob/bad-hmac.json";
import refundChildFixture from "../fixtures/paymob/refund-child.json";
import refundParentFixture from "../fixtures/paymob/refund-parent.json";
import successFixture from "../fixtures/paymob/success.json";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import notifyWorkMigrationSql from "../../migrations/0003_notify_work.sql?raw";
import grantMigrationSql from "../../migrations/0004_grant.sql?raw";
import { loadOffersFixture } from "../../src/records/append";
import {
  applySql,
  billingFetch,
  mintBilling,
  newIssuer,
  pinIssuer,
  runScheduled,
  scriptPaymobInquiry,
  setIntakeR2PutThrows,
  tableCount,
} from "./harness";
import {
  platformCall,
  resetCrossWorkerHarness,
  scriptPaymobStub,
  setClock,
  setupCrossWorkerHarness,
} from "./cross-worker-harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const PLAN_ID = "plan-pro";
const PLAN_VERSION = 1;
const CAPABILITY_ID = "clinic.visit_summary";
const POLICY_ID = "standard";
const POLICY_VERSION = "1";
const ALLOWANCE_CREDITS = 100;
const VENDOR_OPERATOR_EMAIL = "operator@vendor.test";

const ORG_SWEEP_01 = "a4550001-0000-4001-8001-000000000001";
const ORG_SWEEP_02 = "a4550002-0000-4002-8002-000000000002";
const ORG_SWEEP_03 = "a4550003-0000-4003-8003-000000000003";
const ORG_SWEEP_04 = "a4550004-0000-4004-8004-000000000004";
const ORG_SWEEP_05 = "a4550005-0000-4005-8005-000000000005";
const ORG_SWEEP_06 = "a4550006-0000-4006-8006-000000000006";
const ORG_SWEEP_07 = "a4550007-0000-4007-8007-000000000007";
const ORG_SWEEP_08 = "a4550008-0000-4008-8008-000000000008";
const ORG_SWEEP_11 = "a4550011-0000-4011-8011-000000000011";
const ORG_SWEEP_12 = "a4550012-0000-4012-8012-000000000012";

type AboGrantKey = {
  kid: string;
  pkcs8: string;
  public_key: string;
};

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

declare module "cloudflare:test" {
  interface ProvidedEnv {
    PLATFORM_DB: D1Database;
    ABO_GRANT_KEY: string;
  }
}

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

function parseAboGrantKey(): AboGrantKey {
  return JSON.parse(env.ABO_GRANT_KEY) as AboGrantKey;
}

function addMinutes(isoUtc: string, minutes: number): string {
  return new Date(Date.parse(isoUtc) + minutes * 60_000).toISOString();
}

function addDays(isoUtc: string, days: number): string {
  return new Date(Date.parse(isoUtc) + days * 24 * 60 * 60_000).toISOString();
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

async function ensureMigrations(): Promise<void> {
  for (const sql of [
    checkoutMigrationSql,
    notifyWorkMigrationSql,
    grantMigrationSql,
  ]) {
    try {
      await applySql(sql);
    } catch {
      // Migration not present yet.
    }
  }
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
    .bind(
      aboKey.kid,
      aboKey.public_key,
      notBefore,
      notAfter,
      VENDOR_OPERATOR_EMAIL,
    )
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

async function administratorHeaders(
  org: string,
): Promise<Record<string, string>> {
  const issuer = await newIssuer();
  await pinIssuer(issuer.kid, issuer.publicKey);
  const now = Math.floor(Date.now() / 1000);
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
  const headers = await administratorHeaders(org);
  const response = await billingFetch("/v1/billing-contact", {
    method: "PUT",
    headers,
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
  const headers = await administratorHeaders(org);
  const response = await billingFetch("/v1/checkouts", {
    method: "POST",
    headers,
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
    connectingIp?: string;
    amountMinor?: number;
    hmac?: string;
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
  const hmac =
    options?.hmac ??
    (await signPaymobObj(env.PAYMOB_HMAC_SECRET, bodyFixture.obj));
  return billingFetch(`/notify/paymob?hmac=${encodeURIComponent(hmac)}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": options?.connectingIp ?? "203.0.113.10",
    },
    body,
  });
}

async function postBadHmacFixture(connectingIp?: string): Promise<Response> {
  const fixture = badHmacFixture as PaymobCallbackFixture & {
    _fixture_hmac?: string;
  };
  const hmac =
    fixture._fixture_hmac ??
    "0000000000000000000000000000000000000000000000000000000000000000";
  return postPaymobProcessedCallback(fixture, {
    hmac,
    connectingIp,
  });
}

async function runGrantStep(): Promise<void> {
  const { runDueGrantWork } = await import("../../src/work/grant");
  await runScheduled("* * * * *");
  await runDueGrantWork(env as never);
}

async function openedEventAt(checkoutId: string): Promise<string> {
  const row = await env.DB.prepare(
    `SELECT at FROM checkout_event WHERE checkout_id = ? AND kind = 'opened'`,
  )
    .bind(checkoutId)
    .first<{ at: string }>();
  expect(row).not.toBeNull();
  return row!.at;
}

async function checkoutExpiresAt(checkoutId: string): Promise<string> {
  const row = await env.DB.prepare(
    `SELECT expires_at FROM checkout WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ expires_at: string }>();
  expect(row).not.toBeNull();
  return row!.expires_at;
}

async function checkoutStatusState(checkoutId: string): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT state FROM checkout_status WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ state: string }>();
    return row?.state ?? null;
  } catch {
    return null;
  }
}

async function paymentCountForCheckout(checkoutId: string): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function paymentClassification(
  checkoutId: string,
): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT classification FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ classification: string }>();
    return row?.classification ?? null;
  } catch {
    return null;
  }
}

async function grantOutcomeCount(): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM grant_outcome`,
    ).first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function alertCountByCode(code: string): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM alert WHERE code = ? AND active = 1`,
    )
      .bind(code)
      .first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function sweepCheckoutWorkCount(checkoutId: string): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n
       FROM work
       WHERE kind = 'sweep_checkout' AND subject_id = ?`,
    )
      .bind(checkoutId)
      .first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function doneSweepCheckoutWorkCount(checkoutId: string): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n
       FROM work
       WHERE kind = 'sweep_checkout' AND subject_id = ? AND state = 'done'`,
    )
      .bind(checkoutId)
      .first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function confirmWorkState(checkoutId: string): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT state FROM work
       WHERE kind = 'confirm'
         AND (subject_id = ? OR dedupe_key = ?)
       ORDER BY opened_at
       LIMIT 1`,
    )
      .bind(checkoutId, `confirm-schedule:${checkoutId}`)
      .first<{ state: string }>();
    return row?.state ?? null;
  } catch {
    return null;
  }
}

async function getCheckoutShownState(
  org: string,
  checkoutId: string,
): Promise<string | null> {
  const headers = await administratorHeaders(org);
  const response = await billingFetch(`/v1/checkouts/${checkoutId}`, {
    headers,
  });
  if (response.status !== 200) {
    return null;
  }
  const body = (await response.json()) as { shown_state?: string };
  return body.shown_state ?? null;
}

async function platformCoverageSnapshot(
  orgId: string,
): Promise<Record<string, unknown> | null> {
  const coverage = await platformCall("getCoverage", {
    contract_version: CONTRACT_VERSION,
    org_id: orgId,
  });
  if (coverage.result !== "ok") {
    return null;
  }
  const parsed = JSON.parse(String(coverage.detail)) as {
    snapshot?: Record<string, unknown>;
  };
  return parsed.snapshot ?? null;
}

async function createOpenCheckoutWithoutCallback(
  org: string,
  expectations: OffersFixtureExpectations,
  clientRequestId: string,
): Promise<{ checkoutId: string; reference: string }> {
  await putBillingContact(org);
  await ensureGrantTenantBinding(org);
  const checkout = await postCheckout(org, expectations, clientRequestId);
  await syncPaymobForCheckout(checkout.checkoutId);
  return checkout;
}

async function seedTermOfferVersions(
  expectations: OffersFixtureExpectations,
): Promise<Record<number, { offerId: string; version: number }>> {
  const versions: Record<number, { offerId: string; version: number }> = {
    1: { offerId: expectations.offer_id, version: expectations.version },
  };
  for (const termCount of [3, 12] as const) {
    const suffix = termCount === 3 ? "003" : "012";
    const offerId = `01JHARNESSOFFER${suffix}MONTH001`;
    const version = 1;
    versions[termCount] = { offerId, version };
    await env.DB.prepare(
      `INSERT OR IGNORE INTO offer (offer_id, code, contract_version)
       VALUES (?, ?, 1)`,
    )
      .bind(offerId, `harness-pro-${termCount}month`)
      .run();
    await env.DB.prepare(
      `INSERT OR REPLACE INTO offer_version (
         offer_id, version, plan_id, plan_version, term_unit, term_count,
         price_minor, currency, allowance_credits, grace_days, grace_cap_rule,
         copy, terms_version, published_by, assertion_sha256, contract_version
       ) VALUES (?, ?, ?, ?, 'month', ?, ?, 'EGP', ?, 7, 'proportional', ?, ?, 'fixture', ?, 1)`,
    )
      .bind(
        offerId,
        version,
        PLAN_ID,
        PLAN_VERSION,
        termCount,
        1000 + termCount * 100,
        ALLOWANCE_CREDITS,
        JSON.stringify({
          en: {
            name: `Clinic Pro ${termCount} Months`,
            summary: `${termCount}-month clinic subscription`,
          },
        }),
        expectations.terms.version,
        `fixture-assertion-${termCount}m`,
      )
      .run();
    await env.DB.prepare(
      `INSERT OR IGNORE INTO offer_event (
         offer_id, kind, version, actor, at, contract_version
       ) VALUES (?, 'published', ?, 'fixture', '2026-02-01T00:00:00.000Z', 1)`,
    )
      .bind(offerId, version)
      .run();
  }
  return versions;
}

async function postCheckoutWithOffer(
  org: string,
  offer: { offerId: string; version: number },
  expectations: OffersFixtureExpectations,
  clientRequestId: string,
): Promise<{ checkoutId: string; reference: string }> {
  const headers = await administratorHeaders(org);
  const response = await billingFetch("/v1/checkouts", {
    method: "POST",
    headers,
    body: JSON.stringify({
      client_request_id: clientRequestId,
      offer_id: offer.offerId,
      offer_version: offer.version,
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

async function postPaymobCallback(
  fixture: PaymobCallbackFixture,
  options?: { connectingIp?: string },
): Promise<Response> {
  const body = JSON.stringify({ type: fixture.type, obj: fixture.obj });
  const hmac = await signPaymobObj(env.PAYMOB_HMAC_SECRET, fixture.obj);
  return billingFetch(`/notify/paymob?hmac=${encodeURIComponent(hmac)}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": options?.connectingIp ?? "203.0.113.10",
    },
    body,
  });
}

function refundParentFixtureWithTxnId(txnId: number): PaymobCallbackFixture {
  const base = refundParentFixture as PaymobCallbackFixture;
  return {
    type: base.type,
    obj: { ...base.obj, id: txnId },
  };
}

function refundChildFixtureWithTxnId(childTxnId: number): PaymobCallbackFixture {
  const base = refundChildFixture as PaymobCallbackFixture;
  return {
    type: base.type,
    obj: { ...base.obj, id: childTxnId },
  };
}

function partialRefundFixtureWithTxnId(txnId: number): PaymobCallbackFixture {
  const base = refundParentFixture as PaymobCallbackFixture;
  return {
    type: base.type,
    obj: {
      ...base.obj,
      id: txnId,
      is_refunded: true,
      amount_cents: "800",
    },
  };
}

async function paidCheckoutWithGrant(
  org: string,
  offer: { offerId: string; version: number },
  expectations: OffersFixtureExpectations,
  txnId: number,
): Promise<{ checkoutId: string; reference: string }> {
  await putBillingContact(org);
  await ensureGrantTenantBinding(org);
  const checkout = await postCheckoutWithOffer(
    org,
    offer,
    expectations,
    `req-sweep-paid-${org}-${txnId}`,
  );
  const chargedPrice = await syncPaymobForCheckout(checkout.checkoutId);
  const intake = await postPaymobProcessedCallback(
    successFixture as PaymobCallbackFixture,
    {
      txnId,
      connectingIp: `203.0.113.${txnId % 200}`,
      amountMinor: chargedPrice,
    },
  );
  expect(intake.status).toBe(200);
  await runGrantStep();
  return checkout;
}

async function paymentIdForCheckout(checkoutId: string): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT payment_id FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ payment_id: string }>();
    return row?.payment_id ?? null;
  } catch {
    return null;
  }
}

async function grantWorkState(paymentId: string): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT state FROM work WHERE kind = 'grant' AND subject_id = ?`,
    )
      .bind(paymentId)
      .first<{ state: string }>();
    return row?.state ?? null;
  } catch {
    return null;
  }
}

async function seedHeldForTransferBinding(orgId: string): Promise<void> {
  const installationId = crypto.randomUUID();
  const createdAt = "2026-06-01T12:00:00.000Z";
  await env.PLATFORM_DB.batch([
    env.PLATFORM_DB.prepare(
      `INSERT OR REPLACE INTO installation (
         installation_id, org_id, status, display_name, region, enrolled_at
       ) VALUES (?, ?, 'active', '', '', ?)`,
    ).bind(installationId, orgId, createdAt),
    env.PLATFORM_DB.prepare(
      `INSERT OR REPLACE INTO tenant_binding (
         org_id, installation_id, epoch, status, retired_at, reason, created_at
       ) VALUES (?, ?, 1, 'held_for_transfer', NULL, NULL, ?)`,
    ).bind(orgId, installationId, createdAt),
  ]);
}

async function activateTenantBinding(orgId: string): Promise<void> {
  await env.PLATFORM_DB.prepare(
    `UPDATE tenant_binding SET status = 'active' WHERE org_id = ?`,
  )
    .bind(orgId)
    .run();
}

async function reversalCount(): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM reversal`,
    ).first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function reversalEffectForPayment(
  paymentId: string,
): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT effect FROM reversal WHERE payment_id = ?`,
    )
      .bind(paymentId)
      .first<{ effect: string }>();
    return row?.effect ?? null;
  } catch {
    return null;
  }
}

async function reverseWorkCount(): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'reverse'`,
    ).first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function findingCount(kind?: string): Promise<number> {
  try {
    const row =
      kind === undefined
        ? await env.DB.prepare(`SELECT COUNT(*) AS n FROM finding`).first<{
            n: number;
          }>()
        : await env.DB.prepare(
            `SELECT COUNT(*) AS n FROM finding WHERE kind = ?`,
          )
            .bind(kind)
            .first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function findingSubjectForKind(kind: string): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT subject FROM finding WHERE kind = ? LIMIT 1`,
    )
      .bind(kind)
      .first<{ subject: string }>();
    return row?.subject ?? null;
  } catch {
    return null;
  }
}

async function platformGrantVoidCount(grantId: string): Promise<number> {
  try {
    const row = await env.PLATFORM_DB.prepare(
      `SELECT COUNT(*) AS n FROM grant_void WHERE grant_id = ?`,
    )
      .bind(grantId)
      .first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function recentTermState(
  orgId: string,
  paymentId: string,
): Promise<string | null> {
  const coverage = await platformCall("getCoverage", {
    contract_version: CONTRACT_VERSION,
    org_id: orgId,
  });
  if (coverage.result !== "ok") {
    return null;
  }
  const parsed = JSON.parse(String(coverage.detail)) as {
    recent_terms?: Array<{ term_id?: string; state?: string }>;
  };
  const grantId = await grantIdPaid(paymentId);
  const outcome = await env.DB.prepare(
    `SELECT term_ids FROM grant_outcome go
     JOIN grant_request gr ON gr.grant_id = go.grant_id
     WHERE gr.grant_id = ? OR gr.source_ref = ?`,
  )
    .bind(grantId, paymentId)
    .first<{ term_ids: string }>();
  if (!outcome?.term_ids) {
    return null;
  }
  const termIds = JSON.parse(outcome.term_ids) as string[];
  const termId = termIds[0];
  const match = (parsed.recent_terms ?? []).find(
    (term) => term.term_id === termId,
  );
  return match?.state ?? null;
}

async function getSubscriptionBody(
  org: string,
): Promise<{
  snapshot?: { queued_count?: number; held_count?: number; state?: string };
  notices?: string[];
}> {
  const headers = await administratorHeaders(org);
  const response = await billingFetch("/v1/subscription", { headers });
  expect(response.status).toBe(200);
  return (await response.json()) as {
    snapshot?: { queued_count?: number; held_count?: number; state?: string };
    notices?: string[];
  };
}

async function setupReversalHarness(): Promise<{
  expectations: OffersFixtureExpectations;
  offerVersions: Record<number, { offerId: string; version: number }>;
}> {
  const expectations = await setupSweepsHarness();
  const offerVersions = await seedTermOfferVersions(expectations);
  return { expectations, offerVersions };
}

async function advanceClockPastTermExpiry(): Promise<void> {
  await setClock(addMinutes("2026-06-01T12:00:00.000Z", 45));
  await runScheduled("0 * * * *");
}

async function setupActiveAndQueuedTerms(
  org: string,
  expectations: OffersFixtureExpectations,
  offer: { offerId: string; version: number },
  firstTxnId: number,
  secondTxnId: number,
): Promise<{ activeCheckoutId: string; activePaymentId: string }> {
  await putBillingContact(org);
  await ensureGrantTenantBinding(org);
  const firstCheckout = await postCheckoutWithOffer(
    org,
    offer,
    expectations,
    `req-sweep-active-${firstTxnId}`,
  );
  const secondCheckout = await postCheckoutWithOffer(
    org,
    offer,
    expectations,
    `req-sweep-queued-${secondTxnId}`,
  );
  const firstChargedPrice = await syncPaymobForCheckout(firstCheckout.checkoutId);
  await postPaymobProcessedCallback(successFixture as PaymobCallbackFixture, {
    txnId: firstTxnId,
    amountMinor: firstChargedPrice,
  });
  await runGrantStep();
  const secondChargedPrice = await syncPaymobForCheckout(
    secondCheckout.checkoutId,
  );
  await postPaymobProcessedCallback(successFixture as PaymobCallbackFixture, {
    txnId: secondTxnId,
    connectingIp: `203.0.113.${secondTxnId % 200}`,
    amountMinor: secondChargedPrice,
  });
  await runGrantStep();
  const activePaymentId = await paymentIdForCheckout(firstCheckout.checkoutId);
  expect(activePaymentId).not.toBeNull();
  const subscriptionBefore = await getSubscriptionBody(org);
  expect((subscriptionBefore.snapshot?.queued_count ?? 0) > 0).toBe(true);
  return {
    activeCheckoutId: firstCheckout.checkoutId,
    activePaymentId: activePaymentId!,
  };
}

async function setupSweepsHarness(): Promise<OffersFixtureExpectations> {
  const expectations = await seedOffersCatalogueFixture();
  expect(expectations).not.toBeNull();
  await registerAboGrantKeyOnPlatform();
  await publishPlanProOnPlatform();
  return expectations!;
}

beforeEach(async () => {
  await resetCrossWorkerHarness();
  await setupCrossWorkerHarness();
  await ensureMigrations();
  await scriptPaymobStub("ok");
  await scriptPaymobInquiry("bound_success");
  await setClock("2026-06-01T12:00:00.000Z");
});

describe("sweeps cross-worker", () => {
  it("E2E-P4.5-01 callback blocked, +2 min sweep confirms and grants", async () => {
    const expectations = await setupSweepsHarness();
    const txnId = 95001;
    const { checkoutId } = await createOpenCheckoutWithoutCallback(
      ORG_SWEEP_01,
      expectations,
      `req-sweep-01-${txnId}`,
    );
    expect(await tableCount("notification")).toBe(0);
    expect(await paymentCountForCheckout(checkoutId)).toBe(0);

    const openedAt = await openedEventAt(checkoutId);

    await setClock(addMinutes(openedAt, 2));
    await runScheduled("* * * * *");
    await runGrantStep();

    expect(await paymentCountForCheckout(checkoutId)).toBe(1);
    expect(await grantOutcomeCount()).toBeGreaterThan(0);
    expect(await alertCountByCode("AL-03")).toBe(1);

    const snapshot = await platformCoverageSnapshot(ORG_SWEEP_01);
    expect(snapshot?.state).toBe("active");

    for (const offsetMin of [5, 10, 20]) {
      await setClock(addMinutes(openedAt, offsetMin));
      await runScheduled("* * * * *");
      expect(await paymentCountForCheckout(checkoutId)).toBe(1);
      expect(await doneSweepCheckoutWorkCount(checkoutId)).toBeGreaterThanOrEqual(
        offsetMin === 5 ? 2 : offsetMin === 10 ? 3 : 4,
      );
    }
    expect(await sweepCheckoutWorkCount(checkoutId)).toBeGreaterThanOrEqual(4);
  });

  it("E2E-P4.5-02 HMAC failures still confirm by sweep", async () => {
    const expectations = await setupSweepsHarness();
    const txnId = 95002;
    const { checkoutId } = await createOpenCheckoutWithoutCallback(
      ORG_SWEEP_02,
      expectations,
      `req-sweep-02-${txnId}`,
    );
    const openedAt = await openedEventAt(checkoutId);

    for (let index = 0; index < 3; index += 1) {
      await setClock(addMinutes(openedAt, index));
      const response = await postBadHmacFixture(`203.0.113.${20 + index}`);
      expect(response.status).toBe(401);
    }
    expect(await alertCountByCode("AL-02")).toBe(1);
    expect(await paymentCountForCheckout(checkoutId)).toBe(0);

    await setClock(addMinutes(openedAt, 2));
    await runScheduled("* * * * *");
    await runGrantStep();

    expect(await paymentCountForCheckout(checkoutId)).toBe(1);
    expect(await grantOutcomeCount()).toBeGreaterThan(0);
  });

  it("E2E-P4.5-03 expiry then day-3 payment is paid_late", async () => {
    const expectations = await setupSweepsHarness();
    const txnId = 95003;
    const { checkoutId } = await createOpenCheckoutWithoutCallback(
      ORG_SWEEP_03,
      expectations,
      `req-sweep-03-${txnId}`,
    );
    const expiresAt = await checkoutExpiresAt(checkoutId);

    await setClock(expiresAt);
    await runScheduled("* * * * *");

    expect(await checkoutStatusState(checkoutId)).toBe("expired");
    expect(await getCheckoutShownState(ORG_SWEEP_03, checkoutId)).toBe(
      "Abandoned",
    );
    expect(await paymentCountForCheckout(checkoutId)).toBe(0);

    const day3 = addDays(expiresAt, 3);
    await setClock(day3);
    await runScheduled("* * * * *");

    expect(await checkoutStatusState(checkoutId)).toBe("paid_late");
    expect(await paymentClassification(checkoutId)).toBe("late");
    expect(await getCheckoutShownState(ORG_SWEEP_03, checkoutId)).toBe("Paid");
    expect(await grantOutcomeCount()).toBe(0);

    await runGrantStep();
    expect(await grantOutcomeCount()).toBeGreaterThan(0);
    expect(await alertCountByCode("AL-08")).toBe(1);
  });

  it("E2E-P4.5-12 crash after callback is inquired within 2–20 minutes", async () => {
    const expectations = await setupSweepsHarness();
    const txnId = 95012;
    const { checkoutId } = await createOpenCheckoutWithoutCallback(
      ORG_SWEEP_12,
      expectations,
      `req-sweep-12-${txnId}`,
    );
    const openedAt = await openedEventAt(checkoutId);
    const chargedPrice = await chargedPriceMinorForCheckout(checkoutId);

    setIntakeR2PutThrows(true);
    const intake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      {
        txnId,
        amountMinor: chargedPrice,
        connectingIp: "203.0.113.112",
      },
    );
    expect(intake.status).toBe(500);
    expect(await tableCount("notification")).toBe(0);
    expect(await confirmWorkState(checkoutId)).toBeNull();
    expect(await paymentCountForCheckout(checkoutId)).toBe(0);

    await setClock(addMinutes(openedAt, 10));
    await scriptPaymobInquiry("bound_success");
    await runScheduled("* * * * *");

    expect(await paymentCountForCheckout(checkoutId)).toBe(1);
    expect(await doneSweepCheckoutWorkCount(checkoutId)).toBeGreaterThanOrEqual(1);
  });

  it("E2E-P4.5-04 parent-flag refund ends the active term and holds the queue", async () => {
    const { expectations, offerVersions } = await setupReversalHarness();
    const org = ORG_SWEEP_04;
    const firstTxnId = 95104;
    const secondTxnId = 95105;
    const { activePaymentId } = await setupActiveAndQueuedTerms(
      org,
      expectations,
      offerVersions[1],
      firstTxnId,
      secondTxnId,
    );
    const paymentsBefore = await tableCount("payment");
    expect(await reversalCount()).toBe(0);

    const refundIntake = await postPaymobCallback(
      refundParentFixtureWithTxnId(firstTxnId),
      { connectingIp: "203.0.113.104" },
    );
    expect(refundIntake.status).toBe(200);
    expect(await tableCount("payment")).toBe(paymentsBefore);
    expect(await reversalCount()).toBe(1);
    expect(await reversalEffectForPayment(activePaymentId)).toBe("end_current");

    await scriptPaymobInquiry("reversed");
    await runScheduled("* * * * *");

    const grantId = await grantIdPaid(activePaymentId);
    expect(await platformGrantVoidCount(grantId)).toBe(1);
    expect(await reverseWorkCount()).toBe(0);
    expect(await alertCountByCode("AL-06")).toBe(1);

    const subscription = await getSubscriptionBody(org);
    expect((subscription.snapshot?.held_count ?? 0) > 0).toBe(true);
    expect(subscription.notices ?? []).toContain("terms_held");
    expect(await recentTermState(org, activePaymentId)).toBe("ended");
  });

  it("E2E-P4.5-05 child refund is the same reversal", async () => {
    const { expectations, offerVersions } = await setupReversalHarness();
    const org = ORG_SWEEP_05;
    const firstTxnId = 95106;
    const secondTxnId = 95107;
    const childTxnId = 95108;
    const { activePaymentId } = await setupActiveAndQueuedTerms(
      org,
      expectations,
      offerVersions[1],
      firstTxnId,
      secondTxnId,
    );

    const parentRefund = await postPaymobCallback(
      refundParentFixtureWithTxnId(firstTxnId),
      { connectingIp: "203.0.113.105" },
    );
    expect(parentRefund.status).toBe(200);
    expect(await reversalCount()).toBe(1);
    expect(await reversalEffectForPayment(activePaymentId)).toBe("end_current");

    const childRefund = await postPaymobCallback(
      refundChildFixtureWithTxnId(childTxnId),
      { connectingIp: "203.0.113.106" },
    );
    expect(childRefund.status).toBe(200);
    expect(await reversalCount()).toBe(1);
    expect(await tableCount("payment")).toBe(2);

    await scriptPaymobInquiry("reversed");
    await runScheduled("* * * * *");

    const grantId = await grantIdPaid(activePaymentId);
    expect(await platformGrantVoidCount(grantId)).toBe(1);
    expect(await alertCountByCode("AL-06")).toBe(1);
    const subscription = await getSubscriptionBody(org);
    expect(subscription.notices ?? []).toContain("terms_held");
  });

  it("E2E-P4.5-06 ended term reversal is effect none", async () => {
    const { expectations, offerVersions } = await setupReversalHarness();
    const org = ORG_SWEEP_06;
    const txnId = 95109;
    const { checkoutId } = await paidCheckoutWithGrant(
      org,
      offerVersions[1],
      expectations,
      txnId,
    );
    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();

    await advanceClockPastTermExpiry();

    const refundIntake = await postPaymobCallback(
      refundParentFixtureWithTxnId(txnId),
      { connectingIp: "203.0.113.107" },
    );
    expect(refundIntake.status).toBe(200);
    expect(await reversalCount()).toBe(1);
    expect(await reversalEffectForPayment(paymentId!)).toBe("none");

    await scriptPaymobInquiry("reversed");
    await runScheduled("* * * * *");

    const grantId = await grantIdPaid(paymentId!);
    expect(await platformGrantVoidCount(grantId)).toBe(0);
    expect(await reverseWorkCount()).toBe(0);
    expect(await alertCountByCode("AL-06")).toBe(1);
    expect(await recentTermState(org, paymentId!)).toBe("ended");
  });

  it("E2E-P4.5-07 full reversal while granting stores a tombstone", async () => {
    const { expectations, offerVersions } = await setupReversalHarness();
    const org = ORG_SWEEP_07;
    const txnId = 95110;
    await putBillingContact(org);
    await ensureGrantTenantBinding(org);
    await seedHeldForTransferBinding(org);
    const { checkoutId } = await postCheckoutWithOffer(
      org,
      offerVersions[1],
      expectations,
      `req-sweep-tombstone-${txnId}`,
    );
    const chargedPrice = await syncPaymobForCheckout(checkoutId);
    const intake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      {
        txnId,
        amountMinor: chargedPrice,
      },
    );
    expect(intake.status).toBe(200);
    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();
    expect(await grantWorkState(paymentId!)).toBe("open");
    expect(await grantOutcomeCount()).toBe(0);

    const refundIntake = await postPaymobCallback(
      refundParentFixtureWithTxnId(txnId),
      { connectingIp: "203.0.113.108" },
    );
    expect(refundIntake.status).toBe(200);
    expect(await reversalCount()).toBe(1);
    expect(await reversalEffectForPayment(paymentId!)).toBe("tombstone");

    await scriptPaymobInquiry("reversed");
    await runScheduled("* * * * *");

    const grantId = await grantIdPaid(paymentId!);
    expect(await platformGrantVoidCount(grantId)).toBe(1);

    await activateTenantBinding(org);
    await runGrantStep();
    expect(await grantWorkState(paymentId!)).toBe("done");
    const outcome = await env.DB.prepare(
      `SELECT result FROM grant_outcome WHERE grant_id = ?`,
    )
      .bind(grantId)
      .first<{ result: string }>();
    expect(outcome?.result).toBe("rejected");
  });

  it("E2E-P4.5-08 partial refund stays in review", async () => {
    const { expectations, offerVersions } = await setupReversalHarness();
    const org = ORG_SWEEP_08;
    const txnId = 95111;
    const { checkoutId } = await paidCheckoutWithGrant(
      org,
      offerVersions[1],
      expectations,
      txnId,
    );
    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();
    const grantId = await grantIdPaid(paymentId!);
    expect(await platformGrantVoidCount(grantId)).toBe(0);

    const refundIntake = await postPaymobCallback(
      partialRefundFixtureWithTxnId(txnId),
      { connectingIp: "203.0.113.109" },
    );
    expect(refundIntake.status).toBe(200);
    expect(await reversalCount()).toBe(1);
    expect(await reversalEffectForPayment(paymentId!)).toBe("review_partial");

    await scriptPaymobInquiry("partial_refund");
    await runScheduled("* * * * *");

    expect(await reverseWorkCount()).toBe(0);
    expect(await platformGrantVoidCount(grantId)).toBe(0);
    expect(await alertCountByCode("AL-06")).toBe(1);
  });

  it("E2E-P4.5-11 inquiry that contradicts a refund dismisses it", async () => {
    const { expectations, offerVersions } = await setupReversalHarness();
    const org = ORG_SWEEP_11;
    const txnId = 95112;
    const { checkoutId } = await paidCheckoutWithGrant(
      org,
      offerVersions[1],
      expectations,
      txnId,
    );
    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();

    const refundIntake = await postPaymobCallback(
      refundParentFixtureWithTxnId(txnId),
      { connectingIp: "203.0.113.111" },
    );
    expect(refundIntake.status).toBe(200);
    expect(await reversalCount()).toBe(1);

    await scriptPaymobInquiry("bound_success");
    await runScheduled("* * * * *");

    expect(await findingCount("inquiry_disagrees")).toBe(1);
    const reversalSubject = await findingSubjectForKind("inquiry_disagrees");
    expect(reversalSubject).not.toBeNull();
    const grantId = await grantIdPaid(paymentId!);
    expect(await platformGrantVoidCount(grantId)).toBe(0);
    expect(await reverseWorkCount()).toBe(0);
  });
});
