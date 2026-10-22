/**
 * RM36 (R7-A2) — payment history names come from each payment's immutable offer version (H-XW).
 */

import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { applySql, billingFetch, harnessClockNowSeconds, mintBilling, newIssuer, pinIssuer } from "./harness";
import { resetCrossWorkerHarness, setupCrossWorkerHarness } from "./cross-worker-harness";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";

async function ensureCheckoutMigration(): Promise<void> {
  try {
    await applySql(checkoutMigrationSql);
  } catch {
    // Migration already applied by the harness.
  }
}

async function administratorHeaders(org: string): Promise<Record<string, string>> {
  const issuer = await newIssuer();
  await pinIssuer(issuer.kid, issuer.publicKey);
  const now = await harnessClockNowSeconds();
  const token = await mintBilling(issuer, {
    sub: "admin-sub",
    org,
    role: "administrator",
    branch: "branch-test",
    iat: now,
    exp: now + 300,
    jti: crypto.randomUUID(),
  });
  return {
    authorization: `Bearer ${token}`,
    "Abo-Contract-Version": "1",
    "content-type": "application/json",
  };
}

function offerCopy(name: string): string {
  return JSON.stringify({ en: { name, summary: `${name} summary` } });
}

async function insertOfferVersion(offerId: string, version: number, name: string): Promise<void> {
  await insertOfferVersionCopy(offerId, version, offerCopy(name));
}

