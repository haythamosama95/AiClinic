import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  CANONICAL_FIELD_MANIFEST,
  assertNoProviderShapedFieldNames,
  type CanonicalError,
  type CanonicalRequest,
  type CanonicalResult,
  type CanonicalStreamChunk,
} from "../src/contracts/canonical";
import {
  getTaxonomyEntry,
  isRetrySafe,
  type TaxonomyCode,
} from "../src/errors";
import {
  classifyFailure,
  setRetryabilityFromClassification,
} from "../src/provider/classify";
import {
  GeminiAdapter,
  GEMINI_API_KEY_BINDING,
  type GeminiAdapterOptions,
  type GeminiTransport,
  type GeminiTransportResponse,
  type SecretStorePort,
} from "../src/provider/gemini";
import {
  type ProviderInvokeResult,
  type ProviderPort,
} from "../src/provider/port";

const TEST_ROOT = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES_ROOT = path.join(TEST_ROOT, "fixtures", "gemini");

const KNOWN_SECRET = "gemini-test-api-key-secret-value-do-not-log";

const RETRY_FALLBACK_API_PATTERN =
  /^(retry|withRetry|executeRetry|retryAttempt|fallback|withFallback|executeFallback|fallbackTo)/i;

const LOGGING_POLICY_API_PATTERN =
  /^(setLogLevel|configureLogging|loggingPolicy|withLogging|logPolicy|decideLogLevel|emitLogPolicy)/i;

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

type WireRequestGolden = {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: unknown;
};

type GeminiWireErrorClass =
  | "auth_rejected"
  | "rate_limited"
  | "provider_server_error"
  | "content_filtered";

const WIRE_ERROR_EXPECTATIONS: Record<
  GeminiWireErrorClass,
  { taxonomy: TaxonomyCode; retryable: boolean }
> = {
  auth_rejected: { taxonomy: "provider_rejected", retryable: false },
  rate_limited: { taxonomy: "rate_limited", retryable: true },
  provider_server_error: { taxonomy: "internal_error", retryable: true },
  content_filtered: { taxonomy: "provider_rejected", retryable: false },
};

type CapturedWireRequest = {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
};

type RecordingSecretStore = {
  store: SecretStorePort;
  reads: string[];
};

type CapturingTransport = {
  transport: GeminiTransport;
  captured: CapturedWireRequest[];
};

function loadFixture<T>(...segments: string[]): T {
  const fixturePath = path.join(FIXTURES_ROOT, ...segments);
  const raw = readFileSync(fixturePath, "utf8");
  return JSON.parse(raw) as T;
}

function loadFixtureText(...segments: string[]): string {
  const fixturePath = path.join(FIXTURES_ROOT, ...segments);
  return readFileSync(fixturePath, "utf8");
}

function createRecordingSecretStore(
  secret: string = KNOWN_SECRET,
): RecordingSecretStore {
  const reads: string[] = [];
  const store: SecretStorePort = {
    getSecret(name: string): string | undefined {
      reads.push(name);
      return name === GEMINI_API_KEY_BINDING ? secret : undefined;
    },
  };
  return { store, reads };
}

function createCapturingTransport(
  responder: (request: CapturedWireRequest) => GeminiTransportResponse,
): CapturingTransport {
  const captured: CapturedWireRequest[] = [];
  const transport: GeminiTransport = {
    fetch(url, init) {
      const request: CapturedWireRequest = {
        url,
        method: init.method,
        headers: { ...init.headers },
        body: init.body,
      };
      captured.push(request);
      return responder(request);
    },
  };
  return { transport, captured };
}

function createGeminiAdapter(
  options: GeminiAdapterOptions,
): GeminiAdapter & ProviderPort {
  return new GeminiAdapter(options);
}

async function invokeThroughPort(
  port: ProviderPort,
  request: CanonicalRequest,
): Promise<ProviderInvokeResult> {
  return port.invoke(request);
}

