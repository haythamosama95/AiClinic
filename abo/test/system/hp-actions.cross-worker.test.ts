/**
 * P4.7 — console passkey ceremony and ABO-side HP actions (H-XW),
 * E2E-P4.7-01 through E2E-P4.7-07.
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import {
  CHANNEL_VERSIONS,
  grantIdPaid,
} from "vendor-contracts";
import {
  createSoftwareAuthenticator,
  type SoftwareAuthenticator,
} from "vendor-contracts/testkit";
import offersFixture from "../../fixtures/offers.json";
import successFixture from "../fixtures/paymob/success.json";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import notifyWorkMigrationSql from "../../migrations/0003_notify_work.sql?raw";
import grantMigrationSql from "../../migrations/0004_grant.sql?raw";
import reversalMigrationSql from "../../migrations/0005_reversal.sql?raw";
import operatorActionMigrationSql from "../../migrations/0006_operator_action.sql?raw";
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
import {
  mintVendorAccessJwt,
  platformCall,
  resetCrossWorkerHarness,
  scriptPaymobStub,
  setClock,
  setupActivePlatformCoverage,
  setupCrossWorkerHarness,
} from "./cross-worker-harness";

const VENDOR_CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const ABO_CONTRACT_VERSION = 1;
const VENDOR_OPERATOR_EMAIL = "operator@vendor.test";
const PLAN_ID = "plan-pro";
const PLAN_VERSION = 1;
const ALLOWANCE_CREDITS = 100;

const ORG_HP_01 = "a4770001-0001-4001-8001-000000000001";
const ORG_HP_02 = "a4770002-0002-4002-8002-000000000002";

const HP_V1_ONLY_OFFER_ID = "01JHP4P7PUBLISH00001";
const HP_V1_ONLY_VERSION = 1;
const HP_V1_ONLY_PRICE_MINOR = 800;
const HP_V2_PRICE_MINOR = 1000;

type OffersFixtureExpectations = {
  offer_id: string;
  version: number;
  price_minor: number;
  terms: { version: number; text: string };
  older_version: number;
};

type PublishOfferParams = {
  price_minor: number;
  terms_text: string;
  copy: {
    en: {
      name: string;
      summary: string;
    };
  };
};

type HpOperation = {
  op: string;
  params: Record<string, unknown>;
  actor_email: string;
  issued_at: string;
  nonce: string;
  contract_version: number;
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

type ActiveHpCredential = {
  credentialId: string;
  authenticator: SoftwareAuthenticator;
  accessJwt: string;
};

declare module "cloudflare:test" {
  interface ProvidedEnv {
    PLATFORM_DB: D1Database;
    ABO_GRANT_KEY: string;
    ACCESS_AUD: string;
    WEBAUTHN_RP_ID: string;
    WEBAUTHN_ORIGIN: string;
    PAYMOB_HMAC_SECRET: string;
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

function parseAboGrantKey(): AboGrantKey {
  return JSON.parse(env.ABO_GRANT_KEY) as AboGrantKey;
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
    operatorActionMigrationSql,
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
      JSON.stringify(["clinic.visit_summary"]),
      "2",
      4,
      ALLOWANCE_CREDITS,
      VENDOR_OPERATOR_EMAIL,
    )
    .run();
}

async function registerClinicIssuerKey(): Promise<void> {
  const issuer = await newIssuer();
  await pinIssuer(issuer.kid, issuer.publicKey);
}

async function setupHpHarness(): Promise<OffersFixtureExpectations> {
  const expectations = await seedOffersCatalogueFixture();
  expect(expectations).not.toBeNull();
  await registerAboGrantKeyOnPlatform();
  await publishPlanProOnPlatform();
  await registerClinicIssuerKey();
  return expectations!;
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

async function opsHeaders(accessJwt: string): Promise<Record<string, string>> {
  return {
    "Cf-Access-Jwt-Assertion": accessJwt,
    "Abo-Contract-Version": "1",
    "content-type": "application/json",
  };
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

async function currentHarnessClockIso(): Promise<string> {
  const row = await env.DB.prepare(
    `SELECT now_iso FROM harness_test_clock WHERE id = 'default'`,
  ).first<{ now_iso: string }>();
  return row?.now_iso ?? "2026-06-01T12:00:00.000Z";
}

async function platformPlanVersionSnapshot(): Promise<string> {
  const rows = await env.PLATFORM_DB.prepare(
    `SELECT plan_id, version, display_name, status
     FROM plan_version
     ORDER BY plan_id, version`,
  ).all<{
    plan_id: string;
    version: number;
    display_name: string;
    status: string;
  }>();
  return JSON.stringify(rows.results ?? []);
}

async function seedActiveOperatorCredential(
  authenticator: SoftwareAuthenticator,
  credentialId = crypto.randomUUID(),
): Promise<string> {
  const attestation = encodeVendorAttestation(await authenticator.attest());
  const activatesAt = "2020-01-01T00:00:00.000Z";
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
      activatesAt,
    )
    .run();
  return credentialId;
}

async function operationForRegisterCredential(input: {
  credentialId: string;
  signerCredentialId: string;
  attestation: { alg: "ES256" | "EdDSA"; public_key: string };
  accessJwt: string;
  issuedAt: string;
}): Promise<HpOperation> {
  return {
    op: "registerOperatorCredential",
    params: {
      contract_version: VENDOR_CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      credential_id: input.credentialId,
      attestation: input.attestation,
      signer_credential_id: input.signerCredentialId,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: input.issuedAt,
    nonce: crypto.randomUUID(),
    contract_version: VENDOR_CONTRACT_VERSION,
  };
}

async function operationForRevokeCredential(input: {
  credentialId: string;
  signerCredentialId: string;
  accessJwt: string;
  issuedAt: string;
}): Promise<HpOperation> {
  return {
    op: "revokeOperatorCredential",
    params: {
      contract_version: VENDOR_CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      credential_id: input.credentialId,
      signer_credential_id: input.signerCredentialId,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: input.issuedAt,
    nonce: crypto.randomUUID(),
    contract_version: VENDOR_CONTRACT_VERSION,
  };
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
  const operation = await operationForRegisterCredential({
    credentialId: input.credentialId,
    signerCredentialId: input.signerCredentialId,
    attestation,
    accessJwt: input.accessJwt,
    issuedAt,
  });
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
      contract_version: VENDOR_CONTRACT_VERSION,
      credential_id: input.credentialId,
      attestation,
      signer_credential_id: input.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt: input.accessJwt },
  );
}

async function revokeOperatorCredentialOnPlatform(input: {
  credentialId: string;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  accessJwt: string;
}): Promise<Record<string, unknown>> {
  const issuedAt = await currentHarnessClockIso();
  const operation = await operationForRevokeCredential({
    credentialId: input.credentialId,
    signerCredentialId: input.signerCredentialId,
    accessJwt: input.accessJwt,
    issuedAt,
  });
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
    "revokeOperatorCredential",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      credential_id: input.credentialId,
      signer_credential_id: input.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt: input.accessJwt },
  );
}

async function ensureActiveHpCredential(): Promise<ActiveHpCredential> {
  const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
  const signerCredentialId = await seedActiveOperatorCredential(
    signerAuthenticator,
  );
  const hpAuthenticator = await createSoftwareAuthenticator("EdDSA");
  const hpCredentialId = crypto.randomUUID();
  const accessJwt = await mintVendorAccessJwt();
  const registered = await registerOperatorCredentialWithSigner({
    credentialId: hpCredentialId,
    signerCredentialId,
    signerAuthenticator,
    attestationAuthenticator: hpAuthenticator,
    accessJwt,
  });
  expect(registered.result).toBe("ok");
  const row = JSON.parse(String(registered.detail)) as Record<string, unknown>;
  await setClock(String(row.activates_at));
  return {
    credentialId: hpCredentialId,
    authenticator: hpAuthenticator,
    accessJwt,
  };
}

function publishOfferParams(
  expectations: OffersFixtureExpectations,
  priceMinor: number,
): PublishOfferParams {
  return {
    price_minor: priceMinor,
    terms_text: expectations.terms.text,
    copy: {
      en: {
        name: "Clinic Pro Monthly",
        summary: "Monthly clinic subscription",
      },
    },
  };
}

async function buildHpOperation(input: {
  op: string;
  params: Record<string, unknown>;
  actorEmail: string;
  issuedAt?: string;
}): Promise<HpOperation> {
  return {
    op: input.op,
    params: input.params,
    actor_email: input.actorEmail,
    issued_at: input.issuedAt ?? (await currentHarnessClockIso()),
    nonce: crypto.randomUUID(),
    contract_version: ABO_CONTRACT_VERSION,
  };
}

async function signHpOperation(
  authenticator: SoftwareAuthenticator,
  operation: HpOperation,
): Promise<Record<string, string>> {
  return encodeVendorAssertion(
    await authenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
}

async function opsHpFetch(
  path: string,
  input: {
    accessJwt: string;
    operation: HpOperation;
    assertion?: Record<string, string>;
  },
): Promise<Response> {
  const body: Record<string, unknown> = {
    operation: input.operation,
  };
  if (input.assertion !== undefined) {
    body.assertion = input.assertion;
  }
  return opsFetch(path, {
    method: "POST",
    headers: await opsHeaders(input.accessJwt),
    body: JSON.stringify(body),
  });
}

async function seedV1OnlyPublishOffer(
  expectations: OffersFixtureExpectations,
): Promise<void> {
  await env.DB.prepare(
    `INSERT OR IGNORE INTO offer (offer_id, code, contract_version)
     VALUES (?, 'hp-v1-only-monthly', 1)`,
  )
    .bind(HP_V1_ONLY_OFFER_ID)
    .run();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO offer_version (
       offer_id, version, plan_id, plan_version, term_unit, term_count,
       price_minor, currency, allowance_credits, grace_days, grace_cap_rule,
       copy, terms_version, published_by, assertion_sha256, contract_version
     ) VALUES (?, ?, ?, ?, 'month', 1, ?, 'EGP', ?, 7, 'proportional', ?, ?, 'fixture', ?, 1)`,
  )
    .bind(
      HP_V1_ONLY_OFFER_ID,
      HP_V1_ONLY_VERSION,
      PLAN_ID,
      PLAN_VERSION,
      HP_V1_ONLY_PRICE_MINOR,
      ALLOWANCE_CREDITS,
      JSON.stringify({
        en: {
          name: "Clinic Pro Monthly (legacy price)",
          summary: "Earlier monthly price",
        },
      }),
      expectations.terms.version,
      "fixture-assertion-hp-v1",
    )
    .run();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO offer_event (
       offer_id, kind, version, actor, at, contract_version
     ) VALUES (?, 'published', ?, 'fixture', '2026-02-01T00:00:00.000Z', 1)`,
  )
    .bind(HP_V1_ONLY_OFFER_ID, HP_V1_ONLY_VERSION)
    .run();
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

async function grantOutcomeResult(grantId: string): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT result FROM grant_outcome WHERE grant_id = ?`,
  )
    .bind(grantId)
    .first<{ result: string }>();
  return row?.result ?? null;
}

async function operatorActionCount(): Promise<number> {
  return tableCount("operator_action");
}

async function latestOperatorActionResult(): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT result FROM operator_action ORDER BY rowid DESC LIMIT 1`,
  ).first<{ result: string }>();
  return row?.result ?? null;
}

beforeEach(async () => {
  await resetCrossWorkerHarness();
  await setupCrossWorkerHarness();
  await ensureMigrations();
  await scriptPaymobStub("ok");
  await setClock("2026-06-01T12:00:00.000Z");
});

describe("hp-actions cross-worker", () => {
  it("E2E-P4.7-03 HP publish refusals for missing assertion, mismatch, and stale issued_at", async () => {
    const expectations = await setupHpHarness();
    const hp = await ensureActiveHpCredential();
    const controlAuditBefore = await platformControlAuditCountForActor(
      VENDOR_OPERATOR_EMAIL,
    );
    const operatorActionBefore = await operatorActionCount();
    const publishPath = `/ops/offers/${expectations.offer_id}/publish`;
    const params = publishOfferParams(expectations, expectations.price_minor);

    const missingAssertionOperation = await buildHpOperation({
      op: "publish_offer",
      params,
      actorEmail: VENDOR_OPERATOR_EMAIL,
    });
    const missingAssertion = await opsHpFetch(publishPath, {
      accessJwt: hp.accessJwt,
      operation: missingAssertionOperation,
    });
    expect(missingAssertion.status).toBe(400);
    const missingBody = (await missingAssertion.json()) as Record<string, unknown>;
    expect(missingBody.code).toBe("assertion_required");
    expect(await operatorActionCount()).toBe(operatorActionBefore + 1);
    expect(await latestOperatorActionResult()).toBe("assertion_required");
    expect(
      await platformControlAuditCountForActor(VENDOR_OPERATOR_EMAIL),
    ).toBe(controlAuditBefore);

    const signedOperation = await buildHpOperation({
      op: "publish_offer",
      params,
      actorEmail: VENDOR_OPERATOR_EMAIL,
    });
    const mismatchedOperation = await buildHpOperation({
      op: "publish_offer",
      params: { ...params, price_minor: params.price_minor + 1 },
      actorEmail: VENDOR_OPERATOR_EMAIL,
    });
    const mismatchAssertion = await signHpOperation(hp.authenticator, signedOperation);
    const mismatch = await opsHpFetch(publishPath, {
      accessJwt: hp.accessJwt,
      operation: mismatchedOperation,
      assertion: mismatchAssertion,
    });
    expect(mismatch.status).toBe(400);
    const mismatchBody = (await mismatch.json()) as Record<string, unknown>;
    expect(mismatchBody.code).not.toBe("assertion_required");
    expect(mismatchBody.code).not.toBe("assertion_expired");
    expect(await operatorActionCount()).toBe(operatorActionBefore + 2);
    expect(
      await platformControlAuditCountForActor(VENDOR_OPERATOR_EMAIL),
    ).toBe(controlAuditBefore);

    const staleIssuedAt = "2026-06-01T11:54:00.000Z";
    const staleOperation = await buildHpOperation({
      op: "publish_offer",
      params,
      actorEmail: VENDOR_OPERATOR_EMAIL,
      issuedAt: staleIssuedAt,
    });
    const staleAssertion = await signHpOperation(hp.authenticator, staleOperation);
    const stale = await opsHpFetch(publishPath, {
      accessJwt: hp.accessJwt,
      operation: staleOperation,
      assertion: staleAssertion,
    });
    expect(stale.status).toBe(400);
    const staleBody = (await stale.json()) as Record<string, unknown>;
    expect(staleBody.code).toBe("assertion_expired");
    expect(await operatorActionCount()).toBe(operatorActionBefore + 3);
    expect(await latestOperatorActionResult()).toBe("assertion_expired");
    expect(
      await platformControlAuditCountForActor(VENDOR_OPERATOR_EMAIL),
    ).toBe(controlAuditBefore);
  });

  it("E2E-P4.7-07 revoked credential is refused with credential_not_active", async () => {
    const expectations = await setupHpHarness();
    const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const signerCredentialId = await seedActiveOperatorCredential(
      signerAuthenticator,
    );
    const hpAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const hpCredentialId = crypto.randomUUID();
    const accessJwt = await mintVendorAccessJwt();
    const registered = await registerOperatorCredentialWithSigner({
      credentialId: hpCredentialId,
      signerCredentialId,
      signerAuthenticator,
      attestationAuthenticator: hpAuthenticator,
      accessJwt,
    });
    expect(registered.result).toBe("ok");
    const row = JSON.parse(String(registered.detail)) as Record<string, unknown>;
    await setClock(String(row.activates_at));

    const revoked = await revokeOperatorCredentialOnPlatform({
      credentialId: hpCredentialId,
      signerCredentialId,
      signerAuthenticator,
      accessJwt,
    });
    expect(revoked.result).toBe("ok");

    const controlAuditBefore = await platformControlAuditCountForActor(
      VENDOR_OPERATOR_EMAIL,
    );
    const operatorActionBefore = await operatorActionCount();
    const operation = await buildHpOperation({
      op: "publish_offer",
      params: publishOfferParams(expectations, expectations.price_minor),
      actorEmail: VENDOR_OPERATOR_EMAIL,
    });
    const assertion = await signHpOperation(hpAuthenticator, operation);
    const response = await opsHpFetch(
      `/ops/offers/${expectations.offer_id}/publish`,
      {
        accessJwt,
        operation,
        assertion,
      },
    );
    expect(response.status).toBe(400);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.code).toBe("credential_not_active");
    expect(await operatorActionCount()).toBe(operatorActionBefore + 1);
    expect(await latestOperatorActionResult()).toBe("credential_not_active");
    expect(
      await platformControlAuditCountForActor(VENDOR_OPERATOR_EMAIL),
    ).toBe(controlAuditBefore);
  });

  it("E2E-P4.7-01 publish offer v2 keeps open v1 checkout at v1 price", async () => {
    const expectations = await setupHpHarness();
    await seedV1OnlyPublishOffer(expectations);

    const orgId = ORG_HP_01;
    await putBillingContact(orgId);
    await setupActivePlatformCoverage(orgId);
    const { checkoutId } = await postCheckout(
      orgId,
      { offerId: HP_V1_ONLY_OFFER_ID, version: HP_V1_ONLY_VERSION },
      expectations,
      "req-hp-01-open-v1",
    );

    const hp = await ensureActiveHpCredential();
    const publishOperation = await buildHpOperation({
      op: "publish_offer",
      params: publishOfferParams(expectations, HP_V2_PRICE_MINOR),
      actorEmail: VENDOR_OPERATOR_EMAIL,
    });
    const publishAssertion = await signHpOperation(
      hp.authenticator,
      publishOperation,
    );
    const publish = await opsHpFetch(
      `/ops/offers/${HP_V1_ONLY_OFFER_ID}/publish`,
      {
        accessJwt: hp.accessJwt,
        operation: publishOperation,
        assertion: publishAssertion,
      },
    );
    expect(publish.status).toBe(200);

    const offersResponse = await billingFetch("/v1/offers", {
      headers: { "Abo-Contract-Version": "1" },
    });
    expect(offersResponse.status).toBe(200);
    const offersBody = (await offersResponse.json()) as {
      offers: Array<{ offer_id: string; version: number; price_minor: number }>;
    };
    const listed = offersBody.offers.find(
      (offer) => offer.offer_id === HP_V1_ONLY_OFFER_ID,
    );
    expect(listed).toBeDefined();
    expect(listed!.version).toBe(2);
    expect(listed!.price_minor).toBe(HP_V2_PRICE_MINOR);

    const chargedPrice = await syncPaymobForCheckout(checkoutId);
    expect(chargedPrice).toBe(HP_V1_ONLY_PRICE_MINOR);
    const intake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      { txnId: 97701, amountMinor: chargedPrice },
    );
    expect(intake.status).toBe(200);
    await runScheduled("* * * * *");
    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();
    const grantId = await grantIdPaid(paymentId!);
    expect(await grantOutcomeResult(grantId)).toBe("applied");
  });

  it("E2E-P4.7-02 retire offer removes it from offers and blocks checkout", async () => {
    const expectations = await setupHpHarness();
    const orgId = ORG_HP_02;
    await putBillingContact(orgId);
    await setupActivePlatformCoverage(orgId);
    const platformTermsBefore = await platformPlanVersionSnapshot();

    const hp = await ensureActiveHpCredential();
    const retireOperation = await buildHpOperation({
      op: "retire_offer",
      params: {},
      actorEmail: VENDOR_OPERATOR_EMAIL,
    });
    const retireAssertion = await signHpOperation(
      hp.authenticator,
      retireOperation,
    );
    const retire = await opsHpFetch(
      `/ops/offers/${expectations.offer_id}/retire`,
      {
        accessJwt: hp.accessJwt,
        operation: retireOperation,
        assertion: retireAssertion,
      },
    );
    expect(retire.status).toBe(200);

    const offersResponse = await billingFetch("/v1/offers", {
      headers: { "Abo-Contract-Version": "1" },
    });
    expect(offersResponse.status).toBe(200);
    const offersBody = (await offersResponse.json()) as {
      offers: Array<{ offer_id: string }>;
    };
    expect(
      offersBody.offers.some((offer) => offer.offer_id === expectations.offer_id),
    ).toBe(false);

    const checkoutResponse = await billingFetch("/v1/checkouts", {
      method: "POST",
      headers: await administratorHeaders(orgId),
      body: JSON.stringify({
        client_request_id: "req-hp-02-retired-offer",
        offer_id: expectations.offer_id,
        offer_version: expectations.version,
        terms_version: expectations.terms.version,
      }),
    });
    expect(checkoutResponse.status).toBe(409);
    const checkoutBody = (await checkoutResponse.json()) as Record<string, unknown>;
    expect(checkoutBody.code).toBe("offer_unavailable");

    expect(await platformPlanVersionSnapshot()).toBe(platformTermsBefore);
  });
});
