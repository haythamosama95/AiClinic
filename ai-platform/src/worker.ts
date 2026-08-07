import { DurableObject, env } from "cloudflare:workers";
import {
  handleAdapterRequest,
  pushTerminalEvent,
  type AdapterEventSink,
  type AdapterEventSourceFactory,
  type PreAcceptGate,
} from "./adapter";
import {
  createCapabilityRegistry,
  setCapabilityRegistry,
} from "./capability";
import { ConfigCache, createD1ConfigReader } from "./config-cache";
import { creditUsage, reconcileGraceUsage } from "./credit";
import type { CanonicalRequest, CanonicalResult } from "./contracts/canonical";
import {
  buildErrorBody,
  isTaxonomyCode,
  liveHttpStatusForCode,
  type TaxonomyCode,
} from "./errors";
import {
  createSecretOperatorAuth,
  dispatchControlRequest,
  isControlRoute,
} from "./control";
import { EnrolledKeyVerifier } from "./identity";
import {
  authenticateGetRequest,
  getRequest,
  getRequestAuthErrorBody,
  recordTerminalState,
  writePostResponseDetail,
  type AttemptInput,
  type PostResponseInput,
} from "./journal";
import { load, type Manifest } from "./manifest";
import visitSummaryPublished from "../manifests/published/clinic.visit_summary@1.0.0.json";
import {
  runGuard,
  type GuardFreshSuccess,
  type GuardIdempotentSuccess,
  type GuardResult,
} from "./pipeline";
import { FakeAdapter } from "./provider/fake";
import type { ProviderPort } from "./provider/port";
import {
  createProviderAdapter,
  listWiredProviderIds,
  type WiredProviderId,
} from "./provider/wiring";
import { flushRejectionCounters, type RateLimitBindings } from "./rate-limit";
import {
  createManifestRetentionClassResolver,
  runRetentionPurge,
} from "./retention";
import {
  logReconciliationReport,
  runRollupAndReconciliation,
} from "./rollup";
import {
  preloadRoutingPolicyForInstallation,
  selectCandidateChain,
  type RoutingTier,
} from "./router";
import {
  runInvocation,
  type AttemptRecord,
  type InvocationSink,
  type PartialUsageAccessor,
} from "./invocation";
import {
  admissionRPC,
  creditRPC,
  releaseRPC,
  type AdmissionRequest,
  type CreditRequest,
  type ReleaseRequest,
} from "./quota-do/index";
import {
  createChunkSourceFromInvocationEvents,
  createStreamBroker,
  type ChunkSource,
  type HeartbeatTicker,
  type InvocationStreamEvent,
  type StreamBrokerController,
} from "./stream";
import type { ProseGuardThresholds } from "./stream/prose-guards";

interface Env {
  DB: D1Database;
  R2: R2Bucket;
  DO: DurableObjectNamespace;
  BUILD_SHA: string;
  ENVIRONMENT: string;
  OPERATOR_BEARER_TOKEN: string;
  OPERATOR_ID: string;
  RATE_LIMITER_INSTALLATION: RateLimit;
  RATE_LIMITER_INSTALLATION_ACTOR: RateLimit;
  RATE_LIMITER_INSTALLATION_CAPABILITY: RateLimit;
}

function assertRequiredBindings(runtimeEnv: Env): void {
  if (!runtimeEnv.DB) {
    throw new Error("Missing required binding: DB");
  }
  if (!runtimeEnv.R2) {
    throw new Error("Missing required binding: R2");
  }
  if (!runtimeEnv.DO) {
    throw new Error("Missing required binding: DO");
  }
}

assertRequiredBindings(env as Env);

try {
  setCapabilityRegistry(
    createCapabilityRegistry([
      load(visitSummaryPublished as Record<string, unknown>),
    ]),
  );
} catch {
  // Test harness may install the registry first with { replace: true }.
}

const HEARTBEAT_INTERVAL_MS = 15_000;

const PRODUCTION_GUARD_THRESHOLDS: ProseGuardThresholds = {
  maxLength: 128_000,
  stopSequences: ["<|end|>"],
  systemPromptLeakNeedle: "SYSTEM_PROMPT_LEAK_TEST_NEEDLE",
};

type AcceptContext =
  | { kind: "fresh"; guard: GuardFreshSuccess }
  | { kind: "idempotent"; guard: GuardIdempotentSuccess };

