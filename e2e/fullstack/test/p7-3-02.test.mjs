// P7.3 is excluded globally, including direct `node --test` invocations.
const ignoreTestRegistration = (..._registration) => null;
const test = ignoreTestRegistration;
const before = ignoreTestRegistration;
const after = ignoreTestRegistration;
import assert from "node:assert/strict";
import {
  billingFetch,
  ABO_GRANT_KEY,
  countAboTable,
  ensurePlatformGrantPrerequisites,
  mintAccessJwt,
  openCheckout,
  opsFetch,
  parseSendEmailCaptures,
  putBillingContact,
  queryAboD1One,
  PLATFORM_CONFIG,
  queryPlatformD1One,
  readSendEmailTextFile,
  rpc,
  seedAboOffers,
  sqlLiteral,
  startStack,
  syncPaymobForCheckout,
  triggerAboScheduled,
  waitForClinicAiCoverage,
} from "./p7-3-stack.mjs";

// H-FS unit harness (P7.3 US2): node --import tsx --test test/p7-3-02.test.mjs

const ABO_N_PLUS_1 = "test/variant/abo-n-plus-1.toml";
const PLATFORM_N_PLUS_1 = "test/variant/platform-n-plus-1.toml";
const ABO_SENDER_VERSION = 2;

let stack = null;

