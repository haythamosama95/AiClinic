import { describe, expect, it, vi } from "vitest";
import {
  type CanonicalError,
  type CanonicalRequest,
  type CanonicalResult,
} from "../src/contracts/canonical";
import { ALL_TAXONOMY_CODES, type TaxonomyCode } from "../src/errors";
import { classifyFailure } from "../src/provider/classify";
import { FakeAdapter } from "../src/provider/fake";
import {
  type ProviderInvokeResult,
  type ProviderPort,
  type ScriptedOutcome,
} from "../src/provider/port";
import {
  BACKOFF_CAP_MS,
  computeJitteredBackoff,
  pureExponentialBackoffMs,
  runInvocation,
  type AttemptRecord,
  type InvocationInput,
  type InvocationSink,
} from "../src/invocation";
import {
  type ChainEntry,
  type RoutingDecision,
} from "../src/router";

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

const FIXTURE_REQUEST_ID = "req-d3-001";
const FIXTURE_IDEMPOTENCY_KEY = "idem-d3-001";

const PRIMARY_PROVIDER_ID = "fake-primary";
const FALLBACK_PROVIDER_ID = "fake-fallback";
const EXTRA_PROVIDER_ID = "fake-extra";

type SinkEvent =
  | { kind: "attempt"; record: AttemptRecord }
  | { kind: "regenerating" }
  | { kind: "stream_text"; text: string };

type AttemptSinkCollector = {
  sink: InvocationSink;
  attempts: AttemptRecord[];
  events: SinkEvent[];
};

type RecordingSleeper = {
  sleeper: (ms: number) => Promise<void>;
  delays: number[];
};

function defaultRequirements(): RoutingDecision["required_features"] {
  return {
    structured_output_required: false,
    min_context_window: 128_000,
    languages: ["en"],
    latency_class: "interactive",
  };
}

function chainEntry(
  ordinal: number,
  providerId: string,
  modelId: string,
  maxAttempts: number,
  timeoutMs = 30_000,
): ChainEntry {
  return {
    ordinal,
    provider_id: providerId,
    model_id: modelId,
    max_attempts: maxAttempts,
    timeout_ms: timeoutMs,
  };
}

function twoEntryChainFixture(
  primaryMaxAttempts = 3,
  fallbackMaxAttempts = 2,
): ChainEntry[] {
  return [
    chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", primaryMaxAttempts),
    chainEntry(1, FALLBACK_PROVIDER_ID, "fake-v2", fallbackMaxAttempts),
  ];
}

function routingDecisionFixture(chain: ChainEntry[]): RoutingDecision {
  return {
    policy_id: "policy-d3-fixture",
    policy_version: 1,
    rule_id: "rule-d3-fixture",
    effective_cost_class: "standard",
    cost_class_source: "manifest",
    routing_tier: "standard",
    required_features: defaultRequirements(),
    chain,
    excluded: [],
    max_parallel_attempts: 1,
  };
}

function createAttemptSink(): AttemptSinkCollector {
  const attempts: AttemptRecord[] = [];
  const events: SinkEvent[] = [];

  const sink: InvocationSink = {
    recordAttempt(record: AttemptRecord) {
      attempts.push(record);
      events.push({ kind: "attempt", record });
    },
    emitRegenerating() {
      events.push({ kind: "regenerating" });
    },
    emitStreamText(text: string) {
      events.push({ kind: "stream_text", text });
    },
  };

  return { sink, attempts, events };
}

function createRecordingSleeper(): RecordingSleeper {
  const delays: number[] = [];
  return {
    delays,
    sleeper: async (ms: number) => {
      delays.push(ms);
    },
  };
}

function createRetryableError(code: TaxonomyCode): CanonicalError {
  return {
    taxonomyCode: code,
    retryability: true,
    providerNative: {
      code: "HARNESS_ERROR",
      message: `Harness retryable ${code}`,
    },
    consumedBudget: false,
  };
}

/**
 * Test-only port double: returns partial stream chunks then a retryable/terminal
 * failure. Does not call the caller sink — the loop relays text via observing sink.
 */
function createPartialStreamHarness(
  partialText: string,
  failCode: TaxonomyCode,
): ProviderPort {
  return {
    async invoke(_request: CanonicalRequest): Promise<ProviderInvokeResult> {
      return {
        kind: "error",
        error: createRetryableError(failCode),
        chunks: [
          {
            kind: "text_delta",
            payload: { text: partialText },
            terminal: false,
            sequenceNumber: 0,
          },
        ],
      };
    },
  };
}