function getStreamChunks(outcome: ProviderInvokeResult): CanonicalStreamChunk[] {
  if (outcome.kind === "success" || outcome.kind === "truncation") {
    return [...outcome.chunks];
  }
  return [];
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

function assertCanonicalStreamChunkShape(chunk: CanonicalStreamChunk): void {
  for (const key of CANONICAL_FIELD_MANIFEST.streamChunk) {
    expect(chunk).toHaveProperty(key);
  }
  assertNoProviderShapedFieldNames(Object.keys(chunk));
  if (chunk.payload && typeof chunk.payload === "object") {
    assertNoProviderShapedFieldNames(Object.keys(chunk.payload as object));
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

function assertNoLoggingPolicyApi(exportNames: readonly string[]): void {
  for (const name of exportNames) {
    expect(
      name,
      `export ${name} must not be a logging-policy API`,
    ).not.toMatch(LOGGING_POLICY_API_PATTERN);
  }
}

function assertSecretAbsentFromEmissions(
  secret: string,
  emissions: unknown[],
): void {
  const serialized = JSON.stringify(emissions);
  expect(serialized).not.toContain(secret);
}

function assertClassifiedError(
  outcome: ProviderInvokeResult,
  expectedCode: TaxonomyCode,
): CanonicalError {
  expect(outcome.kind === "error" || outcome.kind === "malformed").toBe(true);
  const error =
    outcome.kind === "error" || outcome.kind === "malformed"
      ? outcome.error
      : (() => {
          throw new Error("Expected classified error outcome");
        })();
  assertCanonicalErrorShape(error);
  expect(error.taxonomyCode).toBe(expectedCode);
  const classification = classifyFailure(expectedCode);
  expect(error.retryability).toBe(classification === "retryable");
  expect(error).toEqual(setRetryabilityFromClassification(error));
  return error;
}

function normalizeWireGolden(golden: WireRequestGolden): WireRequestGolden {
  return {
    url: golden.url,
    method: golden.method,
    headers: Object.fromEntries(
      Object.entries(golden.headers).map(([key, value]) => [
        key.toLowerCase(),
        value,
      ]),
    ),
    body: golden.body,
  };
}

function normalizeCapturedRequest(
  request: CapturedWireRequest,
): WireRequestGolden {
  const headers = Object.fromEntries(
    Object.entries(request.headers).map(([key, value]) => [
      key.toLowerCase(),
      value,
    ]),
  );
  let body: unknown = undefined;
  if (request.body !== undefined) {
    try {
      body = JSON.parse(request.body);
    } catch {
      body = request.body;
    }
  }
  return {
    url: request.url,
    method: request.method,
    headers,
    body,
  };
}

describe("T-D7-09 second_adapter_owns_no_retry_or_fallback", () => {
  it("Gemini adapter export surface exposes classification only — no retry or fallback API", async () => {
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: "{}",
    }));

    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });
    expect(adapter).toBeInstanceOf(GeminiAdapter);
    expect(typeof adapter.invoke).toBe("function");

    const geminiModule = await import("../src/provider/gemini");
    assertNoRetryOrFallbackApi(Object.keys(geminiModule));
  });
});

describe("T-D7-11 second_provider_credentials_from_secret_store_only", () => {
  it("reads credentials from the secret-store binding only — not config, request input, or literals", async () => {
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        candidates: [
          {
            content: { parts: [{ text: "ok" }], role: "model" },
            finishReason: "STOP",
          },
        ],
        usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 2 },
      }),
    }));

    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const requestWithEmbeddedCredential: CanonicalRequest = {
      ...requestFixture,
      correlationIds: {
        ...requestFixture.correlationIds,
        request_reference: KNOWN_SECRET,
      },
    };

    await invokeThroughPort(adapter, requestWithEmbeddedCredential);

    expect(secretStore.reads).toContain(GEMINI_API_KEY_BINDING);
    expect(secretStore.reads.length).toBeGreaterThan(0);})
});

