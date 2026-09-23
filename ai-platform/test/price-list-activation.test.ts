/**
 * G4 — Price-list activation and invoice evidence (Workers integration).
 * M1 — credit-price activate withdrawn: assert route 404; no activate happy-path writes.
 */
import { env, SELF } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import planCatalogueSql from "../migrations/20260911120000_plan_catalogue.sql?raw";
import quotaWeightMigrationSql from "../migrations/20260911180000_usage_rollup_quota_weight.sql?raw";
import invoiceMigrationSql from "../migrations/20260911200000_invoice.sql?raw";
import { runPeriodClose } from "../src/period-close";
import * as pricing from "../src/pricing/index";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    OPERATOR_BEARER_TOKEN: string;
    OPERATOR_ID: string;
  }
}

const GATEWAY_ORIGIN = "https://ai-gateway.test";
const TEST_OPERATOR_BEARER = "test-operator-bearer-token";
const TEST_OPERATOR_ID = "operator-test-principal";

const FIXTURE_PERIOD = "2026-08";
const FIXTURE_PERIOD_START = "2026-08-01T00:00:00.000Z";
const FIXTURE_PERIOD_END = "2026-09-01T00:00:00.000Z";
const FIXTURE_ORG_ID = "org-price-list-001";
const FIXTURE_INSTALLATION = "inst-price-list-001";

const PAYMENT_PROVIDER_URL =
  /stripe\.com|paypal\.|braintree|adyen|checkout\.com|payment-provider|payments\.api/i;

type CreditPriceActivatePayload = {
  version: string;
  price_per_credit: number;
  currency: string;
  active_from: string;
};

type InvoiceRow = {
  installation_id: string;
  period: string;
  credits_consumed: number;
  credit_price_version: string;
  total: number;
  status: string;
  issued_at: string;
};

type UsageRollupRow = {
  rollup_id: string;
  dimensions: string;
  request_count: number;
  tokens: number;
  cost: number;
  quota_weight: number;
};

type RequestReferenceRow = {
  request_id: string;
  request_reference: string;
};

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);

  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function rollupIdFor(installationId: string, period: string): Promise<string> {
  const dimensions = JSON.stringify({ installation_id: installationId, period });
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(dimensions),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function seedInstallation(installationId: string = FIXTURE_INSTALLATION): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (
      installation_id, org_id, display_name, status, region, enrolled_at
    ) VALUES (?, ?, ?, 'active', 'us-east-1', ?)`,
  )
    .bind(
      installationId,
      FIXTURE_ORG_ID,
      "Price List Clinic",
      FIXTURE_PERIOD_START,
    )
    .run();
}

async function seedEntitlement(
  installationId: string = FIXTURE_INSTALLATION,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO entitlement (
      entitlement_id, installation_id, plan, period_start, period_end,
      request_quota, token_budget, cost_budget, credit_budget,
      allowed_capabilities, soft_threshold, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      `ent-${installationId}`,
      installationId,
      "professional",
      FIXTURE_PERIOD_START,
      FIXTURE_PERIOD_END,
      10_000,
      10_000_000,
      1_000,
      10_000,
      JSON.stringify(["ai.access"]),
      0.8,
      "active",
    )
    .run();
}

async function seedUsageRollup(options: {
  installationId?: string;
  period?: string;
  quotaWeight: number;
  requestCount?: number;
  tokens?: number;
  cost?: number;
}): Promise<void> {
  const installationId = options.installationId ?? FIXTURE_INSTALLATION;
  const period = options.period ?? FIXTURE_PERIOD;
  const dimensions = JSON.stringify({ installation_id: installationId, period });
  const rollupId = await rollupIdFor(installationId, period);
  await env.DB.prepare(
    `INSERT INTO usage_rollup (
       rollup_id, dimensions, request_count, tokens, cost, quota_weight
     ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      rollupId,
      dimensions,
      options.requestCount ?? 1,
      options.tokens ?? 999_999,
      options.cost ?? 999.99,
      options.quotaWeight,
    )
    .run();
}

async function seedCreditPrice(options: {
  version: string;
  pricePerCredit: number;
  currency?: string;
  activeFrom: string;
  activatedBy?: string;
}): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO credit_price (
       version, price_per_credit, currency, active_from, activated_by
     ) VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(
      options.version,
      options.pricePerCredit,
      options.currency ?? "USD",
      options.activeFrom,
      options.activatedBy ?? TEST_OPERATOR_ID,
    )
    .run();
}