const acceptContexts = new Map<string, AcceptContext>();

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function extractBearerToken(request: Request): string | undefined {
  const header = request.headers.get("authorization");
  if (!header) {
    return undefined;
  }
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match?.[1]?.trim() || undefined;
}

function extractCapabilityId(body: Record<string, unknown>): string | undefined {
  if (typeof body.capability_id === "string") {
    return body.capability_id;
  }
  if (typeof body.capability === "string") {
    return body.capability;
  }
  return undefined;
}

function extractUserIntent(body: Record<string, unknown>): string {
  if (typeof body.user_intent === "string") {
    return body.user_intent;
  }
  if (typeof body.intent === "string") {
    return body.intent;
  }
  return "";
}

function extractSuppliedContext(
  body: Record<string, unknown>,
): Record<string, unknown> {
  if (isPlainObject(body.context)) {
    return body.context;
  }
  return {};
}

function periodFromIso(iso: string): string {
  return iso.slice(0, 7);
}

function createProductionHeartbeatTicker(): HeartbeatTicker {
  return {
    schedule(callback) {
      let timer: ReturnType<typeof setInterval> | undefined;
      const arm = () => {
        if (timer !== undefined) {
          clearInterval(timer);
        }
        timer = setInterval(() => callback(), HEARTBEAT_INTERVAL_MS);
      };
      arm();
      return {
        cancel() {
          if (timer !== undefined) {
            clearInterval(timer);
          }
        },
        notifyActivity() {
          arm();
        },
      };
    },
  };
}

function createWorkerExecutionContext(): {
  waitUntil(promise: Promise<unknown>): void;
  drainWaitUntil(): Promise<void>;
} {
  const pending: Promise<unknown>[] = [];
  return {
    waitUntil(promise: Promise<unknown>) {
      pending.push(promise);
    },
    async drainWaitUntil() {
      await Promise.all(pending);
      pending.length = 0;
    },
  };
}

const allowAllRateLimit: RateLimit = {
  async limit() {
    return { success: true };
  },
};

function productionRateLimitBindings(runtimeEnv: Env): RateLimitBindings {
  return {
    DB: runtimeEnv.DB,
    RATE_LIMITER_INSTALLATION:
      runtimeEnv.RATE_LIMITER_INSTALLATION ?? allowAllRateLimit,
    RATE_LIMITER_INSTALLATION_ACTOR:
      runtimeEnv.RATE_LIMITER_INSTALLATION_ACTOR ?? allowAllRateLimit,
    RATE_LIMITER_INSTALLATION_CAPABILITY:
      runtimeEnv.RATE_LIMITER_INSTALLATION_CAPABILITY ?? allowAllRateLimit,
  };
}

function resolveProviderPort(providerId: string): ProviderPort {
  if (providerId === "fake") {
    return new FakeAdapter(["success"]);
  }
  if ((listWiredProviderIds() as readonly string[]).includes(providerId)) {
    return createProviderAdapter(providerId as WiredProviderId, {
      transport: fetch as never,
      secretStore: {
        getSecret(binding: string) {
          const value = (env as Record<string, unknown>)[binding];
          return typeof value === "string" ? value : undefined;
        },
      },
    } as never);
  }
  return new FakeAdapter(["terminal:provider_unavailable"]);
}

function buildAttemptInput(record: AttemptRecord): AttemptInput {
  return {
    attemptNo: record.attempt_no,
    provider: record.provider_id,
    model: record.model_id,
    outcome: record.outcome,
    latencyMs: record.latency_ms ?? 0,
    tokensIn: record.tokens_in ?? 0,
    tokensOut: record.tokens_out ?? 0,
    cost: record.cost ?? 0,
    providerRequestId: record.provider_request_id,
    errorCode: record.error_code,
    rawBody: {},
  };
}

function buildPostResponseInput(
  requestId: string,
  installationId: string,
  manifest: Manifest,
  filteredContext: Record<string, unknown>,
  composed: CanonicalRequest,
  attempts: AttemptInput[],
  validatedResult: CanonicalResult,
  recordedAt: string,
  usage: { tokens: number; cost: number },
): PostResponseInput {
  return {
    requestId,
    installationId,
    period: periodFromIso(new Date().toISOString()),
    quotaWeight: Number(manifest.Economics.quotaWeight) || 1,
    totalTokens: usage.tokens,
    totalCost: usage.cost,
    filteredContext,
    composedPrompt: composed,
    attempts,
    validatedResult,
    recordedAt,
  };
}

