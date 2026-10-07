/**
 * P4.8 — console relays: complimentary grants, adjustments, voids, suspension,
 * deletion and the transfer saga (H-XW), E2E-P4.8-01 through E2E-P4.8-08.
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
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
import { loadOffersFixture } from "../../src/records/append";
import {
  applySql,
  billingFetch,
  mintAi,
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
const ALLOWANCE_CREDITS = 100;
const CAPABILITY_ID = "clinic.visit_summary";
const CAPABILITY_VERSION = "1.0.0";
const POLICY_ID = "standard";
const POLICY_VERSION = "1";
const GATEWAY_ORIGIN = "https://ai-gateway.test";

/** Fixture trial length inside the default ceiling (not a product default). */
const TRIAL_DAY_COUNT = 14;

const ORG_CR_01 = "a4880001-0001-4001-8001-000000000001";
const ORG_CR_02 = "a4880002-0002-4002-8002-000000000002";
const ORG_CR_03 = "a4880003-0003-4003-8003-000000000003";
const ORG_CR_06 = "a4880006-0006-4006-8006-000000000006";
const ORG_CR_04 = "a4880004-0004-4004-8004-000000000004";
const ORG_CR_05 = "a4880005-0005-4005-8005-000000000005";
const ORG_CR_07 = "a4880007-0007-4007-8007-000000000007";
const ORG_CR_08 = "a4880008-0008-4008-8008-000000000008";

const VOID_LIST_WINDOW = {
  applied_from: "2026-06-01T00:00:00.000Z",
  applied_to: "2026-06-30T23:59:59.999Z",
};

