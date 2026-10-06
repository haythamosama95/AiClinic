/**
 * P4.1 — catalogue and gate E2E tests (H-ABO).
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import offersFixture from "../../fixtures/offers.json";
import { loadOffersFixture } from "../../src/records/append";
import {
  applySql,
  billingFetch,
  clearCapturedEmails,
  clearCapturedHeartbeatFetches,
  getCapturedEmails,
  getCapturedHeartbeatFetches,
  mintAi,
  mintBilling,
  newIssuer,
  opsFetch,
  pinIssuer,
  resetHarnessState,
  r2GetText,
  runScheduled,
  setClock,
  setLockRulesBody,
  setSendEmailThrows,
  tableCount,
} from "./harness";

type OffersFixtureExpectations = {
  offer_id: string;
  version: number;
  plan_display_name: string;
  term_unit: string;
  term_count: number;
  price_minor: number;
  currency: string;
  allowance_credits: number;
  grace_days: number;
  terms: { version: number; text: string };
  retired_offer_id: string;
  older_version: number;
};

const dynamicImport = new Function(
  "specifier",
  "return import(specifier)",
) as (specifier: string) => Promise<{ default: unknown }>;

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
): Promise<Record<string, string>> {
  const issuer = await newIssuer();
  await pinIssuer(issuer.kid, issuer.publicKey);
  const now = Math.floor(Date.now() / 1000);
  const token = await mintBilling(issuer, {
    sub: options?.sub ?? "admin-sub",
    org,
    role: "administrator",
    branch: "branch-test",
    iat: now,
    exp: now + 300,
    jti: options?.jti ?? crypto.randomUUID(),
  });
  return {
    authorization: `Bearer ${token}`,
    "Abo-Contract-Version": "1",
  };
}

async function tokenUseHits(jti: string): Promise<number | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT hits FROM token_use WHERE jti = ?`,
    )
      .bind(jti)
      .first<{ hits: number }>();
    return row?.hits ?? null;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return null;
    }
    throw error;
  }
}

async function maxBillingContactVersion(orgId: string): Promise<number | null> {
  try {
    const row = await env.DB.prepare(
      `SELECT MAX(version) AS version FROM billing_contact WHERE org_id = ?`,
    )
      .bind(orgId)
      .first<{ version: number | null }>();
    return row?.version ?? null;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return null;
    }
    throw error;
  }
}

type AppendModule = {
  appendOffer?: (row: {
    offer_id: string;
    code: string;
    contract_version: number;
  }) => Promise<void>;
};

function addHours(isoUtc: string, hours: number): string {
  return new Date(Date.parse(isoUtc) + hours * 3_600_000).toISOString();
}

async function ensureRecordsMigration(): Promise<void> {
  try {
    const migrationModule = await dynamicImport(
      "../../migrations/0001_records.sql?raw",
    );
    await applySql(String((migrationModule as { default: string }).default));
  } catch {
    // Migration not present yet.
  }
}

async function appendMinimalOffer(): Promise<string> {
  const appendModule = (await import(
    "../../src/records/append.js"
  )) as AppendModule;
  expect(appendModule.appendOffer).toBeTypeOf("function");
  const suffix = crypto.randomUUID().replace(/-/g, "").slice(0, 20);
  const offerId = `01JTEST${suffix}`;
  await appendModule.appendOffer!({
    offer_id: offerId,
    code: `harness-minimal-offer-${suffix}`,
    contract_version: 1,
  });
  return offerId;
}

async function expectD1Abort(statement: string, ...binds: unknown[]): Promise<void> {
  await expect(
    env.DB.prepare(statement).bind(...binds).run(),
  ).rejects.toThrow(/append_only/i);
}

async function latestFactSeq(): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT fact_seq FROM fact_log ORDER BY fact_seq DESC LIMIT 1`,
  ).first<{ fact_seq: number }>();
  expect(row?.fact_seq).toBeTypeOf("number");
  return row!.fact_seq;
}

async function listLedgerExports(): Promise<
  Array<{ factSeq: number; text: string }>
> {
  const listed = await env.R2.list({ prefix: "ledger/" });
  const exports: Array<{ factSeq: number; text: string }> = [];
  for (const object of listed.objects) {
    const match = /^ledger\/(\d+)\.ndjson$/u.exec(object.key);
    if (!match) {
      continue;
    }
    const text = await r2GetText(object.key);
    exports.push({
      factSeq: Number.parseInt(match[1]!, 10),
      text: text ?? "",
    });
  }
  exports.sort((a, b) => a.factSeq - b.factSeq);
  return exports;
}

function emailsWithAl16(): Array<{
  from: string;
  to: string;
  subject: string;
  text: string;
}> {
  return getCapturedEmails().filter((message) => message.text.includes("AL-16"));
}

async function billingContactCount(orgId: string): Promise<number> {
  try {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM billing_contact WHERE org_id = ?`,
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

beforeEach(async () => {
  await resetHarnessState();
});

describe("catalogue", () => {
  it("E2E-P4.1-01 missing or unsupported Abo-Contract-Version is 400 before auth", async () => {
    const tokenUseBefore = await tableCount("token_use");
    const contactBefore = await tableCount("billing_contact");

    const paths = [
      { fetch: billingFetch, path: "/v1/offers" },
      { fetch: opsFetch, path: "/ops/lookup" },
    ] as const;

    for (const { fetch, path } of paths) {
      for (const version of [undefined, "2"] as const) {
        const headers: Record<string, string> = {
          authorization: "Bearer invalid-token",
        };
        if (version !== undefined) {
          headers["Abo-Contract-Version"] = version;
        }
        const response = await fetch(path, { headers });
        expect(response.status).toBe(400);
        const json = (await response.json()) as Record<string, unknown>;
        expect(json.code).toBe("contract_version_unsupported");
        expect(json.message).toBe("contract_version_unsupported");
        expect(json.contract_version).toBe(1);
        expect(json.accepted_versions).toEqual([0, 1]);
        expect(response.headers.get("Abo-Contract-Version")).toBe("1");
      }
    }

    expect(await tableCount("token_use")).toBe(tokenUseBefore);
    expect(await tableCount("billing_contact")).toBe(contactBefore);
  });

  it("E2E-P4.1-02 AI token and unpinned kid are 401 and doctor is 403", async () => {
    const pinned = await newIssuer();
    await pinIssuer(pinned.kid, pinned.publicKey);
    const unpinned = await newIssuer();

    const now = Math.floor(Date.now() / 1000);
    const baseClaims = {
      sub: "user-test",
      org: "org-test",
      branch: "branch-test",
      iat: now,
      exp: now + 300,
      jti: crypto.randomUUID(),
    };

    const aiToken = await mintAi(pinned, {
      ...baseClaims,
      role: "administrator",
      scopes: ["clinic.visit_summary"],
    });
    const aiResponse = await billingFetch("/v1/offers", {
      headers: {
        authorization: `Bearer ${aiToken}`,
        "Abo-Contract-Version": "1",
      },
    });
    expect(aiResponse.status).toBe(401);
    const aiJson = (await aiResponse.json()) as Record<string, unknown>;
    expect(aiJson.code).toBe("unauthenticated");

    const unpinnedToken = await mintBilling(unpinned, {
      ...baseClaims,
      role: "administrator",
      jti: crypto.randomUUID(),
    });
    const unpinnedResponse = await billingFetch("/v1/offers", {
      headers: {
        authorization: `Bearer ${unpinnedToken}`,
        "Abo-Contract-Version": "1",
      },
    });
    expect(unpinnedResponse.status).toBe(401);
    const unpinnedJson = (await unpinnedResponse.json()) as Record<string, unknown>;
    expect(unpinnedJson.code).toBe("unauthenticated");

    const doctorToken = await mintBilling(pinned, {
      ...baseClaims,
      role: "doctor",
      jti: crypto.randomUUID(),
    });
    const doctorResponse = await billingFetch("/v1/offers", {
      headers: {
        authorization: `Bearer ${doctorToken}`,
        "Abo-Contract-Version": "1",
      },
    });
    expect(doctorResponse.status).toBe(403);
    const doctorJson = (await doctorResponse.json()) as Record<string, unknown>;
    expect(doctorJson.code).toBe("forbidden_role");
  });

  it("E2E-P4.1-06 cross-host paths are 404 before version and auth", async () => {
    const tokenUseBefore = await tableCount("token_use");

    const crossings = [
      { fetch: billingFetch, path: "/ops/lookup" },
      { fetch: opsFetch, path: "/v1/offers" },
    ] as const;

    for (const { fetch, path } of crossings) {
      const withoutVersion = await fetch(path);
      expect(withoutVersion.status).toBe(404);
      expect(await withoutVersion.text()).toBe("");
      expect(withoutVersion.headers.get("Abo-Contract-Version")).toBeNull();

      const withVersion = await fetch(path, {
        headers: { "Abo-Contract-Version": "1" },
      });
      expect(withVersion.status).toBe(404);
      expect(await withVersion.text()).toBe("");
      expect(withVersion.headers.get("Abo-Contract-Version")).toBeNull();
    }

    expect(await tableCount("token_use")).toBe(tokenUseBefore);
  });

  it("E2E-P4.1-09 the 61st request with one billing token is 429", async () => {
    const pinned = await newIssuer();
    await pinIssuer(pinned.kid, pinned.publicKey);
    const jti = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    const token = await mintBilling(pinned, {
      sub: "rate-limit-sub",
      org: "org-rate-limit",
      role: "administrator",
      branch: "branch-test",
      iat: now,
      exp: now + 300,
      jti,
    });
    const headers = {
      authorization: `Bearer ${token}`,
      "Abo-Contract-Version": "1",
    };

    for (let i = 0; i < 60; i += 1) {
      const response = await billingFetch("/v1/offers", { headers });
      expect(response.status).toBe(200);
    }

    const limited = await billingFetch("/v1/offers", { headers });
    expect(limited.status).toBe(429);
    const json = (await limited.json()) as Record<string, unknown>;
    expect(json.code).toBe("rate_limited");
    expect(json.message).toBe("rate_limited");
    expect(json.contract_version).toBe(1);
    expect(limited.headers.get("Abo-Contract-Version")).toBe("1");
    expect(await tokenUseHits(jti)).toBe(60);
  });

  it("E2E-P4.1-03 GET offers lists the sellable latest version and echoes version 1", async () => {
    const expectations = await seedOffersCatalogueFixture();
    const headers = await administratorHeaders("org-offers");

    const response = await billingFetch("/v1/offers", { headers });
    expect(response.status).toBe(200);
    expect(response.headers.get("Abo-Contract-Version")).toBe("1");

    const body = (await response.json()) as {
      contract_version: number;
      offers: Array<Record<string, unknown>>;
    };
    expect(body.contract_version).toBe(1);
    expect(body.offers).toHaveLength(1);

    const offer = body.offers[0]!;
    if (expectations) {
      expect(offer.offer_id).toBe(expectations.offer_id);
      expect(offer.version).toBe(expectations.version);
      expect(offer.plan_display_name).toBe(expectations.plan_display_name);
      expect(offer.term_unit).toBe(expectations.term_unit);
      expect(offer.term_count).toBe(expectations.term_count);
      expect(offer.price_minor).toBe(expectations.price_minor);
      expect(offer.currency).toBe(expectations.currency);
      expect(offer.allowance_credits).toBe(expectations.allowance_credits);
      expect(offer.grace_days).toBe(expectations.grace_days);
      const terms = offer.terms as { version: number; text: string };
      expect(terms.version).toBe(expectations.terms.version);
      expect(terms.text).toBe(expectations.terms.text);
      expect(body.offers.some((row) => row.offer_id === expectations.retired_offer_id)).toBe(
        false,
      );
      expect(offer.version).not.toBe(expectations.older_version);
    } else {
      expect(offer.plan_display_name).toBeTruthy();
      expect(offer.version).toBeTruthy();
      const terms = offer.terms as { version: number; text: string };
      expect(terms.version).toBeTruthy();
      expect(terms.text).toBeTruthy();
    }
  });

  it("E2E-P4.1-04 PUT billing contact is idempotent and rejects a non-E.164 phone", async () => {
    const org = "org-contact-idempotent";
    const headers = await administratorHeaders(org);

    const firstBody = {
      client_request_id: "req-contact-1",
      name: "Clinic Admin",
      email: "admin@clinic.test",
      phone: "+201001234567",
    };
    const first = await billingFetch("/v1/billing-contact", {
      method: "PUT",
      headers: { ...headers, "content-type": "application/json" },
      body: JSON.stringify(firstBody),
    });
    expect(first.status).toBe(200);
    const firstJson = (await first.json()) as Record<string, unknown>;
    expect(firstJson.version).toBe(1);

    const second = await billingFetch("/v1/billing-contact", {
      method: "PUT",
      headers: { ...headers, "content-type": "application/json" },
      body: JSON.stringify({
        ...firstBody,
        name: "Different Name",
      }),
    });
    expect(second.status).toBe(200);
    const secondJson = (await second.json()) as Record<string, unknown>;
    expect(secondJson.version).toBe(1);
    expect(await billingContactCount(org)).toBe(1);
    expect(await maxBillingContactVersion(org)).toBe(1);

    const third = await billingFetch("/v1/billing-contact", {
      method: "PUT",
      headers: { ...headers, "content-type": "application/json" },
      body: JSON.stringify({
        client_request_id: "req-contact-2",
        name: "Clinic Admin",
        email: "admin@clinic.test",
        phone: "+201009998877",
      }),
    });
    expect(third.status).toBe(200);
    const thirdJson = (await third.json()) as Record<string, unknown>;
    expect(thirdJson.version).toBe(2);
    expect(await maxBillingContactVersion(org)).toBe(2);

    const rowsBeforeInvalid = await billingContactCount(org);
    const invalid = await billingFetch("/v1/billing-contact", {
      method: "PUT",
      headers: { ...headers, "content-type": "application/json" },
      body: JSON.stringify({
        client_request_id: "req-contact-invalid",
        name: "Clinic Admin",
        email: "admin@clinic.test",
        phone: "12345",
      }),
    });
    expect(invalid.status).toBe(422);
    const invalidJson = (await invalid.json()) as Record<string, unknown>;
    expect(invalidJson.code).toBe("invalid_request");
    expect(await billingContactCount(org)).toBe(rowsBeforeInvalid);
    expect(await maxBillingContactVersion(org)).toBe(2);
  });

  it("E2E-P4.1-05 tenant B does not receive tenant A contact", async () => {
    const orgA = "org-tenant-a";
    const orgB = "org-tenant-b";
    const headersA = await administratorHeaders(orgA, { sub: "sub-tenant-a" });
    const headersB = await administratorHeaders(orgB, { sub: "sub-tenant-b" });

    const putA = await billingFetch("/v1/billing-contact", {
      method: "PUT",
      headers: { ...headersA, "content-type": "application/json" },
      body: JSON.stringify({
        client_request_id: "req-tenant-a",
        name: "Tenant A Admin",
        email: "a@clinic.test",
        phone: "+201001111111",
      }),
    });
    expect(putA.status).toBe(200);

    const getB = await billingFetch("/v1/billing-contact", { headers: headersB });
    expect(getB.status).toBe(404);
    const getBJson = (await getB.json()) as Record<string, unknown>;
    expect(getBJson.code).toBe("not_found");

    const putB = await billingFetch("/v1/billing-contact", {
      method: "PUT",
      headers: { ...headersB, "content-type": "application/json" },
      body: JSON.stringify({
        client_request_id: "req-tenant-b",
        org: orgA,
        name: "Tenant B Admin",
        email: "b@clinic.test",
        phone: "+201002222222",
      }),
    });
    expect(putB.status).toBe(200);
    const putBJson = (await putB.json()) as Record<string, unknown>;
    expect(putBJson.version).toBe(1);

    const getBAfter = await billingFetch("/v1/billing-contact", { headers: headersB });
    expect(getBAfter.status).toBe(200);
    const getBAfterJson = (await getBAfter.json()) as Record<string, unknown>;
    expect(getBAfterJson.email).toBe("b@clinic.test");
    expect(getBAfterJson.phone).toBe("+201002222222");

    const getA = await billingFetch("/v1/billing-contact", { headers: headersA });
    expect(getA.status).toBe(200);
    const getAJson = (await getA.json()) as Record<string, unknown>;
    expect(getAJson.email).toBe("a@clinic.test");
    expect(getAJson.phone).toBe("+201001111111");
    expect(await billingContactCount(orgA)).toBe(1);
    expect(await billingContactCount(orgB)).toBe(1);
  });

  it("E2E-P4.1-07 append-only rejects update and delete and the minute cron exports facts", async () => {
    await ensureRecordsMigration();
    const offerId = await appendMinimalOffer();

    await expectD1Abort(
      `UPDATE offer SET code = ? WHERE offer_id = ?`,
      "mutated",
      offerId,
    );
    await expectD1Abort(`DELETE FROM offer WHERE offer_id = ?`, offerId);

    expect(await tableCount("fact_log")).toBe(1);

    await runScheduled("* * * * *");

    const ledgerExports = await listLedgerExports();
    expect(ledgerExports.length).toBeGreaterThan(0);
    for (const exportRow of ledgerExports) {
      expect(exportRow.text.split("\n").filter((line) => line.length > 0)).toHaveLength(
        1,
      );
      expect(exportRow.text).not.toMatch(/"name"/u);
      expect(exportRow.text).not.toMatch(/"email"/u);
      expect(exportRow.text).not.toMatch(/"phone"/u);
    }
    for (let index = 1; index < ledgerExports.length; index += 1) {
      expect(ledgerExports[index]!.factSeq).toBeGreaterThan(
        ledgerExports[index - 1]!.factSeq,
      );
    }
  });

  it("E2E-P4.1-08 export lag raises AL-16 once then daily and a failed send is retried", async () => {
    await ensureRecordsMigration();
    const factCreatedAt = "2026-06-01T10:00:00.000Z";
    await setClock(factCreatedAt);
    await appendMinimalOffer();
    const factSeq = await latestFactSeq();

    clearCapturedEmails();
    await setClock(addHours(factCreatedAt, 2));
    await runScheduled("* * * * *");
    expect(emailsWithAl16()).toHaveLength(1);
    expect(emailsWithAl16()[0]!.text).toContain("AL-16");
    expect(emailsWithAl16()[0]!.text).toContain(String(factSeq));

    const afterFirst = emailsWithAl16().length;
    await setClock(addHours(addHours(factCreatedAt, 2), 24));
    await runScheduled("* * * * *");
    expect(emailsWithAl16().length).toBe(afterFirst + 1);

    clearCapturedEmails();
    const retryCreatedAt = "2026-07-01T08:00:00.000Z";
    await setClock(retryCreatedAt);
    await appendMinimalOffer();
    const retryFactSeq = await latestFactSeq();
    await setClock(addHours(retryCreatedAt, 2));
    setSendEmailThrows(true);
    await runScheduled("* * * * *");
    expect(emailsWithAl16()).toHaveLength(0);
    setSendEmailThrows(false);
    await runScheduled("* * * * *");
    expect(emailsWithAl16()).toHaveLength(1);
    expect(emailsWithAl16()[0]!.text).toContain(String(retryFactSeq));

    clearCapturedEmails();
    await runScheduled("0 6 * * *");
    expect(emailsWithAl16().some((message) => message.text.includes("r2-lock"))).toBe(
      false,
    );

    clearCapturedEmails();
    setLockRulesBody({ success: true, result: { rules: [] } });
    await runScheduled("0 6 * * *");
    expect(emailsWithAl16()).toHaveLength(1);
    expect(emailsWithAl16()[0]!.text).toContain("AL-16");
    expect(emailsWithAl16()[0]!.text).toContain("r2-lock");

    clearCapturedEmails();
    setLockRulesBody({ success: false, result: { rules: [] } });
    await runScheduled("0 6 * * *");
    expect(emailsWithAl16()).toHaveLength(0);
  });

  it("E2E-P4.1-10 minute cron pings the heartbeat URL", async () => {
    clearCapturedHeartbeatFetches();
    await runScheduled("* * * * *");
    expect(getCapturedHeartbeatFetches()).toContain(env.HEARTBEAT_URL);
  });
});
