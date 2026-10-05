/**
 * P3.3 — Plan versions, paid-grant intake, coverage ledger (E2E-P3.3-01–12).
 */

import {
  env,
  runDurableObjectAlarm,
  runInDurableObject,
} from "cloudflare:test";
import {
  CHANNEL_VERSIONS,
  grantIdPaid,
  verifyReceiptSignature,
} from "vendor-contracts";
import { createAboGrantSigner, createSoftwareAuthenticator } from "vendor-contracts/testkit";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  count,
  encodeVendorAssertion,
  encodeVendorAttestation,
  getVendorTestClockIso,
  mintVendorAccessJwt,
  queryOne,
  queryAll,
  resetPlatformState,
  r2Exists,
  setTestClock,
  setupVendorHarness,
  getCapturedVendorEmails,
  clearCapturedVendorEmails,
  vendorCall,
  VENDOR_OPERATOR_EMAIL,
  type VendorResultEnvelope,
} from "./harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;

const PLAN_ID = "live-monthly";
const PLAN_VERSION = 1;
const PLAN_DISPLAY_NAME = "Live Monthly";
const PLAN_CAPABILITIES = ["clinic.visit_summary"];
const PLAN_MAX_COST_CLASS = 2;
const PLAN_CONCURRENCY_LIMIT = 4;
const PLAN_MAX_ALLOWANCE_PER_MONTH = 10_000;

const PLATFORM_RECEIPT_PUBLIC_KEY_B64URL =
  "GNzxZ6Gymues_aeJArGyb3wDESTOUJeqhuZBfTByni0";

type SoftwareAuthenticator = Awaited<
  ReturnType<typeof createSoftwareAuthenticator>
>;

type AboGrantSigner = Awaited<ReturnType<typeof createAboGrantSigner>>;

type CoverageVendorMethod =
  | "publishPlanVersion"
  | "registerServiceKey"
  | "revokeServiceKey"
  | "listServiceKeys"
  | "retirePlanVersion"
  | "grant"
  | "getCoverage"
  | "listGrants"
  | "readCoverageEvents";

type GrantResultEnvelope = VendorResultEnvelope & {
  result: string;
  receipt?: Record<string, unknown>;
};

const coverageVendorCall = vendorCall as (
  method: CoverageVendorMethod,
  args: Record<string, unknown>,
  opts?: {
    accessJwt?: string;
    assertion?: Record<string, unknown>;
  },
) => Promise<GrantResultEnvelope>;

type PaidGrantFixture = {
  orgId: string;
  grantId: string;
  envelope: Record<string, unknown>;
  aboKid: string;
  aboSignature: string;
  aboSigner: AboGrantSigner;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
};

type DoCoverageSnapshot = {
  termCount: number;
  clinicSeq: number | null;
  envelopeHash: string | null;
  activeStartsAt: string | null;
};

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

