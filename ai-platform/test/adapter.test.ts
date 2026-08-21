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
  type AdapterEventSourceFactory,
  type AdapterSseEvent,
  type AdapterStreamContext,
  type HandleAdapterRequestOptions,
  type TerminalEventKind,
} from "../src/adapter";
import type { StubEventSourceController } from "./helpers/adapter-stub";

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
  signal?: AbortSignal;
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
    signal: options.signal,
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
 * sequences directly into the adapter event sink (test harness only).
 */
function createCannedStubEventSource(
  plan: (
    sink: AdapterEventSink,
    context: AdapterStreamContext,
    controller: StubEventSourceController,
  ) => void | Promise<void>,
): AdapterEventSourceFactory {
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
      requestContext() {
        // unused in A6 harness
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
      eventSource: (sink, context) => {
        captured = context;
        return createCannedStubEventSource((_s, _c, controller) => {
          controller.complete();
        })(sink, context);
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

    const response = await handleAdapterRequest(request, {
      eventSource: createCannedStubEventSource(() => undefined),
    });

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

  it("rejects oversized body with malformed headers as 413 not 422 (ordering)", async () => {
    const referenceSpy = vi.spyOn(referenceModule, "generateRequestReference");
    const oversizedBody = "x".repeat(INGRESS_BODY_SIZE_LIMIT + 1);
    const request = buildWellFormedRequest({
      body: oversizedBody,
      omitHeaders: ["x-idempotency-key", "x-capability-version"],
    });

    const response = await handleAdapterRequest(request, {
      eventSource: createCannedStubEventSource(() => undefined),
    });

    expect(response.status).toBe(413);
    expect(referenceSpy).not.toHaveBeenCalled();
  });

  it("rejects when Content-Length exceeds the limit before consuming the body", async () => {
    const referenceSpy = vi.spyOn(referenceModule, "generateRequestReference");
    const request = new Request("http://test.local/v1/requests", {
      method: "POST",
      headers: {
        ...DEFAULT_HEADERS,
        "content-length": String(INGRESS_BODY_SIZE_LIMIT + 1),
      },
      // Body intentionally smaller than declared Content-Length — gate must use the header.
      body: JSON.stringify(VALID_BODY),
    });

    const response = await handleAdapterRequest(request, {
      eventSource: createCannedStubEventSource(() => undefined),
    });

    expect(response.status).toBe(413);
    expect(referenceSpy).not.toHaveBeenCalled();
  });

  it("rejects a multi-byte UTF-8 body that exceeds the byte limit (not UTF-16 length)", async () => {
    // Arabic letter "م" is U+0645 — one UTF-16 code unit, two UTF-8 bytes.
    const arabic = "م";
    const bytesPerChar = new TextEncoder().encode(arabic).byteLength;
    expect(bytesPerChar).toBe(2);

    const charsNeeded = Math.floor(INGRESS_BODY_SIZE_LIMIT / bytesPerChar) + 1;
    const oversized = arabic.repeat(charsNeeded);
    expect(oversized.length).toBeLessThanOrEqual(INGRESS_BODY_SIZE_LIMIT);
    expect(new TextEncoder().encode(oversized).byteLength).toBeGreaterThan(
      INGRESS_BODY_SIZE_LIMIT,
    );

    const response = await handleAdapterRequest(
      buildWellFormedRequest({ body: oversized }),
      { eventSource: createCannedStubEventSource(() => undefined) },
    );

    expect(response.status).toBe(413);
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

  it("accepts any non-empty client-supplied trace id including non-ULID", async () => {
    const traceId = "550e8400-e29b-41d4-a716-446655440000";
    const { options, getContext } = captureContextStub();
    const request = buildWellFormedRequest({
      headers: { "x-trace-id": traceId },
    });

    const response = await handleAdapterRequest(request, options);
    expect(response.status).toBe(200);
    expect(getContext()?.traceId).toBe(traceId);
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

describe("T-A6-T5 malformed body or headers rejected (T006)", () => {
  it.each([
    {
      case: "missing x-idempotency-key",
      omitHeaders: ["x-idempotency-key"] as HeaderName[],
      headers: undefined,
      body: undefined,
    },
    {
      case: "empty x-idempotency-key",
      omitHeaders: undefined,
      headers: { "x-idempotency-key": "   " },
      body: undefined,
    },
    {
      case: "missing x-capability-version",
      omitHeaders: ["x-capability-version"] as HeaderName[],
      headers: undefined,
      body: undefined,
    },
    {
      case: "empty x-capability-version",
      omitHeaders: undefined,
      headers: { "x-capability-version": "\t" },
      body: undefined,
    },
    {
      case: "present-but-empty x-trace-id",
      omitHeaders: undefined,
      headers: { "x-trace-id": "  " },
      body: undefined,
    },
    {
      case: "malformed JSON body",
      omitHeaders: undefined,
      headers: undefined,
      body: "not json",
    },
    {
      case: "JSON array body",
      omitHeaders: undefined,
      headers: undefined,
      body: "[1,2,3]",
    },
    {
      case: "JSON null body",
      omitHeaders: undefined,
      headers: undefined,
      body: "null",
    },
  ])(
    "rejects $case with bare 422, no taxonomy error body, and no stream",
    async ({ omitHeaders, headers, body }) => {
      const request = buildWellFormedRequest({ omitHeaders, headers, body });
      const response = await handleAdapterRequest(request, {
        eventSource: createCannedStubEventSource(() => undefined),
      });

      expect(response.status).toBe(422);
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
      eventSource: stub,
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

describe("T-A6-T7 heartbeat framing while idle (T008)", () => {
  it("frames an injected heartbeat as neither content nor terminal", async () => {
    const stub = createCannedStubEventSource(async (_sink, _context, controller) => {
      await controller.idle();
      controller.complete();
    });

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      eventSource: stub,
    });

    const events = await collectSseEvents(response);
    const heartbeatEvents = events.filter((event) => event.type === "heartbeat");
    expect(heartbeatEvents.length).toBeGreaterThanOrEqual(1);

    for (const heartbeat of heartbeatEvents) {
      expect(isContentEventType(heartbeat.type)).toBe(false);
      expect(isTerminalEventType(heartbeat.type)).toBe(false);
    }

    // Heartbeat does not satisfy the one-terminal-event invariant.
    expect(countTerminalEvents(events)).toBe(1);
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
      { eventSource: stub },
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
      eventSource: stub,
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
      eventSource: stub,
    });

    const events = await collectSseEvents(response);
    const failed = events.filter((event) => event.type === "failed");
    expect(failed).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
    expect(failed[0]?.data.code).toBe(failureCode);
    expect(isTaxonomyCode(failed[0]?.data.code as string)).toBe(true);
  });
});

describe("T-A6-T10 connection-scoped cancel without dead-socket write (T012)", () => {
  it("ends with exactly one cancelled terminal via stub abort and cancelled is not an HTTP status", async () => {
    expect(liveHttpStatusForCode("cancelled")).toBeNull();

    const stub = createCannedStubEventSource(async (_sink, _context, controller) => {
      await controller.idle();
      controller.abort();
    });

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      eventSource: stub,
    });

    expect(response.status).not.toBe(499);
    expect(response.status).toBe(200);

    const reader = response.body!.getReader();
    const events = await readSseEventsFromStream(reader);

    const cancelled = events.filter((event) => event.type === "cancelled");
    expect(cancelled).toHaveLength(1);
    expect(countTerminalEvents(events)).toBe(1);
  });

  it("reader.cancel() mid-stream marks terminal without throwing or writing cancelled", async () => {
    let resolveHold: (() => void) | undefined;
    const hold = new Promise<void>((resolve) => {
      resolveHold = resolve;
    });

    const stub = createCannedStubEventSource(async (_sink, _context, controller) => {
      await controller.idle();
      await hold;
      // Attempt a late terminal after client disconnect — sink must drop it.
      controller.complete();
    });

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      eventSource: stub,
    });
    expect(response.status).toBe(200);

    const reader = response.body!.getReader();
    const seen: AdapterSseEvent[] = [];

    // Read until accepted + heartbeat, then cancel the reader (real disconnect path).
    await new Promise<void>((resolve, reject) => {
      const decoder = new TextDecoder();
      let buffer = "";
      const pump = async () => {
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) {
              resolve();
              return;
            }
            buffer += decoder.decode(value, { stream: true });
            const parts = buffer.split("\n\n");
            buffer = parts.pop() ?? "";
            for (const part of parts) {
              const parsed = parseSseBlock(part);
              if (parsed) {
                seen.push(parsed);
              }
            }
            if (
              seen.some((e) => e.type === "accepted") &&
              seen.some((e) => e.type === "heartbeat")
            ) {
              await expect(reader.cancel()).resolves.toBeUndefined();
              resolve();
              return;
            }
          }
        } catch (error) {
          reject(error);
        }
      };
      void pump();
    });

    resolveHold?.();
    // Allow the stub's late complete() to run against the marked-terminal sink.
    await new Promise((r) => setTimeout(r, 20));

    expect(seen.some((e) => e.type === "cancelled")).toBe(false);
    expect(countTerminalEvents(seen)).toBe(0);
  });

  it("already-aborted request signal closes without hanging or writing cancelled", async () => {
    const controller = new AbortController();
    controller.abort();

    let eventSourceInvoked = false;
    const response = await handleAdapterRequest(
      buildWellFormedRequest({ signal: controller.signal }),
      {
        eventSource: () => {
          eventSourceInvoked = true;
        },
      },
    );

    expect(response.status).toBe(200);
    const events = await collectSseEvents(response);
    expect(events.some((e) => e.type === "accepted")).toBe(true);
    expect(events.some((e) => e.type === "cancelled")).toBe(false);
    expect(eventSourceInvoked).toBe(false);
  });

  it("request.signal abort mid-stream marks terminal without writing cancelled", async () => {
    const abortController = new AbortController();
    let resolveHold: (() => void) | undefined;
    const hold = new Promise<void>((resolve) => {
      resolveHold = resolve;
    });

    const stub = createCannedStubEventSource(async (_sink, _context, ctrl) => {
      await ctrl.idle();
      await hold;
      ctrl.complete();
    });

    const response = await handleAdapterRequest(
      buildWellFormedRequest({ signal: abortController.signal }),
      { eventSource: stub },
    );

    const reader = response.body!.getReader();
    const seen: AdapterSseEvent[] = [];
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const parts = buffer.split("\n\n");
      buffer = parts.pop() ?? "";
      for (const part of parts) {
        const parsed = parseSseBlock(part);
        if (parsed) seen.push(parsed);
      }
      if (
        seen.some((e) => e.type === "accepted") &&
        seen.some((e) => e.type === "heartbeat")
      ) {
        abortController.abort();
        break;
      }
    }

    resolveHold?.();
    await new Promise((r) => setTimeout(r, 20));

    expect(seen.some((e) => e.type === "cancelled")).toBe(false);
  });
});

