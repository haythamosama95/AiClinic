import type { AdapterSseEvent } from "../adapter";
import type { TaxonomyCode } from "../errors";
import {
  validateAndRepair,
  type BusinessRuleRegistry,
  type RepairCostSink,
  type RepairJournalSink,
  type RepairPolicy,
  type ReaskPort,
  type SafetyMarkers,
  type SchemaRegistry,
} from "../validate";

/**
 * Structured-mode stream broker (D6).
 *
 * Lives beside the D4 prose broker in `./index.ts`. Shares sink / chunk /
 * ticker shapes so callers can wire either path with the same plumbing, but
 * owns structured emission and commit-time validation (including optional
 * bounded repair).
 */

export type StreamChunk = string | { kind: "regenerating" };

/** Structured output modes only — prose lives on the D4 broker. */
export type OutputMode = "structured" | "structured_atomic";

export interface ChunkSource {
  getPartialUsage?(): { tokens: number; cost: number } | undefined;
  /** True when the provider finished because of an output-length limit. */
  wasTruncated?(): boolean;
  stream(input: { signal: AbortSignal }): AsyncIterable<StreamChunk>;
}

export interface StreamBrokerEventSink {
  push(event: AdapterSseEvent): void;
}

export interface HeartbeatTicker {
  schedule(callback: () => void): { cancel(): void; notifyActivity(): void };
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

export interface StructuredValidationConfig {
  outputSchemaRef: string | null;
  businessValidationRuleRefs: readonly string[];
  schemaRegistry: SchemaRegistry;
  ruleRegistry: BusinessRuleRegistry;
  repairPolicy: RepairPolicy;
  context?: unknown;
  safetyMarkers?: SafetyMarkers;
}

export interface StructuredStreamBrokerOptions {
  traceId: string;
  requestId: string;
  eventSink: StreamBrokerEventSink;
  chunkSource: ChunkSource;
  heartbeatTicker: HeartbeatTicker;
  creditSink: CreditSink;
  journalTerminalSink: JournalTerminalSink;
  outputMode: OutputMode;
  structuredValidation: StructuredValidationConfig;
  /** When omitted, repair is refused even if the policy allows it. */
  reask?: ReaskPort;
  repairJournalSink?: RepairJournalSink;
  repairCostSink?: RepairCostSink;
}

export interface StreamBrokerController {
  run(): Promise<void>;
  disconnect(reason: "client_close" | "network_drop"): void;
  fetchSignal: AbortSignal;
}

type HeartbeatHandle = { cancel(): void; notifyActivity(): void };

function isRegeneratingChunk(
  chunk: StreamChunk,
): chunk is { kind: "regenerating" } {
  return typeof chunk === "object" && chunk !== null && chunk.kind === "regenerating";
}

function isAbortError(error: unknown): boolean {
  if (error instanceof Error && error.name === "AbortError") {
    return true;
  }
  return (
    typeof DOMException !== "undefined" &&
    error instanceof DOMException &&
    error.name === "AbortError"
  );
}

/**
 * Yields from `iterable` until `signal` aborts, even when the source ignores
 * the abort signal passed to `stream()`. Mirrors the D4 prose broker defense.
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
    if (typeof iterator.return === "function") {
      await iterator.return(undefined);
    }
  }
}

function tryParsePartialStructured(assembled: string): unknown | null {
  try {
    return JSON.parse(assembled) as unknown;
  } catch {
    return null;
  }
}

function safeCall(fn: () => void): void {
  try {
    fn();
  } catch {
    // Sink throws must not suppress the one-terminal invariant.
  }
}

export function createStructuredStreamBroker(
  options: StructuredStreamBrokerOptions,
): StreamBrokerController {
  const { outputMode } = options;
  const abortController = new AbortController();
  let disconnected = false;
  let terminalEmitted = false;
  let heartbeatHandle: HeartbeatHandle | null = null;

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

  const journalTerminal = (
    state: "cancelled" | "completed" | "failed",
    terminalErrorCode?: TaxonomyCode,
  ): void => {
    safeCall(() => {
      options.journalTerminalSink({
        requestId: options.requestId,
        state,
        ...(terminalErrorCode !== undefined ? { terminalErrorCode } : {}),
      });
    });
  };

  const creditPartialIfPresent = (): void => {
    safeCall(() => {
      const usage = options.chunkSource.getPartialUsage?.();
      if (usage) {
        options.creditSink({
          requestId: options.requestId,
          usage,
          partial: true,
        });
      }
    });
  };

  const handleCancel = (): void => {
    if (terminalEmitted) {
      return;
    }

    // Terminal SSE first, then sinks — sink throws cannot suppress terminal.
    emitTerminalOnce({
      type: "cancelled",
      data: { trace_id: options.traceId },
      trace_id: options.traceId,
    });
    creditPartialIfPresent();
    journalTerminal("cancelled");
  };

  const handleFailed = (code: TaxonomyCode): void => {
    if (terminalEmitted) {
      return;
    }

    emitTerminalOnce({
      type: "failed",
      data: { code },
      trace_id: options.traceId,
    });
    journalTerminal("failed", code);
  };

  const handleValidationFailure = (): void => {
    handleFailed("validation_failed");
  };

  const completeStructured = async (assembled: string): Promise<void> => {
    const config = options.structuredValidation;

    const validation = await validateAndRepair({
      output: {
        raw: assembled,
        transportValid: true,
        truncated: options.chunkSource.wasTruncated?.() === true,
      },
      mode: outputMode === "structured_atomic" ? "structured_atomic" : "structured",
      outputSchemaRef: config.outputSchemaRef,
      businessValidationRuleRefs: config.businessValidationRuleRefs,
      repairPolicy: config.repairPolicy,
      schemaRegistry: config.schemaRegistry,
      ruleRegistry: config.ruleRegistry,
      context: config.context,
      safetyMarkers: config.safetyMarkers,
      reask: options.reask,
      repairJournalSink: options.repairJournalSink,
      repairCostSink: options.repairCostSink,
    });

    if (!validation.ok) {
      handleValidationFailure();
      return;
    }

    const validatedDocument = validation.validated;

    emitTerminalOnce({
      type: "completed",
      data: {
        result: {
          finalContent: {
            document: validatedDocument,
            authoritative: true,
            _assembledFromChunks: false,
          },
        },
        trace_id: options.traceId,
      },
      trace_id: options.traceId,
    });
    journalTerminal("completed");
  };

  const run = async (): Promise<void> => {
    const { traceId, chunkSource, heartbeatTicker } = options;
    let assembled = "";
    let sequence = 0;
    const emitPartials = outputMode === "structured";

    heartbeatHandle = heartbeatTicker.schedule(() => {
      emitEvent({
        type: "heartbeat",
        data: { trace_id: traceId },
        trace_id: traceId,
      });
    });

    try {
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
            continue;
          }

          assembled += chunk;

          if (outputMode === "structured_atomic") {
            emitEvent({
              type: "progress",
              data: { trace_id: traceId, bytesReceived: assembled.length },
              trace_id: traceId,
            });
          } else if (emitPartials) {
            const partialDocument = tryParsePartialStructured(assembled);
            emitEvent({
              type: "partial_structured",
              data: {
                sequence,
                provisional: true,
                document: partialDocument ?? { _partial: true },
                committed: false,
                committable: false,
              },
              trace_id: traceId,
            });
            sequence += 1;
          }

          heartbeatHandle?.notifyActivity();

          if (disconnected || abortController.signal.aborted) {
            handleCancel();
            return;
          }
        }
      } catch (error) {
        if (
          disconnected ||
          abortController.signal.aborted ||
          isAbortError(error)
        ) {
          handleCancel();
          return;
        }
        handleFailed("internal_error");
        return;
      }

      if (!terminalEmitted && (disconnected || abortController.signal.aborted)) {
        handleCancel();
        return;
      }

      if (terminalEmitted) {
        return;
      }

      await completeStructured(assembled);
    } finally {
      heartbeatHandle?.cancel();
    }
  };

  return {
    run,
    disconnect(_reason: "client_close" | "network_drop") {
      if (terminalEmitted) {
        return;
      }
      disconnected = true;
      abortController.abort();
      // Synchronous cancel so signal-ignoring sources cannot hang the terminal.
      handleCancel();
    },
    fetchSignal: abortController.signal,
  };
}
