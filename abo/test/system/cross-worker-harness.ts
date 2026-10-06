/**
 * H-XW cross-worker harness helpers (P4.2).
 */

import { env } from "cloudflare:test";
import {
  canonicalize,
  CHANNEL_VERSIONS,
  grantIdPaid,
  sha256Hex,
} from "vendor-contracts";
import { mintHxwVendorAccessJwt } from "./hxw-access-fixture";
import {
  createAboGrantSigner,
  createAccessTeam,
  createSoftwareAuthenticator,
} from "vendor-contracts/testkit";
import {
  applySql,
  billingFetch,
  mintBilling,
  resetHarnessState,
  runScheduled,
  setupHarness,
  setClock as setHarnessClock,
} from "./harness";

import platformSchemaSql from "../../../ai-platform/migrations/20260731120000_platform_schema.sql?raw";
import capabilityGrantLifecycleSql from "../../../ai-platform/migrations/20260802100000_capability_grant_lifecycle.sql?raw";
import routingPolicyCanarySql from "../../../ai-platform/migrations/20260803100000_routing_policy_canary.sql?raw";
import tokenContractSql from "../../../ai-platform/migrations/20260803120000_token_contract.sql?raw";
import retentionIndexesSql from "../../../ai-platform/migrations/20260805120000_f3_retention_indexes.sql?raw";
import conversationIndexSql from "../../../ai-platform/migrations/20260805180000_h3_conversation_index.sql?raw";
import routingPolicyStatusSql from "../../../ai-platform/migrations/20260805190000_routing_policy_status.sql?raw";
import killSwitchSql from "../../../ai-platform/migrations/20260807120000_kill_switch.sql?raw";
import graceAdmissionQueueSql from "../../../ai-platform/migrations/20260821120000_grace_admission_queue.sql?raw";
import entitlementInstallationUniqueSql from "../../../ai-platform/migrations/20260821130000_entitlement_installation_unique.sql?raw";
import planCatalogueSql from "../../../ai-platform/migrations/20260911120000_plan_catalogue.sql?raw";
import usageRollupQuotaWeightSql from "../../../ai-platform/migrations/20260911180000_usage_rollup_quota_weight.sql?raw";
import invoiceSql from "../../../ai-platform/migrations/20260911200000_invoice.sql?raw";
import operatorCredentialSql from "../../../ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql?raw";
import issuerKeyTenantBindingSql from "../../../ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql?raw";
import planVersionPaidGrantCoverageSql from "../../../ai-platform/migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import usageTermSql from "../../../ai-platform/migrations/20261006120000_usage_term.sql?raw";
import ceilingPolicySql from "../../../ai-platform/migrations/20261006130000_ceiling_policy.sql?raw";
import grantVoidSql from "../../../ai-platform/migrations/20261006140000_grant_void.sql?raw";
import transferSql from "../../../ai-platform/migrations/20261006150000_transfer.sql?raw";
import fallbackAdmissionFeedSql from "../../../ai-platform/migrations/20261006160000_fallback_admission_feed.sql?raw";
import dropInvoicingSql from "../../../ai-platform/migrations/20261006170000_drop_invoicing.sql?raw";
import dropPlanEntitlementSql from "../../../ai-platform/migrations/20261006170100_drop_plan_entitlement.sql?raw";

const PLATFORM_MIGRATION_SQL: string[] = [
  platformSchemaSql,
  capabilityGrantLifecycleSql,
  routingPolicyCanarySql,
  tokenContractSql,
  retentionIndexesSql,
  conversationIndexSql,
  routingPolicyStatusSql,
  killSwitchSql,
  graceAdmissionQueueSql,
  entitlementInstallationUniqueSql,
  planCatalogueSql,
  usageRollupQuotaWeightSql,
  invoiceSql,
  operatorCredentialSql,
  issuerKeyTenantBindingSql,
  planVersionPaidGrantCoverageSql,
  usageTermSql,
  ceilingPolicySql,
  grantVoidSql,
  transferSql,
  fallbackAdmissionFeedSql,
  dropInvoicingSql,
  dropPlanEntitlementSql,
];