describe("T-A6-T11 no second terminal after the first (T013)", () => {
  it.each([
    { path: "completion after completed", first: "completed" as const },
    { path: "failure after failed", first: "failed" as const },
    { path: "abort after cancelled", first: "cancelled" as const },
    {
      path: "duplicate close after cancelled",
      first: "cancelled" as const,
      duplicateClose: true,
    },
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
        eventSource: stub,
      });

      const events = await collectSseEvents(response);
      expect(countTerminalEvents(events)).toBe(1);
    },
  );

  it("keeps terminalEmitted connection-scoped with no per-request state object", async () => {
    const contexts: AdapterStreamContext[] = [];
    const stub = createCannedStubEventSource((sink, context, controller) => {
      contexts.push(context);
      controller.complete();
    });

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      eventSource: stub,
    });
    const events = await collectSseEvents(response);
    expect(countTerminalEvents(events)).toBe(1);

    // Context is a plain closure-local object — no server-side request registry.
    expect(contexts).toHaveLength(1);
    expect(Object.keys(contexts[0]!)).toEqual([
      "traceId",
      "requestReference",
      "headers",
      "signal",
    ]);
    expect(contexts[0]!.signal).toBeInstanceOf(AbortSignal);
    expect(contexts[0]!.signal.aborted).toBe(false);
  });
});

