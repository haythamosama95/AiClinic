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
  DeepSeekAdapter,
  DEEPSEEK_API_KEY_BINDING,
  type DeepSeekAdapterOptions,
  type DeepSeekTransport,
  type DeepSeekTransportResponse,
  type JournalSink,
  type LoggerSink,
  type SecretStorePort,
} from "../src/provider/deepseek";
import {
  type ProviderInvokeResult,
  type ProviderPort,
} from "../src/provider/port";

const TEST_ROOT = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES_ROOT = path.join(TEST_ROOT, "fixtures", "deepseek");

const KNOWN_SECRET = "deepseek-test-api-key-secret-value-do-not-log";

const RETRY_FALLBACK_API_PATTERN =
  /^(retry|withRetry|executeRetry|retryAttempt|fallback|withFallback|executeFallback|fallbackTo)/i;

const LOGGING_POLICY_API_PATTERN =
  /^(setLogLevel|configureLogging|loggingPolicy|withLogging|logPolicy|decideLogLevel|emitLogPolicy)/i;

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

type RecordingLogger = {
  sink: LoggerSink;
  lines: Array<{
    level: string;
    message: string;
    meta?: Record<string, unknown>;
  }>;
};

type RecordingJournal = {
  sink: JournalSink;
  records: Record<string, unknown>[];
};

type CapturingTransport = {
  transport: DeepSeekTransport;
  captured: CapturedWireRequest[];
};

/** DeepSeek invoke may attach normalized stream chunks when stream flag is true. */
type DeepSeekInvokeOutcome = ProviderInvokeResult & {
  streamChunks?: readonly CanonicalStreamChunk[];
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
      return name === DEEPSEEK_API_KEY_BINDING ? secret : undefined;
    },
  };
  return { store, reads };
}

function createRecordingLogger(): RecordingLogger {
  const lines: RecordingLogger["lines"] = [];
  const sink: LoggerSink = {
    log(level, message, meta) {
      lines.push({ level, message, meta });
    },
  };
  return { sink, lines };
}

function createRecordingJournal(): RecordingJournal {
  const records: Record<string, unknown>[] = [];
  const sink: JournalSink = {
    emit(record) {
      records.push(record);
    },
  };
  return { sink, records };
}

