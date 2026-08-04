import { describe, expect, it } from "vitest";
import {
  assertExactlyOneTerminal,
  CANONICAL_FIELD_MANIFEST,
  type CanonicalError,
  type CanonicalRequest,
  type CanonicalResult,
} from "../src/contracts/canonical";
import {
  ALL_TAXONOMY_CODES,
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

const RETRYABLE_CODES = ALL_TAXONOMY_CODES.filter((code) =>
  isRetrySafe(getTaxonomyEntry(code).retryable),
);

const TERMINAL_CODES = ALL_TAXONOMY_CODES.filter(
  (code) => !isRetrySafe(getTaxonomyEntry(code).retryable),
);

/** Literal pins — must fail if classifyFailure drifts from A2 retry-safety. */
const LITERAL_CLASSIFICATION_PINS: ReadonlyArray<{
  code: TaxonomyCode;
  expected: "retryable" | "terminal";
}> = [
  { code: "provider_rejected", expected: "terminal" },
  { code: "timeout", expected: "retryable" },
  { code: "cancelled", expected: "terminal" },
  { code: "rate_limited", expected: "retryable" },
  { code: "internal_error", expected: "retryable" },
  { code: "validation_failed", expected: "retryable" },
];

const CREDENTIAL_FIELD_PATTERN =
  /credential|api[_-]?key|secret|token|password|authorization|bearer/i;

const RETRY_FALLBACK_NAME_PATTERN =
  /(^|_)(retry|fallback|shouldRetry|maxRetries|withRetry|executeRetry|retryAttempt|withFallback|executeFallback|fallbackTo)(_|$)/i;

const PROVIDER_MODULES = [
  "../src/provider/port",
  "../src/provider/fake",
  "../src/provider/classify",
  "../src/provider/deepseek",
  "../src/provider/gemini",
  "../src/provider/wiring",
] as const;

/** Minimal §5.3 canonical request — every manifest field present, values kept small. */
const requestFixture: CanonicalRequest = {
  parts: [
    { role: "user", content: "Summarise the visit." },
  ],
  formatDirective: { type: "text" },
  samplingConstraints: { temperature: 0.2 },
  maxOutputTokens: 256,
  stopConditions: [],
  toolDeclarations: [],
  stream: false,
  deadline: 30_000,
  correlationIds: {
    request_reference: "7QK4-2B9F",
    trace_id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
  },
};

function createFakeAdapter(scriptedOutcomes: ScriptedOutcome[]): FakeAdapter {
  return new FakeAdapter(scriptedOutcomes);
}

async function invokeThroughPort(
  port: ProviderPort,
  request: CanonicalRequest,
): Promise<ProviderInvokeResult> {
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
    diagnostics.push(outcome.error.providerNative);
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

function collectOwnPropertyNames(value: unknown): string[] {
  if (value === null || value === undefined) {
    return [];
  }
  if (typeof value === "function") {
    const names = [
      ...Object.getOwnPropertyNames(value),
      ...Object.getOwnPropertyNames(value.prototype ?? {}),
    ];
    return names.filter((name) => name !== "constructor" && name !== "length" && name !== "name" && name !== "prototype");
  }
  if (typeof value === "object") {
    return Object.getOwnPropertyNames(value);
  }
  return [];
}

function assertNoRetryOrFallbackNames(
  names: readonly string[],
  surface: string,
): void {
  for (const name of names) {
    expect(
      name,
      `${surface} member ${name} must not be a retry/fallback policy API`,
    ).not.toMatch(RETRY_FALLBACK_NAME_PATTERN);
  }
}

function assertModuleHasNoRetryFallbackOrLoggingPolicy(
  moduleNamespace: Record<string, unknown>,
  modulePath: string,
): void {
  assertNoRetryOrFallbackNames(Object.keys(moduleNamespace), `${modulePath} exports`);

  for (const [exportName, exported] of Object.entries(moduleNamespace)) {
    assertNoRetryOrFallbackNames(
      collectOwnPropertyNames(exported),
      `${modulePath}.${exportName}`,
    );

    if (typeof exported === "function" && exported.prototype) {
      const proto = exported.prototype as Record<string, unknown>;
      expect(
        Object.prototype.hasOwnProperty.call(proto, "logger") ||
          Object.prototype.hasOwnProperty.call(proto, "journal"),
        `${modulePath}.${exportName} must not own logger/journal on the prototype`,
      ).toBe(false);
    }
  }

  expect(
    Object.keys(moduleNamespace).some((name) =>
      /^(LoggerSink|JournalSink)$/i.test(name),
    ),
    `${modulePath} must not export LoggerSink/JournalSink (adapters own no logging policy)`,
  ).toBe(false);
}

describe("T-D2-01 fake_success", () => {
  it("returns a canonical result when scripted for success", async () => {
    const adapter = createFakeAdapter(["success"]);
    const outcome = await invokeThroughPort(adapter, requestFixture);

    expect(outcome.kind).toBe("success");
    if (outcome.kind !== "success") {
      throw new Error("Expected success outcome");
    }
    assertCanonicalResultShape(outcome.result);
    expect(outcome.result.finishReason).toBeTruthy();
    expect(outcome.result.finalContent).toBeTruthy();
    assertExactlyOneTerminal(outcome.chunks);
  });
});

describe("T-D2-02 fake_retryable_<class>", () => {
  it.each(RETRYABLE_CODES)(
    "retryable:%s yields a canonical error classified retryable",
    async (code) => {
      const adapter = createFakeAdapter([`retryable:${code}`]);
      const outcome = await invokeThroughPort(adapter, requestFixture);

      expect(outcome.kind).toBe("error");
      if (outcome.kind !== "error") {
        throw new Error("Expected error outcome");
      }
      assertCanonicalErrorShape(outcome.error);
      expect(outcome.error.taxonomyCode).toBe(code);
      expect(outcome.error.retryability).toBe(true);
    },
  );
});

describe("T-D2-03 fake_terminal_<class>", () => {
  it.each(TERMINAL_CODES)(
    "terminal:%s yields a canonical error classified terminal",
    async (code) => {
      const adapter = createFakeAdapter([`terminal:${code}`]);
      const outcome = await invokeThroughPort(adapter, requestFixture);

      expect(outcome.kind).toBe("error");
      if (outcome.kind !== "error") {
        throw new Error("Expected error outcome");
      }
      assertCanonicalErrorShape(outcome.error);
      expect(outcome.error.taxonomyCode).toBe(code);
      expect(outcome.error.retryability).toBe(false);
    },
  );
});

describe("T-D2-04 fake_truncation", () => {
  it("normalizes a scripted truncation outcome through the port", async () => {
    const adapter = createFakeAdapter(["truncation"]);
    const outcome = await invokeThroughPort(adapter, requestFixture);

    expect(outcome.kind).toBe("truncation");
    if (outcome.kind !== "truncation") {
      throw new Error("Expected truncation outcome");
    }
    assertCanonicalResultShape(outcome.result);
    expect(outcome.result.finishReason).toBe("length");
    assertExactlyOneTerminal(outcome.chunks);
  });
});

describe("T-D2-05 fake_malformed", () => {
  it("normalizes a scripted malformed outcome through the port", async () => {
    const adapter = createFakeAdapter(["malformed"]);
    const outcome = await invokeThroughPort(adapter, requestFixture);

    expect(outcome.kind).toBe("malformed");
    if (outcome.kind !== "malformed") {
      throw new Error("Expected malformed outcome");
    }
    assertCanonicalErrorShape(outcome.error);
    expect(ALL_TAXONOMY_CODES).toContain(outcome.error.taxonomyCode);
  });
});

describe("T-D2-R1 fake_empty_queue_and_invalid_code_are_classified", () => {
  it("returns classified internal_error when the outcome queue is empty — never throws", async () => {
    const adapter = createFakeAdapter([]);
    await expect(
      invokeThroughPort(adapter, requestFixture),
    ).resolves.toMatchObject({
      kind: "error",
      error: expect.objectContaining({ taxonomyCode: "internal_error" }),
    });
  });

  it("classifies an invalid prefixed taxonomy code as internal_error", async () => {
    const adapter = createFakeAdapter([
      "retryable:bogus_not_a_code" as ScriptedOutcome,
    ]);
    const outcome = await invokeThroughPort(adapter, requestFixture);
    expect(outcome.kind).toBe("error");
    if (outcome.kind !== "error") {
      throw new Error("Expected error outcome");
    }
    expect(outcome.error.taxonomyCode).toBe("internal_error");
  });
});

describe("T-D2-06 classification_exhaustive_over_taxonomy", () => {
  it("enumerates A2's exported taxonomy list and pins literal code→class mappings", () => {
    const classifications = new Map<TaxonomyCode, "retryable" | "terminal">();

    expect(ALL_TAXONOMY_CODES.length).toBeGreaterThan(0);

    for (const code of ALL_TAXONOMY_CODES) {
      const classification = classifyFailure(code);

      expect(
        classification === "retryable" || classification === "terminal",
      ).toBe(true);
      expect(classifications.has(code)).toBe(false);
      classifications.set(code, classification);
    }

    expect(classifications.size).toBe(ALL_TAXONOMY_CODES.length);

    for (const { code, expected } of LITERAL_CLASSIFICATION_PINS) {
      expect(classifyFailure(code)).toBe(expected);
    }
  });
});

describe("T-D2-18 adapters_own_no_retry_or_fallback", () => {
  it("every provider module export and prototype surface excludes retry/fallback/logging policy", async () => {
    for (const modulePath of PROVIDER_MODULES) {
      const moduleNamespace = (await import(modulePath)) as Record<
        string,
        unknown
      >;
      assertModuleHasNoRetryFallbackOrLoggingPolicy(
        moduleNamespace,
        modulePath,
      );
    }

    const fakeProto = FakeAdapter.prototype as unknown as Record<
      string,
      unknown
    >;
    assertNoRetryOrFallbackNames(
      Object.getOwnPropertyNames(fakeProto).filter(
        (name) => name !== "constructor",
      ),
      "FakeAdapter.prototype",
    );
  });
});

describe("T-D2-21 credentials_absent_from_fake_emissions", () => {
  it("returns no credential fields across success, error, truncation, and malformed outcomes", async () => {
    const scriptedOutcomes: ScriptedOutcome[] = [
      "success",
      `retryable:${RETRYABLE_CODES[0]}`,
      `terminal:${TERMINAL_CODES[0]}`,
      "truncation",
      "malformed",
    ];

    const adapter = createFakeAdapter(scriptedOutcomes);

    for (let index = 0; index < scriptedOutcomes.length; index += 1) {
      const outcome = await invokeThroughPort(adapter, requestFixture);
      for (const diagnostic of collectCredentialDiagnostics(outcome)) {
        assertNoCredentialFields(diagnostic, `invoke[${index}]`);
      }
    }
  });
});
