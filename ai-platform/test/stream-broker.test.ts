import { afterEach, describe, expect, it, vi } from "vitest";
import type { AdapterSseEvent } from "../src/adapter";
import { isTaxonomyCode, type TaxonomyCode } from "../src/errors";
import * as journalModule from "../src/journal/index";
import {
  createChunkSourceFromInvocationEvents,
  createStreamBroker,
  type ChunkSource,
  type CreditSink,
  type HeartbeatTicker,
  type JournalTerminalSink,
  type ProseGuardThresholds,
  type StreamBrokerController,
  type StreamBrokerEventSink,
  type StreamBrokerOptions,
} from "../src/stream";
import * as proseGuards from "../src/stream/prose-guards";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const TERMINAL_EVENT_KINDS = ["completed", "failed", "cancelled"] as const;

const FIXTURE_TRACE_ID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
const FIXTURE_REQUEST_ID = "req-d4-001";

/** Injectable guard thresholds — test parameters, not broker constants. */
const GUARD_THRESHOLDS: ProseGuardThresholds = {
  maxLength: 20,
  stopSequences: ["<|end|>"],
  systemPromptLeakNeedle: "SYSTEM_PROMPT_LEAK_TEST_NEEDLE",
};

const STREAM_BROKER_OPTION_KEYS = [
  "traceId",
  "requestId",
  "eventSink",
  "chunkSource",
  "heartbeatTicker",
  "creditSink",
  "journalTerminalSink",
  "guardThresholds",
] as const;

type EventSinkCollector = {
  sink: StreamBrokerEventSink;
  events: AdapterSseEvent[];
};

type CreditSinkSpy = {
  sink: CreditSink;
  calls: Array<{
    requestId: string;
    usage: { tokens: number; cost: number };
    partial: boolean;
  }>;
};

type JournalTerminalSinkSpy = {
  sink: JournalTerminalSink;
  records: Array<{
    requestId: string;
    state: "cancelled" | "completed" | "failed";
    terminalErrorCode?: TaxonomyCode;
  }>;
};

type ControllableHeartbeatTicker = HeartbeatTicker & {
  triggerSilentGap(): void;
  notifyActivityCallCount: () => number;
};

function usageFromTokens(tokens: number): { tokens: number; cost: number } {
  return { tokens, cost: tokens * 0.001 };
}

function expectedUsageForChunks(chunks: string[]): {
  tokens: number;
  cost: number;
} {
  const tokens = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  return usageFromTokens(tokens);
}

function isTerminalEventType(type: string): boolean {
  return (TERMINAL_EVENT_KINDS as readonly string[]).includes(type);
}

function countTerminalEvents(events: AdapterSseEvent[]): number {
  return events.filter((event) => isTerminalEventType(event.type)).length;
}

function eventsOfType(events: AdapterSseEvent[], type: string): AdapterSseEvent[] {
  return events.filter((event) => event.type === type);
}

function createEventSinkCollector(): EventSinkCollector {
  const events: AdapterSseEvent[] = [];
  const sink: StreamBrokerEventSink = {
    push(event: AdapterSseEvent) {
      events.push(event);
    },
  };
  return { sink, events };
}

function createControllableHeartbeatTicker(): ControllableHeartbeatTicker {
  let onHeartbeat: (() => void) | null = null;
  let activitySinceScheduleOrGap = false;
  let notifyActivityCalls = 0;

  return {
    schedule(callback: () => void) {
      onHeartbeat = callback;
      activitySinceScheduleOrGap = false;
      return {
        cancel() {
          onHeartbeat = null;
        },
        notifyActivity() {
          notifyActivityCalls += 1;
          activitySinceScheduleOrGap = true;
        },
      };
    },
    triggerSilentGap() {
      if (!activitySinceScheduleOrGap) {
        onHeartbeat?.();
      }
      activitySinceScheduleOrGap = false;
    },
    notifyActivityCallCount() {
      return notifyActivityCalls;
    },
  };
}

function createCreditSinkSpy(): CreditSinkSpy {
  const calls: CreditSinkSpy["calls"] = [];
  const sink: CreditSink = (input) => {
    calls.push(input);
  };
  return { sink, calls };
}

