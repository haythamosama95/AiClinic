import {
  assertExactlyOneTerminal,
  type CanonicalError,
  type CanonicalRequest,
  type CanonicalResult,
  type CanonicalStreamChunk,
} from "../contracts/canonical";
import { getTaxonomyEntry, isTaxonomyCode, type TaxonomyCode } from "../errors";
import { setRetryabilityFromClassification } from "./classify";
import {
  type ProviderInvokeOptions,
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
    taxonomyCode: code,
    retryability: false,
    providerNative: {
      code: "FAKE_ERROR",
      message: `Simulated ${code} from fake adapter`,
    },
    consumedBudget: consumesBudget(code),
  });
}

function createSuccessResult(): CanonicalResult {
  return {
    finalContent: { type: "text", text: "Fake adapter summary." },
    usage: { input: 10, output: 20, cached: 0 },
    providerModel: { provider: "fake", model: "fake-v1" },
    finishReason: "stop",
    providerRequestId: "fake-req-001",
    timing: { queue_ms: 1, provider_ms: 5, total_ms: 6 },
  };
}

function createTruncationResult(): CanonicalResult {
  return {
    ...createSuccessResult(),
    finalContent: { type: "text", text: "Partial output…" },
    finishReason: "length",
  };
}

function textFromResult(result: CanonicalResult): string {
  const content = result.finalContent;
  if (content && typeof content === "object" && "text" in content) {
    return String((content as { text: unknown }).text ?? "");
  }
  return typeof content === "string" ? content : "";
}

function minimalTerminalChunks(text: string): readonly CanonicalStreamChunk[] {
  const chunks: CanonicalStreamChunk[] = [
    {
      sequenceNumber: 0,
      kind: "text_delta",
      payload: { text },
      terminal: true,
    },
  ];
  assertExactlyOneTerminal(chunks);
  return chunks;
}

function parsePrefixedCode(
  outcome: string,
  prefix: "retryable:" | "terminal:",
): TaxonomyCode | undefined {
  const code = outcome.slice(prefix.length);
  return isTaxonomyCode(code) ? code : undefined;
}

export class FakeAdapter implements ProviderPort {
  private readonly queue: ScriptedOutcome[];

  constructor(scriptedOutcomes: ScriptedOutcome[]) {
    this.queue = [...scriptedOutcomes];
  }

  async invoke(
    _request: CanonicalRequest,
    _options?: ProviderInvokeOptions,
  ): Promise<ProviderInvokeResult> {
    const outcome = this.queue.shift();
    if (outcome === undefined) {
      return {
        kind: "error",
        error: createCanonicalError("internal_error"),
      };
    }

    if (outcome === "success") {
      const result = createSuccessResult();
      return {
        kind: "success",
        result,
        chunks: minimalTerminalChunks(textFromResult(result)),
      };
    }

    if (outcome === "truncation") {
      const result = createTruncationResult();
      return {
        kind: "truncation",
        result,
        chunks: minimalTerminalChunks(textFromResult(result)),
      };
    }

    if (outcome === "malformed") {
      return {
        kind: "malformed",
        error: createCanonicalError("internal_error"),
      };
    }

    if (outcome.startsWith("retryable:")) {
      const code = parsePrefixedCode(outcome, "retryable:");
      return {
        kind: "error",
        error: createCanonicalError(code ?? "internal_error"),
      };
    }

    if (outcome.startsWith("terminal:")) {
      const code = parsePrefixedCode(outcome, "terminal:");
      return {
        kind: "error",
        error: createCanonicalError(code ?? "internal_error"),
      };
    }

    return {
      kind: "error",
      error: createCanonicalError("internal_error"),
    };
  }
}
