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
import hpActionsMigrationSql from "../../migrations/0007_hp_actions.sql?raw";
import { loadOffersFixture } from "../../src/records/append";
import {
  applySql,
  billingFetch,
  mintBilling,
  newIssuer,
  opsFetch,
  pinIssuer,
  runScheduled,
  scriptPaymobInquiry,
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
  drainPlatformDurableObjects,
  settlePlatformDurableObjectAlarms,
  syncPlatformGrantLedger,
  syncPlatformGrantVoids,
} from "./cross-worker-harness";

const VENDOR_CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const ABO_CONTRACT_VERSION = 1;
const VENDOR_OPERATOR_EMAIL = "operator@vendor.test";
const PLAN_ID = "plan-pro";
const PLAN_VERSION = 1;
const ALLOWANCE_CREDITS = 100;

const ORG_HP_01 = "a4770001-0001-4001-8001-000000000001";
const ORG_HP_02 = "a4770002-0002-4002-8002-000000000002";
const ORG_HP_03 = "a4770003-0003-4003-8003-000000000003";
const ORG_HP_04 = "a4770004-0004-4004-8004-000000000004";
const ORG_HP_05 = "a4770005-0005-4005-8005-000000000005";

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
    hpActionsMigrationSql,
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

async function expectR2ObjectExists(key: string): Promise<void> {
  const object = await env.R2.get(key);
  expect(object).not.toBeNull();
  if (object !== null) {
    await object.text();
  }
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

async function paymentDisposition(paymentId: string): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT disposition FROM payment WHERE payment_id = ?`,
  )
    .bind(paymentId)
    .first<{ disposition: string }>();
  return row?.disposition ?? null;
}

async function paymentReleaseCount(paymentId?: string): Promise<number> {
  try {
    if (paymentId !== undefined) {
      const row = await env.DB.prepare(
        `SELECT COUNT(*) AS n FROM payment_release WHERE payment_id = ?`,
      )
        .bind(paymentId)
        .first<{ n: number }>();
      return row?.n ?? 0;
    }
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM payment_release`,
    ).first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function grantWorkCountForPayment(paymentId: string): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant' AND subject_id = ?`,
    )
      .bind(paymentId)
      .first<{ n: number }>();
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

async function createWithheldMismatchPayment(
  org: string,
  offer: { offerId: string; version: number },
  expectations: OffersFixtureExpectations,
  txnId: number,
): Promise<{ checkoutId: string; paymentId: string; amountMinor: number }> {
  await putBillingContact(org);
  await setupActivePlatformCoverage(org);
  const { checkoutId } = await postCheckout(
    org,
    offer,
    expectations,
    `req-hp-withheld-${txnId}`,
  );
  await scriptPaymobInquiry("amount_mismatch");
  const chargedPrice = await syncPaymobForCheckout(checkoutId);
  const intake = await postPaymobProcessedCallback(
    successFixture as PaymobCallbackFixture,
    { txnId, amountMinor: chargedPrice },
  );
  expect(intake.status).toBe(200);
  const paymentId = await paymentIdForCheckout(checkoutId);
  expect(paymentId).not.toBeNull();
  expect(await paymentDisposition(paymentId!)).toBe("withheld_mismatch");
  return {
    checkoutId,
    paymentId: paymentId!,
    amountMinor: chargedPrice,
  };
}

async function seedFullReversalForPayment(
  paymentId: string,
  amountMinor: number,
): Promise<void> {
  const reversalId = crypto.randomUUID();
  const parentTxn = await env.DB.prepare(
    `SELECT txn_id FROM paymob_txn
     WHERE payment_id = ? AND parent_txn_id IS NULL
     ORDER BY txn_id ASC LIMIT 1`,
  )
    .bind(paymentId)
    .first<{ txn_id: string }>();
  const parentRef = parentTxn?.txn_id ?? paymentId;
  const dedupeKey = `paymob:${parentRef}:reversal:${amountMinor}`;
  await env.DB.prepare(
    `INSERT INTO reversal (
       reversal_id, payment_id, reference, amount_minor, kind, is_full,
       source, cumulative_reversed_minor, detected_via, recorded_by,
       evidence_sha256, effect, dedupe_key
     ) VALUES (?, ?, ?, ?, 'chargeback', 1, 'operator', ?, 'manual', ?, 'evidence', 'hold', ?)`,
  )
    .bind(
      reversalId,
      paymentId,
      `REV-${reversalId.slice(0, 8)}`,
      amountMinor,
      amountMinor,
      VENDOR_OPERATOR_EMAIL,
      dedupeKey,
    )
    .run();
}

async function runGrantStep(orgId: string): Promise<void> {
  const { runDueGrantWork } = await import("../../src/work/grant");
  await runScheduled("* * * * *");
  await runDueGrantWork(env as never);
  await syncPlatformGrantLedger(orgId);
}

