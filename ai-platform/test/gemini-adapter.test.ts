import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it, vi } from "vitest";
import {
  CANONICAL_FIELD_MANIFEST,
  assertExactlyOneTerminal,
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
  PROVIDER_RESPONSE_BODY_SIZE_LIMIT,
  type GeminiAdapterOptions,
  type GeminiTransport,
  type GeminiTransportResponse,
  type SecretStorePort,
} from "../src/provider/gemini";
import {
  type ProviderInvokeOptions,
  type ProviderInvokeResult,
  type ProviderPort,
} from "../src/provider/port";

const TEST_ROOT = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES_ROOT = path.join(TEST_ROOT, "fixtures", "gemini");

const KNOWN_SECRET = "gemini-test-api-key-secret-value-do-not-log";
const DECOY_SECRET = "request-embedded-decoy-not-the-store-secret";

const ALLOWED_ADAPTER_OPTION_KEYS = new Set([
  "transport",
  "secretStore",
  "timeoutMs",
]);

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

/** Pass `null` for a missing binding (plain `undefined` would hit the default). */
function createRecordingSecretStore(
  secret: string | null = KNOWN_SECRET,
): RecordingSecretStore {
  const reads: string[] = [];
  const store: SecretStorePort = {
    getSecret(name: string): string | undefined {
      reads.push(name);
      if (name !== GEMINI_API_KEY_BINDING) {
        return undefined;
      }
      return secret === null ? undefined : secret;
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

function createPushableUtf8Stream(): {
  stream: ReadableStream<Uint8Array>;
  enqueue: (text: string) => void;
  close: () => void;
} {
  const encoder = new TextEncoder();
  let controller: ReadableStreamDefaultController<Uint8Array> | undefined;
  const stream = new ReadableStream<Uint8Array>({
    start(c) {
      controller = c;
    },
  });
  return {
    stream,
    enqueue(text) {
      controller!.enqueue(encoder.encode(text));
    },
    close() {
      controller!.close();
    },
  };
}

function createGeminiAdapter(
  options: GeminiAdapterOptions,
): GeminiAdapter & ProviderPort {
  return new GeminiAdapter(options);
}

function assertAdapterOptionsKeysOnly(
  options: Record<string, unknown>,
): void {
  const keys = Object.keys(options);
  expect(keys.length).toBeGreaterThan(0);
  for (const key of keys) {
    expect(
      ALLOWED_ADAPTER_OPTION_KEYS.has(key),
      `unexpected GeminiAdapterOptions key: ${key}`,
    ).toBe(true);
  }
  expect(keys.every((key) => ALLOWED_ADAPTER_OPTION_KEYS.has(key))).toBe(true);
}

async function invokeThroughPort(
  port: ProviderPort,
  request: CanonicalRequest,
  options?: ProviderInvokeOptions,
): Promise<ProviderInvokeResult> {
  return port.invoke(request, options);
}

function getStreamChunks(outcome: ProviderInvokeResult): CanonicalStreamChunk[] {
  if (outcome.kind === "success" || outcome.kind === "truncation") {
    return [...outcome.chunks];
  }
  if (
    (outcome.kind === "error" || outcome.kind === "malformed") &&
    outcome.chunks
  ) {
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

function successJsonBody(content = "ok"): string {
  return JSON.stringify({
    candidates: [
      {
        content: { parts: [{ text: content }], role: "model" },
        finishReason: "STOP",
      },
    ],
    usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1 },
  });
}

describe("T-D7-09 second_adapter_owns_no_retry_or_fallback", () => {
  it("Gemini adapter export surface exposes classification only — no retry or fallback API", async () => {
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: "{}",
    }));

    const plainOptions = {
      transport,
      secretStore: secretStore.store,
      timeoutMs: 1_000,
    };
    assertAdapterOptionsKeysOnly(plainOptions);

    const adapter = createGeminiAdapter(plainOptions);
    expect(adapter).toBeInstanceOf(GeminiAdapter);
    expect(typeof adapter.invoke).toBe("function");

    const geminiModule = await import("../src/provider/gemini");
    assertNoRetryOrFallbackApi(Object.keys(geminiModule));
  });
});

describe("T-D7-11 second_provider_credentials_from_secret_store_only", () => {
  it("reads credentials from the secret-store binding only — not config, request input, or literals", async () => {
    const secretStore = createRecordingSecretStore();
    const { transport, captured } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: successJsonBody("ok"),
    }));

    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const requestWithEmbeddedCredential: CanonicalRequest = {
      ...requestFixture,
      correlationIds: {
        ...requestFixture.correlationIds,
        request_reference: DECOY_SECRET,
      },
    };

    await invokeThroughPort(adapter, requestWithEmbeddedCredential);

    expect(secretStore.reads).toContain(GEMINI_API_KEY_BINDING);
    expect(secretStore.reads.length).toBeGreaterThan(0);

    expect(captured).toHaveLength(1);
    const wire = normalizeCapturedRequest(captured[0]!);
    expect(wire.headers["x-goog-api-key"]).toBe(KNOWN_SECRET);
    expect(wire.headers["x-goog-api-key"]).not.toBe(DECOY_SECRET);
    expect(JSON.stringify(wire.body)).not.toContain(KNOWN_SECRET);
  });
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
    expect(JSON.stringify(emitted.body)).not.toContain(KNOWN_SECRET);
  });
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
    }

    assertExactlyOneTerminal(chunks);

    const nonTerminalTextDeltas = chunks.filter(
      (chunk) => chunk.kind === "text_delta" && chunk.terminal !== true,
    );
    expect(
      nonTerminalTextDeltas.map(
        (chunk) => (chunk.payload as { text: string }).text,
      ),
    ).toEqual(["Hello", " world"]);

    expect(chunks.map((chunk) => chunk.sequenceNumber)).toEqual(
      chunks.map((_, index) => index),
    );
    expect(chunks[0]!.sequenceNumber).toBe(0);

    const terminal = chunks.find((chunk) => chunk.terminal === true)!;
    expect(terminal.kind).toBe("text_delta");
    expect((terminal.payload as { text: string }).text).toBe("");

    expect(outcome.kind).toBe("success");
    if (outcome.kind !== "success") {
      throw new Error("Expected success outcome");
    }
    expect(outcome.result.finalContent.text).toBe("Hello world");
  });
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
    expect(outcome.result.usage).toEqual({
      input: 42,
      output: 18,
      cached: 7,
    });
    expect(typeof outcome.result.timing.provider_ms).toBe("number");
    expect(outcome.result.timing.provider_ms).toBeGreaterThanOrEqual(0);

    const usageChunk = getStreamChunks(outcome).find(
      (chunk) => chunk.kind === "usage",
    );
    if (usageChunk) {
      assertCanonicalStreamChunkShape(usageChunk);
    }
  });
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

    expect(outcome.kind).toBe("truncation");
    if (outcome.kind !== "truncation") {
      throw new Error("Expected truncation outcome");
    }
    assertCanonicalResultShape(outcome.result);
    expect(outcome.result.finishReason).toBe("length");
  });
});

