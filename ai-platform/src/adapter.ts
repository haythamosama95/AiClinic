import {
  buildErrorBody,
  liveHttpStatusForCode,
  type TaxonomyCode,
} from "./errors";
import type { InteractionMode } from "./manifest";
import { generateRequestReference } from "./reference";
import { resolveTraceId } from "./trace";

/** Transport ingress body-size limit (bytes). Shared with tests via Clarification Q1. */
export const INGRESS_BODY_SIZE_LIMIT = 1_048_576;

const ULID_PATTERN = /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/;

export const TERMINAL_EVENT_KINDS = [
  "completed",
  "failed",
  "cancelled",
  "context_requested",
] as const;

export type TerminalEventKind = (typeof TERMINAL_EVENT_KINDS)[number];

export interface AdapterSseEvent {
  type: string;
  data: Record<string, unknown>;
  trace_id: string;
}

export interface AdapterStreamContext {
  traceId: string;
  requestReference: string;
  headers: {
    idempotencyKey: string;
    traceId: string;
    capabilityVersion: string;
  };
}

export interface AdapterEventSink {
  push(event: AdapterSseEvent): void;
}

export interface StubEventSourceController {
  complete(result?: unknown): void;
  fail(code: TaxonomyCode): void;
  idle(): void | Promise<void>;
  abort(): void;
  attemptDuplicateTerminal(kind: TerminalEventKind): void;
  requestContext(contextRequest: unknown): void;
}

export type StubEventSourceFactory = (
  sink: AdapterEventSink,
  context: AdapterStreamContext,
) => StubEventSourceController;

export interface HandleAdapterRequestOptions {
  stubEventSource?: StubEventSourceFactory;
  degradedNotice?: boolean;
}

export interface AcceptedSseEventInput {
  requestReference: string;
  traceId: string;
  degradedNotice?: boolean;
}

export function buildAcceptedSseEvent(
  input: AcceptedSseEventInput,
): AdapterSseEvent {
  const data: Record<string, unknown> = {
    request_reference: input.requestReference,
    trace_id: input.traceId,
  };
  if (input.degradedNotice) {
    data.degraded_notice = true;
  }
  return {
    type: "accepted",
    data,
    trace_id: input.traceId,
  };
}

function isTerminalEventType(type: string): type is TerminalEventKind {
  return (TERMINAL_EVENT_KINDS as readonly string[]).includes(type);
}

export function isTerminalEventKind(type: string): boolean {
  return isTerminalEventType(type);
}

export function pushTerminalEvent(
  sink: AdapterEventSink,
  context: AdapterStreamContext,
  kind: TerminalEventKind,
  interactionMode: InteractionMode,
  payload?: Record<string, unknown>,
): void {
  if (kind === "context_requested" && interactionMode !== "conversational") {
    throw new Error("context_requested is conversational-only");
  }

  if (kind === "completed") {
    sink.push({
      type: "completed",
      data: { result: payload?.result ?? {}, trace_id: context.traceId },
      trace_id: context.traceId,
    });
    return;
  }

  if (kind === "failed") {
    const code = (payload?.code as TaxonomyCode | undefined) ?? "internal_error";
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
    return;
  }

  if (kind === "cancelled") {
    sink.push({
      type: "cancelled",
      data: { trace_id: context.traceId },
      trace_id: context.traceId,
    });
    return;
  }

  sink.push({
    type: "context_requested",
    data: {
      context_request: payload?.context_request ?? [],
      trace_id: context.traceId,
    },
    trace_id: context.traceId,
  });
}

export function createModeGatedStubEventSource(
  interactionMode: InteractionMode,
  terminalKind: TerminalEventKind,
  contextRequest: unknown = [],
): StubEventSourceFactory {
  return (sink, context) => {
    const controller: StubEventSourceController = {
      complete(result = { status: "ok" }) {
        pushTerminalEvent(sink, context, "completed", interactionMode, {
          result,
        });
      },
      fail(code: TaxonomyCode) {
        pushTerminalEvent(sink, context, "failed", interactionMode, { code });
      },
      idle() {
        sink.push({
          type: "heartbeat",
          data: { trace_id: context.traceId },
          trace_id: context.traceId,
        });
      },
      abort() {
        pushTerminalEvent(sink, context, "cancelled", interactionMode);
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
        if (kind === "context_requested") {
          controller.requestContext(contextRequest);
          return;
        }
        controller.abort();
      },
      requestContext(request) {
        if (interactionMode !== "conversational") {
          controller.complete();
          return;
        }
        pushTerminalEvent(sink, context, "context_requested", interactionMode, {
          context_request: request,
        });
      },
    };

    if (terminalKind === "context_requested") {
      if (interactionMode === "conversational") {
        controller.requestContext(contextRequest);
      } else {
        controller.complete();
      }
    } else if (terminalKind === "completed") {
      controller.complete();
    } else if (terminalKind === "failed") {
      controller.fail("internal_error");
    } else if (terminalKind === "cancelled") {
      controller.abort();
    }

    return controller;
  };
}