async function insertOfferVersionCopy(offerId: string, version: number, copy: string): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO offer_version (
       offer_id, version, plan_id, plan_version, term_unit, term_count, price_minor,
       currency, allowance_credits, grace_days, grace_cap_rule, copy, terms_version,
       published_by, assertion_sha256, contract_version
     ) VALUES (?, ?, 'plan-r7a2', 1, 'month', 1, 1000, 'EGP', 100, 7, 'proportional', ?, 1,
       'fixture', ?, 1)`,
  )
    .bind(offerId, version, copy, `assertion-r7a2-${offerId}-${version}`)
    .run();
}

async function insertPaidPayment(
  orgId: string,
  offerId: string,
  offerVersion: number,
  reference: string,
  paidAt = "2026-04-02T10:00:00.000Z",
): Promise<void> {
  const checkoutId = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO checkout (
       checkout_id, reference, org_id, created_by_sub, billing_token_jti, client_request_id,
       offer_id, offer_version, plan_id, plan_version, term_unit, term_count, allowance_credits,
       grace_days, grace_cap_rule, list_price_minor, charged_price_minor, currency,
       terms_version, billing_contact_version, billing_contact_sha256, coverage_source,
       provider_id, initiator, expires_at, contract_version
     ) VALUES (?, ?, ?, 'admin-sub', ?, ?, ?, ?, 'plan-r7a2', 1, 'month', 1, 100, 7,
       'proportional', 1000, 1000, 'EGP', 1, 1, 'sha-r7a2', 'none', 'paymob', 'administrator',
       '2026-04-03T10:00:00.000Z', 1)`,
  )
    .bind(
      checkoutId,
      `CK-${reference}`,
      orgId,
      crypto.randomUUID(),
      `req-${reference}`,
      offerId,
      offerVersion,
    )
    .run();
  await env.DB.prepare(
    `INSERT INTO payment (
       payment_id, reference, org_id, checkout_id, provider_id, amount_minor, currency,
       paid_at, confirmed_at, confirmation_inquiry_id, offer_id, offer_version,
       billing_contact_version, classification, disposition, mismatch_detail, evidence_sha256
     ) VALUES (?, ?, ?, ?, 'paymob', 1000, 'EGP', ?, ?, ?, ?, ?, 1, 'normal', 'grant', NULL, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      reference,
      orgId,
      checkoutId,
      paidAt,
      paidAt,
      `inquiry-${reference}`,
      offerId,
      offerVersion,
      `evidence-${reference}`,
    )
    .run();
}

async function getPayments(orgId: string, cursor?: string): Promise<{
  status: number;
  body: {
    payments?: Array<{ reference: string; plan_display_name: string | null; offer_version: number }>;
    next_cursor?: string;
    has_more?: boolean;
  };
}> {
  const path = cursor === undefined ? "/v1/payments" : `/v1/payments?cursor=${cursor}`;
  const response = await billingFetch(path, {
    headers: await administratorHeaders(orgId),
  });
  return { status: response.status, body: (await response.json()) as never };
}

beforeAll(async () => {
  await setupCrossWorkerHarness();
  await ensureCheckoutMigration();
});

beforeEach(async () => {
  await resetCrossWorkerHarness();
});

describe("R7-A2 payment history names", () => {
  it("R7-A2-01: a version-1 payment keeps its version-1 name after version 2 is published", async () => {
    const orgId = crypto.randomUUID();
    const offerId = `offer-r7a2-01-${orgId}`;
    await insertOfferVersion(offerId, 1, "Gold One");
    await insertOfferVersion(offerId, 2, "Gold Two");
    await env.DB.prepare(
      `INSERT INTO offer_event (offer_id, kind, version, actor, at, contract_version)
       VALUES (?, 'published', 2, 'fixture', '2026-04-04T10:00:00.000Z', 1)`,
    )
      .bind(offerId)
      .run();
    await insertPaidPayment(orgId, offerId, 1, "PAY-R7A2-01");

    const result = await getPayments(orgId);
    expect(result.status).toBe(200);
    const payment = result.body.payments?.find((row) => row.reference === "PAY-R7A2-01");
    expect(payment?.plan_display_name).toBe("Gold One");
    expect(payment?.offer_version).toBe(1);
  });

  it("R7-A2-02: a retired offer keeps its version-1 name in payment history", async () => {
    const orgId = crypto.randomUUID();
    const offerId = `offer-r7a2-02-${orgId}`;
    await insertOfferVersion(offerId, 1, "Silver One");
    await insertPaidPayment(orgId, offerId, 1, "PAY-R7A2-02");
    await env.DB.prepare(
      `INSERT INTO offer_event (offer_id, kind, version, actor, at, contract_version)
       VALUES (?, 'retired', 1, 'fixture', '2026-04-05T10:00:00.000Z', 1)`,
    )
      .bind(offerId)
      .run();

    const result = await getPayments(orgId);
    expect(result.status).toBe(200);
    const payment = result.body.payments?.find((row) => row.reference === "PAY-R7A2-02");
    expect(payment?.plan_display_name).toBe("Silver One");
  });

  it("R7-A2-03: a payment whose offer version is missing is diagnosed, not given an invented name", async () => {
    const orgId = crypto.randomUUID();
    const offerId = `offer-r7a2-03-${orgId}`;
    await insertPaidPayment(orgId, offerId, 9, "PAY-R7A2-03");

    const result = await getPayments(orgId);
    expect(result.status).toBe(200);
    const payment = result.body.payments?.find((row) => row.reference === "PAY-R7A2-03");
    expect(payment?.plan_display_name).toBeNull();

    const alert = await env.DB.prepare(
      `SELECT code FROM alert WHERE alert_key = ?`,
    )
      .bind(`offer_malformed:${offerId}:9`)
      .first<{ code: string }>();
    expect(alert?.code).toBe("offer_malformed");
  });

  it("R7-A2-04: a malformed copy yields a null name and the offer_malformed alert", async () => {
    const orgId = crypto.randomUUID();
    const offerId = `offer-r7a2-04-${orgId}`;
    await insertOfferVersionCopy(offerId, 1, JSON.stringify({ en: { summary: "no name" } }));
    await insertPaidPayment(orgId, offerId, 1, "PAY-R7A2-04");

    const result = await getPayments(orgId);
    expect(result.status).toBe(200);
    const payment = result.body.payments?.find((row) => row.reference === "PAY-R7A2-04");
    expect(payment?.plan_display_name).toBeNull();

    const alert = await env.DB.prepare(
      `SELECT code FROM alert WHERE alert_key = ?`,
    )
      .bind(`offer_malformed:${offerId}:1`)
      .first<{ code: string }>();
    expect(alert?.code).toBe("offer_malformed");
  });

  it("R7-A2-05: a null-name row does not break paging (next_cursor and has_more intact) and the following payment keeps its name", async () => {
    const orgId = crypto.randomUUID();
    const goodOffer = `offer-r7a2-05-good-${orgId}`;
    const badOffer = `offer-r7a2-05-bad-${orgId}`;
    await insertOfferVersion(goodOffer, 1, "Gold One");
    await insertOfferVersionCopy(badOffer, 1, JSON.stringify({ en: { summary: "no name" } }));
    for (let index = 1; index <= 21; index += 1) {
      const reference = `PAY-R7A2-05-${String(index).padStart(2, "0")}`;
      const paidAt = `2026-04-02T10:${String(index).padStart(2, "0")}:00.000Z`;
      await insertPaidPayment(orgId, index === 5 ? badOffer : goodOffer, 1, reference, paidAt);
    }

    const firstPage = await getPayments(orgId);
    expect(firstPage.status).toBe(200);
    expect(firstPage.body.payments?.length).toBe(20);
    expect(firstPage.body.payments?.[4]?.plan_display_name).toBeNull();
    expect(firstPage.body.payments?.[5]?.plan_display_name).toBe("Gold One");
    expect(firstPage.body.has_more).toBe(true);
    expect(firstPage.body.next_cursor).toBe("PAY-R7A2-05-20");

    const secondPage = await getPayments(orgId, "PAY-R7A2-05-20");
    expect(secondPage.status).toBe(200);
    expect(secondPage.body.payments?.map((row) => row.reference)).toEqual(["PAY-R7A2-05-21"]);
    expect(secondPage.body.payments?.[0]?.plan_display_name).toBe("Gold One");
    expect(secondPage.body.has_more).toBe(false);
    expect(secondPage.body.next_cursor).toBe("PAY-R7A2-05-21");
  });

  it("R7-A2-06: history loads with terms R2 unavailable", async () => {
    const orgId = crypto.randomUUID();
    const offerId = `offer-r7a2-06-${orgId}`;
    await insertOfferVersion(offerId, 1, "Platinum One");
    await insertPaidPayment(orgId, offerId, 1, "PAY-R7A2-06");

    const originalGet = env.R2.get.bind(env.R2);
    const r2 = env.R2 as unknown as { get: unknown };
    r2.get = async () => {
      throw new Error("terms R2 unavailable injected by test");
    };
    try {
      const result = await getPayments(orgId);
      expect(result.status).toBe(200);
      const payment = result.body.payments?.find((row) => row.reference === "PAY-R7A2-06");
      expect(payment?.plan_display_name).toBe("Platinum One");
    } finally {
      r2.get = originalGet;
    }
  });
});
