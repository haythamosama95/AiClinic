import { CHANNEL_VERSIONS } from "vendor-contracts";
import { createSoftwareAuthenticator } from "vendor-contracts/testkit";
import { queryOne } from "./d1";
import {
  AAT_AUDIENCE,
  env,
  ISSUER_ID,
  TOKEN_CONTRACT_VER,
  WEBAUTHN_ORIGIN,
  WEBAUTHN_RP_ID,
} from "./env";
import {
  nowSeconds,
  signJwt,
  type TestKeypair,
} from "./crypto";
import type { Scenario } from "./types";

export type AatClaims = {
  iss: string;
  aud: string;
  sub: string;
  org: string;
  branch: string;
  role: string;
  scopes: string[];
  jti: string;
  iat: number;
  exp: number;
  ver: string;
};

export type MintAatOptions = {
  /** Sign with this keypair (default: harness issuer key). */
  keypair?: TestKeypair;
  /** JWT header `kid`. Defaults to the signing keypair's kid. */
  kid?: string;
  /** JWT header `alg`. Default `EdDSA`. */
  alg?: string;
  /** Extra / overriding header fields (merged after alg/kid defaults). */
  header?: Record<string, unknown>;
  /**
   * Claim overrides. Unspecified claims keep defaults.
   * The live JWT claim is `role` (singular), not `roles`.
   * Pass wrong types or extra keys here — they are serialized as given.
   */
  claims?: Record<string, unknown>;
  /** Delete these claim names after applying defaults + `claims`. */
  omitClaims?: string[];
  /** Delete these header names after applying defaults + `header`. */
  omitHeaderFields?: string[];
  /** @deprecated Issuer tokens have no installation_key validity window. */
  skipValidityWait?: boolean;
  /** Replace the signature segment instead of signing. */
  signatureB64?: string;
};

type IssuerRegistry = {
  kid: string;
  privateKey: CryptoKey;
  publicKeyB64: string;
  signerCredentialId: string;
  signerAuthenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>;
};

let issuerRegistry: IssuerRegistry | null = null;