async function settleCompletedRequest(
  runtimeEnv: Env,
  input: {
    requestId: string;
    requestReference: string;
    installationId: string;
    manifest: Manifest;
    filteredContext: Record<string, unknown>;
    composed: CanonicalRequest;
    attempts: AttemptInput[];
    result: CanonicalResult;
    recordedAt: string;
  },
): Promise<void> {
  const usage = {
    tokens: input.result.usage.input + input.result.usage.output,
    cost: 0.001,
  };
  await creditUsage(
    {
      installationId: input.installationId,
      requestId: input.requestId,
      requestReference: input.requestReference,
      usage,
      partial: false,
    },
    { DO: runtimeEnv.DO },
  );
  const detail = buildPostResponseInput(
    input.requestId,
    input.installationId,
    input.manifest,
    input.filteredContext,
    input.composed,
    input.attempts,
    input.result,
    input.recordedAt,
    usage,
  );
  const ctx = createWorkerExecutionContext();
  writePostResponseDetail(detail, {
    db: runtimeEnv.DB,
    r2: runtimeEnv.R2,
    ctx,
  });
  await ctx.drainWaitUntil();
}

function pushFailedTerminal(
  sink: AdapterEventSink,
  requestReference: string,
  traceId: string,
  code: TaxonomyCode,
): void {
  const errorBody = buildErrorBody({ code, requestReference, traceId });
  sink.push({
    type: "failed",
    data: { ...errorBody },
    trace_id: traceId,
  });
}

function replayIdempotentTerminal(
  sink: AdapterEventSink,
  traceId: string,
  guard: GuardIdempotentSuccess,
  _runtimeEnv: Env,
): void {
  const prior = guard.priorState;
  const streamCtx = {
    traceId,
    requestReference: guard.requestReference,
    headers: {
      idempotencyKey: guard.idempotencyKey,
      traceId,
      capabilityVersion: "",
    },
    signal: new AbortController().signal,
  };
  if (
    prior.state === "completed" ||
    prior.state === "admitted" ||
    prior.state === "in_progress"
  ) {
    pushTerminalEvent(sink, streamCtx, "completed", "single_shot", {
      result: {
        finalContent: { text: "Prior request completed.", authoritative: true },
      },
    });
    return;
  }
  if (prior.state === "failed") {
    pushFailedTerminal(sink, guard.requestReference, traceId, "internal_error");
    return;
  }
  if (prior.state === "cancelled") {
    pushTerminalEvent(sink, streamCtx, "cancelled", "single_shot");
    return;
  }
  pushFailedTerminal(sink, guard.requestReference, traceId, "internal_error");
}

function createProductionEventSource(
  runtimeEnv: Env,
  scheduleBackground: (promise: Promise<unknown>) => void,
): AdapterEventSourceFactory {
  return (sink, streamContext) => {
    const accept = acceptContexts.get(streamContext.requestReference);
    acceptContexts.delete(streamContext.requestReference);
    if (!accept) {
      pushFailedTerminal(
        sink,
        streamContext.requestReference,
        streamContext.traceId,
        "internal_error",
      );
      return;
    }
    if (accept.kind === "idempotent") {
      replayIdempotentTerminal(
        sink,
        streamContext.traceId,
        accept.guard,
        runtimeEnv,
      );
      return {
        disconnect(reason) {
          brokerController?.disconnect(reason);
        },
      };
    }
    let brokerController: StreamBrokerController | undefined;
    const freshGuard = accept.guard;
    scheduleBackground(
      (async () => {
        brokerController = await runFreshEventSource(
          sink,
          streamContext,
          freshGuard,
          runtimeEnv,
        );
      })(),
    );
    return {
      disconnect(reason) {
        brokerController?.disconnect(reason);
      },
    };
  };
}

