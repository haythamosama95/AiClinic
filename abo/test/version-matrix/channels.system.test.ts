/**
 * P7.3 — contract version matrix ABO channels (E2E-P7.3-01).
 */

import { env } from "cloudflare:test";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { beforeEach, describe, expect, it } from "vitest";
import successFixture from "../fixtures/paymob/success.json";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import notifyWorkMigrationSql from "../../migrations/0003_notify_work.sql?raw";
import {
  applySql,
  billingFetch,
  mintBilling,
  newIssuer,
  opsFetch,
  pinIssuer,
  resetHarnessState,
  setupHarness,
  tableCount,
} from "../system/harness";

const RECEIVER_CURRENT = CHANNEL_VERSIONS.aboClinic;
const ACCEPTED_VERSIONS = [RECEIVER_CURRENT - 1, RECEIVER_CURRENT];
const PAYMOB_ADAPTER_VERSION = CHANNEL_VERSIONS.paymobAdapter;
const PAYMOB_RETURN_VERSION = CHANNEL_VERSIONS.paymobReturn;
const HARNESS_OFFER_ID = "01JHARNESSOFFERPUBLISH001";
const HARNESS_OFFER_VERSION = 2;
const HARNESS_TERMS_VERSION = 1;
const HARNESS_PLAN_ID = "plan-pro";
const HARNESS_PLAN_VERSION = 1;
const HARNESS_ALLOWANCE_CREDITS = 100;

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
  source_data: { pan: string; sub_type: string; type: string };
  success: boolean;
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
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function ensureCheckoutSchema(): Promise<void> {
  await applySql(checkoutMigrationSql);
  await applySql(notifyWorkMigrationSql);
}

async function seedHarnessOffer(): Promise<void> {
  await env.DB.prepare(
    `INSERT OR IGNORE INTO terms_version (
       terms_version, locale, text_r2_key, text_sha256, published_by, contract_version
     ) VALUES (?, 'en', 'terms/en/1.txt',
       'dbb6d8870e5636c8da062789e912326c66eacd68838980a81bf6ad9484677753',
       'fixture', 1)`,
  )
    .bind(HARNESS_TERMS_VERSION)
    .run();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO offer (offer_id, code, contract_version)
     VALUES (?, 'harness-pro-monthly', 1)`,
  )
    .bind(HARNESS_OFFER_ID)
    .run();
  await env.DB.prepare(
    `INSERT OR REPLACE INTO offer_version (
       offer_id, version, plan_id, plan_version, term_unit, term_count,
       price_minor, currency, allowance_credits, grace_days, grace_cap_rule,
       copy, terms_version, published_by, assertion_sha256, contract_version
     ) VALUES (?, ?, ?, ?, 'month', 1, 1000, 'EGP', ?, 7, 'proportional',
       '{"en":{"name":"Clinic Pro Monthly","summary":"Monthly clinic subscription"}}',
       ?, 'fixture', 'fixture-assertion-v2', 1)`,
  )
    .bind(
      HARNESS_OFFER_ID,
      HARNESS_OFFER_VERSION,
      HARNESS_PLAN_ID,
      HARNESS_PLAN_VERSION,
      HARNESS_ALLOWANCE_CREDITS,
      HARNESS_TERMS_VERSION,
    )
    .run();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO offer_event (
       offer_id, kind, version, actor, at, contract_version
     ) VALUES (?, 'published', ?, 'fixture', '2026-02-01T00:00:00.000Z', 1)`,
  )
    .bind(HARNESS_OFFER_ID, HARNESS_OFFER_VERSION)
    .run();
}

async function alertCountByCode(code: string): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM alert WHERE code = ?`,
    )
      .bind(code)
      .first<{ n: number }>();
    return row?.n ?? 0;
  } catch {
    return 0;
  }
}

async function latestNotificationAdapterVersion(): Promise<number | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT adapter_version FROM notification ORDER BY notification_id DESC LIMIT 1`,
    ).first<{ adapter_version: number }>();
    return row?.adapter_version ?? null;
  } catch {
    return null;
  }
}

function baseClaims(now = Math.floor(Date.now() / 1000)) {
  return {
    sub: "user-version-matrix",
    org: "org-version-matrix",
    branch: "branch-version-matrix",
    iat: now,
    exp: now + 300,
    jti: crypto.randomUUID(),
  };
}

async function expectClinicVersionRefusal(
  path: string,
  version: string | undefined,
): Promise<void> {
  const headers: Record<string, string> = {
    authorization: "Bearer invalid-token",
  };
  if (version !== undefined) {
    headers["Abo-Contract-Version"] = version;
  }
  const before = await tableCount("token_use");
  const response = await billingFetch(path, { headers });
  expect(response.status).toBe(400);
  const body = (await response.json()) as Record<string, unknown>;
  expect(body.code).toBe("contract_version_unsupported");
  expect(body.accepted_versions).toEqual(ACCEPTED_VERSIONS);
  expect(body.contract_version).toBe(RECEIVER_CURRENT);
  expect(response.headers.get("Abo-Contract-Version")).toBe(
    String(RECEIVER_CURRENT),
  );
  expect(await tableCount("token_use")).toBe(before);
}