async function seedTerminalRequestWithUsage(options: {
  requestId: string;
  reference: string;
  installationId?: string;
  period?: string;
  quotaWeight: number;
  tokens?: number;
  cost?: number;
}): Promise<void> {
  const installationId = options.installationId ?? FIXTURE_INSTALLATION;
  const period = options.period ?? FIXTURE_PERIOD;
  const completedAt = "2026-08-15T12:00:00.000Z";

  await env.DB.prepare(
    `INSERT INTO ai_request (
      request_id, request_reference, installation_id, actor_id, branch_id,
      capability_id, capability_version, prompt_artifact_hash, idempotency_key,
      trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
      payload_pointer, conversation_id, turn_ordinal
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL)`,
  )
    .bind(
      options.requestId,
      options.reference,
      installationId,
      "actor-price-list-001",
      "branch-price-list-001",
      "clinic.price-list-test",
      "1.0.0",
      "prompt/price-list@v1",
      `idem-${options.requestId}`,
      `trace-${options.requestId}`,
      "Completed",
      completedAt,
      completedAt,
      completedAt,
    )
    .run();

  await env.DB.prepare(
    `INSERT INTO usage_event (
      usage_event_id, installation_id, period, request_id, quota_weight, tokens, cost, recorded_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      `usage-${options.requestId}`,
      installationId,
      period,
      options.requestId,
      options.quotaWeight,
      options.tokens ?? 150,
      options.cost ?? 0.01,
      completedAt,
    )
    .run();
}

function buildCreditPriceActivateRequest(
  payload: CreditPriceActivatePayload,
  bearerToken: string = TEST_OPERATOR_BEARER,
): Request {
  return new Request(`${GATEWAY_ORIGIN}/control/credit-price/activate`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${bearerToken}`,
    },
    body: JSON.stringify(payload),
  });
}

async function fetchInvoice(
  installationId: string = FIXTURE_INSTALLATION,
  period: string = FIXTURE_PERIOD,
): Promise<InvoiceRow | null> {
  return env.DB.prepare(
    `SELECT installation_id, period, credits_consumed, credit_price_version,
            total, status, issued_at
     FROM invoice
     WHERE installation_id = ? AND period = ?`,
  )
    .bind(installationId, period)
    .first<InvoiceRow>();
}

async function fetchUsageRollupForInvoice(
  installationId: string,
  period: string,
): Promise<UsageRollupRow[]> {
  const result = await env.DB.prepare(
    `SELECT rollup_id, dimensions, request_count, quota_weight, tokens, cost
     FROM usage_rollup
     WHERE json_extract(dimensions, '$.installation_id') = ?
       AND json_extract(dimensions, '$.period') = ?
     ORDER BY rollup_id`,
  )
    .bind(installationId, period)
    .all<UsageRollupRow>();
  return result.results ?? [];
}

async function fetchRequestReferencesForPeriod(
  installationId: string,
  period: string,
): Promise<RequestReferenceRow[]> {
  const result = await env.DB.prepare(
    `SELECT ue.request_id, ar.request_reference
     FROM usage_event ue
     JOIN ai_request ar ON ar.request_id = ue.request_id
     WHERE ue.installation_id = ?
       AND ue.period = ?
       AND ue.request_id IS NOT NULL
     ORDER BY ar.request_reference`,
  )
    .bind(installationId, period)
    .all<RequestReferenceRow>();
  return result.results ?? [];
}

function looksLikePaymentProvider(url: string): boolean {
  return PAYMENT_PROVIDER_URL.test(url);
}

function requestUrl(input: RequestInfo | URL): string {
  return typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
}

async function clearPriceListTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM invoice"),
    env.DB.prepare("DELETE FROM control_audit"),
    env.DB.prepare("DELETE FROM credit_price"),
    env.DB.prepare("DELETE FROM usage_rollup"),
    env.DB.prepare("DELETE FROM usage_event"),
    env.DB.prepare("DELETE FROM ai_request"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, planCatalogueSql);
  await applyPlatformSchema(env.DB, quotaWeightMigrationSql);
  await applyPlatformSchema(env.DB, invoiceMigrationSql);
});