/** Terminal variant: same chunks, but a terminal taxonomy code. */
function createPartialStreamThenTerminalHarness(
  partialText: string,
  failCode: TaxonomyCode,
): ProviderPort {
  return {
    async invoke(_request: CanonicalRequest): Promise<ProviderInvokeResult> {
      return {
        kind: "error",
        error: {
          taxonomyCode: failCode,
          retryability: false,
          providerNative: {
            code: "HARNESS_TERMINAL",
            message: `Harness terminal ${failCode}`,
          },
          consumedBudget: false,
        },
        chunks: [
          {
            kind: "text_delta",
            payload: { text: partialText },
            terminal: false,
            sequenceNumber: 0,
          },
        ],
      };
    },
  };
}

type AdapterRegistry = Record<string, ProviderPort>;

function createPortResolver(
  adapters: AdapterRegistry,
  invokeSpy?: Record<string, number>,
): (providerId: string) => ProviderPort {
  return (providerId: string) => {
    if (invokeSpy) {
      invokeSpy[providerId] = (invokeSpy[providerId] ?? 0) + 1;
    }
    const adapter = adapters[providerId];
    if (!adapter) {
      throw new Error(`No adapter registered for provider_id ${providerId}`);
    }
    return adapter;
  };
}

function buildInvocationInput(options: {
  chain: ChainEntry[];
  adapters: AdapterRegistry;
  sink: InvocationSink;
  sleeper?: (ms: number) => Promise<void>;
  requestId?: string;
  idempotencyKey?: string;
  invokeSpy?: Record<string, number>;
  random?: () => number;
  request?: CanonicalRequest;
  signal?: AbortSignal;
  partialUsage?: InvocationInput["partialUsage"];
}): InvocationInput {
  return {
    request: options.request ?? requestFixture,
    routingDecision: routingDecisionFixture(options.chain),
    requestId: options.requestId ?? FIXTURE_REQUEST_ID,
    idempotencyKey: options.idempotencyKey ?? FIXTURE_IDEMPOTENCY_KEY,
    portResolver: createPortResolver(options.adapters, options.invokeSpy),
    sink: options.sink,
    sleeper: options.sleeper ?? (async () => {}),
    ...(options.random !== undefined ? { random: options.random } : {}),
    ...(options.signal !== undefined ? { signal: options.signal } : {}),
    ...(options.partialUsage !== undefined
      ? { partialUsage: options.partialUsage }
      : {}),
  };
}

function scriptedAdapter(outcomes: ScriptedOutcome[]): FakeAdapter {
  return new FakeAdapter(outcomes);
}

function finalText(result: CanonicalResult): string {
  const content = result.finalContent;
  if (
    typeof content === "object" &&
    content !== null &&
    "text" in content &&
    typeof (content as { text: unknown }).text === "string"
  ) {
    return (content as { text: string }).text;
  }
  return "";
}

const TERMINAL_TAXONOMY_CODES = ALL_TAXONOMY_CODES.filter(
  (code) => classifyFailure(code) === "terminal",
);

describe("T-D3-08 first_attempt_success_no_fallback", () => {
  it("succeeds on the first attempt with selection_reason primary and no fallback", async () => {
    const chain = twoEntryChainFixture();
    const collector = createAttemptSink();
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter(["success"]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    expect(collector.attempts).toHaveLength(1);
    expect(collector.attempts[0]).toMatchObject({
      attempt_no: 1,
      provider_id: PRIMARY_PROVIDER_ID,
      model_id: "fake-v1",
      selection_reason: "primary",
      outcome: "success",
      request_id: FIXTURE_REQUEST_ID,
      idempotency_key: FIXTURE_IDEMPOTENCY_KEY,
    });
    expect(
      collector.attempts.some((attempt) => attempt.provider_id === FALLBACK_PROVIDER_ID),
    ).toBe(false);
  });
});

describe("T-D3-01 retryable_retried_to_cap_then_fallback", () => {
  it("retries the first target to max_attempts then falls back with correct selection reasons", async () => {
    const chain = twoEntryChainFixture(3, 2);
    const collector = createAttemptSink();
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
        "retryable:internal_error",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    expect(collector.attempts).toHaveLength(4);

    const primaryAttempts = collector.attempts.filter(
      (attempt) => attempt.provider_id === PRIMARY_PROVIDER_ID,
    );
    expect(primaryAttempts).toHaveLength(3);
    for (const attempt of primaryAttempts) {
      expect(attempt.selection_reason).toBe("primary");
      expect(attempt.outcome).toBe("retryable_failure");
    }

    const fallbackAttempts = collector.attempts.filter(
      (attempt) => attempt.provider_id === FALLBACK_PROVIDER_ID,
    );
    expect(fallbackAttempts).toHaveLength(1);
    expect(fallbackAttempts[0]).toMatchObject({
      selection_reason: "fallback_after_retryable_error",
      outcome: "success",
    });
  });
});

describe("T-D3-03 jitter_applied_on_backoff", () => {
  it("applies jitter so recorded delays differ from pure exponential and stay within cap", async () => {
    const chain = [chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 3)];
    const collector = createAttemptSink();
    const recording = createRecordingSleeper();
    const fixedRandom = () => 0.5;
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
        "success",
      ]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        sleeper: recording.sleeper,
        random: fixedRandom,
      }),
    );

    expect(result.ok).toBe(true);
    expect(recording.delays.length).toBeGreaterThanOrEqual(2);

    const differsFromPure = recording.delays.some(
      (delay, index) => delay !== pureExponentialBackoffMs(index),
    );
    expect(differsFromPure).toBe(true);

    for (const delay of recording.delays) {
      expect(delay).toBeLessThanOrEqual(BACKOFF_CAP_MS);
    }

    expect(recording.delays[0]).toBe(computeJitteredBackoff(0, fixedRandom));
    expect(recording.delays[1]).toBe(computeJitteredBackoff(1, fixedRandom));
  });
});

