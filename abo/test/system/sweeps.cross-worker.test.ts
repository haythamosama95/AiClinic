/**
 * P4.5 — checkout sweeps E2E tests (H-XW + H-PAY), E2E-P4.5-01 through E2E-P4.5-12.
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import offersFixture from "../../fixtures/offers.json";
import badHmacFixture from "../fixtures/paymob/bad-hmac.json";
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
});
