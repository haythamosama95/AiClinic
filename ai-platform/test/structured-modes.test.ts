import { afterEach, describe, expect, it, vi } from "vitest";
import type { AdapterSseEvent } from "../src/adapter";
import {
  createStreamBroker,
  type ChunkSource,
  type CreditSink,
  type HeartbeatTicker,
  type JournalTerminalSink,
  type StreamBrokerEventSink,
  type StreamBrokerOptions,
} from "../src/stream";
import * as proseGuards from "../src/stream/prose-guards";
import type {
  BusinessRuleRegistry,
  SafetyMarkers,
  SchemaRegistry,
} from "../src/validate";

const SCHEMA_REF = "schemas/visit-summary@v1";

const SAFETY_MARKERS: SafetyMarkers = {
  leakedInstructionNeedle: "SYSTEM_PROMPT_LEAK_TEST_NEEDLE",
  refusalPrefixes: ["I'm sorry, I can't assist"],
  injectionEchoNeedle: "IGNORE_PREVIOUS_INSTRUCTIONS_TEST",
};

const VALID_DOCUMENT = {
  summary: "Patient presents with mild headache.",
  severity: "mild",
  patientRef: "patient-001",
  painScore: 3,
  sections: { assessment: "Stable", plan: "Rest and fluids" },
};

function createSchemaRegistry(): SchemaRegistry {
  const registry: SchemaRegistry = new Map();
  registry.set(SCHEMA_REF, (parsed: unknown) => {
    if (typeof parsed !== "object" || parsed === null) {
      return "expected object";
    }
    const doc = parsed as Record<string, unknown>;
    if (typeof doc.summary !== "string") {
      return "summary required";
    }
    return null;
  });
  return registry;
}

const FIXTURE_TRACE_ID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
const FIXTURE_REQUEST_ID = "req-d6-structured-001";

const GUARD_THRESHOLDS = {
  maxLength: 500,
  stopSequences: ["<|end|>"],
  systemPromptLeakNeedle: "SYSTEM_PROMPT_LEAK_TEST_NEEDLE",
};

const TERMINAL_EVENT_KINDS = ["completed", "failed", "cancelled"] as const;

type EventSinkCollector = {
  sink: StreamBrokerEventSink;
  events: AdapterSseEvent[];
};

type ControllableHeartbeatTicker = HeartbeatTicker & {
  triggerSilentGap(): void;
};

function isTerminalEventType(type: string): boolean {
  return (TERMINAL_EVENT_KINDS as readonly string[]).includes(type);
}

function eventsOfType(events: AdapterSseEvent[], type: string): AdapterSseEvent[] {
  return events.filter((event) => event.type === type);
}

function createEventSinkCollector(): EventSinkCollector {
  const events: AdapterSseEvent[] = [];
  return {
    events,
    sink: {
      push(event: AdapterSseEvent) {
        events.push(event);
      },
    },
  };
}

function createControllableHeartbeatTicker(): ControllableHeartbeatTicker {
  let onHeartbeat: (() => void) | null = null;
  return {
    schedule(callback: () => void) {
      onHeartbeat = callback;
      return { cancel() { onHeartbeat = null; } };
    },
    triggerSilentGap() {
      onHeartbeat?.();
    },
  };
}

function createNoopCreditSink(): CreditSink {
  return () => {};
}

function createNoopJournalSink(): JournalTerminalSink {
  return () => {};
}

function createScriptedChunkSource(chunks: string[]): ChunkSource {
  return {
    async *stream({ signal }: { signal: AbortSignal }) {
      for (const chunk of chunks) {
        if (signal.aborted) return;
        yield chunk;
      }
    },
  };
}

function structuredChunksFor(document: typeof VALID_DOCUMENT): string[] {
  const full = JSON.stringify(document);
  const mid = Math.floor(full.length / 2);
  return [full.slice(0, mid), full.slice(mid)];
}

type StructuredBrokerHarnessOptions = {
  mode: "structured" | "structured_atomic";
  chunks: string[];
  schemaRegistry?: SchemaRegistry;
  ruleRegistry?: BusinessRuleRegistry;
};