describe("T-D3-07 retry_budget_never_exceeded", () => {
  it("never invokes a target more than its max_attempts under any failure script", async () => {
    const chain = twoEntryChainFixture(2, 2);
    const collector = createAttemptSink();
    const invokeSpy: Record<string, number> = {};
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
        "retryable:internal_error",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter([
        "retryable:timeout",
        "retryable:timeout",
        "retryable:timeout",
      ]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        invokeSpy,
      }),
    );

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.error.taxonomyCode).toBe("provider_unavailable");
    expect(invokeSpy[PRIMARY_PROVIDER_ID]).toBe(2);
    expect(invokeSpy[FALLBACK_PROVIDER_ID]).toBe(2);
    expect(collector.attempts).toHaveLength(4);
  });
});

describe("T-D3-12 internal_retry_same_request_not_user_retry", () => {
  it("journals the same request_id and idempotency_key on every attempt record", async () => {
    const chain = twoEntryChainFixture(3, 2);
    const collector = createAttemptSink();
    const requestId = "req-internal-retry-42";
    const idempotencyKey = "idem-internal-retry-42";
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
        "retryable:internal_error",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        requestId,
        idempotencyKey,
      }),
    );

    expect(result.ok).toBe(true);
    expect(collector.attempts.length).toBeGreaterThan(1);
    for (const attempt of collector.attempts) {
      expect(attempt.request_id).toBe(requestId);
      expect(attempt.idempotency_key).toBe(idempotencyKey);
    }
  });
});

describe("T-D3-02 terminal_failure_not_retried", () => {
  it("does not retry or fall back after a terminal adapter-classified failure", async () => {
    const chain = twoEntryChainFixture();
    const collector = createAttemptSink();
    const invokeSpy: Record<string, number> = {};
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter(["terminal:provider_rejected"]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        invokeSpy,
      }),
    );

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.error.taxonomyCode).toBe("provider_rejected");
    expect(collector.attempts).toHaveLength(1);
    expect(collector.attempts[0]).toMatchObject({
      provider_id: PRIMARY_PROVIDER_ID,
      outcome: "terminal_failure",
      error_code: "provider_rejected",
    });
    expect(invokeSpy[PRIMARY_PROVIDER_ID]).toBe(1);
    expect(invokeSpy[FALLBACK_PROVIDER_ID]).toBeUndefined();
  });
});

describe("T-D3-05 exhausted_chain_provider_unavailable", () => {
  it("fails with provider_unavailable when every chain target exhausts retryable attempts", async () => {
    const chain = twoEntryChainFixture(2, 2);
    const collector = createAttemptSink();
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
      ]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.error.taxonomyCode).toBe("provider_unavailable");
    expect(collector.attempts).toHaveLength(4);
  });
});

