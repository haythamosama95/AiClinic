/**
 * P4.4 — grant pipeline E2E tests (H-XW + H-PAY), E2E-P4.4-01 through E2E-P4.4-04.
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import {
  createSoftwareAuthenticator,
  type SoftwareAuthenticator,
} from "vendor-contracts/testkit";
import offersFixture from "../../fixtures/offers.json";
import successFixture from "../fixtures/paymob/success.json";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import notifyWorkMigrationSql from "../../migrations/0003_notify_work.sql?raw";
import { loadOffersFixture } from "../../src/records/append";
import {
  applySql,
  billingFetch,
  mintAi,
  mintBilling,
  newIssuer,
  pinIssuer,
  runScheduled,
  scriptPaymobInquiry,
  setClock,
  setD1BatchThrows,
} from "./harness";
import {
  platformCall,
  resetCrossWorkerHarness,
  scriptPaymobStub,
  setupCrossWorkerHarness,
} from "./cross-worker-harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const PLAN_ID = "plan-pro";
const PLAN_VERSION = 1;
const CAPABILITY_ID = "clinic.visit_summary";
const CAPABILITY_VERSION = "1.0.0";
const POLICY_ID = "standard";
const POLICY_VERSION = "1";
const ALLOWANCE_CREDITS = 100;
const VENDOR_OPERATOR_EMAIL = "operator@vendor.test";
const GATEWAY_ORIGIN = "https://ai-gateway.test";

type AboGrantKey = {
  kid: string;
  pkcs8: string;
  public_key: string;
};

type PlatformPublicKey = {
  kid: string;
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

type OperatorBootstrap = {
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
};

declare module "cloudflare:test" {
  interface ProvidedEnv {
    PLATFORM_HTTP: Fetcher;
    ABO_GRANT_KEY: string;
    PLATFORM_PUBLIC_KEYS: string;
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

let operatorBootstrap: OperatorBootstrap | null = null;
let registeredIssuerKid: string | null = null;

function parseAboGrantKey(): AboGrantKey {
  return JSON.parse(env.ABO_GRANT_KEY) as AboGrantKey;
}

function parsePlatformPublicKeys(): PlatformPublicKey[] {
  return JSON.parse(env.PLATFORM_PUBLIC_KEYS) as PlatformPublicKey[];
}

function base64urlEncode(bytes: Uint8Array): string {
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
    authenticator_data: base64urlEncode(assertion.authenticatorData),
    client_data_json: base64urlEncode(assertion.clientDataJSON),
    signature: base64urlEncode(assertion.signature),
  };
}

function encodeVendorAttestation(attestation: {
  alg: "ES256" | "EdDSA";
  publicKey: Uint8Array;
}): { alg: "ES256" | "EdDSA"; public_key: string } {
  return {
    alg: attestation.alg,
    public_key: base64urlEncode(attestation.publicKey),
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

function visitSummaryInvokeBody(
  org: string,
  branch = "branch-test",
): Record<string, unknown> {
  return {
    capability_id: CAPABILITY_ID,
    capability_version: CAPABILITY_VERSION,
    user_intent: "Summarize the visit.",
    context: {
      org,
      branch,
      "visit.chief_complaint@v1": {
        visit_id: crypto.randomUUID(),
        complaint: "Headache for three days.",
        recorded_at: new Date().toISOString(),
      },
    },
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

async function ensureMigrations(): Promise<void> {
  try {
    await applySql(checkoutMigrationSql);
  } catch {
    // Migration not present yet.
  }
  try {
    await applySql(notifyWorkMigrationSql);
  } catch {
    // Migration not present yet.
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

async function ensureOperatorBootstrap(): Promise<OperatorBootstrap> {
  if (operatorBootstrap !== null) {
    return operatorBootstrap;
  }
  const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
  const credentialId = crypto.randomUUID();
  const attestation = encodeVendorAttestation(await signerAuthenticator.attest());
  const activatesAt = new Date(Date.now() - 60_000).toISOString();
  await env.PLATFORM_DB.prepare(
    `INSERT OR IGNORE INTO operator_credential
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
  operatorBootstrap = {
    signerCredentialId: credentialId,
    signerAuthenticator,
  };
  return operatorBootstrap;
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
  const { mintHxwVendorAccessJwt } = await import("./hxw-access-fixture");
  return mintHxwVendorAccessJwt(
    env.ACCESS_AUD,
    VENDOR_OPERATOR_EMAIL,
    await harnessNowSeconds(),
  );
}

async function setupPromotedRoutingPolicy(): Promise<void> {
  const existing = await env.PLATFORM_DB.prepare(
    `SELECT status FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(POLICY_ID, POLICY_VERSION)
    .first<{ status: string }>();
  if (existing?.status === "promoted") {
    return;
  }

  const accessJwt = await mintHarnessAccessJwt();
  const document = fakePolicyDocument();
  const published = await platformCall(
    "publishRoutingPolicy",
    {
      contract_version: CONTRACT_VERSION,
      document,
    },
    { accessJwt },
  );
  if (published.result === "ok") {
    const promoted = await platformCall(
      "promoteRoutingPolicy",
      {
        contract_version: CONTRACT_VERSION,
        policy_id: POLICY_ID,
        version: POLICY_VERSION,
      },
      { accessJwt },
    );
    if (promoted.result === "ok") {
      return;
    }
  }

  const now = "2026-06-01T12:00:00.000Z";
  const pointer = `routing/${POLICY_ID}/${POLICY_VERSION}.json`;
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO routing_policy (
       policy_id, version, content_pointer, active_from, activated_by, status
     ) VALUES (?, ?, ?, ?, ?, 'promoted')`,
  )
    .bind(POLICY_ID, POLICY_VERSION, pointer, now, VENDOR_OPERATOR_EMAIL)
    .run();
}

async function registerClinicIssuerKey(): Promise<void> {
  const issuer = await newIssuer();
  await pinIssuer(issuer.kid, issuer.publicKey);
  if (registeredIssuerKid === issuer.kid) {
    return;
  }
  const rawPublicKey = await crypto.subtle.exportKey("raw", issuer.publicKey);
  const publicKeyB64 = base64urlEncode(new Uint8Array(rawPublicKey));
  const notBefore = "2020-01-01T00:00:00.000Z";
  const notAfter = "2099-01-01T00:00:00.000Z";
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO issuer_key
       (kid, issuer, public_key, status, not_before, not_after, registered_by, assertion_sha256)
     VALUES (?, ?, ?, 'active', ?, ?, ?, 'harness')`,
  )
    .bind(issuer.kid, env.ISSUER_ID, publicKeyB64, notBefore, notAfter, VENDOR_OPERATOR_EMAIL)
    .run();
  registeredIssuerKid = issuer.kid;
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

async function postPaymobProcessedCallback(
  fixture: PaymobCallbackFixture,
  options?: { txnId?: number; connectingIp?: string },
): Promise<Response> {
  const bodyFixture =
    options?.txnId !== undefined
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

async function runGrantStep(): Promise<void> {
  await runScheduled("* * * * *");
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

async function paymentPaidAt(checkoutId: string): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT paid_at FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ paid_at: string }>();
    return row?.paid_at ?? null;
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

async function mintIssuerAiToken(org: string): Promise<string> {
  const issuer = await newIssuer();
  await pinIssuer(issuer.kid, issuer.publicKey);
  const now = Math.floor(Date.now() / 1000);
  return mintAi(issuer, {
    sub: "clinician-sub",
    org,
    role: "clinician",
    branch: "branch-test",
    scopes: ["ai.visit_summary", "ai.access"],
    iat: now,
    exp: now + 300,
    jti: crypto.randomUUID(),
  });
}

async function platformHttpInvoke(org: string): Promise<Response> {
  const token = await mintIssuerAiToken(org);
  return env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1/requests`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      "Aip-Contract-Version": "1",
      "x-idempotency-key": crypto.randomUUID(),
      "x-capability-version": CAPABILITY_VERSION,
    },
    body: JSON.stringify(visitSummaryInvokeBody(org)),
  });
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

async function retirePlanProOnPlatform(): Promise<void> {
  const boot = await ensureOperatorBootstrap();
  const accessJwt = await mintHarnessAccessJwt();
  const operation = {
    op: "retirePlanVersion",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: accessJwt,
      plan_id: PLAN_ID,
      version: PLAN_VERSION,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
  const assertion = encodeVendorAssertion(
    await boot.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const retired = await platformCall(
    "retirePlanVersion",
    {
      contract_version: CONTRACT_VERSION,
      plan_id: PLAN_ID,
      version: PLAN_VERSION,
      signer_credential_id: boot.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
  if (retired.result === "ok") {
    return;
  }
  await env.PLATFORM_DB.prepare(
    `UPDATE plan_version SET status = 'retired' WHERE plan_id = ? AND version = ?`,
  )
    .bind(PLAN_ID, PLAN_VERSION)
    .run();
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
    `req-grant-${org}-${offer.offerId}-${offer.version}-${txnId}`,
  );
  await scriptPaymobInquiry("bound_success");
  const intake = await postPaymobProcessedCallback(
    successFixture as PaymobCallbackFixture,
    { txnId, connectingIp: `203.0.113.${txnId % 200}` },
  );
  expect(intake.status).toBe(200);
  await runGrantStep();
  return checkout;
}

async function setupGrantHarness(): Promise<{
  expectations: OffersFixtureExpectations;
  offerVersions: Record<number, { offerId: string; version: number }>;
}> {
  const expectations = await seedOffersCatalogueFixture();
  expect(expectations).not.toBeNull();
  const offerVersions = await seedTermOfferVersions(expectations!);
  await registerAboGrantKeyOnPlatform();
  await publishPlanProOnPlatform();
  await registerClinicIssuerKey();
  await setupPromotedRoutingPolicy();
  return { expectations: expectations!, offerVersions };
}

beforeEach(async () => {
  operatorBootstrap = null;
  registeredIssuerKid = null;
  await resetCrossWorkerHarness();
  await setupCrossWorkerHarness();
  await ensureMigrations();
  await scriptPaymobStub("ok");
  await scriptPaymobInquiry("bound_success");
  await setClock("2026-06-01T12:00:00.000Z");
  parsePlatformPublicKeys();
});

describe("grant cross-worker", () => {
  it("E2E-P4.4-01 paid grant activates the term and completes an issuer request", async () => {
    const { expectations, offerVersions } = await setupGrantHarness();

    for (const termCount of [1, 3, 12] as const) {
      const org = `org-grant-01-${termCount}m`;
      const offer = offerVersions[termCount];
      const txnId = 94000 + termCount;
      const { checkoutId } = await paidCheckoutFlow(
        org,
        offer,
        expectations,
        txnId,
      );

      const snapshot = await platformCoverageSnapshot(org);
      expect(snapshot?.state).toBe("active");
      const term = snapshot?.term as Record<string, unknown> | undefined;
      expect(term?.allowance).toBe(ALLOWANCE_CREDITS);

      const invokeResponse = await platformHttpInvoke(org);
      expect(invokeResponse.status).toBe(200);

      const headers = await administratorHeaders(org);
      const checkoutRead = await billingFetch(`/v1/checkouts/${checkoutId}`, {
        headers,
      });
      expect(checkoutRead.status).toBe(200);
      const checkoutBody = (await checkoutRead.json()) as Record<string, unknown>;
      expect(checkoutBody.shown_state).toBe("Active");

      const paymentsRead = await billingFetch("/v1/payments", { headers });
      expect(paymentsRead.status).toBe(200);
      const paymentsBody = (await paymentsRead.json()) as {
        payments: Array<{ reference: string }>;
      };
      expect(paymentsBody.payments.length).toBeGreaterThan(0);
    }
  });

  it("E2E-P4.4-02 transient for 4 days then applied starts at activation", async () => {
    const { expectations, offerVersions } = await setupGrantHarness();
    const org = "org-grant-02-transient";
    const txnId = 94020;
    await putBillingContact(org);
    const { checkoutId } = await postCheckout(
      org,
      offerVersions[1],
      expectations,
      `req-grant-02-${txnId}`,
    );
    await postPaymobProcessedCallback(successFixture as PaymobCallbackFixture, {
      txnId,
    });
    await seedHeldForTransferBinding(org);

    let activationIso = "2026-06-01T12:15:00.000Z";
    await setClock(activationIso);
    await runGrantStep();
    expect(await grantOutcomeCount()).toBe(0);

    const paidAt = await paymentPaidAt(checkoutId);
    expect(paidAt).not.toBeNull();

    const fourDaysLater = new Date(
      Date.parse("2026-06-01T12:00:00.000Z") + 4 * 24 * 60 * 60 * 1000,
    ).toISOString();
    let cursor = Date.parse(activationIso);
    const endMs = Date.parse(fourDaysLater);
    let sawAl04 = false;
    while (cursor < endMs) {
      cursor += 15 * 60 * 1000;
      await setClock(new Date(cursor).toISOString());
      await runGrantStep();
      const paymentId = await paymentIdForCheckout(checkoutId);
      if (paymentId !== null) {
        expect(await grantWorkState(paymentId)).toBe("open");
      }
      if ((await alertCountByCode("AL-04")) > 0) {
        sawAl04 = true;
      }
      await runScheduled("0 * * * *");
    }
    expect(sawAl04).toBe(true);

    activationIso = new Date(cursor).toISOString();
    await activateTenantBinding(org);
    await setClock(activationIso);
    await runScheduled("0 * * * *");
    await runGrantStep();

    const snapshot = await platformCoverageSnapshot(org);
    expect(snapshot?.state).toBe("active");
    const term = snapshot?.term as { starts_at?: string } | undefined;
    expect(term?.starts_at).toBe(activationIso);
    expect(term?.starts_at).not.toBe(paidAt);
  });

  it("E2E-P4.4-03 rejected parks the grant row and raises AL-07", async () => {
    const { expectations, offerVersions } = await setupGrantHarness();
    await retirePlanProOnPlatform();

    const org = "org-grant-03-rejected";
    const txnId = 94030;
    const { checkoutId } = await paidCheckoutFlow(
      org,
      offerVersions[1],
      expectations,
      txnId,
    );
    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();

    expect(await grantWorkState(paymentId!)).toBe("parked");
    expect(await alertCountByCode("AL-07")).toBeGreaterThan(0);

    await runGrantStep();
    expect(await grantWorkState(paymentId!)).toBe("parked");
  });

  it("E2E-P4.4-04 lost outcome retries as already_applied with one term", async () => {
    const { expectations, offerVersions } = await setupGrantHarness();
    const org = "org-grant-04-lost";
    const txnId = 94040;
    await putBillingContact(org);
    const { checkoutId } = await postCheckout(
      org,
      offerVersions[1],
      expectations,
      `req-grant-04-${txnId}`,
    );
    await postPaymobProcessedCallback(successFixture as PaymobCallbackFixture, {
      txnId,
    });
    expect(await paymentIdForCheckout(checkoutId)).not.toBeNull();
    expect(await grantOutcomeCount()).toBe(0);

    setD1BatchThrows(true);
    await runGrantStep();
    expect(await grantOutcomeCount()).toBe(0);

    await runGrantStep();
    expect(await grantOutcomeCount()).toBe(1);

    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();
    const outcome = await env.DB.prepare(
      `SELECT result FROM grant_outcome go
       JOIN grant_request gr ON gr.grant_id = go.grant_id
       WHERE gr.source_ref = ?`,
    )
      .bind(paymentId)
      .first<{ result: string }>();
    expect(outcome?.result).toBe("already_applied");

    const snapshot = await platformCoverageSnapshot(org);
    expect(snapshot?.queued_count ?? 0).toBe(0);
    expect((snapshot?.term as { allowance?: number } | undefined)?.allowance).toBe(
      ALLOWANCE_CREDITS,
    );
  });
});
