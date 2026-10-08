import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import {
  billingFetch,
  countAboTable,
  ensurePlatformGrantPrerequisites,
  mintAccessJwt,
  openCheckout,
  opsFetch,
  parseSendEmailCaptures,
  putBillingContact,
  queryAboD1One,
  queryPlatformD1One,
  readLatestSendEmailText,
  readSendEmailTextFile,
  rpc,
  sqlLiteral,
  startStack,
  syncPaymobForCheckout,
  triggerAboScheduled,
} from "./p7-3-stack.mjs";

// H-FS unit harness (P7.3 US2): node --import tsx --test test/p7-3-02.test.mjs

const ABO_N_PLUS_1 = "test/variant/abo-n-plus-1.toml";
const PLATFORM_N_PLUS_1 = "test/variant/platform-n-plus-1.toml";
const ABO_SENDER_VERSION = 2;

let stack = null;

before(async () => {
  stack = await startStack({
    aboConfig: ABO_N_PLUS_1,
  });
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

function countPlatformCoverageEvents(orgId) {
  const row = queryPlatformD1One(
    `SELECT COUNT(*) AS n FROM coverage_event WHERE org_id = ${sqlLiteral(orgId)}`,
  );
  return Number(row?.n ?? 0);
}

function grantWorkForPayment(paymentId) {
  return queryAboD1One(
    `SELECT work_id, state, last_error FROM work WHERE kind = 'grant' AND subject_id = ${sqlLiteral(paymentId)}`,
  );
}

function alertCountByCode(code) {
  const row = queryAboD1One(
    `SELECT COUNT(*) AS n FROM alert WHERE code = ${sqlLiteral(code)}`,
  );
  return Number(row?.n ?? 0);
}

async function readLatestAlertBody() {
  const captures = parseSendEmailCaptures();
  assert.ok(captures.length > 0, "send_email should capture AL-07");
  const text = await readSendEmailTextFile(captures[captures.length - 1].textFilePath);
  return JSON.parse(text);
}

test("E2E-P7.3-02", async () => {
  const { orgId, installationId, administrator } = stack.clinics.orgA;
  ensurePlatformGrantPrerequisites(orgId, installationId);

  const billing = await rpc(administrator, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(billing.success, true);
  const billingToken = billing.data.token;
  await putBillingContact(billingToken);

  const coverageEventsBefore = countPlatformCoverageEvents(orgId);
  const grantOutcomesBefore = countAboTable("grant_outcome");

  const checkout = await openCheckout(billingToken, "p73-fm25-grant");
  await syncPaymobForCheckout(checkout.checkoutId);

  const paymentId = queryAboD1One(
    `SELECT payment_id FROM payment WHERE checkout_id = ${sqlLiteral(checkout.checkoutId)} LIMIT 1`,
  )?.payment_id;
  assert.ok(paymentId, "paid checkout should create a payment row");

  await triggerAboScheduled("0 * * * *");

  const parkedWork = grantWorkForPayment(paymentId);
  assert.ok(parkedWork, "grant work should exist after scheduled run");
  assert.equal(parkedWork.state, "parked");
  assert.match(String(parkedWork.last_error ?? ""), /contract_version_unsupported|rejected/);

  assert.equal(countPlatformCoverageEvents(orgId), coverageEventsBefore);
  assert.equal(countAboTable("grant_outcome"), grantOutcomesBefore);

  const al07Before = alertCountByCode("AL-07");
  await triggerAboScheduled("0 * * * *");
  assert.ok(alertCountByCode("AL-07") > al07Before, "FM-25 should raise AL-07");

  const alertBody = await readLatestAlertBody();
  assert.equal(alertBody.code, "AL-07");

  await stack.restartPlatform({ platformConfig: PLATFORM_N_PLUS_1 });

  const workId = parkedWork.work_id;
  const retry = await opsFetchWithAccess(`/ops/parked/${workId}/retry`, {
    method: "POST",
  });
  assert.equal(retry.status, 200);

  await triggerAboScheduled("0 * * * *");

  const retriedWork = grantWorkForPayment(paymentId);
  assert.ok(retriedWork);
  assert.notEqual(retriedWork.state, "parked", "retry should apply after platform accepts N and N+1");

  const grantOutcome = queryAboD1One(
    `SELECT result FROM grant_outcome go
     JOIN grant_request gr ON gr.grant_id = go.grant_id
     WHERE gr.source_ref = ${sqlLiteral(paymentId)}
     ORDER BY go.at DESC LIMIT 1`,
  );
  assert.ok(grantOutcome, "grant should be written after retry");
  assert.equal(grantOutcome.result, "applied");
  assert.ok(
    countPlatformCoverageEvents(orgId) > coverageEventsBefore,
    "platform should receive the grant after retry",
  );
});