function base64urlDecode(value: string): Uint8Array {
  const padded =
    value.replace(/-/g, "+").replace(/_/g, "/") +
    "===".slice((value.length + 3) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function importPlatformReceiptPublicKey(): Promise<CryptoKey> {
  const raw = base64urlDecode(PLATFORM_RECEIPT_PUBLIC_KEY_B64URL);
  return crypto.subtle.importKey(
    "raw",
    raw,
    { name: "Ed25519" },
    false,
    ["verify"],
  );
}

async function serviceValidityWindow(): Promise<{
  notBefore: string;
  notAfter: string;
}> {
  const notBefore = getVendorTestClockIso() ?? new Date().toISOString();
  const notAfter = new Date(
    Date.parse(notBefore) + 365 * 24 * 60 * 60 * 1000,
  ).toISOString();
  return { notBefore, notAfter };
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
  const row = JSON.parse(result.detail) as Record<string, unknown>;
  await setTestClock(String(row.activates_at));
  return { credentialId, accessJwt };
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

async function operationForRetirePlanVersion(input: {
  accessJwt: string;
}): Promise<Record<string, unknown>> {
  return {
    op: "retirePlanVersion",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      plan_id: PLAN_ID,
      version: PLAN_VERSION,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function retirePlanVersionHp(input: {
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  accessJwt?: string;
}): Promise<VendorResultEnvelope> {
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const operation = await operationForRetirePlanVersion({ accessJwt });
  const assertion = encodeVendorAssertion(
    await input.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  return coverageVendorCall(
    "retirePlanVersion",
    {
      contract_version: CONTRACT_VERSION,
      plan_id: PLAN_ID,
      version: PLAN_VERSION,
      signer_credential_id: input.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function publishPlanVersionHp(input: {
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  accessJwt?: string;
}): Promise<VendorResultEnvelope> {
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const operation = await operationForPublishPlanVersion({ accessJwt });
  const assertion = encodeVendorAssertion(
    await input.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  return coverageVendorCall(
    "publishPlanVersion",
    {
      contract_version: CONTRACT_VERSION,
      plan_id: PLAN_ID,
      version: PLAN_VERSION,
      display_name: PLAN_DISPLAY_NAME,
      capabilities: PLAN_CAPABILITIES,
      max_cost_class: PLAN_MAX_COST_CLASS,
      concurrency_limit: PLAN_CONCURRENCY_LIMIT,
      max_allowance_per_month: PLAN_MAX_ALLOWANCE_PER_MONTH,
      signer_credential_id: input.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function operationForRegisterServiceKey(input: {
  kid: string;
  publicKey: string;
  notBefore: string;
  notAfter: string;
  accessJwt: string;
}): Promise<Record<string, unknown>> {
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
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function registerServiceKeyHp(input: {
  signer: AboGrantSigner;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  accessJwt?: string;
}): Promise<VendorResultEnvelope> {
  const rawPublicKey = await crypto.subtle.exportKey("raw", input.signer.publicKey);
  const publicKeyB64 = base64urlEncode(new Uint8Array(rawPublicKey));
  const { notBefore, notAfter } = await serviceValidityWindow();
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const operation = await operationForRegisterServiceKey({
    kid: input.signer.kid,
    publicKey: publicKeyB64,
    notBefore,
    notAfter,
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
  return coverageVendorCall(
    "registerServiceKey",
    {
      contract_version: CONTRACT_VERSION,
      kid: input.signer.kid,
      public_key: publicKeyB64,
      not_before: notBefore,
      not_after: notAfter,
      signer_credential_id: input.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function operationForRevokeServiceKey(input: {
  kid: string;
  accessJwt: string;
}): Promise<Record<string, unknown>> {
  return {
    op: "revokeServiceKey",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      kid: input.kid,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function revokeServiceKeyHp(input: {
  kid: string;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  accessJwt?: string;
}): Promise<VendorResultEnvelope> {
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const operation = await operationForRevokeServiceKey({
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
  return coverageVendorCall(
    "revokeServiceKey",
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

async function expectNoTenantBinding(orgId: string): Promise<void> {
  expect(await count("tenant_binding", "org_id = ?", [orgId])).toBe(0);
}

async function bootstrapSignedGrantWithoutPublishedPlan(
  clockIso = "2026-01-15T10:00:00.000Z",
): Promise<{
  orgId: string;
  grantId: string;
  envelope: Record<string, unknown>;
  aboKid: string;
  aboSignature: string;
  aboSigner: AboGrantSigner;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
}> {
  await setTestClock(clockIso);
  const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
  const { credentialId: signerCredentialId } =
    await bootstrapOperatorCredential(signerAuthenticator);

  const aboSigner = await createAboGrantSigner();
  const registerKey = await registerServiceKeyHp({
    signer: aboSigner,
    signerCredentialId,
    signerAuthenticator,
  });
  expect(registerKey.result).toBe("ok");

  const orgId = crypto.randomUUID();
  const paymentRef = crypto.randomUUID().replace(/-/g, "");
  const grantId = await grantIdPaid(paymentRef);
  const envelope = await buildPaidGrantEnvelope({ orgId, grantId });
  const aboSignature = await aboSigner.sign(envelope);

  return {
    orgId,
    grantId,
    envelope,
    aboKid: aboSigner.kid,
    aboSignature,
    aboSigner,
    signerCredentialId,
    signerAuthenticator,
  };
}

async function buildPaidGrantEnvelope(input: {
  orgId: string;
  grantId: string;
  allowanceCredits?: number;
}): Promise<Record<string, unknown>> {
  const paidAt = getVendorTestClockIso() ?? new Date().toISOString();
  const paymentRef = crypto.randomUUID().replace(/-/g, "");
  return {
    contract_version: CONTRACT_VERSION,
    grant_id: input.grantId,
    org_id: input.orgId,
    kind: "term",
    placement: "queue",
    source: {
      kind: "paid",
      ref: paymentRef,
    },
    plan: {
      plan_id: PLAN_ID,
      plan_version: PLAN_VERSION,
    },
    duration: {
      unit: "month",
      count: 1,
    },
    allowance_credits: input.allowanceCredits ?? 10_000,
    grace: {
      days: 7,
      cap_rule: "proportional",
    },
    paid_at: paidAt,
    evidence: {
      content_sha256: paymentRef,
      approvals: [
        {
          credential_id: "cred-001",
          assertion: "stub",
        },
      ],
    },
  };
}

async function grantPaid(input: {
  envelope: Record<string, unknown>;
  aboKid: string;
  aboSignature: string;
}): Promise<GrantResultEnvelope> {
  return coverageVendorCall("grant", {
    contract_version: CONTRACT_VERSION,
    envelope: input.envelope,
    abo_kid: input.aboKid,
    abo_signature: input.aboSignature,
  });
}

async function getCoverageForOrg(orgId: string): Promise<VendorResultEnvelope> {
  return coverageVendorCall("getCoverage", {
    contract_version: CONTRACT_VERSION,
    org_id: orgId,
  });
}

type DoTermRow = {
  state: string;
  starts_at: string | null;
  ends_at: string | null;
};

async function readDoTerms(installationId: string): Promise<DoTermRow[]> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect<DoTermRow>(
      state,
      "SELECT state, starts_at, ends_at FROM term",
    ),
  );
}

async function readActiveTermTiming(
  installationId: string,
): Promise<{ starts_at: string | null; ends_at: string | null } | null> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ starts_at: string | null; ends_at: string | null }>(
        state,
        "SELECT starts_at, ends_at FROM term WHERE state = 'active' LIMIT 1",
      ),
  );
  return rows[0] ?? null;
}

async function readActiveTermPlanSnapshot(
  installationId: string,
): Promise<Record<string, unknown> | null> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ plan_snapshot: string }>(
        state,
        "SELECT plan_snapshot FROM term WHERE state = 'active' LIMIT 1",
      ),
  );
  const raw = rows[0]?.plan_snapshot;
  if (!raw) {
    return null;
  }
  return JSON.parse(raw) as Record<string, unknown>;
}

const DO_RPC_URL = "https://quota-do.internal/rpc";
const PLATFORM_DO_CONTRACT_VERSION = CHANNEL_VERSIONS.platformDo;

async function fetchGatewayObjectRpc(
  installationId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  return quotaDoStub(installationId).fetch(DO_RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function inspectGatewayObjectState(
  installationId: string,
): Promise<unknown> {
  const response = await fetchGatewayObjectRpc(installationId, {
    contract_version: PLATFORM_DO_CONTRACT_VERSION,
    kind: "inspect",
  });
  expect(response.ok).toBe(true);
  const body = (await response.json()) as { state: unknown };
  return body.state;
}

function withDurationScale<T>(
  scale: string | undefined,
  fn: () => Promise<T>,
): Promise<T> {
  const envWithScale = env as { DURATION_SCALE?: string };
  const previous = envWithScale.DURATION_SCALE;
  if (scale === undefined) {
    delete envWithScale.DURATION_SCALE;
  } else {
    envWithScale.DURATION_SCALE = scale;
  }
  return fn().finally(() => {
    if (previous === undefined) {
      delete envWithScale.DURATION_SCALE;
    } else {
      envWithScale.DURATION_SCALE = previous;
    }
  });
}

async function installationIdForOrg(orgId: string): Promise<string> {
  const binding = await queryOne<{ installation_id: string }>(
    "SELECT installation_id FROM tenant_binding WHERE org_id = ? AND status = 'active'",
    [orgId],
  );
  if (!binding?.installation_id) {
    throw new Error(`no active binding for org ${orgId}`);
  }
  return binding.installation_id;
}

function quotaDoStub(installationId: string) {
  return env.DO.get(env.DO.idFromName(installationId));
}

function sqlSelect<T extends Record<string, unknown>>(
  state: DurableObjectState,
  query: string,
): T[] {
  const storage = state.storage as DurableObjectStorage & {
    sql?: { exec: (q: string) => Iterable<T> };
  };
  if (!storage.sql) {
    return [];
  }
  return [...storage.sql.exec(query)];
}

async function readDoCoverageSnapshot(
  installationId: string,
): Promise<DoCoverageSnapshot> {
  const stub = quotaDoStub(installationId);
  return runInDurableObject(stub, async (_instance, state) => {
    const terms = sqlSelect<{ state: string; starts_at: string | null }>(
      state,
      "SELECT state, starts_at FROM term",
    );
    const hotRows = sqlSelect<{ clinic_seq: number }>(
      state,
      "SELECT clinic_seq FROM hot LIMIT 1",
    );
    const grantRows = sqlSelect<{ envelope_sha256: string }>(
      state,
      "SELECT envelope_sha256 FROM grant LIMIT 1",
    );
    const active = terms.find((row) => row.state === "active");
    return {
      termCount: terms.length,
      clinicSeq: hotRows[0]?.clinic_seq ?? null,
      envelopeHash: grantRows[0]?.envelope_sha256 ?? null,
      activeStartsAt: active?.starts_at ?? null,
    };
  });
}

async function grantLedgerCount(grantId: string): Promise<number> {
  const exists = await queryOne<{ ok: number }>(
    "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = 'grant_ledger'",
  );
  if (!exists) {
    return 0;
  }
  return count("grant_ledger", "grant_id = ?", [grantId]);
}

type CoverageEventRow = {
  feed_seq: number;
  clinic_seq: number;
  kind: string;
  org_id: string;
  event_id: string;
};

async function listCoverageEventsForOrg(orgId: string): Promise<CoverageEventRow[]> {
  const exists = await queryOne<{ ok: number }>(
    "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = 'coverage_event'",
  );
  if (!exists) {
    return [];
  }
  return queryAll<CoverageEventRow>(
    "SELECT feed_seq, clinic_seq, kind, org_id, event_id FROM coverage_event WHERE org_id = ? ORDER BY feed_seq ASC",
    [orgId],
  );
}

async function coverageMirrorForInstallation(
  installationId: string,
): Promise<Record<string, unknown> | null> {
  const exists = await queryOne<{ ok: number }>(
    "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = 'coverage_mirror'",
  );
  if (!exists) {
    return null;
  }
  return queryOne<Record<string, unknown>>(
    "SELECT * FROM coverage_mirror WHERE installation_id = ?",
    [installationId],
  );
}

async function readCoverageEventsPage(
  after: number,
  limit: number,
): Promise<VendorResultEnvelope> {
  return coverageVendorCall("readCoverageEvents", {
    contract_version: CONTRACT_VERSION,
    after,
    limit,
  });
}

async function grantPaidForOrg(
  fixture: Pick<PaidGrantFixture, "orgId" | "aboKid" | "aboSigner">,
): Promise<GrantResultEnvelope> {
  const paymentRef = crypto.randomUUID().replace(/-/g, "");
  const grantId = await grantIdPaid(paymentRef);
  const envelope = await buildPaidGrantEnvelope({
    orgId: fixture.orgId,
    grantId,
  });
  const aboSignature = await fixture.aboSigner.sign(envelope);
  return grantPaid({
    envelope,
    aboKid: fixture.aboKid,
    aboSignature,
  });
}

async function bootstrapPaidGrantFixture(
  clockIso = "2026-01-15T10:00:00.000Z",
): Promise<PaidGrantFixture> {
  await setTestClock(clockIso);
  const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
  const { credentialId: signerCredentialId } =
    await bootstrapOperatorCredential(signerAuthenticator);

  const publish = await publishPlanVersionHp({
    signerCredentialId,
    signerAuthenticator,
  });
  expect(publish.result).toBe("ok");

  const aboSigner = await createAboGrantSigner();
  const registerKey = await registerServiceKeyHp({
    signer: aboSigner,
    signerCredentialId,
    signerAuthenticator,
  });
  expect(registerKey.result).toBe("ok");

  const orgId = crypto.randomUUID();
  const paymentRef = crypto.randomUUID().replace(/-/g, "");
  const grantId = await grantIdPaid(paymentRef);
  const envelope = await buildPaidGrantEnvelope({ orgId, grantId });
  const aboSignature = await aboSigner.sign(envelope);

  return {
    orgId,
    grantId,
    envelope,
    aboKid: aboSigner.kid,
    aboSignature,
    aboSigner,
    signerCredentialId,
    signerAuthenticator,
  };
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  await setupVendorHarness();
});

beforeEach(async () => {
  await resetPlatformState();
  await setupVendorHarness();
});

describe("paid grant coverage", () => {
  it("E2E-P3.3-01 Publish plan v1 then a paid grant for a new org is applied, the receipt verifies, and the term is active", async () => {
    const clockIso = "2026-01-15T10:00:00.000Z";
    const fixture = await bootstrapPaidGrantFixture(clockIso);

    const applied = await grantPaid({
      envelope: fixture.envelope,
      aboKid: fixture.aboKid,
      aboSignature: fixture.aboSignature,
    });
    expect(applied.result).toBe("applied");
    expect(applied.receipt).toBeDefined();

    const platformKey = await importPlatformReceiptPublicKey();
    expect(
      await verifyReceiptSignature({
        receipt: applied.receipt,
        publicKey: platformKey,
      }),
    ).toBe(true);

    const installationId = await installationIdForOrg(fixture.orgId);
    const snapshot = await readDoCoverageSnapshot(installationId);
    expect(snapshot.activeStartsAt).toBe(clockIso);
    const activeTerms = await runInDurableObject(
      quotaDoStub(installationId),
      async (_instance, state) =>
        sqlSelect<{ state: string }>(state, "SELECT state FROM term"),
    );
    expect(activeTerms.some((row) => row.state === "active")).toBe(true);
  });

  it("E2E-P3.3-02 The same grant resent is already_applied with the identical receipt and one ledger row", async () => {
    const fixture = await bootstrapPaidGrantFixture();

    const first = await grantPaid({
      envelope: fixture.envelope,
      aboKid: fixture.aboKid,
      aboSignature: fixture.aboSignature,
    });
    expect(first.result).toBe("applied");
    expect(first.receipt).toBeDefined();

    const second = await grantPaid({
      envelope: fixture.envelope,
      aboKid: fixture.aboKid,
      aboSignature: fixture.aboSignature,
    });
    expect(second.result).toBe("already_applied");
    expect(second.receipt).toEqual(first.receipt);

    const installationId = await installationIdForOrg(fixture.orgId);
    await runDurableObjectAlarm(quotaDoStub(installationId));

    expect(await grantLedgerCount(fixture.grantId)).toBe(1);
  });

  it("E2E-P3.3-03 The same grant_id with a changed allowance is conflict and nothing changes", async () => {
    const fixture = await bootstrapPaidGrantFixture();

    const first = await grantPaid({
      envelope: fixture.envelope,
      aboKid: fixture.aboKid,
      aboSignature: fixture.aboSignature,
    });
    expect(first.result).toBe("applied");

    const installationId = await installationIdForOrg(fixture.orgId);
    const before = await readDoCoverageSnapshot(installationId);

    const mutatedEnvelope = structuredClone(fixture.envelope) as Record<
      string,
      unknown
    >;
    mutatedEnvelope.allowance_credits = 9_000;
    const mutatedSignature = await fixture.aboSigner.sign(mutatedEnvelope);

    const conflict = await grantPaid({
      envelope: mutatedEnvelope,
      aboKid: fixture.aboKid,
      aboSignature: mutatedSignature,
    });
    expect(conflict.result).toBe("conflict");
    expect(conflict).not.toHaveProperty("receipt");

    const after = await readDoCoverageSnapshot(installationId);
    expect(after.termCount).toBe(before.termCount);
    expect(after.clinicSeq).toBe(before.clinicSeq);
    expect(after.envelopeHash).toBe(before.envelopeHash);
  });

  it("E2E-P3.3-04 A second paid grant is queued without dates and getCoverage shows queued_count 1 and coverage_through extended", async () => {
    const fixture = await bootstrapPaidGrantFixture();

    const first = await grantPaid({
      envelope: fixture.envelope,
      aboKid: fixture.aboKid,
      aboSignature: fixture.aboSignature,
    });
    expect(first.result).toBe("applied");

    const paymentRef = crypto.randomUUID().replace(/-/g, "");
    const secondGrantId = await grantIdPaid(paymentRef);
    const secondEnvelope = await buildPaidGrantEnvelope({
      orgId: fixture.orgId,
      grantId: secondGrantId,
    });
    const secondSignature = await fixture.aboSigner.sign(secondEnvelope);
    const second = await grantPaid({
      envelope: secondEnvelope,
      aboKid: fixture.aboKid,
      aboSignature: secondSignature,
    });
    expect(second.result).toBe("applied");

    const installationId = await installationIdForOrg(fixture.orgId);
    const terms = await readDoTerms(installationId);
    const active = terms.find((row) => row.state === "active");
    expect(active?.ends_at).toBeTruthy();

    const queuedTerms = terms.filter((row) => row.state === "queued");
    expect(queuedTerms).toHaveLength(1);
    expect(queuedTerms[0]?.starts_at).toBeNull();
    expect(queuedTerms[0]?.ends_at).toBeNull();

    const coverage = await getCoverageForOrg(fixture.orgId);
    expect(coverage.result).toBe("ok");
    expect(coverage.code).toBe("");
    expect(coverage.receipt).toBeUndefined();

    const detail = JSON.parse(coverage.detail) as {
      snapshot: {
        queued_count: number;
        coverage_through: string;
      };
    };
    expect(detail.snapshot.queued_count).toBe(1);
    expect(
      Date.parse(detail.snapshot.coverage_through) >
      Date.parse(String(active!.ends_at)),
    ).toBe(true);
  });

  it("E2E-P3.3-05 An unregistered signing kid is transient unknown_kid and a revoked kid is rejected bad_signature", async () => {
    const fixture = await bootstrapPaidGrantFixture();
    const unknownSigner = await createAboGrantSigner();
    const unknownSignature = await unknownSigner.sign(fixture.envelope);

    const unknownKid = await grantPaid({
      envelope: fixture.envelope,
      aboKid: unknownSigner.kid,
      aboSignature: unknownSignature,
    });
    expect(unknownKid.result).toBe("transient");
    expect(unknownKid.code).toBe("");
    expect(unknownKid.detail).toBe("unknown_kid");
    expect(unknownKid.receipt).toBeUndefined();
    await expectNoTenantBinding(fixture.orgId);

    const revoke = await revokeServiceKeyHp({
      kid: fixture.aboKid,
      signerCredentialId: fixture.signerCredentialId,
      signerAuthenticator: fixture.signerAuthenticator,
    });
    expect(revoke.result).toBe("ok");

    const revokedKey = await grantPaid({
      envelope: fixture.envelope,
      aboKid: fixture.aboKid,
      aboSignature: fixture.aboSignature,
    });
    expect(revokedKey.result).toBe("rejected");
    expect(revokedKey.code).toBe("bad_signature");
    expect(revokedKey.receipt).toBeUndefined();
    await expectNoTenantBinding(fixture.orgId);
  });

  it("E2E-P3.3-06 Unpublished plan, allowance or grace over the bound, paid unit day, and placement immediate are refused", async () => {
    const unpublished = await bootstrapSignedGrantWithoutPublishedPlan();
    const planNotPublished = await grantPaid({
      envelope: unpublished.envelope,
      aboKid: unpublished.aboKid,
      aboSignature: unpublished.aboSignature,
    });
    expect(planNotPublished.result).toBe("rejected");
    expect(planNotPublished.code).toBe("plan_not_published");
    expect(planNotPublished.receipt).toBeUndefined();
    await expectNoTenantBinding(unpublished.orgId);

    const fixture = await bootstrapPaidGrantFixture();

    const overAllowanceEnvelope = structuredClone(fixture.envelope) as Record<
      string,
      unknown
    >;
    overAllowanceEnvelope.allowance_credits = PLAN_MAX_ALLOWANCE_PER_MONTH + 1;
    const overAllowanceOrg = crypto.randomUUID();
    overAllowanceEnvelope.org_id = overAllowanceOrg;
    const overAllowanceGrantId = await grantIdPaid(
      crypto.randomUUID().replace(/-/g, ""),
    );
    overAllowanceEnvelope.grant_id = overAllowanceGrantId;
    const overAllowanceSignature =
      await fixture.aboSigner.sign(overAllowanceEnvelope);
    const exceedsAllowance = await grantPaid({
      envelope: overAllowanceEnvelope,
      aboKid: fixture.aboKid,
      aboSignature: overAllowanceSignature,
    });
    expect(exceedsAllowance.result).toBe("rejected");
    expect(exceedsAllowance.code).toBe("exceeds_plan_bound");
    expect(exceedsAllowance.receipt).toBeUndefined();
    await expectNoTenantBinding(overAllowanceOrg);

    const graceEnvelope = structuredClone(fixture.envelope) as Record<
      string,
      unknown
    >;
    graceEnvelope.grace = { days: 8, cap_rule: "proportional" };
    const graceOrg = crypto.randomUUID();
    graceEnvelope.org_id = graceOrg;
    graceEnvelope.grant_id = await grantIdPaid(
      crypto.randomUUID().replace(/-/g, ""),
    );
    const graceSignature = await fixture.aboSigner.sign(graceEnvelope);
    const exceedsGrace = await grantPaid({
      envelope: graceEnvelope,
      aboKid: fixture.aboKid,
      aboSignature: graceSignature,
    });
    expect(exceedsGrace.result).toBe("rejected");
    expect(exceedsGrace.code).toBe("exceeds_plan_bound");
    expect(exceedsGrace.receipt).toBeUndefined();
    await expectNoTenantBinding(graceOrg);

    const dayUnitEnvelope = structuredClone(fixture.envelope) as Record<
      string,
      unknown
    >;
    dayUnitEnvelope.duration = { unit: "day", count: 1 };
    const dayUnitOrg = crypto.randomUUID();
    dayUnitEnvelope.org_id = dayUnitOrg;
    dayUnitEnvelope.grant_id = await grantIdPaid(
      crypto.randomUUID().replace(/-/g, ""),
    );
    const dayUnitSignature = await fixture.aboSigner.sign(dayUnitEnvelope);
    const unitDay = await grantPaid({
      envelope: dayUnitEnvelope,
      aboKid: fixture.aboKid,
      aboSignature: dayUnitSignature,
    });
    expect(unitDay.result).toBe("rejected");
    expect(unitDay.code).toBe("unit_not_allowed");
    expect(unitDay.receipt).toBeUndefined();
    await expectNoTenantBinding(dayUnitOrg);

    const immediateEnvelope = structuredClone(fixture.envelope) as Record<
      string,
      unknown
    >;
    immediateEnvelope.placement = "immediate";
    const immediateOrg = crypto.randomUUID();
    immediateEnvelope.org_id = immediateOrg;
    immediateEnvelope.grant_id = await grantIdPaid(
      crypto.randomUUID().replace(/-/g, ""),
    );
    const immediateSignature =
      await fixture.aboSigner.sign(immediateEnvelope);
    const placementImmediate = await grantPaid({
      envelope: immediateEnvelope,
      aboKid: fixture.aboKid,
      aboSignature: immediateSignature,
    });
    expect(placementImmediate.result).toBe("rejected");
    expect(placementImmediate.code).toBe("placement_not_supported");
    expect(placementImmediate.receipt).toBeUndefined();
    await expectNoTenantBinding(immediateOrg);
  });

  it("E2E-P3.3-07 After the alarm, coverage events, the ledger, the mirror, and R2 exist, and readCoverageEvents pages by feed_seq", async () => {
    const fixture = await bootstrapPaidGrantFixture();

    const applied = await grantPaid({
      envelope: fixture.envelope,
      aboKid: fixture.aboKid,
      aboSignature: fixture.aboSignature,
    });
    expect(applied.result).toBe("applied");

    const installationId = await installationIdForOrg(fixture.orgId);
    await runDurableObjectAlarm(quotaDoStub(installationId));

    const events = await listCoverageEventsForOrg(fixture.orgId);
    expect(events.length).toBeGreaterThan(0);
    for (let index = 1; index < events.length; index += 1) {
      expect(events[index]!.clinic_seq).toBeGreaterThan(
        events[index - 1]!.clinic_seq,
      );
    }

    expect(await grantLedgerCount(fixture.grantId)).toBe(1);

    const mirror = await coverageMirrorForInstallation(installationId);
    expect(mirror).not.toBeNull();
    expect(mirror?.org_id).toBe(fixture.orgId);

    expect(await r2Exists(`grant-ledger/${fixture.grantId}.ndjson`)).toBe(true);

    const page = await readCoverageEventsPage(0, 200);
    expect(page.result).toBe("ok");
    expect(page.code).toBe("");
    expect(page.receipt).toBeUndefined();

    const detail = JSON.parse(page.detail) as {
      events: Array<{ feed_seq: number; kind: string }>;
    };
    const feedSeqs = detail.events.map((event) => event.feed_seq);
    expect(feedSeqs).toEqual(events.map((event) => event.feed_seq));
    for (let index = 1; index < feedSeqs.length; index += 1) {
      expect(feedSeqs[index]!).toBeGreaterThan(feedSeqs[index - 1]!);
    }
  });

  it("E2E-P3.3-08 AL-11 email per grant carries the decoded operation and org, and the fourth paid grant within 24 hours raises AL-17", async () => {
    const fixture = await bootstrapPaidGrantFixture();

    const first = await grantPaid({
      envelope: fixture.envelope,
      aboKid: fixture.aboKid,
      aboSignature: fixture.aboSignature,
    });
    expect(first.result).toBe("applied");

    const installationId = await installationIdForOrg(fixture.orgId);
    clearCapturedVendorEmails();
    await runDurableObjectAlarm(quotaDoStub(installationId));

    const afterFirstAlarm = getCapturedVendorEmails();
    expect(afterFirstAlarm.length).toBeGreaterThanOrEqual(1);
    const al11Body = JSON.parse(afterFirstAlarm[0]!.text) as Record<
      string,
      unknown
    >;
    expect(al11Body).toEqual({
      code: "AL-11",
      org_id: fixture.orgId,
      operation: {
        op: "grant",
        params: fixture.envelope,
      },
    });

    const second = await grantPaidForOrg(fixture);
    expect(second.result).toBe("applied");
    const third = await grantPaidForOrg(fixture);
    expect(third.result).toBe("applied");

    clearCapturedVendorEmails();
    const fourth = await grantPaidForOrg(fixture);
    expect(fourth.result).toBe("applied");

    await runDurableObjectAlarm(quotaDoStub(installationId));

    const afterFourthAlarm = getCapturedVendorEmails();
    const al17Bodies = afterFourthAlarm
      .map((email) => JSON.parse(email.text) as Record<string, unknown>)
      .filter((body) => body.code === "AL-17");
    expect(al17Bodies.length).toBeGreaterThanOrEqual(1);
    expect(al17Bodies.some((body) => body.org_id === fixture.orgId)).toBe(true);
  });

  it("E2E-P3.3-09 A grant at 31 January 10:00 ends 28 February 10:00, or 29 February in a leap year, and the staging scale makes a month 30 minutes", async () => {
    const jan31NonLeap = "2026-01-31T10:00:00.000Z";
    const fixtureNonLeap = await bootstrapPaidGrantFixture(jan31NonLeap);
    const appliedNonLeap = await grantPaid({
      envelope: fixtureNonLeap.envelope,
      aboKid: fixtureNonLeap.aboKid,
      aboSignature: fixtureNonLeap.aboSignature,
    });
    expect(appliedNonLeap.result).toBe("applied");

    const installationNonLeap = await installationIdForOrg(fixtureNonLeap.orgId);
    const timingNonLeap = await readActiveTermTiming(installationNonLeap);
    expect(timingNonLeap?.starts_at).toBe(jan31NonLeap);
    expect(timingNonLeap?.ends_at).toBe("2026-02-28T10:00:00.000Z");

    const jan31Leap = "2024-01-31T10:00:00.000Z";
    const fixtureLeap = await bootstrapPaidGrantFixture(jan31Leap);
    const appliedLeap = await grantPaid({
      envelope: fixtureLeap.envelope,
      aboKid: fixtureLeap.aboKid,
      aboSignature: fixtureLeap.aboSignature,
    });
    expect(appliedLeap.result).toBe("applied");

    const installationLeap = await installationIdForOrg(fixtureLeap.orgId);
    const timingLeap = await readActiveTermTiming(installationLeap);
    expect(timingLeap?.starts_at).toBe(jan31Leap);
    expect(timingLeap?.ends_at).toBe("2024-02-29T10:00:00.000Z");

    const stagingStart = "2026-03-01T12:00:00.000Z";
    const fixtureStaging = await bootstrapPaidGrantFixture(stagingStart);
    const appliedStaging = await withDurationScale("staging", () =>
      grantPaid({
        envelope: fixtureStaging.envelope,
        aboKid: fixtureStaging.aboKid,
        aboSignature: fixtureStaging.aboSignature,
      }),
    );
    expect(appliedStaging.result).toBe("applied");

    const installationStaging = await installationIdForOrg(fixtureStaging.orgId);
    const timingStaging = await readActiveTermTiming(installationStaging);
    expect(timingStaging?.starts_at).toBe(stagingStart);
    expect(timingStaging?.ends_at).toBe("2026-03-01T12:30:00.000Z");
  });

  it("E2E-P3.3-10 retirePlanVersion refuses the next grant on that version and the existing term keeps its snapshot", async () => {
    const fixture = await bootstrapPaidGrantFixture();

    const applied = await grantPaid({
      envelope: fixture.envelope,
      aboKid: fixture.aboKid,
      aboSignature: fixture.aboSignature,
    });
    expect(applied.result).toBe("applied");

    const installationId = await installationIdForOrg(fixture.orgId);
    const snapshotBefore = await readActiveTermPlanSnapshot(installationId);
    expect(snapshotBefore).not.toBeNull();

    const retired = await retirePlanVersionHp({
      signerCredentialId: fixture.signerCredentialId,
      signerAuthenticator: fixture.signerAuthenticator,
    });
    expect(retired.result).toBe("ok");
    expect(retired.code).toBe("");
    expect(retired.receipt).toBeUndefined();

    const paymentRef = crypto.randomUUID().replace(/-/g, "");
    const nextGrantId = await grantIdPaid(paymentRef);
    const nextEnvelope = await buildPaidGrantEnvelope({
      orgId: fixture.orgId,
      grantId: nextGrantId,
    });
    const nextSignature = await fixture.aboSigner.sign(nextEnvelope);
    const refused = await grantPaid({
      envelope: nextEnvelope,
      aboKid: fixture.aboKid,
      aboSignature: nextSignature,
    });
    expect(refused.result).toBe("rejected");
    expect(refused.code).toBe("plan_not_published");
    expect(refused.receipt).toBeUndefined();

    const snapshotAfter = await readActiveTermPlanSnapshot(installationId);
    expect(snapshotAfter).toEqual(snapshotBefore);
  });

  it("E2E-P3.3-11 A Worker to DO RPC with the current contract version is accepted and the answer echoes it", async () => {
    const installationId = crypto.randomUUID();
    const response = await fetchGatewayObjectRpc(installationId, {
      contract_version: PLATFORM_DO_CONTRACT_VERSION,
      kind: "inspect",
    });
    expect(response.ok).toBe(true);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.contract_version).toBe(PLATFORM_DO_CONTRACT_VERSION);
    expect(body.kind).toBe("inspect");
  });

  it("E2E-P3.3-12 A Worker to DO RPC with contract_version missing or 2 is rejected contract_version_unsupported before any write", async () => {
    const installationId = crypto.randomUUID();

    const stateBefore = await inspectGatewayObjectState(installationId);

    const missingVersion = await fetchGatewayObjectRpc(installationId, {
      kind: "inspect",
    });
    expect(missingVersion.ok).toBe(true);
    const missingBody = (await missingVersion.json()) as Record<string, unknown>;
    expect(missingBody.result).toBe("rejected");
    expect(missingBody.code).toBe("contract_version_unsupported");
    expect(missingBody.accepted_versions).toEqual([0, 1]);
    expect(missingBody.contract_version).toBe(PLATFORM_DO_CONTRACT_VERSION);

    const unsupportedVersion = await fetchGatewayObjectRpc(installationId, {
      contract_version: 2,
      kind: "inspect",
    });
    expect(unsupportedVersion.ok).toBe(true);
    const unsupportedBody = (await unsupportedVersion.json()) as Record<
      string,
      unknown
    >;
    expect(unsupportedBody.result).toBe("rejected");
    expect(unsupportedBody.code).toBe("contract_version_unsupported");
    expect(unsupportedBody.accepted_versions).toEqual([0, 1]);
    expect(unsupportedBody.contract_version).toBe(PLATFORM_DO_CONTRACT_VERSION);

    const stateAfter = await inspectGatewayObjectState(installationId);
    expect(stateAfter).toEqual(stateBefore);
  });
});