describe("T-D3-09 timeout_exhaustion_fallback_reason", () => {
  it("records fallback_after_timeout when the prior target exhausted via timeout failures", async () => {
    const chain = twoEntryChainFixture(2, 2);
    const collector = createAttemptSink();
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:timeout",
        "retryable:timeout",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    const fallbackAttempt = collector.attempts.find(
      (attempt) => attempt.provider_id === FALLBACK_PROVIDER_ID,
    );
    expect(fallbackAttempt).toBeDefined();
    expect(fallbackAttempt?.selection_reason).toBe("fallback_after_timeout");
    expect(
      collector.attempts
        .filter((attempt) => attempt.provider_id === PRIMARY_PROVIDER_ID)
        .every((attempt) => attempt.outcome === "timeout"),
    ).toBe(true);
  });
});

describe("T-D3-10 fallback_only_walks_given_chain", () => {
  it("invokes only router-supplied chain targets and never widens beyond the given chain", async () => {
    const chain = twoEntryChainFixture(2, 1);
    const collector = createAttemptSink();
    const invokeSpy: Record<string, number> = {};
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
      [EXTRA_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        invokeSpy,
      }),
    );

    expect(result.ok).toBe(true);
    expect(invokeSpy[PRIMARY_PROVIDER_ID]).toBe(2);
    expect(invokeSpy[FALLBACK_PROVIDER_ID]).toBe(1);
    expect(invokeSpy[EXTRA_PROVIDER_ID]).toBeUndefined();
    const invokedProviderIds = new Set(
      collector.attempts.map((attempt) => attempt.provider_id),
    );
    expect(invokedProviderIds).toEqual(
      new Set([PRIMARY_PROVIDER_ID, FALLBACK_PROVIDER_ID]),
    );
  });
});

describe("T-D3-11 no_provider_history_consulted", () => {
  it("never accepts or consults a provider-history store; walk is chain-only", async () => {
    const chain = twoEntryChainFixture(2, 1);
    const collector = createAttemptSink();
    const localHistoryStore = {
      getProviderHealth: vi.fn(() => ({ healthy: true })),
      getRecentFailures: vi.fn(() => []),
      isCircuitOpen: vi.fn(() => false),
    };
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const input = buildInvocationInput({
      chain,
      adapters,
      sink: collector.sink,
    });

    expect(Object.prototype.hasOwnProperty.call(input, "providerHistoryStore")).toBe(
      false,
    );
    expect("providerHistoryStore" in input).toBe(false);

    const result = await runInvocation(input);

    expect(result.ok).toBe(true);
    expect(localHistoryStore.getProviderHealth).not.toHaveBeenCalled();
    expect(localHistoryStore.getRecentFailures).not.toHaveBeenCalled();
    expect(localHistoryStore.isCircuitOpen).not.toHaveBeenCalled();

    const invokedProviderIds = collector.attempts.map((a) => a.provider_id);
    expect(invokedProviderIds).toEqual([
      PRIMARY_PROVIDER_ID,
      PRIMARY_PROVIDER_ID,
      FALLBACK_PROVIDER_ID,
    ]);
  });
});

describe("T-D3-13 repair_retry_reason_not_emitted", () => {
  it("never records selection_reason repair_retry under retry and fallback scripts", async () => {
    const chain = twoEntryChainFixture(3, 2);
    const collector = createAttemptSink();
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:timeout",
        "retryable:internal_error",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "success",
      ]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    for (const attempt of collector.attempts) {
      expect(attempt.selection_reason).not.toBe("repair_retry");
    }
  });
});

describe("T-D3-04 every_attempt_journaled_separately", () => {
  it("feeds exactly one sink attempt record per provider invoke", async () => {
    const chain = twoEntryChainFixture(3, 2);
    const collector = createAttemptSink();
    const invokeSpy: Record<string, number> = {};
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
        "retryable:internal_error",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        invokeSpy,
      }),
    );

    expect(result.ok).toBe(true);
    const totalInvokes =
      (invokeSpy[PRIMARY_PROVIDER_ID] ?? 0) +
      (invokeSpy[FALLBACK_PROVIDER_ID] ?? 0);
    expect(totalInvokes).toBe(4);
    expect(collector.attempts).toHaveLength(4);
    expect(collector.attempts.map((attempt) => attempt.attempt_no)).toEqual([
      1,
      2,
      3,
      4,
    ]);
  });
});