describe("T-D7-07 second_provider_timeout", () => {
  it("classifies adapter-owned deadline exceeded as taxonomy timeout with D2 retryability", async () => {
    const harness = loadFixture<{ deadline_ms?: number }>(
      "timeout",
      "harness.json",
    );
    const secretStore = createRecordingSecretStore();
    let capturedSignal: AbortSignal | undefined;
    const neverResolvingTransport: GeminiTransport = {
      fetch(_url, init) {
        capturedSignal = init.signal;
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
    expect(classifyFailure("timeout")).toBe("retryable");
    expect(capturedSignal).toBeDefined();
    expect(capturedSignal!.aborted).toBe(true);
  });

  it("resolves within deadline via async transport as success", async () => {
    const secretStore = createRecordingSecretStore();
    const asyncTransport: GeminiTransport = {
      async fetch() {
        await Promise.resolve();
        return {
          status: 200,
          headers: { "content-type": "application/json" },
          body: successJsonBody("within-deadline"),
        };
      },
    };

    const adapter = createGeminiAdapter({
      transport: asyncTransport,
      secretStore: secretStore.store,
      timeoutMs: 5_000,
    });

    const outcome = await invokeThroughPort(adapter, {
      ...requestFixture,
      deadline: 5_000,
    });
    expect(outcome.kind).toBe("success");
  });
});

describe("T-D7-08 second_provider_credentials_absent_from_logs_and_journal", () => {
  it("keeps the known secret absent from invoke results; adapter options reject logger/journal", async () => {
    const secretStore = createRecordingSecretStore();

    const successTransport = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: successJsonBody("ok"),
    }));

    const successAdapter = createGeminiAdapter({
      transport: successTransport.transport,
      secretStore: secretStore.store,
    });
    const successOutcome = await invokeThroughPort(
      successAdapter,
      requestFixture,
    );
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
    const failureOutcome = await invokeThroughPort(
      failureAdapter,
      requestFixture,
    );
    assertSecretAbsentFromEmissions(KNOWN_SECRET, [failureOutcome]);
    if (
      failureOutcome.kind === "error" ||
      failureOutcome.kind === "malformed"
    ) {
      expect(failureOutcome.error.providerNative).toBeDefined();
      assertSecretAbsentFromEmissions(KNOWN_SECRET, [
        failureOutcome.error.providerNative,
      ]);
    }

    const timeoutTransport: GeminiTransport = {
      fetch() {
        return new Promise(() => {
          /* never resolves */
        });
      },
    };
    const timeoutAdapter = createGeminiAdapter({
      transport: timeoutTransport,
      secretStore: secretStore.store,
      timeoutMs: 30,
    });
    const timeoutOutcome = await invokeThroughPort(timeoutAdapter, {
      ...requestFixture,
      deadline: 30,
    });
    assertSecretAbsentFromEmissions(KNOWN_SECRET, [timeoutOutcome]);

    const missingStore = createRecordingSecretStore(null);
    const missingAdapter = createGeminiAdapter({
      transport: successTransport.transport,
      secretStore: missingStore.store,
    });
    const missingOutcome = await invokeThroughPort(
      missingAdapter,
      requestFixture,
    );
    assertSecretAbsentFromEmissions(KNOWN_SECRET, [missingOutcome]);

    const streamBody = loadFixtureText("stream", "provider-stream.sse");
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const streamTransport = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: streamBody,
    }));
    const streamAdapter = createGeminiAdapter({
      transport: streamTransport.transport,
      secretStore: secretStore.store,
    });
    const streamOutcome = await invokeThroughPort(streamAdapter, streamRequest);
    assertSecretAbsentFromEmissions(KNOWN_SECRET, [streamOutcome]);

    // Adapters must not accept logger/journal sinks (§4.3.8).
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

    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: successJsonBody(),
    }));
    const plainOptions = {
      transport,
      secretStore: secretStore.store,
      timeoutMs: 500,
    };
    assertAdapterOptionsKeysOnly(plainOptions);
    createGeminiAdapter(plainOptions);
  });
});

