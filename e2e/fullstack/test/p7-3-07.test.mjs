import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import {
  billingFetch,
  countAboTable,
  openCheckout,
  putBillingContact,
  queryAboD1One,
  rpc,
  seedAboOffers,
  sqlLiteral,
  startStack,
} from "./p7-3-stack.mjs";

// H-FS unit harness (P7.3 US1): node --import tsx --test test/p7-3-07.test.mjs

const CHECKOUT_ID = "01JP73RETURNCHECKOUT007";

let stack = null;

before(async () => {
  stack = await startStack();
});

after(async () => {
  await stack?.stop();
  stack = null;
});

function scheduledConfirmCount(checkoutId) {
  const row = queryAboD1One(
    `SELECT COUNT(*) AS n FROM work WHERE kind = 'confirm' AND dedupe_key = ${sqlLiteral(`confirm-schedule:${checkoutId}`)}`,
  );
  return Number(row?.n ?? 0);
}

test("E2E-P7.3-07", async () => {
  const { administrator } = stack.clinics.orgA;
  seedAboOffers();
  const billing = await rpc(administrator, "issue_billing_token", {
    p_contract_version: 1,
  });
  assert.equal(billing.success, true);
  await putBillingContact(billing.data.token);
  const checkout = await openCheckout(billing.data.token, `p73-return-${CHECKOUT_ID}`);

  const paymentsBefore = countAboTable("payment");
  const confirmsBefore = scheduledConfirmCount(checkout.checkoutId);

  const response = await billingFetch("/return/paymob?v=99");
  assert.equal(response.status, 200);
  const html = (await response.text()).toLowerCase();
  assert.equal(html.includes("contract_version_unsupported"), false);
  assert.equal(html.includes("payment successful"), false);
  assert.equal(html.includes("payment failed"), false);
  assert.equal(html.includes("checkout paid"), false);

  assert.equal(countAboTable("payment"), paymentsBefore);
  assert.equal(scheduledConfirmCount(checkout.checkoutId), confirmsBefore + 1);
});
