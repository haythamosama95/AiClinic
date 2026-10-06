/**
 * H-XW cross-worker harness helpers (P4.2).
 */

import { env } from "cloudflare:test";
import { CHANNEL_VERSIONS, grantIdPaid } from "vendor-contracts";
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

const platformMigrationModules = import.meta.glob(
  "../../../ai-platform/migrations/*.sql",
  { query: "?raw", import: "default", eager: true },
) as Record<string, string>;

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
  const paths = Object.keys(platformMigrationModules).sort();
  for (const migrationPath of paths) {
    await applyPlatformSql(platformMigrationModules[migrationPath]);
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

async function vendorAccessIssuer() {
  return {
    issuerId: env.ISSUER_ID,
    teamDomain: env.ACCESS_TEAM_DOMAIN,
    aud: env.ACCESS_AUD,
  };
}

async function ensureVendorAccessTeam(): Promise<
  Awaited<ReturnType<typeof createAccessTeam>>
> {
  if (vendorAccessTeam === null) {
    vendorAccessTeam = await createAccessTeam({
      issuer: await vendorAccessIssuer(),
    });
  }
  return vendorAccessTeam;
}

export async function mintVendorAccessJwt(
  email = VENDOR_OPERATOR_EMAIL,
): Promise<string> {
  const team = await ensureVendorAccessTeam();
  return team.mintAccessJwt({ email });
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
        data: Buffer.from(data),
        headers: Object.fromEntries(response.headers.entries()),
      };
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

async function bootstrapPlatformOperator(
  authenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>,
): Promise<string> {
  const existing = await env.PLATFORM_DB.prepare(
    `SELECT credential_id FROM operator_credential
     WHERE status = 'active'
     ORDER BY rowid DESC
     LIMIT 1`,
  ).first<{ credential_id: string }>();
  if (existing?.credential_id) {
    return existing.credential_id;
  }

  const credentialId = crypto.randomUUID();
  const attestation = encodeVendorAttestation(await authenticator.attest());
  const accessJwt = await mintVendorAccessJwt();
  const result = await platformCall(
    "registerOperatorCredential",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      credential_id: credentialId,
      attestation,
    },
    { accessJwt },
  );
  if (result.result !== "ok") {
    throw new Error(`registerOperatorCredential failed: ${result.code}`);
  }
  const row = JSON.parse(String(result.detail)) as Record<string, unknown>;
  await setPlatformTestClock(String(row.activates_at));
  return credentialId;
}

