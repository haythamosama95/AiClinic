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

/**
 * Injected event source (broker in production; test harness stubs in tests).
 * Required — without one the adapter fails fast with 503.
 */
export type AdapterEventSourceFactory = (
  sink: AdapterEventSink,
  context: AdapterStreamContext,
) => unknown;

export interface HandleAdapterRequestOptions {
  eventSource?: AdapterEventSourceFactory;
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

function encodeSseEvent(event: AdapterSseEvent): string {
  return `event: ${event.type}\ndata: ${JSON.stringify(event.data)}\n\n`;
}

function ingressTooLargeResponse(): Response {
  // Stage-1 size gate runs before headers/reference: empty fields by design (FR-006 exception).
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
  // §5.4: no taxonomy code maps to a bare 400; adapter-local parse failures use bare 422.
  return new Response(null, {
    status: 422,
    headers: { "content-type": "text/plain" },
  });
}

function eventSourceRequiredResponse(): Response {
  return new Response("event source required", {
    status: 503,
    headers: { "content-type": "text/plain" },
  });
}

interface ParsedHeaders {
  idempotencyKey: string;
  traceId: string;
  capabilityVersion: string;
}

function parseRequiredHeaders(request: Request): ParsedHeaders | null {
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

  // A2 resolveTraceId: any non-empty supplied id is accepted; ULID only when absent.
  const traceId = resolveTraceId(
    suppliedTraceId === null ? null : suppliedTraceId.trim(),
  );

  return {
    idempotencyKey,
    traceId,
    capabilityVersion,
  };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseRequestBody(bodyText: string): Record<string, unknown> | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(bodyText);
  } catch {
    return null;
  }
  if (!isPlainObject(parsed)) {
    return null;
  }
  return parsed;
}

function concatUint8Arrays(chunks: Uint8Array[], totalBytes: number): Uint8Array {
  const merged = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return merged;
}

type BodyReadResult =
  | { ok: true; text: string }
  | { ok: false; reason: "too_large" | "read_error" };

/**
 * Byte-accurate ingress gate: Content-Length pre-check when present; otherwise stream-read
 * and abort at the first chunk that would exceed the limit. Never buffers past the cap.
 */
async function readBodyWithinLimit(request: Request): Promise<BodyReadResult> {
  const contentLengthHeader = request.headers.get("content-length");
  if (contentLengthHeader !== null) {
    const declared = Number(contentLengthHeader);
    if (Number.isFinite(declared) && declared > INGRESS_BODY_SIZE_LIMIT) {
      return { ok: false, reason: "too_large" };
    }
  }

  if (request.body === null) {
    return { ok: true, text: "" };
  }

  try {
    const reader = request.body.getReader();
    const chunks: Uint8Array[] = [];
    let totalBytes = 0;

    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      if (!value || value.byteLength === 0) {
        continue;
      }
      if (totalBytes + value.byteLength > INGRESS_BODY_SIZE_LIMIT) {
        await reader.cancel();
        return { ok: false, reason: "too_large" };
      }
      chunks.push(value);
      totalBytes += value.byteLength;
    }

    const merged = concatUint8Arrays(chunks, totalBytes);
    return { ok: true, text: new TextDecoder().decode(merged) };
  } catch {
    return { ok: false, reason: "read_error" };
  }
}

function safeCloseController(
  controller: ReadableStreamDefaultController<Uint8Array> | null,
): void {
  if (!controller) {
    return;
  }
  try {
    controller.close();
  } catch {
    // Already closed or cancelled — ignore.
  }
}

export async function handleAdapterRequest(
  request: Request,
  options: HandleAdapterRequestOptions = {},
): Promise<Response> {
  const bodyResult = await readBodyWithinLimit(request);
  if (!bodyResult.ok) {
    if (bodyResult.reason === "too_large") {
      return ingressTooLargeResponse();
    }
    return adapterParseFailureResponse();
  }

  if (parseRequestBody(bodyResult.text) === null) {
    return adapterParseFailureResponse();
  }

  const parsedHeaders = parseRequiredHeaders(request);
  if (!parsedHeaders) {
    return adapterParseFailureResponse();
  }

  const eventSource = options.eventSource;
  if (!eventSource) {
    return eventSourceRequiredResponse();
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

  // Connection-scoped only — no per-request server state object (§4.4 / §9.7).
  let terminalEmitted = false;
  let streamController: ReadableStreamDefaultController<Uint8Array> | null =
    null;
  const abortedAtEntry = request.signal.aborted;

  const markCancelledWithoutEnqueue = (): void => {
    terminalEmitted = true;
  };

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
        safeCloseController(streamController);
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

      if (abortedAtEntry || request.signal.aborted) {
        markCancelledWithoutEnqueue();
        safeCloseController(controller);
        return;
      }

      eventSource(sink, context);
    },
    cancel() {
      // Client disconnected — nobody left to receive `cancelled` on the wire (contract §4).
      markCancelledWithoutEnqueue();
    },
  });

  if (!abortedAtEntry) {
    request.signal.addEventListener(
      "abort",
      () => {
        if (!terminalEmitted) {
          markCancelledWithoutEnqueue();
          safeCloseController(streamController);
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