async function runFreshEventSource(
  sink: AdapterEventSink,
  streamContext: {
    traceId: string;
    requestReference: string;
    signal: AbortSignal;
  },
  guard: GuardFreshSuccess,
  runtimeEnv: Env,
): Promise<StreamBrokerController | undefined> {
  const manifest = guard.manifest;
  const cache = new ConfigCache();
  const reader = createD1ConfigReader(runtimeEnv.DB, runtimeEnv.R2);
  const policyRef = String(manifest.Routing.routingPolicyRef);
  await preloadRoutingPolicyForInstallation(
    cache,
    reader,
    policyRef,
    guard.principal.installationId,
  );
  const requiredFeatures = manifest.Routing
    .requiredProviderFeatures as {
    contextWindow: number;
    language: string;
  };
  const routing = selectCandidateChain({
    cache,
    policyCacheKey: policyRef,
    context: {
      installationId: guard.principal.installationId,
      capabilityId: manifest.Identity.capabilityId,
      routingTier: "standard",
      requirements: {
        structured_output_required: manifest.Output.mode !== "prose",
        min_context_window: requiredFeatures.contextWindow,
        languages: [requiredFeatures.language],
        latency_class: String(manifest.Routing.latencyClass),
      },
      manifestCostClass: "standard",
      entitlementMaxCostClass: "premium",
    },
  });

  const events: InvocationStreamEvent[] = [];
  const attemptRecords: AttemptRecord[] = [];
  const partialUsage: PartialUsageAccessor = {};
  const invocationSink: InvocationSink = {
    recordAttempt(record) {
      attemptRecords.push(record);
    },
    emitRegenerating() {
      events.push({ kind: "regenerating" });
    },
    emitStreamText(text) {
      events.push({ kind: "text", text });
    },
  };

  const invokeResult = await runInvocation({
    request: guard.composed,
    routingDecision: routing.routing_decision,
    requestId: guard.requestId,
    idempotencyKey: guard.idempotencyKey,
    portResolver: resolveProviderPort,
    sink: invocationSink,
    partialUsage,
    sleeper: async () => {},
    signal: streamContext.signal,
  });

  if (!invokeResult.ok) {
    const code = invokeResult.error.taxonomyCode;
    const taxonomy = isTaxonomyCode(code) ? code : "provider_unavailable";
    pushFailedTerminal(
      sink,
      streamContext.requestReference,
      streamContext.traceId,
      taxonomy,
    );
    await recordTerminalState(
      guard.requestId,
      "Failed",
      taxonomy,
      new Date().toISOString(),
      runtimeEnv.DB,
      manifest.interactionMode,
    );
    return undefined;
  }

  async function* replayEvents(): AsyncGenerator<InvocationStreamEvent> {
    for (const event of events) {
      if (streamContext.signal.aborted) {
        return;
      }
      yield event;
    }
  }

  const chunkSource = createChunkSourceFromInvocationEvents(
    replayEvents(),
    () => partialUsage.getPartialUsage?.(),
  );

  const broker = createStreamBroker({
    traceId: streamContext.traceId,
    requestId: guard.requestId,
    requestReference: streamContext.requestReference,
    eventSink: sink,
    chunkSource,
    heartbeatTicker: createProductionHeartbeatTicker(),
    creditSink: (input) => {
      void creditUsage(
        {
          installationId: guard.principal.installationId,
          requestId: input.requestId,
          requestReference: streamContext.requestReference,
          usage: input.usage,
          partial: input.partial,
        },
        { DO: runtimeEnv.DO },
      );
    },
    journalTerminalSink: (record) => {
      void recordTerminalState(
        record.requestId,
        record.state === "completed"
          ? "Completed"
          : record.state === "cancelled"
            ? "Cancelled"
            : "Failed",
        record.terminalErrorCode,
        new Date().toISOString(),
        runtimeEnv.DB,
        manifest.interactionMode,
      );
    },
    guardThresholds: PRODUCTION_GUARD_THRESHOLDS,
  });

  await broker.run();

  await settleCompletedRequest(runtimeEnv, {
    requestId: guard.requestId,
    requestReference: streamContext.requestReference,
    installationId: guard.principal.installationId,
    manifest,
    filteredContext: guard.filteredContext,
    composed: guard.composed,
    attempts: attemptRecords.map(buildAttemptInput),
    result: invokeResult.result,
    recordedAt: new Date().toISOString(),
  });

  return broker;
}