function createJournalTerminalSinkSpy(): JournalTerminalSinkSpy {
  const records: JournalTerminalSinkSpy["records"] = [];
  const sink: JournalTerminalSink = (record) => {
    records.push(record);
  };
  return { sink, records };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

/**
 * Live getPartialUsage: tokens = sum of yielded chunk lengths so far;
 * cost = tokens * 0.001. Returns undefined when nothing has been yielded.
 */
function createScriptedChunkSource(
  chunks: string[],
  options: {
    delayMs?: number;
  } = {},
): ChunkSource {
  const delayMs = options.delayMs ?? 0;
  let yieldedTokens = 0;

  return {
    getPartialUsage() {
      if (yieldedTokens === 0) {
        return undefined;
      }
      return usageFromTokens(yieldedTokens);
    },
    async *stream({ signal }: { signal: AbortSignal }) {
      for (const chunk of chunks) {
        if (delayMs > 0) {
          await delay(delayMs);
        }
        if (signal.aborted) {
          return;
        }
        yieldedTokens += chunk.length;
        yield chunk;
      }
    },
  };
}

function createSilentChunkSource(): ChunkSource {
  return {
    getPartialUsage() {
      return undefined;
    },
    async *stream({ signal }: { signal: AbortSignal }) {
      while (!signal.aborted) {
        await delay(10);
      }
    },
  };
}

function abortError(): Error {
  if (typeof DOMException !== "undefined") {
    return new DOMException("The operation was aborted.", "AbortError");
  }
  return Object.assign(new Error("The operation was aborted."), {
    name: "AbortError",
  });
}

/**
 * Yields the given chunks, then hangs until abort and throws AbortError
 * (does not return gracefully). Keeps the stream open after the last chunk
 * so mid-stream disconnect cannot race a premature `completed`.
 */
function createAbortRejectingChunkSource(
  chunks: string[] = ["pre-abort"],
  options: { delayMs?: number } = {},
): ChunkSource {
  const delayMs = options.delayMs ?? 30;
  let yieldedTokens = 0;

  return {
    getPartialUsage() {
      if (yieldedTokens === 0) {
        return undefined;
      }
      return usageFromTokens(yieldedTokens);
    },
    async *stream({ signal }: { signal: AbortSignal }) {
      for (const chunk of chunks) {
        if (delayMs > 0) {
          await delay(delayMs);
        }
        if (signal.aborted) {
          throw abortError();
        }
        yieldedTokens += chunk.length;
        yield chunk;
      }
      while (!signal.aborted) {
        await delay(10);
      }
      throw abortError();
    },
  };
}

/** Yields one chunk then throws a non-abort Error. */
function createThrowingChunkSource(error: Error): ChunkSource {
  let yieldedTokens = 0;

  return {
    getPartialUsage() {
      if (yieldedTokens === 0) {
        return undefined;
      }
      return usageFromTokens(yieldedTokens);
    },
    async *stream() {
      const chunk = "before-throw";
      yieldedTokens += chunk.length;
      yield chunk;
      throw error;
    },
  };
}

/** Loops forever ignoring abort — for disconnect-sync-cancel proof. */
function createSignalIgnoringChunkSource(): ChunkSource {
  return {
    getPartialUsage() {
      return undefined;
    },
    async *stream() {
      while (true) {
        await delay(50);
        yield "ignored";
      }
    },
  };
}

type RunBrokerHarnessOptions = {
  chunkSource?: ChunkSource;
  chunks?: string[];
  chunkDelayMs?: number;
  guardThresholds?: ProseGuardThresholds;
  heartbeatTicker?: ControllableHeartbeatTicker;
  creditSink?: CreditSink;
  journalTerminalSink?: JournalTerminalSink;
  disconnect?:
    | { kind: "before_first_token" }
    | { kind: "after_first_delta" }
    | { kind: "network_drop"; afterMs?: number }
    | { kind: "client_close"; afterMs?: number };
};

type RunBrokerHarnessResult = {
  events: AdapterSseEvent[];
  controller: StreamBrokerController;
  creditSpy: CreditSinkSpy;
  journalSpy: JournalTerminalSinkSpy;
  heartbeatTicker: ControllableHeartbeatTicker;
  brokerOptions: StreamBrokerOptions;
};

async function runBrokerHarness(
  options: RunBrokerHarnessOptions = {},
): Promise<RunBrokerHarnessResult> {
  const collector = createEventSinkCollector();
  const creditSpy = createCreditSinkSpy();
  const journalSpy = createJournalTerminalSinkSpy();
  const heartbeatTicker =
    options.heartbeatTicker ?? createControllableHeartbeatTicker();

  const chunkSource =
    options.chunkSource ??
    createScriptedChunkSource(options.chunks ?? ["Hello", " world"], {
      delayMs: options.chunkDelayMs ?? 0,
    });

  const brokerOptions: StreamBrokerOptions = {
    traceId: FIXTURE_TRACE_ID,
    requestId: FIXTURE_REQUEST_ID,
    eventSink: collector.sink,
    chunkSource,
    heartbeatTicker,
    creditSink: options.creditSink ?? creditSpy.sink,
    journalTerminalSink: options.journalTerminalSink ?? journalSpy.sink,
    guardThresholds: options.guardThresholds ?? GUARD_THRESHOLDS,
  };

  const controller = createStreamBroker(brokerOptions);

  const runPromise = controller.run();

  if (options.disconnect?.kind === "before_first_token") {
    await delay(5);
    controller.disconnect("client_close");
  } else if (options.disconnect?.kind === "after_first_delta") {
    const waitForDelta = async () => {
      while (
        collector.events.filter((event) => event.type === "text_delta").length ===
        0
      ) {
        await delay(5);
      }
    };
    await waitForDelta();
    controller.disconnect("client_close");
  } else if (
    options.disconnect?.kind === "network_drop" ||
    options.disconnect?.kind === "client_close"
  ) {
    const afterMs = options.disconnect.afterMs ?? 25;
    await delay(afterMs);
    controller.disconnect(
      options.disconnect.kind === "network_drop" ? "network_drop" : "client_close",
    );
  }

  await runPromise;

  return {
    events: collector.events,
    controller,
    creditSpy,
    journalSpy,
    heartbeatTicker,
    brokerOptions,
  };
}

function assertBrokerOptionsSurface(brokerOptions: StreamBrokerOptions): void {
  expect(Object.keys(brokerOptions).sort()).toEqual(
    [...STREAM_BROKER_OPTION_KEYS].sort(),
  );
  expect(brokerOptions).not.toHaveProperty("sessionDo");
  expect(brokerOptions).not.toHaveProperty("requestRegistry");
  expect(brokerOptions).not.toHaveProperty("durableObject");
  expect(brokerOptions).not.toHaveProperty("SessionDurableObject");
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("T-D4-03 incremental_guard_length_ceiling_aborts", () => {
  it("fails when cumulative assembled length exceeds maxLength across sub-ceiling chunks", async () => {
    // maxLength 20; chunks 10+10+5 → assembled 25 > 20 on third chunk
    const { events } = await runBrokerHarness({
      chunks: ["x".repeat(10), "y".repeat(10), "z".repeat(5)],
    });

    const failed = eventsOfType(events, "failed");
    expect(failed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(failed[0]?.data.code).toBe("validation_failed");
    expect(isTaxonomyCode(failed[0]?.data.code as string)).toBe(true);
  });

  it("completes when assembled length equals maxLength exactly", async () => {
    const exact = "x".repeat(GUARD_THRESHOLDS.maxLength);
    const { events } = await runBrokerHarness({
      chunks: [exact.slice(0, 10), exact.slice(10)],
    });

    const completed = eventsOfType(events, "completed");
    expect(completed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(eventsOfType(events, "failed")).toHaveLength(0);
  });
});

describe("T-D4-04 incremental_guard_stop_sequence_aborts", () => {
  it("aborts on stop-sequence violation and emits exactly one failed terminal", async () => {
    const { events } = await runBrokerHarness({
      chunks: ["partial", GUARD_THRESHOLDS.stopSequences[0]!],
    });

    const failed = eventsOfType(events, "failed");
    expect(failed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(failed[0]?.data.code).toBe("validation_failed");
  });
});

describe("T-D4-05 incremental_guard_system_prompt_leak_aborts", () => {
  it("aborts on system-prompt-leak and emits exactly one failed terminal", async () => {
    const { events } = await runBrokerHarness({
      chunks: [GUARD_THRESHOLDS.systemPromptLeakNeedle],
    });

    const failed = eventsOfType(events, "failed");
    expect(failed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(failed[0]?.data.code).toBe("validation_failed");
  });
});

describe("T-D4-06 full_guard_set_runs_on_assembled_text", () => {
  it("invokes the full guard set on assembled text before the terminal event", async () => {
    const fullGuardSpy = vi.spyOn(proseGuards, "runFullGuardSet");

    const chunks = ["Hello", " world"];
    const { events } = await runBrokerHarness({ chunks });

    expect(fullGuardSpy).toHaveBeenCalledOnce();
    expect(fullGuardSpy).toHaveBeenCalledWith(
      chunks.join(""),
      GUARD_THRESHOLDS,
    );

    const completed = eventsOfType(events, "completed");
    expect(completed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(fullGuardSpy.mock.invocationCallOrder.length).toBeGreaterThan(0);
  });

  it("fails with validation_failed when assembled text is empty (empty_output)", async () => {
    const fullGuardSpy = vi.spyOn(proseGuards, "runFullGuardSet");

    const { events } = await runBrokerHarness({
      chunks: [],
    });

    expect(fullGuardSpy).toHaveBeenCalledOnce();
    expect(fullGuardSpy).toHaveBeenCalledWith("", GUARD_THRESHOLDS);
    expect(fullGuardSpy.mock.results[0]?.value).toBe("empty_output");

    const failed = eventsOfType(events, "failed");
    expect(failed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(failed[0]?.data.code).toBe("validation_failed");
  });
});

describe("T-D4-01 chunks_relayed_in_order", () => {
  it("relays normalized chunks in order as text_delta events", async () => {
    const chunks = ["alpha", "beta", "gamma"];
    const { events } = await runBrokerHarness({ chunks });

    const deltas = eventsOfType(events, "text_delta");
    expect(deltas.map((event) => event.data.text)).toEqual(chunks);
    expect(deltas.map((event) => event.data.sequence)).toEqual([0, 1, 2]);
  });
});

describe("T-D4-07 terminal_completed_carries_validated_payload", () => {
  it("emits exactly one completed terminal with a self-contained validated payload", async () => {
    // Assembled length must stay within GUARD_THRESHOLDS.maxLength (20).
    const chunks = ["Visit", " note", "."];
    const assembled = chunks.join("");
    const { events } = await runBrokerHarness({ chunks });

    const completed = eventsOfType(events, "completed");
    expect(completed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);

    const payload = completed[0]?.data.result as Record<string, unknown>;
    expect(payload).toBeDefined();
    expect(payload).not.toEqual({ assembled_from_chunks: true });

    const finalContent = payload.finalContent as Record<string, unknown>;
    expect(finalContent?.text).toBe(assembled);
    expect(finalContent?.authoritative).toBe(true);
  });
});

describe("T-D4-18 provisional_chunks_not_authoritative", () => {
  it("treats text_delta chunks as provisional and only the terminal payload as authoritative", async () => {
    const chunks = ["draft", "-only"];
    const { events } = await runBrokerHarness({ chunks });

    const deltas = eventsOfType(events, "text_delta");
    expect(deltas.length).toBeGreaterThan(0);
    for (const delta of deltas) {
      expect(delta.data.provisional).toBe(true);
      expect(delta.data.authoritative).not.toBe(true);
    }

    const completed = eventsOfType(events, "completed");
    expect(completed).toHaveLength(1);
    const payload = completed[0]?.data.result as Record<string, unknown>;
    const finalContent = payload.finalContent as Record<string, unknown>;
    expect(finalContent?.authoritative).toBe(true);
    expect(finalContent?.text).toBe(chunks.join(""));
  });
});

describe("T-D4-02 heartbeat_during_provider_silence", () => {
  it("emits at least one heartbeat while the stream is open without content", async () => {
    const heartbeatTicker = createControllableHeartbeatTicker();
    const collector = createEventSinkCollector();
    const creditSpy = createCreditSinkSpy();
    const journalSpy = createJournalTerminalSinkSpy();

    const controller = createStreamBroker({
      traceId: FIXTURE_TRACE_ID,
      requestId: FIXTURE_REQUEST_ID,
      eventSink: collector.sink,
      chunkSource: createSilentChunkSource(),
      heartbeatTicker,
      creditSink: creditSpy.sink,
      journalTerminalSink: journalSpy.sink,
      guardThresholds: GUARD_THRESHOLDS,
    });

    const runPromise = controller.run();
    await delay(5);
    heartbeatTicker.triggerSilentGap();
    await delay(5);
    controller.disconnect("client_close");
    await runPromise;

    const heartbeats = eventsOfType(collector.events, "heartbeat");
    expect(heartbeats.length).toBeGreaterThanOrEqual(1);
    expect(eventsOfType(collector.events, "text_delta")).toHaveLength(0);
    expect(isTerminalEventType(collector.events.at(-1)?.type ?? "")).toBe(true);
  });

  it("suppresses heartbeat during content activity (notifyActivity)", async () => {
    const heartbeatTicker = createControllableHeartbeatTicker();
    const collector = createEventSinkCollector();
    const creditSpy = createCreditSinkSpy();
    const journalSpy = createJournalTerminalSinkSpy();

    const controller = createStreamBroker({
      traceId: FIXTURE_TRACE_ID,
      requestId: FIXTURE_REQUEST_ID,
      eventSink: collector.sink,
      chunkSource: createScriptedChunkSource(["content"], { delayMs: 5 }),
      heartbeatTicker,
      creditSink: creditSpy.sink,
      journalTerminalSink: journalSpy.sink,
      guardThresholds: GUARD_THRESHOLDS,
    });

    const runPromise = controller.run();

    while (eventsOfType(collector.events, "text_delta").length === 0) {
      await delay(5);
    }
    expect(heartbeatTicker.notifyActivityCallCount()).toBeGreaterThanOrEqual(1);

    const heartbeatsBeforeGap = eventsOfType(collector.events, "heartbeat").length;
    heartbeatTicker.triggerSilentGap();
    await delay(5);

    expect(eventsOfType(collector.events, "heartbeat").length).toBe(
      heartbeatsBeforeGap,
    );

    await runPromise;
  });
});

describe("T-D4-08 disconnect_aborts_provider_fetch_via_abort_signal", () => {
  it("aborts the broker-held AbortSignal when the client stream closes", async () => {
    let observedSignal: AbortSignal | undefined;

    const chunkSource: ChunkSource = {
      async *stream({ signal }) {
        observedSignal = signal;
        await delay(50);
        if (!signal.aborted) {
          yield "late";
        }
      },
    };

    const { controller } = await runBrokerHarness({
      chunkSource,
      disconnect: { kind: "client_close", afterMs: 10 },
    });

    expect(observedSignal).toBeDefined();
    expect(observedSignal!.aborted).toBe(true);
    expect(controller.fetchSignal.aborted).toBe(true);
  });
});

describe("T-D4-09 disconnect_terminates_as_cancelled", () => {
  it("terminates the request as cancelled on client disconnect", async () => {
    const { events } = await runBrokerHarness({
      chunkDelayMs: 50,
      disconnect: { kind: "client_close", afterMs: 10 },
    });

    const cancelled = eventsOfType(events, "cancelled");
    expect(cancelled).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
  });
});

describe("T-D4-13 cancel_before_first_token", () => {
  it("aborts before first token, terminates as cancelled, and skips credit when no usage", async () => {
    const { events, creditSpy, journalSpy } = await runBrokerHarness({
      chunkDelayMs: 100,
      disconnect: { kind: "before_first_token" },
    });

    expect(eventsOfType(events, "text_delta")).toHaveLength(0);
    expect(eventsOfType(events, "cancelled")).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    // Nothing yielded → getPartialUsage() is undefined → credit sink not called
    expect(creditSpy.calls).toHaveLength(0);
    expect(journalSpy.records).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        state: "cancelled",
      },
    ]);
  });
});

describe("T-D4-14 cancel_mid_stream", () => {
  it("aborts mid-stream, terminates as cancelled, and credits live partial usage", async () => {
    const chunks = ["first", " second", " third"];
    const expectedUsage = expectedUsageForChunks(["first"]);

    const { events, creditSpy } = await runBrokerHarness({
      chunks,
      chunkDelayMs: 30,
      disconnect: { kind: "after_first_delta" },
    });

    const deltas = eventsOfType(events, "text_delta");
    expect(deltas.length).toBeGreaterThanOrEqual(1);
    expect(deltas[0]?.data.text).toBe("first");
    expect(eventsOfType(events, "cancelled")).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(creditSpy.calls).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        usage: expectedUsage,
        partial: true,
      },
    ]);
  });
});

describe("T-D4-16 network_drop_indistinguishable_from_cancel", () => {
  it("follows the same abort, cancelled, and credit path as deliberate cancel", async () => {
    let deliberateSignal: AbortSignal | undefined;
    let networkDropSignal: AbortSignal | undefined;

    const makeSource = (
      assignSignal: (s: AbortSignal) => void,
    ): ChunkSource => {
      let yieldedTokens = 0;
      return {
        getPartialUsage() {
          if (yieldedTokens === 0) {
            return undefined;
          }
          return usageFromTokens(yieldedTokens);
        },
        async *stream({ signal }) {
          assignSignal(signal);
          for (const chunk of ["a", "b"]) {
            await delay(30);
            if (signal.aborted) {
              return;
            }
            yieldedTokens += chunk.length;
            yield chunk;
          }
        },
      };
    };

    const deliberate = await runBrokerHarness({
      chunkSource: makeSource((s) => {
        deliberateSignal = s;
      }),
      disconnect: { kind: "client_close", afterMs: 15 },
    });

    const networkDrop = await runBrokerHarness({
      chunkSource: makeSource((s) => {
        networkDropSignal = s;
      }),
      disconnect: { kind: "network_drop", afterMs: 15 },
    });

    const summarize = (events: AdapterSseEvent[], creditSpy: CreditSinkSpy) => ({
      terminal: events.filter((event) => isTerminalEventType(event.type)).map(
        (event) => event.type,
      ),
      credit: creditSpy.calls,
      deltas: eventsOfType(events, "text_delta").length,
    });

    expect(summarize(networkDrop.events, networkDrop.creditSpy)).toEqual(
      summarize(deliberate.events, deliberate.creditSpy),
    );

    expect(networkDrop.controller.fetchSignal.aborted).toBe(true);
    expect(deliberate.controller.fetchSignal.aborted).toBe(true);
    expect(networkDropSignal?.aborted).toBe(true);
    expect(deliberateSignal?.aborted).toBe(true);
  });
});

describe("T-D4-10 partial_usage_credited_on_cancel", () => {
  it("calls the credit sink with live partial usage on cancel after first delta", async () => {
    const chunks = ["partial", " stream"];
    const expectedUsage = expectedUsageForChunks(["partial"]);

    const { creditSpy } = await runBrokerHarness({
      chunks,
      chunkDelayMs: 25,
      disconnect: { kind: "after_first_delta" },
    });

    expect(creditSpy.calls).toHaveLength(1);
    expect(creditSpy.calls[0]).toEqual({
      requestId: FIXTURE_REQUEST_ID,
      usage: expectedUsage,
      partial: true,
    });
  });
});

describe("T-D4-11 journal_row_complete_on_cancel", () => {
  it("records a complete terminal cancelled outcome via the journal-terminal sink", async () => {
    const journalSpy = createJournalTerminalSinkSpy();

    const collector = createEventSinkCollector();
    const creditSpy = createCreditSinkSpy();
    const controller = createStreamBroker({
      traceId: FIXTURE_TRACE_ID,
      requestId: FIXTURE_REQUEST_ID,
      eventSink: collector.sink,
      chunkSource: createScriptedChunkSource(["token"], { delayMs: 40 }),
      heartbeatTicker: createControllableHeartbeatTicker(),
      creditSink: creditSpy.sink,
      journalTerminalSink: journalSpy.sink,
      guardThresholds: GUARD_THRESHOLDS,
    });

    const runPromise = controller.run();
    await delay(10);
    controller.disconnect("client_close");
    await runPromise;

    expect(journalSpy.records).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        state: "cancelled",
      },
    ]);
    expect(eventsOfType(collector.events, "cancelled")).toHaveLength(1);
  });
});

