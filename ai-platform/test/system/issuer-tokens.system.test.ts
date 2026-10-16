/**
 * P3.2 — Issuer-key registry, issuer-token verification, tenant bindings (E2E-P3.2-01–08).
 */

import { env, SELF } from "cloudflare:test";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { createSoftwareAuthenticator } from "vendor-contracts/testkit";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  clearCapturedVendorEmails,
  count,
  encodeVendorAssertion,
  encodeVendorAttestation,
  GATEWAY_ORIGIN,
  getCapturedVendorEmails,
  getRequest,
  getVendorTestClockIso,
  mintVendorAccessJwt,
  queryOne,
  resetPlatformState,
  setTestClock,
  setupVendorHarness,
  vendorCall,
  VENDOR_OPERATOR_EMAIL,
  type VendorResultEnvelope,
} from "./harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;

/** Matches `ISSUER_ID` added to wrangler in T011. */
const ISSUER_ID =
  (env as { ISSUER_ID?: string }).ISSUER_ID ?? "issuer-test";

type SoftwareAuthenticator = Awaited<
  ReturnType<typeof createSoftwareAuthenticator>
>;

type IssuerKeyVendorMethod =
  | "registerIssuerKey"
  | "revokeIssuerKey"
  | "retireIssuerKey";

type IssuerKeyVendorCall = (
  method: IssuerKeyVendorMethod,
  args: Record<string, unknown>,
  opts?: {
    accessJwt?: string;
    assertion?: Record<string, unknown>;
  },
) => Promise<VendorResultEnvelope>;

const issuerKeyVendorCall = vendorCall as IssuerKeyVendorCall;

type IssuerKeyMaterial = {
  kid: string;
  privateKey: CryptoKey;
  publicKeyB64: string;
};

type IssuerTokenClaims = {
  iss?: string;
  aud?: string;
  sub?: string;
  org: string;
  branch?: string;
  role?: string;
  scopes?: string[];
  jti?: string;
  iat?: number;
  exp?: number;
  ver?: string;
};

function expectNoReceipt(envelope: VendorResultEnvelope): void {
  expect(envelope).not.toHaveProperty("receipt");
}

function parseDetailRow(detail: string): Record<string, unknown> {
  return JSON.parse(detail) as Record<string, unknown>;
}

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

function configCacheTtlMs(): number {
  const raw =
    (env as { CONFIG_CACHE_TTL_MS?: string }).CONFIG_CACHE_TTL_MS ?? "100";
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : 100;
}

async function tableCount(table: string): Promise<number> {
  const exists = await queryOne<{ ok: number }>(
    "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  if (!exists) {
    return 0;
  }
  return count(table);
}

async function nowSeconds(): Promise<number> {
  const iso = getVendorTestClockIso();
  if (iso) {
    return Math.floor(Date.parse(iso) / 1000);
  }
  return Math.floor(Date.now() / 1000);
}

async function generateIssuerKeyMaterial(): Promise<IssuerKeyMaterial> {
  const kid = crypto.randomUUID();
  const keyPair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const rawPublicKey = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  return {
    kid,
    privateKey: keyPair.privateKey,
    publicKeyB64: base64urlEncode(new Uint8Array(rawPublicKey)),
  };
}