type OffersFixtureExpectations = {
  offer_id: string;
  version: number;
  price_minor: number;
  terms: { version: number; text: string };
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
    PLATFORM_HTTP: Fetcher;
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

let clinicIssuer: Awaited<ReturnType<typeof newIssuer>> | null = null;

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
  recordedAt?: string,
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
        recorded_at: recordedAt ?? new Date().toISOString(),
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
  const existing = await env.PLATFORM_DB.prepare(
    `SELECT status, content_pointer FROM routing_policy
     WHERE policy_id = ? AND version = ?`,
  )
    .bind(POLICY_ID, POLICY_VERSION)
    .first<{ status: string; content_pointer: string | null }>();

  if (existing?.status === "active") {
    await ensureRoutingPolicyDocumentInR2(
      existing.content_pointer ?? contentPointer,
      document,
    );
    return;
  }

  const accessJwt = await mintHarnessAccessJwt();
  if (existing?.status === "published") {
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
      await ensureRoutingPolicyDocumentInR2(contentPointer, document);
      return;
    }
  }

  const published = await platformCall(
    "publishRoutingPolicy",
    {
      contract_version: CONTRACT_VERSION,
      document,
    },
    { accessJwt },
  );
  if (published.result === "ok" || published.error === "already_published") {
    const promoted = await platformCall(
      "promoteRoutingPolicy",
      {
        contract_version: CONTRACT_VERSION,
        policy_id: POLICY_ID,
        version: POLICY_VERSION,
      },
      { accessJwt },
    );
    if (
      promoted.result === "ok" ||
      promoted.error === "illegal_policy_transition"
    ) {
      await ensureRoutingPolicyDocumentInR2(contentPointer, document);
      return;
    }
  }

  const now = "2026-06-01T12:00:00.000Z";
  await ensureRoutingPolicyDocumentInR2(contentPointer, document);
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO routing_policy (
       policy_id, version, content_pointer, active_from, activated_by, status
     ) VALUES (?, ?, ?, ?, ?, 'active')`,
  )
    .bind(POLICY_ID, POLICY_VERSION, contentPointer, now, VENDOR_OPERATOR_EMAIL)
    .run();
}

async function setupConsoleRelaysHarness(): Promise<OffersFixtureExpectations> {
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
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      credential_id: input.credentialId,
      attestation: input.attestation,
      signer_credential_id: input.signerCredentialId,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: input.issuedAt,
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
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
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      credential_id: input.credentialId,
      signer_credential_id: input.signerCredentialId,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: input.issuedAt,
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
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
      contract_version: CONTRACT_VERSION,
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
    contract_version: CONTRACT_VERSION,
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
  kind?: "term" | "term_adjustment";
  count?: number;
  adjustment?: Record<string, unknown>;
  ceilingOverride?: Record<string, unknown>;
}): Promise<Record<string, unknown>> {
  const ref = input.actionId;
  const contentSha256 = await sha256Hex(new TextEncoder().encode(ref));
  const envelope: Record<string, unknown> = {
    contract_version: CONTRACT_VERSION,
    grant_id: await grantIdComp(input.actionId),
    org_id: input.orgId,
    kind: input.kind ?? "term",
    placement: "queue",
    source: {
      kind: "complimentary",
      ref,
      operator_email: VENDOR_OPERATOR_EMAIL,
      reason: "console relay test",
    },
    plan: { plan_id: PLAN_ID, plan_version: PLAN_VERSION },
    duration: { unit: "day", count: input.count ?? 14 },
    allowance_credits: ALLOWANCE_CREDITS,
    grace: { days: 7, cap_rule: "proportional" },
    evidence: {
      content_sha256: contentSha256,
      approvals: [{ credential_id: "cred-001", assertion: "stub" }],
    },
  };
  if (input.ceilingOverride !== undefined) {
    envelope.ceiling_override = input.ceilingOverride;
    envelope.evidence = {
      content_sha256: contentSha256,
      approvals: [
        { credential_id: "cred-001", assertion: "stub" },
        { credential_id: "cred-002", assertion: "stub" },
      ],
    };
  }
  if (input.adjustment !== undefined) {
    envelope.adjustment = input.adjustment;
  }
  return envelope;
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

async function operationForCeilingOverride(input: {
  accessJwt: string;
  envelope: Record<string, unknown>;
}): Promise<HpOperation> {
  return {
    op: "ceiling_override",
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

async function encodeCeilingOverrideAssertion(input: {
  envelope: Record<string, unknown>;
  accessJwt: string;
  authenticator: SoftwareAuthenticator;
}): Promise<{
  assertion: Record<string, string>;
  operation: HpOperation;
}> {
  const operation = await operationForCeilingOverride({
    accessJwt: input.accessJwt,
    envelope: input.envelope,
  });
  const assertion = await signHpOperation(input.authenticator, operation);
  return { assertion, operation };
}

async function opsComplimentaryGrantRelay(input: {
  orgId: string;
  accessJwt: string;
  hpCredential: ActiveHpCredential;
  actionId?: string;
  kind?: "term" | "term_adjustment";
  count?: number;
  adjustment?: Record<string, unknown>;
  ceilingOverride?: Record<string, unknown>;
  ceilingOverrideOperation?: HpOperation;
}): Promise<{ response: Response; actionId: string }> {
  const actionId = input.actionId ?? crypto.randomUUID();
  const envelope = await buildComplimentaryEnvelope({
    orgId: input.orgId,
    actionId,
    kind: input.kind,
    count: input.count,
    adjustment: input.adjustment,
    ceilingOverride: input.ceilingOverride,
  });
  const operation = await operationForHpGrant({
    accessJwt: input.accessJwt,
    envelope,
  });
  const assertion = await signHpOperation(
    input.hpCredential.authenticator,
    operation,
  );
  const body: Record<string, unknown> = {
    action_id: actionId,
    envelope,
    operation,
    assertion,
    signer_credential_id: input.hpCredential.credentialId,
  };
  if (input.ceilingOverrideOperation !== undefined) {
    body.ceiling_override_operation = input.ceilingOverrideOperation;
  }
  const response = await opsFetch(
    `/ops/orgs/${input.orgId}/complimentary-grant`,
    {
      method: "POST",
      headers: await opsHeaders(input.accessJwt),
      body: JSON.stringify(body),
    },
  );
  return { response, actionId };
}

async function platformAlertCount(code: string): Promise<number> {
  const row = await env.PLATFORM_DB.prepare(
    `SELECT COUNT(*) AS n FROM platform_alert WHERE code = ?`,
  )
    .bind(code)
    .first<{ n: number }>();
  return row?.n ?? 0;
}

async function operatorActionRow(
  actionId: string,
): Promise<{ action_id: string; result: string } | null> {
  return env.DB.prepare(
    `SELECT action_id, result FROM operator_action WHERE action_id = ?`,
  )
    .bind(actionId)
    .first<{ action_id: string; result: string }>();
}

async function grantRequestForAction(
  actionId: string,
): Promise<{ grant_id: string; source_ref: string } | null> {
  return env.DB.prepare(
    `SELECT grant_id, source_ref FROM grant_request WHERE source_ref = ?`,
  )
    .bind(actionId)
    .first<{ grant_id: string; source_ref: string }>();
}

async function grantOutcomeResult(grantId: string): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT result FROM grant_outcome WHERE grant_id = ?`,
  )
    .bind(grantId)
    .first<{ result: string }>();
  return row?.result ?? null;
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

