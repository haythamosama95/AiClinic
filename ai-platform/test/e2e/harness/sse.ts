export type SseEvent = {
  event: string;
  data: Record<string, unknown>;
};

const TERMINAL_EVENTS = new Set([
  "completed",
  "failed",
  "cancelled",
  "context_requested",
]);

export function parseSseText(text: string): SseEvent[] {
  const events: SseEvent[] = [];
  const blocks = text.split("\n\n").filter((block) => block.trim().length > 0);
  for (const block of blocks) {
    const lines = block.split("\n");
    let event = "";
    let data: Record<string, unknown> = {};
    for (const line of lines) {
      if (line.startsWith("event: ")) {
        event = line.slice(7);
      } else if (line.startsWith("data: ")) {
        const raw = line.slice(6);
        try {
          data = JSON.parse(raw) as Record<string, unknown>;
        } catch {
          data = { raw };
        }
      }
    }
    if (event) {
      events.push({ event, data });
    }
  }
  return events;
}

export async function parseSseEvents(response: Response): Promise<SseEvent[]> {
  const text = await response.text();
  return parseSseText(text);
}

export function sseEventNames(events: SseEvent[]): string[] {
  return events.map((event) => event.event);
}

export function terminalEventTypes(events: SseEvent[]): string[] {
  return events
    .filter((event) => TERMINAL_EVENTS.has(event.event))
    .map((event) => event.event);
}

export type SseSequenceMode = "exact" | "prefix" | "subsequence";

/**
 * Assert an SSE event-name sequence.
 * - `prefix` (default): stream starts with `expected`
 * - `exact`: names equal `expected`
 * - `subsequence`: `expected` appears in order, not necessarily contiguous
 */
export function assertSseSequence(
  events: SseEvent[],
  expected: string[],
  mode: SseSequenceMode = "prefix",
): void {
  const actual = sseEventNames(events);
  if (mode === "exact") {
    if (actual.length !== expected.length || actual.some((name, i) => name !== expected[i])) {
      throw new Error(
        `SSE sequence mismatch (exact): expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
      );
    }
    return;
  }
  if (mode === "prefix") {
    if (actual.length < expected.length) {
      throw new Error(
        `SSE sequence too short (prefix): expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
      );
    }
    for (let index = 0; index < expected.length; index += 1) {
      if (actual[index] !== expected[index]) {
        throw new Error(
          `SSE sequence mismatch (prefix) at [${index}]: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
        );
      }
    }
    return;
  }
  let cursor = 0;
  for (const name of expected) {
    const found = actual.indexOf(name, cursor);
    if (found === -1) {
      throw new Error(
        `SSE subsequence missing ${JSON.stringify(name)}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
      );
    }
    cursor = found + 1;
  }
}
