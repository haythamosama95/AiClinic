/**
 * Thin §6.1 pipeline composition — guard (stages 1–10) plus happy-path settle
 * (FakeAdapter stage 11 + stages 15–16). Production modules only; no Worker wiring.
 */

import { runAdmission, type AdmissionBindings } from "../admission";
import { INGRESS_BODY_SIZE_LIMIT, parseAdapterRequestBody } from "../adapter";
import { resolve } from "../capability";
import type { ConfigCache, D1Reader } from "../config-cache";
import type { CanonicalRequest, CanonicalResult } from "../contracts/canonical";
import {
  runCostPreflight,
  serializePreflightInput,
} from "../context/preflight";
import {
  validateContext,
  type ContextRequiredFailure,
  type Transcript,
} from "../context/validator";
import { creditUsage, type CreditBindings } from "../credit";
import { evaluateEntitlement, type EntitlementContext } from "../entitlement";
import type { EntitlementSnapshot } from "../quota-do/index";
import type { Principal, TokenVerifier, VerifyContext } from "../identity";
import {
  createRequestRow,
  recordTerminalState,
  writePostResponseDetail,
  type AttemptInput,
  type PostResponseInput,
} from "../journal";
import type { Manifest } from "../manifest";
import { ledgerUsageFromProvider } from "../pricing";
import { FakeAdapter } from "../provider/fake";
import {
  checkRateLimit,
  type RateLimitBindings,
} from "../rate-limit";
import { routingTierFromAdmission } from "../soft-threshold";
import type { Logger } from "../logger";
import { noopLogger } from "../logger";
import type {
  IdempotencyPriorState,
  ReleaseRequest,
} from "../quota-do/index";

export type GuardStage = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10;

/** Injected so callers can supply production `composeRequest` without eager prompt-registry load. */
export type ComposeRequestFn = (input: {
  manifest: Manifest;
  filteredContext: Record<string, unknown>;
  userIntent: string;
  principal: Principal;
  requestReference: string;
  streamFlag?: boolean;
  deadline?: number | null;
  transcript?: Transcript;
}) =>
  | {
    ok: true;
    request: CanonicalRequest;
    promptVersion: string;
    systemPromptLeakNeedle: string;
    systemPromptLeakNeedles?: readonly string[];
  }
  | { ok: false; code: "internal_error" };

export type GuardInput = {
  /** Raw ingress body text (stage 1 size + JSON shape). */
  bodyText: string;
  /** Signed AAT — stage 2 when `principal` is omitted. */
  token?: string;
  /** Pre-verified principal — skips stage 2 crypto when provided with no token. */
  principal?: Principal;
  verifier?: TokenVerifier;
  verifyContext?: Omit<VerifyContext, "cache" | "reader"> &
  Partial<Pick<VerifyContext, "cache" | "reader">>;
  capabilityId: string;
  capabilityVersion: string;
  entitlement: EntitlementContext;
  suppliedContext: Record<string, unknown>;
  userIntent: string;
  idempotencyKey: string;
  requestReference: string;
  traceId: string;
  cache: ConfigCache;
  reader: D1Reader;
  /** Admission clock (seconds, matching Principal.exp). */
  now?: number;
  /** Optional prompt-artifact UTF-8 byte length for stage 7. */
  promptArtifactByteLength?: number;
  /**
   * Composer-known UTF-8 byte length of the prompt scaffold (system instruction
   * + rule fragments + template). Used at stage 7 when the numeric override is
   * omitted. Production worker injects `promptScaffoldByteLength` from composer.
   */
  promptScaffoldByteLength?: (manifest: Manifest) => number;
  /**
   * Composer's `promptVersion` (content hash of resolved artifact bytes).
   * Journaled into `ai_request.prompt_artifact_hash` at stage 9.
   */
  resolvePromptVersion?: (manifest: Manifest) => string;
  /**
   * Remaining-ms chain budget forwarded to compose (CanonicalRequest.deadline).
   * Omitted → composer default (`null`, unbounded).
   */
  deadline?: number | null;
  /** Stage 10 — production `composeRequest` (injected; avoids eager prompt-registry load). */
  composeRequest: ComposeRequestFn;
  logger?: Logger;
};

export type GuardBindings = {
  DB: D1Database;
  DO: DurableObjectNamespace;
  rateLimit: RateLimitBindings;
};

