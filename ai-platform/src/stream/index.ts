import type { AdapterSseEvent } from "../adapter";
import { buildErrorBody, type TaxonomyCode } from "../errors";
import {
  checkIncrementalGuards,
  runFullGuardSet,
  type ProseGuardThresholds,
} from "./prose-guards";

export type { ProseGuardThresholds, GuardViolationKind } from "./prose-guards";

/**
 * Broker-facing chunk union. Aligns with D3 `InvocationSink` emissions:
 * `emitStreamText(text)` → string chunks; `emitRegenerating()` → regenerating.
 * See `createChunkSourceFromInvocationEvents` for the named adapter bridge.
 */
export type StreamChunk = string | { kind: "regenerating" };

/** Event shape produced by an InvocationSink-compatible relay into the broker. */
export type InvocationStreamEvent =
  | { kind: "text"; text: string }
  | { kind: "regenerating" };

export interface ChunkSource {
  /**
   * Live partial usage at cancel time. Called when cancel settles — must reflect
   * tokens actually generated before the cancel point, not a constructor snapshot.
   * Absent or undefined → credit sink is not called (FR-011).
   */
  getPartialUsage?(): { tokens: number; cost: number } | undefined;
  /** True when the provider finished because of an output-length limit. */
  wasTruncated?(): boolean;
  stream(input: { signal: AbortSignal }): AsyncIterable<StreamChunk>;
}

/**
 * Named adapter (Spec Kit Consumes): bridges D3 invocation stream events into
 * a `ChunkSource` the broker can pull. Production wiring later feeds this from
 * the invocation loop; regenerating is preserved as a first-class chunk.
 */
export function createChunkSourceFromInvocationEvents(
  events: AsyncIterable<InvocationStreamEvent>,
  getPartialUsage?: () => { tokens: number; cost: number } | undefined,
): ChunkSource {
  return {
    getPartialUsage,
    async *stream({
      signal,
    }: {
      signal: AbortSignal;
    }): AsyncIterable<StreamChunk> {
      for await (const event of events) {
        if (signal.aborted) {
          return;
        }
        if (event.kind === "regenerating") {
          yield { kind: "regenerating" };
        } else {
          yield event.text;
        }
      }
    },
  };
}

export interface StreamBrokerEventSink {
  push(event: AdapterSseEvent): void;
}

export interface HeartbeatScheduleHandle {
  cancel(): void;
  /** Reset silence window — called by the broker on each relayed content chunk. */
  notifyActivity(): void;
}

export interface HeartbeatTicker {
  schedule(callback: () => void): HeartbeatScheduleHandle;
}

export interface CreditSink {
  (input: {
    requestId: string;
    usage: { tokens: number; cost: number };
    partial: boolean;
  }): void;
}

export interface JournalTerminalSink {
  (record: {
    requestId: string;
    state: "cancelled" | "completed" | "failed";
    terminalErrorCode?: TaxonomyCode;
  }): void;
}

export interface StreamBrokerOptions {
  traceId: string;
  requestId: string;
  /** Client-facing request reference carried on terminal `failed` error bodies (§5.4). */
  requestReference: string;
  eventSink: StreamBrokerEventSink;
  chunkSource: ChunkSource;
  heartbeatTicker: HeartbeatTicker;
  creditSink: CreditSink;
  journalTerminalSink: JournalTerminalSink;
  guardThresholds: ProseGuardThresholds;
}

export interface StreamBrokerController {
  run(): Promise<void>;
  disconnect(reason: "client_close" | "network_drop"): void;
  fetchSignal: AbortSignal;
}

function isRegeneratingChunk(
  chunk: StreamChunk,
): chunk is { kind: "regenerating" } {
  return typeof chunk === "object" && chunk !== null && chunk.kind === "regenerating";
}

function isAbortError(error: unknown): boolean {
  if (error === null || error === undefined) {
    return false;
  }
  if (typeof error === "object") {
    const name = (error as { name?: string }).name;
    if (name === "AbortError") {
      return true;
    }
    const code = (error as { code?: string }).code;
    if (code === "ABORT_ERR") {
      return true;
    }
  }
  return false;
}

/**
 * Iterate an async iterable, racing each `next()` against abort so a
 * signal-ignoring source cannot hang the broker after disconnect.
 */
async function* abortableAsyncIterate<T>(
  iterable: AsyncIterable<T>,
  signal: AbortSignal,
): AsyncIterable<T> {
  const iterator = iterable[Symbol.asyncIterator]();
  try {
    while (!signal.aborted) {
      const nextPromise = iterator.next();
      const result = await new Promise<IteratorResult<T>>((resolve, reject) => {
        if (signal.aborted) {
          resolve({ done: true, value: undefined as T });
          return;
        }
        const onAbort = () => {
          resolve({ done: true, value: undefined as T });
        };
        signal.addEventListener("abort", onAbort, { once: true });
        nextPromise.then(
          (value) => {
            signal.removeEventListener("abort", onAbort);
            resolve(value);
          },
          (error: unknown) => {
            signal.removeEventListener("abort", onAbort);
            reject(error);
          },
        );
      });
      if (result.done) {
        return;
      }
      yield result.value;
    }
  } finally {
    // Do not await: return() queues behind a pending next() on hung /
    // signal-ignoring sources and never settles (§3.2.6).
    if (typeof iterator.return === "function") {
      void Promise.resolve(iterator.return(undefined)).catch(() => undefined);
    }
  }
}

