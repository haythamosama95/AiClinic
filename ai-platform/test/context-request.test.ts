import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
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
  it("does not add a conversational pipeline stage module under src/", () => {
    const srcRoot = join(__dirname, "../src");
    const forbiddenPaths = [
      "pipeline/conversational.ts",
      "pipeline/context-request-stage.ts",
      "stages/conversational.ts",
      "conversation/stage.ts",
    ];
    for (const rel of forbiddenPaths) {
      expect(() => readFileSync(join(srcRoot, rel), "utf8")).toThrow();
    }

    // H1's context-request module is a schema helper, not a §6.1 stage.
    const contextRequestSource = readFileSync(
      join(srcRoot, "context/context-request.ts"),
      "utf8",
    );
    expect(contextRequestSource).not.toMatch(/runStage|pipelineStage|stage\s*\d+/i);
  });
});

describe("no_per_request_server_state_from_h1", () => {
  it("introduces no conversation table migration or extra Durable Object binding", () => {
    const migrationsDir = join(__dirname, "../migrations");
    for (const name of readdirSync(migrationsDir)) {
      if (!name.endsWith(".sql")) continue;
      const sql = readFileSync(join(migrationsDir, name), "utf8").toLowerCase();
      expect(sql).not.toMatch(/create\s+table\s+[`"]?ai_conversation\b/);
      expect(sql).not.toMatch(/create\s+table\s+[`"]?conversation_session\b/);
      expect(sql).not.toMatch(/create\s+table\s+[`"]?conversation_store\b/);
    }

    const wrangler = readFileSync(join(__dirname, "../wrangler.toml"), "utf8");
    expect(wrangler).toMatch(/class_name\s*=\s*"GatewayObject"/);
    expect(wrangler).not.toMatch(
      /class_name\s*=\s*"(ConversationObject|SessionObject|ChatObject)"/,
    );
  });
});