describe("T-D3-06 fallback_after_partial_stream_emits_regenerating", () => {
  it("emits regenerating exactly once before the fallback provider's first output", async () => {
    // max_attempts=1 so only the chain-boundary regenerating fires (same-target
    // regenerating after partial is covered by T-D3-R-13).
    const chain = twoEntryChainFixture(1, 2);
    const collector = createAttemptSink();
    const partialText = "Partial streamed text from primary.";
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: createPartialStreamHarness(
        partialText,
        "internal_error",
      ),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    if (!result.ok) {
      return;
    }

    const regeneratingIndexes = collector.events
      .map((event, index) => (event.kind === "regenerating" ? index : -1))
      .filter((index) => index >= 0);
    expect(regeneratingIndexes).toHaveLength(1);

    const regeneratingIndex = regeneratingIndexes[0];
    const firstFallbackEventIndex = collector.events.findIndex(
      (event) =>
        (event.kind === "attempt" &&
          event.record.provider_id === FALLBACK_PROVIDER_ID) ||
        (event.kind === "stream_text" &&
          event.text === "Fake adapter summary."),
    );
    expect(firstFallbackEventIndex).toBeGreaterThan(-1);
    expect(regeneratingIndex).toBeLessThan(firstFallbackEventIndex);

    expect(
      collector.events.some(
        (event) => event.kind === "stream_text" && event.text === partialText,
      ),
    ).toBe(true);

    const finalContent = finalText(result.result);
    expect(finalContent).not.toContain(partialText);
    expect(finalContent).toBe("Fake adapter summary.");

    const fallbackAttempts = collector.attempts.filter(
      (attempt) => attempt.provider_id === FALLBACK_PROVIDER_ID,
    );
    expect(fallbackAttempts).toHaveLength(1);
    expect(fallbackAttempts[0].outcome).toBe("success");
  });
});

describe("T-D3-R-01 regenerating_absent_without_prior_chunks", () => {
  it("does not emit regenerating on fallback when the prior target streamed no text", async () => {
    const chain = twoEntryChainFixture(2, 1);
    const collector = createAttemptSink();
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    expect(
      collector.events.some((event) => event.kind === "regenerating"),
    ).toBe(false);
    expect(
      collector.attempts.some(
        (attempt) => attempt.provider_id === FALLBACK_PROVIDER_ID,
      ),
    ).toBe(true);
  });
});

describe("T-D3-R-02 regenerating_absent_after_partial_then_terminal", () => {
  it("does not emit regenerating when partial chunks precede a terminal failure (no fallback)", async () => {
    const chain = twoEntryChainFixture(2, 2);
    const collector = createAttemptSink();
    const partialText = "Partial then terminal.";
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: createPartialStreamThenTerminalHarness(
        partialText,
        "provider_rejected",
      ),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.error.taxonomyCode).toBe("provider_rejected");
    expect(
      collector.events.some((event) => event.kind === "regenerating"),
    ).toBe(false);
    expect(
      collector.events.some(
        (event) => event.kind === "stream_text" && event.text === partialText,
      ),
    ).toBe(true);
    expect(
      collector.attempts.some(
        (attempt) => attempt.provider_id === FALLBACK_PROVIDER_ID,
      ),
    ).toBe(false);
  });
});

describe("T-D3-R-03 empty_chain_provider_unavailable", () => {
  it("fails with provider_unavailable and zero attempts when the chain is empty", async () => {
    const collector = createAttemptSink();
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain: [],
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.error.taxonomyCode).toBe("provider_unavailable");
    expect(collector.attempts).toHaveLength(0);
  });
});

describe("T-D3-R-04 max_attempts_one_no_sleeper", () => {
  it("invokes once with no sleeper calls then falls back when max_attempts is 1", async () => {
    const chain = [
      chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 1),
      chainEntry(1, FALLBACK_PROVIDER_ID, "fake-v2", 1),
    ];
    const collector = createAttemptSink();
    const recording = createRecordingSleeper();
    const invokeSpy: Record<string, number> = {};
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter(["retryable:internal_error"]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        sleeper: recording.sleeper,
        invokeSpy,
      }),
    );

    expect(result.ok).toBe(true);
    expect(invokeSpy[PRIMARY_PROVIDER_ID]).toBe(1);
    expect(invokeSpy[FALLBACK_PROVIDER_ID]).toBe(1);
    expect(recording.delays).toHaveLength(0);
    expect(collector.attempts[1]?.selection_reason).toBe(
      "fallback_after_retryable_error",
    );
  });
});