async function ensureCoverageMirrorForOrg(orgId: string): Promise<void> {
  const binding = await env.PLATFORM_DB.prepare(
    `SELECT installation_id, epoch FROM tenant_binding
     WHERE org_id = ? AND status = 'active'`,
  )
    .bind(orgId)
    .first<{ installation_id: string; epoch: number }>();
  if (binding === null) {
    return;
  }

  const coverage = await platformCall("getCoverage", {
    contract_version: CONTRACT_VERSION,
    org_id: orgId,
  });
  if (coverage.result !== "ok") {
    return;
  }
  const parsed = JSON.parse(String(coverage.detail)) as {
    snapshot?: Record<string, unknown>;
  };
  const snapshot = parsed.snapshot;
  if (snapshot === undefined) {
    return;
  }

  const term = snapshot.term as Record<string, unknown> | undefined;
  const hardStopAt =
    typeof term?.ends_at === "string"
      ? term.ends_at
      : typeof term?.grace_ends_at === "string"
        ? term.grace_ends_at
        : null;

  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO coverage_mirror (
       installation_id, org_id, binding_epoch, clinic_seq, state, suspended,
       hard_stop_at, term_snapshot
     ) VALUES (?, ?, ?, ?, ?, 0, ?, ?)`,
  )
    .bind(
      binding.installation_id,
      orgId,
      binding.epoch,
      typeof snapshot.clinic_seq === "number" ? snapshot.clinic_seq : 1,
      typeof snapshot.state === "string" ? snapshot.state : "active",
      hardStopAt,
      JSON.stringify(snapshot),
    )
    .run();
}

async function platformHttpInvoke(org: string): Promise<Response> {
  await ensureCoverageMirrorForOrg(org);
  if (clinicIssuer === null) {
    await registerClinicIssuerKey();
  }
  const issuer = clinicIssuer!;
  await pinIssuer(issuer.kid, issuer.publicKey);
  const now = await harnessNowSeconds();
  const token = await mintAi(issuer, {
    sub: "clinician-sub",
    org,
    role: "clinician",
    branch: "branch-test",
    scopes: ["ai.visit_summary", "ai.access"],
    iat: now,
    exp: now + 300,
    jti: crypto.randomUUID(),
  });
  const nowIso = await currentHarnessClockIso();
  const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1/requests`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      "Aip-Contract-Version": "1",
      "x-idempotency-key": crypto.randomUUID(),
      "x-capability-version": CAPABILITY_VERSION,
    },
    body: JSON.stringify(visitSummaryInvokeBody(org, "branch-test", nowIso)),
  });
  try {
    await response.clone().text();
  } catch {
    // Best-effort drain so platform SSE work settles.
  }
  return response;
}

