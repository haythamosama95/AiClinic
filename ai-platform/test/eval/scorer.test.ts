import { describe, expect, it } from "vitest";
import type { CanonicalRequest } from "../../src/contracts/canonical";
import type { ProviderInvokeResult } from "../../src/provider/port";
import {
  scoreQuality,
  scoreSchema,
  type ExpectationDefinition,
} from "./harness";
import { deriveOverall } from "./score-report";

function requestWithSystem(systemText: string): CanonicalRequest {
  return {
    requestReference: "EVAL-REQ-SCORER",
    parts: [{ role: "system", content: systemText }],
    stream: false,
  } as CanonicalRequest;
}

function successOutcome(text: string): ProviderInvokeResult {
  return {
    kind: "success",
    result: {
      finalContent: { type: "text", text },
      usage: { input: 1, output: 1, cached: 0 },
      providerModel: { provider: "deepseek", model: "deepseek-v4-flash" },
      finishReason: "stop",
      providerRequestId: "scorer-1",
      timing: { queue_ms: 0, provider_ms: 1, total_ms: 1 },
    },
    chunks: [],
  };
}

describe("scorer_branch_coverage", () => {
  const baseExpectation: ExpectationDefinition = {
    case_id: "synthetic",
    system_instruction_must_contain: ["advisory only"],
    output_must_contain: ["headache"],
    output_min_length: 20,
    output_mode: "prose",
  };

  it("fails quality when system_instruction needle is missing", () => {
    expect(
      scoreQuality(
        requestWithSystem("unrelated system text"),
        "The patient has a headache and this is long enough.",
        baseExpectation,
      ),
    ).toBe("fail");
  });

  it("fails quality when output_must_contain needle is missing", () => {
    expect(
      scoreQuality(
        requestWithSystem("advisory only clinical documentation assistant"),
        "No matching clinical term appears in this sufficiently long text.",
        baseExpectation,
      ),
    ).toBe("fail");
  });

  it("fails quality when output_min_length is not met", () => {
    expect(
      scoreQuality(
        requestWithSystem("advisory only clinical documentation assistant"),
        "headache",
        baseExpectation,
      ),
    ).toBe("fail");
  });

  it("fails schema on non-success provider outcome", () => {
    const outcome: ProviderInvokeResult = {
      kind: "error",
      error: {
        code: "provider_rejected",
        retryable: false,
        message: "boom",
        taxonomy: "provider_rejected",
        detail: "boom",
      },
    };
    expect(scoreSchema(outcome, baseExpectation)).toBe("fail");
  });

  it("fails schema when canonical result fields are missing", () => {
    const outcome = {
      kind: "success",
      result: {
        finalContent: { type: "text", text: "headache advisory text here" },
      },
      chunks: [],
    } as unknown as ProviderInvokeResult;
    expect(scoreSchema(outcome, baseExpectation)).toBe("fail");
  });

  it("fails schema on empty prose content", () => {
    expect(scoreSchema(successOutcome("   "), baseExpectation)).toBe("fail");
  });

  it("fails schema on JSON-shaped prose", () => {
    expect(
      scoreSchema(successOutcome('{"summary":"headache"}'), baseExpectation),
    ).toBe("fail");
  });

  it("deriveOverall fails on schema alone and on empty case sets", () => {
    expect(
      deriveOverall([
        { case_id: "a", quality: "pass", schema: "fail" },
      ]),
    ).toBe("fail");
    expect(deriveOverall([])).toBe("fail");
  });

  it("passes quality and schema on a synthetic happy path", () => {
    const request = requestWithSystem(
      "advisory only clinical documentation assistant",
    );
    const content =
      "The patient presents with headache; advisory summary for review.";
    expect(scoreQuality(request, content, baseExpectation)).toBe("pass");
    expect(scoreSchema(successOutcome(content), baseExpectation)).toBe("pass");
  });

  it("fails quality for insufficient-context needles when output omits what is missing", () => {
    const expectation: ExpectationDefinition = {
      case_id: "visit_summary.insufficient_context",
      system_instruction_must_contain: ["state what is missing"],
      output_must_contain: ["insufficient", "missing"],
      output_min_length: 40,
      output_mode: "prose",
    };
    expect(
      scoreQuality(
        requestWithSystem("state what is missing in advisory summaries"),
        "The patient presents with headache; advisory summary for review.",
        expectation,
      ),
    ).toBe("fail");
    expect(
      scoreQuality(
        requestWithSystem("state what is missing in advisory summaries"),
        "Context is insufficient; what is missing is a concrete chief complaint.",
        expectation,
      ),
    ).toBe("pass");
  });
});
