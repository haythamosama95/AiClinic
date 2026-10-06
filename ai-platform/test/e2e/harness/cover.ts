import { CHANNEL_VERSIONS, grantIdPaid, sha256Hex } from "vendor-contracts";
import {
  createAboGrantSigner,
  createSoftwareAuthenticator,
} from "vendor-contracts/testkit";
import { isolateConfigCache } from "../../../src/config-cache";
import { ensureE2eIssuerRegistry, mintVendorAccessJwt } from "./aat";
import { queryOne } from "./d1";
import { CAPABILITY_ID, env } from "./env";
import type { Scenario } from "./types";
import { vendorCall, vendorEnvelopeToHttp } from "./vendor";

const VENDOR_CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
export const VENDOR_OPERATOR_EMAIL = "operator@clinic.test";

const COVER_PLAN_ID = "live-monthly";
const COVER_PLAN_VERSION = 1;
const COVER_PLAN_DISPLAY = "Live Monthly";
const COVER_DEFAULT_CAPABILITIES = [CAPABILITY_ID];
const COVER_DEFAULT_MAX_COST_CLASS = 2;
const COVER_DEFAULT_CONCURRENCY = 4;
const COVER_DEFAULT_ALLOWANCE = 10_000;

export type CoverClinicOptions = {
  capabilities?: string[];
  concurrency_limit?: number;
  max_allowance_per_month?: number;
};

type CoverClinicBootstrap = {
  signerCredentialId: string;
  signerAuthenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>;
  aboSigner: Awaited<ReturnType<typeof createAboGrantSigner>>;
  aboKid: string;
};

let coverClinicBootstrap: CoverClinicBootstrap | null = null;

export function resetCoverClinicBootstrap(): void {
  coverClinicBootstrap = null;
}

