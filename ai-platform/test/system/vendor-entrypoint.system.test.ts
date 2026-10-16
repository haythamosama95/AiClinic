/**
 * P3.1 — VendorEntrypoint, operator credentials, platform alerting (E2E-P3.1-01–10).
 */

import { env } from "cloudflare:test";
import { CHANNEL_VERSIONS, canonicalize, sha256Hex } from "vendor-contracts";
import { createSoftwareAuthenticator } from "vendor-contracts/testkit";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import wranglerToml from "../../wrangler.toml?raw";
import {
  applyAllMigrations,
  clearCapturedHeartbeatFetches,
  clearCapturedVendorEmails,
  encodeVendorAssertion,
  getVendorTestClockIso,
  encodeVendorAttestation,
  getCapturedHeartbeatFetches,
  getCapturedVendorEmails,
  mintVendorAccessJwt,
  queryOne,
  resetPlatformState,
  runScheduled,
  setHeartbeatFetchThrows,
  setSendPlatformEmailThrows,
  setTestClock,
  setupVendorHarness,
  vendorCall,
  VENDOR_OPERATOR_EMAIL,
  type VendorResultEnvelope,
  vendorTableCount,
} from "./harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;

type SoftwareAuthenticator = Awaited<
  ReturnType<typeof createSoftwareAuthenticator>
>;

function expectNoReceipt(envelope: VendorResultEnvelope): void {
  expect(envelope).not.toHaveProperty("receipt");
}

function parseDetailRow(detail: string): Record<string, unknown> {
  return JSON.parse(detail) as Record<string, unknown>;
}

