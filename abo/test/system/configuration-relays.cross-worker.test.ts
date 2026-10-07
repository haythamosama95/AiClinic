/**
 * P4.9 — console configuration relays: registries and bootstrap (H-XW),
 * E2E-P4.9-01 through E2E-P4.9-07.
 */

import { env, SELF } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import {
  canonicalize,
  CHANNEL_VERSIONS,
  grantIdPaid,
  signCompactJws,
} from "vendor-contracts";
import {
  createAboGrantSigner,
  createIssuer,
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
  mintAi,
  mintBilling,
  newIssuer,
  opsFetch,
  pinIssuer,
  runScheduled,
  scriptPaymobInquiry,
} from "./harness";
import {
  drainPlatformDurableObjects,
  mintVendorAccessJwt,
  resetCrossWorkerHarness,
  scriptPaymobStub,
  setClock,
  setupActivePlatformCoverage,
  setupCrossWorkerHarness,
  syncPlatformGrantLedger,
} from "./cross-worker-harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const VENDOR_OPERATOR_EMAIL = "operator@vendor.test";
const CONFIG_CACHE_TTL_MS = 100;
const PLAN_ID = "plan-pro";
const PLAN_VERSION = 1;
const ALLOWANCE_CREDITS = 100;
const CAPABILITY_ID = "clinic.visit_summary";
const CAPABILITY_VERSION = "1.0.0";
const POLICY_ID = "standard";
const POLICY_VERSION = "1";
const GATEWAY_ORIGIN = "https://ai-gateway.test";

const ORG_CFG_03 = "a4890003-0003-4003-8003-000000000003";
const ORG_CFG_04 = "a4890004-0004-4004-8004-000000000004";

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

function addHours(isoUtc: string, hours: number): string {
  return new Date(Date.parse(isoUtc) + hours * 3_600_000).toISOString();
}

function addMs(isoUtc: string, ms: number): string {
  return new Date(Date.parse(isoUtc) + ms).toISOString();
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

async function registerAboGrantKeyOnPlatform(kid: string, publicKey: string): Promise<void> {
  const notBefore = "2020-01-01T00:00:00.000Z";
  const notAfter = "2099-01-01T00:00:00.000Z";
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO service_key
       (kid, service, public_key, status, not_before, not_after, registered_by, assertion_sha256)
     VALUES (?, 'abo', ?, 'active', ?, ?, ?, 'harness')`,
  )
    .bind(kid, publicKey, notBefore, notAfter, VENDOR_OPERATOR_EMAIL)
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
  const now = "2026-06-01T12:00:00.000Z";
  await env.R2.put(contentPointer, JSON.stringify(document), {
    httpMetadata: { contentType: "application/json" },
  });
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO routing_policy (
       policy_id, version, content_pointer, active_from, activated_by, status
     ) VALUES (?, ?, ?, ?, ?, 'active')`,
  )
    .bind(POLICY_ID, POLICY_VERSION, contentPointer, now, VENDOR_OPERATOR_EMAIL)
    .run();
}

async function setupConfigurationRelaysHarness(): Promise<OffersFixtureExpectations> {
  const expectations = await seedOffersCatalogueFixture();
  expect(expectations).not.toBeNull();
  const harnessKey = parseAboGrantKey();
  await registerAboGrantKeyOnPlatform(harnessKey.kid, harnessKey.public_key);
  await publishPlanProOnPlatform();
  await registerClinicIssuerKey();
  await setupPromotedRoutingPolicy();
  return expectations!;
}

async function clearOperatorCredentials(): Promise<void> {
  await env.PLATFORM_DB.prepare("DELETE FROM operator_credential").run();
  await env.PLATFORM_DB.prepare("DELETE FROM platform_alert").run();
}

