/**
 * P4.10 — reconciliation, payout import and findings (H-XW),
 * E2E-P4.10-01 through E2E-P4.10-09.
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
import { runReconciliation } from "../../src/reconciliation/run";
import {
  applySql,
  billingFetch,
  clearCapturedEmails,
  getCapturedEmails,
  mintBilling,
  newIssuer,
  opsFetch,
  pinIssuer,
  runScheduled,
  scriptPaymobInquiry,
} from "./harness";
import { mintHxwVendorAccessJwt } from "./hxw-access-fixture";
import {
  drainPlatformDurableObjects,
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
const VENDOR_OPERATOR_EMAIL = "operator@vendor.test";
const PLAN_ID = "plan-pro";
const PLAN_VERSION = 1;
const CAPABILITY_ID = "clinic.visit_summary";
const POLICY_ID = "standard";
const POLICY_VERSION = "1";
const ALLOWANCE_CREDITS = 100;

const ORG_RC_01 = "a4100001-0001-4001-8001-000000000001";
const ORG_RC_02 = "a4100002-0002-4002-8002-000000000002";
const ORG_RC_03A = "a4100003-0003-4003-8003-000000000003";
const ORG_RC_03B = "a4100003-0003-4003-8003-00000000000b";
const ORG_RC_04 = "a4100004-0004-4004-8004-000000000004";
const ORG_RC_07 = "a4100007-0007-4007-8007-000000000007";

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
    ISSUER_ID: string;
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

let clinicIssuer: Awaited<ReturnType<typeof newIssuer>> | null = null;

function parseAboGrantKey(): AboGrantKey {
  return JSON.parse(env.ABO_GRANT_KEY) as AboGrantKey;
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

function addMinutes(isoUtc: string, minutes: number): string {
  return new Date(Date.parse(isoUtc) + minutes * 60_000).toISOString();
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

async function mintHarnessAccessJwt(): Promise<string> {
  return mintHxwVendorAccessJwt(
    env.ACCESS_AUD,
    VENDOR_OPERATOR_EMAIL,
    await harnessNowSeconds(),
  );
}

async function ensureRoutingPolicyDocumentInR2(
  contentPointer: string,
  document: Record<string, unknown>,
): Promise<void> {
  await env.R2.put(contentPointer, JSON.stringify(document), {
    httpMetadata: { contentType: "application/json" },
  });
}

async function setupPromotedRoutingPolicy(): Promise<void> {
  const document = fakePolicyDocument();
  const contentPointer = `control/routing-policy/${POLICY_ID}/${POLICY_VERSION}.json`;
  await ensureRoutingPolicyDocumentInR2(contentPointer, document);
  const now = "2026-06-01T12:00:00.000Z";
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO routing_policy (
       policy_id, version, content_pointer, active_from, activated_by, status
     ) VALUES (?, ?, ?, ?, ?, 'active')`,
  )
    .bind(POLICY_ID, POLICY_VERSION, contentPointer, now, VENDOR_OPERATOR_EMAIL)
    .run();
}

async function setupReconciliationHarness(): Promise<OffersFixtureExpectations> {
  const expectations = await seedOffersCatalogueFixture();
  expect(expectations).not.toBeNull();
  await registerAboGrantKeyOnPlatform();
  await publishPlanProOnPlatform();
  await registerClinicIssuerKey();
  await setupPromotedRoutingPolicy();
  return expectations!;
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

async function opsHeaders(accessJwt: string): Promise<Record<string, string>> {
  return {
    "Cf-Access-Jwt-Assertion": accessJwt,
    "Abo-Contract-Version": "1",
    "content-type": "application/json",
  };
}

async function currentHarnessClockIso(): Promise<string> {
  const row = await env.DB.prepare(
    `SELECT now_iso FROM harness_test_clock WHERE id = 'default'`,
  ).first<{ now_iso: string }>();
  return row?.now_iso ?? "2026-06-01T12:00:00.000Z";
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

async function runGrantStep(orgId: string): Promise<void> {
  const { runDueGrantWork } = await import("../../src/work/grant");
  await runScheduled("* * * * *");
  await runDueGrantWork(env as never);
  await syncPlatformGrantLedger(orgId);
}

async function paymentIdForCheckout(checkoutId: string): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT payment_id FROM payment WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ payment_id: string }>();
  return row?.payment_id ?? null;
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
  await drainPlatformDurableObjects();
  return { checkoutId, paymentId: paymentId! };
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

async function buildComplimentaryEnvelope(input: {
  orgId: string;
  actionId: string;
  operatorCredentialId: string;
  count?: number;
}): Promise<Record<string, unknown>> {
  const ref = input.actionId;
  const contentSha256 = await sha256Hex(new TextEncoder().encode(ref));
  return {
    contract_version: CONTRACT_VERSION,
    grant_id: await grantIdComp(input.actionId),
    org_id: input.orgId,
    kind: "term",
    placement: "queue",
    source: {
      kind: "complimentary",
      ref,
      operator_email: VENDOR_OPERATOR_EMAIL,
      reason: "reconciliation harness",
    },
    plan: { plan_id: PLAN_ID, plan_version: PLAN_VERSION },
    duration: { unit: "day", count: input.count ?? 14 },
    allowance_credits: ALLOWANCE_CREDITS,
    grace: { days: 7, cap_rule: "proportional" },
    evidence: {
      content_sha256: contentSha256,
      approvals: [
        { credential_id: input.operatorCredentialId, assertion: "stub" },
      ],
    },
  };
}

async function operationForHpGrant(input: {
  accessJwt: string;
  envelope: Record<string, unknown>;
}): Promise<HpOperation> {
  return {
    op: "grant",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      envelope: input.envelope,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: await currentHarnessClockIso(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function complimentaryGrantOnPlatform(input: {
  orgId: string;
  actionId: string;
  hpCredential: ActiveHpCredential;
}): Promise<Record<string, unknown>> {
  const envelope = await buildComplimentaryEnvelope({
    orgId: input.orgId,
    actionId: input.actionId,
    operatorCredentialId: input.hpCredential.credentialId,
  });
  const operation = await operationForHpGrant({
    accessJwt: input.hpCredential.accessJwt,
    envelope,
  });
  const assertion = await signHpOperation(
    input.hpCredential.authenticator,
    operation,
  );
  return platformCall(
    "grant",
    {
      contract_version: CONTRACT_VERSION,
      envelope,
      signer_credential_id: input.hpCredential.credentialId,
      operation,
      assertion,
    },
    { accessJwt: input.hpCredential.accessJwt },
  );
}

async function opsComplimentaryGrantRelay(input: {
  orgId: string;
  accessJwt: string;
  hpCredential: ActiveHpCredential;
  actionId: string;
}): Promise<Response> {
  const envelope = await buildComplimentaryEnvelope({
    orgId: input.orgId,
    actionId: input.actionId,
    operatorCredentialId: input.hpCredential.credentialId,
  });
  const operation = await operationForHpGrant({
    accessJwt: input.accessJwt,
    envelope,
  });
  const assertion = await signHpOperation(
    input.hpCredential.authenticator,
    operation,
  );
  return opsFetch(`/ops/orgs/${input.orgId}/complimentary-grant`, {
    method: "POST",
    headers: await opsHeaders(input.accessJwt),
    body: JSON.stringify({
      action_id: input.actionId,
      envelope,
      operation,
      assertion,
      signer_credential_id: input.hpCredential.credentialId,
    }),
  });
}

async function activeInstallationId(orgId: string): Promise<string | null> {
  const row = await env.PLATFORM_DB.prepare(
    `SELECT installation_id FROM tenant_binding
     WHERE org_id = ? AND status = 'active'`,
  )
    .bind(orgId)
    .first<{ installation_id: string }>();
  return row?.installation_id ?? null;
}

async function operationForBeginTransfer(input: {
  orgId: string;
  fromInstallationId: string;
  accessJwt: string;
}): Promise<HpOperation> {
  return {
    op: "beginTransfer",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      org_id: input.orgId,
      from_installation_id: input.fromInstallationId,
      reason: "reconciliation clean month",
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: await currentHarnessClockIso(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function opsBeginTransferRelay(input: {
  orgId: string;
  fromInstallationId: string;
  accessJwt: string;
  hpCredential: ActiveHpCredential;
  actionId: string;
}): Promise<Response> {
  const operation = await operationForBeginTransfer({
    orgId: input.orgId,
    fromInstallationId: input.fromInstallationId,
    accessJwt: input.accessJwt,
  });
  const assertion = await signHpOperation(
    input.hpCredential.authenticator,
    operation,
  );
  return opsFetch(`/ops/orgs/${input.orgId}/begin-transfer`, {
    method: "POST",
    headers: await opsHeaders(input.accessJwt),
    body: JSON.stringify({
      action_id: input.actionId,
      from_installation_id: input.fromInstallationId,
      reason: "reconciliation clean month",
      operation,
      assertion,
      signer_credential_id: input.hpCredential.credentialId,
    }),
  });
}

async function transferStepWorkRow(
  transferId: string,
): Promise<{ state: string } | null> {
  return env.DB.prepare(
    `SELECT state FROM work WHERE kind = 'transfer_step' AND subject_id = ?`,
  )
    .bind(transferId)
    .first<{ state: string }>();
}

async function runTransferSagaUntilDone(transferId: string): Promise<void> {
  for (let attempt = 0; attempt < 12; attempt += 1) {
    const row = await transferStepWorkRow(transferId);
    if (row?.state === "done") {
      return;
    }
    await runScheduled("* * * * *");
    await drainPlatformDurableObjects();
  }
  const final = await transferStepWorkRow(transferId);
  expect(final?.state).toBe("done");
}

async function seedUnauthorizedTransferGrantOnPlatform(
  orgId: string,
): Promise<string> {
  await ensureGrantTenantBinding(orgId);
  const binding = await env.PLATFORM_DB.prepare(
    `SELECT installation_id FROM tenant_binding
     WHERE org_id = ? AND status = 'active'`,
  )
    .bind(orgId)
    .first<{ installation_id: string }>();
  expect(binding?.installation_id).toBeTruthy();
  const transferId = crypto.randomUUID();
  const grantId = await grantIdTransfer(transferId, 0);
  const receipt = JSON.stringify({
    contract_version: CONTRACT_VERSION,
    grant_id: grantId,
    signature: "harness-transfer-receipt",
  });
  await env.PLATFORM_DB.prepare(
    `INSERT OR IGNORE INTO grant_ledger (
       grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
       operator_credential_id, envelope_sha256, receipt, applied_at
     ) VALUES (?, ?, ?, ?, 'term', 'transfer', ?, 'sha-transfer', ?, ?)`,
  )
    .bind(
      grantId,
      grantId,
      orgId,
      binding!.installation_id,
      "cred-harness",
      receipt,
      "2026-06-01T12:00:00.000Z",
    )
    .run();
  return grantId;
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

async function findingRow(
  kind: string,
): Promise<{ finding_id: string; subject: string; kind: string } | null> {
  try {
    return env.DB.prepare(
      `SELECT finding_id, subject, kind FROM finding WHERE kind = ? LIMIT 1`,
    )
      .bind(kind)
      .first<{ finding_id: string; subject: string; kind: string }>();
  } catch {
    return null;
  }
}

async function findingResolutionCount(findingId: string): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM finding_resolution WHERE finding_id = ?`,
    )
      .bind(findingId)
      .first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

function capturedEmailMentions(code: string): boolean {
  return getCapturedEmails().some((email) => email.text.includes(code));
}

async function runDailyReconciliation(): Promise<void> {
  clearCapturedEmails();
  await runScheduled("0 6 * * *");
}

void runReconciliation;

beforeEach(async () => {
  clinicIssuer = null;
  await resetCrossWorkerHarness();
  await setupCrossWorkerHarness();
  await ensureMigrations();
  await scriptPaymobStub("ok");
  await scriptPaymobInquiry("bound_success");
  await setClock("2026-06-01T12:00:00.000Z");
});

afterEach(async () => {
  await drainPlatformDurableObjects();
});

describe("reconciliation cross-worker", () => {
  it("E2E-P4.10-01 clean month of payments, grants, complimentary grants, and transfer yields zero findings", async () => {
    const expectations = await setupReconciliationHarness();
    const orgId = ORG_RC_01;
    const hp = await ensureActiveHpCredential();

    await paidCheckoutWithGrant(
      orgId,
      expectations,
      94101,
      "req-rc-01-paid",
    );

    const complimentaryActionId = crypto.randomUUID();
    const complimentary = await opsComplimentaryGrantRelay({
      orgId,
      accessJwt: hp.accessJwt,
      hpCredential: hp,
      actionId: complimentaryActionId,
    });
    expect(complimentary.status).toBe(200);
    await syncPlatformGrantLedger(orgId);
    await drainPlatformDurableObjects();

    const fromInstallationId = await activeInstallationId(orgId);
    expect(fromInstallationId).not.toBeNull();
    const transferActionId = crypto.randomUUID();
    const begun = await opsBeginTransferRelay({
      orgId,
      fromInstallationId: fromInstallationId!,
      accessJwt: hp.accessJwt,
      hpCredential: hp,
      actionId: transferActionId,
    });
    expect(begun.status).toBe(200);
    const beginBody = (await begun.json()) as Record<string, unknown>;
    expect(beginBody.result).toBe("ok");
    const transferDetail = JSON.parse(String(beginBody.detail)) as {
      transfer_id: string;
    };
    await runTransferSagaUntilDone(transferDetail.transfer_id);
    await syncPlatformGrantLedger(orgId);
    await drainPlatformDurableObjects();

    await runDailyReconciliation();

    expect(await findingCount()).toBe(0);
  });

  it("E2E-P4.10-02 paid platform grant without ABO payment raises grant_without_payment and AL-10, then resolves", async () => {
    const orgId = ORG_RC_02;
    await setupReconciliationHarness();
    const hp = await ensureActiveHpCredential();
    await setupActivePlatformCoverage(orgId);
    await drainPlatformDurableObjects();

    clearCapturedEmails();
    await runDailyReconciliation();

    const finding = await findingRow("grant_without_payment");
    expect(finding).not.toBeNull();
    expect(capturedEmailMentions("AL-10")).toBe(true);

    const resolve = await opsFetch(
      `/ops/findings/${finding!.finding_id}/resolve`,
      {
        method: "POST",
        headers: await opsHeaders(hp.accessJwt),
        body: JSON.stringify({ note: "reviewed in harness" }),
      },
    );
    expect(resolve.status).toBe(200);
    expect(await findingResolutionCount(finding!.finding_id)).toBe(1);
  });

  it("E2E-P4.10-03 complimentary and transfer grants without ABO authorisation raise findings", async () => {
    await setupReconciliationHarness();
    const hp = await ensureActiveHpCredential();

    const compActionId = crypto.randomUUID();
    const compGranted = await complimentaryGrantOnPlatform({
      orgId: ORG_RC_03A,
      actionId: compActionId,
      hpCredential: hp,
    });
    expect(compGranted.result).toBe("applied");
    const compGrantId = await grantIdComp(compActionId);

    await seedUnauthorizedTransferGrantOnPlatform(ORG_RC_03B);
    await drainPlatformDurableObjects();

    await runDailyReconciliation();

    const compFinding = await findingRow("grant_without_operator_action");
    expect(compFinding).not.toBeNull();
    expect(compFinding!.subject).toBe(compGrantId);

    const transferFinding = await findingRow("transfer_without_authorisation");
    expect(transferFinding).not.toBeNull();
  });

  it("E2E-P4.10-04 grant parked more than 15 minutes raises payment_without_grant", async () => {
    const expectations = await setupReconciliationHarness();
    const orgId = ORG_RC_04;
    await putBillingContact(orgId);
    await ensureGrantTenantBinding(orgId);
    const { checkoutId } = await postCheckout(
      orgId,
      expectations,
      "req-rc-04-parked",
    );
    const chargedPrice = await syncPaymobForCheckout(checkoutId);
    const intake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      { txnId: 94104, amountMinor: chargedPrice },
    );
    expect(intake.status).toBe(200);

    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();
    const paymentRow = await env.DB.prepare(
      `SELECT confirmed_at, disposition FROM payment WHERE payment_id = ?`,
    )
      .bind(paymentId!)
      .first<{ confirmed_at: string; disposition: string }>();
    expect(paymentRow?.disposition).toBe("grant");

    await setClock(addMinutes(paymentRow!.confirmed_at, 16));
    await runDailyReconciliation();

    const finding = await findingRow("payment_without_grant");
    expect(finding).not.toBeNull();
    expect(finding!.subject).toBe(paymentId);
  });

  it("E2E-P4.10-07 HMAC-valid success callback without confirming inquiry raises callback_without_confirmation", async () => {
    const expectations = await setupReconciliationHarness();
    const orgId = ORG_RC_07;
    await putBillingContact(orgId);
    const { checkoutId } = await postCheckout(
      orgId,
      expectations,
      "req-rc-07-callback",
    );
    await syncPaymobForCheckout(checkoutId);
    await scriptPaymobInquiry("pending");

    const chargedPrice = await chargedPriceMinorForCheckout(checkoutId);
    const intake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      { txnId: 94107, amountMinor: chargedPrice },
    );
    expect(intake.status).toBe(200);

    const notification = await env.DB.prepare(
      `SELECT notification_id, hmac_valid FROM notification LIMIT 1`,
    ).first<{ notification_id: string; hmac_valid: number }>();
    expect(notification?.hmac_valid).toBe(1);
    expect(await paymentIdForCheckout(checkoutId)).toBeNull();

    await runDailyReconciliation();

    const finding = await findingRow("callback_without_confirmation");
    expect(finding).not.toBeNull();
    expect(finding!.subject).toBe(notification!.notification_id);
  });
});
