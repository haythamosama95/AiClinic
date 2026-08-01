import type {
  CanonicalError,
  CanonicalRequest,
  CanonicalResult,
} from "../contracts/canonical";
import { getTaxonomyEntry, type TaxonomyCode } from "../errors";
import { setRetryabilityFromClassification } from "./classify";
import {
  type ProviderInvokeResult,
  type ProviderPort,
  type ScriptedOutcome,
} from "./port";

function consumesBudget(code: TaxonomyCode): boolean {
  const { consumesQuota } = getTaxonomyEntry(code);
  return consumesQuota !== "No";
}

function createCanonicalError(code: TaxonomyCode): CanonicalError {
  return setRetryabilityFromClassification({
    "taxonomy code": code,
    retryability: false,
    "provider-native code and message": {
      code: "FAKE_ERROR",
      message: `Simulated ${code} from fake adapter`,
    },
    "whether the attempt consumed budget": consumesBudget(code),
  });
}

function createSuccessResult(): CanonicalResult {
  return {
    "final content": { type: "text", text: "Fake adapter summary." },
    "usage counters": { input: 10, output: 20, cached: 0 },
    "provider+model actually used": { provider: "fake", model: "fake-v1" },
    "finish reason": "stop",
    "provider request id": "fake-req-001",
    "timing breakdown": { queue_ms: 1, provider_ms: 5, total_ms: 6 },
  };
}

function createTruncationResult(): CanonicalResult {
  return {
    ...createSuccessResult(),
    "final content": { type: "text", text: "Partial output…" },
    "finish reason": "length",
  };
}

function parsePrefixedCode(
  outcome: ScriptedOutcome,
  prefix: "retryable:" | "terminal:",
): TaxonomyCode {
  return outcome.slice(prefix.length) as TaxonomyCode;
}

export class FakeAdapter implements ProviderPort {
  private readonly queue: ScriptedOutcome[];

  constructor(scriptedOutcomes: ScriptedOutcome[]) {
    this.queue = [...scriptedOutcomes];
  }

  invoke(_request: CanonicalRequest): ProviderInvokeResult {
    const outcome = this.queue.shift();
    if (outcome === undefined) {
      throw new Error("FakeAdapter invoke called with empty outcome queue");
    }

    if (outcome === "success") {
      return { kind: "success", result: createSuccessResult() };
    }

    if (outcome === "truncation") {
      return { kind: "truncation", result: createTruncationResult() };
    }

    if (outcome === "malformed") {
      return {
        kind: "malformed",
        error: createCanonicalError("internal_error"),
      };
    }

    if (outcome.startsWith("retryable:")) {
      const code = parsePrefixedCode(outcome, "retryable:");
      return { kind: "error", error: createCanonicalError(code) };
    }

    if (outcome.startsWith("terminal:")) {
      const code = parsePrefixedCode(outcome, "terminal:");
      return { kind: "error", error: createCanonicalError(code) };
    }

    throw new Error(`Unrecognized scripted outcome: ${outcome}`);
  }
}
