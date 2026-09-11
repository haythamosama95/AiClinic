import { describe, expect, it } from "vitest";
import { COMMERCIAL_PLAN_OPERATIONS } from "../src/catalog/commercial-plans.ts";
import { COMMERCIAL_USAGE_OPERATIONS } from "../src/catalog/commercial-usage.ts";
import type { JourneyOperationDefinition } from "../src/catalog/journey-types.ts";
import { parseCreditGaugeFromUsage } from "../src/lib/credit-gauge.ts";
import { sendJourneyRequest } from "../src/lib/journey-api.ts";
import {
  fetchInvoiceDetailEvidence,
  listIssuedInvoices,
} from "../server/d1-inspect.ts";
import {
  assertHttpExchangeRaw,
  mintInstallationAat,
  readOperatorBearer,
} from "./helpers/smoke-http.ts";

const PLAN_BODY = {
  name: "v4-smoke-plan",
  credit_budget: 1000,
  request_quota: 500,
  max_cost_class: "standard",
  soft_threshold: 0.8,
  allowed_capabilities: ["clinic.visit_summary"],
  status: "active",
} as const;

const INVOICE_COLUMNS = [
  "installation_id",
  "period",
  "credits_consumed",
  "credit_price_version",
  "total",
  "status",
  "issued_at",
] as const;

function findPlanOperation(
  pathFragment: "/control/plans/create" | "/update" | "/delete",
): JourneyOperationDefinition {
  const operation = COMMERCIAL_PLAN_OPERATIONS.find((candidate) =>
    candidate.path.includes(pathFragment),
  );
  if (!operation) {
    throw new Error(`Expected commercial plan operation for ${pathFragment}`);
  }
  return operation;
}

function planParams(
  operation: JourneyOperationDefinition,
): Record<string, string> {
  return {
    name: PLAN_BODY.name,
    credit_budget: String(PLAN_BODY.credit_budget),
    request_quota: String(PLAN_BODY.request_quota),
    max_cost_class: PLAN_BODY.max_cost_class,
    soft_threshold: String(PLAN_BODY.soft_threshold),
    allowed_capabilities: JSON.stringify(PLAN_BODY.allowed_capabilities),
    status: PLAN_BODY.status,
  };
}

function findUsageOperation(): JourneyOperationDefinition {
  const operation = COMMERCIAL_USAGE_OPERATIONS.find(
    (candidate) => candidate.path === "/v1/usage",
  );
  if (!operation) {
    throw new Error("Expected GET /v1/usage commercial usage card");
  }
  return operation;
}

function parseInvoiceRows(rawBody: string): Array<Record<string, unknown>> {
  const payload = JSON.parse(rawBody) as unknown;
  if (Array.isArray(payload)) {
    return payload as Array<Record<string, unknown>>;
  }
  if (
    payload &&
    typeof payload === "object" &&
    Array.isArray((payload as { rows?: unknown[] }).rows)
  ) {
    return (payload as { rows: Array<Record<string, unknown>> }).rows;
  }
  throw new Error("Invoice list response must be JSON rows");
}

function forbiddenGaugeKeys(model: Record<string, unknown>): string[] {
  return Object.keys(model).filter((key) =>
    /token|cost|price/i.test(key),
  );
}

