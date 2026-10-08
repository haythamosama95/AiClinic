import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import {
  billingFetch,
  countAboTable,
  queryAboD1One,
  runAboD1Command,
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

function seedOpenCheckout(checkoutId) {
  const now = new Date().toISOString();
  runAboD1Command(
    `INSERT OR REPLACE INTO checkout (
      checkout_id, org_id, offer_id, offer_version, terms_version, currency,
      amount_minor, client_request_id, return_url, state, created_at, updated_at
    ) VALUES (
      ${sqlLiteral(checkoutId)},
      ${sqlLiteral(stack.clinics.orgA.orgId)},
      '01JHARNESSOFFERPUBLISH001',
      2,
      1,
      'EGP',
      80000,
      ${sqlLiteral(`p73-return-${checkoutId}`)},
      'https://billing.vendor.test/return/paymob?v=99',
      'open',
      ${sqlLiteral(now)},
      ${sqlLiteral(now)}
    )`,
  );
  runAboD1Command(
    `INSERT OR REPLACE INTO checkout_status (checkout_id, state, updated_at)
     VALUES (${sqlLiteral(checkoutId)}, 'open', ${sqlLiteral(now)})`,
  );
}

test("E2E-P7.3-07", async () => {
  seedOpenCheckout(CHECKOUT_ID);
  const paymentsBefore = countAboTable("payment");
  const confirmsBefore = scheduledConfirmCount(CHECKOUT_ID);

  const response = await billingFetch("/return/paymob?v=99");
  assert.equal(response.status, 200);
  const html = (await response.text()).toLowerCase();
  assert.equal(html.includes("contract_version_unsupported"), false);
  assert.equal(html.includes("payment successful"), false);
  assert.equal(html.includes("payment failed"), false);
  assert.equal(html.includes("checkout paid"), false);

  assert.equal(countAboTable("payment"), paymentsBefore);
  assert.equal(scheduledConfirmCount(CHECKOUT_ID), confirmsBefore + 1);
});
