/**
 * P4.3 — Paymob notify intake and confirm E2E tests (H-ABO + H-PAY).
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import badHmacFixture from "../fixtures/paymob/bad-hmac.json";
import declineFixture from "../fixtures/paymob/decline.json";
import refundChildFixture from "../fixtures/paymob/refund-child.json";
import refundParentFixture from "../fixtures/paymob/refund-parent.json";
import successFixture from "../fixtures/paymob/success.json";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import {
  applySql,
  billingFetch,
  resetHarnessState,
  r2GetText,
  scriptPaymobInquiry,
  setClock,
  setD1BatchThrows,
  setIntakeR2PutThrows,
  tableCount,
} from "./harness";

type PaymobCallbackObj = {
  amount_cents: string | number;
  created_at: string;
  currency: string;
  error_occured: boolean;
  has_parent_transaction: boolean;
  id: number | string;
  integration_id: number | string;
  is_3d_secure: boolean;
  is_auth: boolean;
  is_capture: boolean;
  is_refunded: boolean;
  is_standalone_payment: boolean;
  is_voided: boolean;
  order: { id: number | string };
  owner: number | string;
  pending: boolean;
  source_data: {
    pan: string;
    sub_type: string;
    type: string;
  };
  success: boolean;
};

type PaymobCallbackFixture = {
  type: string;
  obj: PaymobCallbackObj;
};

const PAYMOB_HMAC_FIELDS = [
  "amount_cents",
  "created_at",
  "currency",
  "error_occured",
  "has_parent_transaction",
  "id",
  "integration_id",
  "is_3d_secure",
  "is_auth",
  "is_capture",
  "is_refunded",
  "is_standalone_payment",
  "is_voided",
  "order.id",
  "owner",
  "pending",
  "source_data.pan",
  "source_data.sub_type",
  "source_data.type",
  "success",
] as const;

const TEST_ORG = "org-notify-p43";
const TEST_ORDER_ID = "9001";
const AMOUNT_MINOR = 800;
const CURRENCY = "EGP";

function hmacFieldValue(obj: PaymobCallbackObj, field: string): string {
  if (field === "order.id") {
    return String(obj.order.id);
  }
  if (field === "source_data.pan") {
    return String(obj.source_data.pan);
  }
  if (field === "source_data.sub_type") {
    return String(obj.source_data.sub_type);
  }
  if (field === "source_data.type") {
    return String(obj.source_data.type);
  }
  const raw = obj[field as keyof PaymobCallbackObj];
  if (typeof raw === "boolean") {
    return raw ? "true" : "false";
  }
  return String(raw);
}

async function signPaymobObj(
  secret: string,
  obj: PaymobCallbackObj,
): Promise<string> {
  const concatenated = PAYMOB_HMAC_FIELDS.map((field) =>
    hmacFieldValue(obj, field),
  ).join("");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(concatenated),
  );
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function postPaymobProcessedCallback(
  fixture: PaymobCallbackFixture,
  options?: {
    hmac?: string;
    connectingIp?: string;
    bodyOverride?: string;
  },
): Promise<Response> {
  const body =
    options?.bodyOverride ??
    JSON.stringify({ type: fixture.type, obj: fixture.obj });
  const hmac =
    options?.hmac ??
    (await signPaymobObj(env.PAYMOB_HMAC_SECRET, fixture.obj));
  const connectingIp = options?.connectingIp ?? "203.0.113.10";
  return billingFetch(`/notify/paymob?hmac=${encodeURIComponent(hmac)}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": connectingIp,
    },
    body,
  });
}

async function ensureCheckoutMigration(): Promise<void> {
  try {
    await applySql(checkoutMigrationSql);
  } catch {
    // Migration not present yet.
  }
}

async function seedOpenCheckout(
  checkoutId: string,
  options?: { openedWithCoverageThrough?: string | null },
): Promise<void> {
  const now = "2026-01-15T09:00:00.000Z";
  const expires = "2026-01-15T10:30:00.000Z";
  const coverageThrough = options?.openedWithCoverageThrough ?? null;
  await env.DB.prepare(
    `INSERT INTO checkout (
       checkout_id, reference, org_id, created_by_sub, billing_token_jti,
       client_request_id, offer_id, offer_version, plan_id, plan_version,
       term_unit, term_count, allowance_credits, grace_days, grace_cap_rule,
       list_price_minor, charged_price_minor, currency, terms_version,
       billing_contact_version, billing_contact_sha256, opened_with_coverage_through,
       coverage_source, provider_id, initiator, expires_at, contract_version
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      checkoutId,
      "CK-NOTIFY01",
      TEST_ORG,
      "admin-sub",
      "jti-notify",
      `client-${checkoutId}`,
      "01JHARNESSOFFERPUBLISH001",
      1,
      "plan-pro",
      1,
      "month",
      1,
      100,
      7,
      "proportional",
      AMOUNT_MINOR,
      AMOUNT_MINOR,
      CURRENCY,
      1,
      1,
      "sha256-billing-contact",
      coverageThrough,
      coverageThrough === null ? "none" : "platform",
      "paymob",
      "administrator",
      expires,
      1,
    )
    .run();
  await env.DB.prepare(
    `INSERT INTO checkout_status (checkout_id, state, last_event_at)
     VALUES (?, 'open', ?)`,
  )
    .bind(checkoutId, now)
    .run();
  await env.DB.prepare(
    `INSERT INTO paymob_intention (
       checkout_id, intention_id, order_id, client_secret, special_reference, expires_at
     ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      checkoutId,
      "intention-stub-id",
      TEST_ORDER_ID,
      "stub-client-secret",
      "CK-NOTIFY01",
      expires,
    )
    .run();
}

async function checkoutEventKinds(checkoutId: string): Promise<string[]> {
  try {
    const rows = await env.DB.prepare(
      `SELECT kind FROM checkout_event WHERE checkout_id = ? ORDER BY at`,
    )
      .bind(checkoutId)
      .all<{ kind: string }>();
    return rows.results?.map((row) => row.kind) ?? [];
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return [];
    }
    throw error;
  }
}

async function checkoutStatusState(checkoutId: string): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT state FROM checkout_status WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ state: string }>();
    return row?.state ?? null;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return null;
    }
    throw error;
  }
}

async function paymentReference(): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT reference FROM payment LIMIT 1`,
    ).first<{ reference: string }>();
    return row?.reference ?? null;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return null;
    }
    throw error;
  }
}

async function openGrantWorkCount(): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant' AND state = 'open'`,
    ).first<{ n: number }>();
    return row?.n ?? 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return 0;
    }
    throw error;
  }
}

async function notificationDispositions(): Promise<string[]> {
  try {
    const rows = await env.DB.prepare(
      `SELECT disposition FROM notification ORDER BY notification_id`,
    ).all<{ disposition: string }>();
    return rows.results?.map((row) => row.disposition) ?? [];
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return [];
    }
    throw error;
  }
}

async function alertCountByCode(code: string): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM alert WHERE code = ? AND active = 1`,
    )
      .bind(code)
      .first<{ n: number }>();
    return row?.n ?? 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return 0;
    }
    throw error;
  }
}

async function r2KeyCount(prefix: string): Promise<number> {
  const listed = await env.R2.list({ prefix });
  return listed.objects.length;
}

async function hmacInvalidBodiesWithRawPayload(): Promise<number> {
  const listed = await env.R2.list({ prefix: "hmac-invalid/" });
  let withBody = 0;
  for (const object of listed.objects) {
    const text = await r2GetText(object.key);
    if (text !== null && text.length > 0) {
      withBody += 1;
    }
  }
  return withBody;
}

async function paymentRow(
  checkoutId: string,
): Promise<{ classification: string; disposition: string } | null> {
  try {
    return await env.DB.prepare(
      `SELECT classification, disposition FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ classification: string; disposition: string }>();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return null;
    }
    throw error;
  }
}

function successFixtureWithTxnId(txnId: number): PaymobCallbackFixture {
  const base = successFixture as PaymobCallbackFixture;
  return {
    type: base.type,
    obj: { ...base.obj, id: txnId },
  };
}

async function postBadHmacFixture(): Promise<Response> {
  const fixture = badHmacFixture as PaymobCallbackFixture & {
    _fixture_hmac?: string;
  };
  const hmac =
    fixture._fixture_hmac ??
    "0000000000000000000000000000000000000000000000000000000000000000";
  return postPaymobProcessedCallback(fixture, { hmac });
}

beforeEach(async () => {
  await resetHarnessState();
  await ensureCheckoutMigration();
  await setClock("2026-01-15T09:30:00.000Z");
  await scriptPaymobInquiry("bound_success");
});

describe("P4.3 notify intake", () => {
  it("E2E-P4.3-01 replayed success callback opens a PAY payment and a grant row", async () => {
    const checkoutId = "01JNOTIFYCHECKOUT000001";
    await seedOpenCheckout(checkoutId);

    const intake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
    );
    expect(intake.status).toBe(200);

    expect(await tableCount("notification")).toBe(1);
    const reference = await paymentReference();
    expect(reference).toMatch(/^PAY-/u);
    expect(await checkoutEventKinds(checkoutId)).toContain("paid");
    expect(await checkoutStatusState(checkoutId)).toBe("paid");
    expect(await openGrantWorkCount()).toBe(1);

    const oversizeBody = "x".repeat(1_048_577);
    const oversize = await billingFetch("/notify/paymob", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "cf-connecting-ip": "203.0.113.11",
      },
      body: oversizeBody,
    });
    expect(oversize.status).toBe(413);
    expect(await oversize.text()).toBe("");
    expect(await tableCount("notification")).toBe(1);
    expect(await tableCount("work")).toBe(2);
  });

  it("E2E-P4.3-04 decline then success is one payment", async () => {
    const checkoutId = "01JNOTIFYCHECKOUT000002";
    await seedOpenCheckout(checkoutId);

    const decline = await postPaymobProcessedCallback(
      declineFixture as PaymobCallbackFixture,
    );
    expect(decline.status).toBe(200);
    expect(await checkoutEventKinds(checkoutId)).toContain("attempt_declined");
    expect(await checkoutStatusState(checkoutId)).toBe("open");

    const success = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
    );
    expect(success.status).toBe(200);
    expect(await tableCount("payment")).toBe(1);
    expect(await paymentReference()).toMatch(/^PAY-/u);
  });

  it("E2E-P4.3-02 same body is duplicate and the 61st request is 429", async () => {
    const checkoutId = "01JNOTIFYCHECKOUT000003";
    await seedOpenCheckout(checkoutId);

    const body = JSON.stringify({
      type: (successFixture as PaymobCallbackFixture).type,
      obj: (successFixture as PaymobCallbackFixture).obj,
    });
    const hmac = await signPaymobObj(
      env.PAYMOB_HMAC_SECRET,
      (successFixture as PaymobCallbackFixture).obj,
    );

    const first = await billingFetch(
      `/notify/paymob?hmac=${encodeURIComponent(hmac)}`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "cf-connecting-ip": "203.0.113.10",
        },
        body,
      },
    );
    expect(first.status).toBe(200);

    const duplicate = await billingFetch(
      `/notify/paymob?hmac=${encodeURIComponent(hmac)}`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "cf-connecting-ip": "203.0.113.10",
        },
        body,
      },
    );
    expect(duplicate.status).toBe(200);
    expect(await notificationDispositions()).toEqual(["enqueued", "duplicate"]);
    expect(await tableCount("payment")).toBe(1);

    await setClock("2026-01-15T11:00:00.000Z");
    const rateIp = "203.0.113.99";
    const notificationsBefore = await tableCount("notification");
    const workBefore = await tableCount("work");

    for (let index = 0; index < 60; index += 1) {
      const response = await postPaymobProcessedCallback(
        successFixtureWithTxnId(88000 + index),
        { connectingIp: rateIp },
      );
      expect(response.status).toBe(200);
    }

    const limited = await postPaymobProcessedCallback(
      successFixtureWithTxnId(88999),
      { connectingIp: rateIp },
    );
    expect(limited.status).toBe(429);
    expect(await limited.text()).toBe("");
    expect(await tableCount("notification")).toBe(notificationsBefore + 60);
    expect(await tableCount("work")).toBe(workBefore + 60);
  });

  it("E2E-P4.3-03 bad HMAC stores no evidence and raises AL-02", async () => {
    await setClock("2026-01-15T12:00:00.000Z");

    const first = await postBadHmacFixture();
    expect(first.status).toBe(401);
    expect(await r2KeyCount("evidence/")).toBe(0);
    expect(await r2KeyCount("hmac-invalid/")).toBe(1);

    await setClock("2026-01-15T12:05:00.000Z");
    await postBadHmacFixture();
    await setClock("2026-01-15T12:10:00.000Z");
    const third = await postBadHmacFixture();
    expect(third.status).toBe(401);
    expect(await alertCountByCode("AL-02")).toBe(1);
    expect(await r2KeyCount("hmac-invalid/")).toBe(3);

    for (let index = 3; index < 11; index += 1) {
      await setClock(
        `2026-01-15T12:${String(11 + index).padStart(2, "0")}:00.000Z`,
      );
      await postBadHmacFixture();
    }
    expect(await r2KeyCount("hmac-invalid/")).toBe(11);
    expect(await hmacInvalidBodiesWithRawPayload()).toBe(10);
    expect(await r2KeyCount("evidence/")).toBe(0);
  });

  it("E2E-P4.3-09 R2 and D1 intake failures enqueue nothing", async () => {
    const checkoutR2 = "01JNOTIFYCHECKOUT000009A";
    const checkoutD1 = "01JNOTIFYCHECKOUT000009B";
    await seedOpenCheckout(checkoutR2);
    await seedOpenCheckout(checkoutD1);

    setIntakeR2PutThrows(true);
    const r2Failure = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
    );
    expect(r2Failure.status).toBe(500);
    expect(await tableCount("notification")).toBe(0);
    expect(await tableCount("work")).toBe(0);

    setD1BatchThrows(true);
    const d1Failure = await postPaymobProcessedCallback(
      successFixtureWithTxnId(99050),
      { connectingIp: "203.0.113.12" },
    );
    expect(d1Failure.status).toBe(500);
    expect(await tableCount("notification")).toBe(0);
    expect(await tableCount("work")).toBe(0);
  });

  it("E2E-P4.3-05 unbound order and amount mismatch withhold the grant", async () => {
    const unboundCheckout = "01JNOTIFYCHECKOUT000005A";
    await seedOpenCheckout(unboundCheckout);
    await scriptPaymobInquiry("unbound");
    const unboundIntake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
    );
    expect(unboundIntake.status).toBe(200);
    expect(await tableCount("payment")).toBe(0);
    expect(await alertCountByCode("AL-05")).toBe(1);

    const mismatchCheckout = "01JNOTIFYCHECKOUT000005B";
    await seedOpenCheckout(mismatchCheckout);
    await scriptPaymobInquiry("amount_mismatch");
    const mismatchIntake = await postPaymobProcessedCallback(
      successFixtureWithTxnId(99005),
      { connectingIp: "203.0.113.13" },
    );
    expect(mismatchIntake.status).toBe(200);
    const mismatchPayment = await paymentRow(mismatchCheckout);
    expect(mismatchPayment?.disposition).toBe("withheld_mismatch");
    expect(await openGrantWorkCount()).toBe(0);
    expect(await alertCountByCode("AL-05")).toBe(2);
  });

  it("E2E-P4.3-06 first inquiry already refunded grants nothing", async () => {
    await scriptPaymobInquiry("reversed");

    const parentCheckout = "01JNOTIFYCHECKOUT000006A";
    await seedOpenCheckout(parentCheckout);
    const parentIntake = await postPaymobProcessedCallback(
      refundParentFixture as PaymobCallbackFixture,
    );
    expect(parentIntake.status).toBe(200);
    const parentPayment = await paymentRow(parentCheckout);
    expect(parentPayment?.disposition).toBe("reversed_before_grant");
    expect(await openGrantWorkCount()).toBe(0);

    const childCheckout = "01JNOTIFYCHECKOUT000006B";
    await seedOpenCheckout(childCheckout);
    const childIntake = await postPaymobProcessedCallback(
      refundChildFixture as PaymobCallbackFixture,
      { connectingIp: "203.0.113.14" },
    );
    expect(childIntake.status).toBe(200);
    const childPayment = await paymentRow(childCheckout);
    expect(childPayment?.disposition).toBe("reversed_before_grant");
    expect(await openGrantWorkCount()).toBe(0);
  });

  it("E2E-P4.3-07 second payment at the same coverage through is likely_duplicate", async () => {
    const coverageThrough = "2026-06-30";
    const firstCheckout = "01JNOTIFYCHECKOUT000007A";
    const secondCheckout = "01JNOTIFYCHECKOUT000007B";
    await seedOpenCheckout(firstCheckout, {
      openedWithCoverageThrough: coverageThrough,
    });
    await seedOpenCheckout(secondCheckout, {
      openedWithCoverageThrough: coverageThrough,
    });

    await scriptPaymobInquiry("bound_success");
    const firstIntake = await postPaymobProcessedCallback(
      successFixture as PaymobCallbackFixture,
    );
    expect(firstIntake.status).toBe(200);
    expect(await tableCount("payment")).toBe(1);

    const secondIntake = await postPaymobProcessedCallback(
      successFixtureWithTxnId(99007),
      { connectingIp: "203.0.113.15" },
    );
    expect(secondIntake.status).toBe(200);
    const secondPayment = await paymentRow(secondCheckout);
    expect(secondPayment?.classification).toBe("likely_duplicate");
    expect(secondPayment?.disposition).toBe("grant");
    expect(await alertCountByCode("AL-09")).toBe(1);
    expect(await openGrantWorkCount()).toBe(2);
  });
});
