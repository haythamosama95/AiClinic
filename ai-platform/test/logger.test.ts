import { describe, expect, it } from "vitest";
import {
  createLogger,
  createLoggerFactory,
  formatLogLine,
  resolveLogVerbosity,
  verbosityFromEnv,
  type LogStatus,
} from "../src/logger";

const FIXED_TIME = () => new Date("2026-08-14T13:08:42.000Z");

function captureLogger(verbosity: 0 | 1 | 2) {
  const lines: Array<{ line: string; status: LogStatus }> = [];
  const logger = createLogger({
    file: "worker.ts",
    verbosity,
    sink: {
      write(line, status) {
        lines.push({ line, status });
      },
    },
  });
  return { lines, logger };
}

describe("resolveLogVerbosity", () => {
  it("accepts numeric and V-prefixed values", () => {
    expect(resolveLogVerbosity("0")).toBe(0);
    expect(resolveLogVerbosity("V0")).toBe(0);
    expect(resolveLogVerbosity("1")).toBe(1);
    expect(resolveLogVerbosity("V1")).toBe(1);
    expect(resolveLogVerbosity("2")).toBe(2);
    expect(resolveLogVerbosity("V2")).toBe(2);
  });

  it("falls back when unset or invalid", () => {
    expect(resolveLogVerbosity(undefined, 1)).toBe(1);
    expect(resolveLogVerbosity("", 0)).toBe(0);
    expect(resolveLogVerbosity("verbose", 0)).toBe(0);
  });
});

describe("verbosityFromEnv", () => {
  it("prefers LOG_VERBOSITY when set", () => {
    expect(verbosityFromEnv({ LOG_VERBOSITY: "V1" })).toBe(1);
  });

  it("defaults development to V2 and other environments to V0", () => {
    expect(verbosityFromEnv({ ENVIRONMENT: "development" })).toBe(2);
    expect(verbosityFromEnv({ ENVIRONMENT: "production" })).toBe(0);
    expect(verbosityFromEnv({ ENVIRONMENT: "staging" })).toBe(0);
  });
});

describe("formatLogLine", () => {
  it("formats time, file, status, and message", () => {
    const line = formatLogLine(
      "adapter.ts",
      "Info",
      "Request received",
      undefined,
      1,
      FIXED_TIME,
    );
    expect(line).toBe("[13:08:42] [adapter.ts] [Info] Request received");
  });

  it("appends flat key=value data at V1", () => {
    const line = formatLogLine(
      "worker.ts",
      "Info",
      "Guard passed",
      { step: "guard", attempt: 1 },
      1,
      FIXED_TIME,
    );
    expect(line).toBe(
      "[13:08:42] [worker.ts] [Info] Guard passed step=guard attempt=1",
    );
  });

  it("appends JSON data at V2", () => {
    const line = formatLogLine(
      "pipeline/index.ts",
      "Debug",
      "Routing resolved",
      { provider: "gemini", chain: ["primary", "fallback"] },
      2,
      FIXED_TIME,
    );
    expect(line).toBe(
      '[13:08:42] [pipeline/index.ts] [Debug] Routing resolved {"provider":"gemini","chain":["primary","fallback"]}',
    );
  });

  it("formats Error values in data", () => {
    const line = formatLogLine(
      "worker.ts",
      "Error",
      "Invoke failed",
      { error: new Error("rate limited") },
      1,
      FIXED_TIME,
    );
    expect(line).toBe(
      "[13:08:42] [worker.ts] [Error] Invoke failed error=Error: rate limited",
    );
  });
});

describe("verbosity gating", () => {
  it("V0 emits errors only", () => {
    const { lines, logger } = captureLogger(0);

    logger.debug("hidden debug");
    logger.info("hidden info");
    logger.error("visible error");

    expect(lines).toHaveLength(1);
    expect(lines[0]?.line).toMatch(/\[Error\] visible error/);
    expect(lines[0]?.status).toBe("Error");
  });

  it("V1 emits errors and info", () => {
    const { lines, logger } = captureLogger(1);

    logger.debug("hidden debug");
    logger.info("visible info", { step: "compose" });
    logger.error("visible error");

    expect(lines).toHaveLength(2);
    expect(lines[0]?.line).toMatch(/\[Info\] visible info step=compose/);
    expect(lines[1]?.line).toMatch(/\[Error\] visible error/);
  });

  it("V2 emits all levels", () => {
    const { lines, logger } = captureLogger(2);

    logger.debug("visible debug", { detail: true });
    logger.info("visible info");
    logger.error("visible error");

    expect(lines).toHaveLength(3);
    expect(lines[0]?.line).toMatch(/\[Debug\] visible debug/);
    expect(lines[1]?.line).toMatch(/\[Info\] visible info/);
    expect(lines[2]?.line).toMatch(/\[Error\] visible error/);
  });
});

describe("child logger", () => {
  it("merges parent and child context into emitted data", () => {
    const lines: string[] = [];
    const parent = createLogger({
      file: "worker.ts",
      verbosity: 2,
      context: { trace_id: "trace-1" },
      sink: { write: (line) => lines.push(line) },
    });

    parent.child({ stage: "invoke" }).info("Provider call started", {
      provider: "gemini",
    });

    expect(lines).toHaveLength(1);
    expect(lines[0]).toContain('"trace_id":"trace-1"');
    expect(lines[0]).toContain('"stage":"invoke"');
    expect(lines[0]).toContain('"provider":"gemini"');
  });
});

describe("createLoggerFactory", () => {
  it("creates per-file loggers with shared verbosity and context", () => {
    const lines: string[] = [];
    const makeLog = createLoggerFactory({
      verbosity: 1,
      context: { trace_id: "abc" },
      sink: { write: (line) => lines.push(line) },
    });

    makeLog("adapter.ts").info("Ingress complete");
    makeLog("journal/index.ts").error("Persistence failed", { request_id: "r1" });

    expect(lines).toHaveLength(2);
    expect(lines[0]).toMatch(/\[adapter\.ts\] \[Info\] Ingress complete/);
    expect(lines[1]).toMatch(
      /\[journal\/index\.ts\] \[Error\] Persistence failed/,
    );
    expect(lines[0]).toContain("trace_id=abc");
    expect(lines[1]).toContain("request_id=r1");
  });
});
