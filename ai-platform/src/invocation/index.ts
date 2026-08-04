import type {
  CanonicalError,
  CanonicalRequest,
  CanonicalResult,
  CanonicalStreamChunk,
} from "../contracts/canonical";
import { getTaxonomyEntry, type TaxonomyCode } from "../errors";
import { classifyFailure, setRetryabilityFromClassification } from "../provider/classify";
import type { ProviderInvokeResult, ProviderPort } from "../provider/port";
import type { RoutingDecision } from "../router";

/** Documented ceiling for inter-retry backoff (inclusive of jitter). */
export const BACKOFF_CAP_MS = 10_000;

export type SelectionReason =
  | "primary"
  | "fallback_after_retryable_error"
  | "fallback_after_timeout";

export type AttemptOutcome =
  | "success"
  | "truncation"
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
  idempotency_key: string;
  latency_ms?: number;
  tokens_in?: number;
  tokens_out?: number;
  cost?: number;
  provider_request_id?: string;
};

export interface InvocationSink {
  recordAttempt(record: AttemptRecord): void;
  emitRegenerating(): void;
  emitStreamText(text: string): void;
}

export type InvocationInput = {
  request: CanonicalRequest;
  routingDecision: RoutingDecision;
  requestId: string;
  idempotencyKey: string;
  portResolver: (providerId: string) => ProviderPort;
  sink: InvocationSink;
  sleeper: (ms: number) => Promise<void>;
  /** Injectable RNG for jitter proofs; defaults to `Math.random`. */
  random?: () => number;
};

export type InvocationResult =
  | { ok: true; result: CanonicalResult }
  | { ok: false; error: CanonicalError };

function createProviderUnavailableError(): CanonicalError {
  const { consumesQuota } = getTaxonomyEntry("provider_unavailable");
  return setRetryabilityFromClassification({
    taxonomyCode: "provider_unavailable",
    retryability: true,
    providerNative: {
      code: "PROVIDER_UNAVAILABLE",
      message: "All candidate providers exhausted",
    },
    consumedBudget: consumesQuota !== "No",
  });
}

function createTimeoutError(): CanonicalError {
  const { consumesQuota } = getTaxonomyEntry("timeout");
  return setRetryabilityFromClassification({
    taxonomyCode: "timeout",
    retryability: true,
    providerNative: {
      code: "ATTEMPT_TIMEOUT",
      message: "Provider invoke exceeded chain-entry timeout_ms",
    },
    consumedBudget: consumesQuota !== "No",
  });
}

function createInternalError(message: string): CanonicalError {
  const { consumesQuota } = getTaxonomyEntry("internal_error");
  return setRetryabilityFromClassification({
    taxonomyCode: "internal_error",
    retryability: true,
    providerNative: {
      code: "UNEXPECTED_INVOKE_RESULT",
      message,
    },
    consumedBudget: consumesQuota !== "No",
  });
}

/**
 * Exponential backoff with full-jitter, capped at {@link BACKOFF_CAP_MS}.
 * `retryIndex` is 0-based within the current target (first inter-retry sleep = 0).
 */
export function computeJitteredBackoff(
  retryIndex: number,
  random: () => number = Math.random,
): number {
  const baseMs = 100;
  const exponential = Math.min(baseMs * 2 ** retryIndex, BACKOFF_CAP_MS);
  const jitter = random() * exponential * 0.5;
  return Math.floor(Math.min(exponential + jitter, BACKOFF_CAP_MS));
}

/** Pure exponential component without jitter — used by tests to prove jitter is present. */
export function pureExponentialBackoffMs(retryIndex: number): number {
  const baseMs = 100;
  return Math.min(baseMs * 2 ** retryIndex, BACKOFF_CAP_MS);
}

type ProcessedInvoke = {
  record: AttemptRecord;
  success?: CanonicalResult;
  terminalError?: CanonicalError;
};