describe("T-A6-R-disconnect event source notified on client abort (§2.3)", () => {
  it("calls eventSource.disconnect exactly once on reader.cancel() mid-stream", async () => {
    let resolveHold: (() => void) | undefined;
    const hold = new Promise<void>((resolve) => {
      resolveHold = resolve;
    });
    const disconnectReasons: string[] = [];
    let contextSignal: AbortSignal | undefined;

    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      eventSource: (sink, context) => {
        contextSignal = context.signal;
        void (async () => {
          sink.push({
            type: "heartbeat",
            data: { trace_id: context.traceId },
            trace_id: context.traceId,
          });
          await hold;
          sink.push({
            type: "completed",
            data: { result: {}, trace_id: context.traceId },
            trace_id: context.traceId,
          });
        })();
        return {
          disconnect(reason) {
            disconnectReasons.push(reason);
          },
        };
      },
    });

    const reader = response.body!.getReader();
    const seen: AdapterSseEvent[] = [];
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const parts = buffer.split("\n\n");
      buffer = parts.pop() ?? "";
      for (const part of parts) {
        const parsed = parseSseBlock(part);
        if (parsed) seen.push(parsed);
      }
      if (
        seen.some((e) => e.type === "accepted") &&
        seen.some((e) => e.type === "heartbeat")
      ) {
        await expect(reader.cancel()).resolves.toBeUndefined();
        break;
      }
    }

    resolveHold?.();
    await new Promise((r) => setTimeout(r, 20));

    expect(disconnectReasons).toEqual(["client_close"]);
    expect(contextSignal?.aborted).toBe(true);
    expect(seen.some((e) => e.type === "cancelled")).toBe(false);
  });

  it("calls eventSource.disconnect once on request.signal abort mid-stream", async () => {
    const abortController = new AbortController();
    let resolveHold: (() => void) | undefined;
    const hold = new Promise<void>((resolve) => {
      resolveHold = resolve;
    });
    const disconnectReasons: string[] = [];
    let contextSignal: AbortSignal | undefined;

    const response = await handleAdapterRequest(
      buildWellFormedRequest({ signal: abortController.signal }),
      {
        eventSource: (sink, context) => {
          contextSignal = context.signal;
          void (async () => {
            sink.push({
              type: "heartbeat",
              data: { trace_id: context.traceId },
              trace_id: context.traceId,
            });
            await hold;
            sink.push({
              type: "completed",
              data: { result: {}, trace_id: context.traceId },
              trace_id: context.traceId,
            });
          })();
          return {
            disconnect(reason) {
              disconnectReasons.push(reason);
            },
          };
        },
      },
    );

    const reader = response.body!.getReader();
    const seen: AdapterSseEvent[] = [];
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const parts = buffer.split("\n\n");
      buffer = parts.pop() ?? "";
      for (const part of parts) {
        const parsed = parseSseBlock(part);
        if (parsed) seen.push(parsed);
      }
      if (
        seen.some((e) => e.type === "accepted") &&
        seen.some((e) => e.type === "heartbeat")
      ) {
        abortController.abort();
        break;
      }
    }

    resolveHold?.();
    await new Promise((r) => setTimeout(r, 20));

    expect(disconnectReasons).toEqual(["client_close"]);
    expect(contextSignal?.aborted).toBe(true);
  });
});

