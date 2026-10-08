import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { getPlatformProxy } from "wrangler";
import {
  CHANNEL_VERSIONS,
  canonicalize,
  grantIdComp,
  grantIdPaid,
  sha256Hex,
  signCompactJws,
} from "vendor-contracts";
import {
  ABO_GRANT_KEY,
  ABO_URL,
  ALLOWANCE_CREDITS,
  CAPABILITY_ID,
  clearPlatformLogBuffer,
  encodeVendorAssertion,
  ensurePlatformGrantPrerequisites,
  HARNESS_URL,
  mintAccessJwt,
  openCheckout,
  OPS_HOST,
  OPERATOR_EMAIL,
  parseSendEmailCaptures,
  PLAN_ID,
  PLAN_VERSION,
  PLATFORM_CONFIG,
  PLATFORM_PERSIST,
  putBillingContact,
  queryAboD1One,
  queryPlatformD1One,
  readLatestSendEmailText,
  readSendEmailTextFile,
  rpc,
  runAboD1Command,
  sqlLiteral,
  startStack,
  triggerAboScheduled,
  WEBAUTHN_ORIGIN,
  WEBAUTHN_RP_ID,
} from "./p7-2-stack.mjs";

// H-FS unit harness (P7.2 US2): node --import tsx --test test/p7-2-vendor-entrypoint.test.mjs

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const LAUNCH_CEILING_POLICY = {
  per_grant_max_days: 31,
  per_grant_max_allowance_months: 1,
  window_days: 90,
  window_max_days: 62,
  window_max_allowance_months: 2,
  max_paid_grace_days: 7,
  paid_cap_rule: "proportional",
};

let stack = null;
let platformProxy = null;
let aboGrantSigner = null;

before(async () => {
  stack = await startStack();
  aboGrantSigner = await createHarnessAboGrantSigner();
  platformProxy = await getPlatformProxy({
    configPath: PLATFORM_CONFIG,
    environment: "development",
    persist: { path: PLATFORM_PERSIST },
  });
});

after(async () => {
  await platformProxy?.dispose();
  platformProxy = null;
  await stack?.stop();
  stack = null;
});

function base64urlDecode(value) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function envelopeB64(envelope) {
  const bytes = canonicalize(envelope);
  return Buffer.from(bytes).toString("base64");
}

async function createHarnessAboGrantSigner() {
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    base64urlDecode(ABO_GRANT_KEY.pkcs8),
    { name: "Ed25519" },
    false,
    ["sign"],
  );
  return {
    kid: ABO_GRANT_KEY.kid,
    async sign(envelope) {
      return signCompactJws({
        payload: canonicalize(envelope),
        privateKey,
        kid: ABO_GRANT_KEY.kid,
      });
    },
  };
}

async function vendorCall(method, args, { accessJwt, assertion } = {}) {
  const payload = { ...args };
  if (accessJwt !== undefined) {
    payload.access_jwt = accessJwt;
  }
  if (assertion !== undefined) {
    payload.assertion = assertion;
  }
  const response = await fetch(`${HARNESS_URL}/vendor-call`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ method, args: payload }),
  });
  return response.json();
}

async function buildPaidGrantEnvelope({ orgId, grantId, allowanceCredits }) {
  const paidAt = new Date().toISOString();
  const paymentRef = crypto.randomUUID().replace(/-/g, "");
  const contentSha256 = await sha256Hex(new TextEncoder().encode(paymentRef));
  return {
    contract_version: CONTRACT_VERSION,
    grant_id: grantId,
    org_id: orgId,
    kind: "term",
    placement: "queue",
    source: { kind: "paid", ref: paymentRef },
    plan: { plan_id: PLAN_ID, plan_version: PLAN_VERSION },
    duration: { unit: "month", count: 1 },
    allowance_credits: allowanceCredits,
    grace: { days: 7, cap_rule: "proportional" },
    paid_at: paidAt,
    evidence: {
      content_sha256: contentSha256,
      approvals: [{ credential_id: stack.credentialId, assertion: "stub" }],
    },
  };
}