const VENDOR_CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const COVER_PLAN_ID = "live-monthly";
const COVER_PLAN_VERSION = 1;
const COVER_PLAN_DISPLAY = "Live Monthly";
const COVER_DEFAULT_CAPABILITIES = ["clinic.visit_summary"];
const COVER_DEFAULT_MAX_COST_CLASS = 2;
const COVER_DEFAULT_CONCURRENCY = 4;
const COVER_DEFAULT_ALLOWANCE = 10_000;
const VENDOR_OPERATOR_EMAIL = "operator@vendor.test";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    PLATFORM: {
      [method: string]: (
        args: Record<string, unknown>,
      ) => Promise<Record<string, unknown>>;
    };
    PAYMOB_STUB: Fetcher;
    PLATFORM_DB: D1Database;
    PAYMOB_BASE_URL: string;
    PAYMOB_SECRET_KEY: string;
    PAYMOB_PUBLIC_KEY: string;
    PAYMOB_CARD_INTEGRATION_ID: string;
    ACCESS_TEAM_DOMAIN: string;
    ACCESS_AUD: string;
    WEBAUTHN_RP_ID: string;
    WEBAUTHN_ORIGIN: string;
  }
}

export {
  billingFetch,
  mintBilling,
  resetHarnessState,
  runScheduled,
  setupHarness,
};

export type PaymobStubMode = "ok" | "refuse" | "timeout";

type PlatformBootstrap = {
  signerCredentialId: string;
  signerAuthenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>;
  aboSigner: Awaited<ReturnType<typeof createAboGrantSigner>>;
  aboKid: string;
};

let platformMigrationsApplied = false;
let platformBootstrap: PlatformBootstrap | null = null;
let vendorAccessTeam: Awaited<ReturnType<typeof createAccessTeam>> | null =
  null;

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

async function applyPlatformSql(sql: string): Promise<void> {
  await applySqlOnDb(env.PLATFORM_DB, sql);
}

async function applySqlOnDb(db: D1Database, sql: string): Promise<void> {
  const withoutComments = sql.replace(/--[^\n]*\n/g, "\n");
  const statements: string[] = [];
  let start = 0;
  let index = 0;
  let beginDepth = 0;

  const pushStatement = (end: number): void => {
    const chunk = withoutComments.slice(start, end).trim();
    if (chunk.length > 0) {
      statements.push(chunk);
    }
    start = end;
  };

  while (index < withoutComments.length) {
    const remaining = withoutComments.slice(index);
    const beginMatch = remaining.match(/^\s*BEGIN\b/i);
    if (beginMatch) {
      beginDepth += 1;
      index += beginMatch[0].length;
      continue;
    }
    const endMatch = remaining.match(/^\s*END\s*;/i);
    if (endMatch) {
      beginDepth = Math.max(0, beginDepth - 1);
      index += endMatch[0].length;
      if (beginDepth === 0) {
        pushStatement(index);
      }
      continue;
    }
    if (withoutComments[index] === ";" && beginDepth === 0) {
      index += 1;
      pushStatement(index);
      continue;
    }
    index += 1;
  }
  pushStatement(withoutComments.length);

  for (const statement of statements) {
    try {
      await db.prepare(statement).run();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!/already exists/i.test(message)) {
        throw error;
      }
    }
  }
}

export async function applyPlatformMigrations(): Promise<void> {
  if (platformMigrationsApplied) {
    return;
  }
  for (const sql of PLATFORM_MIGRATION_SQL) {
    await applyPlatformSql(sql);
  }
  await env.PLATFORM_DB.prepare(
    `INSERT OR IGNORE INTO token_contract (ver, added_at, retired_at, changed_by)
     VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed')`,
  ).run();
  await ensurePlatformHarnessClockTable();
  platformMigrationsApplied = true;
}

async function ensurePlatformHarnessClockTable(): Promise<void> {
  await env.PLATFORM_DB.prepare(
    `CREATE TABLE IF NOT EXISTS harness_test_clock (
       id TEXT PRIMARY KEY,
       now_iso TEXT NOT NULL
     )`,
  ).run();
}