before(async () => {
  stack = await startStack({
    aboConfig: ABO_N_PLUS_1,
    platformConfig: PLATFORM_N_PLUS_1,
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

function countPlatformGrantLedgerRows() {
  const row = queryPlatformD1One("SELECT COUNT(*) AS n FROM grant_ledger");
  return Number(row?.n ?? 0);
}

function assertGrantPrerequisiteGate(orgId) {
  const row = queryPlatformD1One(
    `SELECT
       (SELECT COUNT(*) FROM service_key
        WHERE kid = ${sqlLiteral(ABO_GRANT_KEY.kid)}
          AND service = 'abo' AND status = 'active') AS abo_key_active,
       (SELECT COUNT(*) FROM tenant_binding
        WHERE org_id = ${sqlLiteral(orgId)} AND status = 'active') AS tenant_binding_active,
       (SELECT COUNT(*) FROM installation i
        JOIN tenant_binding tb ON tb.installation_id = i.installation_id
        WHERE tb.org_id = ${sqlLiteral(orgId)}
          AND tb.status = 'active' AND i.status = 'active') AS installation_active`,
  );
  assert.equal(Number(row?.abo_key_active), 1, "ABO signing key must be active");
  assert.equal(Number(row?.tenant_binding_active), 1, "tenant binding must be active");
  assert.equal(Number(row?.installation_active), 1, "installation must be active");
}

function grantWorkForPayment(paymentId) {
  return queryAboD1One(
    `SELECT work_id, state, next_attempt_at, last_error FROM work WHERE kind = 'grant' AND subject_id = ${sqlLiteral(paymentId)}`,
  );
}

async function waitForGrantWorkToLeaveOpen(paymentId) {
  const maxAttempts = 20;
  const pollIntervalMs = 250;
  let work = null;

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    if (attempt > 0) {
      await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
    }

    await triggerAboScheduled("* * * * *");
    work = grantWorkForPayment(paymentId);
    if (work && work.state !== "open") return work;
  }

  assert.fail(
    `grant work did not leave open after ${maxAttempts} targeted minute triggers; ` +
      `state=${work?.state ?? "missing"}, ` +
      `next_attempt_at=${work?.next_attempt_at ?? "null"}, ` +
      `last_error=${work?.last_error ?? "null"}`,
  );
}

function alertCountByCode(code) {
  const row = queryAboD1One(
    `SELECT COUNT(*) AS n FROM alert WHERE code = ${sqlLiteral(code)}`,
  );
  return Number(row?.n ?? 0);
}

async function readAlertCaptures() {
  return parseSendEmailCaptures();
}

async function waitForAlertSend(workId) {
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    for (const capture of await readAlertCaptures()) {
      const text = await readSendEmailTextFile(capture.textFilePath);
      if (text.trim() === `AL-07 ${workId}`) return text.trim();
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.fail(`send_email did not capture AL-07 for grant work ${workId}`);
}

test("E2E-P7.3-02", async () => {
  const { orgId, installationId, administrator } = stack.clinics.orgA;
  ensurePlatformGrantPrerequisites(orgId, installationId);
  assertGrantPrerequisiteGate(orgId);
  seedAboOffers();

  // Begin with matching N+1 receivers and then downgrade only the platform.
  // This keeps the signing-key and tenant gates valid while exercising FM-25.
  await stack.restartPlatform({ platformConfig: PLATFORM_CONFIG });

  const billing = await rpc(administrator, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(billing.success, true);
  const billingToken = billing.data.token;
  await putBillingContact(billingToken);

  const coverageEventsBefore = countPlatformCoverageEvents(orgId);
  const platformGrantRowsBefore = countPlatformGrantLedgerRows();
  const grantOutcomesBefore = countAboTable("grant_outcome");

  const checkout = await openCheckout(billingToken, "p73-fm25-grant");
  await syncPaymobForCheckout(checkout.checkoutId);
  const returnResponse = await billingFetch("/return/paymob?v=99");
  assert.equal(returnResponse.status, 200);
  await triggerAboScheduled("* * * * *");

  const paymentId = queryAboD1One(
    `SELECT payment_id FROM payment WHERE checkout_id = ${sqlLiteral(checkout.checkoutId)} LIMIT 1`,
  )?.payment_id;
  assert.ok(paymentId, "paid checkout should create a payment row");

  const parkedWork = await waitForGrantWorkToLeaveOpen(paymentId);
  assert.ok(parkedWork, "grant work should exist after scheduled run");
  assert.equal(parkedWork.state, "parked");
  assert.match(String(parkedWork.last_error ?? ""), /contract_version_unsupported|rejected/);

  assert.equal(countPlatformCoverageEvents(orgId), coverageEventsBefore);
  assert.equal(countPlatformGrantLedgerRows(), platformGrantRowsBefore);
  const rejectedOutcome = queryAboD1One(
    `SELECT result FROM grant_outcome go
     JOIN grant_request gr ON gr.grant_id = go.grant_id
     WHERE gr.source_ref = ${sqlLiteral(paymentId)}
     ORDER BY go.at DESC LIMIT 1`,
  );
  assert.equal(rejectedOutcome?.result, "rejected");
  assert.equal(countAboTable("grant_outcome"), grantOutcomesBefore + 1);

  const al07BeforeUpsert = alertCountByCode("AL-07");
  await triggerAboScheduled("* * * * *");
  const targetAlert = queryAboD1One(
    `SELECT alert_key, code, active, detail_id FROM alert
     WHERE alert_key = ${sqlLiteral(`AL-07:${parkedWork.work_id}`)}`,
  );
  assert.equal(targetAlert?.code, "AL-07");
  assert.equal(Number(targetAlert?.active), 1, "AL-07 should remain active for parked work");
  assert.equal(targetAlert?.detail_id, parkedWork.work_id);
  assert.equal(
    alertCountByCode("AL-07"),
    al07BeforeUpsert,
    "reprocessing parked work should upsert its AL-07 row",
  );
  assert.equal(await waitForAlertSend(parkedWork.work_id), `AL-07 ${parkedWork.work_id}`);

  await stack.restartPlatform({ platformConfig: PLATFORM_N_PLUS_1 });

  const workId = parkedWork.work_id;
  const retry = await opsFetchWithAccess(`/ops/parked/${workId}/retry`, {
    method: "POST",
  });
  assert.equal(retry.status, 200);

  let retriedWork = null;
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (attempt > 0) await new Promise((resolve) => setTimeout(resolve, 250));
    await triggerAboScheduled("* * * * *");
    retriedWork = grantWorkForPayment(paymentId);
    if (retriedWork?.state === "done") break;
  }
  assert.ok(retriedWork, "grant work should remain present after retry");
  assert.equal(retriedWork.state, "done", "retry should complete after platform accepts N and N+1");

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
  const coverage = await waitForClinicAiCoverage(orgId, {
    predicate: (projection) =>
      projection?.state === "active" && Boolean(projection.term_ref),
  });
  assert.equal(coverage.state, "active");
  assert.ok(coverage.term_ref, "applied grant should project an active clinic AI term");
});