export type GuardFreshSuccess = {
  ok: true;
  outcome?: undefined;
  requestId: string;
  principal: Principal;
  manifest: Manifest;
  filteredContext: Record<string, unknown>;
  composed: CanonicalRequest;
  promptVersion: string;
  /** Distinctive substring of the composed system instruction for leak guards. */
  systemPromptLeakNeedle: string;
  /** Start, interior, and end slices; the guard matches any of them. */
  systemPromptLeakNeedles?: readonly string[];
  guardLatencyMs: number;
  requestReference: string;
  idempotencyKey: string;
  transcript?: Transcript;
  /** Provider ids with an active `provider:<id>` kill switch (guard stage 5). */
  killedProviderIds?: readonly string[];
  /** Soft-threshold / grace admission flag; drives `degraded_notice` and router tier. */
  degraded?: boolean;
  /** Journaled and routed tier, derived from admission (never client-supplied). */
  routingTier?: "standard" | "degraded";
  /** Admission-time entitlement snapshot — settlement period and DO credit reset. */
  entitlementSnapshot: EntitlementSnapshot;
};

/** Idempotent replay — stages 9–10 skipped; adapter replays from priorState. */
export type GuardIdempotentSuccess = {
  ok: true;
  outcome: "idempotent";
  priorState: IdempotencyPriorState;
  requestId: string;
  guardLatencyMs: number;
  requestReference: string;
  idempotencyKey: string;
};

export type GuardSuccess = GuardFreshSuccess | GuardIdempotentSuccess;

export type GuardFailure = {
  ok: false;
  code: string;
  stage: GuardStage;
  guardLatencyMs: number;
  retryAfter?: number;
  periodReset?: string;
  contextRequired?: ContextRequiredFailure;
};

export type GuardResult = GuardSuccess | GuardFailure;

export type SettleHappyPathInput = {
  requestId: string;
  requestReference: string;
  installationId: string;
  composed: CanonicalRequest;
  filteredContext: Record<string, unknown>;
  period: string;
  quotaWeight: number;
  recordedAt: string;
  usage?: { tokens: number; cost: number };
  logger?: Logger;
};

export type SettleHappyPathBindings = {
  DB: D1Database;
  R2: R2Bucket;
  DO: DurableObjectNamespace;
  ctx: {
    waitUntil(promise: Promise<unknown>): void;
    drainWaitUntil(): Promise<void>;
  };
};

export type SettleHappyPathResult =
  | { ok: true; result: CanonicalResult }
  | { ok: false; code: string };

function fail(
  stage: GuardStage,
  code: string,
  started: number,
  logger: Logger,
  extras?: Pick<GuardFailure, "retryAfter" | "periodReset" | "contextRequired">,
): GuardFailure {
  const guardLatencyMs = performance.now() - started;
  const logData = { stage, code, guard_latency_ms: Math.round(guardLatencyMs) };
  if (code === "internal_error") {
    logger.error(`Guard failed at stage ${stage}`, logData);
  } else {
    logger.info(`Guard rejected at stage ${stage}`, logData);
  }
  return {
    ok: false,
    code,
    stage,
    guardLatencyMs,
    ...(extras?.retryAfter !== undefined ? { retryAfter: extras.retryAfter } : {}),
    ...(extras?.periodReset !== undefined ? { periodReset: extras.periodReset } : {}),
    ...(extras?.contextRequired !== undefined
      ? { contextRequired: extras.contextRequired }
      : {}),
  };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Wire-shape helpers: prefer body fields when present (Flutter / adapter snake_case). */
function extractUserIntent(
  body: Record<string, unknown>,
  fallback: string,
): string {
  if (typeof body.user_intent === "string") {
    return body.user_intent;
  }
  if (typeof body.intent === "string") {
    return body.intent;
  }
  return fallback;
}

function extractSuppliedContext(
  body: Record<string, unknown>,
  fallback: Record<string, unknown>,
): Record<string, unknown> {
  if (isPlainObject(body.context)) {
    return body.context;
  }
  return fallback;
}

function extractConversationId(body: Record<string, unknown>): string | undefined {
  if (typeof body.conversation_id === "string") {
    return body.conversation_id;
  }
  if (typeof body.conversationId === "string") {
    return body.conversationId;
  }
  return undefined;
}

function extractTurnOrdinal(body: Record<string, unknown>): number | undefined {
  const raw =
    body.turn_ordinal !== undefined ? body.turn_ordinal : body.turnOrdinal;
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return raw;
  }
  return undefined;
}