beforeEach(async () => {
  await clearPriceListTables();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("m1_credit_price_activate_returns_404", () => {
  it("m1_credit_price_activate_returns_404", async () => {
    // Route unregistered after M1 — no credit_price table read/write in this case.
    const response = await SELF.fetch(
      buildCreditPriceActivateRequest({
        version: "v2026-09",
        price_per_credit: 0.25,
        currency: "USD",
        active_from: "2026-09-01T00:00:00.000Z",
      }),
    );

    expect(response.status).toBe(404);
    expect(await response.text()).toBe("Not Found");
  });
});

describe("invoice_resolves_to_usage_rollup", () => {
  it("matches invoice credits_consumed to usage_rollup quota_weight for the period", async () => {
    await seedInstallation();
    await seedEntitlement();
    await seedUsageRollup({ quotaWeight: 75 });
    await seedCreditPrice({
      version: "v2026-07",
      pricePerCredit: 0.2,
      activeFrom: "2026-07-01T00:00:00.000Z",
    });

    await runPeriodClose({ db: env.DB, period: FIXTURE_PERIOD });

    const invoice = await fetchInvoice();
    expect(invoice).not.toBeNull();

    const rollupRows = await fetchUsageRollupForInvoice(
      invoice!.installation_id,
      invoice!.period,
    );
    expect(rollupRows.length).toBeGreaterThan(0);

    const rollupCredits = rollupRows.reduce(
      (sum, row) => sum + row.quota_weight,
      0,
    );
    expect(invoice?.credits_consumed).toBe(rollupCredits);
    expect(invoice?.credits_consumed).toBe(75);
  });
});

describe("invoice_line_traces_to_request_references", () => {
  it("traces usage_rollup evidence through usage_event to ai_request.request_reference", async () => {
    await seedInstallation();
    await seedEntitlement();
    await seedTerminalRequestWithUsage({
      requestId: "req-evidence-001",
      reference: "REF-EVIDENCE-001",
      quotaWeight: 30,
    });
    await seedTerminalRequestWithUsage({
      requestId: "req-evidence-002",
      reference: "REF-EVIDENCE-002",
      quotaWeight: 20,
    });
    await seedUsageRollup({ quotaWeight: 50 });
    await seedCreditPrice({
      version: "v2026-07",
      pricePerCredit: 0.1,
      activeFrom: "2026-07-01T00:00:00.000Z",
    });

    await runPeriodClose({ db: env.DB, period: FIXTURE_PERIOD });

    const invoice = await fetchInvoice();
    expect(invoice).not.toBeNull();

    const rollupRows = await fetchUsageRollupForInvoice(
      invoice!.installation_id,
      invoice!.period,
    );
    expect(rollupRows.length).toBeGreaterThan(0);

    const references = await fetchRequestReferencesForPeriod(
      invoice!.installation_id,
      invoice!.period,
    );
    expect(references.map((row) => row.request_reference)).toEqual([
      "REF-EVIDENCE-001",
      "REF-EVIDENCE-002",
    ]);
    expect(references.every((row) => row.request_id.length > 0)).toBe(true);
  });
});

describe("no_payment_provider_call", () => {
  it("makes zero payment-provider fetch calls during close", async () => {
    const paymentProviderCalls: string[] = [];
    const originalFetch = globalThis.fetch.bind(globalThis);
    vi.spyOn(globalThis, "fetch").mockImplementation(
      async (input, init) => {
        const url = requestUrl(input);
        if (looksLikePaymentProvider(url)) {
          paymentProviderCalls.push(url);
        }
        return originalFetch(input, init);
      },
    );

    await seedInstallation();
    await seedEntitlement();
    await seedUsageRollup({ quotaWeight: 10 });
    await seedCreditPrice({
      version: "v2026-07",
      pricePerCredit: 0.1,
      activeFrom: "2026-07-01T00:00:00.000Z",
    });

    await runPeriodClose({ db: env.DB, period: FIXTURE_PERIOD });

    expect(paymentProviderCalls).toEqual([]);
  });
});

describe("invoice_prices_through_credit_price_not_token_rate_artifact", () => {
  it("never calls src/pricing and prices invoice.total from quota_weight and credit_price", async () => {
    const priceUsageSpy = vi.spyOn(pricing, "priceUsage");
    const ledgerUsageSpy = vi.spyOn(pricing, "ledgerUsageFromProvider");
    const ratesForModelSpy = vi.spyOn(pricing, "ratesForModel");

    await seedInstallation();
    await seedEntitlement();
    await seedUsageRollup({
      quotaWeight: 50,
      tokens: 1_000_000,
      cost: 500,
    });
    await seedCreditPrice({
      version: "v2026-07",
      pricePerCredit: 0.1,
      activeFrom: "2026-07-01T00:00:00.000Z",
    });

    await runPeriodClose({ db: env.DB, period: FIXTURE_PERIOD });

    expect(priceUsageSpy).not.toHaveBeenCalled();
    expect(ledgerUsageSpy).not.toHaveBeenCalled();
    expect(ratesForModelSpy).not.toHaveBeenCalled();

    const invoice = await fetchInvoice();
    expect(invoice?.credits_consumed).toBe(50);
    expect(invoice?.total).toBe(5);
    expect(invoice?.credit_price_version).toBe("v2026-07");
  });
});