function createCapturingTransport(
  responder: (request: CapturedWireRequest) => DeepSeekTransportResponse,
): CapturingTransport {
  const captured: CapturedWireRequest[] = [];
  const transport: DeepSeekTransport = {
    async fetch(url, init) {
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

function invokeThroughPort(
  port: ProviderPort,
  request: CanonicalRequest,
): ProviderInvokeResult {
  return port.invoke(request);
}

function getStreamChunks(outcome: ProviderInvokeResult): CanonicalStreamChunk[] {
  const extended = outcome as DeepSeekInvokeOutcome;
  return [...(extended.streamChunks ?? [])];
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
  expect(error["taxonomy code"]).toBe(expectedCode);
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

describe("T-D5-09 adapter_owns_no_retry_or_fallback", () => {
  it("DeepSeek adapter export surface exposes classification only — no retry or fallback API", async () => {
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: "{}",
    }));

    const adapter = createDeepSeekAdapter({
      transport,
      secretStore: secretStore.store,
    });
    expect(adapter).toBeInstanceOf(DeepSeekAdapter);
    expect(typeof adapter.invoke).toBe("function");

    const deepseekModule = await import("../src/provider/deepseek");
    assertNoRetryOrFallbackApi(Object.keys(deepseekModule));
  });
});

describe("T-D5-11 credentials_from_secret_store_only", () => {
  it("reads credentials from the secret-store binding only — not config, request input, or literals", () => {
    const secretStore = createRecordingSecretStore();
    const { transport } = createCapturingTransport(() => ({
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
      "correlation ids": {
        ...requestFixture["correlation ids"],
        request_reference: KNOWN_SECRET,
      },
    };

    invokeThroughPort(adapter, requestWithEmbeddedCredential);

    expect(secretStore.reads).toContain(DEEPSEEK_API_KEY_BINDING);
    expect(secretStore.reads.length).toBeGreaterThan(0);
  });
});

describe("T-D5-01 request_mapping_golden", () => {
  it("maps canonical request to recorded outbound wire golden with Authorization from secret store", () => {
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

    invokeThroughPort(adapter, canonicalRequest);

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
  it("normalizes recorded provider stream chunks to canonical form with no provider-shaped fields", () => {
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

    const outcome = invokeThroughPort(adapter, canonicalRequest);
    const chunks = getStreamChunks(outcome);

    expect(chunks.length).toBeGreaterThan(0);
    for (const chunk of chunks) {
      assertCanonicalStreamChunkShape(chunk);
    }
  });
});

describe("T-D5-03 usage_extraction", () => {
  it("extracts usage counters into canonical usage form", () => {
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

    const outcome = invokeThroughPort(adapter, canonicalRequest);

    expect(outcome.kind).toBe("success");
    if (outcome.kind !== "success") {
      throw new Error("Expected success outcome");
    }

    assertCanonicalResultShape(outcome.result);
    expect(outcome.result["usage counters"]).toEqual(
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
    (wireClass, { taxonomy, retryable }) => {
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

      const outcome = invokeThroughPort(adapter, requestFixture);
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
  it("normalizes malformed provider body to classified canonical error — not an unclassified throw", () => {
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

    let outcome: ProviderInvokeResult | undefined;
    expect(() => {
      outcome = invokeThroughPort(adapter, requestFixture);
    }).not.toThrow();

    expect(outcome).toBeDefined();
    expect(outcome!.kind === "error" || outcome!.kind === "malformed").toBe(
      true,
    );
    if (outcome!.kind === "error" || outcome!.kind === "malformed") {
      assertCanonicalErrorShape(outcome!.error);
    }
  });
});

describe("T-D5-06 truncated_response", () => {
  it("normalizes truncated provider response through the port without inventing a taxonomy code", () => {
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

    const outcome = invokeThroughPort(adapter, requestFixture);

    expect(
      outcome.kind === "truncation" || outcome.kind === "success",
    ).toBe(true);

    if (outcome.kind === "truncation" || outcome.kind === "success") {
      assertCanonicalResultShape(outcome.result);
      expect(outcome.result["finish reason"]).toBe("length");
    }
  });
});

describe("T-D5-07 timeout", () => {
  it("classifies adapter-owned deadline exceeded as taxonomy timeout with D2 retryability", () => {
    const harness = loadFixture<{ deadline_ms?: number }>(
      "timeout",
      "harness.json",
    );
    const secretStore = createRecordingSecretStore();
    const neverResolvingTransport: DeepSeekTransport = {
      fetch(_url, _init) {
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

    const outcome = invokeThroughPort(adapter, shortDeadlineRequest);
    const error = assertClassifiedError(outcome, "timeout");
    expect(error.retryability).toBe(true);
    expect(classifyFailure("timeout")).toBe("retryable");
  });
});

describe("T-D5-08 credentials_absent_from_logs_and_journal", () => {
  it("keeps the known secret absent from every collected log line and journal record", () => {
    const secretStore = createRecordingSecretStore();
    const logger = createRecordingLogger();
    const journal = createRecordingJournal();

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
      logger: logger.sink,
      journal: journal.sink,
    });
    invokeThroughPort(successAdapter, requestFixture);

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
      logger: logger.sink,
      journal: journal.sink,
    });
    invokeThroughPort(failureAdapter, requestFixture);

    assertSecretAbsentFromEmissions(KNOWN_SECRET, [
      ...logger.lines,
      ...journal.records,
    ]);
  });
});

describe("T-D5-10 adapter_owns_no_logging_policy", () => {
  it("does not own logging policy — no logging-policy API; credential emissions still satisfy T8", async () => {
    const deepseekModule = await import("../src/provider/deepseek");
    assertNoLoggingPolicyApi(Object.keys(deepseekModule));

    const secretStore = createRecordingSecretStore();
    const logger = createRecordingLogger();
    const journal = createRecordingJournal();
    const { transport } = createCapturingTransport(() => ({
      status: 200,
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        choices: [{ message: { content: "ok" }, finish_reason: "stop" }],
        usage: { prompt_tokens: 1, completion_tokens: 1 },
        id: "ds-logging-policy",
      }),
    }));

    const adapter = createDeepSeekAdapter({
      transport,
      secretStore: secretStore.store,
      logger: logger.sink,
      journal: journal.sink,
    });

    invokeThroughPort(adapter, requestFixture);

    assertSecretAbsentFromEmissions(KNOWN_SECRET, [
      ...logger.lines,
      ...journal.records,
    ]);
  });
});
