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
  harnessClockNowSeconds,
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
import checkoutCreationAttemptsMigrationSql from "../../migrations/0011_checkout_creation_attempts.sql?raw";
import { paymobUnifiedCheckoutUrl } from "../../src/provider/paymob/adapter";

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
  try {
    await applySql(checkoutCreationAttemptsMigrationSql);
  } catch {
    // Migration may already be applied by another harness setup.
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
  const now = await harnessClockNowSeconds();
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

async function currentTermsVersion(): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT MAX(terms_version) AS version FROM terms_version`,
  ).first<{ version: number | null }>();
  expect(row?.version).toBeTypeOf("number");
  return row!.version!;
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

async function intentionAttempts(checkoutId: string): Promise<Array<{
  attempt_no: number;
  state: string;
  special_reference: string;
}>> {
  const rows = await env.DB.prepare(
    `SELECT attempt_no, state, special_reference FROM paymob_intention_attempt
     WHERE checkout_id = ? ORDER BY attempt_no`,
  ).bind(checkoutId).all<{
    attempt_no: number;
    state: string;
    special_reference: string;
  }>();
  return rows.results ?? [];
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
  it("R3-C3 hosted checkout URL pins the path and rejects base URL suffixes", () => {
    const url = new URL(
      paymobUnifiedCheckoutUrl(
        "https://accept.paymob.com/",
        "public key",
        "client/secret",
      ),
    );
    expect(url.href).toBe(
      "https://accept.paymob.com/unifiedcheckout/?publicKey=public+key&clientSecret=client%2Fsecret",
    );
    expect(() =>
      paymobUnifiedCheckoutUrl(
        "https://accept.paymob.com/api",
        "public-key",
        "client-secret",
      ),
    ).toThrow("PAYMOB_BASE_URL must be an HTTPS origin");
    expect(() =>
      paymobUnifiedCheckoutUrl(
        "https://accept.paymob.com/?mode=test",
        "public-key",
        "client-secret",
      ),
    ).toThrow("PAYMOB_BASE_URL must be an HTTPS origin");
    expect(() =>
      paymobUnifiedCheckoutUrl(
        "https://accept.paymob.com/#checkout",
        "public-key",
        "client-secret",
      ),
    ).toThrow("PAYMOB_BASE_URL must be an HTTPS origin");
    expect(() =>
      paymobUnifiedCheckoutUrl(
        "http://localhost:8787",
        "public-key",
        "client-secret",
      ),
    ).toThrow("PAYMOB_BASE_URL must be an HTTPS origin");
    expect(
      paymobUnifiedCheckoutUrl(
        "http://127.0.0.1:8787/",
        "public-key",
        "client-secret",
        true,
      ),
    ).toBe(
      "http://127.0.0.1:8787/unifiedcheckout/?publicKey=public-key&clientSecret=client-secret",
    );
    expect(() =>
      paymobUnifiedCheckoutUrl(
        "http://paymob.example.test",
        "public-key",
        "client-secret",
        true,
      ),
    ).toThrow("PAYMOB_BASE_URL must be an HTTPS origin");
  });

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
    const hostedCheckout = new URL(String(body.redirect_url));
    expect(hostedCheckout.origin).toBe("https://paymob.harness.test");
    expect(hostedCheckout.pathname).toBe("/unifiedcheckout/");
    expect(hostedCheckout.searchParams.get("publicKey")).toBe(
      "paymob-public-test",
    );
    expect(hostedCheckout.searchParams.get("clientSecret")).toBe(
      "stub-client-secret",
    );
    expect(body.expires_at).toBe(addMinutes(clockIso, 30));

    const paymobBody = await getLastPaymobIntentionBody();
    expect(paymobBody.amount).toBe(expectations!.price_minor);
    expect(paymobBody.special_reference).toBe(`${String(body.reference)}-1`);
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
      snapshot?: { coverage_through?: string };
    };
    const coverageThrough = snapshot.snapshot?.coverage_through;
    expect(typeof coverageThrough).toBe("string");

    expect(response.status).toBe(201);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.starts).toBe("after_current");
    expect(body.projected_start).toBe(coverageThrough);
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

    const latest = await env.DB.prepare(
      `SELECT MAX(terms_version) AS version FROM terms_version`,
    ).first<{ version: number | null }>();
    const currentTermsVersion = (latest?.version ?? 0) + 1;
    const currentTermsKey = `terms/en/checkout-current-${currentTermsVersion}.txt`;
    await env.R2.put(currentTermsKey, `Current checkout terms ${currentTermsVersion}`);
    await env.DB.prepare(
      `INSERT INTO terms_version (
         terms_version, locale, text_r2_key, text_sha256, published_by, contract_version
       ) VALUES (?, 'en', ?, ?, 'fixture', 1)`,
    ).bind(currentTermsVersion, currentTermsKey, `sha256-${currentTermsVersion}`).run();
    const orgCurrentTerms = "org-checkout-04-current-terms";
    await putBillingContact(orgCurrentTerms);
    const currentTermsCheckout = await postCheckout(orgCurrentTerms, {
      client_request_id: "req-checkout-04-current-terms",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: currentTermsVersion,
    });
    expect(currentTermsCheckout.status).toBe(201);
    const currentTermsBody = (await currentTermsCheckout.json()) as Record<string, unknown>;
    const currentCheckoutRow = await checkoutRow(String(currentTermsBody.checkout_id));
    expect(currentCheckoutRow?.terms_version).toBe(currentTermsVersion);
    const checkoutFact = await env.DB.prepare(
      `SELECT row_json FROM fact_log WHERE "table" = 'checkout' AND key = ?`,
    ).bind(String(currentTermsBody.checkout_id)).first<{ row_json: string }>();
    expect(checkoutFact).not.toBeNull();
    expect(JSON.parse(checkoutFact!.row_json).terms_version).toBe(currentTermsVersion);
  });

  it("R8-CONSOLE1/R8-CONSOLE5: a retired offer is not sellable, a reinstated version is sellable, and a malformed version is not sellable", async () => {
    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();
    const offerId = expectations!.offer_id;
    const version = expectations!.version;
    const org = crypto.randomUUID();
    await putBillingContact(org);
    await setupActivePlatformCoverage(org);

    const lastAt = await env.DB.prepare(
      `SELECT MAX(at) AS at FROM offer_event WHERE offer_id = ?`,
    )
      .bind(offerId)
      .first<{ at: string | null }>();
    const baseAt = lastAt?.at ?? "2026-06-01T12:00:00.000Z";
    const insertOfferEvent = async (
      kind: string,
      eventVersion: number,
      minutesAfter: number,
    ): Promise<void> => {
      await env.DB.prepare(
        `INSERT INTO offer_event (offer_id, kind, version, actor, at, contract_version)
         VALUES (?, ?, ?, 'fixture', ?, 1)`,
      )
        .bind(offerId, kind, eventVersion, addMinutes(baseAt, minutesAfter))
        .run();
    };
    const checkoutFor = (clientRequestId: string, offerVersion: number) =>
      postCheckout(org, {
        client_request_id: clientRequestId,
        offer_id: offerId,
        offer_version: offerVersion,
        terms_version: expectations!.terms.version,
      });

    // Retired: the version is not sellable.
    await insertOfferEvent("retired", version, 1);
    const retired = await checkoutFor("req-checkout-r8-retired", version);
    expect(retired.status).toBe(409);
    expect(((await retired.json()) as Record<string, unknown>).code).toBe(
      "offer_unavailable",
    );

    // Reinstated: the console writes `published` for the last published version.
    await insertOfferEvent("published", version, 2);
    const reinstated = await checkoutFor("req-checkout-r8-reinstated", version);
    expect(reinstated.status).toBe(201);

    // Historical `reinstated` rows are the same activation.
    await insertOfferEvent("reinstated", version, 3);
    const historical = await checkoutFor("req-checkout-r8-historical", version);
    expect(historical.status).toBe(201);

    // Malformed: a newer published version whose stored copy has no `en` entry is refused.
    const maxVersionRow = await env.DB.prepare(
      `SELECT MAX(version) AS version FROM offer_version WHERE offer_id = ?`,
    )
      .bind(offerId)
      .first<{ version: number }>();
    const malformedVersion = maxVersionRow!.version + 1;
    await env.DB.prepare(
      `INSERT INTO offer_version (
         offer_id, version, plan_id, plan_version, term_unit, term_count,
         price_minor, currency, allowance_credits, grace_days, grace_cap_rule,
         copy, terms_version, published_by, assertion_sha256, contract_version
       )
       SELECT offer_id, ?, plan_id, plan_version, term_unit, term_count,
              price_minor, currency, allowance_credits, grace_days, grace_cap_rule,
              '{}', terms_version, 'fixture', 'fixture-assertion-malformed', contract_version
       FROM offer_version WHERE offer_id = ? AND version = ?`,
    )
      .bind(malformedVersion, offerId, version)
      .run();
    await insertOfferEvent("published", malformedVersion, 4);
    const checkoutsBefore = await checkoutCount(org);
    const malformed = await checkoutFor("req-checkout-r8-malformed", malformedVersion);
    expect(malformed.status).toBe(409);
    expect(((await malformed.json()) as Record<string, unknown>).code).toBe(
      "offer_unavailable",
    );
    expect(await checkoutCount(org)).toBe(checkoutsBefore);
  });

  it("E2E-P4.2-05 R3-C2 provider failure is durable and retry uses the next reference", async () => {
    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();
    const termsVersion = await currentTermsVersion();
    const org = "org-checkout-05";

    await scriptPaymobStub("refuse");
    await putBillingContact(org);
    const refuseResponse = await postCheckout(org, {
      client_request_id: "req-checkout-05-refuse",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
    });
    expect(refuseResponse.status).toBe(503);
    const refuseBody = (await refuseResponse.json()) as Record<string, unknown>;
    expect(refuseBody.code).toBe("provider_unavailable");
    const refuseCheckoutId = String(refuseBody.checkout_id ?? "");
    expect(refuseCheckoutId).toBeTruthy();
    expect(await checkoutEventKinds(refuseCheckoutId)).toContain("open_failed");
    const firstAttempts = await intentionAttempts(refuseCheckoutId);
    expect(firstAttempts).toHaveLength(1);
    expect(firstAttempts[0]).toEqual(
      expect.objectContaining({ attempt_no: 1, state: "abandoned_unconfirmed" }),
    );
    const refuseCheckout = await checkoutRow(refuseCheckoutId);
    expect(refuseCheckout).not.toBeNull();
    expect(firstAttempts[0]?.special_reference).toBe(
      `${String(refuseCheckout!.reference)}-1`,
    );
    const readRefuse = await billingFetch(`/v1/checkouts/${refuseCheckoutId}`, {
      headers: (await administratorHeaders(org)).headers,
    });
    expect(readRefuse.status).toBe(200);
    const readBody = (await readRefuse.json()) as Record<string, unknown>;
    expect(readBody.shown_state).toBe("Abandoned");

    await scriptPaymobStub("ok");
    const retry = await postCheckout(org, {
      client_request_id: "req-checkout-05-refuse",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
    });
    expect(retry.status).toBe(201);
    const retryBody = (await retry.json()) as Record<string, unknown>;
    expect(retryBody.checkout_id).toBe(refuseCheckoutId);
    const attempts = await intentionAttempts(refuseCheckoutId);
    expect(attempts.map((attempt) => attempt.attempt_no)).toEqual([1, 2]);
    expect(attempts[1]?.state).toBe("created");
    expect(attempts[1]?.special_reference).toBe(
      `${String(refuseCheckout!.reference)}-2`,
    );
    expect((await getLastPaymobIntentionBody()).special_reference)
      .toBe(`${String(refuseCheckout!.reference)}-2`);

    await scriptPaymobStub("timeout");
    const timeoutResponse = await postCheckout(org, {
      client_request_id: "req-checkout-05-timeout",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
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

  it("E2E-P4.2-06 R3-M2 same-key replay and atomic 10th checkout admission", async () => {
    const hourStart = "2026-04-01T08:00:00.000Z";
    await setClock(hourStart);

    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();
    const org = "org-checkout-06";
    const termsVersion = await currentTermsVersion();
    await putBillingContact(org);
    await scriptPaymobStub("ok");

    const sharedClientRequestId = "req-checkout-06-shared";
    const first = await postCheckout(org, {
      client_request_id: sharedClientRequestId,
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
    });
    expect(first.status).toBe(201);
    const firstBody = (await first.json()) as Record<string, unknown>;
    const firstCheckoutId = String(firstBody.checkout_id);

    const second = await postCheckout(org, {
      client_request_id: sharedClientRequestId,
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
    });
    expect(second.status).toBe(201);
    const secondBody = (await second.json()) as Record<string, unknown>;
    expect(secondBody.checkout_id).toBe(firstCheckoutId);
    expect(await checkoutCount(org)).toBe(1);

    const changedPayload = await postCheckout(org, {
      client_request_id: sharedClientRequestId,
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion + 1,
    });
    expect(changedPayload.status).toBe(409);
    expect(((await changedPayload.json()) as Record<string, unknown>).code)
      .toBe("idempotency_conflict");
    expect(await checkoutCount(org)).toBe(1);

    for (let index = 0; index < 7; index += 1) {
      const response = await postCheckout(org, {
        client_request_id: `req-checkout-06-distinct-${index}`,
        offer_id: expectations!.offer_id,
        offer_version: expectations!.version,
        terms_version: termsVersion,
      });
      expect(response.status).toBe(201);
    }

    const replayBeforeLastSlot = await postCheckout(org, {
      client_request_id: sharedClientRequestId,
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
    });
    expect(replayBeforeLastSlot.status).toBe(201);
    const replayBeforeLastSlotBody =
      (await replayBeforeLastSlot.json()) as Record<string, unknown>;
    expect(replayBeforeLastSlotBody.checkout_id).toBe(firstCheckoutId);
    expect(await checkoutCount(org)).toBe(8);

    const ninth = await postCheckout(org, {
      client_request_id: "req-checkout-06-ninth",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
    });
    expect(ninth.status).toBe(201);

    const racing = await Promise.all(["race-a", "race-b"].map((suffix) =>
      postCheckout(org, {
        client_request_id: `req-checkout-06-${suffix}`,
        offer_id: expectations!.offer_id,
        offer_version: expectations!.version,
        terms_version: termsVersion,
      }),
    ));
    expect(racing.map((response) => response.status).sort()).toEqual([201, 429]);
    expect(await checkoutCount(org)).toBe(10);

    const replayAtLimit = await postCheckout(org, {
      client_request_id: sharedClientRequestId,
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
    });
    expect(replayAtLimit.status).toBe(201);
    const replayAtLimitBody = (await replayAtLimit.json()) as Record<string, unknown>;
    expect(replayAtLimitBody.checkout_id).toBe(firstCheckoutId);
    expect(await checkoutCount(org)).toBe(10);

    const eleventh = await postCheckout(org, {
      client_request_id: "req-checkout-06-eleventh",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
    });
    expect(eleventh.status).toBe(429);
    const eleventhBody = (await eleventh.json()) as Record<string, unknown>;
    expect(eleventhBody.code).toBe("rate_limited");
    expect(await checkoutCount(org)).toBe(10);
  });

  it("E2E-P4.2-07 other tenant 404 and two open checkouts listed", async () => {
    const expectations = await seedOffersCatalogueFixture();
    expect(expectations).not.toBeNull();
    const termsVersion = await currentTermsVersion();

    const orgA = "org-checkout-07-a";
    const orgB = "org-checkout-07-b";
    await putBillingContact(orgA);
    await putBillingContact(orgB);

    const first = await postCheckout(orgA, {
      client_request_id: "req-checkout-07-a1",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
    });
    expect(first.status).toBe(201);
    const firstBody = (await first.json()) as Record<string, unknown>;

    const second = await postCheckout(orgA, {
      client_request_id: "req-checkout-07-a2",
      offer_id: expectations!.offer_id,
      offer_version: expectations!.version,
      terms_version: termsVersion,
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
