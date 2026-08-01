import { describe, expect, it } from "vitest";
import {
  CANONICAL_FIELD_MANIFEST,
  type CanonicalError,
  type CanonicalRequest,
  type CanonicalResult,
} from "../src/contracts/canonical";
import {
  getTaxonomyEntry,
  isRetrySafe,
  type TaxonomyCode,
} from "../src/errors";
import { classifyFailure } from "../src/provider/classify";
import { FakeAdapter } from "../src/provider/fake";
import {
  type ProviderInvokeResult,
  type ProviderPort,
  type ScriptedOutcome,
} from "../src/provider/port";

const TAXONOMY_CODES: TaxonomyCode[] = [
  "unauthenticated",
  "installation_suspended",
  "forbidden_capability",
  "rate_limited",
  "quota_exhausted",
  "request_too_large",
  "context_required",
  "context_invalid",
  "conversation_budget_exhausted",
  "capability_unknown",
  "capability_retired",
  "capability_disabled",
  "provider_unavailable",
  "provider_rejected",
  "validation_failed",
  "cancelled",
  "timeout",
  "internal_error",
];

const RETRYABLE_CODES = TAXONOMY_CODES.filter((code) =>
  isRetrySafe(getTaxonomyEntry(code).retryable),
);

const TERMINAL_CODES = TAXONOMY_CODES.filter(
  (code) => !isRetrySafe(getTaxonomyEntry(code).retryable),
);

const CREDENTIAL_FIELD_PATTERN =
  /credential|api[_-]?key|secret|token|password|authorization|bearer/i;

const RETRY_FALLBACK_API_PATTERN =
  /^(retry|withRetry|executeRetry|retryAttempt|fallback|withFallback|executeFallback|fallbackTo)/i;

/** Minimal §5.3 canonical request — every manifest field present, values kept small. */
const requestFixture: CanonicalRequest = {
  "ordered role-tagged message parts": [
    { role: "user", content: "Summarise the visit." },
  ],
  "output format directive": { type: "text" },
  "sampling constraints": { temperature: 0.2 },
  "max output tokens": 256,
  "stop conditions": [],
  "tool/function declarations (reserved for future)": [],
  "stream flag": false,
  deadline: 30_000,
  "correlation ids": {
    request_reference: "7QK4-2B9F",
    trace_id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
  },
};

function createFakeAdapter(scriptedOutcomes: ScriptedOutcome[]): FakeAdapter {
  return new FakeAdapter(scriptedOutcomes);
}

function invokeThroughPort(
  port: ProviderPort,
  request: CanonicalRequest,
): ProviderInvokeResult {
  return port.invoke(request);
}

function assertCanonicalResultShape(result: CanonicalResult): void {
  for (const key of CANONICAL_FIELD_MANIFEST.result) {
    expect(result).toHaveProperty(key);
  }
}

function assertCanonicalErrorShape(error: CanonicalError): void {
  for (const key of CANONICAL_FIELD_MANIFEST.error) {
    expect(error).toHaveProperty(key);
  }
}

function collectCredentialDiagnostics(
  outcome: ProviderInvokeResult,
): unknown[] {
  const diagnostics: unknown[] = [outcome];

  if (outcome.kind === "success" || outcome.kind === "truncation") {
    diagnostics.push(outcome.result);
  }

  if (outcome.kind === "error" || outcome.kind === "malformed") {
    diagnostics.push(outcome.error);
    diagnostics.push(outcome.error["provider-native code and message"]);
  }

  return diagnostics;
}

function assertNoCredentialFields(value: unknown, path = "root"): void {
  if (value === null || value === undefined) {
    return;
  }

  if (Array.isArray(value)) {
    for (const [index, item] of value.entries()) {
      assertNoCredentialFields(item, `${path}[${index}]`);
    }
    return;
  }

  if (typeof value === "object") {
    for (const [key, nested] of Object.entries(
      value as Record<string, unknown>,
    )) {
      expect(
        key,
        `credential-like field at ${path}.${key}`,
      ).not.toMatch(CREDENTIAL_FIELD_PATTERN);
      assertNoCredentialFields(nested, `${path}.${key}`);
    }
  }
}

function assertNoRetryOrFallbackApi(exportNames: readonly string[]): void {
  for (const name of exportNames) {
    expect(
      name,
      `export ${name} must not be a retry/fallback policy API`,
    ).not.toMatch(RETRY_FALLBACK_API_PATTERN);
  }
}