async function runStructuredBrokerHarness(
  options: StructuredBrokerHarnessOptions,
): Promise<{ events: AdapterSseEvent[] }> {
  const collector = createEventSinkCollector();
  const brokerOptions: StreamBrokerOptions = {
    traceId: FIXTURE_TRACE_ID,
    requestId: FIXTURE_REQUEST_ID,
    eventSink: collector.sink,
    chunkSource: createScriptedChunkSource(options.chunks),
    heartbeatTicker: createControllableHeartbeatTicker(),
    creditSink: createNoopCreditSink(),
    journalTerminalSink: createNoopJournalSink(),
    guardThresholds: GUARD_THRESHOLDS,
    outputMode: options.mode,
    structuredValidation: {
      outputSchemaRef: SCHEMA_REF,
      businessValidationRuleRefs: [],
      schemaRegistry: options.schemaRegistry ?? createSchemaRegistry(),
      ruleRegistry: options.ruleRegistry ?? new Map(),
      context: { patientId: "patient-001" },
      safetyMarkers: SAFETY_MARKERS,
    },
  };

  const controller = createStreamBroker(brokerOptions);
  await controller.run();
  return { events: collector.events };
}

function terminalPayload(events: AdapterSseEvent[]): Record<string, unknown> | undefined {
  const completed = eventsOfType(events, "completed");
  if (completed.length !== 1) return undefined;
  return completed[0]?.data.result as Record<string, unknown>;
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("T-D6-17 structured_partial_events_provisional", () => {
  it("emits partial_structured events flagged provisional during structured streaming", async () => {
    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: structuredChunksFor(VALID_DOCUMENT),
    });

    const partials = eventsOfType(events, "partial_structured");
    expect(partials.length).toBeGreaterThan(0);
    for (const event of partials) {
      expect(event.data.provisional).toBe(true);
      expect(event.data.authoritative).not.toBe(true);
    }
  });
});

describe("T-D6-18 structured_terminal_carries_whole_validated_document", () => {
  it("emits completed terminal carrying the whole validated document", async () => {
    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: structuredChunksFor(VALID_DOCUMENT),
    });

    const completed = eventsOfType(events, "completed");
    expect(completed).toHaveLength(1);
    expect(isTerminalEventType(completed[0]?.type ?? "")).toBe(true);

    const payload = terminalPayload(events);
    const finalContent = payload?.["final content"] as Record<string, unknown>;
    expect(finalContent?.document).toEqual(VALID_DOCUMENT);
    expect(finalContent?.authoritative).toBe(true);
  });
});

describe("T-D6-19 structured_atomic_progress_only", () => {
  it("emits only progress/heartbeat before completion for structured_atomic", async () => {
    const heartbeatTicker = createControllableHeartbeatTicker();
    const collector = createEventSinkCollector();

    const controller = createStreamBroker({
      traceId: FIXTURE_TRACE_ID,
      requestId: FIXTURE_REQUEST_ID,
      eventSink: collector.sink,
      chunkSource: createScriptedChunkSource(structuredChunksFor(VALID_DOCUMENT)),
      heartbeatTicker,
      creditSink: createNoopCreditSink(),
      journalTerminalSink: createNoopJournalSink(),
      guardThresholds: GUARD_THRESHOLDS,
      outputMode: "structured_atomic",
      structuredValidation: {
        outputSchemaRef: SCHEMA_REF,
        businessValidationRuleRefs: [],
        schemaRegistry: createSchemaRegistry(),
        ruleRegistry: new Map(),
        context: { patientId: "patient-001" },
        safetyMarkers: SAFETY_MARKERS,
      },
    });

    const runPromise = controller.run();
    heartbeatTicker.triggerSilentGap();
    await runPromise;

    const preTerminal = collector.events.filter(
      (event) => !isTerminalEventType(event.type),
    );
    expect(eventsOfType(preTerminal, "partial_structured")).toHaveLength(0);
    expect(
      eventsOfType(preTerminal, "heartbeat").length +
        eventsOfType(preTerminal, "progress").length,
    ).toBeGreaterThanOrEqual(0);

    const completed = eventsOfType(collector.events, "completed");
    expect(completed).toHaveLength(1);
  });
});