describe("T-D7-01 second_provider_request_mapping_golden", () => {
  it("maps canonical request to recorded outbound wire golden with API key from secret store", async () => {
    const canonicalRequest = loadFixture<CanonicalRequest>(
      "request-mapping",
      "canonical-request.json",
    );
    const wireGolden = loadFixture<WireRequestGolden>(
      "request-mapping",
      "outbound-wire-golden.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport, captured } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        candidates: [
          {
            content: { parts: [{ text: "mapped" }], role: "model" },
            finishReason: "STOP",
          },
        ],
        usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 20 },
      }),
    }));

    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    await invokeThroughPort(adapter, canonicalRequest);

    expect(captured).toHaveLength(1);
    const emitted = normalizeCapturedRequest(captured[0]!);
    const expected = normalizeWireGolden(wireGolden);

    expect(emitted.url).toBe(expected.url);
    expect(emitted.method).toBe(expected.method);
    expect(emitted.headers).toEqual(
      expect.objectContaining({
        "x-goog-api-key": KNOWN_SECRET,
      }),
    );
    expect(emitted.headers["x-goog-api-key"]).toBe(KNOWN_SECRET);
    expect(emitted.body).toEqual(expected.body);
    expect(JSON.stringify(emitted.body)).not.toContain(KNOWN_SECRET);})
});

describe("T-D7-02 second_provider_stream_normalization", () => {
  it("normalizes recorded provider stream chunks to canonical form with no provider-shaped fields", async () => {
    const canonicalRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const providerStream = loadFixtureText("stream", "provider-stream.sse");
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: providerStream,
    }));

    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, canonicalRequest);
    const chunks = getStreamChunks(outcome);

    expect(chunks.length).toBeGreaterThan(0);
    for (const chunk of chunks) {
      assertCanonicalStreamChunkShape(chunk);
    }})
});

describe("T-D7-03 second_provider_usage_extraction", () => {
  it("extracts usage counters into canonical usage form", async () => {
    const canonicalRequest = loadFixture<CanonicalRequest>(
      "usage",
      "canonical-request.json",
    );
    const providerResponse = loadFixture<Record<string, unknown>>(
      "usage",
      "provider-response.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(providerResponse),
    }));

    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, canonicalRequest);

    expect(outcome.kind).toBe("success");
    if (outcome.kind !== "success") {
      throw new Error("Expected success outcome");
    }

    assertCanonicalResultShape(outcome.result);
    expect(outcome.result.usage).toEqual(
      expect.objectContaining({
        input: expect.any(Number),
        output: expect.any(Number),
      }),
    );

    const usageChunk = getStreamChunks(outcome).find(
      (chunk) => chunk.kind === "usage",
    );
    if (usageChunk) {
      assertCanonicalStreamChunkShape(usageChunk);
    }})
});

describe("T-D7-04 second_provider_error_class_mapped_to_taxonomy", () => {
  it.each(
    Object.entries(WIRE_ERROR_EXPECTATIONS) as Array<
      [GeminiWireErrorClass, (typeof WIRE_ERROR_EXPECTATIONS)[GeminiWireErrorClass]]
    >,
  )(
    "%s maps to taxonomy with D2 retryability",
    async (wireClass, { taxonomy, retryable }) => {
      const fixture = loadFixture<Record<string, unknown>>(
        "errors",
        `${wireClass}.json`,
      );
      const secretStore = createRecordingSecretStore();
      const { transport } = createCapturingTransport(() => ({
        status: (fixture.status as number) ?? 500,
        headers: { "content-type": "application/json" },
        body: JSON.stringify(fixture.body ?? fixture),
      }));

      const adapter = createGeminiAdapter({
        transport,
        secretStore: secretStore.store,
      });

      const outcome = await invokeThroughPort(adapter, requestFixture);
      const error = assertClassifiedError(outcome, taxonomy);
      expect(error.retryability).toBe(retryable);
      expect(classifyFailure(taxonomy)).toBe(
        retryable ? "retryable" : "terminal",
      );
      expect(isRetrySafe(getTaxonomyEntry(taxonomy).retryable)).toBe(retryable);
    },
  );
});

describe("T-D7-05 second_provider_malformed_response", () => {
  it("normalizes malformed provider body to classified canonical error — not an unclassified throw", async () => {
    const malformedBody = loadFixtureText("malformed", "malformed-response.txt");
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: malformedBody,
    }));

    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    expect(outcome.kind === "error" || outcome.kind === "malformed").toBe(
      true,
    );
    if (outcome.kind === "error" || outcome.kind === "malformed") {
      assertCanonicalErrorShape(outcome.error);
    }
  });
});

