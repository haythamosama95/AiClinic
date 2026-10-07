/**
 * P4.6 — operator console E2E tests (H-XW), E2E-P4.6-01 through E2E-P4.6-05 and E2E-P4.6-07.
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import {
  CHANNEL_VERSIONS,
  grantIdPaid,
  humanRef,
  subscriptionRef,
} from "vendor-contracts";
import offersFixture from "../../fixtures/offers.json";
import successFixture from "../fixtures/paymob/success.json";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import notifyWorkMigrationSql from "../../migrations/0003_notify_work.sql?raw";
import grantMigrationSql from "../../migrations/0004_grant.sql?raw";
import reversalMigrationSql from "../../migrations/0005_reversal.sql?raw";
import { loadOffersFixture } from "../../src/records/append";
import {
  applySql,
  billingFetch,
  mintBilling,
  newIssuer,
  opsFetch,
  pinIssuer,
  runScheduled,
  tableCount,
} from "./harness";
import { mintHxwVendorAccessJwt } from "./hxw-access-fixture";
import {
  mintVendorAccessJwt,
  platformCall,
  resetCrossWorkerHarness,
  scriptPaymobStub,
  setClock,
  setupActivePlatformCoverage,
  setupCrossWorkerHarness,
  syncPlatformGrantLedger,
} from "./cross-worker-harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const OPS_OPERATOR_EMAIL = "ops.operator@test";
const PLAN_ID = "plan-pro";
const PLAN_VERSION = 1;
const ALLOWANCE_CREDITS = 100;

const ORG_OPS_02 = "a4660002-0000-4002-8002-000000000002";
const ORG_OPS_03 = "a4660003-0000-4003-8003-000000000003";
const ORG_OPS_04 = "a4660004-0000-4004-8004-000000000004";
const ORG_OPS_05 = "a4660005-0000-4005-8005-000000000005";
const ORG_OPS_07 = "a4660007-0000-4007-8007-000000000007";

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

type SeededClinic = {
  orgId: string;
  subscriptionRef: string;
  billingEmail: string;
  checkoutId: string;
  checkoutReference: string;
  paymentId: string;
  paymentReference: string;
  grantId: string;
  grantReference: string;
};

declare module "cloudflare:test" {
  interface ProvidedEnv {
    PLATFORM_DB: D1Database;
    ABO_GRANT_KEY: string;
    ACCESS_AUD: string;
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
    reversalMigrationSql,
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

async function registerAboGrantKeyOnPlatform(): Promise<void> {
  const aboKey = parseAboGrantKey();
  const notBefore = "2020-01-01T00:00:00.000Z";
  const notAfter = "2099-01-01T00:00:00.000Z";
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO service_key
       (kid, service, public_key, status, not_before, not_after, registered_by, assertion_sha256)
     VALUES (?, 'abo', ?, 'active', ?, ?, ?, 'harness')`,
  )
    .bind(aboKey.kid, aboKey.public_key, notBefore, notAfter, OPS_OPERATOR_EMAIL)
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
      JSON.stringify(["clinic.visit_summary"]),
      "2",
      4,
      ALLOWANCE_CREDITS,
      OPS_OPERATOR_EMAIL,
    )
    .run();
}

async function retirePlanProOnPlatform(): Promise<void> {
  await env.PLATFORM_DB.prepare(
    `UPDATE plan_version SET status = 'retired' WHERE plan_id = ? AND version = ?`,
  )
    .bind(PLAN_ID, PLAN_VERSION)
    .run();
}

async function registerClinicIssuerKey(): Promise<void> {
  const issuer = await newIssuer();
  await pinIssuer(issuer.kid, issuer.publicKey);
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

async function putBillingContact(
  org: string,
  email = "admin@clinic.test",
): Promise<void> {
  const headers = await administratorHeaders(org);
  const response = await billingFetch("/v1/billing-contact", {
    method: "PUT",
    headers,
    body: JSON.stringify({
      client_request_id: `req-contact-${org}`,
      name: "Clinic Admin",
      email,
      phone: "+201001234567",
    }),
  });
  expect(response.status).toBe(200);
}

async function postCheckout(
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

async function chargedPriceMinorForCheckout(checkoutId: string): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT charged_price_minor FROM checkout WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ charged_price_minor: number }>();
  expect(row).not.toBeNull();
  return row!.charged_price_minor;
}

async function syncPaymobForCheckout(checkoutId: string): Promise<number> {
  const chargedPrice = await chargedPriceMinorForCheckout(checkoutId);
  await env.PAYMOB_STUB.fetch("http://paymob.stub/__script", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ amount_cents: String(chargedPrice) }),
  });
  return chargedPrice;
}

async function postPaymobProcessedCallback(
  fixture: PaymobCallbackFixture,
  options?: {
    txnId?: number;
    connectingIp?: string;
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
      "cf-connecting-ip": options?.connectingIp ?? "203.0.113.10",
    },
    body,
  });
}

async function paidCheckoutFlow(
  org: string,
  offer: { offerId: string; version: number },
  expectations: OffersFixtureExpectations,
  txnId: number,
): Promise<{ checkoutId: string; reference: string }> {
  await putBillingContact(org);
  const checkout = await postCheckout(
    org,
    offer,
    expectations,
    `req-ops-${org}-${txnId}`,
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
  await runScheduled("* * * * *");
  return checkout;
}

async function setupOpsHarness(): Promise<{
  expectations: OffersFixtureExpectations;
  offerVersions: Record<number, { offerId: string; version: number }>;
}> {
  const expectations = await seedOffersCatalogueFixture();
  expect(expectations).not.toBeNull();
  const offerVersions = await seedTermOfferVersions(expectations!);
  await registerAboGrantKeyOnPlatform();
  await publishPlanProOnPlatform();
  await registerClinicIssuerKey();
  return { expectations: expectations!, offerVersions };
}

async function opsHeaders(accessJwt?: string): Promise<Record<string, string>> {
  const headers: Record<string, string> = {
    "Abo-Contract-Version": "1",
  };
  if (accessJwt !== undefined) {
    headers["Cf-Access-Jwt-Assertion"] = accessJwt;
  }
  return headers;
}

async function platformTableCount(table: string): Promise<number> {
  try {
    const row = await env.PLATFORM_DB.prepare(
      `SELECT COUNT(*) AS n FROM ${table}`,
    ).first<{ n: number }>();
    return row?.n ?? 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return 0;
    }
    throw error;
  }
}

async function platformControlAuditCountForActor(
  email: string,
): Promise<number> {
  try {
    const row = await env.PLATFORM_DB.prepare(
      `SELECT COUNT(*) AS n FROM control_audit
       WHERE actor = ? OR operator_id = ?`,
    )
      .bind(email, email)
      .first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function grantWorkIdForPayment(paymentId: string): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT work_id FROM work WHERE kind = 'grant' AND subject_id = ?`,
    )
      .bind(paymentId)
      .first<{ work_id: string }>();
    return row?.work_id ?? null;
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

async function grantOutcomeResult(grantId: string): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT result FROM grant_outcome WHERE grant_id = ?`,
    )
      .bind(grantId)
      .first<{ result: string }>();
    return row?.result ?? null;
  } catch {
    return null;
  }
}

async function operatorActionRow(
  actionId: string,
): Promise<Record<string, unknown> | null> {
  try {
    return await env.DB.prepare(
      `SELECT * FROM operator_action WHERE action_id = ?`,
    )
      .bind(actionId)
      .first<Record<string, unknown>>();
  } catch {
    return null;
  }
}

async function seedFinding(
  orgId: string,
  checkoutId: string,
): Promise<string> {
  const findingId = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO finding (finding_id, kind, subject, detail, detected_at)
     VALUES (?, 'ops_harness', ?, ?, ?)`,
  )
    .bind(
      findingId,
      checkoutId,
      JSON.stringify({ org_id: orgId }),
      "2026-06-01T12:00:00.000Z",
    )
    .run();
  return findingId;
}

async function seedAlert(orgId: string, checkoutId: string): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO alert (alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id)
     VALUES (?, 'AL-99', 1, 0, NULL, NULL, ?)`,
  )
    .bind(`AL-99:${orgId}:${checkoutId}`, `detail-${checkoutId}`)
    .run();
}

async function seedReversal(
  paymentId: string,
  reference: string,
): Promise<string> {
  const reversalId = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO reversal (
       reversal_id, payment_id, reference, amount_minor, kind, is_full,
       source, cumulative_reversed_minor, detected_via, recorded_by,
       evidence_sha256, effect, dedupe_key
     ) VALUES (?, ?, ?, 1000, 'chargeback', 0, 'operator', 1000, 'manual', ?, 'evidence', 'hold', ?)`,
  )
    .bind(
      reversalId,
      paymentId,
      reference,
      OPS_OPERATOR_EMAIL,
      `reversal-${paymentId}`,
    )
    .run();
  return reversalId;
}

async function seedRichClinic(
  orgId: string,
  expectations: OffersFixtureExpectations,
  offerVersions: Record<number, { offerId: string; version: number }>,
): Promise<SeededClinic> {
  await setClock("2026-06-01T12:00:00.000Z");
  const billingEmail = "ops-clinic@clinic.test";
  await putBillingContact(orgId, billingEmail);
  await setupActivePlatformCoverage(orgId);
  const { checkoutId, reference: checkoutReference } = await paidCheckoutFlow(
    orgId,
    offerVersions[1],
    expectations,
    96602,
  );
  const paymentId = await paymentIdForCheckout(checkoutId);
  expect(paymentId).not.toBeNull();
  const paymentReference = humanRef("PAY", paymentId!);
  const grantId = await grantIdPaid(paymentId!);
  const grantReference = humanRef("GR", grantId);
  await syncPlatformGrantLedger(orgId);
  await seedFinding(orgId, checkoutId);
  await seedAlert(orgId, checkoutId);
  await seedReversal(paymentId!, humanRef("REV", crypto.randomUUID()));
  const subRef = await subscriptionRef(orgId);
  return {
    orgId,
    subscriptionRef: subRef,
    billingEmail,
    checkoutId,
    checkoutReference,
    paymentId: paymentId!,
    paymentReference,
    grantId,
    grantReference,
  };
}

function expectContractVersion(response: Response, body: Record<string, unknown>): void {
  expect(response.headers.get("Abo-Contract-Version")).toBe("1");
  expect(body.contract_version).toBe(1);
}

beforeEach(async () => {
  await resetCrossWorkerHarness();
  await setupCrossWorkerHarness();
  await ensureMigrations();
  await scriptPaymobStub("ok");
  await setClock("2026-06-01T12:00:00.000Z");
});

describe("ops cross-worker", () => {
  it("E2E-P4.6-01 ops host and recordOperatorAction reject bad Access JWT", async () => {
    const operatorActionBefore = await tableCount("operator_action");
    const controlAuditBefore = await platformTableCount("control_audit");

    const opsPaths = ["/ops/lookup?q=test", "/ops/parked", "/ops/findings"];

    for (const path of opsPaths) {
      const noJwt = await opsFetch(path, {
        headers: await opsHeaders(),
      });
      expect(noJwt.status).toBe(401);
      const noJwtBody = (await noJwt.json()) as Record<string, unknown>;
      expect(noJwtBody.code).toBe("unauthenticated");
      expect(noJwtBody.message).toBe("unauthenticated");
      expect(noJwtBody.contract_version).toBe(1);
    }

    const clockIso = "2026-06-01T12:00:00.000Z";
    await setClock(clockIso);
    const nowSeconds = Math.floor(Date.parse(clockIso) / 1000);
    const expiredJwt = await mintHxwVendorAccessJwt(
      env.ACCESS_AUD,
      OPS_OPERATOR_EMAIL,
      nowSeconds,
    );
    await setClock("2026-06-03T12:00:00.000Z");
    for (const path of opsPaths) {
      const expired = await opsFetch(path, {
        headers: await opsHeaders(expiredJwt),
      });
      expect(expired.status).toBe(401);
      const expiredBody = (await expired.json()) as Record<string, unknown>;
      expect(expiredBody.code).toBe("unauthenticated");
    }

    await setClock(clockIso);
    const wrongAudJwt = await mintHxwVendorAccessJwt(
      "wrong-audience",
      OPS_OPERATOR_EMAIL,
      nowSeconds,
    );
    for (const path of opsPaths) {
      const wrongAud = await opsFetch(path, {
        headers: await opsHeaders(wrongAudJwt),
      });
      expect(wrongAud.status).toBe(401);
      const wrongAudBody = (await wrongAud.json()) as Record<string, unknown>;
      expect(wrongAudBody.code).toBe("unauthenticated");
    }

    const wrongIssJwt = await mintHxwVendorAccessJwt(
      env.ACCESS_AUD,
      OPS_OPERATOR_EMAIL,
      nowSeconds,
      { iss: "https://bad-issuer.test" },
    );
    for (const path of opsPaths) {
      const wrongIss = await opsFetch(path, {
        headers: await opsHeaders(wrongIssJwt),
      });
      expect(wrongIss.status).toBe(401);
      const wrongIssBody = (await wrongIss.json()) as Record<string, unknown>;
      expect(wrongIssBody.code).toBe("unauthenticated");
    }

    expect(await tableCount("operator_action")).toBe(operatorActionBefore);

    const recordArgs = {
      contract_version: CONTRACT_VERSION,
      action: "Retry parked work",
      subject: "work-subject",
      action_id: crypto.randomUUID(),
    };

    const noJwtCall = await platformCall("recordOperatorAction", recordArgs);
    expect(noJwtCall.result).toBe("rejected");
    expect(noJwtCall.code).toBe("unauthenticated");

    const expiredCall = await platformCall("recordOperatorAction", recordArgs, {
      accessJwt: expiredJwt,
    });
    expect(expiredCall.result).toBe("rejected");
    expect(expiredCall.code).toBe("unauthenticated");

    const wrongAudCall = await platformCall("recordOperatorAction", recordArgs, {
      accessJwt: wrongAudJwt,
    });
    expect(wrongAudCall.result).toBe("rejected");
    expect(wrongAudCall.code).toBe("unauthenticated");

    expect(await platformTableCount("control_audit")).toBe(controlAuditBefore);
  });

  it("E2E-P4.6-02 lookup by AIC and clinic page with global views", async () => {
    const { expectations, offerVersions } = await setupOpsHarness();
    const clinic = await seedRichClinic(ORG_OPS_02, expectations, offerVersions);
    const accessJwt = await mintVendorAccessJwt(OPS_OPERATOR_EMAIL);
    const sessionHeaders = await opsHeaders(accessJwt);

    const lookup = await opsFetch(
      `/ops/lookup?q=${encodeURIComponent(clinic.subscriptionRef)}`,
      { headers: sessionHeaders },
    );
    expect(lookup.status).toBe(200);
    const lookupBody = (await lookup.json()) as Record<string, unknown>;
    expectContractVersion(lookup, lookupBody);
    expect(lookupBody.org_id).toBe(clinic.orgId);

    const clinicPage = await opsFetch(`/ops/clinics/${clinic.orgId}`, {
      headers: sessionHeaders,
    });
    expect(clinicPage.status).toBe(200);
    const clinicBody = (await clinicPage.json()) as Record<string, unknown>;
    expectContractVersion(clinicPage, clinicBody);
    expect(clinicBody.terms).toBeDefined();
    expect(clinicBody.grants).toBeDefined();
    expect(clinicBody.reservations).toBeDefined();
    expect(Array.isArray(clinicBody.checkouts)).toBe(true);
    expect((clinicBody.checkouts as unknown[]).length).toBeGreaterThan(0);
    expect(Array.isArray(clinicBody.payments)).toBe(true);
    expect((clinicBody.payments as unknown[]).length).toBeGreaterThan(0);
    expect(Array.isArray(clinicBody.reversals)).toBe(true);
    expect(Array.isArray(clinicBody.grant_requests)).toBe(true);
    expect(Array.isArray(clinicBody.operator_actions)).toBe(true);
    expect(Array.isArray(clinicBody.findings)).toBe(true);
    expect((clinicBody.findings as unknown[]).length).toBeGreaterThan(0);
    expect(Array.isArray(clinicBody.alerts)).toBe(true);
    expect((clinicBody.alerts as unknown[]).length).toBeGreaterThan(0);

    const parked = await opsFetch("/ops/parked", { headers: sessionHeaders });
    expect(parked.status).toBe(200);
    const parkedBody = (await parked.json()) as Record<string, unknown>;
    expectContractVersion(parked, parkedBody);
    expect(Array.isArray(parkedBody.parked)).toBe(true);

    const findings = await opsFetch("/ops/findings", { headers: sessionHeaders });
    expect(findings.status).toBe(200);
    const findingsBody = (await findings.json()) as Record<string, unknown>;
    expectContractVersion(findings, findingsBody);
    expect(Array.isArray(findingsBody.findings)).toBe(true);
    expect((findingsBody.findings as unknown[]).length).toBeGreaterThan(0);

    const grants = await opsFetch("/ops/grants", { headers: sessionHeaders });
    expect(grants.status).toBe(200);
    const grantsBody = (await grants.json()) as Record<string, unknown>;
    expectContractVersion(grants, grantsBody);
    expect(grantsBody.by_source_kind).toBeDefined();
    expect(grantsBody.by_operator_credential_id).toBeDefined();

    const payoutImports = await opsFetch("/ops/payout-imports", {
      headers: sessionHeaders,
    });
    expect(payoutImports.status).toBe(200);
    const payoutBody = (await payoutImports.json()) as Record<string, unknown>;
    expectContractVersion(payoutImports, payoutBody);
    expect(payoutBody.payout_imports).toEqual([]);

    const registries = await opsFetch("/ops/registries", {
      headers: sessionHeaders,
    });
    expect(registries.status).toBe(200);
    const registriesBody = (await registries.json()) as Record<string, unknown>;
    expectContractVersion(registries, registriesBody);
    expect(Array.isArray(registriesBody.issuer_keys)).toBe(true);
    expect(Array.isArray(registriesBody.service_keys)).toBe(true);
    expect(Array.isArray(registriesBody.operator_credentials)).toBe(true);
  });

  it("E2E-P4.6-03 lookup by billing email, PAY-, org_id, CK-, and GR-", async () => {
    const { expectations, offerVersions } = await setupOpsHarness();
    const clinic = await seedRichClinic(ORG_OPS_03, expectations, offerVersions);
    const accessJwt = await mintVendorAccessJwt(OPS_OPERATOR_EMAIL);
    const sessionHeaders = await opsHeaders(accessJwt);

    const aicLookup = await opsFetch(
      `/ops/lookup?q=${encodeURIComponent(clinic.subscriptionRef)}`,
      { headers: sessionHeaders },
    );
    expect(aicLookup.status).toBe(200);
    const aicBody = (await aicLookup.json()) as Record<string, unknown>;
    expect(aicBody.org_id).toBe(clinic.orgId);

    const lookups = [
      clinic.billingEmail,
      clinic.paymentReference,
      clinic.orgId,
      clinic.checkoutReference,
      clinic.grantReference,
    ];
    for (const query of lookups) {
      const response = await opsFetch(`/ops/lookup?q=${encodeURIComponent(query)}`, {
        headers: sessionHeaders,
      });
      expect(response.status).toBe(200);
      const body = (await response.json()) as Record<string, unknown>;
      expect(body.org_id).toBe(clinic.orgId);
    }
  });

  it("E2E-P4.6-07 inspectCoverage relay and direct call rejection", async () => {
    const { expectations, offerVersions } = await setupOpsHarness();
    const clinic = await seedRichClinic(ORG_OPS_07, expectations, offerVersions);
    const accessJwt = await mintVendorAccessJwt(OPS_OPERATOR_EMAIL);
    const sessionHeaders = await opsHeaders(accessJwt);
    const controlAuditBefore = await platformTableCount("control_audit");
    const actorAuditBefore = await platformControlAuditCountForActor(
      OPS_OPERATOR_EMAIL,
    );

    const clinicPage = await opsFetch(`/ops/clinics/${clinic.orgId}`, {
      headers: sessionHeaders,
    });
    expect(clinicPage.status).toBe(200);
    const clinicBody = (await clinicPage.json()) as Record<string, unknown>;
    expectContractVersion(clinicPage, clinicBody);
    expect(clinicBody.terms).toBeDefined();
    expect(clinicBody.grants).toBeDefined();
    expect(clinicBody.reservations).toBeDefined();
    expect(clinicBody.email).toBeUndefined();

    expect(await platformTableCount("control_audit")).toBe(controlAuditBefore);
    expect(await platformControlAuditCountForActor(OPS_OPERATOR_EMAIL)).toBe(
      actorAuditBefore,
    );

    const direct = await platformCall("inspectCoverage", {
      contract_version: CONTRACT_VERSION,
      org_id: clinic.orgId,
    });
    expect(direct.result).toBe("rejected");
    expect(direct.code).toBe("unauthenticated");
    expect(await platformTableCount("control_audit")).toBe(controlAuditBefore);
  });

  it("E2E-P4.6-04 retry parked grant work records operator_action", async () => {
    const { expectations, offerVersions } = await setupOpsHarness();
    await setClock("2026-06-01T12:00:00.000Z");
    const orgId = ORG_OPS_04;
    await putBillingContact(orgId);
    await setupActivePlatformCoverage(orgId);
    await retirePlanProOnPlatform();
    const { checkoutId } = await paidCheckoutFlow(
      orgId,
      offerVersions[1],
      expectations,
      96604,
    );
    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();
    expect(await grantWorkState(paymentId!)).toBe("parked");

    await publishPlanProOnPlatform();
    const accessJwt = await mintVendorAccessJwt(OPS_OPERATOR_EMAIL);
    const sessionHeaders = await opsHeaders(accessJwt);
    const controlAuditBefore = await platformControlAuditCountForActor(
      OPS_OPERATOR_EMAIL,
    );

    const parkedView = await opsFetch("/ops/parked", { headers: sessionHeaders });
    expect(parkedView.status).toBe(200);
    const parkedBody = (await parkedView.json()) as Record<string, unknown>;
    const parkedRows = parkedBody.parked as Array<Record<string, unknown>>;
    expect(parkedRows.length).toBeGreaterThan(0);
    const workId = await grantWorkIdForPayment(paymentId!);
    expect(workId).not.toBeNull();

    const retry = await opsFetch(`/ops/parked/${workId!}/retry`, {
      method: "POST",
      headers: sessionHeaders,
    });
    expect(retry.status).toBe(200);
    const retryBody = (await retry.json()) as Record<string, unknown>;
    expectContractVersion(retry, retryBody);
    const actionId = String(retryBody.action_id);
    expect(actionId.length).toBeGreaterThan(0);
    expect(await grantWorkState(paymentId!)).toBe("open");

    const { runDueGrantWork } = await import("../../src/work/grant");
    await runDueGrantWork(env as never);
    await syncPlatformGrantLedger(orgId);
    const grantId = await grantIdPaid(paymentId!);
    expect(await grantOutcomeResult(grantId)).toBe("applied");

    const actionRow = await operatorActionRow(actionId);
    expect(actionRow).not.toBeNull();
    expect(actionRow!.actor_email).toBe(OPS_OPERATOR_EMAIL);
    expect(typeof actionRow!.access_jti).toBe("string");
    expect(String(actionRow!.access_jti).length).toBeGreaterThan(0);

    const auditCount = await platformControlAuditCountForActor(OPS_OPERATOR_EMAIL);
    expect(auditCount).toBe(controlAuditBefore + 1);
    const auditRow = await env.PLATFORM_DB.prepare(
      `SELECT actor, operator_id, action, target, assertion_sha256
       FROM control_audit WHERE target = ?`,
    )
      .bind(actionId)
      .first<{
        actor: string;
        operator_id: string;
        action: string;
        target: string;
        assertion_sha256: string | null;
      }>();
    expect(auditRow).not.toBeNull();
    expect(auditRow!.actor).toBe(OPS_OPERATOR_EMAIL);
    expect(auditRow!.operator_id).toBe(OPS_OPERATOR_EMAIL);
    expect(auditRow!.action).toBe("Retry parked work");
    expect(auditRow!.target).toBe(actionId);
    expect(auditRow!.assertion_sha256).toBeNull();

    const repeat = await platformCall(
      "recordOperatorAction",
      {
        contract_version: CONTRACT_VERSION,
        action: "Retry parked work",
        subject: workId!,
        action_id: actionId,
      },
      { accessJwt },
    );
    expect(repeat.result).toBe("ok");
    expect(await platformControlAuditCountForActor(OPS_OPERATOR_EMAIL)).toBe(
      auditCount,
    );
    expect(await tableCount("operator_action")).toBe(1);
  });

  it("E2E-P4.6-05 cancel open checkout then later payment is paid_late", async () => {
    const { expectations, offerVersions } = await setupOpsHarness();
    const orgId = ORG_OPS_05;
    await setClock("2026-06-01T12:00:00.000Z");
    await putBillingContact(orgId);
    await setupActivePlatformCoverage(orgId);
    const { checkoutId } = await postCheckout(
      orgId,
      offerVersions[1],
      expectations,
      "req-ops-05-cancel",
    );
    await syncPaymobForCheckout(checkoutId);
    expect(await checkoutStatusState(checkoutId)).toBe("open");

    const accessJwt = await mintVendorAccessJwt(OPS_OPERATOR_EMAIL);
    const sessionHeaders = await opsHeaders(accessJwt);
    const controlAuditBefore = await platformControlAuditCountForActor(
      OPS_OPERATOR_EMAIL,
    );

    const cancel = await opsFetch(`/ops/checkouts/${checkoutId}/cancel`, {
      method: "POST",
      headers: sessionHeaders,
    });
    expect(cancel.status).toBe(200);
    const cancelBody = (await cancel.json()) as Record<string, unknown>;
    expectContractVersion(cancel, cancelBody);
    const actionId = String(cancelBody.action_id);
    expect(await checkoutStatusState(checkoutId)).toBe("cancelled");

    const actionRow = await operatorActionRow(actionId);
    expect(actionRow).not.toBeNull();
    expect(actionRow!.actor_email).toBe(OPS_OPERATOR_EMAIL);
    expect(typeof actionRow!.access_jti).toBe("string");
    expect(String(actionRow!.access_jti).length).toBeGreaterThan(0);

    const auditCount = await platformControlAuditCountForActor(OPS_OPERATOR_EMAIL);
    expect(auditCount).toBe(controlAuditBefore + 1);
    const auditRow = await env.PLATFORM_DB.prepare(
      `SELECT actor, operator_id, action, target
       FROM control_audit WHERE target = ?`,
    )
      .bind(actionId)
      .first<{ actor: string; operator_id: string; action: string; target: string }>();
    expect(auditRow).not.toBeNull();
    expect(auditRow!.actor).toBe(OPS_OPERATOR_EMAIL);
    expect(auditRow!.operator_id).toBe(OPS_OPERATOR_EMAIL);
    expect(auditRow!.action).toBe("Cancel an open checkout");

    const repeat = await platformCall(
      "recordOperatorAction",
      {
        contract_version: CONTRACT_VERSION,
        action: "Cancel an open checkout",
        subject: checkoutId,
        action_id: actionId,
      },
      { accessJwt },
    );
    expect(repeat.result).toBe("ok");
    expect(await platformControlAuditCountForActor(OPS_OPERATOR_EMAIL)).toBe(
      auditCount,
    );

    const openedAt = await env.DB.prepare(
      `SELECT at FROM checkout_event WHERE checkout_id = ? AND kind = 'opened'`,
    )
      .bind(checkoutId)
      .first<{ at: string }>();
    expect(openedAt).not.toBeNull();
    const laterAt = addMinutes(openedAt!.at, 5);
    await setClock(laterAt);
    const chargedPrice = await chargedPriceMinorForCheckout(checkoutId);
    const intake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      {
        txnId: 96605,
        amountMinor: chargedPrice,
      },
    );
    expect(intake.status).toBe(200);
    await runScheduled("* * * * *");
    expect(await checkoutStatusState(checkoutId)).toBe("paid_late");
  });
});