async function parsePlatformInvokeBody(
  response: Response,
): Promise<Record<string, unknown> | null> {
  const text = await response.text();
  if (text.length === 0) {
    return null;
  }
  try {
    return JSON.parse(text) as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function complimentaryGrantOnPlatform(input: {
  orgId: string;
  actionId: string;
  hpCredential: ActiveHpCredential;
  count?: number;
}): Promise<Record<string, unknown>> {
  const envelope = await buildComplimentaryEnvelope({
    orgId: input.orgId,
    actionId: input.actionId,
    count: input.count ?? 14,
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

async function operationForVoidGrant(input: {
  grantId: string;
  accessJwt: string;
  reason: string;
}): Promise<HpOperation> {
  return {
    op: "voidGrant",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      grant_id: input.grantId,
      reason: input.reason,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: await currentHarnessClockIso(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function opsVoidGrantRelay(input: {
  grantId: string;
  accessJwt: string;
  hpCredential: ActiveHpCredential;
  reason: string;
  actionId?: string;
}): Promise<Response> {
  const actionId = input.actionId ?? crypto.randomUUID();
  const operation = await operationForVoidGrant({
    grantId: input.grantId,
    accessJwt: input.accessJwt,
    reason: input.reason,
  });
  const assertion = await signHpOperation(
    input.hpCredential.authenticator,
    operation,
  );
  return opsFetch(`/ops/grants/${input.grantId}/void`, {
    method: "POST",
    headers: await opsHeaders(input.accessJwt),
    body: JSON.stringify({
      action_id: actionId,
      reason: input.reason,
      operation,
      assertion,
      signer_credential_id: input.hpCredential.credentialId,
    }),
  });
}

async function opsListGrantsForVoidRelay(input: {
  accessJwt: string;
  credentialId: string;
  window: { applied_from: string; applied_to: string };
  actionId?: string;
}): Promise<Response> {
  const actionId = input.actionId ?? crypto.randomUUID();
  return opsFetch("/ops/grants/list-for-void", {
    method: "POST",
    headers: await opsHeaders(input.accessJwt),
    body: JSON.stringify({
      action_id: actionId,
      credential_id: input.credentialId,
      window: input.window,
    }),
  });
}

async function opsSuspendRelay(input: {
  orgId: string;
  accessJwt: string;
  reason: string;
  actionId?: string;
}): Promise<Response> {
  const actionId = input.actionId ?? crypto.randomUUID();
  return opsFetch(`/ops/orgs/${input.orgId}/suspend`, {
    method: "POST",
    headers: await opsHeaders(input.accessJwt),
    body: JSON.stringify({
      action_id: actionId,
      reason: input.reason,
    }),
  });
}

async function opsResumeRelay(input: {
  orgId: string;
  accessJwt: string;
  reason: string;
  actionId?: string;
}): Promise<Response> {
  const actionId = input.actionId ?? crypto.randomUUID();
  return opsFetch(`/ops/orgs/${input.orgId}/resume`, {
    method: "POST",
    headers: await opsHeaders(input.accessJwt),
    body: JSON.stringify({
      action_id: actionId,
      reason: input.reason,
    }),
  });
}

async function platformGrantVoided(grantId: string): Promise<boolean> {
  const row = await env.PLATFORM_DB.prepare(
    `SELECT 1 AS present FROM grant_void WHERE grant_id = ?`,
  )
    .bind(grantId)
    .first<{ present: number }>();
  return (row?.present ?? 0) > 0;
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
  reason: string;
}): Promise<HpOperation> {
  return {
    op: "beginTransfer",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      org_id: input.orgId,
      from_installation_id: input.fromInstallationId,
      reason: input.reason,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: await currentHarnessClockIso(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function operationForDeleteInstallation(input: {
  orgId: string;
  accessJwt: string;
  reason: string;
}): Promise<HpOperation> {
  return {
    op: "deleteInstallation",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      org_id: input.orgId,
      reason: input.reason,
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
  reason?: string;
  actionId?: string;
}): Promise<{ response: Response; actionId: string }> {
  const actionId = input.actionId ?? crypto.randomUUID();
  const reason = input.reason ?? "clinic relocation";
  const operation = await operationForBeginTransfer({
    orgId: input.orgId,
    fromInstallationId: input.fromInstallationId,
    accessJwt: input.accessJwt,
    reason,
  });
  const assertion = await signHpOperation(
    input.hpCredential.authenticator,
    operation,
  );
  const response = await opsFetch(`/ops/orgs/${input.orgId}/begin-transfer`, {
    method: "POST",
    headers: await opsHeaders(input.accessJwt),
    body: JSON.stringify({
      action_id: actionId,
      from_installation_id: input.fromInstallationId,
      reason,
      operation,
      assertion,
      signer_credential_id: input.hpCredential.credentialId,
    }),
  });
  return { response, actionId };
}

async function opsDeleteInstallationRelay(input: {
  orgId: string;
  accessJwt: string;
  hpCredential: ActiveHpCredential;
  reason?: string;
  actionId?: string;
}): Promise<Response> {
  const actionId = input.actionId ?? crypto.randomUUID();
  const reason = input.reason ?? "decommission";
  const operation = await operationForDeleteInstallation({
    orgId: input.orgId,
    accessJwt: input.accessJwt,
    reason,
  });
  const assertion = await signHpOperation(
    input.hpCredential.authenticator,
    operation,
  );
  return opsFetch(`/ops/orgs/${input.orgId}/delete-installation`, {
    method: "POST",
    headers: await opsHeaders(input.accessJwt),
    body: JSON.stringify({
      action_id: actionId,
      reason,
      operation,
      assertion,
      signer_credential_id: input.hpCredential.credentialId,
    }),
  });
}

async function transferStepWorkRow(
  transferId: string,
): Promise<{
  work_id: string;
  state: string;
  last_error: string | null;
  dedupe_key: string;
} | null> {
  return env.DB.prepare(
    `SELECT work_id, state, last_error, dedupe_key FROM work
     WHERE kind = 'transfer_step' AND subject_id = ?`,
  )
    .bind(transferId)
    .first<{
      work_id: string;
      state: string;
      last_error: string | null;
      dedupe_key: string;
    }>();
}

async function readTransferPackage(
  transferId: string,
): Promise<unknown[] | null> {
  const row = await env.PLATFORM_DB.prepare(
    `SELECT package FROM transfer WHERE transfer_id = ?`,
  )
    .bind(transferId)
    .first<{ package: string | null }>();
  if (row?.package === null || row?.package === undefined) {
    return null;
  }
  return JSON.parse(row.package) as unknown[];
}

async function grantRequestsForTransfer(
  transferId: string,
): Promise<Array<{ grant_id: string; source_kind: string; source_ref: string }>> {
  const rows = await env.DB.prepare(
    `SELECT grant_id, source_kind, source_ref FROM grant_request WHERE source_ref = ?`,
  )
    .bind(transferId)
    .all<{ grant_id: string; source_kind: string; source_ref: string }>();
  return rows.results ?? [];
}

async function opsClinicPage(
  orgId: string,
  accessJwt: string,
): Promise<Response> {
  return opsFetch(`/ops/clinics/${orgId}`, {
    headers: await opsHeaders(accessJwt),
  });
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

beforeEach(async () => {
  await setupCrossWorkerHarness();
  await resetCrossWorkerHarness();
  await ensureMigrations();
  await scriptPaymobStub("ok");
  await scriptPaymobInquiry("bound_success");
  await setClock("2026-06-01T12:00:00.000Z");
  clinicIssuer = null;
});

describe("console relays cross-worker", () => {
  it("E2E-P4.8-01 complimentary grant and term adjustment link operator_action to grant_request", async () => {
    const orgId = ORG_CR_01;
    await setupConsoleRelaysHarness();
    await setupActivePlatformCoverage(orgId);
    const hp = await ensureActiveHpCredential();

    const extensionActionId = crypto.randomUUID();
    const extension = await opsComplimentaryGrantRelay({
      orgId,
      accessJwt: hp.accessJwt,
      hpCredential: hp,
      actionId: extensionActionId,
      count: 14,
    });
    expect(extension.response.status).toBe(200);
    const extensionBody = (await extension.response.json()) as Record<
      string,
      unknown
    >;
    expect(extensionBody.result).toBe("applied");

    const adjustmentActionId = crypto.randomUUID();
    const adjustment = await opsComplimentaryGrantRelay({
      orgId,
      accessJwt: hp.accessJwt,
      hpCredential: hp,
      actionId: adjustmentActionId,
      kind: "term_adjustment",
      count: 1,
      adjustment: { extend_days: 14 },
    });
    expect(adjustment.response.status).toBe(200);
    const adjustmentBody = (await adjustment.response.json()) as Record<
      string,
      unknown
    >;
    expect(adjustmentBody.result).toBe("applied");

    await drainPlatformDurableObjects();
    expect(await platformAlertCount("AL-11")).toBeGreaterThan(0);

    const operatorRow = await operatorActionRow(extensionActionId);
    expect(operatorRow).not.toBeNull();
    expect(operatorRow!.result).toBe("applied");

    const grantRow = await grantRequestForAction(extensionActionId);
    expect(grantRow).not.toBeNull();
    expect(grantRow!.source_ref).toBe(extensionActionId);
    expect(grantRow!.grant_id).toBe(await grantIdComp(extensionActionId));

    const snapshot = await platformCoverageSnapshot(orgId);
    expect(snapshot?.queued_count).toBeGreaterThanOrEqual(1);
  });

  it("E2E-P4.8-02 ceiling override applies a 365-day complimentary grant after exceeds_ceiling", async () => {
    const orgId = ORG_CR_02;
    await setupConsoleRelaysHarness();
    await setupActivePlatformCoverage(orgId);
    const hp = await ensureActiveHpCredential();

    const actionId = crypto.randomUUID();
    const rejected = await opsComplimentaryGrantRelay({
      orgId,
      accessJwt: hp.accessJwt,
      hpCredential: hp,
      actionId,
      count: 365,
    });
    expect(rejected.response.status).toBe(200);
    const rejectedBody = (await rejected.response.json()) as Record<
      string,
      unknown
    >;
    expect(rejectedBody.result).toBe("rejected");
    expect(rejectedBody.code).toBe("exceeds_ceiling");

    const baseEnvelope = await buildComplimentaryEnvelope({
      orgId,
      actionId: crypto.randomUUID(),
      count: 365,
    });
    const overrideEncoded = await encodeCeilingOverrideAssertion({
      envelope: baseEnvelope,
      accessJwt: hp.accessJwt,
      authenticator: hp.authenticator,
    });
    const overrideActionId = crypto.randomUUID();
    const applied = await opsComplimentaryGrantRelay({
      orgId,
      accessJwt: hp.accessJwt,
      hpCredential: hp,
      actionId: overrideActionId,
      count: 365,
      ceilingOverride: overrideEncoded.assertion,
      ceilingOverrideOperation: overrideEncoded.operation,
    });
    expect(applied.response.status).toBe(200);
    const appliedBody = (await applied.response.json()) as Record<
      string,
      unknown
    >;
    expect(appliedBody.result).toBe("applied");

    await drainPlatformDurableObjects();
    expect(await platformAlertCount("AL-12")).toBeGreaterThan(0);
  });

  it("E2E-P4.8-03 trial complimentary grant then paid checkout queues the paid term", async () => {
    const orgId = ORG_CR_03;
    const expectations = await setupConsoleRelaysHarness();
    await ensureGrantTenantBinding(orgId);
    await putBillingContact(orgId);
    const hp = await ensureActiveHpCredential();

    const trialActionId = crypto.randomUUID();
    const trial = await opsComplimentaryGrantRelay({
      orgId,
      accessJwt: hp.accessJwt,
      hpCredential: hp,
      actionId: trialActionId,
      count: TRIAL_DAY_COUNT,
    });
    expect(trial.response.status).toBe(200);
    const trialBody = (await trial.response.json()) as Record<string, unknown>;
    expect(trialBody.result).toBe("applied");

    const trialGrantId = await grantIdComp(trialActionId);
    expect(await grantOutcomeResult(trialGrantId)).toBe("applied");

    const { checkoutId } = await postCheckout(
      orgId,
      expectations,
      "req-cr-03-paid",
    );
    const chargedPrice = await syncPaymobForCheckout(checkoutId);
    const intake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      { txnId: 94803, amountMinor: chargedPrice },
    );
    expect(intake.status).toBe(200);

    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();
    await runDueGrantWorkUntilApplied(paymentId!, orgId);
    await drainPlatformDurableObjects();

    const snapshot = await platformCoverageSnapshot(orgId);
    expect(snapshot?.state).toBe("active");
    expect(snapshot?.queued_count).toBeGreaterThanOrEqual(1);
  });

  it("E2E-P4.8-06 list-for-void and void end listed grants voided after credential revocation", async () => {
    const orgId = ORG_CR_06;
    await setupConsoleRelaysHarness();
    await setupActivePlatformCoverage(orgId);

    const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const signerCredentialId = await seedActiveOperatorCredential(
      signerAuthenticator,
    );
    const suspectAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const suspectCredentialId = crypto.randomUUID();
    const revokerAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const revokerCredentialId = crypto.randomUUID();
    const accessJwt = await mintVendorAccessJwt();

    const suspectRegistered = await registerOperatorCredentialWithSigner({
      credentialId: suspectCredentialId,
      signerCredentialId,
      signerAuthenticator,
      attestationAuthenticator: suspectAuthenticator,
      accessJwt,
    });
    expect(suspectRegistered.result).toBe("ok");
    const suspectActivatesAt = JSON.parse(
      String(suspectRegistered.detail),
    ) as Record<string, unknown>;
    await setClock(String(suspectActivatesAt.activates_at));
    const suspectHp: ActiveHpCredential = {
      credentialId: suspectCredentialId,
      authenticator: suspectAuthenticator,
      accessJwt,
    };

    const revokerRegistered = await registerOperatorCredentialWithSigner({
      credentialId: revokerCredentialId,
      signerCredentialId,
      signerAuthenticator,
      attestationAuthenticator: revokerAuthenticator,
      accessJwt,
    });
    expect(revokerRegistered.result).toBe("ok");
    const revokerActivatesAt = JSON.parse(
      String(revokerRegistered.detail),
    ) as Record<string, unknown>;
    await setClock(String(revokerActivatesAt.activates_at));
    const revokerHp: ActiveHpCredential = {
      credentialId: revokerCredentialId,
      authenticator: revokerAuthenticator,
      accessJwt,
    };

    const grantActionIds = [crypto.randomUUID(), crypto.randomUUID()];
    const grantIds: string[] = [];
    for (const actionId of grantActionIds) {
      const granted = await complimentaryGrantOnPlatform({
        orgId,
        actionId,
        hpCredential: suspectHp,
        count: 14,
      });
      expect(granted.result).toBe("applied");
      grantIds.push(await grantIdComp(actionId));
    }
    await syncPlatformGrantLedger(orgId);
    await drainPlatformDurableObjects();

    const revoked = await revokeOperatorCredentialOnPlatform({
      credentialId: suspectCredentialId,
      signerCredentialId,
      signerAuthenticator,
      accessJwt,
    });
    expect(revoked.result).toBe("ok");

    const listResponse = await opsListGrantsForVoidRelay({
      accessJwt,
      credentialId: suspectCredentialId,
      window: VOID_LIST_WINDOW,
    });
    expect(listResponse.status).toBe(200);
    const listBody = (await listResponse.json()) as Record<string, unknown>;
    expect(listBody.result).toBe("ok");
    const listed = JSON.parse(String(listBody.detail)) as Array<{
      grant_id: string;
    }>;
    expect(listed.length).toBeGreaterThan(0);

    for (const entry of listed) {
      const voidResponse = await opsVoidGrantRelay({
        grantId: entry.grant_id,
        accessJwt,
        hpCredential: revokerHp,
        reason: "SR-25 drill",
      });
      expect(voidResponse.status).toBe(200);
      const voidBody = (await voidResponse.json()) as Record<string, unknown>;
      expect(voidBody.result).toBe("applied");
    }

    await drainPlatformDurableObjects();
    for (const grantId of grantIds) {
      expect(await platformGrantVoided(grantId)).toBe(true);
    }
  });

  it("E2E-P4.8-07 suspend refuses admission and resume restores it", async () => {
    const orgId = ORG_CR_07;
    await setupConsoleRelaysHarness();
    await setupPromotedRoutingPolicy();
    await ensureGrantTenantBinding(orgId);
    const hp = await ensureActiveHpCredential();
    const coverageActionId = crypto.randomUUID();
    const coverageGrant = await complimentaryGrantOnPlatform({
      orgId,
      actionId: coverageActionId,
      hpCredential: hp,
      count: 14,
    });
    expect(coverageGrant.result).toBe("applied");
    await drainPlatformDurableObjects();

    const admittedBefore = await platformHttpInvoke(orgId);
    expect(admittedBefore.status).toBe(200);

    const suspend = await opsSuspendRelay({
      orgId,
      accessJwt: hp.accessJwt,
      reason: "billing dispute",
    });
    expect(suspend.status).toBe(200);
    const suspendBody = (await suspend.json()) as Record<string, unknown>;
    expect(suspendBody.result).toBe("ok");

    await drainPlatformDurableObjects();
    const refused = await platformHttpInvoke(orgId);
    expect(refused.status).toBe(403);
    const refusedBody = await parsePlatformInvokeBody(refused);
    expect(refusedBody?.code).toBe("suspended");

    const resume = await opsResumeRelay({
      orgId,
      accessJwt: hp.accessJwt,
      reason: "resolved",
    });
    expect(resume.status).toBe(200);
    const resumeBody = (await resume.json()) as Record<string, unknown>;
    expect(resumeBody.result).toBe("ok");

    await drainPlatformDurableObjects();
    const admittedAfter = await platformHttpInvoke(orgId);
    expect(admittedAfter.status).toBe(200);
  });

  it("E2E-P4.8-08 complimentary grant with assertion omitted is rejected by the platform", async () => {
    const orgId = ORG_CR_08;
    await setupConsoleRelaysHarness();
    await setupActivePlatformCoverage(orgId);
    const hp = await ensureActiveHpCredential();

    const actionId = crypto.randomUUID();
    const envelope = await buildComplimentaryEnvelope({
      orgId,
      actionId,
      count: 14,
    });
    const operation = await operationForHpGrant({
      accessJwt: hp.accessJwt,
      envelope,
    });
    const response = await opsFetch(
      `/ops/orgs/${orgId}/complimentary-grant`,
      {
        method: "POST",
        headers: await opsHeaders(hp.accessJwt),
        body: JSON.stringify({
          action_id: actionId,
          envelope,
          operation,
          signer_credential_id: hp.credentialId,
        }),
      },
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.result).toBe("rejected");

    const operatorRow = await operatorActionRow(actionId);
    expect(operatorRow).not.toBeNull();
    expect(operatorRow!.result).toBe("rejected");
  });

  it("E2E-P4.8-04 begin-transfer saga retries through transient to epoch 2", async () => {
    const orgId = ORG_CR_04;
    await setupConsoleRelaysHarness();
    await setupActivePlatformCoverage(orgId);
    const hp = await ensureActiveHpCredential();

    const fromInstallationId = await activeInstallationId(orgId);
    expect(fromInstallationId).not.toBeNull();

    const bindingBefore = await env.PLATFORM_DB.prepare(
      `SELECT epoch FROM tenant_binding
       WHERE org_id = ? AND status = 'active'`,
    )
      .bind(orgId)
      .first<{ epoch: number }>();
    expect(bindingBefore?.epoch).toBe(1);

    const begun = await opsBeginTransferRelay({
      orgId,
      fromInstallationId: fromInstallationId!,
      accessJwt: hp.accessJwt,
      hpCredential: hp,
    });
    expect(begun.response.status).toBe(200);
    const beginBody = (await begun.response.json()) as Record<string, unknown>;
    expect(beginBody.result).toBe("ok");
    const transferDetail = JSON.parse(String(beginBody.detail)) as {
      transfer_id: string;
    };
    const transferId = transferDetail.transfer_id;
    expect(transferId).toBeTruthy();

    const workRow = await transferStepWorkRow(transferId);
    expect(workRow).not.toBeNull();
    expect(workRow!.state).toBe("open");
    expect(workRow!.dedupe_key).toBe(`transfer_step:${transferId}`);

    await runScheduled("* * * * *");
    await drainPlatformDurableObjects();
    const afterFirst = await transferStepWorkRow(transferId);
    expect(afterFirst).not.toBeNull();
    expect(afterFirst!.last_error).toBe("awaiting_transfer_out");
    expect(afterFirst!.state).toBe("open");

    await runTransferSagaUntilDone(transferId);
    const doneRow = await transferStepWorkRow(transferId);
    expect(doneRow!.state).toBe("done");

    const clinicPage = await opsClinicPage(orgId, hp.accessJwt);
    expect(clinicPage.status).toBe(200);
    const clinicBody = (await clinicPage.json()) as Record<string, unknown>;
    expect(clinicBody.binding_epoch).toBe(2);

    const packageElements = await readTransferPackage(transferId);
    expect(packageElements).not.toBeNull();
    expect(Array.isArray(packageElements)).toBe(true);

    const transferGrants = await grantRequestsForTransfer(transferId);
    expect(transferGrants.length).toBe(packageElements!.length);
    for (let n = 0; n < transferGrants.length; n += 1) {
      const row = transferGrants[n]!;
      expect(row.source_kind).toBe("transfer");
      expect(row.source_ref).toBe(transferId);
      expect(row.grant_id).toBe(await grantIdTransfer(transferId, n));
    }
  });

  it("E2E-P4.8-05 delete-installation holds binding then transfer runs from held binding", async () => {
    const orgId = ORG_CR_05;
    await setupConsoleRelaysHarness();
    await setupActivePlatformCoverage(orgId);
    const hp = await ensureActiveHpCredential();

    const deleteResponse = await opsDeleteInstallationRelay({
      orgId,
      accessJwt: hp.accessJwt,
      hpCredential: hp,
    });
    expect(deleteResponse.status).toBe(200);
    const deleteBody = (await deleteResponse.json()) as Record<string, unknown>;
    expect(deleteBody.result).toBe("ok");
    const effects = JSON.parse(String(deleteBody.detail)) as {
      installation: { status: string };
      tenant_binding: { status: string; installation_id: string };
    };
    expect(effects.installation.status).toBe("deleted");
    expect(effects.tenant_binding.status).toBe("held_for_transfer");

    const heldInstallationId = effects.tenant_binding.installation_id;
    expect(heldInstallationId).toBeTruthy();

    const begun = await opsBeginTransferRelay({
      orgId,
      fromInstallationId: heldInstallationId,
      accessJwt: hp.accessJwt,
      hpCredential: hp,
    });
    expect(begun.response.status).toBe(200);
    const beginBody = (await begun.response.json()) as Record<string, unknown>;
    expect(beginBody.result).toBe("ok");
    const transferDetail = JSON.parse(String(beginBody.detail)) as {
      transfer_id: string;
    };
    const transferId = transferDetail.transfer_id;
    expect(transferId).toBeTruthy();

    const workRow = await transferStepWorkRow(transferId);
    expect(workRow).not.toBeNull();
    expect(workRow!.state).toBe("open");

    await runTransferSagaUntilDone(transferId);
    const doneRow = await transferStepWorkRow(transferId);
    expect(doneRow!.state).toBe("done");

    const clinicPage = await opsClinicPage(orgId, hp.accessJwt);
    expect(clinicPage.status).toBe(200);
    const clinicBody = (await clinicPage.json()) as Record<string, unknown>;
    expect(clinicBody.binding_epoch).toBe(2);
  });
});
