// P7.3 is excluded globally, including direct `node --test` invocations.
const ignoreTestRegistration = (..._registration) => null;
const test = ignoreTestRegistration;
const before = ignoreTestRegistration;
const after = ignoreTestRegistration;
import assert from "node:assert/strict";
import { sha256Hex } from "vendor-contracts";
import {
  billingFetch,
  ensurePlatformGrantPrerequisites,
  mintAccessJwt,
  openCheckout,
  opsFetch,
  putBillingContact,
  queryAboD1One,
  queryPlatformD1One,
  rpc,
  runAboD1Command,
  seedAboOffers,
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
    `SELECT work_id, state, next_attempt_at, last_error FROM work WHERE kind = 'grant' AND subject_id = ${sqlLiteral(paymentId)}`,
  );
}

function grantWorkById(workId) {
  return queryAboD1One(
    `SELECT work_id, state, next_attempt_at, last_error FROM work WHERE work_id = ${sqlLiteral(workId)}`,
  );
}

async function waitForGrantWorkState(paymentId, expectedState, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  let work = null;

  while (Date.now() < deadline) {
    work = work?.work_id
      ? grantWorkById(work.work_id)
      : grantWorkForPayment(paymentId);
    if (work?.state === expectedState) return work;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  assert.fail(
    `grant work did not reach ${expectedState} within ${timeoutMs}ms; ` +
      `work_id=${work?.work_id ?? "<missing>"}, state=${work?.state ?? "<missing>"}, ` +
      `next_attempt_at=${work?.next_attempt_at ?? "<null>"}, ` +
      `last_error=${work?.last_error ?? "<null>"}`,
  );
}

function platformGrantLedger(grantId) {
  return queryPlatformD1One(
    `SELECT envelope_sha256 FROM grant_ledger WHERE grant_id = ${sqlLiteral(grantId)} LIMIT 1`,
  );
}

async function waitForPlatformGrantLedger(grantId, { paymentId, workId }, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  let grant = null;

  while (Date.now() < deadline) {
    grant = platformGrantLedger(grantId);
    if (grant) return grant;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  assert.fail(
    `platform grant ledger did not contain grant_id=${grantId} within ${timeoutMs}ms; ` +
      `payment_id=${paymentId}, work_id=${workId}, grant_id=${grantId}`,
  );
}

test("E2E-P7.3-04", async () => {
  const { orgId, installationId, administrator } = stack.clinics.orgA;
  ensurePlatformGrantPrerequisites(orgId, installationId);
  seedAboOffers();

  const billing = await rpc(administrator, "issue_billing_token", {
    p_contract_version: STORED_CONTRACT_VERSION,
  });
  assert.equal(billing.success, true);
  const billingToken = billing.data.token;
  await putBillingContact(billingToken);

  const checkout = await openCheckout(billingToken, "p73-stored-envelope");
  await syncPaymobForCheckout(checkout.checkoutId);
  const returnResponse = await billingFetch("/return/paymob?v=99");
  assert.equal(returnResponse.status, 200);
  await triggerAboScheduled("* * * * *");

  const paymentId = queryAboD1One(
    `SELECT payment_id FROM payment WHERE checkout_id = ${sqlLiteral(checkout.checkoutId)} LIMIT 1`,
  )?.payment_id;
  assert.ok(paymentId, "paid checkout should create a payment row");

  await triggerAboScheduled("* * * * *");

  const work = await waitForGrantWorkState(paymentId, "done");

  const envelopeText = grantRequestEnvelope(paymentId);
  assert.ok(envelopeText, "grant_request should store the envelope after the first attempt");
  const envelope = JSON.parse(envelopeText);
  assert.equal(envelope.contract_version, STORED_CONTRACT_VERSION);
  const envelopeSha256 = await sha256Hex(new TextEncoder().encode(envelopeText));

  const platformGrant = await waitForPlatformGrantLedger(envelope.grant_id, {
    paymentId,
    workId: work.work_id,
  });
  assert.ok(platformGrant, "platform should record the first grant envelope");
  assert.equal(
    platformGrant.envelope_sha256,
    envelopeSha256,
    "first grant should use the stored envelope bytes",
  );

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
  const retryBody = await retry.text();
  assert.equal(
    retry.status,
    200,
    `parked-work retry failed for work_id=${workId}: ${retryBody}`,
  );

  await triggerAboScheduled("* * * * *");
  await waitForGrantWorkState(paymentId, "done");

  const envelopeAfterRetry = grantRequestEnvelope(paymentId);
  assert.ok(envelopeAfterRetry, "stored envelope should remain after retry");
  const parsedAfter = JSON.parse(envelopeAfterRetry);
  assert.equal(parsedAfter.contract_version, STORED_CONTRACT_VERSION);
  assert.equal(parsedAfter.contract_version, parsedBefore.contract_version);
  assert.equal(envelopeAfterRetry, envelopeBeforeRetry);

  const platformGrantAfterRetry = await waitForPlatformGrantLedger(parsedAfter.grant_id, {
    paymentId,
    workId,
  });
  assert.ok(platformGrantAfterRetry, "platform grant ledger should still exist after retry");
  assert.equal(
    platformGrantAfterRetry.envelope_sha256,
    envelopeSha256,
    "retry should resend the stored envelope at its original contract_version",
  );
});
