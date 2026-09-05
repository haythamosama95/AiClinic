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
import {
  configureIsolateConfigCache,
  createD1ConfigReader,
  isolateConfigCache,
  resolveConfigCacheTtlMs,
} from "./config-cache";
import { creditUsage, reconcileGraceUsage } from "./credit";
import type { CanonicalRequest, CanonicalResult } from "./contracts/canonical";
import {
  buildErrorBody,
  getTaxonomyEntry,
  isTaxonomyCode,
  liveHttpStatusForCode,
  type TaxonomyCode,
} from "./errors";
import { handleDiscoveryRequest } from "./discovery";
import {
  createSecretOperatorAuth,
  dispatchControlRequest,
  isControlRoute,
  isQuotaInspectRoute,
} from "./control";
import { EnrolledKeyVerifier } from "./identity";
import {
  authenticateGetRequest,
  getRequest,
  getRequestAuthErrorBody,
  persistRoutingDecision,
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
import { createFetchTransport } from "./provider/fetch-transport";
import { flushRejectionCounters, type RateLimitBindings } from "./rate-limit";
import {
  createManifestRetentionClassResolver,
  runRetentionPurge,
} from "./retention";
import { runRollupAndReconciliation } from "./rollup";
import {
  preloadRoutingPolicyForInstallation,
  selectCandidateChain,
  type RoutingDecision,
} from "./router";
import {
  runInvocation,
  type AttemptRecord,
  type InvocationSink,
  type PartialUsageAccessor,
} from "./invocation";
import { ledgerUsageFromProvider } from "./pricing";
import { wallClockSleeper } from "./wall-clock-sleeper";
import {
  degradedNoticeFromAdmission,
  routingTierFromAdmission,
  type AdmissionAllowResult,
} from "./soft-threshold";
import {
  admissionRPC,
  creditRPC,
  inspectRPC,
  releaseRPC,
  type AdmissionRequest,
  type CreditIdempotencyState,
  type CreditRequest,
  type EntitlementSnapshot,
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
import {
  createLoggerFactory,
  verbosityFromEnv,
  type Logger,
  type LoggerFactory,
} from "./logger";

interface Env {
  DB: D1Database;
  R2: R2Bucket;
  DO: DurableObjectNamespace;
  BUILD_SHA: string;
  ENVIRONMENT: string;
  LOG_VERBOSITY?: string;
  CONFIG_CACHE_TTL_MS?: string;
  OPERATOR_BEARER_TOKEN: string;
  OPERATOR_ID: string;
  RATE_LIMITER_INSTALLATION: RateLimit;
  RATE_LIMITER_INSTALLATION_ACTOR: RateLimit;
  RATE_LIMITER_INSTALLATION_CAPABILITY: RateLimit;
}

function createWorkerLogFactory(runtimeEnv: Env): LoggerFactory {
  return createLoggerFactory({
    verbosity: verbosityFromEnv(runtimeEnv),
  });
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
configureIsolateConfigCache(
  resolveConfigCacheTtlMs((env as Env).CONFIG_CACHE_TTL_MS),
);

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

const PRODUCTION_GUARD_THRESHOLDS: Omit<
  ProseGuardThresholds,
  "systemPromptLeakNeedle"
> = {
  maxLength: 128_000,
  stopSequences: ["<|end|>"],
  refusalPrefixes: [
    "I'm sorry, I can't help with that",
    "I'm sorry, I can't assist",
  ],
  injectionEchoNeedle: "Ignore previous instructions",
};

type AcceptContext =
  | { kind: "fresh"; guard: GuardFreshSuccess }
  | { kind: "idempotent"; guard: GuardIdempotentSuccess };

type AcceptContextStore = Map<string, AcceptContext>;

type BrokerTerminalState = "completed" | "cancelled" | "failed";

function admissionAllowFromGuard(guard: GuardFreshSuccess): AdmissionAllowResult {
  return {
    outcome: "admitted",
    requestId: guard.requestId,
    ...(guard.degraded ? { degraded: true } : {}),
  };
}

/** Pushable async iterable so invoke and broker run concurrently (live relay). */
function createPushableInvocationEvents(): {
  push(event: InvocationStreamEvent): void;
  end(): void;
  iterable: AsyncIterable<InvocationStreamEvent>;
} {
  const buffer: InvocationStreamEvent[] = [];
  let done = false;
  let wake: (() => void) | undefined;

  const notify = (): void => {
    const resume = wake;
    wake = undefined;
    resume?.();
  };

  return {
    push(event) {
      if (done) {
        return;
      }
      buffer.push(event);
      notify();
    },
    end() {
      done = true;
      notify();
    },
    iterable: {
      async *[Symbol.asyncIterator]() {
        while (true) {
          while (buffer.length > 0) {
            yield buffer.shift() as InvocationStreamEvent;
          }
          if (done) {
            return;
          }
          await new Promise<void>((resolve) => {
            wake = resolve;
          });
        }
      },
    },
  };
}

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
      transport: createFetchTransport(),
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
    rawBody: record.rawBody ?? {},
  };
}

/**
 * Failed settlement always persists at least one ai_attempt row so
 * reconciliation (expected profile: Failed requires attempts + usage) is a
 * signal, including empty-chain provider_unavailable.
 */
function attemptsForFailedSettlement(
  records: AttemptRecord[],
  routing: RoutingDecision,
  taxonomy: TaxonomyCode,
): AttemptInput[] {
  if (records.length > 0) {
    return records.map(buildAttemptInput);
  }
  const hint = routing.chain[0] ?? routing.excluded[0];
  return [
    {
      attemptNo: 1,
      provider: hint?.provider_id ?? "",
      model: hint?.model_id ?? "",
      outcome: "terminal_failure",
      latencyMs: 0,
      tokensIn: 0,
      tokensOut: 0,
      cost: 0,
      errorCode: taxonomy,
      rawBody: {
        payload: {
          reason: "no_provider_attempt",
          excluded: routing.excluded,
        },
        truncated: false,
      },
    },
  ];
}

function placeholderTerminalResult(
  usage: { tokens: number; cost: number },
  finishReason: string,
): CanonicalResult {
  return {
    finalContent: { type: "text", text: "" },
    usage: { input: usage.tokens, output: 0, cached: 0 },
    providerModel: { provider: "", model: "" },
    finishReason,
    providerRequestId: "",
    timing: { queue_ms: 0, provider_ms: 0, total_ms: 0 },
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
  periodStart: string,
): PostResponseInput {
  return {
    requestId,
    installationId,
    period: periodFromIso(periodStart),
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

type SettlementJournalInput = {
  requestId: string;
  installationId: string;
  manifest: Manifest;
  filteredContext: Record<string, unknown>;
  composed: CanonicalRequest;
  attempts: AttemptInput[];
  result: CanonicalResult;
  recordedAt: string;
  usage: { tokens: number; cost: number };
  periodStart: string;
};

async function writeSettlementJournal(
  runtimeEnv: Env,
  input: SettlementJournalInput,
  logger: Logger,
): Promise<void> {
  const detail = buildPostResponseInput(
    input.requestId,
    input.installationId,
    input.manifest,
    input.filteredContext,
    input.composed,
    input.attempts,
    input.result,
    input.recordedAt,
    input.usage,
    input.periodStart,
  );
  const ctx = createWorkerExecutionContext();
  writePostResponseDetail(detail, {
    db: runtimeEnv.DB,
    r2: runtimeEnv.R2,
    ctx,
  }, logger);
  await ctx.drainWaitUntil();
}

async function settleTerminal(
  runtimeEnv: Env,
  input: {
    installationId: string;
    requestId: string;
    requestReference: string;
    usage?: { tokens: number; cost: number };
    code: TaxonomyCode;
    idempotencyState: Extract<CreditIdempotencyState, "failed" | "cancelled">;
    manifest: Manifest;
    filteredContext: Record<string, unknown>;
    composed: CanonicalRequest;
    attempts: AttemptInput[];
    periodStart: string;
    entitlement?: EntitlementSnapshot;
    skipCredit?: boolean;
  },
  logger: Logger,
): Promise<void> {
  const usage = input.usage ?? { tokens: 0, cost: 0 };
  if (!input.skipCredit) {
    await creditUsage(
      {
        installationId: input.installationId,
        requestId: input.requestId,
        requestReference: input.requestReference,
        usage,
        partial: getTaxonomyEntry(input.code).consumesQuota !== "Yes",
        idempotencyState: input.idempotencyState,
        entitlement: input.entitlement,
      },
      { DO: runtimeEnv.DO, DB: runtimeEnv.DB },
    );
  }
  await writeSettlementJournal(
    runtimeEnv,
    {
      requestId: input.requestId,
      installationId: input.installationId,
      manifest: input.manifest,
      filteredContext: input.filteredContext,
      composed: input.composed,
      attempts: input.attempts,
      result: placeholderTerminalResult(usage, input.code),
      recordedAt: new Date().toISOString(),
      usage,
      periodStart: input.periodStart,
    },
    logger,
  );
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
    periodStart: string;
    entitlement?: EntitlementSnapshot;
  },
  logger: Logger,
): Promise<void> {
  const usage = ledgerUsageFromProvider(input.result);
  await creditUsage(
    {
      installationId: input.installationId,
      requestId: input.requestId,
      requestReference: input.requestReference,
      usage,
      partial: false,
      entitlement: input.entitlement,
    },
    { DO: runtimeEnv.DO, DB: runtimeEnv.DB },
  );
  await writeSettlementJournal(
    runtimeEnv,
    {
      requestId: input.requestId,
      installationId: input.installationId,
      manifest: input.manifest,
      filteredContext: input.filteredContext,
      composed: input.composed,
      attempts: input.attempts,
      result: input.result,
      recordedAt: input.recordedAt,
      usage,
      periodStart: input.periodStart,
    },
    logger,
  );
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
  if (prior.state === "completed" || prior.state === "admitted") {
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
  acceptContexts: AcceptContextStore,
  scheduleBackground: (promise: Promise<unknown>) => void,
  makeLog: LoggerFactory,
): AdapterEventSourceFactory {
  return (sink, streamContext) => {
    const log = makeLog("worker.ts", {
      trace_id: streamContext.traceId,
      request_reference: streamContext.requestReference,
    });
    const accept = acceptContexts.get(streamContext.requestReference);
    acceptContexts.delete(streamContext.requestReference);
    if (!accept) {
      log.error("event_source_missing_accept_context");
      pushFailedTerminal(
        sink,
        streamContext.requestReference,
        streamContext.traceId,
        "internal_error",
      );
      return;
    }
    if (accept.kind === "idempotent") {
      log.info("event_source_idempotent_replay");
      replayIdempotentTerminal(
        sink,
        streamContext.traceId,
        accept.guard,
        runtimeEnv,
      );
      return;
    }
    log.info("event_source_fresh_start");
    let brokerController: StreamBrokerController | undefined;
    const freshGuard = accept.guard;
    scheduleBackground(
      runFreshEventSource(
        sink,
        streamContext,
        freshGuard,
        runtimeEnv,
        makeLog,
        (controller) => {
          brokerController = controller;
        },
      ).catch((error) => {
        log.error("event_source_fresh_failed", {
          error: error instanceof Error ? error.message : String(error),
        });
        pushFailedTerminal(
          sink,
          streamContext.requestReference,
          streamContext.traceId,
          "internal_error",
        );
      }),
    );
    return {
      disconnect(reason) {
        log.info("event_source_disconnect", { reason });
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
  makeLog: LoggerFactory,
  onBrokerReady: (controller: StreamBrokerController) => void,
): Promise<void> {
  const log = makeLog("worker.ts", {
    trace_id: streamContext.traceId,
    request_reference: streamContext.requestReference,
    request_id: guard.requestId,
  });
  log.info("invocation_start");
  const manifest = guard.manifest;
  const cache = isolateConfigCache;
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
      routingTier: routingTierFromAdmission(admissionAllowFromGuard(guard)),
      requirements: {
        structured_output_required: manifest.Output.mode !== "prose",
        min_context_window: requiredFeatures.contextWindow,
        languages: [requiredFeatures.language],
        latency_class: String(manifest.Routing.latencyClass),
      },
      manifestCostClass: "standard",
      entitlementMaxCostClass: "premium",
      killedProviderIds: guard.killedProviderIds ?? [],
    },
    logger: makeLog("router/index.ts", {
      trace_id: streamContext.traceId,
      request_id: guard.requestId,
    }),
  });
  await persistRoutingDecision(
    guard.requestId,
    routing.routing_decision,
    runtimeEnv.DB,
  );
  log.debug("routing_resolved", {
    provider: routing.routing_decision.chain[0]?.provider_id,
  });

  const pushable = createPushableInvocationEvents();
  const attemptRecords: AttemptRecord[] = [];
  const partialUsage: PartialUsageAccessor = {};
  const invocationSink: InvocationSink = {
    recordAttempt(record) {
      attemptRecords.push(record);
    },
    emitRegenerating() {
      pushable.push({ kind: "regenerating" });
    },
    emitStreamText(text) {
      pushable.push({ kind: "text", text });
    },
    emitTruncation() {
      pushable.push({ kind: "truncation" });
    },
  };

  let brokerTerminal: BrokerTerminalState | undefined;
  let ignoreBrokerSettlement = false;
  let brokerCredit: Promise<unknown> = Promise.resolve();
  const chunkSource = createChunkSourceFromInvocationEvents(
    pushable.iterable,
    () => partialUsage.getPartialUsage?.(),
  );

  const brokerSink: AdapterEventSink = {
    push(event) {
      if (
        ignoreBrokerSettlement &&
        (event.type === "cancelled" ||
          event.type === "completed" ||
          event.type === "failed" ||
          event.type === "context_requested")
      ) {
        return;
      }
      sink.push(event);
    },
  };

  const broker = createStreamBroker({
    traceId: streamContext.traceId,
    requestId: guard.requestId,
    requestReference: streamContext.requestReference,
    eventSink: brokerSink,
    chunkSource,
    heartbeatTicker: createProductionHeartbeatTicker(),
    logger: makeLog("stream/index.ts", {
      trace_id: streamContext.traceId,
      request_id: guard.requestId,
    }),
    creditSink: (input) => {
      if (ignoreBrokerSettlement) {
        return;
      }
      brokerCredit = creditUsage(
        {
          installationId: guard.principal.installationId,
          requestId: input.requestId,
          requestReference: streamContext.requestReference,
          usage: input.usage,
          partial: input.partial,
          idempotencyState: input.idempotencyState,
          entitlement: guard.entitlementSnapshot,
        },
        { DO: runtimeEnv.DO, DB: runtimeEnv.DB },
      );
    },
    journalTerminalSink: (record) => {
      if (ignoreBrokerSettlement) {
        return;
      }
      brokerTerminal = record.state;
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
    guardThresholds: {
      ...PRODUCTION_GUARD_THRESHOLDS,
      systemPromptLeakNeedle: guard.systemPromptLeakNeedle,
      ...(guard.systemPromptLeakNeedles !== undefined
        ? { systemPromptLeakNeedles: guard.systemPromptLeakNeedles }
        : {}),
    },
  });
  onBrokerReady(broker);

  const onAbort = (): void => {
    broker.disconnect("client_close");
  };
  if (streamContext.signal.aborted) {
    onAbort();
  } else {
    streamContext.signal.addEventListener("abort", onAbort, { once: true });
  }

  const brokerRun = broker.run();

  const invokeResult = await runInvocation({
    request: guard.composed,
    routingDecision: routing.routing_decision,
    requestId: guard.requestId,
    idempotencyKey: guard.idempotencyKey,
    portResolver: resolveProviderPort,
    sink: invocationSink,
    partialUsage,
    sleeper: wallClockSleeper,
    signal: streamContext.signal,
    logger: makeLog("invocation/index.ts", {
      trace_id: streamContext.traceId,
      request_id: guard.requestId,
    }),
  });
  // Ignore broker settlement before ending the event stream so a concurrent
  // wasTruncated/guard fail cannot double-credit against the 1.5 failed path.
  if (
    !invokeResult.ok &&
    invokeResult.error.taxonomyCode !== "cancelled" &&
    !streamContext.signal.aborted
  ) {
    ignoreBrokerSettlement = true;
  }
  pushable.end();

  const journalLog = makeLog("journal/index.ts", {
    trace_id: streamContext.traceId,
    request_id: guard.requestId,
  });
  const periodStart = guard.entitlementSnapshot.period_bounds.period_start;
  const terminalBase = {
    installationId: guard.principal.installationId,
    requestId: guard.requestId,
    requestReference: streamContext.requestReference,
    manifest,
    filteredContext: guard.filteredContext,
    composed: guard.composed,
    attempts: attemptRecords.map(buildAttemptInput),
    periodStart,
    entitlement: guard.entitlementSnapshot,
  };

  if (!invokeResult.ok) {
    const code = invokeResult.error.taxonomyCode;
    if (code === "cancelled" || streamContext.signal.aborted) {
      log.info("invocation_cancelled");
      broker.disconnect("client_close");
      await brokerRun;
      await brokerCredit;
      if (brokerTerminal === undefined) {
        await settleTerminal(runtimeEnv, {
          ...terminalBase,
          usage: partialUsage.getPartialUsage?.(),
          code: "cancelled",
          idempotencyState: "cancelled",
        }, journalLog);
        await recordTerminalState(
          guard.requestId,
          "Cancelled",
          undefined,
          new Date().toISOString(),
          runtimeEnv.DB,
          manifest.interactionMode,
        );
      } else {
        await settleTerminal(runtimeEnv, {
          ...terminalBase,
          usage: partialUsage.getPartialUsage?.(),
          code: "cancelled",
          idempotencyState: "cancelled",
          skipCredit: true,
        }, journalLog);
      }
      return;
    }
    const taxonomy = isTaxonomyCode(code) ? code : "provider_unavailable";
    log.error("invocation_failed", { code: taxonomy });
    // Tear down the waiting broker without treating provider failure as cancel.
    ignoreBrokerSettlement = true;
    broker.disconnect("client_close");
    await brokerRun;
    pushFailedTerminal(
      sink,
      streamContext.requestReference,
      streamContext.traceId,
      taxonomy,
    );
    await settleTerminal(runtimeEnv, {
      ...terminalBase,
      attempts: attemptsForFailedSettlement(
        attemptRecords,
        routing.routing_decision,
        taxonomy,
      ),
      usage: partialUsage.getPartialUsage?.(),
      code: taxonomy,
      idempotencyState: "failed",
    }, journalLog);
    await recordTerminalState(
      guard.requestId,
      "Failed",
      taxonomy,
      new Date().toISOString(),
      runtimeEnv.DB,
      manifest.interactionMode,
    );
    return;
  }

  await brokerRun;
  await brokerCredit;

  if (brokerTerminal !== "completed") {
    log.debug("invocation_broker_non_completed", { terminal: brokerTerminal });
    const brokerCode: TaxonomyCode =
      brokerTerminal === "cancelled" ? "cancelled" : "validation_failed";
    await settleTerminal(runtimeEnv, {
      ...terminalBase,
      attempts:
        brokerTerminal === "cancelled"
          ? terminalBase.attempts
          : attemptsForFailedSettlement(
            attemptRecords,
            routing.routing_decision,
            brokerCode,
          ),
      usage: partialUsage.getPartialUsage?.() ??
        ledgerUsageFromProvider(invokeResult.result),
      code: brokerCode,
      idempotencyState:
        brokerTerminal === "cancelled" ? "cancelled" : "failed",
      skipCredit: true,
    }, journalLog);
    return;
  }

  log.info("invocation_completed");
  await settleCompletedRequest(runtimeEnv, {
    ...terminalBase,
    result: invokeResult.result,
    recordedAt: new Date().toISOString(),
  }, journalLog);
}

function createProductionPreAccept(
  runtimeEnv: Env,
  acceptContexts: AcceptContextStore,
  makeLog: LoggerFactory,
): PreAcceptGate {
  const verifier = new EnrolledKeyVerifier();
  const cache = isolateConfigCache;
  const reader = createD1ConfigReader(runtimeEnv.DB, runtimeEnv.R2);
  return async (input) => {
    const log = makeLog("worker.ts", {
      trace_id: input.headers.traceId,
      request_reference: input.requestReference,
    });
    const { composeRequest, promptScaffoldByteLength } = await import(
      "./prompt/composer"
    );
    const { resolvePromptVersion } = await import("./prompt/registry");
    const capabilityId = extractCapabilityId(input.body);
    if (!capabilityId) {
      log.error("pre_accept_missing_capability");
      return { ok: false, code: "internal_error" };
    }
    const promptLog = makeLog("prompt/composer.ts", {
      trace_id: input.headers.traceId,
      request_reference: input.requestReference,
    });
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
        composeRequest: (params) => composeRequest(params, promptLog),
        promptScaffoldByteLength,
        resolvePromptVersion,
        logger: makeLog("pipeline/index.ts", {
          trace_id: input.headers.traceId,
          request_reference: input.requestReference,
        }),
      },
      {
        DB: runtimeEnv.DB,
        DO: runtimeEnv.DO,
        rateLimit: productionRateLimitBindings(runtimeEnv),
      },
    );
    if (!guard.ok) {
      const code = isTaxonomyCode(guard.code) ? guard.code : "internal_error";
      log.info("guard_rejected", { code });
      return {
        ok: false,
        code,
        ...(typeof guard.retryAfter === "number"
          ? { retryAfter: guard.retryAfter }
          : {}),
      };
    }
    if (guard.outcome === "idempotent") {
      log.info("guard_idempotent");
      acceptContexts.set(input.requestReference, {
        kind: "idempotent",
        guard,
      });
      return { ok: true };
    }
    log.info("guard_fresh");
    acceptContexts.set(input.requestReference, { kind: "fresh", guard });
    const degradedNotice = degradedNoticeFromAdmission(
      admissionAllowFromGuard(guard),
    );
    return {
      ok: true,
      ...(degradedNotice ? { degradedNotice: true } : {}),
    };
  };
}

async function handleLivePostRequest(
  request: Request,
  runtimeEnv: Env,
  executionCtx: ExecutionContext,
): Promise<Response> {
  const makeLog = createWorkerLogFactory(runtimeEnv);
  makeLog("worker.ts").info("live_post_request_received");
  // Request-scoped handoff only — never a module-global per-request store (§4.3.10).
  const acceptContexts: AcceptContextStore = new Map();
  const scheduleBackground = (promise: Promise<unknown>) => {
    executionCtx.waitUntil(promise);
  };
  return handleAdapterRequest(request, {
    makeLog,
    preAccept: createProductionPreAccept(runtimeEnv, acceptContexts, makeLog),
    eventSource: createProductionEventSource(
      runtimeEnv,
      acceptContexts,
      scheduleBackground,
      makeLog,
    ),
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
  if (candidate.idempotencyState !== undefined) {
    const allowed: CreditIdempotencyState[] = [
      "failed",
      "cancelled",
      "completed",
    ];
    if (
      !allowed.includes(candidate.idempotencyState as CreditIdempotencyState)
    ) {
      throw new ArgValidationError("invalid_credit_args");
    }
  }
  if (
    candidate.entitlement !== undefined &&
    (candidate.entitlement === null ||
      typeof candidate.entitlement !== "object")
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
  log: Logger,
  kind: string | undefined,
  body: unknown,
  error: unknown,
): void {
  const rpcBody = body as {
    installationId?: unknown;
    requestReference?: unknown;
    jti?: unknown;
  };
  log.error("gateway_object_rpc_failed", {
    kind: kind ?? "unknown",
    error: error instanceof Error ? error.message : String(error),
    installation:
      typeof rpcBody.installationId === "string" ? rpcBody.installationId : "",
    request_reference:
      typeof rpcBody.requestReference === "string"
        ? rpcBody.requestReference
        : "",
    jti: typeof rpcBody.jti === "string" ? rpcBody.jti : "",
  });
}

export class GatewayObject extends DurableObject {
  async fetch(request: Request): Promise<Response> {
    const makeLog = createWorkerLogFactory(this.env as Env);
    const log = makeLog("worker.ts");
    if (request.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      log.error("gateway_object_invalid_json");
      return Response.json({ error: "invalid_json" }, { status: 400 });
    }
    const kind = (body as { kind?: string }).kind;
    log.debug("gateway_object_rpc_received", { kind: kind ?? "unknown" });
    const injectableNow = (body as { now?: unknown }).now;
    const now =
      typeof injectableNow === "number" && Number.isFinite(injectableNow)
        ? injectableNow
        : undefined;
    try {
      const quotaLog = makeLog("quota-do/index.ts", {
        installation_id:
          typeof (body as { installationId?: string }).installationId === "string"
            ? (body as { installationId: string }).installationId
            : undefined,
      });
      if (kind === "admission") {
        assertAdmissionArgs(body);
        const result = await admissionRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body,
          now,
          quotaLog,
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
          quotaLog,
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
          quotaLog,
        );
        return Response.json(result);
      }
      if (kind === "inspect") {
        const result = await inspectRPC(this.ctx.storage, now);
        return Response.json(result);
      }
    } catch (error) {
      if (isArgValidationError(error)) {
        return Response.json({ error: "bad_request" }, { status: 400 });
      }
      logGatewayRpcFailure(log, kind, body, error);
      return Response.json({ error: "internal_error" }, { status: 500 });
    }
    log.error("gateway_object_unknown_kind", { kind: kind ?? "unknown" });
    return Response.json({ error: "unknown_kind" }, { status: 400 });
  }
}

export default {
  async fetch(
    request: Request,
    _bindings: Env,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const runtimeEnv = env as Env;
    const makeLog = createWorkerLogFactory(runtimeEnv);
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      makeLog("worker.ts").debug("health_check");
      return Response.json({
        build: runtimeEnv.BUILD_SHA,
        environment: runtimeEnv.ENVIRONMENT,
      });
    }

    if (url.pathname === "/v1/capabilities" && request.method === "GET") {
      return handleDiscoveryRequest(request, {
        DB: runtimeEnv.DB,
        R2: runtimeEnv.R2,
      }, makeLog("discovery/index.ts"));
    }

    if (url.pathname === "/v1/requests" && request.method === "POST") {
      return handleLivePostRequest(request, runtimeEnv, ctx);
    }

    if (
      isControlRoute(url.pathname) &&
      (request.method === "POST" ||
        (request.method === "GET" && isQuotaInspectRoute(url.pathname)))
    ) {
      // Installation lifecycle, capability deprecate/retire, cohort activate/promote,
      // routing-policy publish/canary/rollback, support lookup, purge, quota inspect.
      const operatorAuth = createSecretOperatorAuth({
        bearerToken: runtimeEnv.OPERATOR_BEARER_TOKEN ?? "",
        operatorId: runtimeEnv.OPERATOR_ID ?? "",
      });
      return dispatchControlRequest(
        request,
        {
          DB: runtimeEnv.DB,
          R2: runtimeEnv.R2,
          DO: runtimeEnv.DO,
        },
        operatorAuth,
        makeLog("control/index.ts"),
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
      const getLog = makeLog("journal/index.ts", { request_reference: reference });

      const auth = await authenticateGetRequest(request, {
        DB: runtimeEnv.DB,
      }, getLog);
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
        getLog.debug("get_request_not_found");
        return new Response(null, { status: 404 });
      }

      getLog.info("get_request_served", { state: result.state });

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

    makeLog("worker.ts").debug("route_not_found", {
      method: request.method,
      pathname: url.pathname,
    });
    return new Response("Not Found", { status: 404 });
  },

  async scheduled(
    controller: ScheduledController,
    runtimeEnv: Env,
    _ctx: ExecutionContext,
  ): Promise<void> {
    const makeLog = createWorkerLogFactory(runtimeEnv);
    const log = makeLog("worker.ts");
    const cron = controller.cron;
    log.info("scheduled_cron_start", { cron });

    // FR-011 — flush in-isolate guard rejection tallies before other jobs.
    await flushRejectionCounters(
      { DB: runtimeEnv.DB },
      makeLog("rate-limit/index.ts"),
    );
    // FR-013 / §15 #3 — reconcile grace admissions once the Quota DO may be reachable.
    await reconcileGraceUsage(
      { DO: runtimeEnv.DO, DB: runtimeEnv.DB },
      undefined,
      makeLog("credit/index.ts"),
    );

    if (cron === "0 3 * * *") {
      log.info("scheduled_retention_purge_start");
      await runRetentionPurge({
        db: runtimeEnv.DB,
        r2: runtimeEnv.R2,
        resolveRetentionClass: createManifestRetentionClassResolver(),
        logger: makeLog("retention/index.ts"),
      });
      log.info("scheduled_retention_purge_complete");
    } else if (cron === "0 4 * * *") {
      log.info("scheduled_rollup_start");
      const rollupLog = makeLog("rollup/index.ts");
      const result = await runRollupAndReconciliation(
        { db: runtimeEnv.DB },
        rollupLog,
      );
      log.info("usage_rollup_reconciliation", {
        rollups_written: result.rollupsWritten,
        missing_attempt_rows: result.report.missingAttemptRows.length,
        missing_usage_credit: result.report.missingUsageCredit.length,
        window: result.report.window,
      });
      log.debug("usage_rollup_reconciliation_detail", { report: result.report });
    }

    log.debug("scheduled_cron_complete", { cron });
  },
};