async function expectConsoleVersionRefusal(
  path: string,
  version: string | undefined,
): Promise<void> {
  const headers: Record<string, string> = {};
  if (version !== undefined) {
    headers["Abo-Contract-Version"] = version;
  }
  const before = await tableCount("operator_action");
  const response = await opsFetch(path, { headers });
  expect(response.status).toBe(400);
  const body = (await response.json()) as Record<string, unknown>;
  expect(body.code).toBe("contract_version_unsupported");
  expect(body.reload).toBe(true);
  expect(body.accepted_versions).toEqual(ACCEPTED_VERSIONS);
  expect(await tableCount("operator_action")).toBe(before);
}

beforeEach(async () => {
  await resetHarnessState();
  await setupHarness();
  await ensureCheckoutSchema();
  await seedHarnessOffer();
});

describe("E2E-P7.3-01", () => {
  it("E2E-P7.3-01", async () => {
    for (const version of [undefined, "0", "3"] as const) {
      await expectClinicVersionRefusal("/v1/offers", version);
      await expectConsoleVersionRefusal("/ops/lookup", version);
    }

    const acceptedV2 = await billingFetch("/v1/offers", {
      headers: {
        authorization: "Bearer invalid-token",
        "Abo-Contract-Version": String(RECEIVER_CURRENT),
      },
    });
    expect(acceptedV2.status).toBe(401);
    expect(acceptedV2.headers.get("Abo-Contract-Version")).toBe(
      String(RECEIVER_CURRENT),
    );
    const v2Body = (await acceptedV2.json()) as Record<string, unknown>;
    expect(v2Body.contract_version).toBe(RECEIVER_CURRENT);

    const acceptedV1 = await billingFetch("/v1/offers", {
      headers: {
        authorization: "Bearer invalid-token",
        "Abo-Contract-Version": String(RECEIVER_CURRENT - 1),
      },
    });
    expect(acceptedV1.status).toBe(401);
    expect(acceptedV1.headers.get("Abo-Contract-Version")).toBe(
      String(RECEIVER_CURRENT - 1),
    );
    const v1Body = (await acceptedV1.json()) as Record<string, unknown>;
    expect(v1Body.contract_version).toBe(RECEIVER_CURRENT - 1);

    const returnResponse = await billingFetch(
      `/return/paymob?v=${RECEIVER_CURRENT + 99}`,
    );
    expect(returnResponse.status).toBe(200);
    const html = (await returnResponse.text()).toLowerCase();
    expect(html).not.toContain("contract_version_unsupported");

    const issuer = await newIssuer();
    await pinIssuer(issuer.kid, issuer.publicKey);
    const billingToken = await mintBilling(issuer, {
      ...baseClaims(),
      role: "administrator",
    });
    const checkout = await billingFetch("/v1/checkouts", {
      method: "POST",
      headers: {
        authorization: `Bearer ${billingToken}`,
        "content-type": "application/json",
        "Abo-Contract-Version": String(RECEIVER_CURRENT),
      },
      body: JSON.stringify({
        client_request_id: crypto.randomUUID(),
        offer_id: HARNESS_OFFER_ID,
        offer_version: HARNESS_OFFER_VERSION,
        terms_version: HARNESS_TERMS_VERSION,
      }),
    });
    expect(checkout.status).toBe(201);
    expect(checkout.headers.get("Abo-Contract-Version")).toBe(
      String(RECEIVER_CURRENT),
    );
    const checkoutBody = (await checkout.json()) as Record<string, unknown>;
    const returnUrl = String(checkoutBody.return_url ?? "");
    expect(returnUrl).toContain(`v=${PAYMOB_RETURN_VERSION}`);

    const badVerJwt = await mintBilling(issuer, {
      ...baseClaims(),
      role: "administrator",
      jti: crypto.randomUUID(),
      ver: "1",
    });
    const unauthenticated = await billingFetch("/v1/offers", {
      headers: {
        authorization: `Bearer ${badVerJwt}`,
        "Abo-Contract-Version": String(RECEIVER_CURRENT),
      },
    });
    expect(unauthenticated.status).toBe(401);
    const unauthBody = (await unauthenticated.json()) as Record<string, unknown>;
    expect(unauthBody.code).toBe("unauthenticated");

    const fixture = successFixture as { type: string; obj: PaymobCallbackObj };
    const unparseableBody = JSON.stringify({ type: fixture.type });
    const hmac = await signPaymobObj(env.PAYMOB_HMAC_SECRET, fixture.obj);
    const notificationsBefore = await tableCount("notification");
    const alertsBefore = await alertCountByCode("AL-23");
    const notifyResponse = await billingFetch(
      `/notify/paymob?hmac=${encodeURIComponent(hmac)}`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "cf-connecting-ip": "203.0.113.77",
        },
        body: unparseableBody,
      },
    );
    expect(notifyResponse.status).toBe(200);
    expect(await tableCount("notification")).toBeGreaterThan(notificationsBefore);
    expect(await alertCountByCode("AL-23")).toBeGreaterThan(alertsBefore);
    expect(await latestNotificationAdapterVersion()).toBe(PAYMOB_ADAPTER_VERSION);
  });
});
