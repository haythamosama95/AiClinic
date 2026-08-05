/**
 * Thin §6.1 pipeline composition — guard (stages 1–10) plus happy-path settle
 * (FakeAdapter stage 11 + stages 15–16). Production modules only; no Worker wiring.
 */

import { runAdmission, type AdmissionBindings } from "../admission";
import { INGRESS_BODY_SIZE_LIMIT, parseAdapterRequestBody } from "../adapter";
import { resolve } from "../capability";
import type { ConfigCache, D1Reader } from "../config-cache";
import type { CanonicalRequest, CanonicalResult } from "../contracts/canonical";
import { runCostPreflight } from "../context/preflight";
import { validateContext } from "../context/validator";
import { creditUsage, type CreditBindings } from "../credit";
import { evaluateEntitlement, type EntitlementContext } from "../entitlement";
import type { Principal, TokenVerifier, VerifyContext } from "../identity";
import {
  createRequestRow,
  recordTerminalState,
  writePostResponseDetail,
  type AttemptInput,
  type PostResponseInput,
} from "../journal";
import type { Manifest } from "../manifest";
import { FakeAdapter } from "../provider/fake";
import {
  checkRateLimit,
  type RateLimitBindings,
} from "../rate-limit";

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
}) =>
  | { ok: true; request: CanonicalRequest; promptVersion: string }
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
  /** Stage 10 — production `composeRequest` (injected; avoids eager prompt-registry load). */
  composeRequest: ComposeRequestFn;
};

export type GuardBindings = {
  DB: D1Database;
  DO: DurableObjectNamespace;
  rateLimit: RateLimitBindings;
};

export type GuardSuccess = {
  ok: true;
  requestId: string;
  principal: Principal;
  manifest: Manifest;
  filteredContext: Record<string, unknown>;
  composed: CanonicalRequest;
  promptVersion: string;
  guardLatencyMs: number;
  requestReference: string;
  idempotencyKey: string;
};

export type GuardFailure = {
  ok: false;
  code: string;
  stage: GuardStage;
  guardLatencyMs: number;
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
): GuardFailure {
  return {
    ok: false,
    code,
    stage,
    guardLatencyMs: performance.now() - started,
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

/**
 * §6.1 stages 1–10 (the guard). Timed end-to-end for load p95 measurement.
 */
export async function runGuard(
  input: GuardInput,
  bindings: GuardBindings,
): Promise<GuardResult> {
  const started = performance.now();

  // Stage 1 — ingress size + JSON shape
  const bodyBytes = new TextEncoder().encode(input.bodyText).byteLength;
  if (bodyBytes > INGRESS_BODY_SIZE_LIMIT) {
    return fail(1, "request_too_large", started);
  }
  const body = parseAdapterRequestBody(input.bodyText);
  if (body === null) {
    return fail(1, "internal_error", started);
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
      return fail(2, "unauthenticated", started);
    }
    const verifyCtx: VerifyContext = {
      audience: input.verifyContext?.audience ?? "ai-platform",
      clockSkewSeconds: input.verifyContext?.clockSkewSeconds ?? 60,
      now: input.verifyContext?.now ?? input.now ?? Math.floor(Date.now() / 1000),
      cache: input.verifyContext?.cache ?? input.cache,
      reader: input.verifyContext?.reader ?? input.reader,
    };
    const verified = await input.verifier.verify(input.token, verifyCtx);
    if (!verified.ok) {
      return fail(2, verified.code, started);
    }
    principal = verified.principal;
  }

  // Stage 3 — entitlement
  const entitlementResult = await evaluateEntitlement(
    principal,
    input.entitlement,
    input.cache,
    input.reader,
  );
  if (!entitlementResult.ok) {
    return fail(3, entitlementResult.code, started);
  }

  // Stage 4 — rate limit
  const rateResult = await checkRateLimit(
    {
      installationId: principal.installationId,
      actorId: principal.actorId,
      capabilityId: input.capabilityId,
    },
    bindings.rateLimit,
  );
  if (!rateResult.ok) {
    return fail(4, rateResult.code, started);
  }

  // Stage 5 — capability resolve
  const resolved = await resolve(
    principal,
    input.capabilityId,
    input.capabilityVersion,
    input.cache,
    input.reader,
  );
  if (!resolved.ok) {
    return fail(5, resolved.code, started);
  }
  const manifest = resolved.manifest;

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
  );
  if (!contextResult.ok) {
    return fail(6, contextResult.code, started);
  }
  const filteredContext = contextResult.filteredContext as Record<string, unknown>;

  // Stage 7 — cost pre-flight
  const serializedInput = JSON.stringify({
    filteredContext,
    userIntent,
  });
  const preflight = runCostPreflight(
    manifest,
    serializedInput,
    input.promptArtifactByteLength ?? 0,
  );
  if (!preflight.ok) {
    return fail(7, preflight.code, started);
  }

  // Stage 8 — admission (one Quota DO round trip)
  const admission = await runAdmission(
    {
      principal,
      idempotencyKey: input.idempotencyKey,
      requestReference: input.requestReference,
      cache: input.cache,
      reader: input.reader,
    },
    { DB: bindings.DB, DO: bindings.DO } satisfies AdmissionBindings,
    { now: input.now },
  );
  if (!admission.ok) {
    return fail(8, admission.code, started);
  }
  if (admission.outcome !== "admitted" && admission.outcome !== "grace_admitted") {
    return fail(8, "internal_error", started);
  }
  const { requestId } = admission;

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
    },
    bindings.DB,
  );
  if (!journalled.ok) {
    return fail(9, journalled.code, started);
  }

  // Stage 10 — prompt composition
  const composed = input.composeRequest({
    manifest,
    filteredContext,
    userIntent,
    principal,
    requestReference: input.requestReference,
  });
  if (!composed.ok) {
    return fail(10, composed.code, started);
  }

  return {
    ok: true,
    requestId,
    principal,
    manifest,
    filteredContext,
    composed: composed.request,
    promptVersion: composed.promptVersion,
    guardLatencyMs: performance.now() - started,
    requestReference: input.requestReference,
    idempotencyKey: input.idempotencyKey,
  };
}

function buildAttempt(result: CanonicalResult): AttemptInput {
  return {
    attemptNo: 1,
    provider: result.providerModel.provider,
    model: result.providerModel.model,
    outcome: "success",
    latencyMs: result.timing.provider_ms,
    tokensIn: result.usage.input,
    tokensOut: result.usage.output,
    cost: 0.001,
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
  const adapter = new FakeAdapter(["success"]);
  const invokeResult = await adapter.invoke(input.composed);
  if (invokeResult.kind !== "success") {
    return { ok: false, code: "provider_unavailable" };
  }
  const { result } = invokeResult;

  const usage = input.usage ?? {
    tokens: result.usage.input + result.usage.output,
    cost: 0.001,
  };

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
    },
    { DO: bindings.DO } satisfies CreditBindings,
  );
  if (!credited.ok) {
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

  return { ok: true, result };
}
