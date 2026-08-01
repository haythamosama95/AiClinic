import type { AdapterSseEvent } from "../adapter";
import type { TaxonomyCode } from "../errors";
import {
  runValidationPhases,
  type BusinessRuleRegistry,
  type SafetyMarkers,
  type SchemaRegistry,
} from "../validate";
import {
  checkIncrementalGuards,
  runFullGuardSet,
  type ProseGuardThresholds,
} from "./prose-guards";

export type { ProseGuardThresholds } from "./prose-guards";

export type StreamChunk = string | { kind: "regenerating" };

export type OutputMode = "prose" | "structured" | "structured_atomic";

export interface ChunkSource {
  partialUsage?: { tokens: number; cost: number };
  stream(input: { signal: AbortSignal }): AsyncIterable<StreamChunk>;
}

export interface StreamBrokerEventSink {
  push(event: AdapterSseEvent): void;
}

export interface HeartbeatTicker {
  schedule(callback: () => void): { cancel(): void };
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
  context?: unknown;
  safetyMarkers?: SafetyMarkers;
}

export interface StreamBrokerOptions {
  traceId: string;
  requestId: string;
  eventSink: StreamBrokerEventSink;
  chunkSource: ChunkSource;
  heartbeatTicker: HeartbeatTicker;
  creditSink: CreditSink;
  journalTerminalSink: JournalTerminalSink;
  guardThresholds: ProseGuardThresholds;
  outputMode?: OutputMode;
  structuredValidation?: StructuredValidationConfig;
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

function tryParsePartialStructured(assembled: string): unknown | null {
  try {
    return JSON.parse(assembled) as unknown;
  } catch {
    return null;
  }
}

export function createStreamBroker(
  options: StreamBrokerOptions,
): StreamBrokerController {
  const outputMode = options.outputMode ?? "prose";
  const abortController = new AbortController();
  let disconnected = false;
  let terminalEmitted = false;
  let heartbeatHandle: { cancel(): void } | null = null;

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

  const handleCancel = (): void => {
    if (terminalEmitted) {
      return;
    }

    const usage = options.chunkSource.partialUsage;
    if (usage) {
      options.creditSink({
        requestId: options.requestId,
        usage,
        partial: true,
      });
    }

    options.journalTerminalSink({
      requestId: options.requestId,
      state: "cancelled",
    });

    emitTerminalOnce({
      type: "cancelled",
      data: { trace_id: options.traceId },
      trace_id: options.traceId,
    });
  };

  const handleValidationFailure = (): void => {
    emitTerminalOnce({
      type: "failed",
      data: { code: "validation_failed" },
      trace_id: options.traceId,
    });
  };

  const handleGuardFailure = (): void => {
    handleValidationFailure();
  };

  const completeStructured = (assembled: string): void => {
    const config = options.structuredValidation;
    if (!config) {
      handleValidationFailure();
      return;
    }

    const validation = runValidationPhases({
      output: { raw: assembled, transportValid: true },
      mode: outputMode === "structured_atomic" ? "structured_atomic" : "structured",
      outputSchemaRef: config.outputSchemaRef,
      businessValidationRuleRefs: config.businessValidationRuleRefs,
      schemaRegistry: config.schemaRegistry,
      ruleRegistry: config.ruleRegistry,
      context: config.context,
      safetyMarkers: config.safetyMarkers,
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
          "final content": {
            document: validatedDocument,
            authoritative: true,
            _assembledFromChunks: false,
          },
        },
        trace_id: options.traceId,
      },
      trace_id: options.traceId,
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
      for await (const chunk of chunkSource.stream({
        signal: abortController.signal,
      })) {
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

        if (checkIncrementalGuards(chunk, assembled, guardThresholds) !== null) {
          abortController.abort();
          handleGuardFailure();
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

      runFullGuardSet(assembled, guardThresholds);

      emitTerminalOnce({
        type: "completed",
        data: {
          result: {
            "final content": {
              text: assembled,
              authoritative: true,
            },
          },
          trace_id: traceId,
        },
        trace_id: traceId,
      });
    } finally {
      heartbeatHandle?.cancel();
    }
  };

  const runStructured = async (): Promise<void> => {
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
      for await (const chunk of chunkSource.stream({
        signal: abortController.signal,
      })) {
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

      completeStructured(assembled);
    } finally {
      heartbeatHandle?.cancel();
    }
  };

  const run = async (): Promise<void> => {
    if (outputMode === "prose") {
      await runProse();
      return;
    }
    await runStructured();
  };

  return {
    run,
    disconnect(_reason: "client_close" | "network_drop") {
      if (terminalEmitted) {
        return;
      }
      disconnected = true;
      abortController.abort();
    },
    fetchSignal: abortController.signal,
  };
}