describe("T-D4-12 no_per_request_state_object_created", () => {
  it("does not create per-request server-side state objects across streaming and cancel paths", async () => {
    const moduleExports = await import("../src/stream");

    for (const exportName of Object.keys(moduleExports)) {
      const lowered = exportName.toLowerCase();
      expect(lowered).not.toMatch(/session/);
      expect(lowered).not.toMatch(/requestregistry/);
      expect(lowered).not.toMatch(/requeststate/);
      expect(lowered).not.toMatch(/durableobject/);
    }

    const streamSource = readFileSync(
      resolve(__dirname, "../src/stream/index.ts"),
      "utf8",
    );
    expect(streamSource).not.toMatch(/SessionDurableObject|sessionDo|DurableObject/);

    const { controller, brokerOptions } = await runBrokerHarness({
      chunks: ["state", " check"],
      chunkDelayMs: 20,
      disconnect: { kind: "after_first_delta" },
    });

    assertBrokerOptionsSurface(brokerOptions);
    expect(controller.fetchSignal).toBeInstanceOf(AbortSignal);
    expect((controller as { sessionDo?: unknown }).sessionDo).toBeUndefined();
    expect(
      (controller as { requestRegistry?: unknown }).requestRegistry,
    ).toBeUndefined();
  });
});