async function runDueGrantWorkUntilApplied(
  paymentId: string,
  orgId: string,
): Promise<void> {
  const grantId = await grantIdPaid(paymentId);
  for (let attempt = 0; attempt < 12; attempt += 1) {
    if ((await grantOutcomeResult(grantId)) === "applied") {
      return;
    }
    await runGrantStep(orgId);
  }
  expect(await grantOutcomeResult(grantId)).toBe("applied");
}

async function recentTermState(
  orgId: string,
  paymentId: string,
): Promise<string | null> {
  const coverage = await platformCall("getCoverage", {
    contract_version: VENDOR_CONTRACT_VERSION,
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
    `SELECT term_ids FROM grant_outcome WHERE grant_id = ?`,
  )
    .bind(grantId)
    .first<{ term_ids: string }>();
  if (!outcome?.term_ids) {
    return null;
  }
  const termIds = JSON.parse(outcome.term_ids) as string[];
  const termId = termIds[0];
  if (termId === undefined) {
    return null;
  }
  const match = (parsed.recent_terms ?? []).find(
    (term) => term.term_id === termId,
  );
  return match?.state ?? null;
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

async function putBillingContactVersion(
  org: string,
  clientRequestId: string,
  email: string,
): Promise<void> {
  const headers = await administratorHeaders(org);
  const response = await billingFetch("/v1/billing-contact", {
    method: "PUT",
    headers,
    body: JSON.stringify({
      client_request_id: clientRequestId,
      name: "Clinic Admin",
      email,
      phone: "+201001234567",
    }),
  });
  expect(response.status).toBe(200);
}

async function billingContactRows(
  orgId: string,
): Promise<
  Array<{
    version: number;
    name: string;
    email: string;
    phone: string;
    contact_sha256: string;
    erased_at: string | null;
    erased_by: string | null;
  }>
> {
  const rows = await env.DB.prepare(
    `SELECT version, name, email, phone, contact_sha256, erased_at, erased_by
     FROM billing_contact
     WHERE org_id = ?
     ORDER BY version ASC`,
  )
    .bind(orgId)
    .all<{
      version: number;
      name: string;
      email: string;
      phone: string;
      contact_sha256: string;
      erased_at: string | null;
      erased_by: string | null;
    }>();
  return rows.results ?? [];
}

async function tenantEvidenceR2Keys(orgId: string): Promise<string[]> {
  const keys = new Set<string>();
  const notifications = await env.DB.prepare(
    `SELECT n.body_r2_key
     FROM notification n
     WHERE n.body_r2_key != ''
       AND (
         n.checkout_id IN (SELECT checkout_id FROM checkout WHERE org_id = ?)
         OR n.body_sha256 IN (
           SELECT evidence_sha256 FROM payment
           WHERE org_id = ? AND evidence_sha256 != ''
         )
       )`,
  )
    .bind(orgId, orgId)
    .all<{ body_r2_key: string }>();
  for (const row of notifications.results ?? []) {
    keys.add(row.body_r2_key);
  }
  const inquiryRows = await env.DB.prepare(
    `SELECT ir.raw_r2_key
     FROM inquiry_result ir
     WHERE ir.raw_r2_key != ''
       AND ir.subject IN (
         SELECT 'checkout:' || checkout_id FROM checkout WHERE org_id = ?
       )`,
  )
    .bind(orgId)
    .all<{ raw_r2_key: string }>();
  for (const row of inquiryRows.results ?? []) {
    keys.add(row.raw_r2_key);
  }
  return [...keys];
}

async function listLedgerExportKeys(): Promise<string[]> {
  const listed = await env.R2.list({ prefix: "ledger/" });
  return listed.objects.map((object) => object.key);
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
      headers: await administratorHeaders(orgId),
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
      headers: await administratorHeaders(orgId),
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

  it("E2E-P4.7-04 withheld release applies grant; fully reversed release is refused", async () => {
    const expectations = await setupHpHarness();
    const orgId = ORG_HP_03;
    const offer = { offerId: expectations.offer_id, version: expectations.version };
    const withheld = await createWithheldMismatchPayment(
      orgId,
      offer,
      expectations,
      97704,
    );
    expect(await paymentReleaseCount()).toBe(0);
    expect(await grantWorkCountForPayment(withheld.paymentId)).toBe(0);

    const hp = await ensureActiveHpCredential();
    const releaseOperation = await buildHpOperation({
      op: "release_payment",
      params: {},
      actorEmail: VENDOR_OPERATOR_EMAIL,
    });
    const releaseAssertion = await signHpOperation(
      hp.authenticator,
      releaseOperation,
    );
    const release = await opsHpFetch(
      `/ops/payments/${withheld.paymentId}/release`,
      {
        accessJwt: hp.accessJwt,
        operation: releaseOperation,
        assertion: releaseAssertion,
      },
    );
    expect(release.status).toBe(200);
    expect(await paymentReleaseCount(withheld.paymentId)).toBe(1);
    expect(await grantWorkCountForPayment(withheld.paymentId)).toBe(1);
    await runDueGrantWorkUntilApplied(withheld.paymentId, orgId);

    const reversed = await createWithheldMismatchPayment(
      orgId,
      offer,
      expectations,
      97705,
    );
    await seedFullReversalForPayment(reversed.paymentId, reversed.amountMinor);
    const releaseBefore = await paymentReleaseCount();
    const grantWorkBefore = await grantWorkCountForPayment(reversed.paymentId);
    const reversedOperation = await buildHpOperation({
      op: "release_payment",
      params: {},
      actorEmail: VENDOR_OPERATOR_EMAIL,
    });
    const reversedAssertion = await signHpOperation(
      hp.authenticator,
      reversedOperation,
    );
    const refused = await opsHpFetch(
      `/ops/payments/${reversed.paymentId}/release`,
      {
        accessJwt: hp.accessJwt,
        operation: reversedOperation,
        assertion: reversedAssertion,
      },
    );
    expect(refused.status).toBe(400);
    expect(await paymentReleaseCount()).toBe(releaseBefore);
    expect(await grantWorkCountForPayment(reversed.paymentId)).toBe(
      grantWorkBefore,
    );
  });

  it("E2E-P4.7-05 manual chargeback voids the active term and holds the queue", async () => {
    const expectations = await setupHpHarness();
    const orgId = ORG_HP_04;
    const offer = { offerId: expectations.offer_id, version: expectations.version };
    const firstTxnId = 97706;
    const secondTxnId = 97707;
    const hp = await ensureActiveHpCredential();
    await putBillingContact(orgId);
    await ensureGrantTenantBinding(orgId);
    const firstCheckout = await postCheckout(
      orgId,
      offer,
      expectations,
      `req-hp-cb-active-${firstTxnId}`,
    );
    const secondCheckout = await postCheckout(
      orgId,
      offer,
      expectations,
      `req-hp-cb-queued-${secondTxnId}`,
    );
    const firstCharged = await syncPaymobForCheckout(firstCheckout.checkoutId);
    await scriptPaymobInquiry("bound_success");
    await postPaymobProcessedCallback(successFixture as PaymobCallbackFixture, {
      txnId: firstTxnId,
      amountMinor: firstCharged,
    });
    await runDueGrantWorkUntilApplied(
      (await paymentIdForCheckout(firstCheckout.checkoutId))!,
      orgId,
    );
    const subscriptionAfterFirst = await getSubscriptionBody(orgId);
    expect(subscriptionAfterFirst.snapshot?.state).toBe("active");
    const secondCharged = await syncPaymobForCheckout(secondCheckout.checkoutId);
    await scriptPaymobInquiry("bound_success");
    await postPaymobProcessedCallback(successFixture as PaymobCallbackFixture, {
      txnId: secondTxnId,
      connectingIp: `203.0.113.${secondTxnId % 200}`,
      amountMinor: secondCharged,
    });
    await runDueGrantWorkUntilApplied(
      (await paymentIdForCheckout(secondCheckout.checkoutId))!,
      orgId,
    );
    const activePaymentId = await paymentIdForCheckout(firstCheckout.checkoutId);
    expect(activePaymentId).not.toBeNull();
    const subscriptionBefore = await getSubscriptionBody(orgId);
    expect((subscriptionBefore.snapshot?.queued_count ?? 0) > 0).toBe(true);

    await syncPlatformGrantLedger(orgId);
    await settlePlatformDurableObjectAlarms();

    const chargebackOperation = await buildHpOperation({
      op: "manual_chargeback",
      params: {},
      actorEmail: VENDOR_OPERATOR_EMAIL,
    });
    const chargebackAssertion = await signHpOperation(
      hp.authenticator,
      chargebackOperation,
    );
    const chargeback = await opsHpFetch(
      `/ops/payments/${activePaymentId}/chargeback`,
      {
        accessJwt: hp.accessJwt,
        operation: chargebackOperation,
        assertion: chargebackAssertion,
      },
    );
    expect(chargeback.status).toBe(200);

    const reversal = await env.DB.prepare(
      `SELECT source, detected_via, kind, is_full, recorded_by, effect
       FROM reversal WHERE payment_id = ?`,
    )
      .bind(activePaymentId)
      .first<{
        source: string;
        detected_via: string;
        kind: string;
        is_full: number;
        recorded_by: string;
        effect: string;
      }>();
    expect(reversal?.source).toBe("operator");
    expect(reversal?.detected_via).toBe("manual");
    expect(reversal?.kind).toBe("chargeback");
    expect(reversal?.is_full).toBe(1);
    expect(reversal?.recorded_by).toBe(VENDOR_OPERATOR_EMAIL);
    expect(reversal?.effect).toBe("end_current");

    await setClock(
      new Date(Date.parse(await currentHarnessClockIso()) + 60_000).toISOString(),
    );
    await runScheduled("* * * * *");
    await syncPlatformGrantVoids();
    await settlePlatformDurableObjectAlarms();
    const grantId = await grantIdPaid(activePaymentId!);
    expect(await platformGrantVoidCount(grantId)).toBe(1);
    expect(await alertCountByCode("AL-06")).toBe(1);
    expect(await recentTermState(orgId, activePaymentId!)).toBe("ended");
    const subscription = await getSubscriptionBody(orgId);
    expect((subscription.snapshot?.held_count ?? 0) > 0).toBe(true);
    expect(subscription.notices ?? []).toContain("terms_held");
    await drainPlatformDurableObjects();
    await settlePlatformDurableObjectAlarms();
  });

  it("E2E-P4.7-06 erasure blanks contact versions and blocks checkout", async () => {
    const expectations = await setupHpHarness();
    const orgId = ORG_HP_05;
    const offer = { offerId: expectations.offer_id, version: expectations.version };
    await putBillingContactVersion(orgId, "req-hp-erase-v1", "erase-v1@clinic.test");
    await putBillingContactVersion(orgId, "req-hp-erase-v2", "erase-v2@clinic.test");
    const contactsBefore = await billingContactRows(orgId);
    expect(contactsBefore.length).toBeGreaterThanOrEqual(2);
    const contactHashes = contactsBefore.map((row) => row.contact_sha256);
    const ledgerBefore = await listLedgerExportKeys();

    await setupActivePlatformCoverage(orgId);
    const { checkoutId } = await postCheckout(
      orgId,
      offer,
      expectations,
      "req-hp-erase-paid",
    );
    const chargedPrice = await syncPaymobForCheckout(checkoutId);
    await scriptPaymobInquiry("bound_success");
    const intake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      {
        txnId: 97708,
        connectingIp: "203.0.113.108",
        amountMinor: chargedPrice,
      },
    );
    expect(intake.status).toBe(200);
    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();
    await runDueGrantWorkUntilApplied(paymentId!, orgId);
    const evidenceKeys = await tenantEvidenceR2Keys(orgId);
    expect(evidenceKeys.length).toBeGreaterThan(0);
    for (const key of evidenceKeys) {
      await expectR2ObjectExists(key);
    }

    const hp = await ensureActiveHpCredential();
    const eraseOperation = await buildHpOperation({
      op: "erase_contact",
      params: {},
      actorEmail: VENDOR_OPERATOR_EMAIL,
    });
    const eraseAssertion = await signHpOperation(hp.authenticator, eraseOperation);
    const erase = await opsHpFetch(`/ops/orgs/${orgId}/erase-contact`, {
      accessJwt: hp.accessJwt,
      operation: eraseOperation,
      assertion: eraseAssertion,
    });
    expect(erase.status).toBe(200);

    const contactsAfter = await billingContactRows(orgId);
    expect(contactsAfter.length).toBe(contactsBefore.length);
    for (const row of contactsAfter) {
      expect(row.name).toBe("");
      expect(row.email).toBe("");
      expect(row.phone).toBe("");
      expect(row.erased_at).not.toBeNull();
      expect(row.erased_by).toBe(VENDOR_OPERATOR_EMAIL);
    }
    expect(contactsAfter.map((row) => row.contact_sha256)).toEqual(contactHashes);
    for (const key of evidenceKeys) {
      expect(await env.R2.get(key)).toBeNull();
    }
    const ledgerAfter = await listLedgerExportKeys();
    expect(ledgerAfter).toEqual(ledgerBefore);
    for (const key of ledgerAfter) {
      await expectR2ObjectExists(key);
    }

    const checkoutResponse = await billingFetch("/v1/checkouts", {
      method: "POST",
      headers: await administratorHeaders(orgId),
      body: JSON.stringify({
        client_request_id: "req-hp-erase-checkout",
        offer_id: expectations.offer_id,
        offer_version: expectations.version,
        terms_version: expectations.terms.version,
      }),
    });
    expect(checkoutResponse.status).toBe(409);
    const checkoutBody = (await checkoutResponse.json()) as Record<string, unknown>;
    expect(checkoutBody.code).toBe("billing_contact_required");

    expect(paymentId.length).toBeGreaterThan(0);
    await drainPlatformDurableObjects();
    await settlePlatformDurableObjectAlarms();
  });
});