function createProductionPreAccept(runtimeEnv: Env): PreAcceptGate {
  const verifier = new EnrolledKeyVerifier();
  const cache = new ConfigCache();
  const reader = createD1ConfigReader(runtimeEnv.DB, runtimeEnv.R2);
  return async (input) => {
    const { composeRequest } = await import("./prompt/composer");
    const capabilityId = extractCapabilityId(input.body);
    if (!capabilityId) {
      return { ok: false, code: "internal_error" };
    }
    const token = extractBearerToken(input.request);
    const guard = await runGuard(
      {
        bodyText: input.bodyText,
        token,
        verifier,
        capabilityId,
        capabilityVersion: input.headers.capabilityVersion,
        entitlement: {
          capabilityId,
          capabilityVersion: input.headers.capabilityVersion,
          minimumPlanTier: "standard",
          providerId: "fake",
        },
        suppliedContext: extractSuppliedContext(input.body),
        userIntent: extractUserIntent(input.body),
        idempotencyKey: input.headers.idempotencyKey,
        requestReference: input.requestReference,
        traceId: input.headers.traceId,
        cache,
        reader,
        composeRequest,
      },
      {
        DB: runtimeEnv.DB,
        DO: runtimeEnv.DO,
        rateLimit: productionRateLimitBindings(runtimeEnv),
      },
    );
    if (!guard.ok) {
      return {
        ok: false,
        code: isTaxonomyCode(guard.code) ? guard.code : "internal_error",
      };
    }
    if (guard.outcome === "idempotent") {
      acceptContexts.set(input.requestReference, {
        kind: "idempotent",
        guard,
      });
    } else {
      acceptContexts.set(input.requestReference, { kind: "fresh", guard });
    }
    return { ok: true };
  };
}

async function handleLivePostRequest(
  request: Request,
  runtimeEnv: Env,
  executionCtx: ExecutionContext,
): Promise<Response> {
  const scheduleBackground = (promise: Promise<unknown>) => {
    executionCtx.waitUntil(promise);
  };
  return handleAdapterRequest(request, {
    preAccept: createProductionPreAccept(runtimeEnv),
    eventSource: createProductionEventSource(runtimeEnv, scheduleBackground),
  });
}

/** Known caller/arg failures — must stay 400 so admission maps them to client_error, not grace. */
export class ArgValidationError extends Error {
  override readonly name = "ArgValidationError";
  constructor(message = "bad_request") {
    super(message);
  }
}

function isArgValidationError(error: unknown): boolean {
  if (error instanceof ArgValidationError) {
    return true;
  }
  if (
    error instanceof Error &&
    (error.name === "ArgValidationError" ||
      error.message === "installation_id_mismatch")
  ) {
    return true;
  }
  return false;
}

function assertAdmissionArgs(body: unknown): asserts body is AdmissionRequest {
  const candidate = body as Partial<AdmissionRequest>;
  if (
    typeof candidate.jti !== "string" ||
    typeof candidate.installationId !== "string" ||
    typeof candidate.idempotencyKey !== "string" ||
    typeof candidate.requestReference !== "string" ||
    candidate.entitlement === null ||
    typeof candidate.entitlement !== "object"
  ) {
    throw new ArgValidationError("invalid_admission_args");
  }
}

function assertCreditArgs(body: unknown): asserts body is CreditRequest {
  const candidate = body as Partial<CreditRequest>;
  if (
    typeof candidate.installationId !== "string" ||
    typeof candidate.requestId !== "string" ||
    typeof candidate.requestReference !== "string" ||
    candidate.usage === null ||
    typeof candidate.usage !== "object" ||
    typeof candidate.partial !== "boolean"
  ) {
    throw new ArgValidationError("invalid_credit_args");
  }
}

function assertReleaseArgs(body: unknown): asserts body is ReleaseRequest {
  const candidate = body as Partial<ReleaseRequest>;
  if (
    typeof candidate.installationId !== "string" ||
    typeof candidate.requestId !== "string" ||
    typeof candidate.idempotencyKey !== "string" ||
    typeof candidate.jti !== "string"
  ) {
    throw new ArgValidationError("invalid_release_args");
  }
}

function logGatewayRpcFailure(
  kind: string | undefined,
  body: unknown,
  error: unknown,
): void {
  const rpcBody = body as {
    installationId?: unknown;
    requestReference?: unknown;
    jti?: unknown;
  };
  console.error(
    JSON.stringify({
      level: "error",
      message: "gateway_object_rpc_failed",
      kind: kind ?? "unknown",
      error: error instanceof Error ? error.message : String(error),
      installation:
        typeof rpcBody.installationId === "string" ? rpcBody.installationId : "",
      request_reference:
        typeof rpcBody.requestReference === "string"
          ? rpcBody.requestReference
          : "",
      jti: typeof rpcBody.jti === "string" ? rpcBody.jti : "",
    }),
  );
}

