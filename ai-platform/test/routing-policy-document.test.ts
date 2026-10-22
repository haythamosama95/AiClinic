import { describe, expect, it } from "vitest";
import { parseRoutingPolicyDocument } from "../src/router/policy-document";

function minimalDocument(): Record<string, unknown> {
  return {
    schema_version: 1,
    policy_id: "policy-main",
    policy_version: 1,
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules: [
      {
        rule_id: "catch-all",
        requires: { structured_output: false, min_context_window: 0, languages: [] },
        targets: [
          {
            provider_id: "provider-a",
            model_id: "model-a",
            features: {
              structured_output: false,
              min_context_window: 8000,
              languages: ["en"],
              latency_class: "standard",
              cost_class: "standard",
            },
            max_attempts: 2,
            timeout_ms: 30000,
          },
        ],
      },
    ],
    overrides: [],
  };
}

describe("routing policy document parser", () => {
  it("R8-ROUTE1: rejects identity-only documents", () => {
    const result = parseRoutingPolicyDocument({
      policy_id: "policy-main",
      policy_version: 1,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("invalid_policy_document");
    }
  });

  it("R8-ROUTE1: rejects unsupported schema_version", () => {
    const result = parseRoutingPolicyDocument({ ...minimalDocument(), schema_version: 2 });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("invalid_policy_document");
      expect(result.reason).toContain("schema_version");
    }
  });

  it("R8-ROUTE1: rejects a document with missing rules", () => {
    const document = minimalDocument();
    delete document.rules;
    const result = parseRoutingPolicyDocument(document);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("invalid_policy_document");
      expect(result.reason).toContain("rules");
    }
  });

  it("R8-ROUTE1: rejects a document whose last rule is not a catch-all", () => {
    const document = minimalDocument();
    const rules = document.rules as Array<Record<string, unknown>>;
    rules[0] = { ...rules[0], match: { tiers: ["degraded"] } };
    const result = parseRoutingPolicyDocument(document);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("invalid_policy_document");
      expect(result.reason).toContain("catch-all");
    }
  });

  it("R8-ROUTE1: accepts a minimal valid document", () => {
    const result = parseRoutingPolicyDocument(minimalDocument());
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.document.policy_id).toBe("policy-main");
      expect(result.document.policy_version).toBe(1);
      expect(result.document.rules).toHaveLength(1);
      expect(result.document.overrides).toEqual([]);
    }
  });
});