describe("T-D2-01 fake_success", () => {
  it("returns a canonical result when scripted for success", () => {
    const adapter = createFakeAdapter(["success"]);
    const outcome = invokeThroughPort(adapter, requestFixture);

    expect(outcome.kind).toBe("success");
    assertCanonicalResultShape(outcome.result);
    expect(outcome.result["finish reason"]).toBeTruthy();
    expect(outcome.result["final content"]).toBeTruthy();
  });
});

describe("T-D2-02 fake_retryable_<class>", () => {
  it.each(RETRYABLE_CODES)(
    "retryable:%s yields a canonical error classified retryable",
    (code) => {
      const adapter = createFakeAdapter([`retryable:${code}`]);
      const outcome = invokeThroughPort(adapter, requestFixture);

      expect(outcome.kind).toBe("error");
      assertCanonicalErrorShape(outcome.error);
      expect(outcome.error["taxonomy code"]).toBe(code);
      expect(outcome.error.retryability).toBe(true);
    },
  );
});

describe("T-D2-03 fake_terminal_<class>", () => {
  it.each(TERMINAL_CODES)(
    "terminal:%s yields a canonical error classified terminal",
    (code) => {
      const adapter = createFakeAdapter([`terminal:${code}`]);
      const outcome = invokeThroughPort(adapter, requestFixture);

      expect(outcome.kind).toBe("error");
      assertCanonicalErrorShape(outcome.error);
      expect(outcome.error["taxonomy code"]).toBe(code);
      expect(outcome.error.retryability).toBe(false);
    },
  );
});

describe("T-D2-04 fake_truncation", () => {
  it("normalizes a scripted truncation outcome through the port", () => {
    const adapter = createFakeAdapter(["truncation"]);
    const outcome = invokeThroughPort(adapter, requestFixture);

    expect(outcome.kind).toBe("truncation");
    assertCanonicalResultShape(outcome.result);
    expect(outcome.result["finish reason"]).toBe("length");
  });
});

describe("T-D2-05 fake_malformed", () => {
  it("normalizes a scripted malformed outcome through the port", () => {
    const adapter = createFakeAdapter(["malformed"]);
    const outcome = invokeThroughPort(adapter, requestFixture);

    expect(outcome.kind).toBe("malformed");
    assertCanonicalErrorShape(outcome.error);
    expect(TAXONOMY_CODES).toContain(outcome.error["taxonomy code"]);
  });
});

describe("T-D2-06 classification_exhaustive_over_taxonomy", () => {
  it("maps every taxonomy code to exactly one retryable or terminal class", () => {
    const classifications = new Map<TaxonomyCode, "retryable" | "terminal">();

    for (const code of TAXONOMY_CODES) {
      const classification = classifyFailure(code);

      expect(
        classification === "retryable" || classification === "terminal",
      ).toBe(true);
      expect(classifications.has(code)).toBe(false);
      classifications.set(code, classification);

      const expectedRetryable = isRetrySafe(
        getTaxonomyEntry(code).retryable,
      );
      expect(classification === "retryable").toBe(expectedRetryable);
      expect(classification === "terminal").toBe(!expectedRetryable);
    }

    expect(classifications.size).toBe(TAXONOMY_CODES.length);
  });
});

describe("T-D2-18 adapters_own_no_retry_or_fallback", () => {
  it("provider-port and fake export surfaces expose no retry or fallback API", async () => {
    const portModule = await import("../src/provider/port");
    const fakeModule = await import("../src/provider/fake");

    assertNoRetryOrFallbackApi(Object.keys(portModule));
    assertNoRetryOrFallbackApi(Object.keys(fakeModule));
  });
});

describe("T-D2-21 credentials_absent_from_fake_emissions", () => {
  it("returns no credential fields across success, error, truncation, and malformed outcomes", () => {
    const scriptedOutcomes: ScriptedOutcome[] = [
      "success",
      `retryable:${RETRYABLE_CODES[0]}`,
      `terminal:${TERMINAL_CODES[0]}`,
      "truncation",
      "malformed",
    ];

    const adapter = createFakeAdapter(scriptedOutcomes);

    for (let index = 0; index < scriptedOutcomes.length; index += 1) {
      const outcome = invokeThroughPort(adapter, requestFixture);
      for (const diagnostic of collectCredentialDiagnostics(outcome)) {
        assertNoCredentialFields(diagnostic, `invoke[${index}]`);
      }
    }
  });
});
