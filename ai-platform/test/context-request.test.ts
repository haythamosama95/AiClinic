import { describe, expect, it } from "vitest";
import {
  CONTEXT_REQUEST_SCHEMA_ID,
  validateContextRequest,
  type ContextRequest,
} from "../src/context/context-request";

function conformingContextRequest(): ContextRequest {
  return [
    {
      key: "visit.chief_complaint@v1",
      arguments: { visit_id: "550e8400-e29b-41d4-a716-446655440000" },
    },
    { key: "patient.demographics@v1", arguments: {} },
  ];
}

describe("shared_context_request_schema_accepts_conforming", () => {
  it("validates a well-formed list of {key, arguments}", () => {
    const request = conformingContextRequest();
    const result = validateContextRequest(request);
    expect(result.ok).toBe(true);
  });
});

describe("shared_context_request_schema_rejects_malformed_<form>", () => {
  it("rejects a root that is not a list", () => {
    const result = validateContextRequest({
      key: "visit.chief_complaint@v1",
      arguments: {},
    });
    expect(result.ok).toBe(false);
  });

  it("rejects an element missing key", () => {
    const result = validateContextRequest([{ arguments: {} }]);
    expect(result.ok).toBe(false);
  });

  it("rejects an element missing arguments", () => {
    const result = validateContextRequest([
      { key: "visit.chief_complaint@v1" },
    ]);
    expect(result.ok).toBe(false);
  });

  it("rejects an element that is not a {key, arguments} object", () => {
    const result = validateContextRequest(["visit.chief_complaint@v1"]);
    expect(result.ok).toBe(false);
  });
});

describe("context_request_schema_is_platform_owned_not_per_capability", () => {
  it("shares one platform-owned schema id and rejects per-capability alternate shapes", () => {
    expect(CONTEXT_REQUEST_SCHEMA_ID).toBe("platform.context_request@v1");

    const alternateShape = {
      capabilityId: "clinic.chat@v1",
      requests: conformingContextRequest(),
    };
    const result = validateContextRequest(alternateShape);
    expect(result.ok).toBe(false);

    expect(typeof validateContextRequest).toBe("function");
    expect(
      (validateContextRequest as { capabilityId?: unknown }).capabilityId,
    ).toBeUndefined();
  });
});

describe("no_new_pipeline_stage_from_conversational_mode", () => {
  it("does not introduce a new §6.1 pipeline stage export surface", async () => {
    const contextRequestModule = await import("../src/context/context-request");
    const exportNames = Object.keys(contextRequestModule);

    for (const name of exportNames) {
      const lowered = name.toLowerCase();
      expect(lowered).not.toMatch(/pipeline/);
      expect(lowered).not.toMatch(/stage/);
      expect(lowered).not.toMatch(/handler/);
    }

    expect(exportNames).not.toContain("createPipelineStage");
    expect(exportNames).not.toContain("registerStage");
  });
});

describe("no_per_request_server_state_from_h1", () => {
  it("introduces no conversation table or per-request durable/session store exports", async () => {
    const contextRequestModule = await import("../src/context/context-request");

    for (const exportName of Object.keys(contextRequestModule)) {
      const lowered = exportName.toLowerCase();
      expect(lowered).not.toMatch(/conversationtable/);
      expect(lowered).not.toMatch(/sessionstore/);
      expect(lowered).not.toMatch(/durableobject/);
      expect(lowered).not.toMatch(/requeststate/);
    }
  });
});