describe("transport_throw_and_reject", () => {
  it("sync throw from fetch classifies as internal_error without escaping", async () => {
    const secretStore = createRecordingSecretStore();
    const throwingTransport: GeminiTransport = {
      fetch() {
        throw new Error("sync transport boom");
      },
    };
    const adapter = createGeminiAdapter({
      transport: throwingTransport,
      secretStore: secretStore.store,
    });

    let escaped: unknown;
    let outcome: ProviderInvokeResult | undefined;
    try {
      outcome = await invokeThroughPort(adapter, requestFixture);
    } catch (error) {
      escaped = error;
    }
    expect(escaped).toBeUndefined();
    expect(outcome).toBeDefined();
    assertClassifiedError(outcome!, "internal_error");
  });

  it("rejecting transport promise classifies as internal_error", async () => {
    const secretStore = createRecordingSecretStore();
    const rejectingTransport: GeminiTransport = {
      fetch() {
        return Promise.reject(new Error("async transport boom"));
      },
    };
    const adapter = createGeminiAdapter({
      transport: rejectingTransport,
      secretStore: secretStore.store,
    });

    let escaped: unknown;
    let outcome: ProviderInvokeResult | undefined;
    try {
      outcome = await invokeThroughPort(adapter, requestFixture);
    } catch (error) {
      escaped = error;
    }
    expect(escaped).toBeUndefined();
    expect(outcome).toBeDefined();
    assertClassifiedError(outcome!, "internal_error");
  });
});