async function setPlatformTestClock(isoUtc: string): Promise<void> {
  await ensurePlatformHarnessClockTable();
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO harness_test_clock (id, now_iso) VALUES ('default', ?)`,
  )
    .bind(isoUtc)
    .run();
}

export async function setClock(isoUtc: string): Promise<void> {
  await setHarnessClock(isoUtc);
  await setPlatformTestClock(isoUtc);
}

async function ensureVendorAccessTeam(): Promise<
  Awaited<ReturnType<typeof createAccessTeam>>
> {
  if (vendorAccessTeam === null) {
    const issuer = `https://${env.ACCESS_TEAM_DOMAIN}`;
    vendorAccessTeam = await createAccessTeam({ issuer });
    const { fetchMock } = await import("cloudflare:test");
    fetchMock.activate();
    fetchMock.disableNetConnect();
    fetchMock
      .get(issuer)
      .intercept({ path: "/cdn-cgi/access/certs", method: "GET" })
      .reply(200, JSON.stringify({ keys: vendorAccessTeam.certs.keys }))
      .persist();
  }
  return vendorAccessTeam;
}

export async function mintVendorAccessJwt(
  email = VENDOR_OPERATOR_EMAIL,
): Promise<string> {
  await ensureVendorAccessTeam();
  return mintHxwVendorAccessJwt(env.ACCESS_AUD, email);
}

export async function platformCall(
  method: string,
  args: Record<string, unknown>,
  opts: {
    accessJwt?: string;
    assertion?: Record<string, unknown>;
  } = {},
): Promise<Record<string, unknown>> {
  const payload: Record<string, unknown> = { ...args };
  if (opts.accessJwt !== undefined) {
    payload.access_jwt = opts.accessJwt;
  }
  if (opts.assertion !== undefined) {
    payload.assertion = opts.assertion;
  }
  if (
    method === "grant" &&
    (typeof payload.envelope_b64 === "string" ||
      typeof payload.abo_kid === "string" ||
      typeof payload.abo_signature === "string")
  ) {
    const grantWire: Record<string, unknown> = {};
    if (payload.envelope !== undefined) {
      const bytes = grantEnvelopeWireBytes(
        payload.envelope as Record<string, unknown>,
      );
      grantWire.envelope_b64 = grantEnvelopeWireB64(bytes);
    } else if (typeof payload.envelope_b64 === "string") {
      grantWire.envelope_b64 = payload.envelope_b64;
    }
    if (typeof payload.abo_kid === "string") {
      grantWire.abo_kid = payload.abo_kid;
    }
    if (typeof payload.abo_signature === "string") {
      grantWire.abo_signature = payload.abo_signature;
    }
    payload.envelope = grantWire;
    delete payload.envelope_b64;
    delete payload.abo_kid;
    delete payload.abo_signature;
    delete payload.envelope_json;
  }
  const entrypoint = env.PLATFORM as {
    [key: string]: (input: Record<string, unknown>) => Promise<Record<string, unknown>>;
  };
  return entrypoint[method](payload);
}

let paymobMockReady = false;

export async function ensurePaymobFetchMock(): Promise<void> {
  if (paymobMockReady) {
    return;
  }
  const { fetchMock } = await import("cloudflare:test");
  const baseUrl = env.PAYMOB_BASE_URL;
  const origin = new URL(baseUrl).origin;
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock
    .get(origin)
    .intercept({ path: () => true, method: () => true })
    .reply(async (opts) => {
      try {
        const pathPart = typeof opts.path === "string" ? opts.path : "/";
        const target = new URL(pathPart, baseUrl).toString();
        const response = await env.PAYMOB_STUB.fetch(target, {
          method: opts.method,
          headers: opts.headers as HeadersInit | undefined,
          body: opts.body as BodyInit | undefined,
          signal: opts.signal as AbortSignal | undefined,
        });
        const data = await response.arrayBuffer();
        return {
          statusCode: response.status,
          data: new TextDecoder().decode(data),
        };
      } catch {
        return { statusCode: 502, data: "paymob stub forward failed" };
      }
    })
    .persist();
  paymobMockReady = true;
}

export async function scriptPaymobStub(mode: PaymobStubMode): Promise<void> {
  await env.PAYMOB_STUB.fetch("http://paymob.stub/__script", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ mode }),
  });
}

export async function getLastPaymobIntentionBody(): Promise<
  Record<string, unknown>
> {
  const response = await env.PAYMOB_STUB.fetch("http://paymob.stub/__last");
  return (await response.json()) as Record<string, unknown>;
}