describe("plan_catalogue_crud_drives_g1_control_mutations", () => {
  it("plan_catalogue_crud_drives_g1_control_mutations", async () => {
    const operatorBearer = readOperatorBearer();
    expect(operatorBearer.length).toBeGreaterThan(0);

    const createOperation = findPlanOperation("/control/plans/create");
    const createExchange = await sendJourneyRequest(
      createOperation,
      planParams(createOperation),
      { operatorBearer, aat: "" },
    );
    assertHttpExchangeRaw(createExchange);
    expect(createExchange.request.url).toContain("/control/plans/create");
    expect(createExchange.request.raw).toContain('"name"');
    expect(createExchange.request.raw).toContain('"credit_budget"');

    const unauthorizedExchange = await sendJourneyRequest(
      createOperation,
      planParams(createOperation),
      { operatorBearer: "", aat: "" },
    );
    assertHttpExchangeRaw(unauthorizedExchange);
    expect(unauthorizedExchange.response.status).toBe(401);
    expect(unauthorizedExchange.response.rawBody).toBe(
      '{"error":"unauthorized"}',
    );

    const updateOperation = findPlanOperation("/update");
    const updateExchange = await sendJourneyRequest(
      updateOperation,
      planParams(updateOperation),
      { operatorBearer, aat: "" },
    );
    assertHttpExchangeRaw(updateExchange);
    expect(updateExchange.request.url).toContain(
      `/control/plans/${PLAN_BODY.name}/update`,
    );

    const deleteOperation = findPlanOperation("/delete");
    const deleteExchange = await sendJourneyRequest(
      deleteOperation,
      planParams(deleteOperation),
      { operatorBearer, aat: "" },
    );
    assertHttpExchangeRaw(deleteExchange);
    expect(deleteExchange.request.url).toContain(
      `/control/plans/${PLAN_BODY.name}/delete`,
    );
  });
});

describe("credit_gauge_renders_g3_consumed_versus_budget", () => {
  it("credit_gauge_renders_g3_consumed_versus_budget", async () => {
    const operatorBearer = readOperatorBearer();
    const aat = await mintInstallationAat();
    const usageOperation = findUsageOperation();

    expect(
      COMMERCIAL_USAGE_OPERATIONS.some((candidate) =>
        candidate.path.includes("/control/installations/"),
      ),
    ).toBe(false);

    const exchange = await sendJourneyRequest(
      usageOperation,
      {},
      { operatorBearer, aat },
    );
    assertHttpExchangeRaw(exchange);
    expect(exchange.request.url).toContain("/v1/usage");

    const usagePayload = JSON.parse(exchange.response.rawBody) as {
      current_period?: {
        credits_used?: number;
        credit_budget?: number;
      };
    };
    expect(usagePayload.current_period?.credits_used).toBeTypeOf("number");
    expect(usagePayload.current_period?.credit_budget).toBeTypeOf("number");

    const gaugeModel = parseCreditGaugeFromUsage(usagePayload);
    expect(gaugeModel.credits_used).toBeTypeOf("number");
    expect(gaugeModel.credit_budget).toBeTypeOf("number");
    expect(forbiddenGaugeKeys(gaugeModel)).toEqual([]);
  });
});

describe("invoice_list_renders_g4_invoices", () => {
  it("invoice_list_renders_g4_invoices", async () => {
    const exchange = await listIssuedInvoices();
    assertHttpExchangeRaw(exchange);
    expect(exchange.request.raw.toLowerCase()).toContain("select");
    expect(exchange.request.raw.toLowerCase()).toContain("invoice");

    const rows = parseInvoiceRows(exchange.response.rawBody);
    for (const row of rows) {
      for (const column of INVOICE_COLUMNS) {
        expect(row).toHaveProperty(column);
      }
    }
  });
});

describe("invoice_detail_renders_g4_rollup_evidence", () => {
  it("invoice_detail_renders_g4_rollup_evidence", async () => {
    const listExchange = await listIssuedInvoices();
    const rows = parseInvoiceRows(listExchange.response.rawBody);
    expect(rows.length).toBeGreaterThan(0);

    const first = rows[0]!;
    const installationId = String(first.installation_id);
    const period = String(first.period);

    const detailExchange = await fetchInvoiceDetailEvidence(
      installationId,
      period,
    );
    assertHttpExchangeRaw(detailExchange);
    expect(detailExchange.request.raw.toLowerCase()).toContain("usage_rollup");
    expect(detailExchange.request.raw.toLowerCase()).toContain(
      "request_reference",
    );

    const detailPayload = JSON.parse(detailExchange.response.rawBody) as {
      rollup_lines?: unknown[];
      traces?: Array<{ request_id?: string; request_reference?: string }>;
    };

    expect(Array.isArray(detailPayload.rollup_lines)).toBe(true);
    expect((detailPayload.rollup_lines ?? []).length).toBeGreaterThan(0);
    expect(
      (detailPayload.traces ?? []).some(
        (trace) => trace.request_id && trace.request_reference,
      ),
    ).toBe(true);
  });
});