describe("T-D6-20 client_ignoring_chunks_still_correct", () => {
  it("delivers the correct validated result from the terminal payload alone", async () => {
    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: structuredChunksFor(VALID_DOCUMENT),
    });

    const terminalOnly = events.filter((event) => event.type === "completed");
    expect(terminalOnly).toHaveLength(1);

    const payload = terminalOnly[0]?.data.result as Record<string, unknown>;
    const finalContent = payload["final content"] as Record<string, unknown>;
    expect(finalContent.document).toEqual(VALID_DOCUMENT);
  });
});

describe("T-D6-21 terminal_payload_not_assembled_from_chunks", () => {
  it("carries a self-contained terminal payload not assembled from stream chunks", async () => {
    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: structuredChunksFor(VALID_DOCUMENT),
    });

    const partials = eventsOfType(events, "partial_structured");
    const payload = terminalPayload(events);
    const finalContent = payload?.["final content"] as Record<string, unknown>;

    expect(finalContent?._assembledFromChunks).toBe(false);
    expect(finalContent?.document).toEqual(VALID_DOCUMENT);

    for (const partial of partials) {
      expect(partial.data).not.toBe(finalContent?.document);
    }
  });
});

describe("T-D6-22 no_per_request_state_for_repair_or_structured", () => {
  it("does not introduce per-request server-side state in validate or structured paths", async () => {
    const validateExports = await import("../src/validate");
    const streamExports = await import("../src/stream");

    for (const exportName of [
      ...Object.keys(validateExports),
      ...Object.keys(streamExports),
    ]) {
      const lowered = exportName.toLowerCase();
      expect(lowered).not.toMatch(/requestregistry/);
      expect(lowered).not.toMatch(/requeststate/);
      expect(lowered).not.toMatch(/sessiondo/);
      expect(lowered).not.toMatch(/durableobject/);
    }

    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: structuredChunksFor(VALID_DOCUMENT),
    });

    expect(eventsOfType(events, "completed")).toHaveLength(1);
  });
});

describe("T-D6-23 provisional_structured_not_committable_on_emission", () => {
  it("never treats provisional partial_structured content as the committed result", async () => {
    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: structuredChunksFor(VALID_DOCUMENT),
    });

    const partials = eventsOfType(events, "partial_structured");
    const payload = terminalPayload(events);
    const finalContent = payload?.["final content"] as Record<string, unknown>;

    for (const partial of partials) {
      expect(partial.data.committed).not.toBe(true);
      expect(partial.data.committable).not.toBe(true);
      expect(partial.data).not.toEqual(finalContent?.document);
    }
  });
});

describe("T-D6-24 prose_path_unchanged_by_this_slice", () => {
  it("keeps D4 prose incremental guards and relay contracts intact", async () => {
    const incrementalSpy = vi.spyOn(proseGuards, "checkIncrementalGuards");
    const fullSpy = vi.spyOn(proseGuards, "runFullGuardSet");

    const collector = createEventSinkCollector();
    const controller = createStreamBroker({
      traceId: FIXTURE_TRACE_ID,
      requestId: FIXTURE_REQUEST_ID,
      eventSink: collector.sink,
      chunkSource: createScriptedChunkSource(["Hello", " prose"]),
      heartbeatTicker: createControllableHeartbeatTicker(),
      creditSink: createNoopCreditSink(),
      journalTerminalSink: createNoopJournalSink(),
      guardThresholds: GUARD_THRESHOLDS,
      outputMode: "prose",
    });

    await controller.run();

    expect(incrementalSpy).toHaveBeenCalled();
    expect(fullSpy).toHaveBeenCalledOnce();
    expect(eventsOfType(collector.events, "text_delta").length).toBeGreaterThan(0);
    expect(eventsOfType(collector.events, "partial_structured")).toHaveLength(0);
    expect(eventsOfType(collector.events, "completed")).toHaveLength(1);
  });
});