describe("T-D3-R-05 truncation_outcome_distinct_from_success", () => {
  it("journals truncation as outcome truncation and returns ok", async () => {
    const chain = [chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 1)];
    const collector = createAttemptSink();
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter(["truncation"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    expect(collector.attempts).toHaveLength(1);
    expect(collector.attempts[0].outcome).toBe("truncation");
    expect(collector.attempts[0].outcome).not.toBe("success");
  });
});

describe("T-D3-R-06 malformed_through_loop", () => {
  it("journals malformed as retryable_failure and retries or falls back", async () => {
    const chain = twoEntryChainFixture(2, 1);
    const collector = createAttemptSink();
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter(["malformed", "malformed"]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    const primaryAttempts = collector.attempts.filter(
      (attempt) => attempt.provider_id === PRIMARY_PROVIDER_ID,
    );
    expect(primaryAttempts).toHaveLength(2);
    for (const attempt of primaryAttempts) {
      expect(attempt.outcome).toBe("retryable_failure");
      expect(attempt.error_code).toBe("internal_error");
    }
    expect(collector.attempts[2]?.selection_reason).toBe(
      "fallback_after_retryable_error",
    );
  });
});

describe("T-D3-R-07 every_terminal_taxonomy_code_not_retried", () => {
  it.each(TERMINAL_TAXONOMY_CODES)(
    "does not retry terminal code %s",
    async (code) => {
      const chain = twoEntryChainFixture(3, 2);
      const collector = createAttemptSink();
      const invokeSpy: Record<string, number> = {};
      const adapters: AdapterRegistry = {
        [PRIMARY_PROVIDER_ID]: scriptedAdapter([`terminal:${code}`]),
        [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
      };

      const result = await runInvocation(
        buildInvocationInput({
          chain,
          adapters,
          sink: collector.sink,
          invokeSpy,
        }),
      );

      expect(result.ok).toBe(false);
      if (result.ok) {
        return;
      }
      expect(result.error.taxonomyCode).toBe(code);
      expect(collector.attempts).toHaveLength(1);
      expect(collector.attempts[0]).toMatchObject({
        outcome: "terminal_failure",
        error_code: code,
      });
      expect(invokeSpy[PRIMARY_PROVIDER_ID]).toBe(1);
      expect(invokeSpy[FALLBACK_PROVIDER_ID]).toBeUndefined();
    },
  );
});

describe("T-D3-R-08 mixed_script_fallback_after_timeout", () => {
  it("records fallback_after_timeout when the exhausting failure was timeout (§8.6)", async () => {
    const chain = twoEntryChainFixture(2, 1);
    const collector = createAttemptSink();
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:timeout",
      ]),
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    expect(collector.attempts[0]).toMatchObject({
      outcome: "retryable_failure",
      error_code: "internal_error",
    });
    expect(collector.attempts[1]).toMatchObject({
      outcome: "timeout",
      error_code: "timeout",
    });
    expect(collector.attempts[2]).toMatchObject({
      provider_id: FALLBACK_PROVIDER_ID,
      selection_reason: "fallback_after_timeout",
      outcome: "success",
    });
  });
});

describe("T-D3-R-09 timeout_ms_enforced_on_hung_port", () => {
  it("times out a hung port and yields timeout / provider_unavailable", async () => {
    const chain = [chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 1, 20)];
    const collector = createAttemptSink();
    const hungPort: ProviderPort = {
      async invoke() {
        return new Promise(() => {});
      },
    };
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: hungPort,
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.error.taxonomyCode).toBe("provider_unavailable");
    expect(collector.attempts).toHaveLength(1);
    expect(collector.attempts[0]).toMatchObject({
      outcome: "timeout",
      error_code: "timeout",
    });
  });

  it("falls back after hung primary timeout when a second chain entry exists", async () => {
    const chain = [
      chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 1, 20),
      chainEntry(1, FALLBACK_PROVIDER_ID, "fake-v2", 1, 30_000),
    ];
    const collector = createAttemptSink();
    const hungPort: ProviderPort = {
      async invoke() {
        return new Promise(() => {});
      },
    };
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: hungPort,
      [FALLBACK_PROVIDER_ID]: scriptedAdapter(["success"]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    expect(collector.attempts[0]).toMatchObject({
      provider_id: PRIMARY_PROVIDER_ID,
      outcome: "timeout",
    });
    expect(collector.attempts[1]).toMatchObject({
      provider_id: FALLBACK_PROVIDER_ID,
      selection_reason: "fallback_after_timeout",
      outcome: "success",
    });
  });
});

