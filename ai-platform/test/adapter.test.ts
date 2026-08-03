import { afterEach, describe, expect, it, vi } from "vitest";
import { CANONICAL_CHUNK_KINDS } from "../src/contracts/canonical";
import {
  buildErrorBody,
  isTaxonomyCode,
  liveHttpStatusForCode,
  type TaxonomyCode,
} from "../src/errors";
import * as referenceModule from "../src/reference";
import {
  handleAdapterRequest,
  INGRESS_BODY_SIZE_LIMIT,
  type AdapterEventSink,
  type AdapterSseEvent,
  type AdapterStreamContext,
  type HandleAdapterRequestOptions,
  type StubEventSourceController,
  type StubEventSourceFactory,
  type TerminalEventKind,
} from "../src/adapter";

const REFERENCE_PATTERN = /^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/;
const ULID_PATTERN = /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/;

const TERMINAL_EVENT_KINDS = ["completed", "failed", "cancelled"] as const;
const CONTENT_EVENT_KINDS = [...CANONICAL_CHUNK_KINDS];

const VALID_BODY = {
  installation: "installation:test-001",
  capability: "visit.summary@v1",
  prompt_version: "2026-07-31",
};

const DEFAULT_HEADERS = {
  "content-type": "application/json",
  "x-idempotency-key": "idem-a6-test-001",
  "x-trace-id": "01ARZ3NDEKTSV4RRFFQ69G5FAV",
  "x-capability-version": "1.0.0",
};

type HeaderName =
  | "x-idempotency-key"
  | "x-trace-id"
  | "x-capability-version";

interface WellFormedRequestOptions {
  body?: unknown;
  headers?: Record<string, string>;
  omitHeaders?: HeaderName[];
}

/** T001 — builds a well-formed POST /v1/requests with valid JSON body and the three headers. */
function buildWellFormedRequest(
  options: WellFormedRequestOptions = {},
): Request {
  const headers = new Headers({
    ...DEFAULT_HEADERS,
    ...options.headers,
  });

  for (const omitted of options.omitHeaders ?? []) {
    headers.delete(omitted);
  }

  const body = options.body ?? VALID_BODY;
  const bodyText = typeof body === "string" ? body : JSON.stringify(body);

  return new Request("http://test.local/v1/requests", {
    method: "POST",
    headers,
    body: bodyText,
  });
}

function isTerminalEventType(type: string): type is TerminalEventKind {
  return (TERMINAL_EVENT_KINDS as readonly string[]).includes(type);
}

function isContentEventType(type: string): boolean {
  return (CONTENT_EVENT_KINDS as readonly string[]).includes(type);
}

function isTaxonomyErrorBody(body: unknown): boolean {
  if (!body || typeof body !== "object") {
    return false;
  }
  const record = body as Record<string, unknown>;
  return (
    typeof record.code === "string" &&
    isTaxonomyCode(record.code) &&
    typeof record.request_reference === "string" &&
    typeof record.trace_id === "string" &&
    typeof record.retry_safe === "boolean"
  );
}

function parseSseBlock(block: string): AdapterSseEvent | null {
  const trimmed = block.trim();
  if (!trimmed) {
    return null;
  }

  let eventType = "";
  let dataText = "";

  for (const line of trimmed.split("\n")) {
    if (line.startsWith("event:")) {
      eventType = line.slice("event:".length).trim();
    } else if (line.startsWith("data:")) {
      dataText = line.slice("data:".length).trim();
    }
  }

  if (!eventType || !dataText) {
    return null;
  }

  const data = JSON.parse(dataText) as Record<string, unknown>;
  const traceId =
    typeof data.trace_id === "string" ? data.trace_id : "";

  return {
    type: eventType,
    data,
    trace_id: traceId,
  };
}

function parseSseText(text: string): AdapterSseEvent[] {
  return text
    .split(/\n\n+/)
    .map(parseSseBlock)
    .filter((event): event is AdapterSseEvent => event !== null);
}

async function collectSseEvents(response: Response): Promise<AdapterSseEvent[]> {
  const text = await response.text();
  return parseSseText(text);
}

