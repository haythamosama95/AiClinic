import {
  buildErrorBody,
  liveHttpStatusForCode,
  supplementaryFieldsForCode,
  type TaxonomyCode,
} from "./errors";
import { buildContextRequiredResponse, type ContextRequiredFailure } from "./context/validator";
import { noopLogger, type LoggerFactory } from "./logger";
import { validateContextRequest } from "./context/context-request";
import type { InteractionMode } from "./manifest";
import { generateRequestReference } from "./reference";
import { resolveTraceId } from "./trace";

/** Transport ingress body-size limit (bytes). Shared with tests via Clarification Q1. */
export const INGRESS_BODY_SIZE_LIMIT = 1_048_576;

export const TERMINAL_EVENT_KINDS = [
  "completed",
  "failed",
  "cancelled",
  // Conversational-only/latent — unreachable until a conversational capability ships.
  "context_requested",
] as const;

export type TerminalEventKind = (typeof TERMINAL_EVENT_KINDS)[number];

export interface AdapterSseEvent {
  type: string;
  data: Record<string, unknown>;
  trace_id: string;
}

export type AdapterDisconnectReason = "client_close";

export interface AdapterStreamContext {
  traceId: string;
  requestReference: string;
  headers: {
    idempotencyKey: string;
    traceId: string;
    capabilityVersion: string;
  };
  /** Connection-scoped abort; fires on client disconnect / request signal abort. */
  signal: AbortSignal;
}

export interface AdapterEventSink {
  push(event: AdapterSseEvent): void;
}

/**
 * Optional handle returned by the event source so the adapter can notify
 * disconnect (D4 broker `disconnect(reason)`).
 */
export type AdapterEventSourceHandle = {
  disconnect?(reason: AdapterDisconnectReason): void;
};

/**
 * Injected event source (broker in production; test harness stubs in tests).
 * Required — without one the adapter fails fast with 503.
 * Return may expose `disconnect` so client abort reaches the broker.
 */
export type AdapterEventSourceFactory = (
  sink: AdapterEventSink,
  context: AdapterStreamContext,
) => AdapterEventSourceHandle | void;

export type PreAcceptResult =
  | { ok: true; degradedNotice?: boolean }
  | {
      ok: false;
      code: TaxonomyCode;
      retryAfter?: number;
      contextRequired?: ContextRequiredFailure;
    };

export interface PreAcceptInput {
  request: Request;
  bodyText: string;
  body: Record<string, unknown>;
  headers: {
    idempotencyKey: string;
    traceId: string;
    capabilityVersion: string;
  };
  requestReference: string;
}

export type PreAcceptGate = (input: PreAcceptInput) => Promise<PreAcceptResult>;

export interface HandleAdapterRequestOptions {
  eventSource?: AdapterEventSourceFactory;
  preAccept?: PreAcceptGate;
  makeLog?: LoggerFactory;
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
    // Conversational-only/latent — unreachable until a conversational capability ships.
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

  const contextRequest = payload?.context_request;
  if (contextRequest === undefined) {
    throw new Error("context_requested requires a context_request payload");
  }
  // Conversational-only/latent — unreachable until a conversational capability ships.
  const validation = validateContextRequest(contextRequest);
  if (!validation.ok) {
    throw new Error(
      `context_requested payload is not a conforming context request: ${validation.reason}`,
    );
  }