describe("T-D4-15 one_terminal_event_under_guard_abort_and_cancel", () => {
  it("emits exactly one terminal on incremental-guard abort", async () => {
    const { events } = await runBrokerHarness({
      chunks: [GUARD_THRESHOLDS.stopSequences[0]!],
    });

    expect(countTerminalEvents(events)).toBe(1);
    expect(eventsOfType(events, "failed")).toHaveLength(1);
  });

  it("emits exactly one terminal on disconnect", async () => {
    const { events } = await runBrokerHarness({
      chunkDelayMs: 40,
      disconnect: { kind: "client_close", afterMs: 10 },
    });

    expect(countTerminalEvents(events)).toBe(1);
    expect(eventsOfType(events, "cancelled")).toHaveLength(1);
  });
});

describe("T-D4-17 no_out_of_band_cancel_endpoint_or_session_do", () => {
  it("does not expose a separate cancel endpoint or Session Durable Object", async () => {
    const streamExports = await import("../src/stream");
    const exportNames = Object.keys(streamExports);

    for (const exportName of exportNames) {
      const lowered = exportName.toLowerCase();
      expect(lowered).not.toMatch(/cancelendpoint/);
      expect(lowered).not.toMatch(/cancelroute/);
      expect(lowered).not.toMatch(/sessiondo/);
      expect(lowered).not.toMatch(/sessiondurableobject/);
    }

    expect(streamExports).not.toHaveProperty("handleCancelRequest");
    expect(streamExports).not.toHaveProperty("SessionDurableObject");
    expect(streamExports).not.toHaveProperty("createSessionDo");

    const streamSource = readFileSync(
      resolve(__dirname, "../src/stream/index.ts"),
      "utf8",
    );
    expect(streamSource).not.toMatch(
      /SessionDurableObject|sessionDo|cancelEndpoint|cancelRoute/,
    );

    const { brokerOptions } = await runBrokerHarness({
      chunks: ["ok"],
    });
    assertBrokerOptionsSurface(brokerOptions);
  });
});