describe("T-D3-R-10 deadline_truncates_backoff_sleeps", () => {
  it("truncates or skips sleeper delays so they do not exceed the remaining deadline budget", async () => {
    const chain = [chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 3)];
    const collector = createAttemptSink();
    const recording = createRecordingSleeper();
    const tinyDeadlineMs = 40;
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: scriptedAdapter([
        "retryable:internal_error",
        "retryable:internal_error",
        "success",
      ]),
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        sleeper: recording.sleeper,
        random: () => 0.5,
        request: { ...requestFixture, deadline: tinyDeadlineMs },
      }),
    );

    expect(result.ok).toBe(true);
    const uncappedFirst = computeJitteredBackoff(0, () => 0.5);
    expect(uncappedFirst).toBeGreaterThan(tinyDeadlineMs);

    for (const delay of recording.delays) {
      expect(delay).toBeLessThanOrEqual(tinyDeadlineMs);
    }
  });
});

describe("T-D3-R-11 backoff_cap_unit", () => {
  it("caps computeJitteredBackoff at BACKOFF_CAP_MS for large retry indexes", () => {
    expect(BACKOFF_CAP_MS).toBe(10_000);
    expect(computeJitteredBackoff(20, () => 1)).toBeLessThanOrEqual(
      BACKOFF_CAP_MS,
    );
    expect(computeJitteredBackoff(20, () => 1)).toBe(BACKOFF_CAP_MS);
  });
});

describe("T-D3-R-12 caller_abort_terminal_cancelled (§2.4)", () => {
  it("classifies already-aborted caller signal as terminal cancelled, not timeout", async () => {
    const chain = [chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 1, 30_000)];
    const collector = createAttemptSink();
    const controller = new AbortController();
    controller.abort();
    let sawSignal = false;
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: {
        async invoke(_request, options) {
          sawSignal = options?.signal !== undefined;
          return new Promise(() => {});
        },
      },
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        signal: controller.signal,
      }),
    );

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.error.taxonomyCode).toBe("cancelled");
    // Already-aborted at entry returns cancelled with no attempts started.
    expect(collector.attempts).toHaveLength(0);
    expect(sawSignal).toBe(false);
  });

  it("aborts an in-flight hung invoke via caller signal as cancelled", async () => {
    const chain = [chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 1, 30_000)];
    const collector = createAttemptSink();
    const controller = new AbortController();
    let invokeSignal: AbortSignal | undefined;
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: {
        async invoke(_request, options) {
          invokeSignal = options?.signal;
          return new Promise(() => {});
        },
      },
    };

    const runPromise = runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        signal: controller.signal,
      }),
    );

    await new Promise((r) => setTimeout(r, 15));
    controller.abort();
    const result = await runPromise;

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.error.taxonomyCode).toBe("cancelled");
    expect(invokeSignal?.aborted).toBe(true);
    expect(collector.attempts[0]?.error_code).toBe("cancelled");
  });

  it("exposes a live partialUsage accessor reflecting streamed chars before cancel", async () => {
    const collector = createAttemptSink();
    const controller = new AbortController();
    const partialUsage: InvocationInput["partialUsage"] = {};
    const partialText = "Partial before cancel";
    const emitThenHang: ProviderPort = {
      async invoke() {
        return {
          kind: "error",
          error: createRetryableError("internal_error"),
          chunks: [
            {
              kind: "text_delta",
              payload: { text: partialText },
              terminal: false,
              sequenceNumber: 0,
            },
          ],
        };
      },
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain: [chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 2, 30_000)],
        adapters: { [PRIMARY_PROVIDER_ID]: emitThenHang },
        sink: collector.sink,
        signal: controller.signal,
        partialUsage,
        sleeper: async () => {
          // Abort during inter-retry sleep after partial was relayed.
          controller.abort();
        },
      }),
    );

    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.error.taxonomyCode).toBe("cancelled");
    expect(partialUsage.getPartialUsage).toBeTypeOf("function");
    expect(partialUsage.getPartialUsage?.()).toEqual({
      tokens: partialText.length,
      cost: partialText.length * 0.001,
    });
    expect(
      collector.events.some(
        (e) => e.kind === "stream_text" && e.text === partialText,
      ),
    ).toBe(true);
  });
});