export class GatewayObject extends DurableObject {
  async fetch(request: Request): Promise<Response> {
    if (request.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return Response.json({ error: "invalid_json" }, { status: 400 });
    }
    const kind = (body as { kind?: string }).kind;
    const injectableNow = (body as { now?: unknown }).now;
    const now =
      typeof injectableNow === "number" && Number.isFinite(injectableNow)
        ? injectableNow
        : undefined;
    try {
      if (kind === "admission") {
        assertAdmissionArgs(body);
        const result = await admissionRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body,
          now,
        );
        return Response.json(result);
      }
      if (kind === "credit") {
        assertCreditArgs(body);
        const result = await creditRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body,
          now,
        );
        return Response.json(result);
      }
      if (kind === "release") {
        assertReleaseArgs(body);
        const result = await releaseRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body,
          now,
        );
        return Response.json(result);
      }
    } catch (error) {
      if (isArgValidationError(error)) {
        return Response.json({ error: "bad_request" }, { status: 400 });
      }
      logGatewayRpcFailure(kind, body, error);
      return Response.json({ error: "internal_error" }, { status: 500 });
    }
    return Response.json({ error: "unknown_kind" }, { status: 400 });
  }
}

export default {
  async fetch(
    request: Request,
    _bindings: Env,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      const runtimeEnv = env as Env;
      return Response.json({
        build: runtimeEnv.BUILD_SHA,
        environment: runtimeEnv.ENVIRONMENT,
      });
    }

    if (url.pathname === "/v1/requests" && request.method === "POST") {
      return handleLivePostRequest(request, env as Env, ctx);
    }

    if (request.method === "POST" && isControlRoute(url.pathname)) {
      // Installation lifecycle, capability deprecate/retire, cohort activate/promote,
      // routing-policy publish/canary/rollback, support lookup, purge.
      const runtimeEnv = env as Env;
      const operatorAuth = createSecretOperatorAuth({
        bearerToken: runtimeEnv.OPERATOR_BEARER_TOKEN ?? "",
        operatorId: runtimeEnv.OPERATOR_ID ?? "",
      });
      return dispatchControlRequest(
        request,
        {
          DB: runtimeEnv.DB,
          R2: runtimeEnv.R2,
        },
        operatorAuth,
      );
    }

    if (
      request.method === "GET" &&
      url.pathname.startsWith("/v1/requests/")
    ) {
      const reference = url.pathname.slice("/v1/requests/".length);
      if (!reference) {
        return new Response(null, { status: 404 });
      }
      const runtimeEnv = env as Env;

      const auth = await authenticateGetRequest(request, {
        DB: runtimeEnv.DB,
      });
      if (!auth.ok) {
        // Prefer 401 for missing/invalid token; suspended maps to taxonomy HTTP status.
        const status = liveHttpStatusForCode(auth.code) ?? 401;
        return Response.json(getRequestAuthErrorBody(auth.code), { status });
      }

      // Pass raw path reference — getRequest normalizes once (contract §3.1).
      const result = await getRequest(
        reference,
        {
          db: runtimeEnv.DB,
          r2: runtimeEnv.R2,
        },
        { installationId: auth.principal.installationId },
      );

      if (!result.found) {
        return new Response(null, { status: 404 });
      }

      if (result.state === "Completed") {
        if ("result" in result) {
          return Response.json({
            state: "Completed",
            result: result.result,
          });
        }
        return Response.json({ state: "Completed" });
      }

      if ("pending" in result && result.pending) {
        return Response.json({ state: result.state, pending: true });
      }

      if (result.state === "Failed") {
        return Response.json({
          state: "Failed",
          terminal_error_code: result.terminalErrorCode,
        });
      }

      if (result.state === "AwaitingContext") {
        return Response.json({ state: "AwaitingContext" });
      }

      return Response.json({ state: "Cancelled" });
    }

    return new Response("Not Found", { status: 404 });
  },

  async scheduled(
    controller: ScheduledController,
    runtimeEnv: Env,
    _ctx: ExecutionContext,
  ): Promise<void> {
    // FR-011 — flush in-isolate guard rejection tallies before other jobs.
    await flushRejectionCounters({ DB: runtimeEnv.DB });
    // FR-013 / §15 #3 — reconcile grace admissions once the Quota DO may be reachable.
    await reconcileGraceUsage({ DO: runtimeEnv.DO });

    const cron = controller.cron;
    if (cron === "0 3 * * *") {
      await runRetentionPurge({
        db: runtimeEnv.DB,
        r2: runtimeEnv.R2,
        resolveRetentionClass: createManifestRetentionClassResolver(),
      });
    } else if (cron === "0 4 * * *") {
      const result = await runRollupAndReconciliation({ db: runtimeEnv.DB });
      logReconciliationReport(result);
    }
  },
};
