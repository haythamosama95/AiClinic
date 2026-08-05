import { afterEach, describe, expect, it, vi } from "vitest";
import type { AdapterSseEvent } from "../src/adapter";
import * as proseGuards from "../src/stream/prose-guards";
import {
  createStructuredStreamBroker,
  type ChunkSource,
  type CreditSink,
  type HeartbeatTicker,
  type JournalTerminalSink,
  type StreamBrokerEventSink,
  type StreamChunk,
  type StructuredStreamBrokerOptions,
} from "../src/stream/structured";
import type {
  BusinessRuleRegistry,
  RepairPolicy,
  ReaskPort,
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

const DEFAULT_REPAIR_POLICY: RepairPolicy = { allowed: false, maxAttempts: 0 };

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
      return {
        cancel() {
          onHeartbeat = null;
        },
        notifyActivity() {
          // Activity resets silence window; controllable fixture keeps the
          // scheduled callback until cancel or a silent-gap trigger.
        },
      };
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

function createScriptedChunkSource(
  chunks: Array<string | StreamChunk>,
  options: { truncated?: boolean } = {},
): ChunkSource {
  return {
    wasTruncated() {
      return options.truncated === true;
    },
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
  chunks: Array<string | StreamChunk>;
  schemaRegistry?: SchemaRegistry;
  ruleRegistry?: BusinessRuleRegistry;
  repairPolicy?: RepairPolicy;
  reask?: ReaskPort;
  truncated?: boolean;
  outputSchemaRef?: string | null;
  businessValidationRuleRefs?: readonly string[];
  safetyMarkers?: SafetyMarkers;
};

function buildBrokerOptions(
  options: StructuredBrokerHarnessOptions,
  collector: EventSinkCollector,
  heartbeatTicker: HeartbeatTicker = createControllableHeartbeatTicker(),
): StructuredStreamBrokerOptions {
  return {
    traceId: FIXTURE_TRACE_ID,
    requestId: FIXTURE_REQUEST_ID,
    eventSink: collector.sink,
    chunkSource: createScriptedChunkSource(options.chunks, {
      truncated: options.truncated,
    }),
    heartbeatTicker,
    creditSink: createNoopCreditSink(),
    journalTerminalSink: createNoopJournalSink(),
    outputMode: options.mode,
    structuredValidation: {
      outputSchemaRef:
        options.outputSchemaRef === undefined ? SCHEMA_REF : options.outputSchemaRef,
      businessValidationRuleRefs: options.businessValidationRuleRefs ?? [],
      schemaRegistry: options.schemaRegistry ?? createSchemaRegistry(),
      ruleRegistry: options.ruleRegistry ?? new Map(),
      repairPolicy: options.repairPolicy ?? DEFAULT_REPAIR_POLICY,
      context: { patientId: "patient-001" },
      safetyMarkers: options.safetyMarkers ?? SAFETY_MARKERS,
    },
    ...(options.reask ? { reask: options.reask } : {}),
  };
}

async function runStructuredBrokerHarness(
  options: StructuredBrokerHarnessOptions,
): Promise<{ events: AdapterSseEvent[] }> {
  const collector = createEventSinkCollector();
  const controller = createStructuredStreamBroker(
    buildBrokerOptions(options, collector),
  );
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
    const finalContent = payload?.finalContent as Record<string, unknown>;
    expect(finalContent?.document).toEqual(VALID_DOCUMENT);
    expect(finalContent?.authoritative).toBe(true);
  });
});

describe("T-D6-19 structured_atomic_progress_only", () => {
  it("emits only progress/heartbeat before completion for structured_atomic", async () => {
    const heartbeatTicker = createControllableHeartbeatTicker();
    const collector = createEventSinkCollector();

    const controller = createStructuredStreamBroker(
      buildBrokerOptions(
        {
          mode: "structured_atomic",
          chunks: structuredChunksFor(VALID_DOCUMENT),
        },
        collector,
        heartbeatTicker,
      ),
    );

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
    ).toBeGreaterThan(0);

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
    const finalContent = payload.finalContent as Record<string, unknown>;
    expect(finalContent.document).toEqual(VALID_DOCUMENT);
  });
});