function usageFieldsFromResult(
  result: CanonicalResult,
): Pick<
  AttemptRecord,
  "latency_ms" | "tokens_in" | "tokens_out" | "cost" | "provider_request_id"
> {
  return {
    latency_ms: result.timing?.total_ms,
    tokens_in: result.usage.input,
    tokens_out: result.usage.output,
    // Cost attribution lands when a pricing table is wired; carry a stable zero for now.
    cost: 0,
    provider_request_id: result.providerRequestId,
  };
}

function textFromChunkPayload(payload: unknown): string | undefined {
  if (
    typeof payload === "object" &&
    payload !== null &&
    "text" in payload &&
    typeof (payload as { text: unknown }).text === "string"
  ) {
    return (payload as { text: string }).text;
  }
  if (typeof payload === "string") {
    return payload;
  }
  return undefined;
}

function chunksFromResult(
  invokeResult: ProviderInvokeResult,
): readonly CanonicalStreamChunk[] | undefined {
  if (invokeResult.kind === "success" || invokeResult.kind === "truncation") {
    return invokeResult.chunks;
  }
  if (
    (invokeResult.kind === "error" || invokeResult.kind === "malformed") &&
    "chunks" in invokeResult &&
    Array.isArray((invokeResult as { chunks?: unknown }).chunks)
  ) {
    return (invokeResult as { chunks: readonly CanonicalStreamChunk[] }).chunks;
  }
  return undefined;
}

function relayTextDeltas(
  chunks: readonly CanonicalStreamChunk[] | undefined,
  sink: InvocationSink,
): void {
  if (!chunks) {
    return;
  }
  for (const chunk of chunks) {
    if (chunk.kind !== "text_delta") {
      continue;
    }
    const text = textFromChunkPayload(chunk.payload);
    if (text !== undefined && text.length > 0) {
      sink.emitStreamText(text);
    }
  }
}