async function grantPaid({ envelope, aboKid, aboSignature }) {
  return vendorCall("grant", {
    contract_version: CONTRACT_VERSION,
    abo_kid: aboKid,
    abo_signature: aboSignature,
    envelope_b64: envelopeB64(envelope),
  });
}

function installationIdForOrg(orgId) {
  const row = queryPlatformD1One(
    `SELECT installation_id FROM tenant_binding WHERE org_id = ${sqlLiteral(orgId)} AND status = 'active'`,
  );
  return row?.installation_id ?? null;
}

async function runQuotaDoAlarm(installationId) {
  const stub = platformProxy.env.DO.get(
    platformProxy.env.DO.idFromName(installationId),
  );
  if (typeof stub.runAlarm === "function") {
    await stub.runAlarm();
    return;
  }
  if (typeof stub.alarm === "function") {
    await stub.alarm();
    return;
  }
  throw new Error("quota DO alarm runner is unavailable in H-FS");
}

async function readAlertBodiesFromSendEmail() {
  const bodies = [];
  for (const capture of parseSendEmailCaptures()) {
    const text = await readSendEmailTextFile(capture.textFilePath);
    bodies.push(JSON.parse(text));
  }
  return bodies;
}

async function flushPlatformGrantAlerts(orgId) {
  clearPlatformLogBuffer();
  const installationId = installationIdForOrg(orgId);
  assert.ok(installationId, "org should have an active installation binding");
  await runQuotaDoAlarm(installationId);
}

async function buildComplimentaryEnvelope({
  orgId,
  grantId,
  count,
  operatorEmail = OPERATOR_EMAIL,
  reason,
}) {
  const ref = crypto.randomUUID().replace(/-/g, "");
  const contentSha256 = await sha256Hex(new TextEncoder().encode(ref));
  return {
    contract_version: CONTRACT_VERSION,
    grant_id: grantId,
    org_id: orgId,
    kind: "term",
    placement: "queue",
    source: {
      kind: "complimentary",
      ref,
      operator_email: operatorEmail,
      reason,
    },
    plan: { plan_id: PLAN_ID, plan_version: PLAN_VERSION },
    duration: { unit: "day", count },
    allowance_credits: ALLOWANCE_CREDITS,
    grace: { days: 7, cap_rule: "proportional" },
    evidence: {
      content_sha256: contentSha256,
      approvals: [{ credential_id: stack.credentialId, assertion: "stub" }],
    },
  };
}