function canonicalGrantEnvelope(
  envelope: Record<string, unknown>,
): Record<string, unknown> {
  return JSON.parse(
    new TextDecoder().decode(canonicalize(envelope)),
  ) as Record<string, unknown>;
}

async function seedPlatformVendorCatalog(
  input: {
    signerCredentialId: string;
    attestation: { alg: "ES256" | "EdDSA"; public_key: string };
    aboKid: string;
    aboPublicKeyB64: string;
  },
): Promise<void> {
  const activatesAt = new Date(Date.now() - 60_000).toISOString();
  await env.PLATFORM_DB.prepare(
    `INSERT OR IGNORE INTO operator_credential
       (credential_id, operator_email, public_key_cose, alg, status, activates_at, approved_by, revoked_by)
     VALUES (?, ?, ?, ?, 'active', ?, NULL, NULL)`,
  )
    .bind(
      input.signerCredentialId,
      VENDOR_OPERATOR_EMAIL,
      input.attestation.public_key,
      input.attestation.alg,
      activatesAt,
    )
    .run();

  const notBefore = "2020-01-01T00:00:00.000Z";
  const notAfter = "2099-01-01T00:00:00.000Z";
  await env.PLATFORM_DB.prepare(
    `INSERT OR REPLACE INTO service_key
       (kid, service, public_key, status, not_before, not_after, registered_by, assertion_sha256)
     VALUES (?, 'abo', ?, 'active', ?, ?, ?, 'harness')`,
  )
    .bind(input.aboKid, input.aboPublicKeyB64, notBefore, notAfter, VENDOR_OPERATOR_EMAIL)
    .run();

  const existingPlan = await env.PLATFORM_DB.prepare(
    `SELECT 1 AS present FROM plan_version WHERE plan_id = ? AND version = ?`,
  )
    .bind(COVER_PLAN_ID, COVER_PLAN_VERSION)
    .first<{ present: number }>();
  if (!existingPlan?.present) {
    await env.PLATFORM_DB.prepare(
      `INSERT INTO plan_version (
         plan_id, version, display_name, capabilities, max_cost_class,
         concurrency_limit, max_allowance_per_month, status, published_by,
         assertion_sha256
       ) VALUES (?, ?, ?, ?, ?, ?, ?, 'published', ?, 'harness')`,
    )
      .bind(
        COVER_PLAN_ID,
        COVER_PLAN_VERSION,
        COVER_PLAN_DISPLAY,
        JSON.stringify(COVER_DEFAULT_CAPABILITIES),
        String(COVER_DEFAULT_MAX_COST_CLASS),
        COVER_DEFAULT_CONCURRENCY,
        COVER_DEFAULT_ALLOWANCE,
        VENDOR_OPERATOR_EMAIL,
      )
      .run();
  }
}

async function ensurePlatformBootstrap(): Promise<PlatformBootstrap> {
  if (platformBootstrap !== null) {
    return platformBootstrap;
  }
  const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
  const signerCredentialId = crypto.randomUUID();
  const attestation = encodeVendorAttestation(await signerAuthenticator.attest());
  const aboSigner = await createAboGrantSigner();
  const rawPublicKey = await crypto.subtle.exportKey("raw", aboSigner.publicKey);
  const publicKeyB64 = base64urlEncode(new Uint8Array(rawPublicKey));
  await seedPlatformVendorCatalog({
    signerCredentialId,
    attestation,
    aboKid: aboSigner.kid,
    aboPublicKeyB64: publicKeyB64,
  });
  platformBootstrap = {
    signerCredentialId,
    signerAuthenticator,
    aboSigner,
    aboKid: aboSigner.kid,
  };
  return platformBootstrap;
}

function grantEnvelopeWireBytes(envelope: Record<string, unknown>): Uint8Array {
  return canonicalize(envelope);
}