async function mintIssuerToken(
  key: IssuerKeyMaterial,
  claims: IssuerTokenClaims,
): Promise<string> {
  const now = await nowSeconds();
  const payload = {
    iss: ISSUER_ID,
    aud: "ai-platform",
    sub: crypto.randomUUID(),
    branch: crypto.randomUUID(),
    role: "clinician",
    scopes: ["ai.access"],
    jti: crypto.randomUUID(),
    iat: now - 30,
    exp: now + 300,
    ver: "2",
    ...claims,
  };
  const header = { alg: "EdDSA", kid: key.kid, typ: "JWT" };
  const headerB64 = base64urlEncode(JSON.stringify(header));
  const payloadB64 = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    key.privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64urlEncode(new Uint8Array(signature))}`;
}

async function fetchCapabilities(token: string): Promise<Response> {
  return SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, {
      headers: {
        authorization: `Bearer ${token}`,
        "Aip-Contract-Version": "1",
      },
    }),
  );
}

async function expectCapabilitiesUnauthenticated(token: string): Promise<void> {
  const response = await fetchCapabilities(token);
  expect(response.status).toBe(401);
  const json = (await response.json()) as Record<string, unknown>;
  expect(json.code).toBe("unauthenticated");
}

async function issuerValidityWindow(): Promise<{
  notBefore: string;
  notAfter: string;
}> {
  const notBefore = getVendorTestClockIso() ?? new Date().toISOString();
  const notAfter = new Date(
    Date.parse(notBefore) + 365 * 24 * 60 * 60 * 1000,
  ).toISOString();
  return { notBefore, notAfter };
}

async function bootstrapIssuerRegistry(): Promise<{
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
}> {
  const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
  const { credentialId } = await bootstrapOperatorCredential(signerAuthenticator);
  return {
    signerCredentialId: credentialId,
    signerAuthenticator,
  };
}

async function registerIssuerKeyMaterial(input: {
  key: IssuerKeyMaterial;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
}): Promise<void> {
  const { notBefore, notAfter } = await issuerValidityWindow();
  const { envelope } = await registerIssuerKeyWithAssertion({
    kid: input.key.kid,
    publicKey: input.key.publicKeyB64,
    notBefore,
    notAfter,
    signerCredentialId: input.signerCredentialId,
    authenticator: input.signerAuthenticator,
  });
  expect(envelope.result).toBe("ok");
  expect(envelope.code).toBe("");
  expectNoReceipt(envelope);
}

async function operationForIssuerKidMethod(input: {
  op: "revokeIssuerKey" | "retireIssuerKey";
  kid: string;
  accessJwt: string;
  issuedAt?: string;
  actorEmail?: string;
}): Promise<Record<string, unknown>> {
  return {
    op: input.op,
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      kid: input.kid,
    },
    actor_email: input.actorEmail ?? VENDOR_OPERATOR_EMAIL,
    issued_at:
      input.issuedAt ??
      getVendorTestClockIso() ??
      new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function issuerKidVendorCall(input: {
  method: "revokeIssuerKey" | "retireIssuerKey";
  kid: string;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  accessJwt?: string;
}): Promise<VendorResultEnvelope> {
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const operation = await operationForIssuerKidMethod({
    op: input.method,
    kid: input.kid,
    accessJwt,
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
  return issuerKeyVendorCall(
    input.method,
    {
      contract_version: CONTRACT_VERSION,
      kid: input.kid,
      signer_credential_id: input.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function operationForRegisterIssuerKey(input: {
  kid: string;
  publicKey: string;
  notBefore: string;
  notAfter: string;
  accessJwt: string;
  issuedAt?: string;
  actorEmail?: string;
}): Promise<Record<string, unknown>> {
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
    actor_email: input.actorEmail ?? VENDOR_OPERATOR_EMAIL,
    issued_at:
      input.issuedAt ??
      getVendorTestClockIso() ??
      new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function bootstrapOperatorCredential(
  authenticator: SoftwareAuthenticator,
): Promise<{ credentialId: string; accessJwt: string }> {
  const credentialId = crypto.randomUUID();
  const attestation = encodeVendorAttestation(await authenticator.attest());
  const accessJwt = await mintVendorAccessJwt();
  const result = await vendorCall(
    "registerOperatorCredential",
    {
      contract_version: CONTRACT_VERSION,
      credential_id: credentialId,
      attestation,
    },
    { accessJwt },
  );
  expect(result.result).toBe("ok");
  const row = parseDetailRow(result.detail);
  await setTestClock(String(row.activates_at));
  return { credentialId, accessJwt };
}

async function registerIssuerKeyWithAssertion(input: {
  kid: string;
  publicKey: string;
  notBefore: string;
  notAfter: string;
  signerCredentialId: string;
  authenticator: SoftwareAuthenticator;
  accessJwt?: string;
}): Promise<{
  envelope: VendorResultEnvelope;
  operation: Record<string, unknown>;
}> {
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const operation = await operationForRegisterIssuerKey({
    kid: input.kid,
    publicKey: input.publicKey,
    notBefore: input.notBefore,
    notAfter: input.notAfter,
    accessJwt,
  });
  const assertion = encodeVendorAssertion(
    await input.authenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const envelope = await issuerKeyVendorCall(
    "registerIssuerKey",
    {
      contract_version: CONTRACT_VERSION,
      kid: input.kid,
      public_key: input.publicKey,
      not_before: input.notBefore,
      not_after: input.notAfter,
      signer_credential_id: input.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
  return { envelope, operation };
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  await setupVendorHarness();
});

beforeEach(async () => {
  await resetPlatformState();
  await setupVendorHarness();
});

describe("issuer tokens", () => {
  it("E2E-P3.2-08 AL-13 on issuer-key registration carries the decoded operation and kid", async () => {
    const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const { credentialId } = await bootstrapOperatorCredential(signerAuthenticator);

    const issuerAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const publicKey = encodeVendorAttestation(
      await issuerAuthenticator.attest(),
    ).public_key;
    const kid = crypto.randomUUID();
    const notBefore =
      getVendorTestClockIso() ?? new Date().toISOString();
    const notAfter = new Date(
      Date.parse(notBefore) + 365 * 24 * 60 * 60 * 1000,
    ).toISOString();

    const { envelope, operation } = await registerIssuerKeyWithAssertion({
      kid,
      publicKey,
      notBefore,
      notAfter,
      signerCredentialId: credentialId,
      authenticator: signerAuthenticator,
    });

    expect(envelope.result).toBe("ok");
    expect(envelope.code).toBe("");
    expectNoReceipt(envelope);

    const row = parseDetailRow(envelope.detail);
    expect(row.status).toBe("active");
    expect(row.kid).toBe(kid);
    expect(row.public_key).toBe(publicKey);

    const emails = getCapturedVendorEmails();
    expect(emails.length).toBeGreaterThanOrEqual(1);
    const body = JSON.parse(emails[emails.length - 1]!.text) as Record<
      string,
      unknown
    >;
    expect(body.code).toBe("AL-13");
    expect(body.kid).toBe(kid);
    expect(body.operation).toEqual(operation);
  });

  it("E2E-P3.2-01 Token from a registered kid for a new org with ver 2 authenticates; installation and binding epoch 1 are created; a second token resolves the same installation", async () => {
    const { signerCredentialId, signerAuthenticator } =
      await bootstrapIssuerRegistry();
    const issuerKey = await generateIssuerKeyMaterial();
    await registerIssuerKeyMaterial({
      key: issuerKey,
      signerCredentialId,
      signerAuthenticator,
    });

    const orgId = crypto.randomUUID();
    const token = await mintIssuerToken(issuerKey, { org: orgId });

    const first = await fetchCapabilities(token);
    expect(first.status).toBe(200);

    const installation = await queryOne<Record<string, unknown>>(
      "SELECT * FROM installation WHERE org_id = ?",
      [orgId],
    );
    expect(installation).not.toBeNull();
    expect(installation!.status).toBe("active");
    expect(installation!.display_name).toBe("");
    expect(installation!.region).toBe("");
    expect(installation!.enrolled_at).toBeTruthy();

    const binding = await queryOne<Record<string, unknown>>(
      "SELECT * FROM tenant_binding WHERE org_id = ?",
      [orgId],
    );
    expect(binding).not.toBeNull();
    expect(binding!.status).toBe("active");
    expect(binding!.epoch).toBe(1);
    expect(binding!.created_at).toBe(installation!.enrolled_at);
    expect(await tableCount("installation")).toBe(1);
    expect(await tableCount("tenant_binding")).toBe(1);

    const secondToken = await mintIssuerToken(issuerKey, { org: orgId });
    const second = await fetchCapabilities(secondToken);
    expect(second.status).toBe(200);

    const bindingAfter = await queryOne<Record<string, unknown>>(
      "SELECT * FROM tenant_binding WHERE org_id = ?",
      [orgId],
    );
    expect(bindingAfter!.installation_id).toBe(binding!.installation_id);
    expect(await tableCount("tenant_binding")).toBe(1);
  });

  it("E2E-P3.2-02 Unknown kid is 401 unauthenticated; a kid revoked through HP is rejected after one config-cache TTL", async () => {
    const { signerCredentialId, signerAuthenticator } =
      await bootstrapIssuerRegistry();
    const issuerKey = await generateIssuerKeyMaterial();
    await registerIssuerKeyMaterial({
      key: issuerKey,
      signerCredentialId,
      signerAuthenticator,
    });

    const unknownKidKey = await generateIssuerKeyMaterial();
    const unknownToken = await mintIssuerToken(unknownKidKey, {
      org: crypto.randomUUID(),
    });
    await expectCapabilitiesUnauthenticated(unknownToken);
    expect(await tableCount("installation")).toBe(0);
    expect(await tableCount("tenant_binding")).toBe(0);

    const orgId = crypto.randomUUID();
    const warmToken = await mintIssuerToken(issuerKey, { org: orgId });
    const warm = await fetchCapabilities(warmToken);
    expect(warm.status).toBe(200);

    const revoke = await issuerKidVendorCall({
      method: "revokeIssuerKey",
      kid: issuerKey.kid,
      signerCredentialId,
      signerAuthenticator,
    });
    expect(revoke.result).toBe("ok");
    expect(revoke.code).toBe("");
    expectNoReceipt(revoke);
    const revokedRow = parseDetailRow(revoke.detail);
    expect(revokedRow.status).toBe("revoked");

    const beforeTtl = await fetchCapabilities(
      await mintIssuerToken(issuerKey, { org: crypto.randomUUID() }),
    );
    expect(beforeTtl.status).toBe(200);

    const clockIso =
      getVendorTestClockIso() ?? new Date().toISOString();
    await setTestClock(
      new Date(Date.parse(clockIso) + configCacheTtlMs() + 1).toISOString(),
    );

    const afterTtl = await fetchCapabilities(
      await mintIssuerToken(issuerKey, { org: crypto.randomUUID() }),
    );
    expect(afterTtl.status).toBe(401);
    const afterJson = (await afterTtl.json()) as Record<string, unknown>;
    expect(afterJson.code).toBe("unauthenticated");
  });

  it("E2E-P3.2-03 aud abo or ai-platform-feed, lifetime 601 seconds, or ver 1 is 401 before any installation or tenant_binding write", async () => {
    const { signerCredentialId, signerAuthenticator } =
      await bootstrapIssuerRegistry();
    const issuerKey = await generateIssuerKeyMaterial();
    await registerIssuerKeyMaterial({
      key: issuerKey,
      signerCredentialId,
      signerAuthenticator,
    });

    const orgId = crypto.randomUUID();
    const now = await nowSeconds();
    const defects: IssuerTokenClaims[] = [
      { org: orgId, aud: "abo" },
      { org: orgId, aud: "ai-platform-feed" },
      { org: orgId, iat: now, exp: now + 601 },
      { org: orgId, ver: "1" },
    ];

    const installationsBefore = await tableCount("installation");
    const bindingsBefore = await tableCount("tenant_binding");

    for (const claims of defects) {
      const token = await mintIssuerToken(issuerKey, claims);
      await expectCapabilitiesUnauthenticated(token);
    }

    expect(await tableCount("installation")).toBe(installationsBefore);
    expect(await tableCount("tenant_binding")).toBe(bindingsBefore);
  });

  it("E2E-P3.2-04 Tokens of two active kids are accepted; a retiring kid is accepted until not_after and the tenant binding is unchanged", async () => {
    const { signerCredentialId, signerAuthenticator } =
      await bootstrapIssuerRegistry();
    const keyA = await generateIssuerKeyMaterial();
    const keyB = await generateIssuerKeyMaterial();
    await registerIssuerKeyMaterial({
      key: keyA,
      signerCredentialId,
      signerAuthenticator,
    });
    await registerIssuerKeyMaterial({
      key: keyB,
      signerCredentialId,
      signerAuthenticator,
    });

    const orgId = crypto.randomUUID();
    const tokenA = await mintIssuerToken(keyA, { org: orgId });
    expect((await fetchCapabilities(tokenA)).status).toBe(200);
    const tokenB = await mintIssuerToken(keyB, { org: crypto.randomUUID() });
    expect((await fetchCapabilities(tokenB)).status).toBe(200);

    const bindingBefore = await queryOne<Record<string, unknown>>(
      "SELECT epoch, installation_id, created_at FROM tenant_binding WHERE org_id = ?",
      [orgId],
    );
    expect(bindingBefore).not.toBeNull();

    const retire = await issuerKidVendorCall({
      method: "retireIssuerKey",
      kid: keyA.kid,
      signerCredentialId,
      signerAuthenticator,
    });
    expect(retire.result).toBe("ok");
    const retiringRow = parseDetailRow(retire.detail);
    expect(retiringRow.status).toBe("retiring");

    const retiringToken = await mintIssuerToken(keyA, { org: orgId });
    expect((await fetchCapabilities(retiringToken)).status).toBe(200);

    const bindingAfter = await queryOne<Record<string, unknown>>(
      "SELECT epoch, installation_id, created_at FROM tenant_binding WHERE org_id = ?",
      [orgId],
    );
    expect(bindingAfter!.epoch).toBe(bindingBefore!.epoch);
    expect(bindingAfter!.installation_id).toBe(bindingBefore!.installation_id);
    expect(bindingAfter!.created_at).toBe(bindingBefore!.created_at);
  });

  it("E2E-P3.2-05 The 51st new-org creation within 24 hours is 401 unauthenticated, inserts nothing, and raises AL-20", async () => {
    const windowStart =
      getVendorTestClockIso() ?? new Date().toISOString();
    await setTestClock(windowStart);

    const { signerCredentialId, signerAuthenticator } =
      await bootstrapIssuerRegistry();
    const issuerKey = await generateIssuerKeyMaterial();
    await registerIssuerKeyMaterial({
      key: issuerKey,
      signerCredentialId,
      signerAuthenticator,
    });

    clearCapturedVendorEmails();

    for (let index = 0; index < 50; index += 1) {
      const orgId = crypto.randomUUID();
      const token = await mintIssuerToken(issuerKey, { org: orgId });
      const response = await fetchCapabilities(token);
      expect(response.status).toBe(200);
    }

    expect(await count("tenant_binding", "epoch = 1")).toBe(50);

    const blockedToken = await mintIssuerToken(issuerKey, {
      org: crypto.randomUUID(),
    });
    await expectCapabilitiesUnauthenticated(blockedToken);
    expect(await count("tenant_binding", "epoch = 1")).toBe(50);

    const emails = getCapturedVendorEmails();
    expect(emails.length).toBeGreaterThanOrEqual(1);
    const alertBody = JSON.parse(emails[emails.length - 1]!.text) as Record<
      string,
      unknown
    >;
    expect(alertBody).toEqual({ code: "AL-20" });

    const platformAlert = await queryOne<{ code: string }>(
      "SELECT code FROM platform_alert WHERE code = ?",
      ["AL-20"],
    );
    expect(platformAlert?.code).toBe("AL-20");
  });

  it("E2E-P3.2-06 GET /v1/requests/{ref} with the owner org token is 200 and another org token is not found", async () => {
    const { signerCredentialId, signerAuthenticator } =
      await bootstrapIssuerRegistry();
    const issuerKey = await generateIssuerKeyMaterial();
    await registerIssuerKeyMaterial({
      key: issuerKey,
      signerCredentialId,
      signerAuthenticator,
    });

    const ownerOrgId = crypto.randomUUID();
    const otherOrgId = crypto.randomUUID();
    const ownerToken = await mintIssuerToken(issuerKey, { org: ownerOrgId });
    expect((await fetchCapabilities(ownerToken)).status).toBe(200);
    const otherToken = await mintIssuerToken(issuerKey, { org: otherOrgId });
    expect((await fetchCapabilities(otherToken)).status).toBe(200);

    const ownerBinding = await queryOne<{ installation_id: string }>(
      "SELECT installation_id FROM tenant_binding WHERE org_id = ?",
      [ownerOrgId],
    );
    expect(ownerBinding).not.toBeNull();

    const reference = "ABCD-EFGH";
    const requestId = crypto.randomUUID();
    const createdAt =
      getVendorTestClockIso() ?? new Date().toISOString();

    await env.DB.prepare(
      `INSERT INTO ai_request (
        request_id, request_reference, installation_id, actor_id, branch_id,
        capability_id, capability_version, prompt_artifact_hash, idempotency_key,
        trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
        payload_pointer, conversation_id, turn_ordinal
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL)`,
    )
      .bind(
        requestId,
        reference,
        ownerBinding!.installation_id,
        crypto.randomUUID(),
        crypto.randomUUID(),
        "clinic.visit_summary",
        "1.0.0",
        "prompt/p3-2-06@v1",
        `idem-${requestId}`,
        `trace-${requestId}`,
        "Completed",
        createdAt,
        createdAt,
        createdAt,
      )
      .run();

    const ownerGet = await getRequest(ownerToken, reference);
    expect(ownerGet.status).toBe(200);

    const otherGet = await getRequest(otherToken, reference);
    expect(otherGet.status).toBe(404);
  });

  it("E2E-P3.2-07 POST /control/installations/{id}/enroll is 404 and installation_key is gone", async () => {
    const installationId = crypto.randomUUID();
    const response = await SELF.fetch(
      new Request(
        `${GATEWAY_ORIGIN}/control/installations/${installationId}/enroll`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            org_id: crypto.randomUUID(),
            display_name: "P3.2 enroll removal",
            region: "us-east-1",
            plan: "standard",
            public_key: base64urlEncode(crypto.getRandomValues(new Uint8Array(32))),
            algorithm: "EdDSA",
            kid: crypto.randomUUID(),
          }),
        },
      ),
    );
    expect(response.status).toBe(404);

    const installationKeyTable = await queryOne<{ name: string }>(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ["installation_key"],
    );
    expect(installationKeyTable).toBeNull();
  });
});