function operationForHpGrant({ accessJwt, envelope }) {
  return {
    op: "grant",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: accessJwt,
      envelope,
    },
    actor_email: OPERATOR_EMAIL,
    issued_at: new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function hpComplimentaryGrant({ envelope, accessJwt }) {
  const jwt = accessJwt ?? (await mintAccessJwt(stack.accessTeam));
  const operation = operationForHpGrant({ accessJwt: jwt, envelope });
  const assertion = encodeVendorAssertion(
    await stack.authenticator.assert({
      operation,
      rpId: WEBAUTHN_RP_ID,
      origin: WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  return vendorCall(
    "grant",
    {
      contract_version: CONTRACT_VERSION,
      envelope,
      signer_credential_id: stack.credentialId,
      operation,
      assertion,
    },
    { accessJwt: jwt },
  );
}

async function opsFetch(pathname, init = {}) {
  const headers = new Headers(init.headers ?? {});
  if (!headers.has("host")) {
    headers.set("host", OPS_HOST);
  }
  if (!headers.has("Abo-Contract-Version")) {
    headers.set("Abo-Contract-Version", "1");
  }
  return fetch(`${ABO_URL}${pathname}`, {
    ...init,
    headers,
  });
}

function seedParkedGrantWork(workId) {
  const now = new Date().toISOString();
  runAboD1Command(
    `INSERT OR REPLACE INTO work (
      work_id, kind, subject_id, dedupe_key, state, attempts, next_attempt_at,
      lease_until, last_error, opened_at
    ) VALUES (
      ${sqlLiteral(workId)}, 'grant', ${sqlLiteral(workId)}, ${sqlLiteral(`parked-${workId}`)},
      'parked', 0, NULL, NULL, NULL, ${sqlLiteral(now)}
    )`,
  );
}

test("E2E-P7.2-05", async () => {
  const { orgId, installationId } = stack.clinics.orgA;
  ensurePlatformGrantPrerequisites(orgId, installationId);

  const beyondGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
  const beyondEnvelope = await buildPaidGrantEnvelope({
    orgId,
    grantId: beyondGrantId,
    allowanceCredits: ALLOWANCE_CREDITS + 1,
  });
  const beyondSignature = await aboGrantSigner.sign(beyondEnvelope);
  const beyond = await grantPaid({
    envelope: beyondEnvelope,
    aboKid: aboGrantSigner.kid,
    aboSignature: beyondSignature,
  });
  assert.equal(beyond.result, "rejected");
  assert.equal(beyond.code, "exceeds_plan_bound");

  for (let index = 0; index < 4; index += 1) {
    const grantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    const envelope = await buildPaidGrantEnvelope({
      orgId,
      grantId,
      allowanceCredits: ALLOWANCE_CREDITS,
    });
    const aboSignature = await aboGrantSigner.sign(envelope);
    const applied = await grantPaid({
      envelope,
      aboKid: aboGrantSigner.kid,
      aboSignature,
    });
    assert.equal(applied.result, "applied", `within-bound grant ${index + 1}`);
    await flushPlatformGrantAlerts(orgId);
  }

  const alertBodies = await readAlertBodiesFromSendEmail();
  const al11Bodies = alertBodies.filter((body) => body.code === "AL-11");
  const al17Bodies = alertBodies.filter((body) => body.code === "AL-17");
  assert.ok(al11Bodies.length >= 1, "paid grant should raise AL-11");
  assert.ok(
    al17Bodies.some((body) => body.org_id === orgId),
    "fourth paid grant within 24 hours should raise AL-17",
  );

  await triggerAboScheduled("0 6 * * *");
  const finding = queryAboD1One(
    `SELECT kind FROM finding WHERE kind = 'grant_without_payment' ORDER BY rowid DESC LIMIT 1`,
  );
  assert.equal(finding?.kind, "grant_without_payment");

  const accessJwt = await mintAccessJwt(stack.accessTeam);
  const hpEnvelope = await buildComplimentaryEnvelope({
    orgId,
    grantId: await grantIdComp(crypto.randomUUID().replace(/-/g, "")),
    count: 14,
    reason: "hp without assertion probe",
  });
  const withoutAssertion = await vendorCall(
    "grant",
    {
      contract_version: CONTRACT_VERSION,
      envelope: hpEnvelope,
      signer_credential_id: stack.credentialId,
      operation: operationForHpGrant({ accessJwt, envelope: hpEnvelope }),
    },
    { accessJwt },
  );
  assert.equal(withoutAssertion.result, "rejected");
  assert.equal(withoutAssertion.code, "assertion_required");

  const realEnvelope = await buildComplimentaryEnvelope({
    orgId,
    grantId: await grantIdComp(crypto.randomUUID().replace(/-/g, "")),
    count: 14,
    reason: "signed complimentary grant",
  });
  const shownEnvelope = {
    ...realEnvelope,
    grant_id: await grantIdComp(crypto.randomUUID().replace(/-/g, "")),
    source: {
      ...realEnvelope.source,
      reason: "shown to the operator",
    },
  };
  const signedOperation = operationForHpGrant({
    accessJwt,
    envelope: realEnvelope,
  });
  const assertion = encodeVendorAssertion(
    await stack.authenticator.assert({
      operation: signedOperation,
      rpId: WEBAUTHN_RP_ID,
      origin: WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  clearPlatformLogBuffer();
  const substituted = await vendorCall(
    "grant",
    {
      contract_version: CONTRACT_VERSION,
      envelope: realEnvelope,
      signer_credential_id: stack.credentialId,
      operation: signedOperation,
      assertion,
    },
    { accessJwt },
  );
  assert.equal(substituted.result, "applied");
  await flushPlatformGrantAlerts(orgId);
  const latestAlertText = await readLatestSendEmailText();
  assert.ok(latestAlertText, "complimentary grant should emit AL-11");
  const latestAlert = JSON.parse(latestAlertText);
  assert.equal(latestAlert.code, "AL-11");
  const signedParams = latestAlert.operation?.params;
  assert.deepEqual(signedParams?.source, realEnvelope.source);
  assert.notEqual(signedParams?.source, shownEnvelope.source);
});

test("E2E-P7.2-06", async () => {
  const { orgId, installationId, administrator } = stack.clinics.orgA;
  ensurePlatformGrantPrerequisites(orgId, installationId);
  const accessJwt = await mintAccessJwt(stack.accessTeam);

  const suspended = await vendorCall(
    "suspend",
    {
      contract_version: CONTRACT_VERSION,
      org_id: orgId,
      reason: "billing dispute",
    },
    { accessJwt },
  );
  assert.equal(suspended.result, "ok");

  const resumed = await vendorCall(
    "resume",
    {
      contract_version: CONTRACT_VERSION,
      org_id: orgId,
      reason: "resolved",
    },
    { accessJwt },
  );
  assert.equal(resumed.result, "ok");

  const killSwitch = await vendorCall(
    "armKillSwitch",
    {
      contract_version: CONTRACT_VERSION,
      scope: "capability",
      target: CAPABILITY_ID,
    },
    { accessJwt },
  );
  assert.equal(killSwitch.result, "ok");

  const billing = await rpc(administrator, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(billing.success, true);
  const billingToken = billing.data.token;
  await putBillingContact(billingToken);
  const checkout = await openCheckout(billingToken, "p72-class-h-cancel");
  const cancel = await opsFetch(`/ops/checkouts/${checkout.checkoutId}/cancel`, {
    method: "POST",
    headers: { "Cf-Access-Jwt-Assertion": accessJwt },
  });
  assert.equal(cancel.status, 200);

  const workId = crypto.randomUUID();
  seedParkedGrantWork(workId);
  const retry = await opsFetch(`/ops/parked/${workId}/retry`, {
    method: "POST",
    headers: { "Cf-Access-Jwt-Assertion": accessJwt },
  });
  assert.equal(retry.status, 200);

  const complimentaryEnvelope = await buildComplimentaryEnvelope({
    orgId,
    grantId: await grantIdComp(crypto.randomUUID().replace(/-/g, "")),
    count: 14,
    reason: "class hp jwt-only probe",
  });
  const hpJwtOnly = await vendorCall(
    "grant",
    {
      contract_version: CONTRACT_VERSION,
      envelope: complimentaryEnvelope,
      signer_credential_id: stack.credentialId,
      operation: operationForHpGrant({
        accessJwt,
        envelope: complimentaryEnvelope,
      }),
    },
    { accessJwt },
  );
  assert.equal(hpJwtOnly.result, "rejected");
  assert.equal(hpJwtOnly.code, "assertion_required");

  const ceilingJwtOnly = await vendorCall(
    "setCeilingPolicy",
    {
      contract_version: CONTRACT_VERSION,
      ...LAUNCH_CEILING_POLICY,
      signer_credential_id: stack.credentialId,
      operation: {
        op: "setCeilingPolicy",
        params: {
          contract_version: CONTRACT_VERSION,
          access_jwt: accessJwt,
          ...LAUNCH_CEILING_POLICY,
        },
        actor_email: OPERATOR_EMAIL,
        issued_at: new Date().toISOString(),
        nonce: crypto.randomUUID(),
        contract_version: CONTRACT_VERSION,
      },
    },
    { accessJwt },
  );
  assert.equal(ceilingJwtOnly.result, "rejected");
  assert.equal(ceilingJwtOnly.code, "assertion_required");

  const yearEnvelope = await buildComplimentaryEnvelope({
    orgId,
    grantId: await grantIdComp(crypto.randomUUID().replace(/-/g, "")),
    count: 365,
    reason: "year-long complimentary grant",
  });
  const yearBlocked = await hpComplimentaryGrant({
    envelope: yearEnvelope,
    accessJwt,
  });
  assert.equal(yearBlocked.result, "rejected");
  assert.equal(yearBlocked.code, "exceeds_ceiling");
});

test("E2E-P7.2-09", async () => {
  const { orgId, installationId } = stack.clinics.orgA;
  ensurePlatformGrantPrerequisites(orgId, installationId);
  const fixtureToken = "ci-staging-token";
  const complimentaryEnvelope = await buildComplimentaryEnvelope({
    orgId,
    grantId: await grantIdComp(crypto.randomUUID().replace(/-/g, "")),
    count: 14,
    reason: "ci staging fixture",
  });

  for (const method of [
    "grant",
    "setCeilingPolicy",
    "beginTransfer",
    "releaseHeld",
    "voidGrant",
  ]) {
    const args =
      method === "grant"
        ? {
            contract_version: CONTRACT_VERSION,
            envelope: complimentaryEnvelope,
            signer_credential_id: stack.credentialId,
            operation: operationForHpGrant({
              accessJwt: fixtureToken,
              envelope: complimentaryEnvelope,
            }),
          }
        : method === "setCeilingPolicy"
          ? {
              contract_version: CONTRACT_VERSION,
              ...LAUNCH_CEILING_POLICY,
              signer_credential_id: stack.credentialId,
              operation: {
                op: "setCeilingPolicy",
                params: {
                  contract_version: CONTRACT_VERSION,
                  access_jwt: fixtureToken,
                  ...LAUNCH_CEILING_POLICY,
                },
                actor_email: OPERATOR_EMAIL,
                issued_at: new Date().toISOString(),
                nonce: crypto.randomUUID(),
                contract_version: CONTRACT_VERSION,
              },
            }
          : method === "beginTransfer"
            ? {
                contract_version: CONTRACT_VERSION,
                org_id: orgId,
                from_installation_id: installationId,
                reason: "ci staging fixture",
                signer_credential_id: stack.credentialId,
                operation: {
                  op: "beginTransfer",
                  params: {
                    contract_version: CONTRACT_VERSION,
                    access_jwt: fixtureToken,
                    org_id: orgId,
                    from_installation_id: installationId,
                    reason: "ci staging fixture",
                  },
                  actor_email: OPERATOR_EMAIL,
                  issued_at: new Date().toISOString(),
                  nonce: crypto.randomUUID(),
                  contract_version: CONTRACT_VERSION,
                },
              }
            : method === "releaseHeld"
              ? {
                  contract_version: CONTRACT_VERSION,
                  org_id: orgId,
                  payment_id: crypto.randomUUID(),
                  signer_credential_id: stack.credentialId,
                  operation: {
                    op: "releaseHeld",
                    params: {
                      contract_version: CONTRACT_VERSION,
                      access_jwt: fixtureToken,
                      org_id: orgId,
                      payment_id: crypto.randomUUID(),
                    },
                    actor_email: OPERATOR_EMAIL,
                    issued_at: new Date().toISOString(),
                    nonce: crypto.randomUUID(),
                    contract_version: CONTRACT_VERSION,
                  },
                }
              : {
                  contract_version: CONTRACT_VERSION,
                  grant_id: crypto.randomUUID(),
                  reason: "ci staging fixture",
                  signer_credential_id: stack.credentialId,
                  operation: {
                    op: "voidGrant",
                    params: {
                      contract_version: CONTRACT_VERSION,
                      access_jwt: fixtureToken,
                      grant_id: crypto.randomUUID(),
                      reason: "ci staging fixture",
                    },
                    actor_email: OPERATOR_EMAIL,
                    issued_at: new Date().toISOString(),
                    nonce: crypto.randomUUID(),
                    contract_version: CONTRACT_VERSION,
                  },
                };

    const result = await vendorCall(method, args, { accessJwt: fixtureToken });
    assert.equal(result.result, "rejected", `${method} must reject fixture token`);
    assert.notEqual(result.code, "applied", `${method} must not apply`);
  }
});