function grantEnvelopeWireB64(envelopeBytes: Uint8Array): string {
  let binary = "";
  for (const byte of envelopeBytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

async function buildPaidGrantEnvelope(input: {
  orgId: string;
  grantId: string;
  allowanceCredits: number;
  signerCredentialId: string;
}): Promise<Record<string, unknown>> {
  const paidAt = new Date().toISOString();
  const paymentRef = crypto.randomUUID().replace(/-/g, "");
  const contentSha256 = await sha256Hex(
    new TextEncoder().encode(paymentRef),
  );
  return {
    contract_version: VENDOR_CONTRACT_VERSION,
    grant_id: input.grantId,
    org_id: input.orgId,
    kind: "term",
    placement: "queue",
    source: { kind: "paid", ref: paymentRef },
    plan: { plan_id: COVER_PLAN_ID, plan_version: COVER_PLAN_VERSION },
    duration: { unit: "month", count: 1 },
    allowance_credits: input.allowanceCredits,
    grace: { days: 7, cap_rule: "proportional" },
    paid_at: paidAt,
    evidence: {
      content_sha256: contentSha256,
      approvals: [
        { credential_id: input.signerCredentialId, assertion: "stub" },
      ],
    },
  };
}

function buildHarnessCoverageSnapshot(
  bindingEpoch: number,
  clinicSeq: number,
): Record<string, unknown> {
  const at = "2026-04-01T12:00:00.000Z";
  return {
    contract_version: 1,
    state: "active",
    suspended: false,
    term: {
      ref: "term-hxw-feed",
      plan_display_name: COVER_PLAN_DISPLAY,
      starts_at: at,
      ends_at: "2026-05-01T12:00:00.000Z",
      grace_ends_at: "2026-05-08T12:00:00.000Z",
      allowance: COVER_DEFAULT_ALLOWANCE,
      used: 0,
      band: "ok",
    },
    queued_count: 0,
    held_count: 0,
    coverage_through: "2026-05-01T12:00:00.000Z",
    binding_epoch: bindingEpoch,
    clinic_seq: clinicSeq,
  };
}

/** Seeds platform `coverage_event` rows without HP vendor RPC (H-XW feed cron). */
export async function setupPlatformCoverageFeed(orgId: string): Promise<void> {
  await applyPlatformMigrations();
  const installationId = `inst-${orgId}`;
  const bindingEpoch = 1;
  const clinicSeq = 1;
  const at = "2026-04-01T12:00:00.000Z";
  const snapshot = buildHarnessCoverageSnapshot(bindingEpoch, clinicSeq);
  await env.PLATFORM_DB.prepare(
    `INSERT INTO coverage_event (
       event_id, org_id, installation_id, binding_epoch, clinic_seq, kind, snapshot, at
     ) VALUES (?, ?, ?, ?, ?, 'snapshot', ?, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      orgId,
      installationId,
      bindingEpoch,
      clinicSeq,
      JSON.stringify(snapshot),
      at,
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

export async function setupActivePlatformCoverage(orgId: string): Promise<void> {
  const boot = await ensurePlatformBootstrap();
  await setPlatformTestClock("2026-06-01T12:00:00.000Z");
  await ensureGrantTenantBinding(orgId);

  const grantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
  const envelope = canonicalGrantEnvelope(
    await buildPaidGrantEnvelope({
      orgId,
      grantId,
      allowanceCredits: COVER_DEFAULT_ALLOWANCE,
      signerCredentialId: boot.signerCredentialId,
    }),
  );
  const envelopeBytes = grantEnvelopeWireBytes(envelope);
  const aboSignature = await boot.aboSigner.sign(envelope);
  const granted = await platformCall("grant", {
    contract_version: VENDOR_CONTRACT_VERSION,
    envelope_b64: grantEnvelopeWireB64(envelopeBytes),
    abo_kid: boot.aboKid,
    abo_signature: aboSignature,
  });
  if (granted.result !== "applied" && granted.result !== "already_applied") {
    throw new Error(`grant failed: ${String(granted.code)}`);
  }

  const coverage = await platformCall("getCoverage", {
    contract_version: VENDOR_CONTRACT_VERSION,
    org_id: orgId,
  });
  if (coverage.result !== "ok") {
    throw new Error(`getCoverage not active after grant: ${coverage.code}`);
  }
}

export async function setupCrossWorkerHarness(): Promise<void> {
  await setupHarness();
  await ensureVendorAccessTeam();
  await applyPlatformMigrations();
  await ensurePaymobFetchMock();
  platformBootstrap = null;
  vendorAccessTeam = null;
}

export async function resetCrossWorkerHarness(): Promise<void> {
  await resetHarnessState();
  platformBootstrap = null;
  vendorAccessTeam = null;
  platformMigrationsApplied = false;
  paymobMockReady = false;
  await scriptPaymobStub("ok");
}
