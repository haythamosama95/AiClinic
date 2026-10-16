import { describe, expect, it } from "vitest";
import { createStructuredLogger, resolveTraceId } from "../src/trace";

const ULID_PATTERN = /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/;

describe("trace id propagation (T22)", () => {
  it("carries a supplied trace id on every log line emitted for that request", () => {
    const suppliedTraceId = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
    const resolved = resolveTraceId(suppliedTraceId);
    expect(resolved).toBe(suppliedTraceId);

    const { logs, logger } = createStructuredLogger({
      traceId: resolved,
      requestReference: "7QK4-2B9F",
      installation: "inst-1",
      capability: "cap-1",
      promptVersion: "v1",
    });

    logger.info("first line");
    logger.info("second line", { step: "guard" });
    logger.error("third line");

    expect(logs.length).toBeGreaterThan(0);
    for (const line of logs) {
      expect(line.trace_id).toBe(suppliedTraceId);
    }
  });
});

describe("trace id generation (T23)", () => {
  it("generates a ULID when absent and propagates it identically to a caller-supplied id", () => {
    const generated = resolveTraceId(null);
    expect(generated).toMatch(ULID_PATTERN);
    expect(generated).toHaveLength(26);

    const { logs, logger } = createStructuredLogger({
      traceId: generated,
      requestReference: "7QK4-2B9F",
      installation: "inst-1",
      capability: "cap-1",
      promptVersion: "v1",
    });

    logger.info("generated trace line one");
    logger.info("generated trace line two");

    expect(logs.length).toBeGreaterThan(0);
    for (const line of logs) {
      expect(line.trace_id).toBe(generated);
    }

    const supplied = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
    const resolvedSupplied = resolveTraceId(supplied);
    expect(resolvedSupplied).toBe(supplied);
  });
});