describe("T-D4-19 no_d1_row_per_stream_chunk", () => {
  it("writes zero D1 rows per relayed stream chunk", async () => {
    const journalSpy = vi.spyOn(journalModule, "recordTerminalState");
    const transitionSpy = vi.spyOn(journalModule, "journalTransition");

    const chunks = ["one", "two", "three"];
    await runBrokerHarness({ chunks });

    expect(journalSpy).not.toHaveBeenCalled();
    expect(transitionSpy).not.toHaveBeenCalled();
  });
});

describe("T-D4-20 abort_rejecting_source_still_cancels", () => {
  it("disconnect against AbortError-throwing source yields cancelled + journal + credit", async () => {
    // Two delayed chunks so disconnect lands while the source is mid-await and
    // the subsequent aborted next() throws AbortError rather than completing.
    const chunks = ["pre-abort", " more"];
    const expectedUsage = expectedUsageForChunks(["pre-abort"]);

    const { events, creditSpy, journalSpy } = await runBrokerHarness({
      chunkSource: createAbortRejectingChunkSource(chunks, { delayMs: 40 }),
      disconnect: { kind: "after_first_delta" },
    });

    expect(eventsOfType(events, "cancelled")).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(creditSpy.calls).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        usage: expectedUsage,
        partial: true,
      },
    ]);
    expect(journalSpy.records).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        state: "cancelled",
      },
    ]);
  });
});