function isValidSuppliedTraceId(value: string): boolean {
  return ULID_PATTERN.test(value);
}

function encodeSseEvent(event: AdapterSseEvent): string {
  return `event: ${event.type}\ndata: ${JSON.stringify(event.data)}\n\n`;
}

function ingressTooLargeResponse(): Response {
  const body = buildErrorBody({
    code: "request_too_large",
    requestReference: "",
    traceId: "",
  });
  const status = liveHttpStatusForCode("request_too_large");
  return new Response(JSON.stringify(body), {
    status: status ?? 413,
    headers: { "content-type": "application/json" },
  });
}

function adapterParseFailureResponse(): Response {
  // §5.4: no taxonomy code maps to a bare 400; adapter-local parse failures use 422.
  return new Response(null, {
    status: 422,
    headers: { "content-type": "text/plain" },
  });
}

interface ParsedHeaders {
  idempotencyKey: string;
  traceId: string;
  capabilityVersion: string;
}

function parseRequiredHeaders(
  request: Request,
): ParsedHeaders | null {
  const idempotencyKey = request.headers.get("x-idempotency-key")?.trim();
  if (!idempotencyKey) {
    return null;
  }

  const capabilityVersion = request.headers.get("x-capability-version")?.trim();
  if (!capabilityVersion) {
    return null;
  }

  const suppliedTraceId = request.headers.get("x-trace-id");
  if (suppliedTraceId !== null && suppliedTraceId.trim() === "") {
    return null;
  }
  if (suppliedTraceId !== null && !isValidSuppliedTraceId(suppliedTraceId)) {
    return null;
  }

  const traceId = resolveTraceId(suppliedTraceId);

  return {
    idempotencyKey,
    traceId,
    capabilityVersion,
  };
}

function defaultStubEventSource(
  _sink: AdapterEventSink,
  _context: AdapterStreamContext,
): StubEventSourceController {
  const noop = (): void => undefined;
  return {
    complete: noop,
    fail: noop,
    idle: noop,
    abort: noop,
    attemptDuplicateTerminal: noop,
    requestContext: noop,
  };
}

export async function handleAdapterRequest(
  request: Request,
  options: HandleAdapterRequestOptions = {},
): Promise<Response> {
  let bodyText: string;
  try {
    bodyText = await request.text();
  } catch {
    return adapterParseFailureResponse();
  }

  if (bodyText.length > INGRESS_BODY_SIZE_LIMIT) {
    return ingressTooLargeResponse();
  }

  const parsedHeaders = parseRequiredHeaders(request);
  if (!parsedHeaders) {
    return adapterParseFailureResponse();
  }

  const requestReference = generateRequestReference();
  const context: AdapterStreamContext = {
    traceId: parsedHeaders.traceId,
    requestReference,
    headers: {
      idempotencyKey: parsedHeaders.idempotencyKey,
      traceId: parsedHeaders.traceId,
      capabilityVersion: parsedHeaders.capabilityVersion,
    },
  };

  let terminalEmitted = false;
  let streamController: ReadableStreamDefaultController<Uint8Array> | null =
    null;

  const sink: AdapterEventSink = {
    push(event: AdapterSseEvent): void {
      if (terminalEmitted) {
        return;
      }
      if (isTerminalEventType(event.type)) {
        terminalEmitted = true;
      }
      streamController?.enqueue(new TextEncoder().encode(encodeSseEvent(event)));
      if (isTerminalEventType(event.type)) {
        streamController?.close();
      }
    },
  };

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      streamController = controller;

      const acceptedEvent = buildAcceptedSseEvent({
        requestReference,
        traceId: context.traceId,
        degradedNotice: options.degradedNotice,
      });
      controller.enqueue(
        new TextEncoder().encode(encodeSseEvent(acceptedEvent)),
      );

      const stubFactory = options.stubEventSource ?? defaultStubEventSource;
      stubFactory(sink, context);
    },
    cancel() {
      if (terminalEmitted) {
        return;
      }
      const cancelledEvent: AdapterSseEvent = {
        type: "cancelled",
        data: { trace_id: context.traceId },
        trace_id: context.traceId,
      };
      terminalEmitted = true;
      streamController?.enqueue(
        new TextEncoder().encode(encodeSseEvent(cancelledEvent)),
      );
      streamController?.close();
    },
  });

  if (request.signal.aborted) {
    // Handled by stream cancel when consumer aborts.
  } else {
    request.signal.addEventListener(
      "abort",
      () => {
        if (!terminalEmitted) {
          const cancelledEvent: AdapterSseEvent = {
            type: "cancelled",
            data: { trace_id: context.traceId },
            trace_id: context.traceId,
          };
          terminalEmitted = true;
          streamController?.enqueue(
            new TextEncoder().encode(encodeSseEvent(cancelledEvent)),
          );
          streamController?.close();
        }
      },
      { once: true },
    );
  }

  return new Response(stream, {
    status: 200,
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive",
    },
  });
}