async function readSseEventsFromStream(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  onEvents?: (events: AdapterSseEvent[]) => void,
): Promise<AdapterSseEvent[]> {
  const decoder = new TextDecoder();
  let buffer = "";
  const events: AdapterSseEvent[] = [];

  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    buffer += decoder.decode(value, { stream: true });
    const parts = buffer.split("\n\n");
    buffer = parts.pop() ?? "";
    for (const part of parts) {
      const parsed = parseSseBlock(part);
      if (parsed) {
        events.push(parsed);
        onEvents?.(events);
      }
    }
  }

  if (buffer.trim()) {
    const parsed = parseSseBlock(buffer);
    if (parsed) {
      events.push(parsed);
      onEvents?.(events);
    }
  }

  return events;
}

function countTerminalEvents(events: AdapterSseEvent[]): number {
  return events.filter((event) => isTerminalEventType(event.type)).length;
}

/**
 * T001 — in-process stub that injects canned accepted, heartbeat, and terminal
 * sequences directly into the adapter event sink.
 */
function createCannedStubEventSource(
  plan: (
    sink: AdapterEventSink,
    context: AdapterStreamContext,
    controller: StubEventSourceController,
  ) => void | Promise<void>,
): StubEventSourceFactory {
  return (sink, context) => {
    const controller: StubEventSourceController = {
      complete(result = { status: "ok" }) {
        sink.push({
          type: "completed",
          data: { result, trace_id: context.traceId },
          trace_id: context.traceId,
        });
      },
      fail(code: TaxonomyCode) {
        const errorBody = buildErrorBody({
          code,
          requestReference: context.requestReference,
          traceId: context.traceId,
        });
        sink.push({
          type: "failed",
          data: { ...errorBody },
          trace_id: context.traceId,
        });
      },
      async idle() {
        sink.push({
          type: "heartbeat",
          data: { trace_id: context.traceId },
          trace_id: context.traceId,
        });
      },
      abort() {
        sink.push({
          type: "cancelled",
          data: { trace_id: context.traceId },
          trace_id: context.traceId,
        });
      },
      attemptDuplicateTerminal(kind: TerminalEventKind) {
        if (kind === "completed") {
          controller.complete();
          return;
        }
        if (kind === "failed") {
          controller.fail("internal_error");
          return;
        }
        controller.abort();
      },
    };

    void Promise.resolve(plan(sink, context, controller));
    return controller;
  };
}

function captureContextStub(): {
  options: HandleAdapterRequestOptions;
  getContext: () => AdapterStreamContext | undefined;
} {
  let captured: AdapterStreamContext | undefined;

  return {
    options: {
      stubEventSource: (sink, context) => {
        captured = context;
        return createCannedStubEventSource(() => undefined)(sink, context);
      },
    },
    getContext: () => captured,
  };
}

describe("adapter integration harness (T001)", () => {
  it("shares the ingress body-size limit constant with the adapter module", () => {
    expect(typeof INGRESS_BODY_SIZE_LIMIT).toBe("number");
    expect(INGRESS_BODY_SIZE_LIMIT).toBeGreaterThan(0);
  });
});

describe("T-A6-T1 oversized body rejected before any work (T002)", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("rejects a body one byte over the ingress limit as request_too_large HTTP 413 with A2 error body", async () => {
    const referenceSpy = vi.spyOn(referenceModule, "generateRequestReference");
    const oversizedBody = "x".repeat(INGRESS_BODY_SIZE_LIMIT + 1);
    const request = buildWellFormedRequest({ body: oversizedBody });

    const response = await handleAdapterRequest(request);

    expect(response.status).toBe(413);
    expect(response.headers.get("content-type")).toContain("application/json");

    const body = (await response.json()) as Record<string, unknown>;
    expect(body.code).toBe("request_too_large");
    expect(isTaxonomyErrorBody(body)).toBe(true);
    expect(body.request_reference).toBe("");
    expect(body.trace_id).toBe("");
    expect(response.headers.get("content-type")).not.toContain(
      "text/event-stream",
    );
    expect(referenceSpy).not.toHaveBeenCalled();
  });
});

describe("T-A6-T2 idempotency key parsed (T003)", () => {
  it("parses x-idempotency-key and exposes it to later stages", async () => {
    const idempotencyKey = "idem-parsed-key-42";
    const { options, getContext } = captureContextStub();
    const request = buildWellFormedRequest({
      headers: { "x-idempotency-key": idempotencyKey },
    });

    const response = await handleAdapterRequest(request, options);
    expect(response.status).toBe(200);
    expect(getContext()?.headers.idempotencyKey).toBe(idempotencyKey);
  });
});

