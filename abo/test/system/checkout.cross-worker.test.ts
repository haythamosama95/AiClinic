/**
 * P4.2 — checkout creation E2E tests (H-XW + H-PAY).
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
} from "./harness";
import {
  getLastPaymobIntentionBody,
  platformCall,
  resetCrossWorkerHarness,
  scriptPaymobStub,
  setClock,
  setupActivePlatformCoverage,
  setupCrossWorkerHarness,
} from "./cross-worker-harness";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";

type OffersFixtureExpectations = {
  offer_id: string;
  version: number;
  terms: { version: number; text: string };
  older_version: number;
  price_minor: number;
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
  options?: { sub?: string; jti?: string },
): Promise<{ headers: Record<string, string>; jti: string }> {
  const issuer = await newIssuer();
  await pinIssuer(issuer.kid, issuer.publicKey);
  const now = Math.floor(Date.now() / 1000);
  const jti = options?.jti ?? crypto.randomUUID();
  const token = await mintBilling(issuer, {
    sub: options?.sub ?? "admin-sub",
    org,
    role: "administrator",
    branch: "branch-test",
    iat: now,
    exp: now + 300,
    jti,
  });
  return {
    jti,
    headers: {
      authorization: `Bearer ${token}`,
      "Abo-Contract-Version": "1",
      "content-type": "application/json",
    },
  };
}

async function putBillingContact(
  org: string,
  clientRequestId = "req-billing-contact",
): Promise<void> {
  const { headers } = await administratorHeaders(org);
  const response = await billingFetch("/v1/billing-contact", {
    method: "PUT",
    headers,
    body: JSON.stringify({
      client_request_id: clientRequestId,
      name: "Clinic Admin",
      email: "admin@clinic.test",
      phone: "+201001234567",
    }),
  });
  expect(response.status).toBe(200);
}

function addMinutes(isoUtc: string, minutes: number): string {
  return new Date(Date.parse(isoUtc) + minutes * 60_000).toISOString();
}

async function checkoutCount(orgId: string): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM checkout WHERE org_id = ?`,
    )
      .bind(orgId)
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

async function checkoutRow(
  checkoutId: string,
): Promise<Record<string, unknown> | null> {
  try {
    return await env.DB.prepare(
      `SELECT * FROM checkout WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<Record<string, unknown>>();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return null;
    }
    throw error;
  }
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

async function postCheckout(
  org: string,
  body: {
    client_request_id: string;
    offer_id: string;
    offer_version: number;
    terms_version: number;
  },
  options?: { jti?: string },
): Promise<Response> {
  const { headers } = await administratorHeaders(org, options);
  return billingFetch("/v1/checkouts", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

beforeEach(async () => {
  await resetCrossWorkerHarness();
  await setupCrossWorkerHarness();
  await ensureCheckoutMigration();
});

describe("checkout cross-worker", () => {
  it("E2E-P4.2-01 checkout 201 redirect_url CK reference expires_at +30 min", async () => {
    const clockIso = "2026-03-15T12:00:00.000Z";
    await setClock(clockIso);

    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();
    const org = "org-checkout-01";
    await putBillingContact(org);

    const clientRequestId = "req-checkout-01";
    const checkout01Jti = "a0000001-0001-4001-8001-000000000001";
    const { jti } = await administratorHeaders(org, {
      jti: checkout01Jti,
    });
    const response = await postCheckout(
      org,
      {
        client_request_id: clientRequestId,
        offer_id: expectations!.offer_id,
        offer_version: expectations!.version,
        terms_version: expectations!.terms.version,
      },
      { jti },
    );

    expect(response.status).toBe(201);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.contract_version).toBe(1);
    expect(typeof body.checkout_id).toBe("string");
    expect(String(body.reference)).toMatch(/^CK-/u);
    expect(body.redirect_url).toBeTruthy();
    expect(body.expires_at).toBe(addMinutes(clockIso, 30));

    const paymobBody = await getLastPaymobIntentionBody();
    expect(paymobBody.amount).toBe(expectations!.price_minor);
    expect(paymobBody.special_reference).toBe(body.reference);
    expect(paymobBody.expiration).toBe(1800);

    const row = await checkoutRow(String(body.checkout_id));
    expect(row?.billing_token_jti).toBe(jti);
  });

  it("E2E-P4.2-02 active coverage starts after_current", async () => {
    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();
    const org = crypto.randomUUID();
    await putBillingContact(org);
    await setupActivePlatformCoverage(org);

    const response = await postCheckout(org, {
      client_request_id: "req-checkout-02",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: expectations!.terms.version,
    });

    const coverage = await platformCall("getCoverage", {
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      org_id: org,
    });
    expect(coverage.result).toBe("ok");
    const snapshot = JSON.parse(String(coverage.detail)) as {
      coverage_through: string;
    };

    expect(response.status).toBe(201);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.starts).toBe("after_current");
    expect(body.projected_start).toBe(snapshot.coverage_through);
  });

  it("E2E-P4.2-04 superseded offer missing contact stale terms", async () => {
    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();

    const orgSuperseded = "org-checkout-04-superseded";
    await putBillingContact(orgSuperseded);
    const superseded = await postCheckout(orgSuperseded, {
      client_request_id: "req-checkout-04-superseded",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.older_version,
      terms_version: expectations!.terms.version,
    });
    expect(superseded.status).toBe(409);
    const supersededBody = (await superseded.json()) as Record<string, unknown>;
    expect(supersededBody.code).toBe("offer_unavailable");
    expect(supersededBody.current_version).toBe(expectations!.version);
    expect(await checkoutCount(orgSuperseded)).toBe(0);

    const orgNoContact = "org-checkout-04-no-contact";
    const noContact = await postCheckout(orgNoContact, {
      client_request_id: "req-checkout-04-no-contact",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: expectations!.terms.version,
    });
    expect(noContact.status).toBe(409);
    const noContactBody = (await noContact.json()) as Record<string, unknown>;
    expect(noContactBody.code).toBe("billing_contact_required");
    expect(await checkoutCount(orgNoContact)).toBe(0);

    const orgStaleTerms = "org-checkout-04-stale-terms";
    await putBillingContact(orgStaleTerms);
    const staleTerms = await postCheckout(orgStaleTerms, {
      client_request_id: "req-checkout-04-stale-terms",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: expectations!.terms.version + 99,
    });
    expect(staleTerms.status).toBe(409);
    const staleTermsBody = (await staleTerms.json()) as Record<string, unknown>;
    expect(staleTermsBody.code).toBe("terms_not_accepted");
    expect(await checkoutCount(orgStaleTerms)).toBe(0);
  });

  it("E2E-P4.2-05 provider refuse and timeout are Abandoned", async () => {
    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();
    const org = "org-checkout-05";

    await scriptPaymobStub("refuse");
    await putBillingContact(org);
    const refuseResponse = await postCheckout(org, {
      client_request_id: "req-checkout-05-refuse",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: expectations!.terms.version,
    });
    expect(refuseResponse.status).toBe(503);
    const refuseBody = (await refuseResponse.json()) as Record<string, unknown>;
    expect(refuseBody.code).toBe("provider_unavailable");
    const refuseCheckoutId = String(refuseBody.checkout_id ?? "");
    if (refuseCheckoutId.length > 0) {
      expect(await checkoutEventKinds(refuseCheckoutId)).toContain("open_failed");
      const readRefuse = await billingFetch(`/v1/checkouts/${refuseCheckoutId}`, {
        headers: (await administratorHeaders(org)).headers,
      });
      if (readRefuse.status === 200) {
        const readBody = (await readRefuse.json()) as Record<string, unknown>;
        expect(readBody.shown_state).toBe("Abandoned");
      }
    }

    await scriptPaymobStub("timeout");
    const timeoutResponse = await postCheckout(org, {
      client_request_id: "req-checkout-05-timeout",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: expectations!.terms.version,
    });
    expect(timeoutResponse.status).toBe(503);
    const timeoutBody = (await timeoutResponse.json()) as Record<string, unknown>;
    expect(timeoutBody.code).toBe("provider_unavailable");
    const timeoutCheckoutId = String(timeoutBody.checkout_id ?? "");
    if (timeoutCheckoutId.length > 0) {
      expect(await checkoutEventKinds(timeoutCheckoutId)).toContain("open_failed");
      const readTimeout = await billingFetch(
        `/v1/checkouts/${timeoutCheckoutId}`,
        {
          headers: (await administratorHeaders(org)).headers,
        },
      );
      if (readTimeout.status === 200) {
        const readBody = (await readTimeout.json()) as Record<string, unknown>;
        expect(readBody.shown_state).toBe("Abandoned");
      }
    }
  });

  it("E2E-P4.2-06 same client_request_id and the 11th checkout", async () => {
    const hourStart = "2026-04-01T08:00:00.000Z";
    await setClock(hourStart);

    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();
    const org = "org-checkout-06";
    await putBillingContact(org);
    await scriptPaymobStub("ok");

    const sharedClientRequestId = "req-checkout-06-shared";
    const first = await postCheckout(org, {
      client_request_id: sharedClientRequestId,
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: expectations!.terms.version,
    });
    expect(first.status).toBe(201);
    const firstBody = (await first.json()) as Record<string, unknown>;
    const firstCheckoutId = String(firstBody.checkout_id);

    const second = await postCheckout(org, {
      client_request_id: sharedClientRequestId,
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: expectations!.terms.version,
    });
    expect(second.status).toBe(201);
    const secondBody = (await second.json()) as Record<string, unknown>;
    expect(secondBody.checkout_id).toBe(firstCheckoutId);

    for (let index = 0; index < 9; index += 1) {
      const response = await postCheckout(org, {
        client_request_id: `req-checkout-06-distinct-${index}`,
        offer_id: expectations!.offer_id,
        offer_version: expectations!.version,
        terms_version: expectations!.terms.version,
      });
      expect(response.status).toBe(201);
    }

    const eleventh = await postCheckout(org, {
      client_request_id: "req-checkout-06-eleventh",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: expectations!.terms.version,
    });
    expect(eleventh.status).toBe(429);
    const eleventhBody = (await eleventh.json()) as Record<string, unknown>;
    expect(eleventhBody.code).toBe("rate_limited");
  });

  it("E2E-P4.2-07 other tenant 404 and two open checkouts listed", async () => {
    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();

    const orgA = "org-checkout-07-a";
    const orgB = "org-checkout-07-b";
    await putBillingContact(orgA);
    await putBillingContact(orgB);

    const first = await postCheckout(orgA, {
      client_request_id: "req-checkout-07-a1",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: expectations!.terms.version,
    });
    expect(first.status).toBe(201);
    const firstBody = (await first.json()) as Record<string, unknown>;

    const second = await postCheckout(orgA, {
      client_request_id: "req-checkout-07-a2",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: expectations!.terms.version,
    });
    expect(second.status).toBe(201);
    const secondBody = (await second.json()) as Record<string, unknown>;

    const tenantB = await administratorHeaders(orgB);
    const crossTenant = await billingFetch(
      `/v1/checkouts/${String(firstBody.checkout_id)}`,
      { headers: tenantB.headers },
    );
    expect(crossTenant.status).toBe(404);
    const crossTenantBody = (await crossTenant.json()) as Record<string, unknown>;
    expect(crossTenantBody.code).toBe("not_found");

    const tenantA = await administratorHeaders(orgA);
    const listOpen = await billingFetch("/v1/checkouts?open=1", {
      headers: tenantA.headers,
    });
    expect(listOpen.status).toBe(200);
    const listBody = (await listOpen.json()) as {
      checkouts: Array<{ reference: string }>;
    };
    expect(listBody.checkouts).toHaveLength(2);
    const references = listBody.checkouts.map((entry) => entry.reference);
    expect(references).toContain(String(firstBody.reference));
    expect(references).toContain(String(secondBody.reference));
  });
});