async function ensurePlatformBootstrap(): Promise<PlatformBootstrap> {
  if (platformBootstrap !== null) {
    return platformBootstrap;
  }
  const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
  const signerCredentialId =
    await bootstrapPlatformOperator(signerAuthenticator);
  const aboSigner = await createAboGrantSigner();
  const rawPublicKey = await crypto.subtle.exportKey("raw", aboSigner.publicKey);
  const publicKeyB64 = base64urlEncode(new Uint8Array(rawPublicKey));
  const notBefore = new Date().toISOString();
  const notAfter = new Date(
    Date.parse(notBefore) + 365 * 24 * 60 * 60 * 1000,
  ).toISOString();
  const accessJwt = await mintVendorAccessJwt();
  const registerOperation = {
    op: "registerServiceKey",
    params: {
      contract_version: VENDOR_CONTRACT_VERSION,
      access_jwt: accessJwt,
      kid: aboSigner.kid,
      public_key: publicKeyB64,
      not_before: notBefore,
      not_after: notAfter,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: notBefore,
    nonce: crypto.randomUUID(),
    contract_version: VENDOR_CONTRACT_VERSION,
  };
  const registerAssertion = encodeVendorAssertion(
    await signerAuthenticator.assert({
      operation: registerOperation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const registerResult = await platformCall(
    "registerServiceKey",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      kid: aboSigner.kid,
      public_key: publicKeyB64,
      not_before: notBefore,
      not_after: notAfter,
      signer_credential_id: signerCredentialId,
      operation: registerOperation,
      assertion: registerAssertion,
    },
    { accessJwt },
  );
  if (registerResult.result !== "ok") {
    throw new Error(`registerServiceKey failed: ${registerResult.code}`);
  }

  platformBootstrap = {
    signerCredentialId,
    signerAuthenticator,
    aboSigner,
    aboKid: aboSigner.kid,
  };
  return platformBootstrap;
}

async function buildPaidGrantEnvelope(input: {
  orgId: string;
  grantId: string;
  allowanceCredits: number;
}): Promise<Record<string, unknown>> {
  const issuedAt = new Date().toISOString();
  return {
    contract_version: VENDOR_CONTRACT_VERSION,
    grant_id: input.grantId,
    org_id: input.orgId,
    plan_id: COVER_PLAN_ID,
    plan_version: COVER_PLAN_VERSION,
    term_unit: "month",
    term_count: 1,
    allowance_credits: input.allowanceCredits,
    grace_days: 0,
    issued_at: issuedAt,
    payment_reference: input.grantId,
  };
}

export async function setupActivePlatformCoverage(orgId: string): Promise<void> {
  const boot = await ensurePlatformBootstrap();
  const accessJwt = await mintVendorAccessJwt();
  const publishOperation = {
    op: "publishPlanVersion",
    params: {
      contract_version: VENDOR_CONTRACT_VERSION,
      access_jwt: accessJwt,
      plan_id: COVER_PLAN_ID,
      version: COVER_PLAN_VERSION,
      display_name: COVER_PLAN_DISPLAY,
      capabilities: COVER_DEFAULT_CAPABILITIES,
      max_cost_class: COVER_DEFAULT_MAX_COST_CLASS,
      concurrency_limit: COVER_DEFAULT_CONCURRENCY,
      max_allowance_per_month: COVER_DEFAULT_ALLOWANCE,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: VENDOR_CONTRACT_VERSION,
  };
  const publishAssertion = encodeVendorAssertion(
    await boot.signerAuthenticator.assert({
      operation: publishOperation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const published = await platformCall(
    "publishPlanVersion",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      plan_id: COVER_PLAN_ID,
      version: COVER_PLAN_VERSION,
      display_name: COVER_PLAN_DISPLAY,
      capabilities: COVER_DEFAULT_CAPABILITIES,
      max_cost_class: COVER_DEFAULT_MAX_COST_CLASS,
      concurrency_limit: COVER_DEFAULT_CONCURRENCY,
      max_allowance_per_month: COVER_DEFAULT_ALLOWANCE,
      signer_credential_id: boot.signerCredentialId,
      operation: publishOperation,
      assertion: publishAssertion,
    },
    { accessJwt },
  );
  if (published.result !== "ok") {
    throw new Error(`publishPlanVersion failed: ${published.code}`);
  }

  const grantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
  const envelope = await buildPaidGrantEnvelope({
    orgId,
    grantId,
    allowanceCredits: COVER_DEFAULT_ALLOWANCE,
  });
  const aboSignature = await boot.aboSigner.sign(envelope);
  const granted = await platformCall("grant", {
    contract_version: VENDOR_CONTRACT_VERSION,
    envelope,
    abo_kid: boot.aboKid,
    abo_signature: aboSignature,
  });
  if (granted.result !== "applied" && granted.result !== "already_applied") {
    throw new Error(`grant failed: ${granted.code}`);
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
  await applyPlatformMigrations();
  await ensurePaymobFetchMock();
  platformBootstrap = null;
  vendorAccessTeam = null;
}

export async function resetCrossWorkerHarness(): Promise<void> {
  await resetHarnessState();
  platformBootstrap = null;
  vendorAccessTeam = null;
  paymobMockReady = false;
  await scriptPaymobStub("ok");
}