export function createStreamBroker(
  options: StreamBrokerOptions,
): StreamBrokerController {
  const abortController = new AbortController();
  let disconnected = false;
  let terminalEmitted = false;
  let heartbeatHandle: HeartbeatScheduleHandle | null = null;

  const emitEvent = (event: AdapterSseEvent): void => {
    if (terminalEmitted) {
      return;
    }
    options.eventSink.push(event);
  };

  const emitTerminalOnce = (event: AdapterSseEvent): void => {
    if (terminalEmitted) {
      return;
    }
    terminalEmitted = true;
    heartbeatHandle?.cancel();
    options.eventSink.push(event);
  };

  const safeCredit = (usage: { tokens: number; cost: number }): void => {
    try {
      options.creditSink({
        requestId: options.requestId,
        usage,
        partial: true,
      });
    } catch {
      // Settlement failure must not suppress the terminal SSE event (§5.5 rule 4).
    }
  };

  const safeJournal = (record: {
    requestId: string;
    state: "cancelled" | "completed" | "failed";
    terminalErrorCode?: TaxonomyCode;
  }): void => {
    try {
      options.journalTerminalSink(record);
    } catch {
      // Settlement failure must not suppress the terminal SSE event.
    }
  };

  const handleCancel = (): void => {
    if (terminalEmitted) {
      return;
    }

    emitTerminalOnce({
      type: "cancelled",
      data: { trace_id: options.traceId },
      trace_id: options.traceId,
    });

    const usage = options.chunkSource.getPartialUsage?.();
    if (usage !== undefined) {
      safeCredit(usage);
    }

    safeJournal({
      requestId: options.requestId,
      state: "cancelled",
    });
  };

  const handleFailed = (code: TaxonomyCode): void => {
    if (terminalEmitted) {
      return;
    }

    // Mirror adapter pushTerminalEvent("failed") — full §5.4 error body.
    const errorBody = buildErrorBody({
      code,
      requestReference: options.requestReference,
      traceId: options.traceId,
    });

    emitTerminalOnce({
      type: "failed",
      data: { ...errorBody },
      trace_id: options.traceId,
    });

    safeJournal({
      requestId: options.requestId,
      state: "failed",
      terminalErrorCode: code,
    });
  };

  const handleCompleted = (assembled: string): void => {
    if (terminalEmitted) {
      return;
    }

    emitTerminalOnce({
      type: "completed",
      data: {
        result: {
          finalContent: {
            text: assembled,
            authoritative: true,
          },
        },
        trace_id: options.traceId,
      },
      trace_id: options.traceId,
    });

    safeJournal({
      requestId: options.requestId,
      state: "completed",
    });
  };

  const runProse = async (): Promise<void> => {
    const { traceId, chunkSource, heartbeatTicker, guardThresholds } = options;
    let assembled = "";
    let sequence = 0;

    heartbeatHandle = heartbeatTicker.schedule(() => {
      emitEvent({
        type: "heartbeat",
        data: { trace_id: traceId },
        trace_id: traceId,
      });
    });

    try {
      const rawStream = chunkSource.stream({
        signal: abortController.signal,
      });

      for await (const chunk of abortableAsyncIterate(
        rawStream,
        abortController.signal,
      )) {
        if (terminalEmitted) {
          return;
        }

        if (disconnected || abortController.signal.aborted) {
          handleCancel();
          return;
        }

        if (isRegeneratingChunk(chunk)) {
          emitEvent({
            type: "regenerating",
            data: { trace_id: traceId },
            trace_id: traceId,
          });
          assembled = "";
          sequence = 0;
          heartbeatHandle?.notifyActivity();
          continue;
        }

        assembled += chunk;

        if (checkIncrementalGuards(chunk, assembled, guardThresholds) !== null) {
          abortController.abort();
          handleFailed("validation_failed");
          return;
        }

        emitEvent({
          type: "text_delta",
          data: {
            text: chunk,
            sequence,
            provisional: true,
          },
          trace_id: traceId,
        });
        sequence += 1;
        heartbeatHandle?.notifyActivity();

        if (disconnected || abortController.signal.aborted) {
          handleCancel();
          return;
        }
      }

      if (!terminalEmitted && (disconnected || abortController.signal.aborted)) {
        handleCancel();
        return;
      }

      if (terminalEmitted) {
        return;
      }

      // Truncated prose must not complete as authoritative (§4.3.9 / §3.2.2).
      if (chunkSource.wasTruncated?.() === true) {
        handleFailed("validation_failed");
        return;
      }

      const fullViolation = runFullGuardSet(assembled, guardThresholds);
      if (fullViolation !== null) {
        handleFailed("validation_failed");
        return;
      }

      handleCompleted(assembled);
    } catch (error: unknown) {
      if (terminalEmitted) {
        return;
      }
      if (
        disconnected ||
        abortController.signal.aborted ||
        isAbortError(error)
      ) {
        handleCancel();
        return;
      }
      handleFailed("internal_error");
    } finally {
      heartbeatHandle?.cancel();
    }
  };

  return {
    run: runProse,
    disconnect(_reason: "client_close" | "network_drop") {
      if (terminalEmitted) {
        return;
      }
      disconnected = true;
      abortController.abort();
      // Emit cancelled synchronously so a signal-ignoring source cannot hang
      // the one-terminal / credit / journal guarantees (§5.5 rule 4).
      handleCancel();
    },
    fetchSignal: abortController.signal,
  };
}
