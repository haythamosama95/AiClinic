import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import {
  PAYMOB_HMAC_SECRET,
  PAYMOB_URL,
  billingFetch,
  countAboTable,
  countAboWork,
  ensurePlatformGrantPrerequisites,
  openCheckout,
  platformFetch,
  putBillingContact,
  queryAboD1One,
  readClinicAiCoverage,
  readStatusRefreshRequestedAt,
  rpc,
  seedAboOffers,
  signPaymobObj,
  sqlLiteral,
  startStack,
  syncPaymobForCheckout,
  triggerAboScheduled,
} from "./p7-2-stack.mjs";

// H-FS unit harness (P7.2 US1): node --import tsx --test test/p7-2-untrusted-callers.test.mjs

let stack = null;

before(async () => {
  stack = await startStack();
});

after(async () => {
  await stack?.stop();
  stack = null;
});

function junkNotifyBody(index = 0) {
  return JSON.stringify({
    type: "TRANSACTION",
    obj: {
      amount_cents: String(100 + index),
      created_at: new Date().toISOString(),
      currency: "EGP",
      error_occured: false,
      has_parent_transaction: false,
      id: 88000 + index,
      integration_id: 123456,
      is_3d_secure: true,
      is_auth: false,
      is_capture: true,
      is_refunded: false,
      is_standalone_payment: true,
      is_voided: false,
      order: { id: 99000 + index },
      owner: 0,
      pending: false,
      source_data: { pan: "2346", sub_type: "MasterCard", type: "card" },
      success: true,
    },
  });
}

test("E2E-P7.2-01", async () => {
  const notificationsBefore = countAboTable("notification");
  const workBefore = countAboWork();

  const junk = await billingFetch("/notify/paymob?hmac=deadbeef", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": "203.0.113.50",
    },
    body: junkNotifyBody(1),
  });
  assert.equal(junk.status, 401);
  assert.equal(countAboTable("notification"), notificationsBefore);
  assert.equal(countAboWork(), workBefore);

  const oversizeBody = "x".repeat(1_048_577);
  const oversize = await billingFetch("/notify/paymob", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": "203.0.113.51",
    },
    body: oversizeBody,
  });
  assert.equal(oversize.status, 413);
  assert.equal(await oversize.text(), "");
  assert.equal(countAboTable("notification"), notificationsBefore);
  assert.equal(countAboWork(), workBefore);

  const rateIp = "203.0.113.52";
  for (let index = 0; index < 60; index += 1) {
    const response = await billingFetch("/notify/paymob?hmac=deadbeef", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "cf-connecting-ip": rateIp,
      },
      body: junkNotifyBody(100 + index),
    });
    assert.equal(response.status, 401);
  }
  const limited = await billingFetch("/notify/paymob?hmac=deadbeef", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": rateIp,
    },
    body: junkNotifyBody(999),
  });
  assert.equal(limited.status, 429);
  assert.equal(await limited.text(), "");
  assert.equal(countAboTable("notification"), notificationsBefore);
  assert.equal(countAboWork(), workBefore);

  const unknownKeyIp = "unknown";
  for (let index = 0; index < 60; index += 1) {
    await billingFetch("/notify/paymob?hmac=deadbeef", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: junkNotifyBody(200 + index),
    });
  }
  const unknownLimited = await billingFetch("/notify/paymob?hmac=deadbeef", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: junkNotifyBody(299),
  });
  assert.equal(unknownLimited.status, 429);

  const paymentsBeforeReturn = countAboTable("payment");
  const coverageBeforeReturn = readClinicAiCoverage(stack.clinics.orgA.orgId);
  const returnResponse = await billingFetch("/return/paymob?v=99");
  assert.equal(returnResponse.status, 200);
  assert.equal(countAboTable("payment"), paymentsBeforeReturn);
  assert.deepEqual(
    readClinicAiCoverage(stack.clinics.orgA.orgId),
    coverageBeforeReturn,
    "/return must not create or extend service",
  );
});