export function clearE2eIssuerRegistry(): void {
  issuerRegistry = null;
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

type AccessTeam = Awaited<
  ReturnType<typeof import("vendor-contracts/testkit").createAccessTeam>
>;

let vendorAccessTeam: AccessTeam | null = null;

async function ensureVendorAccessTeam(): Promise<AccessTeam> {
  if (vendorAccessTeam !== null) {
    return vendorAccessTeam;
  }
  const { createAccessTeam } = await import("vendor-contracts/testkit");
  const { fetchMock } = await import("cloudflare:test");
  const issuer = `https://${env.ACCESS_TEAM_DOMAIN}`;
  vendorAccessTeam = await createAccessTeam({ issuer });
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock
    .get(issuer)
    .intercept({ path: "/cdn-cgi/access/certs", method: "GET" })
    .reply(200, JSON.stringify({ keys: vendorAccessTeam.certs.keys }))
    .persist();
  return vendorAccessTeam;
}

export async function mintVendorAccessJwt(): Promise<string> {
  const team = await ensureVendorAccessTeam();
  const now = Math.floor(Date.now() / 1000);
  return team.mint({
    email: "operator@clinic.test",
    aud: env.ACCESS_AUD,
    iat: now - 60,
    exp: now + 3600,
  });
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

async function bootstrapOperatorCredential(
  authenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>,
): Promise<string> {
  const credentialId = crypto.randomUUID();
  const attestation = encodeVendorAttestation(await authenticator.attest());
  const accessJwt = await mintVendorAccessJwt();
  const contractVersion = CHANNEL_VERSIONS.vendorEntrypoint;
  const result = await env.VENDOR.registerOperatorCredential({
    contract_version: contractVersion,
    credential_id: credentialId,
    access_jwt: accessJwt,
    attestation,
  });
  if (result.result !== "ok") {
    throw new Error(`registerOperatorCredential failed: ${result.code}`);
  }
  const activatesAt = new Date(Date.now() - 1000).toISOString();
  await env.DB.prepare(
    "UPDATE operator_credential SET activates_at = ? WHERE credential_id = ?",
  )
    .bind(activatesAt, credentialId)
    .run();
  const listed = await env.VENDOR.listOperatorCredentials({
    contract_version: contractVersion,
  });
  if (listed.result !== "ok") {
    throw new Error(`listOperatorCredentials failed: ${listed.code}`);
  }
  const promoted = await env.DB.prepare(
    "SELECT status FROM operator_credential WHERE credential_id = ?",
  )
    .bind(credentialId)
    .first<{ status: string }>();
  if (promoted?.status !== "active") {
    throw new Error(
      `signer credential not active: ${promoted?.status ?? "missing"}`,
    );
  }
  return credentialId;
}

type SignerAuthenticator = Awaited<
  ReturnType<typeof createSoftwareAuthenticator>
>;

function issuerKidOutsideWindow(row: {
  not_before: string;
  not_after: string;
} | null): boolean {
  if (row === null) {
    return true;
  }
  const nowSeconds = Math.floor(Date.now() / 1000);
  const notBeforeMs = Date.parse(row.not_before);
  const notAfterMs = Date.parse(row.not_after);
  return (
    (!Number.isNaN(notBeforeMs) &&
      nowSeconds < Math.floor(notBeforeMs / 1000)) ||
    (!Number.isNaN(notAfterMs) && nowSeconds >= Math.floor(notAfterMs / 1000))
  );
}

async function registerHarnessIssuerKey(
  signerCredentialId: string,
  signerAuthenticator: SignerAuthenticator,
): Promise<IssuerRegistry> {
  const kid = crypto.randomUUID();
  const keyPair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const rawPublicKey = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  const publicKeyB64 = base64urlEncode(new Uint8Array(rawPublicKey));
  const notBefore = new Date().toISOString();
  const notAfter = new Date(
    Date.parse(notBefore) + 365 * 24 * 60 * 60 * 1000,
  ).toISOString();
  const accessJwt = await mintVendorAccessJwt();
  const contractVersion = CHANNEL_VERSIONS.vendorEntrypoint;
  const operation = {
    op: "registerIssuerKey",
    params: {
      contract_version: contractVersion,
      access_jwt: accessJwt,
      kid,
      public_key: publicKeyB64,
      not_before: notBefore,
      not_after: notAfter,
    },
    actor_email: "operator@clinic.test",
    issued_at: notBefore,
    nonce: crypto.randomUUID(),
    contract_version: contractVersion,
  };
  const assertion = encodeVendorAssertion(
    await signerAuthenticator.assert({
      operation,
      rpId: WEBAUTHN_RP_ID,
      origin: WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const envelope = await env.VENDOR.registerIssuerKey({
    contract_version: contractVersion,
    kid,
    public_key: publicKeyB64,
    not_before: notBefore,
    not_after: notAfter,
    signer_credential_id: signerCredentialId,
    operation,
    assertion,
    access_jwt: accessJwt,
  });
  if (envelope.result !== "ok") {
    throw new Error(`registerIssuerKey failed: ${envelope.code}`);
  }

  return {
    kid,
    privateKey: keyPair.privateKey,
    publicKeyB64,
    signerCredentialId,
    signerAuthenticator,
  };
}

export async function ensureE2eIssuerRegistry(): Promise<IssuerRegistry> {
  if (issuerRegistry !== null) {
    const row = await queryOne<{
      not_before: string;
      not_after: string;
    }>(
      "SELECT not_before, not_after FROM issuer_key WHERE kid = ?",
      [issuerRegistry.kid],
    );
    if (!issuerKidOutsideWindow(row)) {
      return issuerRegistry;
    }
    const stored = await queryOne<{ credential_id: string }>(
      "SELECT credential_id FROM operator_credential WHERE credential_id = ?",
      [issuerRegistry.signerCredentialId],
    );
    if (stored !== null) {
      issuerRegistry = await registerHarnessIssuerKey(
        issuerRegistry.signerCredentialId,
        issuerRegistry.signerAuthenticator,
      );
      return issuerRegistry;
    }
    issuerRegistry = null;
  }

  const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
  const signerCredentialId =
    await bootstrapOperatorCredential(signerAuthenticator);
  issuerRegistry = await registerHarnessIssuerKey(
    signerCredentialId,
    signerAuthenticator,
  );
  return issuerRegistry;
}

function defaultClaims(scenario: Scenario): AatClaims {
  const iat = nowSeconds() - 30;
  return {
    iss: ISSUER_ID,
    aud: AAT_AUDIENCE,
    sub: scenario.actorId,
    org: scenario.orgId,
    branch: scenario.branchId,
    role: "clinician",
    scopes: ["ai.visit_summary", "ai.access"],
    jti: crypto.randomUUID(),
    iat,
    exp: iat + 330,
    ver: TOKEN_CONTRACT_VER,
  };
}

/**
 * Mint a compact EdDSA JWS signed by the harness issuer key (ver 2).
 */
export async function mintAat(
  scenario: Scenario,
  options: MintAatOptions = {},
): Promise<string> {
  const issuer = await ensureE2eIssuerRegistry();
  const keypair =
    options.keypair ??
    ({
      kid: issuer.kid,
      privateKey: issuer.privateKey,
      publicKey: issuer.privateKey,
      publicKeyB64: issuer.publicKeyB64,
    } as TestKeypair);

  const header: Record<string, unknown> = {
    alg: options.alg ?? "EdDSA",
    kid: options.kid ?? keypair.kid,
    typ: "JWT",
    ...options.header,
  };
  if (options.alg !== undefined) {
    header.alg = options.alg;
  }
  if (options.kid !== undefined) {
    header.kid = options.kid;
  }
  for (const field of options.omitHeaderFields ?? []) {
    delete header[field];
  }

  const payload: Record<string, unknown> = {
    ...defaultClaims(scenario),
    ...options.claims,
  };
  for (const field of options.omitClaims ?? []) {
    delete payload[field];
  }

  const token = await signJwt({
    header,
    payload,
    privateKey: keypair.privateKey,
  });

  if (options.signatureB64 !== undefined) {
    const parts = token.split(".");
    return `${parts[0]}.${parts[1]}.${options.signatureB64}`;
  }
  return token;
}

export async function ensureInstallationKeyActive(
  _installationId: string,
): Promise<void> {
  await ensureE2eIssuerRegistry();
}