describe("T-D6-21 terminal_payload_not_assembled_from_chunks", () => {
  it("carries a self-contained terminal payload not assembled from stream chunks", async () => {
    const garbageDoc = { summary: "GARBAGE_PROVISIONAL_CONTENT", severity: "mild" };
    const regeneratingChunks: StreamChunk[] = [
      ...structuredChunksFor(garbageDoc as typeof VALID_DOCUMENT),
      { kind: "regenerating" },
      ...structuredChunksFor(VALID_DOCUMENT),
    ];

    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: regeneratingChunks,
    });

    const partials = eventsOfType(events, "partial_structured");
    const regenerating = eventsOfType(events, "regenerating");
    const payload = terminalPayload(events);
    const finalContent = payload?.finalContent as Record<string, unknown>;

    expect(regenerating.length).toBeGreaterThan(0);
    expect(finalContent?._assembledFromChunks).toBe(false);
    expect(finalContent?.document).toEqual(VALID_DOCUMENT);
    expect(finalContent?.document).not.toEqual(garbageDoc);

    const provisionalDocs = partials.map((event) => event.data.document);
    expect(
      provisionalDocs.some(
        (doc) =>
          typeof doc === "object" &&
          doc !== null &&
          (doc as Record<string, unknown>).summary === "GARBAGE_PROVISIONAL_CONTENT",
      ),
    ).toBe(true);
  });
});

describe("T-D6-22 no_per_request_state_for_repair_or_structured", () => {
  it("keeps concurrent structured brokers observationally independent", async () => {
    const docA = { ...VALID_DOCUMENT, summary: "Broker A only" };
    const docB = { ...VALID_DOCUMENT, summary: "Broker B only" };

    const [resultA, resultB] = await Promise.all([
      runStructuredBrokerHarness({
        mode: "structured",
        chunks: structuredChunksFor(docA),
      }),
      runStructuredBrokerHarness({
        mode: "structured",
        chunks: structuredChunksFor(docB),
      }),
    ]);

    const finalA = (
      terminalPayload(resultA.events)?.finalContent as Record<string, unknown>
    )?.document;
    const finalB = (
      terminalPayload(resultB.events)?.finalContent as Record<string, unknown>
    )?.document;

    expect(finalA).toEqual(docA);
    expect(finalB).toEqual(docB);
    expect(finalA).not.toEqual(finalB);
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
    const finalContent = payload?.finalContent as Record<string, unknown>;

    for (const partial of partials) {
      expect(partial.data.committed).not.toBe(true);
      expect(partial.data.committable).not.toBe(true);
      expect(partial.data).not.toEqual(finalContent?.document);
    }
  });
});

describe("T-D6-24 prose_path_unchanged_by_this_slice", () => {
  it("does not invoke prose guards on the structured broker path", async () => {
    const incrementalSpy = vi.spyOn(proseGuards, "checkIncrementalGuards");
    const fullSpy = vi.spyOn(proseGuards, "runFullGuardSet");

    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: structuredChunksFor(VALID_DOCUMENT),
    });

    expect(incrementalSpy).not.toHaveBeenCalled();
    expect(fullSpy).not.toHaveBeenCalled();
    expect(eventsOfType(events, "partial_structured").length).toBeGreaterThan(0);
    expect(eventsOfType(events, "text_delta")).toHaveLength(0);
    expect(eventsOfType(events, "completed")).toHaveLength(1);
  });
});

describe("T-D6-28 broker_validation_failure_terminal", () => {
  it("emits a single failed/validation_failed terminal for complete-but-invalid output", async () => {
    const invalidDoc = { severity: "mild" };
    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: [JSON.stringify(invalidDoc)],
    });

    expect(eventsOfType(events, "completed")).toHaveLength(0);
    const failed = eventsOfType(events, "failed");
    expect(failed).toHaveLength(1);
    expect(failed[0]?.data.code).toBe("validation_failed");
  });
});

describe("T-D6-29 broker_bounded_repair_seam", () => {
  it("attempts one budgeted re-ask when the manifest repairPolicy allows it", async () => {
    const invalidDoc = { severity: "mild" };
    const reask = vi.fn<ReaskPort>(async () => ({
      output: {
        raw: JSON.stringify(VALID_DOCUMENT),
        transportValid: true,
      },
      usage: { tokens: 55, cost: 0.0015 },
    }));

    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: [JSON.stringify(invalidDoc)],
      repairPolicy: { allowed: true, maxAttempts: 1 },
      reask,
    });

    expect(reask).toHaveBeenCalledOnce();
    expect(eventsOfType(events, "failed")).toHaveLength(0);
    const completed = eventsOfType(events, "completed");
    expect(completed).toHaveLength(1);
    const finalContent = (
      terminalPayload(events)?.finalContent as Record<string, unknown>
    )?.document;
    expect(finalContent).toEqual(VALID_DOCUMENT);
  });
});

describe("T-D6-30 broker_truncated_guard_reachable", () => {
  it("fails validation_failed when the chunk source reports truncation", async () => {
    const { events } = await runStructuredBrokerHarness({
      mode: "structured",
      chunks: structuredChunksFor(VALID_DOCUMENT),
      truncated: true,
    });

    expect(eventsOfType(events, "completed")).toHaveLength(0);
    const failed = eventsOfType(events, "failed");
    expect(failed).toHaveLength(1);
    expect(failed[0]?.data.code).toBe("validation_failed");
  });
});
