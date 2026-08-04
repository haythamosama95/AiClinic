import { describe, expect, it } from "vitest";
import {
  buildErrorBody,
  isTaxonomyCode,
} from "../src/errors";
import {
  handleAdapterRequest,
  isTerminalEventKind,
  pushTerminalEvent,
  TERMINAL_EVENT_KINDS,
  type AdapterEventSink,
  type AdapterStreamContext,
  type TerminalEventKind,
} from "../src/adapter";
import { createModeGatedStubEventSource } from "./helpers/adapter-stub";

const VALID_BODY = {
  installation: "installation:test-h1-001",
  capability: "chat.assistant@v1",
  prompt_version: "2026-08-02",
};

const DEFAULT_HEADERS = {
  "content-type": "application/json",
  "x-idempotency-key": "idem-h1-test-001",
  "x-trace-id": "01ARZ3NDEKTSV4RRFFQ69G5FAV",
  "x-capability-version": "1.0.0",
};

function buildRequest(): Request {
  return new Request("http://test.local/v1/requests", {
    method: "POST",
    headers: DEFAULT_HEADERS,
    body: JSON.stringify(VALID_BODY),
  });
}

function parseSseBlock(block: string): { type: string; data: Record<string, unknown> } | null {
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

  return {
    type: eventType,
    data: JSON.parse(dataText) as Record<string, unknown>,
  };
}

function parseSseText(text: string): Array<{ type: string; data: Record<string, unknown> }> {
  return text
    .split(/\n\n+/)
    .map(parseSseBlock)
    .filter((event): event is { type: string; data: Record<string, unknown> } =>
      event !== null,
    );
}

async function collectSseEvents(response: Response) {
  const text = await response.text();
  return parseSseText(text);
}

function countTerminalEvents(
  events: Array<{ type: string; data: Record<string, unknown> }>,
): number {
  return events.filter((event) => isTerminalEventKind(event.type)).length;
}

describe("context_requested_absent_from_error_taxonomy", () => {
  it("is absent from the §5.4 taxonomy and is not buildable as an error-body code", () => {
    expect(isTaxonomyCode("context_requested")).toBe(false);
    expect(TERMINAL_EVENT_KINDS).toContain("context_requested");

    expect(() =>
      buildErrorBody({
        code: "context_requested" as never,
        requestReference: "ABCD-EFGH",
        traceId: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
      }),
    ).toThrow();
  });
});

describe("single_shot_never_emits_context_requested", () => {
  it("ends with completed, failed, or cancelled and never context_requested", async () => {
    const stub = createModeGatedStubEventSource(
      "single_shot",
      "context_requested",
      [{ key: "visit.chief_complaint@v1", arguments: {} }],
    );

    const response = await handleAdapterRequest(buildRequest(), {
      eventSource: stub,
    });

    const events = await collectSseEvents(response);
    const terminalEvents = events.filter((event) =>
      isTerminalEventKind(event.type),
    );

    expect(terminalEvents).toHaveLength(1);
    expect(terminalEvents[0]?.type).not.toBe("context_requested");
    expect(
      ["completed", "failed", "cancelled"].includes(terminalEvents[0]?.type ?? ""),
    ).toBe(true);
  });

  it("rejects pushTerminalEvent for context_requested on single_shot", () => {
    const sink: AdapterEventSink = { push: () => undefined };
    const context: AdapterStreamContext = {
      traceId: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
      requestReference: "ABCD-EFGH",
      headers: {
        idempotencyKey: "idem",
        traceId: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
        capabilityVersion: "1.0.0",
      },
    };

    expect(() =>
      pushTerminalEvent(
        sink,
        context,
        "context_requested",
        "single_shot",
        { context_request: [] },
      ),
    ).toThrow();
  });
});

describe("conversational_leg_still_one_terminal_event", () => {
  it("emits exactly one terminal event when ending in context_requested", async () => {
    const contextRequest = [
      { key: "visit.chief_complaint@v1", arguments: { visit_id: "550e8400-e29b-41d4-a716-446655440000" } },
    ];

    const stub = createModeGatedStubEventSource(
      "conversational",
      "context_requested",
      contextRequest,
    );

    const response = await handleAdapterRequest(buildRequest(), {
      eventSource: stub,
    });

    const events = await collectSseEvents(response);
    expect(countTerminalEvents(events)).toBe(1);

    const terminal = events.find((event) => isTerminalEventKind(event.type));
    expect(terminal?.type).toBe("context_requested");
    expect(terminal?.data.context_request).toEqual(contextRequest);
  });
});
