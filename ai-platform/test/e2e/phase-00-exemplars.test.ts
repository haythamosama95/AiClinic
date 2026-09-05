import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertRequestReferenceShape,
  assertSseSequence,
  assertTaxonomyBody,
  assertUlidShape,
  bootstrapE2e,
  controlFetch,
  enrollPayload,
  newScenario,
  postRequest,
  provisionHappyPath,
  resetE2eState,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

describe("Phase 0 harness exemplars", () => {
  it("P00-001 — control-plane 401 unauthorized", async () => {
    const scenario = await newScenario();
    const result = await controlFetch(
      `/control/installations/${scenario.installationId}/enroll`,
      {
        auth: "none",
        body: enrollPayload(scenario),
      },
    );

    expect(result.status).toBe(401);
    expect(result.headers.get("content-type")).toContain("application/json");
    expect(result.json).toEqual({ error: "unauthorized" });
  });

  it("P00-002 — guard rejection full taxonomy body", async () => {
    const scenario = await newScenario();
    const result = await postRequest(scenario, { token: null });

    expect(result.status).toBe(401);
    assertTaxonomyBody(result.body, {
      code: "unauthenticated",
      retry_safe: true,
    });
    assertRequestReferenceShape(String(result.body.request_reference));
    assertUlidShape(String(result.body.trace_id));
    expect(result.body.request_reference).not.toBe("");
    expect(result.body.trace_id).not.toBe("");
  });

  it("P00-003 — happy-path SSE accepted", async () => {
    const scenario = await provisionHappyPath();
    const result = await postRequest(scenario);

    expect(result.status).toBe(200);
    expect(result.headers.get("content-type")).toContain("text/event-stream");
    assertSseSequence(result.events, ["accepted"]);
    const accepted = result.events[0];
    expect(accepted?.data.request_reference).toEqual(
      expect.stringMatching(/^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/),
    );
    expect(typeof accepted?.data.trace_id).toBe("string");
    expect(String(accepted?.data.trace_id).length).toBeGreaterThan(0);
  });
});
