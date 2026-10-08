import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { sha256Hex } from "vendor-contracts";
import {
  ensurePlatformGrantPrerequisites,
  mintAccessJwt,
  openCheckout,
  opsFetch,
  putBillingContact,
  queryAboD1One,
  queryPlatformD1One,
  rpc,
  runAboD1Command,
  sqlLiteral,
  startStack,
  syncPaymobForCheckout,
  triggerAboScheduled,
} from "./p7-3-stack.mjs";

// H-FS unit harness (P7.3 US2): node --import tsx --test test/p7-3-04.test.mjs

const STORED_CONTRACT_VERSION = 1;

let stack = null;

before(async () => {
  stack = await startStack();
});

after(async () => {
  await stack?.stop();
  stack = null;
});

async function opsFetchWithAccess(pathname, init = {}) {
  const accessJwt = await mintAccessJwt(stack.accessTeam);
  const headers = new Headers(init.headers ?? {});
  headers.set("Cf-Access-Jwt-Assertion", accessJwt);
  return opsFetch(pathname, { ...init, headers });
}

function grantRequestEnvelope(paymentId) {
  const row = queryAboD1One(
    `SELECT envelope FROM grant_request WHERE source_ref = ${sqlLiteral(paymentId)} LIMIT 1`,
  );
  return row?.envelope ?? null;
}

function grantWorkForPayment(paymentId) {
  return queryAboD1One(
    `SELECT work_id, state FROM work WHERE kind = 'grant' AND subject_id = ${sqlLiteral(paymentId)}`,
  );
}

function platformGrantLedger(grantId) {
  return queryPlatformD1One(
    `SELECT envelope_sha256 FROM grant_ledger WHERE grant_id = ${sqlLiteral(grantId)} LIMIT 1`,
  );
}

test("E2E-P7.3-04", async () => {
  const { orgId, installationId, administrator } = stack.clinics.orgA;
  ensurePlatformGrantPrerequisites(orgId, installationId);

  const billing = await rpc(administrator, "issue_billing_token", {
    p_contract_version: STORED_CONTRACT_VERSION,
  });
  assert.equal(billing.success, true);
  const billingToken = billing.data.token;
  await putBillingContact(billingToken);

  const checkout = await openCheckout(billingToken, "p73-stored-envelope");
  await syncPaymobForCheckout(checkout.checkoutId);

  const paymentId = queryAboD1One(
    `SELECT payment_id FROM payment WHERE checkout_id = ${sqlLiteral(checkout.checkoutId)} LIMIT 1`,
  )?.payment_id;
  assert.ok(paymentId, "paid checkout should create a payment row");

  await triggerAboScheduled("0 * * * *");

  const envelopeText = grantRequestEnvelope(paymentId);
  assert.ok(envelopeText, "grant_request should store the envelope after the first attempt");
  const envelope = JSON.parse(envelopeText);
  assert.equal(envelope.contract_version, STORED_CONTRACT_VERSION);
  const envelopeSha256 = await sha256Hex(new TextEncoder().encode(envelopeText));

  const platformGrant = platformGrantLedger(envelope.grant_id);
  assert.ok(platformGrant, "platform should record the first grant envelope");
  assert.equal(
    platformGrant.envelope_sha256,
    envelopeSha256,
    "first grant should use the stored envelope bytes",
  );

  const work = grantWorkForPayment(paymentId);
  assert.ok(work, "grant work should exist");
  assert.equal(work.state, "done", "published pair should apply the first grant attempt");
  const workId = work.work_id;

  runAboD1Command(
    `UPDATE work SET state = 'parked', lease_until = NULL, last_error = 'contract_version_unsupported' WHERE work_id = ${sqlLiteral(workId)}`,
  );

  const envelopeBeforeRetry = grantRequestEnvelope(paymentId);
  assert.ok(envelopeBeforeRetry);
  const parsedBefore = JSON.parse(envelopeBeforeRetry);
  assert.equal(parsedBefore.contract_version, STORED_CONTRACT_VERSION);

  const retry = await opsFetchWithAccess(`/ops/parked/${workId}/retry`, {
    method: "POST",
  });
  assert.equal(retry.status, 200);

  await triggerAboScheduled("0 * * * *");

  const envelopeAfterRetry = grantRequestEnvelope(paymentId);
  assert.ok(envelopeAfterRetry, "stored envelope should remain after retry");
  const parsedAfter = JSON.parse(envelopeAfterRetry);
  assert.equal(parsedAfter.contract_version, STORED_CONTRACT_VERSION);
  assert.equal(parsedAfter.contract_version, parsedBefore.contract_version);
  assert.equal(envelopeAfterRetry, envelopeBeforeRetry);

  const platformGrantAfterRetry = platformGrantLedger(parsedAfter.grant_id);
  assert.ok(platformGrantAfterRetry, "platform grant ledger should still exist after retry");
  assert.equal(
    platformGrantAfterRetry.envelope_sha256,
    envelopeSha256,
    "retry should resend the stored envelope at its original contract_version",
  );
});