  sink.push({
    type: "context_requested",
    data: {
      context_request: contextRequest,
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

function preAcceptFailureResponse(
  code: TaxonomyCode,
  requestReference: string,
  traceId: string,
  retryAfter?: number,
  contextRequired?: ContextRequiredFailure,
): Response {
  const body =
    code === "context_required" && contextRequired !== undefined
      ? buildContextRequiredResponse(contextRequired, requestReference, traceId)
      : {
          ...buildErrorBody({ code, requestReference, traceId }),
          ...supplementaryFieldsForCode(code, { retryAfter }),
        };
  const status = liveHttpStatusForCode(code);
  return new Response(JSON.stringify(body), {
    status: status ?? 500,
    headers: { "content-type": "application/json" },
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

/**
 * Body fields the adapter consults for routing / tier selection.
 * Empty by design — `routing_tier` is gateway-set from admission (§4.3.7 / §8.8).
 */
export const ADAPTER_ROUTING_BODY_FIELDS: readonly string[] = [];

/** Parse ingress JSON; returns null when the body is not a plain object. */
export function parseAdapterRequestBody(
  bodyText: string,
): Record<string, unknown> | null {
  return parseRequestBody(bodyText);
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
  const ingressLog = options.makeLog?.("adapter.ts") ?? noopLogger;

  const bodyResult = await readBodyWithinLimit(request);
  if (!bodyResult.ok) {
    if (bodyResult.reason === "too_large") {
      ingressLog.info("ingress_body_too_large", {
        limit_bytes: INGRESS_BODY_SIZE_LIMIT,
      });
      return ingressTooLargeResponse();
    }
    ingressLog.error("ingress_body_read_error");
    return adapterParseFailureResponse();
  }

  const parsedBody = parseRequestBody(bodyResult.text);
  if (parsedBody === null) {
    ingressLog.error("ingress_body_parse_failed");
    return adapterParseFailureResponse();
  }

  const parsedHeaders = parseRequiredHeaders(request);
  if (!parsedHeaders) {
    ingressLog.error("ingress_headers_invalid");
    return adapterParseFailureResponse();
  }

  const log = options.makeLog?.("adapter.ts", {
    trace_id: parsedHeaders.traceId,
  }) ?? noopLogger;
  log.debug("ingress_headers_parsed", {
    capability_version: parsedHeaders.capabilityVersion,
  });

  let requestReference: string | undefined;
  let degradedNotice: boolean | undefined;

  if (options.preAccept) {
    requestReference = generateRequestReference();
    log.debug("pre_accept_start", { request_reference: requestReference });
    const gate = await options.preAccept({
      request,
      bodyText: bodyResult.text,
      body: parsedBody,
      headers: parsedHeaders,
      requestReference,
    });
    if (!gate.ok) {
      log.info("pre_accept_rejected", {
        code: gate.code,
        request_reference: requestReference,
      });
      return preAcceptFailureResponse(
        gate.code,
        requestReference,
        parsedHeaders.traceId,
        gate.retryAfter,
        gate.contextRequired,
      );
    }
    degradedNotice = gate.degradedNotice;
    log.debug("pre_accept_passed", { request_reference: requestReference });
  }

  const eventSource = options.eventSource;
  if (!eventSource) {
    log.error("event_source_missing");
    return eventSourceRequiredResponse();
  }

  requestReference ??= generateRequestReference();

  const disconnectController = new AbortController();
  const context: AdapterStreamContext = {
    traceId: parsedHeaders.traceId,
    requestReference,
    headers: {
      idempotencyKey: parsedHeaders.idempotencyKey,
      traceId: parsedHeaders.traceId,
      capabilityVersion: parsedHeaders.capabilityVersion,
    },
    signal: disconnectController.signal,
  };

  // Connection-scoped only — no per-request server state object (§4.4 / §9.7).
  let terminalEmitted = false;
  let streamController: ReadableStreamDefaultController<Uint8Array> | null =
    null;
  let eventSourceHandle: AdapterEventSourceHandle | undefined;
  let disconnectNotified = false;
  const abortedAtEntry = request.signal.aborted;

  const markCancelledWithoutEnqueue = (): void => {
    terminalEmitted = true;
  };

  const notifyDisconnect = (reason: AdapterDisconnectReason): void => {
    if (disconnectNotified) {
      return;
    }
    disconnectNotified = true;
    log.info("sse_client_disconnect", {
      reason,
      request_reference: requestReference,
    });
    if (!disconnectController.signal.aborted) {
      disconnectController.abort();
    }
    eventSourceHandle?.disconnect?.(reason);
  };

  const sink: AdapterEventSink = {
    push(event: AdapterSseEvent): void {
      if (terminalEmitted) {
        return;
      }
      if (isTerminalEventType(event.type)) {
        terminalEmitted = true;
        log.info("sse_terminal_event", {
          event_type: event.type,
          request_reference: requestReference,
        });
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
        degradedNotice,
      });
      controller.enqueue(
        new TextEncoder().encode(encodeSseEvent(acceptedEvent)),
      );
      log.info("sse_accepted", {
        request_reference: requestReference,
        degraded_notice: degradedNotice ?? false,
      });

      if (abortedAtEntry || request.signal.aborted) {
        markCancelledWithoutEnqueue();
        notifyDisconnect("client_close");
        safeCloseController(controller);
        return;
      }

      const handle = eventSource(sink, context);
      if (handle && typeof handle === "object") {
        eventSourceHandle = handle;
      }
    },
    cancel() {
      // Client disconnected — nobody left to receive `cancelled` on the wire (contract §4).
      // Notify the event source so the broker can abort the in-flight provider fetch.
      markCancelledWithoutEnqueue();
      notifyDisconnect("client_close");
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
        notifyDisconnect("client_close");
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