async function currentHarnessClockIso(): Promise<string> {
  const row = await env.DB.prepare(
    `SELECT now_iso FROM harness_test_clock WHERE id = 'default'`,
  ).first<{ now_iso: string }>();
  return row?.now_iso ?? "2026-06-01T12:00:00.000Z";
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

async function opsHeaders(accessJwt: string): Promise<Record<string, string>> {
  return {
    "Cf-Access-Jwt-Assertion": accessJwt,
    "Abo-Contract-Version": "1",
    "content-type": "application/json",
  };
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

async function seedActiveHpCredential(): Promise<ActiveHpCredential> {
  const authenticator = await createSoftwareAuthenticator("EdDSA");
  const credentialId = await seedActiveOperatorCredential(authenticator);
  const accessJwt = await mintVendorAccessJwt();
  return {
    credentialId,
    authenticator,
    accessJwt,
  };
}

async function operationForRegisterIssuerKey(input: {
  kid: string;
  publicKey: string;
  notBefore: string;
  notAfter: string;
  accessJwt: string;
  issuedAt?: string;
}): Promise<HpOperation> {
  return {
    op: "registerIssuerKey",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      kid: input.kid,
      public_key: input.publicKey,
      not_before: input.notBefore,
      not_after: input.notAfter,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: input.issuedAt ?? (await currentHarnessClockIso()),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function operationForIssuerKidMethod(input: {
  op: "revokeIssuerKey" | "retireIssuerKey";
  kid: string;
  accessJwt: string;
  issuedAt?: string;
}): Promise<HpOperation> {
  return {
    op: input.op,
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      kid: input.kid,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: input.issuedAt ?? (await currentHarnessClockIso()),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function operationForRegisterServiceKey(input: {
  kid: string;
  publicKey: string;
  notBefore: string;
  notAfter: string;
  accessJwt: string;
  issuedAt?: string;
}): Promise<HpOperation> {
  return {
    op: "registerServiceKey",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      kid: input.kid,
      public_key: input.publicKey,
      not_before: input.notBefore,
      not_after: input.notAfter,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: input.issuedAt ?? (await currentHarnessClockIso()),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function operationForRevokeServiceKey(input: {
  kid: string;
  accessJwt: string;
  issuedAt?: string;
}): Promise<HpOperation> {
  return {
    op: "revokeServiceKey",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      kid: input.kid,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: input.issuedAt ?? (await currentHarnessClockIso()),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function opsRegisterIssuerKey(input: {
  kid: string;
  publicKey: string;
  notBefore: string;
  notAfter: string;
  hp: ActiveHpCredential;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  actionId?: string;
}): Promise<Response> {
  const operation = await operationForRegisterIssuerKey({
    kid: input.kid,
    publicKey: input.publicKey,
    notBefore: input.notBefore,
    notAfter: input.notAfter,
    accessJwt: input.hp.accessJwt,
  });
  const assertion = await signHpOperation(input.signerAuthenticator, operation);
  return opsFetch("/ops/issuer-keys", {
    method: "POST",
    headers: await opsHeaders(input.hp.accessJwt),
    body: JSON.stringify({
      action_id: input.actionId ?? crypto.randomUUID(),
      kid: input.kid,
      public_key: input.publicKey,
      not_before: input.notBefore,
      not_after: input.notAfter,
      operation,
      assertion,
      signer_credential_id: input.signerCredentialId,
    }),
  });
}

async function opsIssuerKidRelay(input: {
  method: "revokeIssuerKey" | "retireIssuerKey";
  kid: string;
  hp: ActiveHpCredential;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  actionId?: string;
}): Promise<Response> {
  const operation = await operationForIssuerKidMethod({
    op: input.method,
    kid: input.kid,
    accessJwt: input.hp.accessJwt,
  });
  const assertion = await signHpOperation(input.signerAuthenticator, operation);
  const path =
    input.method === "revokeIssuerKey"
      ? `/ops/issuer-keys/${encodeURIComponent(input.kid)}/revoke`
      : `/ops/issuer-keys/${encodeURIComponent(input.kid)}/retire`;
  return opsFetch(path, {
    method: "POST",
    headers: await opsHeaders(input.hp.accessJwt),
    body: JSON.stringify({
      action_id: input.actionId ?? crypto.randomUUID(),
      operation,
      assertion,
      signer_credential_id: input.signerCredentialId,
    }),
  });
}

async function opsRegisterServiceKey(input: {
  key: AboGrantKey;
  hp: ActiveHpCredential;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  actionId?: string;
}): Promise<Response> {
  const notBefore = "2020-01-01T00:00:00.000Z";
  const notAfter = "2099-01-01T00:00:00.000Z";
  const operation = await operationForRegisterServiceKey({
    kid: input.key.kid,
    publicKey: input.key.public_key,
    notBefore,
    notAfter,
    accessJwt: input.hp.accessJwt,
  });
  const assertion = await signHpOperation(input.signerAuthenticator, operation);
  return opsFetch("/ops/service-keys", {
    method: "POST",
    headers: await opsHeaders(input.hp.accessJwt),
    body: JSON.stringify({
      action_id: input.actionId ?? crypto.randomUUID(),
      kid: input.key.kid,
      public_key: input.key.public_key,
      not_before: notBefore,
      not_after: notAfter,
      operation,
      assertion,
      signer_credential_id: input.signerCredentialId,
    }),
  });
}

async function opsRevokeServiceKey(input: {
  kid: string;
  hp: ActiveHpCredential;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  actionId?: string;
}): Promise<Response> {
  const operation = await operationForRevokeServiceKey({
    kid: input.kid,
    accessJwt: input.hp.accessJwt,
  });
  const assertion = await signHpOperation(input.signerAuthenticator, operation);
  return opsFetch(`/ops/service-keys/${encodeURIComponent(input.kid)}/revoke`, {
    method: "POST",
    headers: await opsHeaders(input.hp.accessJwt),
    body: JSON.stringify({
      action_id: input.actionId ?? crypto.randomUUID(),
      operation,
      assertion,
      signer_credential_id: input.signerCredentialId,
    }),
  });
}

async function createAboGrantKeyMaterial(): Promise<{
  key: AboGrantKey;
  signer: Awaited<ReturnType<typeof createAboGrantSigner>>;
}> {
  const pair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const kid = crypto.randomUUID();
  const pkcs8Bytes = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const rawBytes = await crypto.subtle.exportKey("raw", pair.publicKey);
  const publicKey = pair.publicKey;
  const sign = async (envelope: unknown): Promise<string> =>
    signCompactJws({
      payload: canonicalize(envelope),
      privateKey: pair.privateKey,
      kid,
    });
  return {
    key: {
      kid,
      pkcs8: base64UrlEncode(new Uint8Array(pkcs8Bytes)),
      public_key: base64UrlEncode(new Uint8Array(rawBytes)),
    },
    signer: { kid, publicKey, sign },
  };
}

async function platformAlertCount(code: string): Promise<number> {
  const row = await env.PLATFORM_DB.prepare(
    `SELECT COUNT(*) AS n FROM platform_alert WHERE code = ?`,
  )
    .bind(code)
    .first<{ n: number }>();
  return row?.n ?? 0;
}

async function operatorActionCount(): Promise<number> {
  const row = await env.DB.prepare(`SELECT COUNT(*) AS n FROM operator_action`).first<{
    n: number;
  }>();
  return row?.n ?? 0;
}

async function operatorActionActorEmails(): Promise<string[]> {
  const rows = await env.DB.prepare(
    `SELECT actor_email FROM operator_action ORDER BY rowid ASC`,
  ).all<{ actor_email: string }>();
  return (rows.results ?? []).map((row) => row.actor_email);
}

async function alertCountByCode(code: string): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM alert WHERE code = ? AND active = 1`,
  )
    .bind(code)
    .first<{ n: number }>();
  return row?.n ?? 0;
}

async function deleteSigningKeyGate(): Promise<void> {
  await env.DB.prepare("DELETE FROM signing_key_gate").run();
}

async function setHarnessAboGrantKey(key: AboGrantKey): Promise<void> {
  Object.assign(env, { ABO_GRANT_KEY: JSON.stringify(key) });
}

async function triggerWorkerFetch(): Promise<void> {
  await deleteSigningKeyGate();
  await SELF.fetch(
    new Request(`https://${env.OPS_HOST}/ops/registries`, {
      headers: {
        "Cf-Access-Jwt-Assertion": await mintVendorAccessJwt(),
        "Abo-Contract-Version": "1",
      },
    }),
  );
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
  const snapshot = {
    contract_version: 1,
    state: "active",
    suspended: false,
    term: {
      ref: "term-hxw-feed",
      plan_display_name: "Clinic Pro",
      starts_at: "2026-04-01T12:00:00.000Z",
      ends_at: "2026-05-01T12:00:00.000Z",
      grace_ends_at: "2026-05-08T12:00:00.000Z",
      allowance: ALLOWANCE_CREDITS,
      used: 0,
      band: "ok",
    },
    queued_count: 0,
    held_count: 0,
    coverage_through: "2026-05-01T12:00:00.000Z",
    binding_epoch: binding.epoch,
    clinic_seq: 1,
  };
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
      1,
      "active",
      snapshot.term.ends_at,
      JSON.stringify(snapshot),
    )
    .run();
}

async function platformHttpInvoke(
  org: string,
  issuer: Awaited<ReturnType<typeof createIssuer>>,
): Promise<Response> {
  await ensureCoverageMirrorForOrg(org);
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

async function runGrantStep(orgId: string): Promise<void> {
  const { runDueGrantWork } = await import("../../src/work/grant");
  await deleteSigningKeyGate();
  await setHarnessAboGrantKey(JSON.parse(env.ABO_GRANT_KEY) as AboGrantKey);
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

beforeEach(async () => {
  await setupCrossWorkerHarness();
  await resetCrossWorkerHarness();
  await ensureMigrations();
  await scriptPaymobStub("ok");
  await scriptPaymobInquiry("bound_success");
  await setClock("2026-06-01T12:00:00.000Z");
  clinicIssuer = null;
});

describe("configuration relays cross-worker", () => {
  it("E2E-P4.9-01 bootstrap operator credential, second credential pending, revoke", async () => {
    await clearOperatorCredentials();
    const accessJwt = await mintVendorAccessJwt();
    const operatorActionBefore = await operatorActionCount();

    const bootstrapAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const bootstrapCredentialId = crypto.randomUUID();
    const bootstrapAttestation = encodeVendorAttestation(
      await bootstrapAuthenticator.attest(),
    );
    const bootstrapActionId = crypto.randomUUID();
    const bootstrap = await opsFetch("/ops/operator-credentials", {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        action_id: bootstrapActionId,
        credential_id: bootstrapCredentialId,
        attestation: bootstrapAttestation,
      }),
    });
    expect(bootstrap.status).toBe(200);
    const bootstrapBody = (await bootstrap.json()) as Record<string, unknown>;
    expect(bootstrapBody.result).toBe("ok");

    const bootstrapAlerts = await env.PLATFORM_DB.prepare(
      `SELECT alert_key, code FROM platform_alert WHERE code = 'AL-13'`,
    ).all<{ alert_key: string; code: string }>();
    expect(
      (bootstrapAlerts.results ?? []).some(
        (row) =>
          row.code === "AL-13" &&
          row.alert_key === `AL-13:${bootstrapCredentialId}:bootstrap`,
      ),
    ).toBe(true);

    const bootstrapClock = await currentHarnessClockIso();
    await setClock(addHours(bootstrapClock, 24));

    const secondAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const secondCredentialId = crypto.randomUUID();
    const secondAttestation = encodeVendorAttestation(
      await secondAuthenticator.attest(),
    );
    const secondIssuedAt = await currentHarnessClockIso();
    const secondOperation = await operationForRegisterCredential({
      credentialId: secondCredentialId,
      signerCredentialId: bootstrapCredentialId,
      attestation: secondAttestation,
      accessJwt,
      issuedAt: secondIssuedAt,
    });
    const secondAssertion = await signHpOperation(
      bootstrapAuthenticator,
      secondOperation,
    );
    const secondActionId = crypto.randomUUID();
    const second = await opsFetch("/ops/operator-credentials", {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        action_id: secondActionId,
        credential_id: secondCredentialId,
        attestation: secondAttestation,
        operation: secondOperation,
        assertion: secondAssertion,
        signer_credential_id: bootstrapCredentialId,
      }),
    });
    expect(second.status).toBe(200);
    const secondBody = (await second.json()) as Record<string, unknown>;
    expect(secondBody.result).toBe("ok");

    const secondRow = await env.PLATFORM_DB.prepare(
      `SELECT status, activates_at FROM operator_credential WHERE credential_id = ?`,
    )
      .bind(secondCredentialId)
      .first<{ status: string; activates_at: string }>();
    expect(secondRow?.status).toBe("pending");
    expect(secondRow?.activates_at).toBe(addHours(secondIssuedAt, 24));

    const revokeOperation = await operationForRevokeCredential({
      credentialId: secondCredentialId,
      signerCredentialId: bootstrapCredentialId,
      accessJwt,
      issuedAt: await currentHarnessClockIso(),
    });
    const revokeAssertion = await signHpOperation(
      bootstrapAuthenticator,
      revokeOperation,
    );
    const revokeActionId = crypto.randomUUID();
    const revoke = await opsFetch(
      `/ops/operator-credentials/${secondCredentialId}/revoke`,
      {
        method: "POST",
        headers: await opsHeaders(accessJwt),
        body: JSON.stringify({
          action_id: revokeActionId,
          operation: revokeOperation,
          assertion: revokeAssertion,
          signer_credential_id: bootstrapCredentialId,
        }),
      },
    );
    expect(revoke.status).toBe(200);
    const revokeBody = (await revoke.json()) as Record<string, unknown>;
    expect(revokeBody.result).toBe("ok");

    expect(await operatorActionCount()).toBe(operatorActionBefore + 3);
    for (const email of await operatorActionActorEmails()) {
      expect(email).toBe(VENDOR_OPERATOR_EMAIL);
    }
  });

  it("E2E-P4.9-03 issuer-key register, token accept/reject within TTL, retire", async () => {
    await setupConfigurationRelaysHarness();
    const orgId = ORG_CFG_03;
    await setupActivePlatformCoverage(orgId);

    const hp = await seedActiveHpCredential();

    const drillIssuer = await createIssuer({ issuerId: env.ISSUER_ID });
    const drillRaw = await crypto.subtle.exportKey("raw", drillIssuer.publicKey);
    const drillPublicKey = base64UrlEncode(new Uint8Array(drillRaw));
    const notBefore = "2020-01-01T00:00:00.000Z";
    const notAfter = "2099-01-01T00:00:00.000Z";
    const operatorActionBefore = await operatorActionCount();

    const registerActionId = crypto.randomUUID();
    const register = await opsRegisterIssuerKey({
      kid: drillIssuer.kid,
      publicKey: drillPublicKey,
      notBefore,
      notAfter,
      hp,
      signerCredentialId: hp.credentialId,
      signerAuthenticator: hp.authenticator,
      actionId: registerActionId,
    });
    expect(register.status).toBe(200);
    const registerBody = (await register.json()) as Record<string, unknown>;
    expect(registerBody.result).toBe("ok");

    const accepted = await platformHttpInvoke(orgId, drillIssuer);
    expect(accepted.status).toBe(200);
    await drainPlatformDurableObjects();

    const revokeActionId = crypto.randomUUID();
    const revoke = await opsIssuerKidRelay({
      method: "revokeIssuerKey",
      kid: drillIssuer.kid,
      hp,
      signerCredentialId: hp.credentialId,
      signerAuthenticator: hp.authenticator,
      actionId: revokeActionId,
    });
    expect(revoke.status).toBe(200);
    const revokeBody = (await revoke.json()) as Record<string, unknown>;
    expect(revokeBody.result).toBe("ok");

    const clockIso = await currentHarnessClockIso();
    await setClock(addMs(clockIso, CONFIG_CACHE_TTL_MS + 1));

    const rejected = await platformHttpInvoke(orgId, drillIssuer);
    expect(rejected.status).toBe(401);
    const rejectedBody = (await rejected.json()) as Record<string, unknown>;
    expect(rejectedBody.code).toBe("unauthenticated");

    const retireIssuer = await createIssuer({ issuerId: env.ISSUER_ID });
    const retireRaw = await crypto.subtle.exportKey(
      "raw",
      retireIssuer.publicKey,
    );
    const retirePublicKey = base64UrlEncode(new Uint8Array(retireRaw));
    const retireRegister = await opsRegisterIssuerKey({
      kid: retireIssuer.kid,
      publicKey: retirePublicKey,
      notBefore,
      notAfter,
      hp,
      signerCredentialId: hp.credentialId,
      signerAuthenticator: hp.authenticator,
      actionId: crypto.randomUUID(),
    });
    expect(retireRegister.status).toBe(200);

    const retireActionId = crypto.randomUUID();
    const retire = await opsIssuerKidRelay({
      method: "retireIssuerKey",
      kid: retireIssuer.kid,
      hp,
      signerCredentialId: hp.credentialId,
      signerAuthenticator: hp.authenticator,
      actionId: retireActionId,
    });
    expect(retire.status).toBe(200);
    const retireBody = (await retire.json()) as Record<string, unknown>;
    expect(retireBody.result).toBe("ok");

    expect(await operatorActionCount()).toBe(operatorActionBefore + 3);
    for (const email of await operatorActionActorEmails()) {
      expect(email).toBe(VENDOR_OPERATOR_EMAIL);
    }
  });

  it("E2E-P4.9-04 service-key register, secret switch, paid grant, revoke old kid", async () => {
    const expectations = await setupConfigurationRelaysHarness();
    const orgId = ORG_CFG_04;
    await putBillingContact(orgId);
    await setupActivePlatformCoverage(orgId);

    const hp = await seedActiveHpCredential();

    const oldHarnessKey = parseAboGrantKey();
    const { key: nextKey } = await createAboGrantKeyMaterial();
    const operatorActionBefore = await operatorActionCount();

    const registerActionId = crypto.randomUUID();
    const register = await opsRegisterServiceKey({
      key: nextKey,
      hp,
      signerCredentialId: hp.credentialId,
      signerAuthenticator: hp.authenticator,
      actionId: registerActionId,
    });
    expect(register.status).toBe(200);
    const registerBody = (await register.json()) as Record<string, unknown>;
    expect(registerBody.result).toBe("ok");

    await setHarnessAboGrantKey(nextKey);
    await deleteSigningKeyGate();

    const { checkoutId } = await postCheckout(
      orgId,
      expectations,
      "req-cfg-04-paid",
    );
    const chargedPrice = await syncPaymobForCheckout(checkoutId);
    const intake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
      { txnId: 94904, amountMinor: chargedPrice },
    );
    expect(intake.status).toBe(200);
    const paymentId = await paymentIdForCheckout(checkoutId);
    expect(paymentId).not.toBeNull();
    await runDueGrantWorkUntilApplied(paymentId!, orgId);
    await drainPlatformDurableObjects();

    const revokeActionId = crypto.randomUUID();
    const revoke = await opsRevokeServiceKey({
      kid: oldHarnessKey.kid,
      hp,
      signerCredentialId: hp.credentialId,
      signerAuthenticator: hp.authenticator,
      actionId: revokeActionId,
    });
    expect(revoke.status).toBe(200);
    const revokeBody = (await revoke.json()) as Record<string, unknown>;
    expect(revokeBody.result).toBe("ok");

    await setHarnessAboGrantKey(nextKey);
    await triggerWorkerFetch();
    expect(await alertCountByCode("AL-23")).toBe(0);

    expect(await operatorActionCount()).toBe(operatorActionBefore + 2);
    for (const email of await operatorActionActorEmails()) {
      expect(email).toBe(VENDOR_OPERATOR_EMAIL);
    }
  });
});
