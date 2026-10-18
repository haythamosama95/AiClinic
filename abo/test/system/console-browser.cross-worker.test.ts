/**
 * RM05 — console browser shell, ceremony context and first-credential
 * bootstrap (R2-P4 / R2-ABO-03), plus the R2-P1 signed-param binding
 * refusals at the producer-to-verifier boundary (H-XW).
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import notifyWorkMigrationSql from "../../migrations/0003_notify_work.sql?raw";
import grantMigrationSql from "../../migrations/0004_grant.sql?raw";
import reversalMigrationSql from "../../migrations/0005_reversal.sql?raw";
import operatorActionMigrationSql from "../../migrations/0006_operator_action.sql?raw";
import hpActionsMigrationSql from "../../migrations/0007_hp_actions.sql?raw";
import acceptedCommandsErasureFenceMigrationSql from "../../migrations/0012_accepted_commands_erasure_fence.sql?raw";
import notificationProviderTxnIdMigrationSql from "../../migrations/0013_notification_provider_txn_id.sql?raw";
import { operationChallenge } from "vendor-contracts";
import {
  createSoftwareAuthenticator,
} from "vendor-contracts/testkit";
import { applySql, billingFetch, opsFetch } from "./harness";
import {
  mintVendorAccessJwt,
  resetCrossWorkerHarness,
  scriptPaymobStub,
  setClock,
  setupCrossWorkerHarness,
} from "./cross-worker-harness";
import {
  base64UrlDecode,
  base64UrlEncodeBytes,
  buildLocalHpCeremony,
  credentialGetRequest,
  serializeAssertion,
} from "../../src/ops/browser/ceremony";

const VENDOR_OPERATOR_EMAIL = "operator@vendor.test";
const OPS_HOST = "ops.vendor.test";
const ORG_CB_01 = "a4a50001-0001-4001-8001-000000000001";
const ORG_CB_02 = "a4a50002-0002-4002-8002-000000000002";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    WEBAUTHN_RP_ID: string;
    WEBAUTHN_ORIGIN: string;
  }
}

function encodeVendorAttestation(attestation: {
  alg: "ES256" | "EdDSA";
  publicKey: Uint8Array;
}): { alg: "ES256" | "EdDSA"; public_key: string } {
  return {
    alg: attestation.alg,
    public_key: base64UrlEncodeBytes(attestation.publicKey),
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
    acceptedCommandsErasureFenceMigrationSql,
    notificationProviderTxnIdMigrationSql,
  ]) {
    try {
      await applySql(sql);
    } catch {
      // Migration not present yet.
    }
  }
}

async function clearOperatorCredentials(): Promise<void> {
  await env.PLATFORM_DB.prepare("DELETE FROM operator_credential").run();
  await env.PLATFORM_DB.prepare("DELETE FROM platform_alert").run();
}

async function seedActiveOperatorCredential(
  authenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>,
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

async function seedBillingContact(orgId: string): Promise<void> {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO billing_contact
       (org_id, version, client_request_id, name, email, phone,
        contact_sha256, created_by_sub, contract_version, erased_at, erased_by)
     VALUES (?, 1, ?, 'Ceremony Clinic', 'ceremony@clinic.test', '+201000000000',
             'ceremony-contact-sha256', 'ceremony-sub', 1, NULL, NULL)`,
  )
    .bind(orgId, `req-cb-${orgId}`)
    .run();
}

// The HP verifier measures issued_at freshness against the harness clock
// (TEST_CLOCK="1" in the cross-worker campaign), so ceremonies must carry
// it, exactly like the production shell stamps Date.now().
async function harnessClockIso(): Promise<string> {
  const row = await env.DB.prepare(
    `SELECT now_iso FROM harness_test_clock WHERE id = 'default'`,
  ).first<{ now_iso: string }>();
  return row?.now_iso ?? "2026-06-01T12:00:00.000Z";
}

async function opsHeaders(accessJwt?: string): Promise<Record<string, string>> {
  const headers: Record<string, string> = {
    "Abo-Contract-Version": "1",
  };
  if (accessJwt !== undefined) {
    headers["Cf-Access-Jwt-Assertion"] = accessJwt;
  }
  return headers;
}

async function registerAndActivateFirstCredential(): Promise<{
  accessJwt: string;
  authenticator: Awaited<ReturnType<typeof createSoftwareAuthenticator>>;
  credentialId: string;
}> {
  const accessJwt = await mintVendorAccessJwt();
  const authenticator = await createSoftwareAuthenticator("EdDSA");
  const credentialId = crypto.randomUUID();
  const bootstrap = await opsFetch("/ops/operator-credentials", {
    method: "POST",
    headers: await opsHeaders(accessJwt),
    body: JSON.stringify({
      action_id: crypto.randomUUID(),
      credential_id: credentialId,
      attestation: encodeVendorAttestation(await authenticator.attest()),
    }),
  });
  expect(bootstrap.status).toBe(200);
  const bootstrapBody = (await bootstrap.json()) as Record<string, unknown>;
  expect(bootstrapBody.result).toBe("ok");
  const bootstrapDetail = JSON.parse(String(bootstrapBody.detail)) as Record<
    string,
    unknown
  >;
  expect(typeof bootstrapDetail.activates_at).toBe("string");
  await setClock(String(bootstrapDetail.activates_at));
  return { accessJwt, authenticator, credentialId };
}

async function ceremonyContext(
  accessJwt: string,
): Promise<{
  credentials: Array<{ credential_id: string; alg: string }>;
}> {
  const response = await opsFetch("/ops/ceremony-context", {
    method: "GET",
    headers: await opsHeaders(accessJwt),
  });
  expect(response.status).toBe(200);
  return (await response.json()) as {
    credentials: Array<{ credential_id: string; alg: string }>;
  };
}

beforeEach(async () => {
  await setupCrossWorkerHarness();
  await resetCrossWorkerHarness();
  await ensureMigrations();
  await scriptPaymobStub("ok");
  await setClock("2026-06-01T12:00:00.000Z");
});

describe("console browser cross-worker", () => {
  it("R2-P4 GET /ops serves the Access-gated shell while every other ops path keeps the version gate", async () => {
    await clearOperatorCredentials();
    const accessJwt = await mintVendorAccessJwt();

    // The exact shell path serves HTML after Access verification and before
    // the contract-version check: a first navigation carries no header.
    const shell = await opsFetch("/ops", {
      method: "GET",
      headers: { "Cf-Access-Jwt-Assertion": accessJwt },
    });
    expect(shell.status).toBe(200);
    expect(shell.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(shell.headers.get("cache-control")).toBe("no-store");
    const html = await shell.text();
    // All six local actions are present with the frozen route templates.
    for (const action of [
      "publish_offer",
      "retire_offer",
      "reinstate_offer",
      "release_payment",
      "manual_chargeback",
      "erase_contact",
    ] as const) {
      expect(html).toContain(`"action":"${action}"`);
    }
    expect(html).toContain("/ops/offers/{subject}/publish");
    expect(html).toContain("/ops/orgs/{subject}/erase-contact");
    expect(html).toContain("Abo-Contract-Version");
    expect(html).toContain("/ops/ceremony-context");
    expect(html).toContain("/ops/operator-credentials");
    expect(html).toContain("Create first operator credential");

    // Supplying a version header on the exact shell path changes nothing:
    // the gate applies only to the JSON APIs.
    const shellWithHeader = await opsFetch("/ops", {
      method: "GET",
      headers: await opsHeaders(accessJwt),
    });
    expect(shellWithHeader.status).toBe(200);
    expect(shellWithHeader.headers.get("content-type")).toBe(
      "text/html; charset=utf-8",
    );

    // No Access JWT: the standard unauthenticated JSON body, not the shell.
    const unauthenticated = await opsFetch("/ops", { method: "GET" });
    expect(unauthenticated.status).toBe(401);
    const unauthenticatedBody = (await unauthenticated.json()) as Record<
      string,
      unknown
    >;
    expect(unauthenticatedBody.code).toBe("unauthenticated");

    // GET /ops/ (trailing slash) and every other /ops/* path keep the
    // version gate before auth, exactly as before this change.
    const gate = await opsFetch("/ops/", {
      method: "GET",
      headers: { "Cf-Access-Jwt-Assertion": accessJwt },
    });
    expect(gate.status).toBe(400);
    const gateBody = (await gate.json()) as Record<string, unknown>;
    expect(gateBody.code).toBe("contract_version_unsupported");
    expect(gateBody.reload).toBe(true);

    // The billing host never serves the shell.
    const billingHost = await billingFetch("/ops", { method: "GET" });
    expect(billingHost.status).toBe(404);
    expect(await billingHost.text()).toBe("");
  });

  it("R2-P4 ceremony-context returns the verified actor, rp, console version and active credentials with no key material", async () => {
    await clearOperatorCredentials();
    const accessJwt = await mintVendorAccessJwt();

    // Version-gated like every /ops/* JSON API: a missing header reloads.
    const gate = await opsFetch("/ops/ceremony-context", {
      method: "GET",
      headers: { "Cf-Access-Jwt-Assertion": accessJwt },
    });
    expect(gate.status).toBe(400);
    const gateBody = (await gate.json()) as Record<string, unknown>;
    expect(gateBody.code).toBe("contract_version_unsupported");
    expect(gateBody.reload).toBe(true);

    // Authenticated read with an empty registry.
    const empty = await opsFetch("/ops/ceremony-context", {
      method: "GET",
      headers: await opsHeaders(accessJwt),
    });
    expect(empty.status).toBe(200);
    const emptyRaw = await empty.text();
    const emptyBody = JSON.parse(emptyRaw) as Record<string, unknown>;
    expect(Object.keys(emptyBody).sort()).toEqual([
      "actor_email",
      "contract_version",
      "credentials",
      "origin",
      "rp_id",
    ]);
    expect(emptyBody.contract_version).toBe(1);
    expect(emptyBody.actor_email).toBe(VENDOR_OPERATOR_EMAIL);
    expect(emptyBody.rp_id).toBe(OPS_HOST);
    expect(emptyBody.origin).toBe(`https://${OPS_HOST}`);
    expect(emptyBody.credentials).toEqual([]);

    // A seeded active credential appears as {credential_id, alg} only.
    const authenticator = await createSoftwareAuthenticator("EdDSA");
    const credentialId = await seedActiveOperatorCredential(authenticator);
    const context = await opsFetch("/ops/ceremony-context", {
      method: "GET",
      headers: await opsHeaders(accessJwt),
    });
    expect(context.status).toBe(200);
    const raw = await context.text();
    // No key material of any form leaks through the context.
    expect(raw).not.toContain("public_key");
    expect(raw).not.toContain("public_key_cose");
    expect(raw).not.toContain(accessJwt);
    const contextBody = JSON.parse(raw) as Record<string, unknown>;
    expect(contextBody.credentials).toEqual([
      { credential_id: credentialId, alg: "EdDSA" },
    ]);
  });

  it("R2-P4 first-credential bootstrap is accepted only while the registry never held a row", async () => {
    await clearOperatorCredentials();
    const accessJwt = await mintVendorAccessJwt();

    const bootstrapAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const bootstrapCredentialId = crypto.randomUUID();
    const bootstrap = await opsFetch("/ops/operator-credentials", {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        action_id: crypto.randomUUID(),
        credential_id: bootstrapCredentialId,
        attestation: encodeVendorAttestation(
          await bootstrapAuthenticator.attest(),
        ),
      }),
    });
    expect(bootstrap.status).toBe(200);
    const bootstrapBody = (await bootstrap.json()) as Record<string, unknown>;
    expect(bootstrapBody.result).toBe("ok");
    const bootstrapDetail = JSON.parse(String(bootstrapBody.detail)) as Record<
      string,
      unknown
    >;
    expect(bootstrapDetail.credential_id).toBe(bootstrapCredentialId);
    expect(typeof bootstrapDetail.activates_at).toBe("string");
    // Bootstrap alert confirms the registration (R2-P3).
    const bootstrapAlerts = await env.PLATFORM_DB.prepare(
      `SELECT COUNT(*) AS n FROM platform_alert
       WHERE code = 'AL-13' AND alert_key = ?`,
    )
      .bind(`AL-13:${bootstrapCredentialId}:bootstrap`)
      .first<{ n: number }>();
    expect(bootstrapAlerts?.n).toBe(1);

    // Until the activation time passes, ceremony-context still lists no
    // active credential (the registry is active-only).
    const pending = await ceremonyContext(accessJwt);
    expect(pending.credentials).toEqual([]);

    // Once active, the bootstrapped credential is the sole allow-list entry.
    await setClock(String(bootstrapDetail.activates_at));
    const active = await ceremonyContext(accessJwt);
    expect(active.credentials).toEqual([
      { credential_id: bootstrapCredentialId, alg: "EdDSA" },
    ]);

    // Bootstrap is closed: an assertion-less second registration is refused
    // and cannot extend the registry.
    const registryBefore = await env.PLATFORM_DB.prepare(
      `SELECT COUNT(*) AS n FROM operator_credential`,
    ).first<{ n: number }>();
    const secondAuthenticator = await createSoftwareAuthenticator("EdDSA");
    const second = await opsFetch("/ops/operator-credentials", {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        action_id: crypto.randomUUID(),
        credential_id: crypto.randomUUID(),
        attestation: encodeVendorAttestation(
          await secondAuthenticator.attest(),
        ),
      }),
    });
    expect(second.status).toBe(200);
    const secondBody = (await second.json()) as Record<string, unknown>;
    expect(secondBody.result).toBe("rejected");
    expect(secondBody.code).toBe("assertion_required");
    const registryAfter = await env.PLATFORM_DB.prepare(
      `SELECT COUNT(*) AS n FROM operator_credential`,
    ).first<{ n: number }>();
    expect(registryAfter?.n).toBe(registryBefore?.n);
  });

  it("R2-ABO-03/R6-O1 console producer ceremonies submit bound bytes and resume accepted erasure", async () => {
    await clearOperatorCredentials();
    const { accessJwt, authenticator, credentialId } =
      await registerAndActivateFirstCredential();
    const context = await ceremonyContext(accessJwt);
    expect(context.credentials).toEqual([
      { credential_id: credentialId, alg: "EdDSA" },
    ]);

    // Producer ceremony for retire_offer; the same producer path backs all
    // six local actions. The challenge must be byte-identical to the
    // package's operationChallenge base64url digest.
    const prebuilt = buildLocalHpCeremony({
      action: "retire_offer",
      values: { subject: "offer-ceremony-6b0f" },
      actorEmail: VENDOR_OPERATOR_EMAIL,
      contractVersion: 1,
      issuedAt: await harnessClockIso(),
    });
    expect(prebuilt).not.toBeNull();
    const operation = prebuilt!.operation;
    expect(prebuilt!.subject).toBe("offer-ceremony-6b0f");
    expect(prebuilt!.route).toBe("/ops/offers/offer-ceremony-6b0f/retire");

    const expectedChallenge = await operationChallenge(operation);
    const getRequest = await credentialGetRequest({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      credentials: context.credentials,
    });
    expect(getRequest).not.toBeNull();
    expect(getRequest!.publicKey.rpId).toBe(env.WEBAUTHN_RP_ID);
    expect(getRequest!.publicKey.userVerification).toBe("required");
    expect(getRequest!.publicKey.allowCredentials).toEqual([
      { id: base64UrlDecode(credentialId), type: "public-key" },
    ]);
    expect(base64UrlEncodeBytes(getRequest!.publicKey.challenge)).toBe(
      expectedChallenge,
    );

    // Sign the exact challenge bytes with the software authenticator and
    // serialize through the console producer's serializeAssertion.
    const signed = await authenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    });
    const wire = serializeAssertion({
      credentials: context.credentials,
      rawId: base64UrlDecode(credentialId)!,
      authenticatorData: signed.authenticatorData,
      clientDataJSON: signed.clientDataJSON,
      signature: signed.signature,
    });
    expect(wire).not.toBeNull();
    expect(wire!.signerCredentialId).toBe(credentialId);
    const assertion: Record<string, string> = {
      alg: wire!.assertion.alg,
      authenticator_data: wire!.assertion.authenticator_data,
      client_data_json: wire!.assertion.client_data_json,
      signature: wire!.assertion.signature,
    };

    // A credential outside the active registry can never be serialized:
    // the console refuses before any submission.
    const foreign = serializeAssertion({
      credentials: context.credentials,
      rawId: base64UrlDecode(crypto.randomUUID())!,
      authenticatorData: signed.authenticatorData,
      clientDataJSON: signed.clientDataJSON,
      signature: signed.signature,
    });
    expect(foreign).toBeNull();

    // Submit an accepting ceremony through the actual versioned handler:
    // erase_contact on an org that has a contact row. The exact signed
    // bytes and bound params ({org_id}) are consumed by decodeAssertion
    // and the verifier.
    const orgId = ORG_CB_01;
    await seedBillingContact(orgId);
    const erase = buildLocalHpCeremony({
      action: "erase_contact",
      values: { subject: orgId },
      actorEmail: VENDOR_OPERATOR_EMAIL,
      contractVersion: 1,
      issuedAt: await harnessClockIso(),
    });
    expect(erase).not.toBeNull();
    expect(erase!.route).toBe(`/ops/orgs/${orgId}/erase-contact`);
    const eraseSigned = await authenticator.assert({
      operation: erase!.operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    });
    const eraseWire = serializeAssertion({
      credentials: context.credentials,
      rawId: base64UrlDecode(credentialId)!,
      authenticatorData: eraseSigned.authenticatorData,
      clientDataJSON: eraseSigned.clientDataJSON,
      signature: eraseSigned.signature,
    });
    expect(eraseWire).not.toBeNull();
    const eraseAssertion: Record<string, string> = {
      alg: eraseWire!.assertion.alg,
      authenticator_data: eraseWire!.assertion.authenticator_data,
      client_data_json: eraseWire!.assertion.client_data_json,
      signature: eraseWire!.assertion.signature,
    };
    const submitted = await opsFetch(erase!.route, {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        operation: erase!.operation,
        assertion: eraseAssertion,
      }),
    });
    expect(submitted.status).toBe(200);
    const submittedBody = (await submitted.json()) as Record<string, unknown>;
    expect(typeof submittedBody.action_id).toBe("string");

    const contacts = await env.DB.prepare(
      `SELECT name, email, phone, erased_at, erased_by
       FROM billing_contact WHERE org_id = ?`,
    )
      .bind(orgId)
      .first<{
        name: string;
        email: string;
        phone: string;
        erased_at: string | null;
        erased_by: string | null;
      }>();
    expect(contacts?.name).toBe("");
    expect(contacts?.erased_at).not.toBeNull();
    expect(contacts?.erased_by).toBe(VENDOR_OPERATOR_EMAIL);

    // An accepted erasure resumes by the same operation and returns its
    // original action identity without applying the mutation twice.
    const replay = await opsFetch(erase!.route, {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        operation: erase!.operation,
        assertion: eraseAssertion,
      }),
    });
    expect(replay.status).toBe(200);

    // The unused retire ceremony (never submitted) serializes fine on its
    // own handler; its subject has no published version, so the handler
    // refuses with a business code after signature consumption.
    const retirement = await opsFetch(prebuilt!.route, {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({ operation, assertion }),
    });
    expect(retirement.status).toBe(400);
    const retirementBody = (await retirement.json()) as Record<string, unknown>;
    expect(retirementBody.code).not.toBe("assertion_invalid");
    expect(retirementBody.code).not.toBe("assertion_required");
    expect(retirementBody.code).not.toBe("assertion_expired");
    expect(retirementBody.code).not.toBe("credential_not_active");
  });

  it("R2-P1/R6-O1 a bound approval stays subject-scoped and accepted erasure resumes", async () => {
    await clearOperatorCredentials();
    const accessJwt = await mintVendorAccessJwt();
    const authenticator = await createSoftwareAuthenticator("EdDSA");
    const credentialId = crypto.randomUUID();
    await seedActiveOperatorCredential(authenticator, credentialId);

    // Org A: contact row. Org B: contact row. An erase_contact approval
    // bound to A is submitted to B's URL.
    const orgA = ORG_CB_01;
    const orgB = ORG_CB_02;
    await seedBillingContact(orgA);
    await seedBillingContact(orgB);

    const bound = buildLocalHpCeremony({
      action: "erase_contact",
      values: { subject: orgA },
      actorEmail: VENDOR_OPERATOR_EMAIL,
      contractVersion: 1,
      issuedAt: await harnessClockIso(),
    });
    expect(bound).not.toBeNull();
    const signed = await authenticator.assert({
      operation: bound!.operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    });
    const wire = serializeAssertion({
      credentials: [
        { credential_id: credentialId, alg: "EdDSA" },
      ],
      rawId: base64UrlDecode(credentialId)!,
      authenticatorData: signed.authenticatorData,
      clientDataJSON: signed.clientDataJSON,
      signature: signed.signature,
    });
    expect(wire).not.toBeNull();

    const toB = await opsFetch(`/ops/orgs/${orgB}/erase-contact`, {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        operation: bound!.operation,
        assertion: {
          alg: wire!.assertion.alg,
          authenticator_data: wire!.assertion.authenticator_data,
          client_data_json: wire!.assertion.client_data_json,
          signature: wire!.assertion.signature,
        },
      }),
    });
    expect(toB.status).toBe(400);
    const toBBody = (await toB.json()) as Record<string, unknown>;
    expect(toBBody.code).toBe("assertion_invalid");

    // B was not changed by the misdirected approval.
    const contactB = await env.DB.prepare(
      `SELECT name, erased_at FROM billing_contact WHERE org_id = ?`,
    )
      .bind(orgB)
      .first<{ name: string; erased_at: string | null }>();
    expect(contactB?.name).toBe("Ceremony Clinic");
    expect(contactB?.erased_at).toBeNull();

    // The challenge was not consumed: the same approval still succeeds
    // exactly once on A's URL.
    const toA = await opsFetch(`/ops/orgs/${orgA}/erase-contact`, {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        operation: bound!.operation,
        assertion: {
          alg: wire!.assertion.alg,
          authenticator_data: wire!.assertion.authenticator_data,
          client_data_json: wire!.assertion.client_data_json,
          signature: wire!.assertion.signature,
        },
      }),
    });
    expect(toA.status).toBe(200);
    const contactA = await env.DB.prepare(
      `SELECT name, erased_at, erased_by FROM billing_contact WHERE org_id = ?`,
    )
      .bind(orgA)
      .first<{ name: string; erased_at: string | null; erased_by: string | null }>();
    expect(contactA?.name).toBe("");
    expect(contactA?.erased_by).toBe(VENDOR_OPERATOR_EMAIL);

    // Reuse of the accepted approval returns the same command result.
    const replay = await opsFetch(`/ops/orgs/${orgA}/erase-contact`, {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        operation: bound!.operation,
        assertion: {
          alg: wire!.assertion.alg,
          authenticator_data: wire!.assertion.authenticator_data,
          client_data_json: wire!.assertion.client_data_json,
          signature: wire!.assertion.signature,
        },
      }),
    });
    expect(replay.status).toBe(200);

    // Missing the frozen bound key altogether is refused before replay
    // consumption as well: an unbound erase_contact (no org_id in params)
    // never reaches the assertion.
    const unboundOperation = {
      op: "erase_contact",
      params: {},
      actor_email: VENDOR_OPERATOR_EMAIL,
      issued_at: bound!.operation.issued_at,
      nonce: crypto.randomUUID(),
      contract_version: 1,
    };
    const unboundSigned = await authenticator.assert({
      operation: unboundOperation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    });
    const unboundWire = serializeAssertion({
      credentials: [{ credential_id: credentialId, alg: "EdDSA" }],
      rawId: base64UrlDecode(credentialId)!,
      authenticatorData: unboundSigned.authenticatorData,
      clientDataJSON: unboundSigned.clientDataJSON,
      signature: unboundSigned.signature,
    });
    const unbound = await opsFetch(`/ops/orgs/${orgB}/erase-contact`, {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        operation: unboundOperation,
        assertion: {
          alg: unboundWire!.assertion.alg,
          authenticator_data: unboundWire!.assertion.authenticator_data,
          client_data_json: unboundWire!.assertion.client_data_json,
          signature: unboundWire!.assertion.signature,
        },
      }),
    });
    expect(unbound.status).toBe(400);
    const unboundBody = (await unbound.json()) as Record<string, unknown>;
    expect(unboundBody.code).toBe("assertion_invalid");
  });

  it("R2-P1 wrong actor, wrong action and wrong contract version are refused without touching the target", async () => {
    await clearOperatorCredentials();
    const accessJwt = await mintVendorAccessJwt();
    const authenticator = await createSoftwareAuthenticator("EdDSA");
    const credentialId = crypto.randomUUID();
    await seedActiveOperatorCredential(authenticator, credentialId);
    const orgId = ORG_CB_01;
    await seedBillingContact(orgId);

    // Wrong actor: the signed operation names a different operator email.
    const wrongActor = buildLocalHpCeremony({
      action: "erase_contact",
      values: { subject: orgId },
      actorEmail: "someone.else@vendor.test",
      contractVersion: 1,
      issuedAt: await harnessClockIso(),
    });
    const wrongActorSigned = await authenticator.assert({
      operation: wrongActor!.operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    });
    const wrongActorWire = serializeAssertion({
      credentials: [{ credential_id: credentialId, alg: "EdDSA" }],
      rawId: base64UrlDecode(credentialId)!,
      authenticatorData: wrongActorSigned.authenticatorData,
      clientDataJSON: wrongActorSigned.clientDataJSON,
      signature: wrongActorSigned.signature,
    });
    const actorRefusal = await opsFetch(`/ops/orgs/${orgId}/erase-contact`, {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        operation: wrongActor!.operation,
        assertion: {
          alg: wrongActorWire!.assertion.alg,
          authenticator_data: wrongActorWire!.assertion.authenticator_data,
          client_data_json: wrongActorWire!.assertion.client_data_json,
          signature: wrongActorWire!.assertion.signature,
        },
      }),
    });
    expect(actorRefusal.status).toBe(400);
    const actorRefusalBody = (await actorRefusal.json()) as Record<
      string,
      unknown
    >;
    expect(actorRefusalBody.code).toBe("actor_email_mismatch");

    // Wrong action: a retire_offer operation posted to the erase-contact
    // route is refused before the assertion is consumed.
    const wrongAction = buildLocalHpCeremony({
      action: "retire_offer",
      values: { subject: "offer-wrong-action-1" },
      actorEmail: VENDOR_OPERATOR_EMAIL,
      contractVersion: 1,
      issuedAt: await harnessClockIso(),
    });
    const wrongActionSigned = await authenticator.assert({
      operation: wrongAction!.operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    });
    const wrongActionWire = serializeAssertion({
      credentials: [{ credential_id: credentialId, alg: "EdDSA" }],
      rawId: base64UrlDecode(credentialId)!,
      authenticatorData: wrongActionSigned.authenticatorData,
      clientDataJSON: wrongActionSigned.clientDataJSON,
      signature: wrongActionSigned.signature,
    });
    const actionRefusal = await opsFetch(`/ops/orgs/${orgId}/erase-contact`, {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        operation: wrongAction!.operation,
        assertion: {
          alg: wrongActionWire!.assertion.alg,
          authenticator_data: wrongActionWire!.assertion.authenticator_data,
          client_data_json: wrongActionWire!.assertion.client_data_json,
          signature: wrongActionWire!.assertion.signature,
        },
      }),
    });
    expect(actionRefusal.status).toBe(400);
    const actionRefusalBody = (await actionRefusal.json()) as Record<
      string,
      unknown
    >;
    expect(actionRefusalBody.code).toBe("assertion_invalid");

    // Wrong contract version in the signed operation (negotiated 1) is
    // refused the same way.
    const wrongVersionOperation = {
      op: "erase_contact",
      params: { org_id: orgId },
      actor_email: VENDOR_OPERATOR_EMAIL,
      issued_at: await harnessClockIso(),
      nonce: crypto.randomUUID(),
      contract_version: 2,
    };
    const wrongVersionSigned = await authenticator.assert({
      operation: wrongVersionOperation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    });
    const wrongVersionWire = serializeAssertion({
      credentials: [{ credential_id: credentialId, alg: "EdDSA" }],
      rawId: base64UrlDecode(credentialId)!,
      authenticatorData: wrongVersionSigned.authenticatorData,
      clientDataJSON: wrongVersionSigned.clientDataJSON,
      signature: wrongVersionSigned.signature,
    });
    const versionRefusal = await opsFetch(`/ops/orgs/${orgId}/erase-contact`, {
      method: "POST",
      headers: await opsHeaders(accessJwt),
      body: JSON.stringify({
        operation: wrongVersionOperation,
        assertion: {
          alg: wrongVersionWire!.assertion.alg,
          authenticator_data: wrongVersionWire!.assertion.authenticator_data,
          client_data_json: wrongVersionWire!.assertion.client_data_json,
          signature: wrongVersionWire!.assertion.signature,
        },
      }),
    });
    expect(versionRefusal.status).toBe(400);
    const versionRefusalBody = (await versionRefusal.json()) as Record<
      string,
      unknown
    >;
    expect(versionRefusalBody.code).toBe("assertion_invalid");

    // None of the refusals mutated the target.
    const contact = await env.DB.prepare(
      `SELECT name, erased_at FROM billing_contact WHERE org_id = ?`,
    )
      .bind(orgId)
      .first<{ name: string; erased_at: string | null }>();
    expect(contact?.name).toBe("Ceremony Clinic");
    expect(contact?.erased_at).toBeNull();
  });
});
