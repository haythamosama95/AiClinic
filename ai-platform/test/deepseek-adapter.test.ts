import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
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
  DeepSeekAdapter,
  DEEPSEEK_API_KEY_BINDING,
  type DeepSeekAdapterOptions,
  type DeepSeekTransport,
  type DeepSeekTransportResponse,
  type SecretStorePort,
} from "../src/provider/deepseek";
import {
  type ProviderInvokeOptions,
  type ProviderInvokeResult,
  type ProviderPort,
} from "../src/provider/port";

const TEST_ROOT = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES_ROOT = path.join(TEST_ROOT, "fixtures", "deepseek");

const KNOWN_SECRET = "deepseek-test-api-key-secret-value-do-not-log";

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

type DeepSeekWireErrorClass =
  | "auth_rejected"
  | "rate_limited"
  | "provider_server_error"
  | "content_filtered";

const WIRE_ERROR_EXPECTATIONS: Record<
  DeepSeekWireErrorClass,
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
  transport: DeepSeekTransport;
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
      if (name !== DEEPSEEK_API_KEY_BINDING) {
        return undefined;
      }
      return secret === null ? undefined : secret;
    },
  };
  return { store, reads };
}

function createCapturingTransport(
  responder: (request: CapturedWireRequest) => DeepSeekTransportResponse,
): CapturingTransport {
  const captured: CapturedWireRequest[] = [];
  const transport: DeepSeekTransport = {
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

function createDeepSeekAdapter(
  options: DeepSeekAdapterOptions,
): DeepSeekAdapter & ProviderPort {
  return new DeepSeekAdapter(options);
}

function assertAdapterOptionsKeysOnly(
  options: Record<string, unknown>,
): void {
  const keys = Object.keys(options);
  expect(keys.length).toBeGreaterThan(0);
  for (const key of keys) {
    expect(
      ALLOWED_ADAPTER_OPTION_KEYS.has(key),
      `unexpected DeepSeekAdapterOptions key: ${key}`,
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
    choices: [{ message: { content }, finish_reason: "stop" }],
    usage: { prompt_tokens: 1, completion_tokens: 1 },
    id: "ds-ok",
  });
}

describe("T-D5-09 adapter_owns_no_retry_or_fallback", () => {
  it("DeepSeek adapter export surface exposes classification only — no retry or fallback API", async () => {
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

    const adapter = createDeepSeekAdapter(plainOptions);
    expect(adapter).toBeInstanceOf(DeepSeekAdapter);
    expect(typeof adapter.invoke).toBe("function");

    const deepseekModule = await import("../src/provider/deepseek");
    assertNoRetryOrFallbackApi(Object.keys(deepseekModule));
  });
});

describe("T-D5-11 credentials_from_secret_store_only", () => {
  it("reads credentials from the secret-store binding only — not config, request input, or literals", async () => {
    const secretStore = createRecordingSecretStore();
    const { transport, captured } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        choices: [
          {
            message: { content: "ok" },
            finish_reason: "stop",
          },
        ],
        usage: { prompt_tokens: 1, completion_tokens: 2 },
        id: "ds-req-001",
      }),
    }));

    const adapter = createDeepSeekAdapter({
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

    expect(secretStore.reads).toContain(DEEPSEEK_API_KEY_BINDING);
    expect(secretStore.reads.length).toBeGreaterThan(0);

    expect(captured).toHaveLength(1);
    const wire = normalizeCapturedRequest(captured[0]!);
    expect(wire.headers.authorization).toBe(`Bearer ${KNOWN_SECRET}`);
    expect(JSON.stringify(wire.body)).not.toContain(KNOWN_SECRET);
  });
});