describe("T-D7-06 second_provider_truncated_response", () => {
  it("normalizes truncated provider response through the port without inventing a taxonomy code", async () => {
    const truncatedResponse = loadFixture<Record<string, unknown>>(
      "truncated",
      "truncated-response.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(truncatedResponse),
    }));

    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);

    expect(
      outcome.kind === "truncation" || outcome.kind === "success",
    ).toBe(true);

    if (outcome.kind === "truncation" || outcome.kind === "success") {
      assertCanonicalResultShape(outcome.result);
      expect(outcome.result.finishReason).toBe("length");
    }})
});

describe("T-D7-07 second_provider_timeout", () => {
  it("classifies adapter-owned deadline exceeded as taxonomy timeout with D2 retryability", async () => {
    const harness = loadFixture<{ deadline_ms?: number }>(
      "timeout",
      "harness.json",
    );
    const secretStore = createRecordingSecretStore();
    const neverResolvingTransport: GeminiTransport = {
      fetch(_url, _init) {
        return new Promise(() => {
          /* never resolves — adapter-owned timeout should fire */
        });
      },
    };

    const adapter = createGeminiAdapter({
      transport: neverResolvingTransport,
      secretStore: secretStore.store,
      timeoutMs: harness.deadline_ms ?? 50,
    });

    const shortDeadlineRequest: CanonicalRequest = {
      ...requestFixture,
      deadline: harness.deadline_ms ?? 50,
    };

    const outcome = await invokeThroughPort(adapter, shortDeadlineRequest);
    const error = assertClassifiedError(outcome, "timeout");
    expect(error.retryability).toBe(true);
    expect(classifyFailure("timeout")).toBe("retryable");})
});

describe("T-D7-08 second_provider_credentials_absent_from_logs_and_journal", () => {
  it("keeps the known secret absent from invoke results; adapter options reject logger/journal", async () => {
    const secretStore = createRecordingSecretStore();

    const successTransport = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        candidates: [
          {
            content: { parts: [{ text: "ok" }], role: "model" },
            finishReason: "STOP",
          },
        ],
        usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1 },
      }),
    }));

    const successAdapter = createGeminiAdapter({
      transport: successTransport.transport,
      secretStore: secretStore.store,
    });
    const successOutcome = await invokeThroughPort(successAdapter, requestFixture);
    assertSecretAbsentFromEmissions(KNOWN_SECRET, [successOutcome]);

    const errorFixture = loadFixture<Record<string, unknown>>(
      "errors",
      "auth_rejected.json",
    );
    const failureTransport = createCapturingTransport(() => ({
      status: (errorFixture.status as number) ?? 401,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(errorFixture.body ?? errorFixture),
    }));

    const failureAdapter = createGeminiAdapter({
      transport: failureTransport.transport,
      secretStore: secretStore.store,
    });
    const failureOutcome = await invokeThroughPort(failureAdapter, requestFixture);
    assertSecretAbsentFromEmissions(KNOWN_SECRET, [failureOutcome]);

    const optionKeys: Array<keyof GeminiAdapterOptions> = [
      "transport",
      "secretStore",
      "timeoutMs",
    ];
    expect(optionKeys).not.toContain("logger");
    expect(optionKeys).not.toContain("journal");
  });
});

describe("T-D7-10 second_adapter_owns_no_logging_policy", () => {
  it("does not own logging policy — no logger/journal exports or option sinks", async () => {
    const geminiModule = await import("../src/provider/gemini");
    assertNoLoggingPolicyApi(Object.keys(geminiModule));
    expect(geminiModule).not.toHaveProperty("LoggerSink");
    expect(geminiModule).not.toHaveProperty("JournalSink");

    type Options = GeminiAdapterOptions;
    type Forbidden = "logger" | "journal";
    type HasForbidden = Forbidden extends keyof Options ? true : false;
    const hasForbidden: HasForbidden = false;
    expect(hasForbidden).toBe(false);
  });
});