test("E2E-P7.2-02", async () => {
  const { staff, orgId } = stack.clinics.orgA;
  const coverageBefore = readClinicAiCoverage(orgId);
  const refreshBefore = readStatusRefreshRequestedAt(orgId);

  const billing = await rpc(staff, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(billing.success, false);
  assert.equal(billing.error_code, "FORBIDDEN_ROLE");

  const aiToken = await rpc(staff, "issue_ai_token", {
    p_contract_version: 1,
  });
  assert.ok(aiToken, "staff should still mint an AI token for coverage probe");

  const coverage = await platformFetch("/v1/coverage", {
    headers: { authorization: `Bearer ${aiToken}` },
  });
  assert.equal(coverage.status, 403);

  const status = await rpc(staff, "get_ai_status", {
    p_contract_version: 1,
  });
  assert.equal(status.success, true);

  const refresh = await rpc(staff, "request_ai_status_refresh", {
    p_contract_version: 1,
  });
  assert.equal(refresh.success, false);
  assert.notEqual(refresh.error_code, "FORBIDDEN_ROLE");

  assert.deepEqual(readClinicAiCoverage(orgId), coverageBefore);
  assert.equal(readStatusRefreshRequestedAt(orgId), refreshBefore);
});

function tokenOrgClaim(token) {
  const payload = token.split(".")[1];
  const decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
  return decoded.org;
}

test("E2E-P7.2-03", async () => {
  const { orgA, orgB } = stack.clinics;
  seedAboOffers();
  ensurePlatformGrantPrerequisites(orgA.orgId, orgA.installationId);
  ensurePlatformGrantPrerequisites(orgB.orgId, orgB.installationId);

  const billingB = await rpc(orgB.administrator, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(billingB.success, true);
  const billingTokenB = billingB.data.token;

  await putBillingContact(billingTokenB);
  const checkoutB = await openCheckout(billingTokenB, "p72-org-b-checkout");
  await syncPaymobForCheckout(checkoutB.checkoutId);

  const billingA = await rpc(orgA.administrator, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(billingA.success, true);
  const billingTokenA = billingA.data.token;
  assert.equal(tokenOrgClaim(billingTokenA), orgA.orgId);
  assert.notEqual(tokenOrgClaim(billingTokenA), orgB.orgId);

  await putBillingContact(billingTokenA);
  const checkoutA = await openCheckout(billingTokenA, "p72-org-a-checkout");

  const coverageBBefore = readClinicAiCoverage(orgB.orgId);
  const paymentCountBBefore = countAboTable("payment");
  const checkoutBStatusBefore = queryAboD1One(
    `SELECT state FROM checkout_status WHERE checkout_id = ${sqlLiteral(checkoutB.checkoutId)}`,
  );

  const foreignCheckout = await billingFetch(`/v1/checkouts/${checkoutB.checkoutId}`, {
    headers: { authorization: `Bearer ${billingTokenA}` },
  });
  assert.equal(foreignCheckout.status, 404);
  const foreignBody = await foreignCheckout.json();
  assert.equal(foreignBody.code, "not_found");

  for (const route of [
    "/v1/offers",
    "/v1/subscription",
    "/v1/payments",
    "/v1/billing-contact",
    "/v1/checkouts?open=1",
  ]) {
    const response = await billingFetch(route, {
      headers: { authorization: `Bearer ${billingTokenA}` },
    });
    assert.equal(response.status, 200, `${route} should answer for org A session`);
    const text = await response.text();
    assert.ok(
      !text.includes(checkoutB.checkoutId) && !text.includes(checkoutB.reference),
      `${route} must not expose org B checkout ids`,
    );
  }

  const aiTokenA = await rpc(orgA.administrator, "issue_ai_token", {
    p_contract_version: 1,
  });
  assert.equal(tokenOrgClaim(aiTokenA), orgA.orgId);

  const capabilities = await platformFetch("/v1/capabilities", {
    headers: { authorization: `Bearer ${aiTokenA}` },
  });
  assert.equal(capabilities.status, 200);

  const coverage = await platformFetch("/v1/coverage", {
    headers: { authorization: `Bearer ${aiTokenA}` },
  });
  assert.equal(coverage.status, 200);
  const coverageBody = await coverage.json();
  assert.notEqual(coverageBody.subscription_ref, checkoutB.reference);

  const feed = await platformFetch("/v1/feed/coverage", {
    headers: { authorization: `Bearer ${aiTokenA}` },
  });
  assert.equal(feed.status, 404);

  const requestBody = {
    contract_version: 1,
    capability_id: "clinic.visit_summary",
    capability_version: "1.0.0",
    policy_id: "standard",
    policy_version: "1",
    idempotency_key: `p72-cross-tenant-${crypto.randomUUID()}`,
    trace_id: crypto.randomUUID(),
    input: { visit_id: orgB.branchId },
  };
  const request = await platformFetch("/v1/requests", {
    method: "POST",
    headers: {
      authorization: `Bearer ${aiTokenA}`,
      "content-type": "application/json",
      "x-idempotency-key": requestBody.idempotency_key,
    },
    body: JSON.stringify(requestBody),
  });
  assert.notEqual(request.status, 201);

  const checkoutBStatusAfter = queryAboD1One(
    `SELECT state FROM checkout_status WHERE checkout_id = ${sqlLiteral(checkoutB.checkoutId)}`,
  );
  assert.deepEqual(checkoutBStatusAfter, checkoutBStatusBefore);
  assert.ok(
    queryAboD1One(
      `SELECT checkout_id FROM checkout WHERE checkout_id = ${sqlLiteral(checkoutA.checkoutId)} AND org = ${sqlLiteral(orgA.orgId)}`,
    ),
    "org A checkout stays under org A",
  );
  assert.equal(
    queryAboD1One(
      `SELECT checkout_id FROM checkout WHERE checkout_id = ${sqlLiteral(checkoutA.checkoutId)} AND org = ${sqlLiteral(orgB.orgId)}`,
    ),
    null,
    "org A open checkout must not lock org B resources",
  );

  assert.deepEqual(readClinicAiCoverage(orgB.orgId), coverageBBefore);
  assert.equal(countAboTable("payment"), paymentCountBBefore);
});

test("E2E-P7.2-04", async () => {
  const { orgA } = stack.clinics;
  seedAboOffers();
  ensurePlatformGrantPrerequisites(orgA.orgId, orgA.installationId);

  const billing = await rpc(orgA.administrator, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(billing.success, true);
  const billingToken = billing.data.token;

  await putBillingContact(billingToken);
  const checkout = await openCheckout(billingToken, "p72-forged-callback");
  await syncPaymobForCheckout(checkout.checkoutId);

  const checkoutRow = queryAboD1One(
    `SELECT c.charged_price_minor, c.currency, pi.order_id
     FROM checkout c
     LEFT JOIN paymob_intention pi ON pi.checkout_id = c.checkout_id
     WHERE c.checkout_id = '${checkout.checkoutId}'`,
  );
  assert.ok(checkoutRow?.order_id, "checkout should have a stored Paymob order id");

  const paymentsBefore = countAboTable("payment");
  const forgedObj = {
    amount_cents: String(checkoutRow.charged_price_minor),
    created_at: new Date().toISOString(),
    currency: checkoutRow.currency,
    error_occured: false,
    has_parent_transaction: false,
    id: 99123,
    integration_id: 123456,
    is_3d_secure: true,
    is_auth: false,
    is_capture: true,
    is_refunded: false,
    is_standalone_payment: true,
    is_voided: false,
    order: { id: Number(checkoutRow.order_id) + 9999 },
    owner: 0,
    pending: false,
    source_data: { pan: "2346", sub_type: "MasterCard", type: "card" },
    success: true,
  };
  const hmac = await signPaymobObj(forgedObj, PAYMOB_HMAC_SECRET);
  const notify = await billingFetch(
    `/notify/paymob?hmac=${encodeURIComponent(hmac)}`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "cf-connecting-ip": "203.0.113.60",
      },
      body: JSON.stringify({ type: "TRANSACTION", obj: forgedObj }),
    },
  );
  assert.equal(notify.status, 200);

  await triggerAboScheduled("* * * * *");
  await triggerAboScheduled("0 6 * * *");

  assert.equal(
    countAboTable("payment"),
    paymentsBefore,
    "forged callback with leaked HMAC must not create a payment",
  );

  const inquiryScript = await fetch(`${PAYMOB_URL}/__script`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ inquiry: "bound_success" }),
  });
  assert.equal(inquiryScript.status, 200);

  await triggerAboScheduled("* * * * *");
  assert.equal(
    countAboTable("payment"),
    paymentsBefore,
    "inquiry must not confirm a forged callback",
  );
});