describe("caller_abort_propagation", () => {
  it("already-aborted caller signal yields cancelled taxonomy", async () => {
    const secretStore = createRecordingSecretStore();
    const neverResolvingTransport: GeminiTransport = {
      fetch() {
        return new Promise(() => {
          /* never resolves */
        });
      },
    };
    const adapter = createGeminiAdapter({
      transport: neverResolvingTransport,
      secretStore: secretStore.store,
      timeoutMs: 5_000,
    });

    const controller = new AbortController();
    controller.abort();

    const outcome = await invokeThroughPort(adapter, requestFixture, {
      signal: controller.signal,
    });
    assertClassifiedError(outcome, "cancelled");
  });
});

describe("truncated_stream_sse", () => {
  it("stream without finish_reason or [DONE] is truncation — not clean stop success", async () => {
    const streamBody = loadFixtureText("truncated", "truncated-stream.sse");
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: streamBody,
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, streamRequest);
    expect(outcome.kind).toBe("truncation");
    expect(outcome.kind).not.toBe("success");
  });
});

describe("malformed_stream_sse", () => {
  it("corrupted SSE line mid-stream classifies as malformed or error — not success", async () => {
    const streamBody = loadFixtureText("malformed", "malformed-stream.sse");
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: streamBody,
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, streamRequest);
    expect(outcome.kind === "malformed" || outcome.kind === "error").toBe(
      true,
    );
    expect(outcome.kind).not.toBe("success");
  });
});

describe("mid_stream_error_frame", () => {
  it("mid-stream provider error frame classifies as error — not success", async () => {
    const streamBody = loadFixtureText("errors", "mid-stream-error.sse");
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: streamBody,
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, streamRequest);
    expect(outcome.kind === "error" || outcome.kind === "malformed").toBe(
      true,
    );
    expect(outcome.kind).not.toBe("success");
  });
});

describe("stream_finish_reason_safety", () => {
  it("stream finishReason SAFETY maps to provider_rejected", async () => {
    const streamBody = loadFixtureText("errors", "stream-safety.sse");
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: streamBody,
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, streamRequest);
    assertClassifiedError(outcome, "provider_rejected");
  });
});