function processInvokeResult(
  invokeResult: ProviderInvokeResult,
  entry: { provider_id: string; model_id: string },
  attemptNo: number,
  selectionReason: SelectionReason,
  requestId: string,
  idempotencyKey: string,
): ProcessedInvoke {
  const base: Omit<AttemptRecord, "outcome" | "error_code"> = {
    attempt_no: attemptNo,
    provider_id: entry.provider_id,
    model_id: entry.model_id,
    selection_reason: selectionReason,
    request_id: requestId,
    idempotency_key: idempotencyKey,
  };

  if (invokeResult.kind === "success") {
    return {
      record: {
        ...base,
        outcome: "success",
        ...usageFieldsFromResult(invokeResult.result),
      },
      success: invokeResult.result,
    };
  }

  if (invokeResult.kind === "truncation") {
    return {
      record: {
        ...base,
        outcome: "truncation",
        ...usageFieldsFromResult(invokeResult.result),
      },
      success: invokeResult.result,
    };
  }

  const error =
    invokeResult.kind === "error" || invokeResult.kind === "malformed"
      ? invokeResult.error
      : undefined;
  if (!error) {
    const internal = createInternalError(
      `Unexpected invoke result kind: ${(invokeResult as { kind: string }).kind}`,
    );
    return {
      record: {
        ...base,
        outcome: "retryable_failure",
        error_code: internal.taxonomyCode,
      },
    };
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

async function invokeWithTimeout(
  port: ProviderPort,
  request: CanonicalRequest,
  timeoutMs: number,
): Promise<ProviderInvokeResult> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeoutPromise = new Promise<ProviderInvokeResult>((resolve) => {
    timer = setTimeout(() => {
      controller.abort();
      resolve({ kind: "error", error: createTimeoutError() });
    }, timeoutMs);
  });

  try {
    return await Promise.race([
      port.invoke(request, { signal: controller.signal }).catch((cause: unknown) => {
        const message =
          cause instanceof Error ? cause.message : "Provider invoke rejected";
        return {
          kind: "error" as const,
          error: createInternalError(message),
        };
      }),
      timeoutPromise,
    ]);
  } finally {
    if (timer !== undefined) {
      clearTimeout(timer);
    }
  }
}

function remainingDeadlineMs(
  deadlineBudgetMs: number | null,
  startedAtMs: number,
  nowMs: number,
): number | null {
  if (deadlineBudgetMs === null) {
    return null;
  }
  return deadlineBudgetMs - (nowMs - startedAtMs);
}

async function sleepWithinDeadline(
  sleeper: (ms: number) => Promise<void>,
  delayMs: number,
  deadlineBudgetMs: number | null,
  startedAtMs: number,
  nowMs: () => number = Date.now,
): Promise<void> {
  const remaining = remainingDeadlineMs(deadlineBudgetMs, startedAtMs, nowMs());
  if (remaining === null) {
    await sleeper(delayMs);
    return;
  }
  if (remaining <= 0) {
    return;
  }
  await sleeper(Math.min(delayMs, remaining));
}

export async function runInvocation(
  input: InvocationInput,
): Promise<InvocationResult> {
  const {
    request,
    routingDecision,
    requestId,
    idempotencyKey,
    portResolver,
    sink,
    sleeper,
    random = Math.random,
  } = input;

  const chain = routingDecision.chain;
  if (chain.length === 0) {
    return { ok: false, error: createProviderUnavailableError() };
  }

  const startedAtMs = Date.now();
  let attemptNo = 0;
  /** True when the prior target's exhausting (final) failure was timeout-classified. */
  let prevExhaustedViaTimeout = false;
  let prevTargetHadPartialStream = false;

  // Run-scoped observing sink — never mutate the caller-owned sink object.
  let currentTargetHadPartialStream = false;
  const observingSink: InvocationSink = {
    recordAttempt(record) {
      sink.recordAttempt(record);
    },
    emitRegenerating() {
      sink.emitRegenerating();
    },
    emitStreamText(text) {
      currentTargetHadPartialStream = true;
      sink.emitStreamText(text);
    },
  };

  for (let chainIndex = 0; chainIndex < chain.length; chainIndex++) {
    if (chainIndex > 0 && prevTargetHadPartialStream) {
      observingSink.emitRegenerating();
    }

    const entry = chain[chainIndex];
    const selectionReason: SelectionReason =
      chainIndex === 0
        ? "primary"
        : prevExhaustedViaTimeout
          ? "fallback_after_timeout"
          : "fallback_after_retryable_error";

    currentTargetHadPartialStream = false;
    let lastFailureWasTimeout = false;

    for (
      let attemptOnTarget = 0;
      attemptOnTarget < entry.max_attempts;
      attemptOnTarget++
    ) {
      attemptNo++;
      const port = portResolver(entry.provider_id);
      const invokeResult = await invokeWithTimeout(
        port,
        request,
        entry.timeout_ms,
      );

      relayTextDeltas(chunksFromResult(invokeResult), observingSink);

      const processed = processInvokeResult(
        invokeResult,
        entry,
        attemptNo,
        selectionReason,
        requestId,
        idempotencyKey,
      );

      observingSink.recordAttempt(processed.record);

      if (processed.success) {
        return { ok: true, result: processed.success };
      }

      if (processed.terminalError) {
        return { ok: false, error: processed.terminalError };
      }

      lastFailureWasTimeout = processed.record.outcome === "timeout";

      if (attemptOnTarget < entry.max_attempts - 1) {
        const delay = computeJitteredBackoff(attemptOnTarget, random);
        await sleepWithinDeadline(
          sleeper,
          delay,
          request.deadline,
          startedAtMs,
        );
      }
    }

    prevExhaustedViaTimeout = lastFailureWasTimeout;
    prevTargetHadPartialStream = currentTargetHadPartialStream;
  }

  return { ok: false, error: createProviderUnavailableError() };
}
