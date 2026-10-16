import type { TaxonomyCode } from "../../src/errors";
import type { InteractionMode } from "../../src/manifest";
import {
  pushTerminalEvent,
  type AdapterEventSink,
  type AdapterEventSourceFactory,
  type AdapterStreamContext,
  type TerminalEventKind,
} from "../../src/adapter";

/** Test-harness-only stub controller (Clarification Q2). Must not ship in src/. */
export interface StubEventSourceController {
  complete(result?: unknown): void;
  fail(code: TaxonomyCode): void;
  idle(): void | Promise<void>;
  abort(): void;
  attemptDuplicateTerminal(kind: TerminalEventKind): void;
  requestContext(contextRequest: unknown): void;
}

export type StubEventSourceFactory = AdapterEventSourceFactory;

/**
 * Mode-gated canned stub for H1 / conversational terminal tests.
 * Lives in the test harness only — not exported from src/adapter.ts.
 *
 * Emission of `context_requested` always goes through production
 * `pushTerminalEvent` so the conversational-only gate is exercised there
 * (not by a silent stub-side downgrade).
 */
export function createModeGatedStubEventSource(
  interactionMode: InteractionMode,
  terminalKind: TerminalEventKind,
  contextRequest: unknown = [],
): StubEventSourceFactory {
  return (sink: AdapterEventSink, context: AdapterStreamContext) => {
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
        pushTerminalEvent(sink, context, "context_requested", interactionMode, {
          context_request: request,
        });
      },
    };

    if (terminalKind === "context_requested") {
      try {
        controller.requestContext(contextRequest);
      } catch (error) {
        // Production `pushTerminalEvent` refused (single_shot). End the stream
        // with a permitted terminal kind so the adapter still completes.
        if (interactionMode === "conversational") {
          throw error;
        }
        controller.fail("internal_error");
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
