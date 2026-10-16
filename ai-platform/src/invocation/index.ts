import type {
  CanonicalError,
  CanonicalRequest,
  CanonicalResult,
  CanonicalStreamChunk,
} from "../contracts/canonical";
import { getTaxonomyEntry, type TaxonomyCode } from "../errors";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";
import {
  estimateUsageFromStreamedChars,
  ledgerUsageFromProvider,
} from "../pricing";
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
  rawBody?: unknown;
};

export interface InvocationSink {
  recordAttempt(record: AttemptRecord): void;
  emitRegenerating(): void;
  emitStreamText(text: string): void;
  /** Provider finished because of an output-length limit — not a successful completion. */
  emitTruncation(): void;
}

/** Live partial-usage snapshot for ChunkSource.getPartialUsage honesty. */
export type PartialUsageSnapshot = { tokens: number; cost: number };

/**
 * Optional out-handle filled by {@link runInvocation}. Callers pass an empty
 * object; after start, `getPartialUsage` reflects accrued usage for cancel credit.
 */
export type PartialUsageAccessor = {
  getPartialUsage?: () => PartialUsageSnapshot | undefined;
};

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
  /** Caller abort (broker disconnect); chained into each attempt's fetch. */
  signal?: AbortSignal;
  /** Out-param for live partial usage (ChunkSource.getPartialUsage). */
  partialUsage?: PartialUsageAccessor;
  logger?: Logger;
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

