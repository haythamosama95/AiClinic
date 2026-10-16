/**
 * P4.2 — checkout coverage fallback when PLATFORM throws (H-XW throw config).
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import offersFixture from "../../fixtures/offers.json";
import { loadOffersFixture } from "../../src/records/append";
import {
  applySql,
  billingFetch,
  mintBilling,
  newIssuer,
  pinIssuer,
  resetHarnessState,
  setupHarness,
} from "./harness";
import {
  ensurePaymobFetchMock,
  scriptPaymobStub,
} from "./cross-worker-harness";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";

type OffersFixtureExpectations = {
  offer_id: string;
  version: number;
  terms: { version: number; text: string };
};

const VIEW_COVERAGE_THROUGH = "2026-05-01T00:00:00.000Z";

const COVERAGE_VIEW_SNAPSHOT = {
  contract_version: 1,
  state: "active",
  suspended: false,
  term: {
    ref: "term-view-fixture",
    plan_display_name: "View Fixture",
    starts_at: "2026-04-01T00:00:00.000Z",
    ends_at: VIEW_COVERAGE_THROUGH,
    grace_ends_at: "2026-05-08T00:00:00.000Z",
    allowance: 10_000,
    used: 0,
    band: "ok",
  },
  queued_count: 0,
  held_count: 0,
  coverage_through: VIEW_COVERAGE_THROUGH,
  binding_epoch: 1,
  clinic_seq: 1,
};

async function ensureCheckoutMigration(): Promise<void> {
  try {
    await applySql(checkoutMigrationSql);
  } catch {
    // Migration not present yet.
  }
}

async function seedOffersCatalogueFixture(): Promise<OffersFixtureExpectations | null> {
  try {
    const fixture = offersFixture as {
      expectations?: OffersFixtureExpectations;
    };
    await loadOffersFixture(fixture);
    return fixture.expectations ?? null;
  } catch {
    return null;
  }
}

async function administratorHeaders(
  org: string,
): Promise<Record<string, string>> {
  const issuer = await newIssuer();
  await pinIssuer(issuer.kid, issuer.publicKey);
  const now = Math.floor(Date.now() / 1000);
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

async function putBillingContact(org: string): Promise<void> {
  const headers = await administratorHeaders(org);
  const response = await billingFetch("/v1/billing-contact", {
    method: "PUT",
    headers,
    body: JSON.stringify({
      client_request_id: `req-contact-${org}`,
      name: "Clinic Admin",
      email: "admin@clinic.test",
      phone: "+201001234567",
    }),
  });
  expect(response.status).toBe(200);
}

async function insertCoverageView(orgId: string): Promise<void> {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO coverage_view (org_id, binding_epoch, clinic_seq, snapshot)
     VALUES (?, ?, ?, ?)`,
  )
    .bind(orgId, 1, 1, JSON.stringify(COVERAGE_VIEW_SNAPSHOT))
    .run();
}

async function checkoutCoverageSource(
  checkoutId: string,
): Promise<string | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT coverage_source FROM checkout WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ coverage_source: string }>();
    return row?.coverage_source ?? null;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return null;
    }
    throw error;
  }
}

beforeEach(async () => {
  await resetHarnessState();
  await setupHarness();
  await ensureCheckoutMigration();
  await ensurePaymobFetchMock();
  await scriptPaymobStub("ok");
});

describe("checkout throw fallback", () => {
  it("E2E-P4.2-03 throw and transient use coverage_view", async () => {
    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();

    const orgThrow = "org-throw-fallback";
    await putBillingContact(orgThrow);
    await insertCoverageView(orgThrow);

    const throwHeaders = await administratorHeaders(orgThrow);
    const throwResponse = await billingFetch("/v1/checkouts", {
      method: "POST",
      headers: throwHeaders,
      body: JSON.stringify({
        client_request_id: "req-checkout-03-throw",
        offer_id: expectations!.offer_id,
        offer_version: expectations!.version,
        terms_version: expectations!.terms.version,
      }),
    });
    expect(throwResponse.status).toBe(201);
    const throwBody = (await throwResponse.json()) as Record<string, unknown>;
    const throwCheckoutId = String(throwBody.checkout_id);
    expect(await checkoutCoverageSource(throwCheckoutId)).toBe("view");

    const orgTransient = "org-transient-aa";
    await putBillingContact(orgTransient);
    await insertCoverageView(orgTransient);

    const transientHeaders = await administratorHeaders(orgTransient);
    const transientResponse = await billingFetch("/v1/checkouts", {
      method: "POST",
      headers: transientHeaders,
      body: JSON.stringify({
        client_request_id: "req-checkout-03-transient",
        offer_id: expectations!.offer_id,
        offer_version: expectations!.version,
        terms_version: expectations!.terms.version,
      }),
    });
    expect(transientResponse.status).toBe(201);
    const transientBody = (await transientResponse.json()) as Record<
      string,
      unknown
    >;
    const transientCheckoutId = String(transientBody.checkout_id);
    expect(await checkoutCoverageSource(transientCheckoutId)).toBe("view");
  });
});