describe("T-D3-R-13 same_target_retry_emits_regenerating (§3.2.1)", () => {
  it("emits regenerating before the same-target retry after a partial stream", async () => {
    const chain = [chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 2)];
    const collector = createAttemptSink();
    const partialText = "First attempt partial.";
    let invokeCount = 0;
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: {
        async invoke(): Promise<ProviderInvokeResult> {
          invokeCount++;
          if (invokeCount === 1) {
            return {
              kind: "error",
              error: createRetryableError("internal_error"),
              chunks: [
                {
                  kind: "text_delta",
                  payload: { text: partialText },
                  terminal: false,
                  sequenceNumber: 0,
                },
              ],
            };
          }
          return scriptedAdapter(["success"]).invoke(requestFixture);
        },
      },
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
      }),
    );

    expect(result.ok).toBe(true);
    const regeneratingIndexes = collector.events
      .map((event, index) => (event.kind === "regenerating" ? index : -1))
      .filter((index) => index >= 0);
    expect(regeneratingIndexes).toHaveLength(1);

    const partialIndex = collector.events.findIndex(
      (e) => e.kind === "stream_text" && e.text === partialText,
    );
    const regeneratingIndex = regeneratingIndexes[0];
    const successTextIndex = collector.events.findIndex(
      (e) => e.kind === "stream_text" && e.text === "Fake adapter summary.",
    );
    expect(partialIndex).toBeGreaterThanOrEqual(0);
    expect(regeneratingIndex).toBeGreaterThan(partialIndex);
    expect(successTextIndex).toBeGreaterThan(regeneratingIndex);
  });
});

describe("T-D3-R-14 deadline_clamps_attempt_timeout (§3.2.5)", () => {
  it("clamps each attempt timeout to remaining deadline and skips exhausted targets", async () => {
    const deadlineMs = 50;
    const chain = [
      chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 1, 30_000),
      chainEntry(1, FALLBACK_PROVIDER_ID, "fake-v2", 1, 30_000),
    ];
    const collector = createAttemptSink();
    const invokeSpy: Record<string, number> = {};
    const seenTimeouts: number[] = [];
    const seenDeadlines: number[] = [];

    const makePort = (providerId: string): ProviderPort => ({
      async invoke(request, options) {
        invokeSpy[providerId] = (invokeSpy[providerId] ?? 0) + 1;
        seenDeadlines.push(request.deadline ?? -1);
        await new Promise<void>((resolve) => {
          const signal = options?.signal;
          if (signal?.aborted) {
            resolve();
            return;
          }
          const started = Date.now();
          signal?.addEventListener(
            "abort",
            () => {
              seenTimeouts.push(Date.now() - started);
              resolve();
            },
            { once: true },
          );
        });
        return {
          kind: "error",
          error: createRetryableError("timeout"),
        };
      },
    });

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters: {
          [PRIMARY_PROVIDER_ID]: makePort(PRIMARY_PROVIDER_ID),
          [FALLBACK_PROVIDER_ID]: makePort(FALLBACK_PROVIDER_ID),
        },
        sink: collector.sink,
        request: { ...requestFixture, deadline: deadlineMs },
      }),
    );

    expect(result.ok).toBe(false);
    expect(invokeSpy[PRIMARY_PROVIDER_ID]).toBe(1);
    expect(seenDeadlines[0]).toBeLessThanOrEqual(deadlineMs);
    expect(seenDeadlines[0]).toBeGreaterThan(0);
    expect(seenTimeouts[0]).toBeLessThan(deadlineMs + 80);
    expect(invokeSpy[FALLBACK_PROVIDER_ID] ?? 0).toBeLessThanOrEqual(1);
    if (invokeSpy[FALLBACK_PROVIDER_ID]) {
      expect(seenDeadlines[1]).toBeLessThanOrEqual(deadlineMs);
    }
  });
});

describe("T-D3-R-15 retry_after_ms_honored (§3.2.4)", () => {
  it("sleeps max(jitteredBackoff, retryAfterMs) clamped by the deadline", async () => {
    const chain = [chainEntry(0, PRIMARY_PROVIDER_ID, "fake-v1", 2)];
    const collector = createAttemptSink();
    const recording = createRecordingSleeper();
    const fixedRandom = () => 0.5;
    const retryAfterMs = 2_500;
    let invokeCount = 0;
    const adapters: AdapterRegistry = {
      [PRIMARY_PROVIDER_ID]: {
        async invoke(): Promise<ProviderInvokeResult> {
          invokeCount++;
          if (invokeCount === 1) {
            const error = {
              ...createRetryableError("rate_limited"),
              retryAfterMs,
            } as CanonicalError & { retryAfterMs: number };
            return { kind: "error", error };
          }
          return scriptedAdapter(["success"]).invoke(requestFixture);
        },
      },
    };

    const result = await runInvocation(
      buildInvocationInput({
        chain,
        adapters,
        sink: collector.sink,
        sleeper: recording.sleeper,
        random: fixedRandom,
      }),
    );

    expect(result.ok).toBe(true);
    const jittered = computeJitteredBackoff(0, fixedRandom);
    expect(jittered).toBeLessThan(retryAfterMs);
    expect(recording.delays).toEqual([retryAfterMs]);
  });
});