async function operationForRevoke(input: {
  credentialId: string;
  signerCredentialId: string;
  accessJwt: string;
  issuedAt?: string;
  actorEmail?: string;
}): Promise<Record<string, unknown>> {
  return {
    op: "revokeOperatorCredential",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      credential_id: input.credentialId,
      signer_credential_id: input.signerCredentialId,
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

async function operationForRegister(input: {
  credentialId: string;
  signerCredentialId: string;
  attestation: { alg: "ES256" | "EdDSA"; public_key: string };
  accessJwt: string;
  issuedAt?: string;
  actorEmail?: string;
}): Promise<Record<string, unknown>> {
  return {
    op: "registerOperatorCredential",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      credential_id: input.credentialId,
      attestation: input.attestation,
      signer_credential_id: input.signerCredentialId,
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

async function bootstrapCredential(
  authenticator: SoftwareAuthenticator,
): Promise<{
  credentialId: string;
  row: Record<string, unknown>;
  accessJwt: string;
  attestation: { alg: "ES256" | "EdDSA"; public_key: string };
}> {
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
  expect(result.code).toBe("");
  expectNoReceipt(result);
  const row = parseDetailRow(result.detail);
  expect(row.status).toBe("pending");
  return { credentialId, row, accessJwt, attestation };
}

async function revokeWithAssertion(input: {
  credentialId: string;
  signerCredentialId: string;
  authenticator: SoftwareAuthenticator;
  accessJwt?: string;
  issuedAt?: string;
  actorEmail?: string;
}): Promise<VendorResultEnvelope> {
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const operation = await operationForRevoke({
    credentialId: input.credentialId,
    signerCredentialId: input.signerCredentialId,
    accessJwt,
    issuedAt: input.issuedAt,
    actorEmail: input.actorEmail,
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
  return vendorCall(
    "revokeOperatorCredential",
    {
      contract_version: CONTRACT_VERSION,
      credential_id: input.credentialId,
      signer_credential_id: input.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function registerWithAssertion(input: {
  credentialId: string;
  signerCredentialId: string;
  signerAuthenticator: SoftwareAuthenticator;
  attestationAuthenticator: SoftwareAuthenticator;
  accessJwt?: string;
}): Promise<VendorResultEnvelope> {
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const attestation = encodeVendorAttestation(
    await input.attestationAuthenticator.attest(),
  );
  const operation = await operationForRegister({
    credentialId: input.credentialId,
    signerCredentialId: input.signerCredentialId,
    attestation,
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
  return vendorCall(
    "registerOperatorCredential",
    {
      contract_version: CONTRACT_VERSION,
      credential_id: input.credentialId,
      attestation,
      signer_credential_id: input.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

function productionStagingBlocksHaveNoTestClock(): void {
  const productionBlock = wranglerToml.match(
    /\[env\.production\][\s\S]*?(?=\n\[env\.|$)/u,
  )?.[0];
  const stagingBlock = wranglerToml.match(
    /\[env\.staging\][\s\S]*?(?=\n\[env\.|$)/u,
  )?.[0];
  expect(productionBlock).toBeDefined();
  expect(stagingBlock).toBeDefined();
  expect(productionBlock).not.toMatch(/TEST_CLOCK/u);
  expect(stagingBlock).not.toMatch(/TEST_CLOCK/u);
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  await setupVendorHarness();
});

beforeEach(async () => {
  await resetPlatformState();
  await setupVendorHarness();
});

describe("vendor entrypoint", () => {
  it("E2E-P3.1-01 Empty registry: bootstrap registration without approval returns pending and AL-13 bootstrap; a second unapproved registration is rejected", async () => {
    const authenticator = await createSoftwareAuthenticator("EdDSA");
    const credentialId = crypto.randomUUID();
    const attestation = encodeVendorAttestation(await authenticator.attest());
    const accessJwt = await mintVendorAccessJwt();

    const first = await vendorCall(
      "registerOperatorCredential",
      {
        contract_version: CONTRACT_VERSION,
        credential_id: credentialId,
        attestation,
      },
      { accessJwt },
    );
    expect(first.result).toBe("ok");
    expect(first.code).toBe("");
    expectNoReceipt(first);
    const row = parseDetailRow(first.detail);
    expect(row.status).toBe("pending");

    const emails = getCapturedVendorEmails();
    expect(emails.length).toBeGreaterThanOrEqual(1);
    const body = JSON.parse(emails[emails.length - 1]!.text) as Record<
      string,
      unknown
    >;
    expect(body.code).toBe("AL-13");
    expect(body.kind).toBe("bootstrap");
    expect(body.credential_id).toBe(credentialId);
    expect(body.operator_email).toBe(VENDOR_OPERATOR_EMAIL);
    expect(body.operation).toBeNull();

    const secondCredentialId = crypto.randomUUID();
    const secondAttestation = encodeVendorAttestation(
      await authenticator.attest(),
    );
    const beforeRows = await vendorTableCount("operator_credential");
    const second = await vendorCall(
      "registerOperatorCredential",
      {
        contract_version: CONTRACT_VERSION,
        credential_id: secondCredentialId,
        attestation: secondAttestation,
      },
      { accessJwt },
    );
    expect(second.result).toBe("rejected");
    expect(second.code).toBe("assertion_required");
    expectNoReceipt(second);
    expect(await vendorTableCount("operator_credential")).toBe(beforeRows);
  });

  it("E2E-P3.1-02 HP call using a credential under 24 hours is rejected; after the test clock passes 24 hours it is ok", async () => {
    productionStagingBlocksHaveNoTestClock();

    const authenticator = await createSoftwareAuthenticator("EdDSA");
    const { credentialId, row } = await bootstrapCredential(authenticator);
    const activatesAt = String(row.activates_at);
    const usedBefore = await vendorTableCount("assertion_used");
    const auditsBefore = await vendorTableCount("control_audit");

    const rejected = await revokeWithAssertion({
      credentialId,
      signerCredentialId: credentialId,
      authenticator,
    });
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("credential_not_active");
    expectNoReceipt(rejected);
    expect(await vendorTableCount("assertion_used")).toBe(usedBefore);
    expect(await vendorTableCount("control_audit")).toBe(auditsBefore + 1);

    const pendingRow = await queryOne<Record<string, unknown>>(
      "SELECT status FROM operator_credential WHERE credential_id = ?",
      [credentialId],
    );
    expect(pendingRow).not.toBeNull();
    expect(pendingRow?.status).toBe("pending");

    await setTestClock(activatesAt);
    const ok = await revokeWithAssertion({
      credentialId,
      signerCredentialId: credentialId,
      authenticator,
    });
    expect(ok.result).toBe("ok");
    expect(ok.code).toBe("");
    expectNoReceipt(ok);
    const detail = parseDetailRow(ok.detail);
    expect(detail.credential_id).toBe(credentialId);
    expect(detail.status).toBe("revoked");
  });

  it("E2E-P3.1-03 HP with a valid Access JWT and an assertion over the exact operation is ok; replaying the assertion is rejected", async () => {
    const authenticator = await createSoftwareAuthenticator("EdDSA");
    const { credentialId, row } = await bootstrapCredential(authenticator);
    await setTestClock(String(row.activates_at));

    const accessJwt = await mintVendorAccessJwt();
    const operation = await operationForRevoke({
      credentialId,
      signerCredentialId: credentialId,
      accessJwt,
    });
    const assertion = encodeVendorAssertion(
      await authenticator.assert({
        operation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      }),
    );

    const ok = await vendorCall(
      "revokeOperatorCredential",
      {
        contract_version: CONTRACT_VERSION,
        credential_id: credentialId,
        signer_credential_id: credentialId,
        operation,
        assertion,
      },
      { accessJwt },
    );
    expect(ok.result).toBe("ok");
    expect(ok.code).toBe("");
    expectNoReceipt(ok);
    expect(ok.contract_version).toBe(CONTRACT_VERSION);

    const assertionSha256 = await sha256Hex(canonicalize(operation));
    const audit = await queryOne<Record<string, unknown>>(
      "SELECT actor, assertion_sha256 FROM control_audit ORDER BY recorded_at DESC LIMIT 1",
    );
    expect(audit?.actor).toBe(VENDOR_OPERATOR_EMAIL);
    expect(audit?.assertion_sha256).toBe(assertionSha256);

    const replay = await vendorCall(
      "revokeOperatorCredential",
      {
        contract_version: CONTRACT_VERSION,
        credential_id: credentialId,
        signer_credential_id: credentialId,
        operation,
        assertion,
      },
      { accessJwt },
    );
    expect(replay.result).toBe("rejected");
    expect(replay.code).toBe("assertion_used");
    expectNoReceipt(replay);
  });

  it("E2E-P3.1-04 Assertion issued_at 6 minutes old is rejected; actor_email other than the Access email is rejected", async () => {
    const authenticator = await createSoftwareAuthenticator("EdDSA");
    const { credentialId, row } = await bootstrapCredential(authenticator);
    await setTestClock(String(row.activates_at));

    const accessJwt = await mintVendorAccessJwt();
    const auditsBefore = await vendorTableCount("control_audit");
    const usedBefore = await vendorTableCount("assertion_used");
    const staleIssuedAt = new Date(Date.parse(String(row.activates_at)) - 6 * 60 * 1000).toISOString();
    const expired = await revokeWithAssertion({
      credentialId,
      signerCredentialId: credentialId,
      authenticator,
      accessJwt,
      issuedAt: staleIssuedAt,
    });
    expect(expired.result).toBe("rejected");
    expect(expired.code).toBe("assertion_expired");
    expectNoReceipt(expired);

    const mismatch = await revokeWithAssertion({
      credentialId,
      signerCredentialId: credentialId,
      authenticator,
      accessJwt,
      actorEmail: "other-operator@clinic.test",
    });
    expect(mismatch.result).toBe("rejected");
    expect(mismatch.code).toBe("actor_email_mismatch");
    expectNoReceipt(mismatch);
    expect(await vendorTableCount("assertion_used")).toBe(usedBefore);
    expect(await vendorTableCount("control_audit")).toBe(auditsBefore + 2);
  });

  it("E2E-P3.1-05 revokeOperatorCredential with a missing, expired, or wrong-aud Access JWT is unauthenticated and writes nothing", async () => {
    const authenticator = await createSoftwareAuthenticator("EdDSA");
    const { credentialId, row } = await bootstrapCredential(authenticator);
    await setTestClock(String(row.activates_at));

    const beforeCredential = await vendorTableCount("operator_credential");
    const beforeAssertion = await vendorTableCount("assertion_used");
    const beforeAudit = await vendorTableCount("control_audit");

    const operation = await operationForRevoke({
      credentialId,
      signerCredentialId: credentialId,
      accessJwt: "",
    });
    const assertion = encodeVendorAssertion(
      await authenticator.assert({
        operation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      }),
    );

    const missing = await vendorCall(
      "revokeOperatorCredential",
      {
        contract_version: CONTRACT_VERSION,
        credential_id: credentialId,
        signer_credential_id: credentialId,
        operation,
        assertion,
      },
      {},
    );
    expect(missing.result).toBe("rejected");
    expect(missing.code).toBe("unauthenticated");
    expectNoReceipt(missing);

    const expiredJwt = await mintVendorAccessJwt({
      exp: Math.floor(Date.now() / 1000) - 120,
      iat: Math.floor(Date.now() / 1000) - 3600,
    });
    const expired = await vendorCall(
      "revokeOperatorCredential",
      {
        contract_version: CONTRACT_VERSION,
        credential_id: credentialId,
        signer_credential_id: credentialId,
        operation,
        assertion,
      },
      { accessJwt: expiredJwt },
    );
    expect(expired.result).toBe("rejected");
    expect(expired.code).toBe("unauthenticated");
    expectNoReceipt(expired);

    const wrongAudJwt = await mintVendorAccessJwt({ aud: "wrong-audience" });
    const wrongAud = await vendorCall(
      "revokeOperatorCredential",
      {
        contract_version: CONTRACT_VERSION,
        credential_id: credentialId,
        signer_credential_id: credentialId,
        operation,
        assertion,
      },
      { accessJwt: wrongAudJwt },
    );
    expect(wrongAud.result).toBe("rejected");
    expect(wrongAud.code).toBe("unauthenticated");
    expectNoReceipt(wrongAud);

    expect(await vendorTableCount("operator_credential")).toBe(beforeCredential);
    expect(await vendorTableCount("assertion_used")).toBe(beforeAssertion);
    expect(await vendorTableCount("control_audit")).toBe(beforeAudit);
  });

  it("E2E-P3.1-06 A method with contract_version missing or 2 is rejected contract_version_unsupported and writes nothing", async () => {
    const badJwt = await mintVendorAccessJwt({ aud: "wrong-audience" });

    async function expectUnsupported(
      method: "registerOperatorCredential" | "revokeOperatorCredential" | "listOperatorCredentials",
      args: Record<string, unknown>,
    ): Promise<void> {
      const beforeCredential = await vendorTableCount("operator_credential");
      const beforeAssertion = await vendorTableCount("assertion_used");
      const beforeAudit = await vendorTableCount("control_audit");

      const result = await vendorCall(method, args, { accessJwt: badJwt });
      expect(result.result).toBe("rejected");
      expect(result.code).toBe("contract_version_unsupported");
      expectNoReceipt(result);

      expect(await vendorTableCount("operator_credential")).toBe(beforeCredential);
      expect(await vendorTableCount("assertion_used")).toBe(beforeAssertion);
      expect(await vendorTableCount("control_audit")).toBe(beforeAudit);
    }

    const attestation = encodeVendorAttestation(
      await (await createSoftwareAuthenticator("EdDSA")).attest(),
    );

    await expectUnsupported("registerOperatorCredential", {
      credential_id: crypto.randomUUID(),
      attestation,
    });
    await expectUnsupported("registerOperatorCredential", {
      contract_version: 2,
      credential_id: crypto.randomUUID(),
      attestation,
    });

    await expectUnsupported("revokeOperatorCredential", {
      credential_id: crypto.randomUUID(),
      signer_credential_id: crypto.randomUUID(),
    });
    await expectUnsupported("revokeOperatorCredential", {
      contract_version: 2,
      credential_id: crypto.randomUUID(),
      signer_credential_id: crypto.randomUUID(),
    });

    await expectUnsupported("listOperatorCredentials", {});
    await expectUnsupported("listOperatorCredentials", { contract_version: 2 });
  });

  it("E2E-P3.1-07 Credential A revokes B, then an HP call that uses B fails, and AL-13 is sent", async () => {
    const authenticatorA = await createSoftwareAuthenticator("EdDSA");
    const bootstrapA = await bootstrapCredential(authenticatorA);
    await setTestClock(String(bootstrapA.row.activates_at));

    const authenticatorB = await createSoftwareAuthenticator("EdDSA");
    const credentialB = crypto.randomUUID();
    const registerB = await registerWithAssertion({
      credentialId: credentialB,
      signerCredentialId: bootstrapA.credentialId,
      signerAuthenticator: authenticatorA,
      attestationAuthenticator: authenticatorB,
    });
    expect(registerB.result).toBe("ok");
    const rowB = parseDetailRow(registerB.detail);
    await setTestClock(String(rowB.activates_at));

    const emailsBeforeRevoke = getCapturedVendorEmails().length;
    const revoke = await revokeWithAssertion({
      credentialId: credentialB,
      signerCredentialId: bootstrapA.credentialId,
      authenticator: authenticatorA,
    });
    expect(revoke.result).toBe("ok");
    expect(revoke.code).toBe("");
    expectNoReceipt(revoke);
    const revokedRow = parseDetailRow(revoke.detail);
    expect(revokedRow.status).toBe("revoked");

    const audit = await queryOne<Record<string, unknown>>(
      "SELECT actor, assertion_sha256 FROM control_audit WHERE target = ? ORDER BY recorded_at DESC LIMIT 1",
      [credentialB],
    );
    expect(audit?.actor).toBe(VENDOR_OPERATOR_EMAIL);
    expect(typeof audit?.assertion_sha256).toBe("string");

    const revokeEmails = getCapturedVendorEmails().slice(emailsBeforeRevoke);
    expect(revokeEmails.length).toBeGreaterThanOrEqual(1);
    const revokeBody = JSON.parse(revokeEmails[revokeEmails.length - 1]!.text) as Record<
      string,
      unknown
    >;
    expect(revokeBody.code).toBe("AL-13");
    expect(revokeBody.kind).toBe("revoke");

    const hpWithB = await revokeWithAssertion({
      credentialId: bootstrapA.credentialId,
      signerCredentialId: credentialB,
      authenticator: authenticatorB,
    });
    expect(hpWithB.result).toBe("rejected");
    expect(hpWithB.code).toBe("credential_revoked");
    expectNoReceipt(hpWithB);
  });

  it("E2E-P3.1-08 When send_email throws the alert stays unsent and the next five-minute run sends it once", async () => {
    setSendPlatformEmailThrows(true);
    const authenticator = await createSoftwareAuthenticator("EdDSA");
    const { credentialId } = await bootstrapCredential(authenticator);

    const alert = await queryOne<Record<string, unknown>>(
      "SELECT send_state, code FROM platform_alert WHERE alert_key LIKE ?",
      [`AL-13:${credentialId}:%`],
    );
    expect(alert?.send_state).toBe("unsent");
    expect(alert?.code).toBe("AL-13");
    expect(getCapturedVendorEmails().length).toBe(0);

    setSendPlatformEmailThrows(false);
    clearCapturedVendorEmails();
    await runScheduled("*/5 * * * *");
    const afterFirstCron = getCapturedVendorEmails();
    expect(afterFirstCron.length).toBe(1);
    const firstBody = JSON.parse(afterFirstCron[0]!.text) as Record<string, unknown>;
    expect(firstBody.code).toBe("AL-13");
    expect(firstBody.credential_id).toBe(credentialId);
    expect(firstBody.operator_email).toBe(VENDOR_OPERATOR_EMAIL);
    expect(firstBody.operation).toBeNull();

    await runScheduled("*/5 * * * *");
    expect(getCapturedVendorEmails().length).toBe(1);
  });

  it("E2E-P3.1-09 The five-minute cron pings the heartbeat URL and a failing job raises a platform alert", async () => {
    clearCapturedHeartbeatFetches();
    await runScheduled("*/5 * * * *");
    expect(getCapturedHeartbeatFetches()).toContain(env.HEARTBEAT_URL);

    const logSpy = vi.spyOn(console, "log");
    setHeartbeatFetchThrows(true);
    const beforeFailedAlerts = await vendorTableCount("platform_alert");
    await runScheduled("*/5 * * * *");

    const jsonLine = logSpy.mock.calls
      .map((call) => call[0])
      .find(
        (line) =>
          typeof line === "string" &&
          line.includes("scheduled_job_failed") &&
          line.includes("*/5 * * * *"),
      );
    expect(jsonLine).toBeDefined();
    const parsed = JSON.parse(String(jsonLine)) as Record<string, unknown>;
    expect(parsed.cron).toBe("*/5 * * * *");
    expect(parsed.job).toBe("heartbeat");
    expect(typeof parsed.error).toBe("string");

    const failedAlert = await queryOne<Record<string, unknown>>(
      "SELECT code FROM platform_alert WHERE code = ?",
      ["scheduled_job_failed"],
    );
    expect(failedAlert?.code).toBe("scheduled_job_failed");
    expect(await vendorTableCount("platform_alert")).toBeGreaterThan(
      beforeFailedAlerts,
    );
    logSpy.mockRestore();
    setHeartbeatFetchThrows(false);
  });

  it("E2E-P3.1-10 listOperatorCredentials returns ok with the active keys in detail", async () => {
    const signerAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const signer = await bootstrapCredential(signerAuthenticator);
    await setTestClock(String(signer.row.activates_at));

    const activeAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const activeCredentialId = crypto.randomUUID();
    const registered = await registerWithAssertion({
      credentialId: activeCredentialId,
      signerCredentialId: signer.credentialId,
      signerAuthenticator,
      attestationAuthenticator: activeAuthenticator,
    });
    expect(registered.result).toBe("ok");
    const activeRow = parseDetailRow(registered.detail);
    await setTestClock(String(activeRow.activates_at));

    const pendingAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const pendingCredentialId = crypto.randomUUID();
    const pendingRegister = await registerWithAssertion({
      credentialId: pendingCredentialId,
      signerCredentialId: signer.credentialId,
      signerAuthenticator,
      attestationAuthenticator: pendingAuthenticator,
    });
    expect(pendingRegister.result).toBe("ok");
    expect(parseDetailRow(pendingRegister.detail).status).toBe("pending");

    const revokeSigner = await revokeWithAssertion({
      credentialId: signer.credentialId,
      signerCredentialId: signer.credentialId,
      authenticator: signerAuthenticator,
    });
    expect(revokeSigner.result).toBe("ok");

    const list = await vendorCall("listOperatorCredentials", {
      contract_version: CONTRACT_VERSION,
    });
    expect(list.result).toBe("ok");
    expect(list.code).toBe("");
    expectNoReceipt(list);
    expect(list.contract_version).toBe(CONTRACT_VERSION);

    const keys = JSON.parse(list.detail) as Array<{
      credential_id: string;
      public_key_cose: string;
      alg: string;
    }>;
    expect(keys).toEqual([
      {
        credential_id: activeCredentialId,
        public_key_cose: activeRow.public_key_cose,
        alg: activeRow.alg,
      },
    ]);
  });
});