describe("pre_accept_rate_limited_retry_after_from_admission_hint", () => {
  it("puts the preAccept retryAfter hint on the HTTP JSON body, not a hardcoded 60", async () => {
    const hint = 15;
    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      preAccept: async () => ({
        ok: false,
        code: "rate_limited",
        retryAfter: hint,
      }),
      eventSource: createCannedStubEventSource((_sink, _context, controller) => {
        controller.complete();
      }),
    });

    expect(response.status).toBe(liveHttpStatusForCode("rate_limited"));
    expect(response.headers.get("content-type")).toContain("application/json");
    const body = (await response.json()) as {
      code?: string;
      retry_after?: number;
    };
    expect(body.code).toBe("rate_limited");
    expect(body.retry_after).toBe(hint);
  });

  it("falls back to 60 when rate_limited has no admission retry hint", async () => {
    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      preAccept: async () => ({ ok: false, code: "rate_limited" }),
      eventSource: createCannedStubEventSource((_sink, _context, controller) => {
        controller.complete();
      }),
    });

    expect(response.status).toBe(liveHttpStatusForCode("rate_limited"));
    const body = (await response.json()) as { retry_after?: number };
    expect(body.retry_after).toBe(60);
  });
});

describe("accepted_degraded_notice_is_per_request_from_preAccept", () => {
  it("emits degraded_notice on accepted when preAccept returns it for this request", async () => {
    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      preAccept: async () => ({ ok: true, degradedNotice: true }),
      eventSource: createCannedStubEventSource((_sink, _context, controller) => {
        controller.complete();
      }),
    });

    expect(response.status).toBe(200);
    const events = await collectSseEvents(response);
    expect(events[0]?.type).toBe("accepted");
    expect(events[0]?.data.degraded_notice).toBe(true);
  });

  it("omits degraded_notice when preAccept succeeds without it", async () => {
    const response = await handleAdapterRequest(buildWellFormedRequest(), {
      preAccept: async () => ({ ok: true }),
      eventSource: createCannedStubEventSource((_sink, _context, controller) => {
        controller.complete();
      }),
    });

    expect(response.status).toBe(200);
    const events = await collectSseEvents(response);
    expect(events[0]?.type).toBe("accepted");
    expect(events[0]?.data.degraded_notice).toBeUndefined();
  });

  it("does not reuse a static adapter option across requests", async () => {
    const first = await handleAdapterRequest(buildWellFormedRequest(), {
      preAccept: async () => ({ ok: true, degradedNotice: true }),
      eventSource: createCannedStubEventSource((_sink, _context, controller) => {
        controller.complete();
      }),
    });
    const second = await handleAdapterRequest(buildWellFormedRequest(), {
      preAccept: async () => ({ ok: true }),
      eventSource: createCannedStubEventSource((_sink, _context, controller) => {
        controller.complete();
      }),
    });

    const firstAccepted = (await collectSseEvents(first))[0];
    const secondAccepted = (await collectSseEvents(second))[0];
    expect(firstAccepted?.data.degraded_notice).toBe(true);
    expect(secondAccepted?.data.degraded_notice).toBeUndefined();
  });
});

describe("T-A6-T13 fail-fast without eventSource (T013a)", () => {
  it("returns HTTP 503 and opens no stream when eventSource is missing", async () => {
    const referenceSpy = vi.spyOn(referenceModule, "generateRequestReference");
    const response = await handleAdapterRequest(buildWellFormedRequest());

    expect(response.status).toBe(503);
    expect(response.headers.get("content-type")).not.toContain(
      "text/event-stream",
    );
    expect(referenceSpy).not.toHaveBeenCalled();
    referenceSpy.mockRestore();
  });
});