function base64urlEncode(data: Uint8Array): string {
  let binary = "";
  for (const byte of data) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

function randomUuid(): string {
  return crypto.randomUUID();
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

async function operationForCoverPublishPlan(input: {
  accessJwt: string;
  capabilities: string[];
  concurrencyLimit: number;
  maxAllowance: number;
}): Promise<Record<string, unknown>> {
  return {
    op: "publishPlanVersion",
    params: {
      contract_version: VENDOR_CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      plan_id: COVER_PLAN_ID,
      version: COVER_PLAN_VERSION,
      display_name: COVER_PLAN_DISPLAY,
      capabilities: input.capabilities,
      max_cost_class: COVER_DEFAULT_MAX_COST_CLASS,
      concurrency_limit: input.concurrencyLimit,
      max_allowance_per_month: input.maxAllowance,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: new Date().toISOString(),
    nonce: randomUuid(),
    contract_version: VENDOR_CONTRACT_VERSION,
  };
}

async function ensureCoverClinicBootstrap(): Promise<CoverClinicBootstrap> {
  if (coverClinicBootstrap !== null) {
    return coverClinicBootstrap;
  }
  const issuer = await ensureE2eIssuerRegistry();
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
    nonce: randomUuid(),
    contract_version: VENDOR_CONTRACT_VERSION,
  };
  const registerAssertion = encodeVendorAssertion(
    await issuer.signerAuthenticator.assert({
      operation: registerOperation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const registerResult = await vendorCall(
    "registerServiceKey",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      kid: aboSigner.kid,
      public_key: publicKeyB64,
      not_before: notBefore,
      not_after: notAfter,
      signer_credential_id: issuer.signerCredentialId,
      operation: registerOperation,
      assertion: registerAssertion,
    },
    { accessJwt },
  );
  if (registerResult.result !== "ok") {
    throw new Error(`registerServiceKey failed: ${registerResult.code}`);
  }
  coverClinicBootstrap = {
    signerCredentialId: issuer.signerCredentialId,
    signerAuthenticator: issuer.signerAuthenticator,
    aboSigner,
    aboKid: aboSigner.kid,
  };
  return coverClinicBootstrap;
}

export function coverClinicSigner(): {
  signerCredentialId: string;
  signerAuthenticator: CoverClinicBootstrap["signerAuthenticator"];
} {
  if (coverClinicBootstrap === null) {
    throw new Error("coverClinicSigner: call coverClinic() first");
  }
  return {
    signerCredentialId: coverClinicBootstrap.signerCredentialId,
    signerAuthenticator: coverClinicBootstrap.signerAuthenticator,
  };
}

async function buildCoverPaidGrantEnvelope(input: {
  orgId: string;
  grantId: string;
  allowanceCredits: number;
}): Promise<Record<string, unknown>> {
  const paidAt = new Date().toISOString();
  const paymentRef = randomUuid().replace(/-/g, "");
  const contentSha256 = await sha256Hex(new TextEncoder().encode(paymentRef));
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
      approvals: [{ credential_id: "cred-001", assertion: "stub" }],
    },
  };
}

export async function coverClinic(
  scenario: Scenario,
  opts: CoverClinicOptions = {},
): Promise<void> {
  const boot = await ensureCoverClinicBootstrap();
  const capabilities = opts.capabilities ?? COVER_DEFAULT_CAPABILITIES;
  const concurrencyLimit =
    opts.concurrency_limit ?? COVER_DEFAULT_CONCURRENCY;
  const maxAllowance =
    opts.max_allowance_per_month ?? COVER_DEFAULT_ALLOWANCE;

  const accessJwt = await mintVendorAccessJwt();
  const publishOperation = await operationForCoverPublishPlan({
    accessJwt,
    capabilities,
    concurrencyLimit,
    maxAllowance,
  });
  const publishAssertion = encodeVendorAssertion(
    await boot.signerAuthenticator.assert({
      operation: publishOperation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const published = await vendorCall(
    "publishPlanVersion",
    {
      contract_version: VENDOR_CONTRACT_VERSION,
      plan_id: COVER_PLAN_ID,
      version: COVER_PLAN_VERSION,
      display_name: COVER_PLAN_DISPLAY,
      capabilities,
      max_cost_class: COVER_DEFAULT_MAX_COST_CLASS,
      concurrency_limit: concurrencyLimit,
      max_allowance_per_month: maxAllowance,
      signer_credential_id: boot.signerCredentialId,
      operation: publishOperation,
      assertion: publishAssertion,
    },
    { accessJwt },
  );
  if (published.result !== "ok") {
    throw new Error(`publishPlanVersion failed: ${published.code}`);
  }

  const grantId = await grantIdPaid(randomUuid().replace(/-/g, ""));
  const envelope = await buildCoverPaidGrantEnvelope({
    orgId: scenario.orgId,
    grantId,
    allowanceCredits: maxAllowance,
  });
  const aboSignature = await boot.aboSigner.sign(envelope);
  const granted = await vendorCall("grant", {
    contract_version: VENDOR_CONTRACT_VERSION,
    envelope,
    abo_kid: boot.aboKid,
    abo_signature: aboSignature,
  });
  if (
    granted.result !== "applied" &&
    granted.result !== "already_applied"
  ) {
    throw new Error(`grant failed: ${granted.code}`);
  }

  const binding = await queryOne<{ installation_id: string }>(
    "SELECT installation_id FROM tenant_binding WHERE org_id = ? AND status = 'active'",
    [scenario.orgId],
  );
  if (!binding?.installation_id) {
    throw new Error("coverClinic: tenant_binding missing after grant");
  }
  scenario.installationId = binding.installation_id;
  isolateConfigCache.clear();
}

export async function vendorSuspend(
  scenario: Scenario,
  reason = "e2e",
): Promise<{ status: number; json: Record<string, unknown> }> {
  const accessJwt = await mintVendorAccessJwt();
  return vendorEnvelopeToHttp(
    await vendorCall(
      "suspend",
      {
        contract_version: VENDOR_CONTRACT_VERSION,
        org_id: scenario.orgId,
        reason,
      },
      { accessJwt },
    ),
  );
}

export async function vendorResume(
  scenario: Scenario,
  reason = "e2e",
): Promise<{ status: number; json: Record<string, unknown> }> {
  const accessJwt = await mintVendorAccessJwt();
  return vendorEnvelopeToHttp(
    await vendorCall(
      "resume",
      {
        contract_version: VENDOR_CONTRACT_VERSION,
        org_id: scenario.orgId,
        reason,
      },
      { accessJwt },
    ),
  );
}

export async function vendorDeleteInstallation(
  scenario: Scenario,
  reason = "e2e-delete",
): Promise<{ status: number; json: Record<string, unknown> }> {
  const boot = await ensureCoverClinicBootstrap();
  const accessJwt = await mintVendorAccessJwt();
  const operation = {
    op: "deleteInstallation",
    params: {
      contract_version: VENDOR_CONTRACT_VERSION,
      access_jwt: accessJwt,
      org_id: scenario.orgId,
      reason,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: new Date().toISOString(),
    nonce: randomUuid(),
    contract_version: VENDOR_CONTRACT_VERSION,
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
  return vendorEnvelopeToHttp(
    await vendorCall(
      "deleteInstallation",
      {
        contract_version: VENDOR_CONTRACT_VERSION,
        org_id: scenario.orgId,
        reason,
        signer_credential_id: boot.signerCredentialId,
        operation,
        assertion,
      },
      { accessJwt },
    ),
  );
}

export async function vendorInspectCoverage(
  orgId: string,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const accessJwt = await mintVendorAccessJwt();
  return vendorEnvelopeToHttp(
    await vendorCall(
      "inspectCoverage",
      {
        contract_version: VENDOR_CONTRACT_VERSION,
        org_id: orgId,
      },
      { accessJwt },
    ),
  );
}