describe("T-A6-T3 trace id parsed and propagated (T004)", () => {
  it("parses x-trace-id and propagates it on the stream context", async () => {
    const traceId = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
    const { options, getContext } = captureContextStub();
    const request = buildWellFormedRequest({
      headers: { "x-trace-id": traceId },
    });

    const response = await handleAdapterRequest(request, options);
    expect(response.status).toBe(200);
    expect(getContext()?.traceId).toBe(traceId);
    expect(getContext()?.headers.traceId).toBe(traceId);
  });

  it("uses resolveTraceId ULID when x-trace-id is absent", async () => {
    const { options, getContext } = captureContextStub();
    const request = buildWellFormedRequest({
      omitHeaders: ["x-trace-id"],
    });

    const response = await handleAdapterRequest(request, options);
    expect(response.status).toBe(200);

    const traceId = getContext()?.traceId;
    expect(traceId).toBeDefined();
    expect(traceId).toMatch(ULID_PATTERN);
    expect(traceId).toBe(getContext()?.headers.traceId);
  });
});

describe("T-A6-T4 capability version pin parsed (T005)", () => {
  it("parses x-capability-version and exposes it to later stages", async () => {
    const capabilityVersion = "2026.07.31";
    const { options, getContext } = captureContextStub();
    const request = buildWellFormedRequest({
      headers: { "x-capability-version": capabilityVersion },
    });

    const response = await handleAdapterRequest(request, options);
    expect(response.status).toBe(200);
    expect(getContext()?.headers.capabilityVersion).toBe(capabilityVersion);
  });
});

describe("T-A6-T5 malformed or missing required headers rejected (T006)", () => {
  it.each([
    {
      case: "missing x-idempotency-key",
      omitHeaders: ["x-idempotency-key"] as HeaderName[],
      headers: undefined,
    },
    {
      case: "malformed x-trace-id",
      omitHeaders: undefined,
      headers: { "x-trace-id": "not-a-valid-trace-id!!!" },
    },
    {
      case: "missing x-capability-version",
      omitHeaders: ["x-capability-version"] as HeaderName[],
      headers: undefined,
    },
  ])(
    "rejects $case with no taxonomy error body and no stream",
    async ({ omitHeaders, headers }) => {
      const request = buildWellFormedRequest({ omitHeaders, headers });
      const response = await handleAdapterRequest(request);

      expect(response.headers.get("content-type")).not.toContain(
        "text/event-stream",
      );

      const raw = await response.text();
      if (raw.length > 0) {
        let parsed: unknown;
        try {
          parsed = JSON.parse(raw);
        } catch {
          parsed = null;
        }
        expect(isTaxonomyErrorBody(parsed)).toBe(false);
      }
    },
  );
});

describe("T-A6-T6 stream opens with accepted exactly once (T007)", () => {
  it("emits accepted carrying the request reference before any content or terminal event", async () => {
    const stub = createCannedStubEventSource(async (_sink, _context, controller) => {
      await controller.idle();
      controller.complete();
    });

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      stubEventSource: stub,
    });

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/event-stream");

    const events = await collectSseEvents(response);
    const acceptedEvents = events.filter((event) => event.type === "accepted");
    expect(acceptedEvents).toHaveLength(1);

    const firstIndex = events.findIndex((event) => event.type === "accepted");
    expect(firstIndex).toBe(0);

    const beforeAccepted = events.slice(0, firstIndex);
    const afterAccepted = events.slice(firstIndex + 1);
    expect(
      beforeAccepted.some(
        (event) =>
          isContentEventType(event.type) || isTerminalEventType(event.type),
      ),
    ).toBe(false);
    expect(
      afterAccepted.findIndex(
        (event) =>
          isContentEventType(event.type) || isTerminalEventType(event.type),
      ),
    ).toBeGreaterThanOrEqual(0);
  });
});