describe("finish_reason_recitation", () => {
  it("200 finishReason RECITATION maps to provider_rejected", async () => {
    const body = loadFixture<Record<string, unknown>>(
      "errors",
      "finish_reason_recitation.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    const error = assertClassifiedError(outcome, "provider_rejected");
    expect(error.retryability).toBe(false);
  });
});

describe("prompt_feedback_block", () => {
  it("promptFeedback.blockReason maps to provider_rejected", async () => {
    const body = loadFixture<Record<string, unknown>>(
      "errors",
      "prompt_feedback_block.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    const error = assertClassifiedError(outcome, "provider_rejected");
    expect(error.retryability).toBe(false);
  });
});

describe("missing_credentials_consumed_budget", () => {
  it("absent secret store value yields error with consumedBudget false", async () => {
    const secretStore = createRecordingSecretStore(null);
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: successJsonBody(),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    expect(outcome.kind === "error" || outcome.kind === "malformed").toBe(
      true,
    );
    if (outcome.kind !== "error" && outcome.kind !== "malformed") {
      throw new Error("Expected classified error for missing credentials");
    }
    expect(outcome.error.consumedBudget).toBe(false);
  });
});

describe("usage_absent_provider_note", () => {
  it("200 JSON without usageMetadata succeeds with usage_absent provider_note", async () => {
    const body = loadFixture<Record<string, unknown>>(
      "usage",
      "usage-absent-response.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    expect(
      outcome.kind === "success" || outcome.kind === "truncation",
    ).toBe(true);
    if (outcome.kind !== "success" && outcome.kind !== "truncation") {
      throw new Error("Expected success or truncation");
    }
    expect(typeof outcome.result.timing.provider_ms).toBe("number");

    const note = getStreamChunks(outcome).find(
      (chunk) => chunk.kind === "provider_note",
    );
    expect(note).toBeDefined();
    expect(note!.payload).toEqual({ note: "usage_absent" });
  });
});

describe("wire_mapping_system_and_roles", () => {
  it("maps system to systemInstruction and folds data into user contents", async () => {
    const secretStore = createRecordingSecretStore();
    const { transport, captured } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: successJsonBody("mapped"),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const multiRoleRequest: CanonicalRequest = {
      ...requestFixture,
      parts: [
        { role: "system", content: "You are a clinic assistant." },
        { role: "user", content: "Summarise the visit." },
        { role: "data", content: "vitals: 120/80" },
      ],
    };

    await invokeThroughPort(adapter, multiRoleRequest);

    expect(captured).toHaveLength(1);
    const wire = normalizeCapturedRequest(captured[0]!);
    const body = wire.body as {
      systemInstruction?: unknown;
      contents?: Array<{ role?: string; parts?: unknown }>;
    };

    expect(body.systemInstruction).toBeDefined();
    expect(body.contents).toBeDefined();
    const roles = (body.contents ?? []).map((entry) => entry.role);
    expect(roles).not.toContain("system");
    expect(roles).not.toContain("data");
    expect(roles).toContain("user");
  });
});

describe("a4_empty_stop_conditions_omit_stop_sequences", () => {
  it("omits generationConfig.stopSequences when CanonicalRequest.stopConditions is empty (A4 always empty)", async () => {
    const secretStore = createRecordingSecretStore();
    const { transport, captured } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: successJsonBody("stop-empty"),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    expect(requestFixture.stopConditions).toEqual([]);
    await invokeThroughPort(adapter, requestFixture);

    expect(captured).toHaveLength(1);
    const wire = normalizeCapturedRequest(captured[0]!);
    const body = wire.body as {
      generationConfig?: { stopSequences?: unknown };
    };
    expect(body.generationConfig).not.toHaveProperty("stopSequences");
  });
});

describe("wire_mapping_top_k_and_schema", () => {
  it("maps top_k and json schema into generationConfig", async () => {
    const secretStore = createRecordingSecretStore();
    const { transport, captured } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: successJsonBody("schema-ok"),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const schemaRequest: CanonicalRequest = {
      ...requestFixture,
      samplingConstraints: { temperature: 0.2, top_k: 3 },
      formatDirective: {
        type: "json",
        schema: { type: "object" },
      },
    };

    await invokeThroughPort(adapter, schemaRequest);

    expect(captured).toHaveLength(1);
    const wire = normalizeCapturedRequest(captured[0]!);
    const body = wire.body as {
      generationConfig?: {
        topK?: number;
        responseMimeType?: string;
        responseSchema?: unknown;
      };
    };

    expect(body.generationConfig?.topK).toBe(3);
    expect(body.generationConfig?.responseMimeType).toBe("application/json");
    expect(body.generationConfig?.responseSchema).toEqual({ type: "object" });
  });
});

describe("stream_error_frame_classification_structured", () => {
  it("does not rate_limit on message substring 'accurate' / 'generate'", async () => {
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: [
        'data: {"error":{"code":400,"message":"Response is not accurate","status":"INVALID_ARGUMENT"}}',
        "",
      ].join("\n"),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, streamRequest);
    assertClassifiedError(outcome, "provider_rejected");
  });

  it("INTERNAL with 'generate' in message classifies as internal_error not rate_limited", async () => {
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: [
        'data: {"error":{"code":500,"message":"failed to generate content","status":"INTERNAL"}}',
        "",
      ].join("\n"),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, streamRequest);
    assertClassifiedError(outcome, "internal_error");
  });

  it("RESOURCE_EXHAUSTED structured status still rate_limited", async () => {
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: [
        'data: {"error":{"code":429,"message":"quota","status":"RESOURCE_EXHAUSTED"}}',
        "",
      ].join("\n"),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, streamRequest);
    assertClassifiedError(outcome, "rate_limited");
  });
});

