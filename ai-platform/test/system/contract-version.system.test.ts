/**
 * P2.1 — clinic route contract version (E2E-P2.1-04–E2E-P2.1-06).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_VERSION,
  count,
  newClinic,
  GATEWAY_ORIGIN,
  mintAat,
  newScenario,
  parseSseEvents,
  registerVisitSummaryCapability,
  resetPlatformState,
  setupPromotedFakePolicy,
  visitSummaryInvokeBody,
} from "./harness";

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
});

describe("contract version", () => {
  it("E2E-P2.1-04 — POST /v1/requests without Aip-Contract-Version is refused before write", async () => {
    const before = await count("ai_request");

    const response = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
        method: "POST",
        headers: {
          authorization: "Bearer invalid-token",
          "content-type": "application/json",
          "x-idempotency-key": crypto.randomUUID(),
          "x-capability-version": CAPABILITY_VERSION,
        },
        body: JSON.stringify({ capability_id: "clinic.visit_summary" }),
      }),
    );

    expect(response.status).toBe(400);
    const json = (await response.json()) as Record<string, unknown>;
    expect(json.code).toBe("contract_version_unsupported");
    expect(json.accepted_versions).toEqual([0, 1]);
    expect(await count("ai_request")).toBe(before);
  });

  it("E2E-P2.1-05 — GET /v1/capabilities echoes version 1 and refuses version 2", async () => {
    const scenario = await newScenario();
    await newClinic(scenario);
    const token = await mintAat(scenario);

    const ok = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, {
        headers: {
          authorization: `Bearer ${token}`,
          "Aip-Contract-Version": "1",
        },
      }),
    );
    expect(ok.status).toBe(200);
    expect(ok.headers.get("Aip-Contract-Version")).toBe("1");

    const refused = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, {
        headers: { "Aip-Contract-Version": "2" },
      }),
    );
    expect(refused.status).toBe(400);
    const json = (await refused.json()) as Record<string, unknown>;
    expect(json.code).toBe("contract_version_unsupported");
  });

  it("E2E-P2.1-06 — streamed POST echoes Aip-Contract-Version before SSE body", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario);

    const response = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
          "x-idempotency-key": crypto.randomUUID(),
          "x-capability-version": CAPABILITY_VERSION,
          "Aip-Contract-Version": "1",
        },
        body: JSON.stringify(visitSummaryInvokeBody(scenario)),
      }),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("Aip-Contract-Version")).toBe("1");
    expect(response.headers.get("content-type") ?? "").toContain(
      "text/event-stream",
    );

    const events = await parseSseEvents(response);
    expect(events[0]?.event).toBe("accepted");
  });
});