describe("T-A6-T7 heartbeat while idle (T008)", () => {
  it("emits heartbeat while idle and heartbeat is neither content nor terminal", async () => {
    const stub = createCannedStubEventSource(async (_sink, _context, controller) => {
      await controller.idle();
      controller.complete();
    });

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      stubEventSource: stub,
    });

    const events = await collectSseEvents(response);
    const heartbeatEvents = events.filter((event) => event.type === "heartbeat");
    expect(heartbeatEvents.length).toBeGreaterThanOrEqual(1);

    for (const heartbeat of heartbeatEvents) {
      expect(isContentEventType(heartbeat.type)).toBe(false);
      expect(isTerminalEventType(heartbeat.type)).toBe(false);
    }
  });
});

describe("T-A6-T12 accepted reference and trace id on every event (T009)", () => {
  it("accepted reference matches A2 format and trace id is on every emitted event", async () => {
    const traceId = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
    const stub = createCannedStubEventSource(async (_sink, _context, controller) => {
      await controller.idle();
      controller.complete();
    });

    const response = await handleAdapterRequest(
      buildWellFormedRequest({ headers: { "x-trace-id": traceId } }),
      { stubEventSource: stub },
    );

    const events = await collectSseEvents(response);
    expect(events.length).toBeGreaterThan(0);

    const accepted = events.find((event) => event.type === "accepted");
    expect(accepted).toBeDefined();
    expect(accepted?.data.request_reference).toMatch(REFERENCE_PATTERN);

    for (const event of events) {
      expect(event.trace_id).toBe(traceId);
      expect(event.data.trace_id).toBe(traceId);
    }
  });
});

describe("T-A6-T8 stream completes with one completed terminal (T010)", () => {
  it("ends with exactly one completed terminal event and no second terminal", async () => {
    const stub = createCannedStubEventSource((_sink, _context, controller) => {
      controller.complete({ validated: true });
    });

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      stubEventSource: stub,
    });

    const events = await collectSseEvents(response);
    const completed = events.filter((event) => event.type === "completed");
    expect(completed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
  });
});

describe("T-A6-T9 stream fails with one failed terminal (T011)", () => {
  it("ends with exactly one failed terminal carrying a taxonomy code", async () => {
    const failureCode: TaxonomyCode = "provider_unavailable";
    const stub = createCannedStubEventSource((_sink, _context, controller) => {
      controller.fail(failureCode);
    });

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      stubEventSource: stub,
    });

    const events = await collectSseEvents(response);
    const failed = events.filter((event) => event.type === "failed");
    expect(failed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(failed[0]?.data.code).toBe(failureCode);
    expect(isTaxonomyCode(failed[0]?.data.code as string)).toBe(true);
  });
});

describe("T-A6-T10 client close yields cancelled terminal (T012)", () => {
  it("ends with exactly one cancelled terminal and cancelled is not an HTTP status on the socket", async () => {
    expect(liveHttpStatusForCode("cancelled")).toBeNull();

    const stub = createCannedStubEventSource(async (_sink, _context, controller) => {
      await controller.idle();
      controller.abort();
    });

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      stubEventSource: stub,
    });

    expect(response.status).not.toBe(499);
    expect(response.status).toBe(200);

    const reader = response.body!.getReader();
    const events = await readSseEventsFromStream(reader);

    const cancelled = events.filter((event) => event.type === "cancelled");
    expect(cancelled).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
  });
});

describe("T-A6-T11 no second terminal after the first (T013)", () => {
  it.each([
  { path: "completion after completed", first: "completed" as const },
  { path: "failure after failed", first: "failed" as const },
  { path: "abort after cancelled", first: "cancelled" as const },
  { path: "duplicate close after cancelled", first: "cancelled" as const, duplicateClose: true },
])(
  "does not emit a second terminal on $path",
  async ({ first, duplicateClose }) => {
    const stub = createCannedStubEventSource(
      async (_sink, _context, controller) => {
        if (first === "completed") {
          controller.complete();
          controller.attemptDuplicateTerminal("failed");
          controller.attemptDuplicateTerminal("cancelled");
          return;
        }
        if (first === "failed") {
          controller.fail("validation_failed");
          controller.attemptDuplicateTerminal("completed");
          controller.attemptDuplicateTerminal("cancelled");
          return;
        }
        controller.abort();
        if (duplicateClose) {
          controller.abort();
        }
        controller.attemptDuplicateTerminal("completed");
        controller.attemptDuplicateTerminal("failed");
      },
    );

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      stubEventSource: stub,
    });

    const events = await collectSseEvents(response);
    expect(countTerminalEvents(events)).toBe(1);
  },
);
});