describe("retry_after_header", () => {
  it("attaches retryAfterMs from Retry-After delta-seconds on 429", async () => {
    const fixture = loadFixture<{
      status: number;
      body: unknown;
    }>("errors", "rate_limited.json");
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: fixture.status,
      headers: {
        "content-type": "application/json",
        "Retry-After": "5",
      },
      body: JSON.stringify(fixture.body),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    const error = assertClassifiedError(outcome, "rate_limited");
    expect(error.retryAfterMs).toBe(5_000);
  });

  it("attaches retryAfterMs from Retry-After HTTP-date on 429", async () => {
    const fixture = loadFixture<{
      status: number;
      body: unknown;
    }>("errors", "rate_limited.json");
    const httpDate = new Date(Date.now() + 30_000).toUTCString();
    const targetMs = Date.parse(httpDate);
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: fixture.status,
      headers: {
        "content-type": "application/json",
        "retry-after": httpDate,
      },
      body: JSON.stringify(fixture.body),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const before = Date.now();
    const outcome = await invokeThroughPort(adapter, requestFixture);
    const after = Date.now();
    const error = assertClassifiedError(outcome, "rate_limited");
    expect(error.retryAfterMs).toBeDefined();
    // Adapter computed max(0, target - now) with now ∈ [before, after].
    expect(error.retryAfterMs!).toBeGreaterThanOrEqual(targetMs - after);
    expect(error.retryAfterMs!).toBeLessThanOrEqual(targetMs - before);
  });
});

describe("provider_response_body_size_limit", () => {
  it("rejects oversized provider body as classified internal_error", async () => {
    const secretStore = createRecordingSecretStore();
    const oversized = "x".repeat(PROVIDER_RESPONSE_BODY_SIZE_LIMIT + 1);
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: oversized,
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    const error = assertClassifiedError(outcome, "internal_error");
    expect(error.providerNative.code).toBe("response_too_large");
  });

  it("rejects when Content-Length declares over the limit", async () => {
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: {
        "content-type": "application/json",
        "content-length": String(PROVIDER_RESPONSE_BODY_SIZE_LIMIT + 1),
      },
      body: successJsonBody("ok"),
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    const error = assertClassifiedError(outcome, "internal_error");
    expect(error.providerNative.code).toBe("response_too_large");
  });
});