function extractTranscript(body: Record<string, unknown>): unknown {
  if ("transcript" in body) {
    return body.transcript;
  }
  return undefined;
}

async function releaseAdmissionReservation(
  bindings: GuardBindings,
  installationId: string,
  request: Omit<ReleaseRequest, "kind" | "installationId">,
): Promise<void> {
  const id = bindings.DO.idFromName(installationId);
  const stub = bindings.DO.get(id);
  try {
    const response = await stub.fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        kind: "release",
        installationId,
        ...request,
      } satisfies ReleaseRequest),
    });
    // Drain the body so Miniflare isolated DO storage can pop cleanly.
    await response.text();
  } catch {
    // Best-effort compensation — stage-9 failure still returns to the caller.
  }
}

/**
 * §6.1 stages 1–10 (the guard). Timed end-to-end for load p95 measurement.
 */
export async function runGuard(
  input: GuardInput,
  bindings: GuardBindings,
): Promise<GuardResult> {
  const started = performance.now();
  const logger = input.logger ?? noopLogger;
  logger.info("Guard pipeline started", {
    trace_id: input.traceId,
    request_reference: input.requestReference,
    capability_id: input.capabilityId,
  });
  // Stage 8 / identity clock: seconds (JWT NumericDate), never Date.now() ms.
  const nowSeconds = input.now ?? Math.floor(Date.now() / 1000);

  // Stage 1 — ingress size + JSON shape
  const bodyBytes = new TextEncoder().encode(input.bodyText).byteLength;
  if (bodyBytes > INGRESS_BODY_SIZE_LIMIT) {
    return fail(1, "request_too_large", started, logger);
  }
  const body = parseAdapterRequestBody(input.bodyText);
  if (body === null) {
    return fail(1, "internal_error", started, logger);
  }

  // Prefer wire body intent/context when present (Flutter CapabilityInvokeInput shape).
  const userIntent = extractUserIntent(body, input.userIntent);
  const suppliedContext = extractSuppliedContext(body, input.suppliedContext);
  const conversationId = extractConversationId(body);
  const turnOrdinal = extractTurnOrdinal(body);
  const transcript = extractTranscript(body);

  // Stage 2 — identity (token verify) or harness-supplied principal
  let principal: Principal;
  if (input.principal !== undefined && input.token === undefined) {
    principal = input.principal;
  } else {
    if (input.token === undefined || input.verifier === undefined) {
      return fail(2, "unauthenticated", started, logger);
    }
    const verifyCtx: VerifyContext = {
      audience: input.verifyContext?.audience ?? "ai-platform",
      clockSkewSeconds: input.verifyContext?.clockSkewSeconds ?? 60,
      now: input.verifyContext?.now ?? nowSeconds,
      cache: input.verifyContext?.cache ?? input.cache,
      reader: input.verifyContext?.reader ?? input.reader,
    };
    const verified = await input.verifier.verify(input.token, verifyCtx);
    if (!verified.ok) {
      return fail(2, verified.code, started, logger);
    }
    principal = verified.principal;
  }

  // Stage 3 — entitlement
  const entitlementResult = await evaluateEntitlement(
    principal,
    input.entitlement,
    input.cache,
    input.reader,
    logger,
  );
  if (!entitlementResult.ok) {
    return fail(3, entitlementResult.code, started, logger);
  }

  // Stage 4 — rate limit
  const rateResult = await checkRateLimit(
    {
      installationId: principal.installationId,
      actorId: principal.actorId,
      capabilityId: input.capabilityId,
    },
    bindings.rateLimit,
    logger,
  );
  if (!rateResult.ok) {
    return fail(4, rateResult.code, started, logger, {
      retryAfter: rateResult.retryAfter,
    });
  }

  // Stage 5 — capability resolve (stage 3 evaluates the same D1 kill-switch rows first; kept as defense against future pipeline reordering).
  const resolved = await resolve(
    principal,
    input.capabilityId,
    input.capabilityVersion,
    input.cache,
    input.reader,
    logger,
  );
  if (!resolved.ok) {
    return fail(5, resolved.code, started, logger);
  }
  const manifest = resolved.manifest;
  const killedProviderIds = resolved.killedProviderIds ?? [];

  // Stage 6 — context validate (H2 conversational options when interactionMode is conversational)
  const conversationalOptions =
    manifest.interactionMode === "conversational" && turnOrdinal !== undefined
      ? { transcript, legTurnOrdinal: turnOrdinal }
      : undefined;
  const contextResult = validateContext(
    manifest,
    suppliedContext,
    principal,
    conversationalOptions,
    logger,
  );
  if (!contextResult.ok) {
    return fail(6, contextResult.code, started, logger, {
      ...(contextResult.code === "context_required"
        ? { contextRequired: contextResult }
        : {}),
    });
  }
  const filteredContext = contextResult.filteredContext as Record<string, unknown>;
  const validatedTranscript = contextResult.validatedTranscript;

  // Stage 7 — cost pre-flight (include validated transcript so conversational growth is priced)
  const serializedInput = serializePreflightInput({
    filteredContext,
    userIntent,
    transcript: validatedTranscript,
  });
  const promptArtifactBytes =
    input.promptArtifactByteLength ??
    input.promptScaffoldByteLength?.(manifest) ??
    0;
  const preflight = runCostPreflight(
    manifest,
    serializedInput,
    promptArtifactBytes,
    logger,
    principal.installationId,
  );
  if (!preflight.ok) {
    return fail(7, preflight.code, started, logger);
  }

  // Stage 8 — admission (one Quota DO round trip)
  const admission = await runAdmission(
    {
      principal,
      idempotencyKey: input.idempotencyKey,
      requestReference: input.requestReference,
      cache: input.cache,
      reader: input.reader,
      logger,
    },
    { DB: bindings.DB, DO: bindings.DO } satisfies AdmissionBindings,
    { now: nowSeconds },
  );
  if (!admission.ok) {
    return fail(8, admission.code, started, logger, {
      ...(admission.retryAfter !== undefined
        ? { retryAfter: admission.retryAfter }
        : {}),
      ...(admission.periodReset !== undefined
        ? { periodReset: admission.periodReset }
        : {}),
    });
  }

  // Idempotent replay — short-circuit stages 9–10; adapter replays from priorState.
  if (admission.outcome === "idempotent") {
    logger.info("Guard idempotent replay", {
      request_id: admission.priorState.requestId,
      prior_state: admission.priorState.state,
    });
    return {
      ok: true,
      outcome: "idempotent",
      priorState: admission.priorState,
      requestId: admission.priorState.requestId,
      guardLatencyMs: performance.now() - started,
      requestReference: input.requestReference,
      idempotencyKey: input.idempotencyKey,
    };
  }

  // Safety net for future DO admission outcomes; currently unreachable.
  if (admission.outcome !== "admitted" && admission.outcome !== "grace_admitted") {
    return fail(8, "internal_error", started, logger);
  }
  const { requestId, entitlement: entitlementSnapshot } = admission;

  const degraded =
    admission.outcome === "grace_admitted" ||
    (admission.outcome === "admitted" && admission.degraded === true);
  const routingTier = routingTierFromAdmission({
    outcome: "admitted",
    requestId,
    ...(degraded ? { degraded: true } : {}),
  });

  // Stage 9 — journal request row (one D1 insert); conversational grouping from wire body
  const journalled = await createRequestRow(
    {
      requestId,
      requestReference: input.requestReference,
      principal,
      manifest,
      idempotencyKey: input.idempotencyKey,
      traceId: input.traceId,
      conversationId: conversationId ?? null,
      turnOrdinal: turnOrdinal ?? null,
      routingTier,
      promptArtifactHash: input.resolvePromptVersion?.(manifest),
    },
    bindings.DB,
    logger,
  );
  if (!journalled.ok) {
    await releaseAdmissionReservation(bindings, principal.installationId, {
      requestId,
      idempotencyKey: input.idempotencyKey,
      jti: principal.jti,
    });
    return fail(9, journalled.code, started, logger);
  }

  // Stage 10 — prompt composition
  const composed = input.composeRequest({
    manifest,
    filteredContext,
    userIntent,
    principal,
    requestReference: input.requestReference,
    streamFlag: true,
    deadline: input.deadline ?? null,
    transcript: validatedTranscript,
  });
  if (!composed.ok) {
    await recordTerminalState(
      requestId,
      "Failed",
      composed.code,
      new Date().toISOString(),
      bindings.DB,
      manifest.interactionMode,
    );
    await releaseAdmissionReservation(bindings, principal.installationId, {
      requestId,
      idempotencyKey: input.idempotencyKey,
      jti: principal.jti,
    });
    return fail(10, composed.code, started, logger);
  }

  logger.info("Guard passed", {
    request_id: requestId,
    routing_tier: routingTier,
    guard_latency_ms: Math.round(performance.now() - started),
  });

  return {
    ok: true,
    requestId,
    principal,
    manifest,
    filteredContext,
    composed: composed.request,
    promptVersion: composed.promptVersion,
    systemPromptLeakNeedle: composed.systemPromptLeakNeedle,
    ...(composed.systemPromptLeakNeedles !== undefined
      ? { systemPromptLeakNeedles: composed.systemPromptLeakNeedles }
      : {}),
    guardLatencyMs: performance.now() - started,
    requestReference: input.requestReference,
    idempotencyKey: input.idempotencyKey,
    killedProviderIds,
    routingTier,
    entitlementSnapshot,
    ...(degraded ? { degraded: true } : {}),
    ...(validatedTranscript !== undefined
      ? { transcript: validatedTranscript }
      : {}),
  };
}

