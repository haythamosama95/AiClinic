import type {
  CanonicalError,
  CanonicalRequest,
  CanonicalResult,
} from "../contracts/canonical";
import { getTaxonomyEntry, type TaxonomyCode } from "../errors";
import { classifyFailure, setRetryabilityFromClassification } from "../provider/classify";
import type { ProviderInvokeResult, ProviderPort } from "../provider/port";
import type { RoutingDecision } from "../router";

export type SelectionReason =
  | "primary"
  | "fallback_after_retryable_error"
  | "fallback_after_timeout";

export type AttemptOutcome =
  | "success"
  | "retryable_failure"
  | "terminal_failure"
  | "timeout";

export type AttemptRecord = {
  attempt_no: number;
  provider_id: string;
  model_id: string;
  selection_reason: SelectionReason;
  outcome: AttemptOutcome;
  error_code?: TaxonomyCode;
  request_id: string;
};

export interface InvocationSink {
  recordAttempt(record: AttemptRecord): void;
  emitRegenerating(): void;
  emitStreamText(text: string): void;
}

export interface ProviderHistoryStore {
  getProviderHealth(providerId: string): unknown;
  getRecentFailures(providerId: string): unknown;
  isCircuitOpen(providerId: string): boolean;
}

export type InvocationInput = {
  request: CanonicalRequest;
  routingDecision: RoutingDecision;
  requestId: string;
  idempotencyKey: string;
  portResolver: (providerId: string) => ProviderPort;
  sink: InvocationSink;
  sleeper: (ms: number) => Promise<void>;
  providerHistoryStore?: ProviderHistoryStore;
};

export type InvocationResult =
  | { ok: true; result: CanonicalResult }
  | { ok: false; error: CanonicalError };

function createProviderUnavailableError(): CanonicalError {
  const { consumesQuota } = getTaxonomyEntry("provider_unavailable");
  return setRetryabilityFromClassification({
    taxonomyCode: "provider_unavailable",
    retryability: false,
    providerNative: {
      code: "PROVIDER_UNAVAILABLE",
      message: "All candidate providers exhausted",
    },
    consumedBudget: consumesQuota !== "No",
  });
}

function computeJitteredBackoff(retryIndex: number): number {
  const baseMs = 100;
  const exponential = baseMs * 2 ** retryIndex;
  const jitter = Math.random() * exponential * 0.5;
  return Math.floor(exponential + jitter);
}

type ProcessedInvoke = {
  record: AttemptRecord;
  success?: CanonicalResult;
  terminalError?: CanonicalError;
};

function processInvokeResult(
  invokeResult: ProviderInvokeResult,
  entry: { provider_id: string; model_id: string },
  attemptNo: number,
  selectionReason: SelectionReason,
  requestId: string,
): ProcessedInvoke {
  const base: Omit<AttemptRecord, "outcome" | "error_code"> = {
    attempt_no: attemptNo,
    provider_id: entry.provider_id,
    model_id: entry.model_id,
    selection_reason: selectionReason,
    request_id: requestId,
  };

  if (invokeResult.kind === "success" || invokeResult.kind === "truncation") {
    return {
      record: { ...base, outcome: "success" },
      success: invokeResult.result,
    };
  }

  const error =
    invokeResult.kind === "error" || invokeResult.kind === "malformed"
      ? invokeResult.error
      : undefined;
  if (!error) {
    throw new Error(`Unexpected invoke result kind: ${invokeResult.kind}`);
  }

  const code = error.taxonomyCode;
  if (classifyFailure(code) === "terminal") {
    return {
      record: {
        ...base,
        outcome: "terminal_failure",
        error_code: code,
      },
      terminalError: error,
    };
  }

  const outcome: AttemptOutcome =
    code === "timeout" ? "timeout" : "retryable_failure";
  return {
    record: { ...base, outcome, error_code: code },
  };
}

export async function runInvocation(
  input: InvocationInput,
): Promise<InvocationResult> {
  const {
    request,
    routingDecision,
    requestId,
    portResolver,
    sink,
    sleeper,
  } = input;

  const chain = routingDecision.chain;
  if (chain.length === 0) {
    return { ok: false, error: createProviderUnavailableError() };
  }

  let attemptNo = 0;
  let prevExhaustedViaTimeoutsOnly = false;
  let prevTargetHadPartialStream = false;

  let currentTargetHadPartialStream = false;
  const originalEmitStreamText = sink.emitStreamText.bind(sink);
  sink.emitStreamText = (text: string) => {
    currentTargetHadPartialStream = true;
    originalEmitStreamText(text);
  };

  for (let chainIndex = 0; chainIndex < chain.length; chainIndex++) {
    if (chainIndex > 0 && prevTargetHadPartialStream) {
      sink.emitRegenerating();
    }

    const entry = chain[chainIndex];
    const selectionReason: SelectionReason =
      chainIndex === 0
        ? "primary"
        : prevExhaustedViaTimeoutsOnly
          ? "fallback_after_timeout"
          : "fallback_after_retryable_error";

    currentTargetHadPartialStream = false;
    let targetFailuresAllTimeout = true;
    let hadAnyFailure = false;

    for (
      let attemptOnTarget = 0;
      attemptOnTarget < entry.max_attempts;
      attemptOnTarget++
    ) {
      attemptNo++;
      const port = portResolver(entry.provider_id);
      const invokeResult = port.invoke(request);
      const processed = processInvokeResult(
        invokeResult,
        entry,
        attemptNo,
        selectionReason,
        requestId,
      );

      sink.recordAttempt(processed.record);

      if (processed.success) {
        return { ok: true, result: processed.success };
      }

      if (processed.terminalError) {
        return { ok: false, error: processed.terminalError };
      }

      hadAnyFailure = true;
      if (processed.record.outcome !== "timeout") {
        targetFailuresAllTimeout = false;
      }

      if (attemptOnTarget < entry.max_attempts - 1) {
        await sleeper(computeJitteredBackoff(attemptOnTarget));
      }
    }

    prevExhaustedViaTimeoutsOnly = hadAnyFailure && targetFailuresAllTimeout;
    prevTargetHadPartialStream = currentTargetHadPartialStream;
  }

  return { ok: false, error: createProviderUnavailableError() };
}
