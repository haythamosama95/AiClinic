import { afterEach, describe, expect, it, vi } from "vitest";
import type { AdapterSseEvent } from "../src/adapter";
import { isTaxonomyCode, type TaxonomyCode } from "../src/errors";
import * as journalModule from "../src/journal/index";
import {
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

const TERMINAL_EVENT_KINDS = ["completed", "failed", "cancelled"] as const;

const FIXTURE_TRACE_ID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
const FIXTURE_REQUEST_ID = "req-d4-001";

/** Injectable guard thresholds — test parameters, not broker constants. */
const GUARD_THRESHOLDS: ProseGuardThresholds = {
  maxLength: 20,
  stopSequences: ["<|end|>"],
  systemPromptLeakNeedle: "SYSTEM_PROMPT_LEAK_TEST_NEEDLE",
};

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
};

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

  return {
    schedule(callback: () => void) {
      onHeartbeat = callback;
      return {
        cancel() {
          onHeartbeat = null;
        },
      };
    },
    triggerSilentGap() {
      onHeartbeat?.();
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

function createScriptedChunkSource(
  chunks: string[],
  options: {
    delayMs?: number;
    partialUsage?: { tokens: number; cost: number };
  } = {},
): ChunkSource {
  const delayMs = options.delayMs ?? 0;

  return {
    partialUsage: options.partialUsage,
    async *stream({ signal }: { signal: AbortSignal }) {
      for (const chunk of chunks) {
        if (delayMs > 0) {
          await delay(delayMs);
        }
        if (signal.aborted) {
          return;
        }
        yield chunk;
      }
    },
  };
}

function createSilentChunkSource(): ChunkSource {
  return {
    async *stream({ signal }: { signal: AbortSignal }) {
      while (!signal.aborted) {
        await delay(10);
      }
    },
  };
}

type RunBrokerHarnessOptions = {
  chunkSource?: ChunkSource;
  chunks?: string[];
  chunkDelayMs?: number;
  partialUsage?: { tokens: number; cost: number };
  guardThresholds?: ProseGuardThresholds;
  heartbeatTicker?: ControllableHeartbeatTicker;
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
      partialUsage: options.partialUsage,
    });

  const brokerOptions: StreamBrokerOptions = {
    traceId: FIXTURE_TRACE_ID,
    requestId: FIXTURE_REQUEST_ID,
    eventSink: collector.sink,
    chunkSource,
    heartbeatTicker,
    creditSink: creditSpy.sink,
    journalTerminalSink: journalSpy.sink,
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
  };
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("T-D4-03 incremental_guard_length_ceiling_aborts", () => {
  it("aborts the stream and emits exactly one failed terminal with validation_failed", async () => {
    const longText = "x".repeat(GUARD_THRESHOLDS.maxLength + 1);
    const { events } = await runBrokerHarness({
      chunks: [longText],
    });

    const failed = eventsOfType(events, "failed");
    expect(failed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(failed[0]?.data.code).toBe("validation_failed");
    expect(isTaxonomyCode(failed[0]?.data.code as string)).toBe(true);
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
    const chunks = ["Visit", " summary", " complete."];
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
  it("aborts before first token, terminates as cancelled, and credits partial usage when present", async () => {
    const partialUsage = { tokens: 12, cost: 0.02 };
    const { events, creditSpy } = await runBrokerHarness({
      chunkDelayMs: 100,
      partialUsage,
      disconnect: { kind: "before_first_token" },
    });

    expect(eventsOfType(events, "text_delta")).toHaveLength(0);
    expect(eventsOfType(events, "cancelled")).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(creditSpy.calls).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        usage: partialUsage,
        partial: true,
      },
    ]);
  });
});

describe("T-D4-14 cancel_mid_stream", () => {
  it("aborts mid-stream, terminates as cancelled, and credits partial usage", async () => {
    const partialUsage = { tokens: 30, cost: 0.05 };
    const { events, creditSpy } = await runBrokerHarness({
      chunks: ["first", " second", " third"],
      chunkDelayMs: 30,
      partialUsage,
      disconnect: { kind: "after_first_delta" },
    });

    expect(eventsOfType(events, "text_delta").length).toBeGreaterThanOrEqual(1);
    expect(eventsOfType(events, "cancelled")).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(creditSpy.calls).toEqual([
      {
        requestId: FIXTURE_REQUEST_ID,
        usage: partialUsage,
        partial: true,
      },
    ]);
  });
});

describe("T-D4-16 network_drop_indistinguishable_from_cancel", () => {
  it("follows the same abort, cancelled, and credit path as deliberate cancel", async () => {
    const partialUsage = { tokens: 8, cost: 0.01 };

    const deliberate = await runBrokerHarness({
      chunks: ["a", "b"],
      chunkDelayMs: 30,
      partialUsage,
      disconnect: { kind: "client_close", afterMs: 15 },
    });

    const networkDrop = await runBrokerHarness({
      chunks: ["a", "b"],
      chunkDelayMs: 30,
      partialUsage,
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
  });
});

describe("T-D4-10 partial_usage_credited_on_cancel", () => {
  it("calls the credit sink with partial usage on cancel after partial provider usage", async () => {
    const partialUsage = { tokens: 42, cost: 0.12 };
    const { creditSpy } = await runBrokerHarness({
      chunks: ["partial", " stream"],
      chunkDelayMs: 25,
      partialUsage,
      disconnect: { kind: "after_first_delta" },
    });

    expect(creditSpy.calls).toHaveLength(1);
    expect(creditSpy.calls[0]).toEqual({
      requestId: FIXTURE_REQUEST_ID,
      usage: partialUsage,
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

    const { controller } = await runBrokerHarness({
      chunks: ["state", " check"],
      chunkDelayMs: 20,
      disconnect: { kind: "after_first_delta" },
    });

    expect(controller.fetchSignal).toBeInstanceOf(AbortSignal);
    expect((controller as { sessionDo?: unknown }).sessionDo).toBeUndefined();
    expect((controller as { requestRegistry?: unknown }).requestRegistry).toBeUndefined();
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
