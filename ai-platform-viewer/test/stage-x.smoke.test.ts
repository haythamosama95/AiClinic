import { describe, expect, it } from "vitest";
import { STAGE_X_OPERATIONS } from "../src/catalog/stage-x.ts";
import type { JourneyOperationDefinition } from "../src/catalog/journey-types.ts";
import { sendJourneyRequest } from "../src/lib/journey-api.ts";
import type { HttpExchange } from "../src/types.ts";
import {
  assertHttpExchangeRaw,
  fetchHttpExchange,
  readOperatorBearer,
} from "./helpers/smoke-http.ts";

const EXPECTED_CRON_EXPRESSIONS = [
  "0 3 * * *",
  "0 4 * * *",
  "0 5 1 * *",
  "0 5 * * *",
] as const;

function cronQueryValue(expression: string): string {
  return expression.replace(/ /g, "+");
}

function findCronOperation(expression: string): JourneyOperationDefinition {
  const encoded = cronQueryValue(expression);
  const operation = STAGE_X_OPERATIONS.find(
    (candidate) =>
      candidate.path.includes("/cdn-cgi/handler/scheduled") &&
      (candidate.fields.some(
        (field) =>
          field.name === "cron" &&
          (field.defaultValue?.includes(encoded) ||
            field.defaultValue?.includes(expression.replace(/ /g, " "))),
      ) ||
        candidate.title.toLowerCase().includes(expression.replace(/\*/g, "").trim())),
  );
  if (!operation) {
    throw new Error(`Expected stage-X cron card for "${expression}"`);
  }
  return operation;
}

function findFailureJourneyOperation(
  pathFragment: string,
): JourneyOperationDefinition {
  const operation = STAGE_X_OPERATIONS.find((candidate) =>
    candidate.path.includes(pathFragment),
  );
  if (!operation) {
    throw new Error(`Expected stage-X failure-journey card for ${pathFragment}`);
  }
  return operation;
}

describe("stage_x_cron_operations_drivable", () => {
  it("stage_x_cron_operations_drivable", async () => {
    const operatorBearer = readOperatorBearer();

    for (const cron of EXPECTED_CRON_EXPRESSIONS) {
      const operation = findCronOperation(cron);
      const params: Record<string, string> = {
        cron: cronQueryValue(cron),
        format: "json",
      };

      let exchange: HttpExchange;
      if (operation.auth === "none" && operation.method === "GET") {
        exchange = await fetchHttpExchange(
          operation.method,
          `${operation.path}?cron=${params.cron}&format=${params.format}`,
        );
      } else {
        exchange = await sendJourneyRequest(
          operation,
          params,
          { operatorBearer, aat: "" },
        );
      }

      assertHttpExchangeRaw(exchange);
      expect(exchange.request.url).toContain("/cdn-cgi/handler/scheduled");
      expect(exchange.request.url).toContain(`cron=${cronQueryValue(cron)}`);
    }
  });
});

describe("stage_x_failure_journey_operations_drivable", () => {
  it("stage_x_failure_journey_operations_drivable", async () => {
    const operatorBearer = readOperatorBearer();
    const requestReference = "00000000-0000-4000-8000-000000000099";

    const pollOperation = findFailureJourneyOperation("/v1/requests/");
    const pollExchange = await sendJourneyRequest(
      pollOperation,
      { request_reference: requestReference },
      { operatorBearer, aat: "" },
    );
    assertHttpExchangeRaw(pollExchange);
    expect(pollExchange.request.url).toContain(requestReference);

    const lookupOperation = findFailureJourneyOperation(
      "/control/support/lookup",
    );
    const lookupExchange = await sendJourneyRequest(
      lookupOperation,
      { reference: requestReference },
      { operatorBearer, aat: "" },
    );
    assertHttpExchangeRaw(lookupExchange);
    expect(lookupExchange.request.url).toContain(
      `reference=${encodeURIComponent(requestReference)}`,
    );
  });
});
