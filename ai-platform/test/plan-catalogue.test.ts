/**
 * P3.10 — plan catalogue via publishPlanVersion (Test Layout mapping).
 */

import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { createAccessTeam, createSoftwareAuthenticator } from "vendor-contracts/testkit";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import operatorCredentialMigrationSql from "../migrations/20261003120000_operator_credential_and_platform_alert.sql?raw";
import issuerKeyTenantBindingMigrationSql from "../migrations/20261003130000_issuer_key_tenant_binding.sql?raw";
import planVersionPaidGrantCoverageMigrationSql from "../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import dropInvoicingSql from "../migrations/20261006170000_drop_invoicing.sql?raw";
import dropPlanEntitlementSql from "../migrations/20261006170100_drop_plan_entitlement.sql?raw";
import { applySqlStatements } from "./split-sql-statements";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    ACCESS_TEAM_DOMAIN: string;
    ACCESS_AUD: string;
    WEBAUTHN_RP_ID: string;
    WEBAUTHN_ORIGIN: string;
    VENDOR: {
      publishPlanVersion(
        args: Record<string, unknown>,
      ): Promise<{ result: string; code: string; detail: string }>;
      registerOperatorCredential(
        args: Record<string, unknown>,
      ): Promise<{ result: string; code: string; detail: string }>;
      registerServiceKey(
        args: Record<string, unknown>,
      ): Promise<{ result: string; code: string; detail: string }>;
    };
  }
}

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const VENDOR_OPERATOR_EMAIL = "operator@clinic.test";

const PLAN_ID = "catalogue-pro";
const PLAN_VERSION = 1;
const PLAN_DISPLAY_NAME = "Professional Catalogue";
const PLAN_CAPABILITIES = ["clinic.visit_summary"];
const PLAN_MAX_COST_CLASS = 2;
const PLAN_CONCURRENCY_LIMIT = 4;
const PLAN_MAX_ALLOWANCE_PER_MONTH = 10_000;

function base64urlEncode(data: string | Uint8Array): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
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

let accessTeam: Awaited<ReturnType<typeof createAccessTeam>> | null = null;
let vendorTestClockIso: string | null = null;

async function ensureHarnessTestClockTable(): Promise<void> {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS harness_test_clock (
       id TEXT PRIMARY KEY,
       now_iso TEXT NOT NULL
     )`,
  ).run();
}

async function setTestClock(isoUtc: string): Promise<void> {
  await ensureHarnessTestClockTable();
  await env.DB.prepare(
    `INSERT OR REPLACE INTO harness_test_clock (id, now_iso) VALUES ('default', ?)`,
  )
    .bind(isoUtc)
    .run();
  vendorTestClockIso = isoUtc;
}

function getVendorTestClockIso(): string | null {
  return vendorTestClockIso;
}

async function mintVendorAccessJwt(): Promise<string> {
  if (accessTeam === null) {
    accessTeam = await createAccessTeam({
      issuer: `https://${env.ACCESS_TEAM_DOMAIN}`,
    });
    const { fetchMock } = await import("cloudflare:test");
    fetchMock.activate();
    fetchMock.disableNetConnect();
    fetchMock
      .get(`https://${env.ACCESS_TEAM_DOMAIN}`)
      .intercept({ path: "/cdn-cgi/access/certs", method: "GET" })
      .reply(200, JSON.stringify({ keys: accessTeam.certs.keys }))
      .persist();
  }
  const nowMs = vendorTestClockIso
    ? Date.parse(vendorTestClockIso)
    : Date.now();
  const now = Math.floor(nowMs / 1000);
  return accessTeam.mint({
    email: VENDOR_OPERATOR_EMAIL,
    aud: env.ACCESS_AUD,
    iat: now - 60,
    exp: now + 3600,
  });
}

async function bootstrapSigner(): Promise<{
  signerCredentialId: string;
  signerAuthenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>;
}> {
  const signerAuthenticator = await createSoftwareAuthenticator();
  const credentialId = crypto.randomUUID();
  const registerJwt = await mintVendorAccessJwt();
  const attestation = encodeVendorAttestation(await signerAuthenticator.attest());
  const registered = await env.VENDOR.registerOperatorCredential({
    contract_version: CONTRACT_VERSION,
    access_jwt: registerJwt,
    credential_id: credentialId,
    attestation,
  });
  expect(registered.result).toBe("ok");
  const row = JSON.parse(registered.detail) as Record<string, unknown>;
  await setTestClock(String(row.activates_at));
  const accessJwt = await mintVendorAccessJwt();
  return { signerCredentialId: credentialId, signerAuthenticator, accessJwt };
}

async function operationForPublishPlanVersion(input: {
  accessJwt: string;
}): Promise<Record<string, unknown>> {
  return {
    op: "publishPlanVersion",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      plan_id: PLAN_ID,
      version: PLAN_VERSION,
      display_name: PLAN_DISPLAY_NAME,
      capabilities: PLAN_CAPABILITIES,
      max_cost_class: PLAN_MAX_COST_CLASS,
      concurrency_limit: PLAN_CONCURRENCY_LIMIT,
      max_allowance_per_month: PLAN_MAX_ALLOWANCE_PER_MONTH,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function clearPlanVersionRows(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM plan_version"),
    env.DB.prepare("DELETE FROM service_key"),
    env.DB.prepare("DELETE FROM control_audit"),
  ]);
}

beforeAll(async () => {
  await applySqlStatements(env.DB, migrationSql);
  await applySqlStatements(env.DB, operatorCredentialMigrationSql);
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, dropInvoicingSql);
  await applySqlStatements(env.DB, dropPlanEntitlementSql);
});

beforeEach(async () => {
  await clearPlanVersionRows();
});

describe("plan_catalogue_publish_plan_version", () => {
  it("creates a published plan_version row via publishPlanVersion", async () => {
    const { signerCredentialId, signerAuthenticator, accessJwt } =
      await bootstrapSigner();
    const operation = await operationForPublishPlanVersion({ accessJwt });
    const assertion = encodeVendorAssertion(
      await signerAuthenticator.assert({
        operation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      }),
    );

    const envelope = await env.VENDOR.publishPlanVersion({
      contract_version: CONTRACT_VERSION,
      access_jwt: accessJwt,
      plan_id: PLAN_ID,
      version: PLAN_VERSION,
      display_name: PLAN_DISPLAY_NAME,
      capabilities: PLAN_CAPABILITIES,
      max_cost_class: PLAN_MAX_COST_CLASS,
      concurrency_limit: PLAN_CONCURRENCY_LIMIT,
      max_allowance_per_month: PLAN_MAX_ALLOWANCE_PER_MONTH,
      signer_credential_id: signerCredentialId,
      operation,
      assertion,
    });

    expect(envelope.result).toBe("ok");
    expect(envelope.code).toBe("");
    expect(envelope.detail.length).toBeGreaterThan(0);

    const row = await env.DB.prepare(
      `SELECT plan_id, version, status, display_name, capabilities
       FROM plan_version WHERE plan_id = ? AND version = ?`,
    )
      .bind(PLAN_ID, PLAN_VERSION)
      .first<{
        plan_id: string;
        version: number;
        status: string;
        display_name: string;
        capabilities: string;
      }>();

    expect(row).toMatchObject({
      plan_id: PLAN_ID,
      version: PLAN_VERSION,
      status: "published",
      display_name: PLAN_DISPLAY_NAME,
    });
    expect(JSON.parse(row?.capabilities ?? "[]")).toEqual(PLAN_CAPABILITIES);
  });
});