function createCancelledError(): CanonicalError {
  const { consumesQuota } = getTaxonomyEntry("cancelled");
  return setRetryabilityFromClassification({
    taxonomyCode: "cancelled",
    retryability: false,
    providerNative: {
      code: "CALLER_ABORTED",
      message: "Invocation aborted by caller signal",
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

function createValidationFailedError(): CanonicalError {
  const { consumesQuota } = getTaxonomyEntry("validation_failed");
  return setRetryabilityFromClassification({
    taxonomyCode: "validation_failed",
    retryability: true,
    providerNative: {
      code: "OUTPUT_TRUNCATED",
      message: "Provider output truncated before a complete result",
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

/**
 * Defensive read of provider-supplied Retry-After (ms). Field may be added on
 * CanonicalError by adapters without this module importing a typed extension.
 */
function retryAfterMsFromError(error: CanonicalError | undefined): number | undefined {
  if (!error) {
    return undefined;
  }
  const value = (error as { retryAfterMs?: unknown }).retryAfterMs;
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    return undefined;
  }
  return value;
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
  const priced = ledgerUsageFromProvider(result);
  return {
    latency_ms: result.timing?.total_ms,
    tokens_in: result.usage.input,
    tokens_out: result.usage.output,
    cost: priced.cost,
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
    ...(invokeResult.rawBody !== undefined
      ? { rawBody: invokeResult.rawBody }
      : {}),
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
  callerSignal?: AbortSignal,
  onStreamChunk?: (chunk: CanonicalStreamChunk) => void,
): Promise<ProviderInvokeResult> {
  if (callerSignal?.aborted) {
    return { kind: "error", error: createCancelledError() };
  }

  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let callerAbortHandler: (() => void) | undefined;

  const timeoutPromise = new Promise<ProviderInvokeResult>((resolve) => {
    timer = setTimeout(() => {
      controller.abort();
      resolve({ kind: "error", error: createTimeoutError() });
    }, timeoutMs);
  });

  const callerAbortPromise =
    callerSignal !== undefined
      ? new Promise<ProviderInvokeResult>((resolve) => {
          callerAbortHandler = () => {
            controller.abort();
            resolve({ kind: "error", error: createCancelledError() });
          };
          callerSignal.addEventListener("abort", callerAbortHandler, {
            once: true,
          });
        })
      : undefined;

  try {
    const raced: Promise<ProviderInvokeResult>[] = [
      port.invoke(request, {
        signal: controller.signal,
        onStreamChunk,
      }).catch((cause: unknown) => {
        if (callerSignal?.aborted) {
          return { kind: "error" as const, error: createCancelledError() };
        }
        const message =
          cause instanceof Error ? cause.message : "Provider invoke rejected";
        return {
          kind: "error" as const,
          error: createInternalError(message),
        };
      }),
      timeoutPromise,
    ];
    if (callerAbortPromise) {
      raced.push(callerAbortPromise);
    }
    return await Promise.race(raced);
  } finally {
    if (timer !== undefined) {
      clearTimeout(timer);
    }
    if (callerSignal && callerAbortHandler) {
      callerSignal.removeEventListener("abort", callerAbortHandler);
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
    signal: callerSignal,
    partialUsage,
  } = input;
  const logger = input.logger ?? noopLogger;

  const chain = routingDecision.chain;
  if (chain.length === 0) {
    logger.error("Invocation failed — empty provider chain", {
      request_id: requestId,
    });
    return { ok: false, error: createProviderUnavailableError() };
  }

  logger.info("Invocation started", {
    request_id: requestId,
    chain_length: chain.length,
    policy_id: routingDecision.policy_id,
  });

  const startedAtMs = Date.now();
  let attemptNo = 0;
  /** True when the prior target's exhausting (final) failure was timeout-classified. */
  let prevExhaustedViaTimeout = false;
  let prevTargetHadPartialStream = false;

  // Accrued usage for ChunkSource.getPartialUsage during/after cancel.
  let accruedTokens = 0;
  let accruedCost = 0;
  let hasAccruedUsage = false;
  let streamedChars = 0;
  let pricingModelId = chain[0]?.model_id ?? "";
  /** True when the last invoked target exhausted on a truncation outcome. */
  let exhaustedViaTruncation = false;

  const readPartialUsage = (): PartialUsageSnapshot | undefined => {
    if (hasAccruedUsage) {
      return { tokens: accruedTokens, cost: accruedCost };
    }
    if (streamedChars > 0) {
      return estimateUsageFromStreamedChars(streamedChars, pricingModelId);
    }
    return undefined;
  };

  if (partialUsage) {
    partialUsage.getPartialUsage = readPartialUsage;
  }

  const noteUsageFromResult = (result: CanonicalResult): void => {
    const priced = ledgerUsageFromProvider(result);
    hasAccruedUsage = true;
    accruedTokens += priced.tokens;
    accruedCost += priced.cost;
  };

  // Run-scoped observing sink — never mutate the caller-owned sink object.
  let currentTargetHadPartialStream = false;
  /** True after this target streamed text and a same-target retry still needs regenerating. */
  let pendingSameTargetRegenerating = false;
  const observingSink: InvocationSink = {
    recordAttempt(record) {
      sink.recordAttempt(record);
    },
    emitRegenerating() {
      sink.emitRegenerating();
    },
    emitStreamText(text) {
      currentTargetHadPartialStream = true;
      streamedChars += text.length;
      sink.emitStreamText(text);
    },
    emitTruncation() {
      sink.emitTruncation();
    },
  };

  // Sequential walk only — `max_parallel_attempts` was deleted from the
  // routing decision. Parallel racing would multiply token spend, the
  // dominant cost by one to two orders of magnitude (§13.6).
  for (let chainIndex = 0; chainIndex < chain.length; chainIndex++) {
    if (callerSignal?.aborted) {
      logger.info("Invocation cancelled by caller signal", {
        request_id: requestId,
      });
      return { ok: false, error: createCancelledError() };
    }

    const remainingAtTarget = remainingDeadlineMs(
      request.deadline,
      startedAtMs,
      Date.now(),
    );
    if (remainingAtTarget !== null && remainingAtTarget <= 0) {
      // Deadline exhausted — skip remaining targets.
      logger.info("Invocation deadline exhausted — skipping remaining providers", {
        request_id: requestId,
      });
      break;
    }

    if (chainIndex > 0 && prevTargetHadPartialStream) {
      observingSink.emitRegenerating();
      pendingSameTargetRegenerating = false;
    }

    const entry = chain[chainIndex];
    pricingModelId = entry.model_id;
    const selectionReason: SelectionReason =
      chainIndex === 0
        ? "primary"
        : prevExhaustedViaTimeout
          ? "fallback_after_timeout"
          : "fallback_after_retryable_error";

    if (chainIndex > 0) {
      logger.info("Falling back to next provider in chain", {
        request_id: requestId,
        chain_index: chainIndex,
        provider_id: entry.provider_id,
        model_id: entry.model_id,
        reason: selectionReason,
      });
    }

    currentTargetHadPartialStream = false;
    pendingSameTargetRegenerating = false;
    let lastFailureWasTimeout = false;
    let lastFailureWasTruncation = false;
    let targetInvoked = false;

    for (
      let attemptOnTarget = 0;
      attemptOnTarget < entry.max_attempts;
      attemptOnTarget++
    ) {
      if (callerSignal?.aborted) {
        return { ok: false, error: createCancelledError() };
      }

      const remaining = remainingDeadlineMs(
        request.deadline,
        startedAtMs,
        Date.now(),
      );
      if (remaining !== null && remaining <= 0) {
        break;
      }

      const attemptTimeoutMs =
        remaining === null
          ? entry.timeout_ms
          : Math.min(entry.timeout_ms, remaining);

      // Propagate remaining-ms (not the stale original) into the attempt request.
      const requestForAttempt: CanonicalRequest =
        remaining === null
          ? request
          : { ...request, deadline: remaining };

      // Emit regenerating before the first emission of a same-target retry after
      // a prior partial stream on this target (§3.2.1).
      if (attemptOnTarget > 0 && pendingSameTargetRegenerating) {
        observingSink.emitRegenerating();
        pendingSameTargetRegenerating = false;
      }

      attemptNo++;
      targetInvoked = true;
      let liveRelayed = false;
      const port = portResolver(entry.provider_id);
      logger.debug("Provider attempt started", {
        request_id: requestId,
        attempt_no: attemptNo,
        provider_id: entry.provider_id,
        model_id: entry.model_id,
        selection_reason: selectionReason,
      });
      const invokeResult = await invokeWithTimeout(
        port,
        requestForAttempt,
        attemptTimeoutMs,
        callerSignal,
        (chunk) => {
          if (chunk.kind !== "text_delta") {
            return;
          }
          const text = textFromChunkPayload(chunk.payload);
          if (text !== undefined && text.length > 0) {
            liveRelayed = true;
            observingSink.emitStreamText(text);
          }
        },
      );

      if (!liveRelayed) {
        relayTextDeltas(chunksFromResult(invokeResult), observingSink);
      }

      if (invokeResult.kind === "truncation") {
        observingSink.emitTruncation();
      }

      const processed = processInvokeResult(
        invokeResult,
        entry,
        attemptNo,
        selectionReason,
        requestId,
        idempotencyKey,
      );

      if (processed.success) {
        noteUsageFromResult(processed.success);
      } else if (invokeResult.kind === "truncation") {
        noteUsageFromResult(invokeResult.result);
      }

      observingSink.recordAttempt(processed.record);

      if (processed.success) {
        logger.info("Provider attempt succeeded", {
          request_id: requestId,
          attempt_no: attemptNo,
          provider_id: entry.provider_id,
          model_id: entry.model_id,
          outcome: processed.record.outcome,
        });
        return { ok: true, result: processed.success };
      }

      if (processed.terminalError) {
        logger.info("Invocation ended with terminal provider error", {
          request_id: requestId,
          attempt_no: attemptNo,
          provider_id: entry.provider_id,
          error_code: processed.record.error_code,
        });
        return { ok: false, error: processed.terminalError };
      }

      logger.debug("Provider attempt finished without success", {
        request_id: requestId,
        attempt_no: attemptNo,
        provider_id: entry.provider_id,
        outcome: processed.record.outcome,
        error_code: processed.record.error_code,
      });

      lastFailureWasTimeout = processed.record.outcome === "timeout";
      lastFailureWasTruncation = processed.record.outcome === "truncation";

      if (attemptOnTarget < entry.max_attempts - 1) {
        if (currentTargetHadPartialStream) {
          pendingSameTargetRegenerating = true;
        }

        const jittered = computeJitteredBackoff(attemptOnTarget, random);
        const retryAfterMs =
          invokeResult.kind === "error" || invokeResult.kind === "malformed"
            ? retryAfterMsFromError(invokeResult.error)
            : undefined;
        const delay =
          retryAfterMs !== undefined
            ? Math.max(jittered, retryAfterMs)
            : jittered;

        logger.info("Retrying provider after failure", {
          request_id: requestId,
          attempt_no: attemptNo,
          provider_id: entry.provider_id,
          delay_ms: delay,
        });

        await sleepWithinDeadline(
          sleeper,
          delay,
          request.deadline,
          startedAtMs,
        );

        if (callerSignal?.aborted) {
          return { ok: false, error: createCancelledError() };
        }
      }
    }

    if (!targetInvoked) {
      // Budget exhausted before any attempt on this (and later) targets.
      break;
    }

    prevExhaustedViaTimeout = lastFailureWasTimeout;
    prevTargetHadPartialStream = currentTargetHadPartialStream;
    exhaustedViaTruncation = lastFailureWasTruncation;
  }

  if (callerSignal?.aborted) {
    logger.info("Invocation cancelled by caller signal", {
      request_id: requestId,
    });
    return { ok: false, error: createCancelledError() };
  }

  if (exhaustedViaTruncation) {
    logger.info("Invocation failed — truncated output is not authoritative", {
      request_id: requestId,
      attempts: attemptNo,
    });
    return { ok: false, error: createValidationFailedError() };
  }

  logger.error("Invocation failed — all providers exhausted", {
    request_id: requestId,
    attempts: attemptNo,
  });
  return { ok: false, error: createProviderUnavailableError() };
}