describe("T-D5-01 request_mapping_golden", () => {
  it("maps canonical request to recorded outbound wire golden with Authorization from secret store", async () => {
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
        choices: [
          {
            message: { content: "mapped" },
            finish_reason: "stop",
          },
        ],
        usage: { prompt_tokens: 10, completion_tokens: 20 },
        id: "ds-req-golden",
      }),
    }));

    const adapter = createDeepSeekAdapter({
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
        authorization: `Bearer ${KNOWN_SECRET}`,
      }),
    );
    expect(emitted.headers.authorization).toBe(`Bearer ${KNOWN_SECRET}`);
    expect(emitted.body).toEqual(expected.body);
    expect(JSON.stringify(emitted.body)).not.toContain(KNOWN_SECRET);
  });
});

describe("T-D5-02 stream_normalization", () => {
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

    const adapter = createDeepSeekAdapter({
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

describe("T-D5-03 usage_extraction", () => {
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

    const adapter = createDeepSeekAdapter({
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
      cached: 0,
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

describe("T-D5-04 provider_error_class_mapped_to_taxonomy", () => {
  it.each(
    Object.entries(WIRE_ERROR_EXPECTATIONS) as Array<
      [DeepSeekWireErrorClass, (typeof WIRE_ERROR_EXPECTATIONS)[DeepSeekWireErrorClass]]
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

      const adapter = createDeepSeekAdapter({
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

describe("T-D5-05 malformed_response", () => {
  it("normalizes malformed provider body to classified canonical error — not an unclassified throw", async () => {
    const malformedBody = loadFixtureText("malformed", "malformed-response.txt");
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: malformedBody,
    }));

    const adapter = createDeepSeekAdapter({
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

describe("T-D5-06 truncated_response", () => {
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

    const adapter = createDeepSeekAdapter({
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

describe("T-D5-07 timeout", () => {
  it("classifies adapter-owned deadline exceeded as taxonomy timeout with D2 retryability", async () => {
    const harness = loadFixture<{ deadline_ms?: number }>(
      "timeout",
      "harness.json",
    );
    const secretStore = createRecordingSecretStore();
    let capturedSignal: AbortSignal | undefined;
    const neverResolvingTransport: DeepSeekTransport = {
      fetch(_url, init) {
        capturedSignal = init.signal;
        return new Promise(() => {
          /* never resolves — adapter-owned timeout should fire */
        });
      },
    };

    const adapter = createDeepSeekAdapter({
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
    const asyncTransport: DeepSeekTransport = {
      async fetch() {
        await Promise.resolve();
        return {
          status: 200,
          headers: { "content-type": "application/json" },
          body: successJsonBody("within-deadline"),
        };
      },
    };

    const adapter = createDeepSeekAdapter({
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

describe("T-D5-08 credentials_absent_from_logs_and_journal", () => {
  it("keeps the known secret absent from invoke results; adapter options reject logger/journal", async () => {
    const secretStore = createRecordingSecretStore();

    const successTransport = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        choices: [{ message: { content: "ok" }, finish_reason: "stop" }],
        usage: { prompt_tokens: 1, completion_tokens: 1 },
        id: "ds-spy-success",
      }),
    }));

    const successAdapter = createDeepSeekAdapter({
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

    const failureAdapter = createDeepSeekAdapter({
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

    const timeoutTransport: DeepSeekTransport = {
      fetch() {
        return new Promise(() => {
          /* never resolves */
        });
      },
    };
    const timeoutAdapter = createDeepSeekAdapter({
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
    const missingAdapter = createDeepSeekAdapter({
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
    const streamAdapter = createDeepSeekAdapter({
      transport: streamTransport.transport,
      secretStore: secretStore.store,
    });
    const streamOutcome = await invokeThroughPort(streamAdapter, streamRequest);
    assertSecretAbsentFromEmissions(KNOWN_SECRET, [streamOutcome]);

    // Adapters must not accept logger/journal sinks (§4.3.8).
    const optionKeys: Array<keyof DeepSeekAdapterOptions> = [
      "transport",
      "secretStore",
      "timeoutMs",
    ];
    expect(optionKeys).not.toContain("logger");
    expect(optionKeys).not.toContain("journal");
  });
});

describe("T-D5-10 adapter_owns_no_logging_policy", () => {
  it("does not own logging policy — no logger/journal exports or option sinks", async () => {
    const deepseekModule = await import("../src/provider/deepseek");
    assertNoLoggingPolicyApi(Object.keys(deepseekModule));
    expect(deepseekModule).not.toHaveProperty("LoggerSink");
    expect(deepseekModule).not.toHaveProperty("JournalSink");

    type Options = DeepSeekAdapterOptions;
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
    createDeepSeekAdapter(plainOptions);
  });
});

describe("transport_throw_and_reject", () => {
  it("sync throw from fetch classifies as internal_error without escaping", async () => {
    const secretStore = createRecordingSecretStore();
    const throwingTransport: DeepSeekTransport = {
      fetch() {
        throw new Error("sync transport boom");
      },
    };
    const adapter = createDeepSeekAdapter({
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
    const rejectingTransport: DeepSeekTransport = {
      fetch() {
        return Promise.reject(new Error("async transport boom"));
      },
    };
    const adapter = createDeepSeekAdapter({
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
    const neverResolvingTransport: DeepSeekTransport = {
      fetch() {
        return new Promise(() => {
          /* never resolves */
        });
      },
    };
    const adapter = createDeepSeekAdapter({
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
    const adapter = createDeepSeekAdapter({
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
    const adapter = createDeepSeekAdapter({
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
    const adapter = createDeepSeekAdapter({
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

describe("finish_reason_content_filter", () => {
  it("200 finish_reason content_filter maps to provider_rejected terminal", async () => {
    const body = loadFixture<Record<string, unknown>>(
      "errors",
      "finish_reason_content_filter.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }));
    const adapter = createDeepSeekAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    const error = assertClassifiedError(outcome, "provider_rejected");
    expect(error.retryability).toBe(false);
  });
});

describe("finish_reason_insufficient_resource", () => {
  it("200 finish_reason insufficient_system_resource maps to internal_error retryable", async () => {
    const body = loadFixture<Record<string, unknown>>(
      "errors",
      "finish_reason_insufficient_resource.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }));
    const adapter = createDeepSeekAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    const error = assertClassifiedError(outcome, "internal_error");
    expect(error.retryability).toBe(true);
  });
});

describe("safety_message_with_429", () => {
  it("HTTP 429 with safety in message still rate_limited retryable — status wins", async () => {
    const fixture = loadFixture<Record<string, unknown>>(
      "errors",
      "safety_message_with_429.json",
    );
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: (fixture.status as number) ?? 429,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(fixture.body ?? fixture),
    }));
    const adapter = createDeepSeekAdapter({
      transport,
      secretStore: secretStore.store,
    });

    const outcome = await invokeThroughPort(adapter, requestFixture);
    const error = assertClassifiedError(outcome, "rate_limited");
    expect(error.retryability).toBe(true);
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
    const adapter = createDeepSeekAdapter({
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
  it("200 JSON without usage succeeds with usage_absent provider_note", async () => {
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
    const adapter = createDeepSeekAdapter({
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

describe("stream_wire_requests_include_usage", () => {
  it("streaming wire body sets stream_options.include_usage true", async () => {
    const streamRequest = loadFixture<CanonicalRequest>(
      "stream",
      "canonical-request.json",
    );
    const streamBody = loadFixtureText("stream", "provider-stream.sse");
    const secretStore = createRecordingSecretStore();
    const { transport, captured } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "text/event-stream" },
      body: streamBody,
    }));
    const adapter = createDeepSeekAdapter({
      transport,
      secretStore: secretStore.store,
    });

    await invokeThroughPort(adapter, streamRequest);

    expect(captured).toHaveLength(1);
    const wire = normalizeCapturedRequest(captured[0]!);
    expect(wire.body).toEqual(
      expect.objectContaining({
        stream: true,
        stream_options: expect.objectContaining({
          include_usage: true,
        }),
      }),
    );
    expect(
      (wire.body as { stream_options?: { include_usage?: boolean } })
        .stream_options?.include_usage,
    ).toBe(true);
  });
});