describe("T-D4-21 mid_stream_source_throw_fails_terminally", () => {
  it("maps a non-abort source throw to exactly one failed/internal_error + journal", async () => {
    const { events, journalSpy, creditSpy } = await runBrokerHarness({
      chunkSource: createThrowingChunkSource(new Error("provider blew up")),
    });

    const failed = eventsOfType(events, "failed");
    expect(failed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(failed[0]?.data.code).toBe("internal_error");
    expect(journalSpy.records).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        state: "failed",
        terminalErrorCode: "internal_error",
      },
    ]);
    // Failed path does not credit
    expect(creditSpy.calls).toHaveLength(0);
  });
});

describe("T-D4-22 zero_usage_cancel_skips_credit", () => {
  it("skips credit when cancel has no yielded tokens / no getPartialUsage", async () => {
    const { events, creditSpy, journalSpy } = await runBrokerHarness({
      chunkSource: createSilentChunkSource(),
      disconnect: { kind: "client_close", afterMs: 15 },
    });

    expect(eventsOfType(events, "cancelled")).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(creditSpy.calls).toHaveLength(0);
    expect(journalSpy.records).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        state: "cancelled",
      },
    ]);
  });
});

describe("T-D4-23 disconnect_after_completion_noop", () => {
  it("keeps exactly one completed terminal when disconnect is called after completion", async () => {
    const collector = createEventSinkCollector();
    const creditSpy = createCreditSinkSpy();
    const journalSpy = createJournalTerminalSinkSpy();

    const controller = createStreamBroker({
      traceId: FIXTURE_TRACE_ID,
      requestId: FIXTURE_REQUEST_ID,
      eventSink: collector.sink,
      chunkSource: createScriptedChunkSource(["done"]),
      heartbeatTicker: createControllableHeartbeatTicker(),
      creditSink: creditSpy.sink,
      journalTerminalSink: journalSpy.sink,
      guardThresholds: GUARD_THRESHOLDS,
    });

    await controller.run();

    expect(eventsOfType(collector.events, "completed")).toHaveLength(1);
    expect(countTerminalEvents(collector.events)).toBe(1);

    controller.disconnect("client_close");

    expect(eventsOfType(collector.events, "completed")).toHaveLength(1);
    expect(eventsOfType(collector.events, "cancelled")).toHaveLength(0);
    expect(countTerminalEvents(collector.events)).toBe(1);
    expect(journalSpy.records).toHaveLength(1);
    expect(journalSpy.records[0]?.state).toBe("completed");
  });
});