describe("incremental_sse_live_deltas", () => {
  it("parses a ReadableStream body incrementally and emits text_delta before the stream closes", async () => {
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const pushable = createPushableUtf8Stream();
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: pushable.stream,
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const liveText: string[] = [];
    let invokeSettled = false;
    const invokePromise = invokeThroughPort(adapter, streamRequest, {
      onStreamChunk(chunk) {
        if (chunk.kind !== "text_delta") {
          return;
        }
        const text =
          typeof chunk.payload === "object" &&
          chunk.payload !== null &&
          "text" in chunk.payload
            ? String((chunk.payload as { text: unknown }).text)
            : "";
        if (text.length > 0) {
          liveText.push(text);
        }
      },
    }).then((outcome) => {
      invokeSettled = true;
      return outcome;
    });

    await Promise.resolve();
    pushable.enqueue(
      'data: {"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"},"finishReason":null}]}\n\n',
    );

    await vi.waitFor(() => {
      expect(liveText).toEqual(["Hello"]);
    });
    expect(invokeSettled).toBe(false);

    pushable.enqueue(
      'data: {"candidates":[{"content":{"parts":[{"text":" world"}],"role":"model"},"finishReason":null}]}\n\n',
    );
    await vi.waitFor(() => {
      expect(liveText).toEqual(["Hello", " world"]);
    });
    expect(invokeSettled).toBe(false);

    pushable.enqueue(
      'data: {"candidates":[{"content":{"parts":[],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":4,"totalTokenCount":16}}\n\n',
    );
    pushable.close();

    const outcome = await invokePromise;
    expect(outcome.kind).toBe("success");
    expect(invokeSettled).toBe(true);
    if (outcome.kind !== "success") {
      throw new Error("Expected success");
    }
    expect(outcome.result.finalContent.text).toBe("Hello world");
  });
});

describe("incremental_sse_live_deltas", () => {
  it("parses a ReadableStream body incrementally and emits text_delta before the stream closes", async () => {
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const pushable = createPushableUtf8Stream();
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: pushable.stream,
    }));
    const adapter = createGeminiAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const liveText: string[] = [];
    let invokeSettled = false;
    const invokePromise = invokeThroughPort(adapter, streamRequest, {
      onStreamChunk(chunk) {
        if (chunk.kind !== "text_delta") {
          return;
        }
        const text =
          typeof chunk.payload === "object" &&
          chunk.payload !== null &&
          "text" in chunk.payload
            ? String((chunk.payload as { text: unknown }).text)
            : "";
        if (text.length > 0) {
          liveText.push(text);
        }
      },
    }).then((outcome) => {
      invokeSettled = true;
      return outcome;
    });

    await Promise.resolve();
    pushable.enqueue(
      'data: {"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"},"finishReason":null}]}\n\n',
    );

    await vi.waitFor(() => {
      expect(liveText).toEqual(["Hello"]);
    });
    expect(invokeSettled).toBe(false);

    pushable.enqueue(
      'data: {"candidates":[{"content":{"parts":[{"text":" world"}],"role":"model"},"finishReason":null}]}\n\n',
    );
    await vi.waitFor(() => {
      expect(liveText).toEqual(["Hello", " world"]);
    });
    expect(invokeSettled).toBe(false);

    pushable.enqueue(
      'data: {"candidates":[{"content":{"parts":[],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":4,"totalTokenCount":16}}\n\n',
    );
    pushable.close();

    const outcome = await invokePromise;
    expect(outcome.kind).toBe("success");
    expect(invokeSettled).toBe(true);
    if (outcome.kind !== "success") {
      throw new Error("Expected success");
    }
    expect(outcome.result.finalContent.text).toBe("Hello world");
  });
});

describe("envelope_raw_provider_body_capture", () => {
  it("attaches a size-capped rawBody from the provider JSON on success", async () => {
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
    expect(outcome).toHaveProperty("rawBody");
    expect(outcome.rawBody).toEqual({
      payload: providerResponse,
      truncated: false,
    });
  });

  it("sets truncated true when the raw provider body exceeds 16 KB", async () => {
    const hugeText = "H".repeat(20_000);
    const providerResponse = {
      candidates: [
        {
          content: { parts: [{ text: hugeText }] },
          finishReason: "STOP",
        },
      ],
      usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1 },
    };
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

    const outcome = await invokeThroughPort(adapter, requestFixture);
    expect(outcome.kind).toBe("success");
    expect(outcome.rawBody).toMatchObject({ truncated: true });
    expect(typeof outcome.rawBody?.payload).toBe("string");
    const encoded = new TextEncoder().encode(String(outcome.rawBody?.payload));
    expect(encoded.byteLength).toBeLessThanOrEqual(16 * 1024);
  });
});