function buildAttempt(result: CanonicalResult): AttemptInput {
  const priced = ledgerUsageFromProvider(result);
  return {
    attemptNo: 1,
    provider: result.providerModel.provider,
    model: result.providerModel.model,
    outcome: "success",
    latencyMs: result.timing.provider_ms,
    tokensIn: result.usage.input,
    tokensOut: result.usage.output,
    cost: priced.cost,
    providerRequestId: result.providerRequestId,
    rawBody: { completion: result.finalContent },
  };
}

/**
 * Post-guard settle for load / FakeAdapter happy path:
 * stage 11 (FakeAdapter) → stage 15 (terminal + credit) → stage 16 (detail + R2).
 */
export async function settleHappyPath(
  input: SettleHappyPathInput,
  bindings: SettleHappyPathBindings,
): Promise<SettleHappyPathResult> {
  const logger = input.logger ?? noopLogger;
  logger.info("Happy-path settlement started", {
    request_id: input.requestId,
    request_reference: input.requestReference,
  });

  const adapter = new FakeAdapter(["success"]);
  const invokeResult = await adapter.invoke(input.composed);
  if (invokeResult.kind !== "success") {
    logger.error("Happy-path settlement failed at provider invoke", {
      request_id: input.requestId,
      code: "provider_unavailable",
    });
    return { ok: false, code: "provider_unavailable" };
  }
  const { result } = invokeResult;

  const usage = input.usage ?? ledgerUsageFromProvider(result);

  // Stage 15 — record terminal state, then credit usage (one DO round trip)
  await recordTerminalState(
    input.requestId,
    "Completed",
    undefined,
    input.recordedAt,
    bindings.DB,
  );

  const credited = await creditUsage(
    {
      installationId: input.installationId,
      requestId: input.requestId,
      requestReference: input.requestReference,
      usage,
      partial: false,
      credits: input.quotaWeight,
    },
    { DO: bindings.DO } satisfies CreditBindings,
  );
  if (!credited.ok) {
    logger.error("Happy-path settlement failed at credit", {
      request_id: input.requestId,
      code: credited.code,
    });
    return { ok: false, code: credited.code };
  }

  // Stage 16 — post-response detail + one R2 envelope (never fails the request)
  const detail: PostResponseInput = {
    requestId: input.requestId,
    installationId: input.installationId,
    period: input.period,
    quotaWeight: input.quotaWeight,
    totalTokens: usage.tokens,
    totalCost: usage.cost,
    filteredContext: input.filteredContext,
    composedPrompt: input.composed,
    attempts: [buildAttempt(result)],
    validatedResult: result,
    recordedAt: input.recordedAt,
  };
  writePostResponseDetail(detail, {
    db: bindings.DB,
    r2: bindings.R2,
    ctx: bindings.ctx,
  });
  await bindings.ctx.drainWaitUntil();

  logger.info("Happy-path settlement completed", {
    request_id: input.requestId,
    tokens: usage.tokens,
  });

  return { ok: true, result };
}