describe("T-D4-24 journal_on_completed_and_failed", () => {
  it("journals completed on the happy path", async () => {
    const { events, journalSpy } = await runBrokerHarness({
      chunks: ["ok"],
    });

    expect(eventsOfType(events, "completed")).toHaveLength(1);
    expect(journalSpy.records).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        state: "completed",
      },
    ]);
  });

  it("journals failed with terminalErrorCode validation_failed on guard failure", async () => {
    const { events, journalSpy } = await runBrokerHarness({
      chunks: [GUARD_THRESHOLDS.stopSequences[0]!],
    });

    expect(eventsOfType(events, "failed")).toHaveLength(1);
    expect(journalSpy.records).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        state: "failed",
        terminalErrorCode: "validation_failed",
      },
    ]);
  });
});

describe("T-D4-25 sink_throw_does_not_suppress_terminal", () => {
  it("still emits cancelled when creditSink and journalSink throw", async () => {
    const collector = createEventSinkCollector();
    const heartbeatTicker = createControllableHeartbeatTicker();

    const controller = createStreamBroker({
      traceId: FIXTURE_TRACE_ID,
      requestId: FIXTURE_REQUEST_ID,
      eventSink: collector.sink,
      // Multiple delayed chunks keep the stream open until disconnect.
      chunkSource: createScriptedChunkSource(["x", "y", "z"], { delayMs: 40 }),
      heartbeatTicker,
      creditSink: () => {
        throw new Error("credit sink boom");
      },
      journalTerminalSink: () => {
        throw new Error("journal sink boom");
      },
      guardThresholds: GUARD_THRESHOLDS,
    });

    const runPromise = controller.run();
    while (eventsOfType(collector.events, "text_delta").length === 0) {
      await delay(5);
    }
    controller.disconnect("client_close");
    await runPromise;

    expect(eventsOfType(collector.events, "cancelled")).toHaveLength(1);
    expect(countTerminalEvents(collector.events)).toBe(1);
  });

  it("still emits completed when journalSink throws", async () => {
    const collector = createEventSinkCollector();

    const controller = createStreamBroker({
      traceId: FIXTURE_TRACE_ID,
      requestId: FIXTURE_REQUEST_ID,
      eventSink: collector.sink,
      chunkSource: createScriptedChunkSource(["ok"]),
      heartbeatTicker: createControllableHeartbeatTicker(),
      creditSink: () => undefined,
      journalTerminalSink: () => {
        throw new Error("journal sink boom");
      },
      guardThresholds: GUARD_THRESHOLDS,
    });

    await controller.run();

    expect(eventsOfType(collector.events, "completed")).toHaveLength(1);
    expect(countTerminalEvents(collector.events)).toBe(1);
  });
});

