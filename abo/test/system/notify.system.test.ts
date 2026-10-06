/**
 * P4.3 — Paymob notify intake and confirm E2E tests (H-ABO + H-PAY).
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import declineFixture from "../fixtures/paymob/decline.json";
import successFixture from "../fixtures/paymob/success.json";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import {
  applySql,
  billingFetch,
  resetHarnessState,
  scriptPaymobInquiry,
  setClock,
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
  options?: { hmac?: string },
): Promise<Response> {
  const body = JSON.stringify({ type: fixture.type, obj: fixture.obj });
  const hmac =
    options?.hmac ??
    (await signPaymobObj(env.PAYMOB_HMAC_SECRET, fixture.obj));
  return billingFetch(`/notify/paymob?hmac=${encodeURIComponent(hmac)}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": "203.0.113.10",
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

async function seedOpenCheckout(checkoutId: string): Promise<void> {
  const now = "2026-01-15T09:00:00.000Z";
  const expires = "2026-01-15T10:30:00.000Z";
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
      null,
      "none",
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
});