describe("T-D4-26 signal_ignoring_source_disconnect_emits_cancelled", () => {
  it("emits cancelled promptly on disconnect against a signal-ignoring source", async () => {
    const collector = createEventSinkCollector();
    const creditSpy = createCreditSinkSpy();
    const journalSpy = createJournalTerminalSinkSpy();

    const controller = createStreamBroker({
      traceId: FIXTURE_TRACE_ID,
      requestId: FIXTURE_REQUEST_ID,
      eventSink: collector.sink,
      chunkSource: createSignalIgnoringChunkSource(),
      heartbeatTicker: createControllableHeartbeatTicker(),
      creditSink: creditSpy.sink,
      journalTerminalSink: journalSpy.sink,
      guardThresholds: GUARD_THRESHOLDS,
    });

    const runPromise = controller.run();
    await delay(20);
    controller.disconnect("client_close");

    // Cancelled must be emitted synchronously — do not await run first
    expect(eventsOfType(collector.events, "cancelled")).toHaveLength(1);
    expect(controller.fetchSignal.aborted).toBe(true);

    await Promise.race([
      runPromise,
      delay(500).then(() => {
        throw new Error("run() hung after disconnect against signal-ignoring source");
      }),
    ]);

    expect(countTerminalEvents(collector.events)).toBe(1);
    expect(journalSpy.records).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        state: "cancelled",
      },
    ]);
  });
});

describe("T-D4-27 invocation_adapter_relays_regenerating", () => {
  it("relays regenerating then text_deltas via createChunkSourceFromInvocationEvents", async () => {
    async function* events() {
      yield { kind: "regenerating" as const };
      yield { kind: "text" as const, text: "hello" };
      yield { kind: "text" as const, text: " world" };
    }

    const { events: sseEvents } = await runBrokerHarness({
      chunkSource: createChunkSourceFromInvocationEvents(events()),
    });

    const regenerating = eventsOfType(sseEvents, "regenerating");
    expect(regenerating).toHaveLength(1);

    const deltas = eventsOfType(sseEvents, "text_delta");
    expect(deltas.map((e) => e.data.text)).toEqual(["hello", " world"]);
    expect(deltas.map((e) => e.data.sequence)).toEqual([0, 1]);

    expect(eventsOfType(sseEvents, "completed")).toHaveLength(1);
    expect(countTerminalEvents(sseEvents)).toBe(1);
  });
});
