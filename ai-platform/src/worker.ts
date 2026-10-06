import { DurableObject, env } from "cloudflare:workers";
import {
  CHANNEL_VERSIONS,
  negotiate,
  validateTokenClaims,
} from "vendor-contracts";
import {
  handleAdapterRequest,
  pushTerminalEvent,
  type AdapterEventSink,
  type AdapterEventSourceFactory,
  type PreAcceptGate,
} from "./adapter";
import {
  createCapabilityRegistry,
  getRegisteredManifest,
  setCapabilityRegistry,
} from "./capability";
import {
  configureIsolateConfigCache,
  createD1ConfigReader,
  ConfigCacheMissError,
  isolateConfigCache,
  loadConfig,
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
import { handleCoverageReadRequest } from "./coverage-read";
import {
  requireAipContractVersion,
  withAipContractVersion,
} from "./vendor/contract-version";
import { clockNowMs, clockNowSeconds } from "./clock";
import { IssuerTokenVerifier } from "./identity";
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
  applyGrantRPC,
  creditRPC,
  ensureCoverageDoTables,
  inspectCoverageRPC,
  inspectRPC,
  openAwaitingTransferRPC,
  readCoverageRPC,
  releaseHeldRPC,
  setTransferPendingRPC,
  transferInRPC,
  transferOutRPC,
  suspendResumeRPC,
  voidForReversalRPC,
  voidGrantRPC,
  releaseRPC,
  settleFallbackRPC,
  shipCoverageOutboxAlarm,
  scheduleOutboxAlarmIfPending,
  type AdmissionRequest,
  type SettleFallbackRequest,
  type ApplyGrantRequest,
  type CreditIdempotencyState,
  type CreditRequest,
  type CoverageShipEnv,
  type EntitlementSnapshot,
  type ReadCoverageRequest,
  type ReleaseRequest,
} from "./quota-do/index";
import { clockNowIso } from "./clock";
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
  noopLogger,
  verbosityFromEnv,
  type Logger,
  type LoggerFactory,
} from "./logger";
import {
  raiseAl11GrantFromOutbox,
  raiseAl12GrantFromOutbox,
  raiseAl17FromOutbox,
  raiseAl19FromOutbox,
  runFiveMinuteCron,
  sendDailyAl18ForHeldBindings,
  type AlertEnv,
} from "./alert/index";

interface Env extends AlertEnv {
  R2: R2Bucket;
  DO: DurableObjectNamespace;
  BUILD_SHA: string;
  ENVIRONMENT: string;
  LOG_VERBOSITY?: string;
  CONFIG_CACHE_TTL_MS?: string;
  ISSUER_ID: string;
  TEST_CLOCK?: string;
  PLATFORM_SIGNING_KEY: string;
  DURATION_SCALE?: string;
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

const bootLog = createWorkerLogFactory(env as Env)("worker.ts");
try {
  setCapabilityRegistry(
    createCapabilityRegistry([
      load(visitSummaryPublished as Record<string, unknown>),
    ]),
  );
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("already installed")) {
    // Test harness may install the registry first with { replace: true }.
  } else {
    bootLog.error("boot_registry_install_failed", { error: message });
    throw error;
  }
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
    ...(guard.band !== undefined ? { band: guard.band } : {}),
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

function termIdFromGuard(guard: GuardFreshSuccess): string | undefined {
  return guard.termAdmission?.termId;
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

/**
 * Miniflare's limiter clears every wall-clock minute
 * (`Date.now() / (period * 1000)`). A burst that crosses that minute
 * never reaches the configured limit. Workers tests pin `TEST_CLOCK=1`
 * and expect one continuous window, so count from the key's first hit
 * for 60s. Production keeps the platform binding.
 */
function stableTestRateLimit(limit: number): RateLimit {
  const buckets = new Map<string, { windowStart: number; count: number }>();
  return {
    async limit(options) {
      const key = options.key;
      const now = Date.now();
      const current = buckets.get(key);
      const fresh =
        current === undefined || now - current.windowStart >= 60_000;
      const count = fresh || current === undefined ? 0 : current.count;
      if (count >= limit) {
        return { success: false };
      }
      buckets.set(key, {
        windowStart: fresh || current === undefined ? now : current.windowStart,
        count: count + 1,
      });
      return { success: true };
    },
  };
}

const testInstallationRateLimit = stableTestRateLimit(600);
const testActorRateLimit = stableTestRateLimit(120);
const testCapabilityRateLimit = stableTestRateLimit(300);

function productionRateLimitBindings(runtimeEnv: Env): RateLimitBindings {
  if (runtimeEnv.TEST_CLOCK === "1") {
    return {
      DB: runtimeEnv.DB,
      RATE_LIMITER_INSTALLATION: testInstallationRateLimit,
      RATE_LIMITER_INSTALLATION_ACTOR: testActorRateLimit,
      RATE_LIMITER_INSTALLATION_CAPABILITY: testCapabilityRateLimit,
    };
  }
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
  return new FakeAdapter(["retryable:provider_unavailable"]);
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

const EMPTY_ROUTING_DECISION: RoutingDecision = {
  policy_id: "",
  policy_version: 0,
  rule_id: "",
  effective_cost_class: "standard",
  cost_class_source: "manifest",
  routing_tier: "standard",
  required_features: {
    structured_output_required: false,
    min_context_window: 0,
    languages: [],
    latency_class: "standard",
  },
  chain: [],
  excluded: [],
};

function placeholderComposedRequest(
  requestReference: string,
  traceId: string,
): CanonicalRequest {
  return {
    parts: [{ role: "user", content: "" }],
    formatDirective: {},
    samplingConstraints: {},
    maxOutputTokens: 1,
    stopConditions: [],
    toolDeclarations: [],
    stream: true,
    deadline: null,
    correlationIds: {
      request_reference: requestReference,
      trace_id: traceId,
    },
  };
}

type PostAcceptInternalErrorInput = {
  requestId: string;
  installationId: string;
  requestReference: string;
  manifest: Manifest;
  filteredContext: Record<string, unknown>;
  composed: CanonicalRequest;
  termId: string;
  entitlement?: EntitlementSnapshot;
  routing?: RoutingDecision;
};

async function settlePostAcceptInternalError(
  runtimeEnv: Env,
  input: PostAcceptInternalErrorInput,
  logger: Logger,
): Promise<void> {
  const code: TaxonomyCode = "internal_error";
  const routing = input.routing ?? EMPTY_ROUTING_DECISION;
  await settleTerminal(
    runtimeEnv,
    {
      installationId: input.installationId,
      requestId: input.requestId,
      requestReference: input.requestReference,
      manifest: input.manifest,
      filteredContext: input.filteredContext,
      composed: input.composed,
      attempts: attemptsForFailedSettlement([], routing, code),
      termId: input.termId,
      entitlement: input.entitlement,
      code,
      idempotencyState: "failed",
    },
    logger,
  );
  await recordTerminalState(
    input.requestId,
    "Failed",
    code,
    new Date().toISOString(),
    runtimeEnv.DB,
    input.manifest.interactionMode,
  );
}

async function settleMissingHandoffInternalError(
  runtimeEnv: Env,
  streamContext: { traceId: string; requestReference: string },
  makeLog: LoggerFactory,
): Promise<void> {
  const log = makeLog("worker.ts", {
    trace_id: streamContext.traceId,
    request_reference: streamContext.requestReference,
  });
  const row = await runtimeEnv.DB.prepare(
    `SELECT request_id, installation_id, capability_id, capability_version,
            trace_id
     FROM ai_request WHERE request_reference = ?`,
  )
    .bind(streamContext.requestReference)
    .first<{
      request_id: string;
      installation_id: string;
      capability_id: string;
      capability_version: string;
      trace_id: string;
    }>();

  if (!row) {
    log.error("missing_handoff_settle_no_row");
    return;
  }

  const manifest = getRegisteredManifest(
    row.capability_id,
    row.capability_version,
  );
  if (manifest === undefined) {
    log.error("missing_handoff_settle_capability_unresolved", {
      code: "capability_unknown",
    });
    await recordTerminalState(
      row.request_id,
      "Failed",
      "internal_error",
      new Date().toISOString(),
      runtimeEnv.DB,
      "single_shot",
    );
    return;
  }

  const mirrorRow = await runtimeEnv.DB.prepare(
    `SELECT term_snapshot FROM coverage_mirror WHERE installation_id = ?`,
  )
    .bind(row.installation_id)
    .first<{ term_snapshot: string }>();
  const termSnapshot = mirrorRow?.term_snapshot
    ? (JSON.parse(mirrorRow.term_snapshot) as {
        ref?: string;
        term_id?: string;
      })
    : undefined;
  const termId = termSnapshot?.ref ?? termSnapshot?.term_id;
  if (!termId) {
    log.error("missing_handoff_settle_term_missing");
    await recordTerminalState(
      row.request_id,
      "Failed",
      "internal_error",
      new Date().toISOString(),
      runtimeEnv.DB,
      "single_shot",
    );
    return;
  }

  const traceId = streamContext.traceId || row.trace_id;
  await settlePostAcceptInternalError(
    runtimeEnv,
    {
      requestId: row.request_id,
      installationId: row.installation_id,
      requestReference: streamContext.requestReference,
      manifest,
      filteredContext: {},
      composed: placeholderComposedRequest(
        streamContext.requestReference,
        traceId,
      ),
      termId,
    },
    log,
  );
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
  termId: string,
): PostResponseInput {
  return {
    requestId,
    installationId,
    termId,
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
  termId: string;
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
    input.termId,
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
    termId: string;
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
        credits: Number(input.manifest.Economics.quotaWeight) || 1,
        idempotencyState: input.idempotencyState,
        ...(input.idempotencyState === "failed"
          ? { terminalErrorCode: input.code }
          : {}),
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
      termId: input.termId,
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
    termId: string;
    reservationId?: string;
    entitlement?: EntitlementSnapshot;
  },
  logger: Logger,
): Promise<void> {
  const usage = ledgerUsageFromProvider(input.result);
  await creditUsage(
    {
      installationId: input.installationId,
      requestId: input.reservationId ?? input.requestId,
      requestReference: input.requestReference,
      usage,
      partial: false,
      credits: Number(input.manifest.Economics.quotaWeight) || 1,
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
      termId: input.termId,
      reservationId: input.reservationId,
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

async function replayIdempotentTerminal(
  sink: AdapterEventSink,
  traceId: string,
  guard: GuardIdempotentSuccess,
  runtimeEnv: Env,
): Promise<void> {
  const prior = guard.priorState;
  const replayTraceId = prior.traceId ?? traceId;
  const streamCtx = {
    traceId: replayTraceId,
    requestReference: prior.requestReference,
    headers: {
      idempotencyKey: guard.idempotencyKey,
      traceId: replayTraceId,
      capabilityVersion: "",
    },
    signal: new AbortController().signal,
  };
  if (prior.state === "completed") {
    const loaded = await getRequest(prior.requestReference, {
      db: runtimeEnv.DB,
      r2: runtimeEnv.R2,
    });
    if (
      loaded.found &&
      loaded.state === "Completed" &&
      "result" in loaded &&
      loaded.result
    ) {
      const text =
        loaded.result.finalContent?.type === "text"
          ? loaded.result.finalContent.text
          : "";
      if (text.length > 0) {
        sink.push({
          type: "text_delta",
          data: { text, sequence: 0, provisional: true },
          trace_id: replayTraceId,
        });
      }
      pushTerminalEvent(sink, streamCtx, "completed", "single_shot", {
        result: {
          finalContent: {
            text,
            authoritative: true,
          },
        },
      });
      return;
    }
    pushTerminalEvent(sink, streamCtx, "completed", "single_shot", {
      result: {
        finalContent: { text: "Prior request completed.", authoritative: true },
      },
    });
    return;
  }
  if (prior.state === "admitted") {
    // In-flight replay: leave the stream open after `accepted` — no fabricated terminal.
    return;
  }
  if (prior.state === "failed") {
    const code =
      prior.terminalErrorCode !== undefined &&
      isTaxonomyCode(prior.terminalErrorCode)
        ? prior.terminalErrorCode
        : "internal_error";
    pushFailedTerminal(sink, guard.requestReference, traceId, code);
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
      scheduleBackground(
        settleMissingHandoffInternalError(
          runtimeEnv,
          streamContext,
          makeLog,
        ).catch((error) => {
          log.error("event_source_missing_handoff_settle_failed", {
            error: error instanceof Error ? error.message : String(error),
          });
        }),
      );
      return;
    }
    if (accept.kind === "idempotent") {
      log.info("event_source_idempotent_replay");
      void replayIdempotentTerminal(
        sink,
        streamContext.traceId,
        accept.guard,
        runtimeEnv,
      ).catch((error) => {
        log.error("event_source_idempotent_replay_failed", {
          error: error instanceof Error ? error.message : String(error),
        });
        pushFailedTerminal(
          sink,
          streamContext.requestReference,
          streamContext.traceId,
          "internal_error",
        );
      });
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
        return settlePostAcceptInternalError(
          runtimeEnv,
          {
            requestId: freshGuard.requestId,
            installationId: freshGuard.principal.installationId,
            requestReference: streamContext.requestReference,
            manifest: freshGuard.manifest,
            filteredContext: freshGuard.filteredContext,
            composed: freshGuard.composed,
            termId: freshGuard.termAdmission?.termId ?? "",
            entitlement: freshGuard.entitlementSnapshot,
          },
          makeLog("journal/index.ts", {
            trace_id: streamContext.traceId,
            request_id: freshGuard.requestId,
          }),
        ).catch((settleError) => {
          log.error("event_source_fresh_settle_failed", {
            error:
              settleError instanceof Error
                ? settleError.message
                : String(settleError),
          });
        });
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
  const preloadedPolicy = await preloadRoutingPolicyForInstallation(
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
    preloadedPolicy,
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
      manifestCostClass:
        guard.termAdmission?.snapshot.max_cost_class ?? "standard",
      entitlementMaxCostClass:
        guard.termAdmission?.snapshot.max_cost_class ?? "standard",
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
          requestId: guard.termAdmission?.reservationId ?? input.requestId,
          requestReference: streamContext.requestReference,
          usage: input.usage,
          partial: input.partial,
          credits: Number(manifest.Economics.quotaWeight) || 1,
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
  const termId = guard.termAdmission?.termId;
  if (!termId) {
    log.error("missing_term_admission_for_settlement");
    return;
  }
  const terminalBase = {
    installationId: guard.principal.installationId,
    requestId: guard.requestId,
    requestReference: streamContext.requestReference,
    manifest,
    filteredContext: guard.filteredContext,
    composed: guard.composed,
    attempts: attemptRecords.map(buildAttemptInput),
    termId,
    reservationId: guard.termAdmission?.reservationId,
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
        // Defensive: client disconnect always journals cancelled via the broker first.
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
    // Drain buffered provisional chunks (truncation prose) before the worker
    // failed terminal. Disconnecting first aborts the broker and drops those
    // chunks; ignoreBrokerSettlement (armed before pushable.end()) already
    // suppresses the broker's own failed event, credit, and journal.
    ignoreBrokerSettlement = true;
    await brokerRun;
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
      skipCredit: brokerTerminal !== undefined,
    }, journalLog);
    await recordTerminalState(
      guard.requestId,
      "Failed",
      taxonomy,
      new Date().toISOString(),
      runtimeEnv.DB,
      manifest.interactionMode,
    );
    pushFailedTerminal(
      sink,
      streamContext.requestReference,
      streamContext.traceId,
      taxonomy,
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
  const verifier = new IssuerTokenVerifier();
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
    const now = await clockNowSeconds(runtimeEnv);
    const nowMs = await clockNowMs(runtimeEnv);
    const guard = await runGuard(
      {
        bodyText: input.bodyText,
        token,
        now,
        verifier,
        verifyContext: {
          audience: "ai-platform",
          clockSkewSeconds: 60,
          now,
          nowMs,
          issuerId: runtimeEnv.ISSUER_ID,
          db: runtimeEnv.DB,
          alertEnv: runtimeEnv,
        },
        capabilityId,
        capabilityVersion: input.headers.capabilityVersion,
        entitlement: {
          capabilityId,
          capabilityVersion: input.headers.capabilityVersion,
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
      // Latent: `cancelled` maps to HTTP 500 at the adapter (no taxonomy status); unreachable for current non-conversational capabilities.
      log.info("guard_rejected", { code });
      return {
        ok: false,
        code,
        ...(typeof guard.retryAfter === "number"
          ? { retryAfter: guard.retryAfter }
          : {}),
        ...(guard.coverageReason !== undefined
          ? { coverageReason: guard.coverageReason }
          : {}),
        ...(code === "context_required" && guard.contextRequired !== undefined
          ? { contextRequired: guard.contextRequired }
          : {}),
      };
    }
    if (guard.outcome === "idempotent") {
      log.info("guard_idempotent");
      const priorReference = guard.priorState.requestReference;
      const priorTraceId =
        guard.priorState.traceId ?? input.headers.traceId;
      acceptContexts.set(priorReference, {
        kind: "idempotent",
        guard,
      });
      return {
        ok: true,
        streamIdentity: {
          requestReference: priorReference,
          traceId: priorTraceId,
        },
      };
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
    typeof candidate.requestReference !== "string"
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

function requestedPlatformDoContractVersion(body: unknown): number | null {
  const raw = (body as { contract_version?: unknown }).contract_version;
  if (raw === undefined) {
    return null;
  }
  if (typeof raw === "number" && Number.isInteger(raw)) {
    return raw;
  }
  return 2;
}

function platformDoContractRefusal(
  negotiated: {
    code: "contract_version_unsupported";
    accepted_versions: number[];
  },
): Record<string, unknown> {
  return {
    contract_version: CHANNEL_VERSIONS.platformDo,
    result: "rejected",
    code: negotiated.code,
    accepted_versions: negotiated.accepted_versions,
  };
}

async function readHarnessAdmissionFault(
  db: D1Database,
): Promise<{ mode: string; hold_until: number | null } | null> {
  try {
    const row = await db
      .prepare(
        "SELECT mode, hold_until FROM harness_admission_fault WHERE id = 'default'",
      )
      .first<{ mode: string; hold_until: number | null }>();
    return row ?? null;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return null;
    }
    throw error;
  }
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
    const negotiated = negotiate(
      CHANNEL_VERSIONS.platformDo,
      requestedPlatformDoContractVersion(body),
    );
    if (!negotiated.ok) {
      return Response.json(platformDoContractRefusal(negotiated));
    }
    const contractVersion = negotiated.version;

    const kind = (body as { kind?: string }).kind;
    log.debug("gateway_object_rpc_received", { kind: kind ?? "unknown" });
    const injectableNow = (body as { now?: unknown }).now;
    const now =
      typeof injectableNow === "number" && Number.isFinite(injectableNow)
        ? injectableNow
        : undefined;
    try {
      await ensureCoverageDoTables(this.ctx.storage, (fn) =>
        this.ctx.blockConcurrencyWhile(fn),
      );
      const quotaLog = makeLog("quota-do/index.ts", {
        installation_id:
          typeof (body as { installationId?: string }).installationId === "string"
            ? (body as { installationId: string }).installationId
            : undefined,
      });
      if (kind === "admission") {
        assertAdmissionArgs(body);
        const runtimeEnv = this.env as Env;
        const admissionNowIso =
          typeof (body as { nowIso?: string }).nowIso === "string"
            ? (body as { nowIso: string }).nowIso
            : await clockNowIso(runtimeEnv);
        const durationScale =
          runtimeEnv.DURATION_SCALE === "staging" ? "staging" : undefined;
        let harnessFault: { mode: string; hold_until: number | null } | null =
          null;
        if (runtimeEnv.TEST_CLOCK === "1" && runtimeEnv.DB !== undefined) {
          harnessFault = await readHarnessAdmissionFault(runtimeEnv.DB);
        }
        if (harnessFault?.mode === "throw") {
          throw new Error("harness_admission_fault_throw");
        }
        const result = await admissionRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          {
            ...(body as AdmissionRequest),
            nowIso: admissionNowIso,
            durationScale,
          },
          now,
          quotaLog,
        );
        if (
          harnessFault?.mode === "hold" &&
          harnessFault.hold_until !== null &&
          Number.isFinite(harnessFault.hold_until)
        ) {
          const holdUntil = harnessFault.hold_until;
          while ((await clockNowMs(runtimeEnv)) < holdUntil) {
            await new Promise<void>((resolve) => {
              setTimeout(resolve, 0);
            });
          }
        }
        await scheduleOutboxAlarmIfPending(
          this.ctx,
          this.ctx.storage,
          admissionNowIso,
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "settleFallback") {
        const settleBody = body as SettleFallbackRequest;
        if (
          typeof settleBody.installationId !== "string" ||
          typeof settleBody.request_id !== "string" ||
          typeof settleBody.term_id !== "string" ||
          typeof settleBody.weight !== "number"
        ) {
          return Response.json({ error: "invalid_settle_fallback_args" }, {
            status: 400,
          });
        }
        const result = await settleFallbackRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          settleBody,
        );
        return Response.json({ ...result, contract_version: contractVersion });
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
        return Response.json({ ...result, contract_version: contractVersion });
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
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "inspect") {
        const result = await inspectRPC(this.ctx.storage, now);
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "apply_grant") {
        const applyBody = body as Omit<ApplyGrantRequest, "db">;
        const runtimeEnv = this.env as Env;
        const result = await applyGrantRPC(
          this.ctx,
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          {
            ...applyBody,
            platformSigningKeyJson:
              applyBody.platformSigningKeyJson ?? runtimeEnv.PLATFORM_SIGNING_KEY,
            db: runtimeEnv.DB,
          },
          quotaLog,
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "read_coverage") {
        const result = await readCoverageRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as ReadCoverageRequest,
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "suspend" || kind === "resume") {
        const result = await suspendResumeRPC(
          this.ctx,
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as Parameters<typeof suspendResumeRPC>[3],
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "inspect_coverage") {
        const result = await inspectCoverageRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as Parameters<typeof inspectCoverageRPC>[2],
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "void_for_reversal") {
        const result = await voidForReversalRPC(
          this.ctx,
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as Parameters<typeof voidForReversalRPC>[3],
          quotaLog,
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "release_held") {
        const result = await releaseHeldRPC(
          this.ctx,
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as Parameters<typeof releaseHeldRPC>[3],
          quotaLog,
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "void_grant") {
        const result = await voidGrantRPC(
          this.ctx,
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as Parameters<typeof voidGrantRPC>[3],
          quotaLog,
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "open_awaiting_transfer") {
        const result = await openAwaitingTransferRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as Parameters<typeof openAwaitingTransferRPC>[2],
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "transfer_out") {
        const result = await transferOutRPC(
          this.ctx,
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as Parameters<typeof transferOutRPC>[3],
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "transfer_in") {
        const result = await transferInRPC(
          this.ctx,
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as Parameters<typeof transferInRPC>[3],
        );
        return Response.json({ ...result, contract_version: contractVersion });
      }
      if (kind === "set_transfer_pending") {
        const result = await setTransferPendingRPC(
          this.ctx.storage,
          (fn) => this.ctx.blockConcurrencyWhile(fn),
          body as Parameters<typeof setTransferPendingRPC>[2],
        );
        return Response.json({ ...result, contract_version: contractVersion });
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

  async alarm(): Promise<void> {
    const runtimeEnv = this.env as Env;
    const makeLog = createWorkerLogFactory(runtimeEnv);
    const log = makeLog("quota-do/index.ts");
    const installationId =
      typeof (this.ctx.id as { toString?: () => string }).toString === "function"
        ? this.ctx.id.toString()
        : "";
    const nowIso = await clockNowIso(runtimeEnv);
    const durationScale =
      runtimeEnv.DURATION_SCALE === "staging" ? "staging" : undefined;
    const shippedAlerts = await shipCoverageOutboxAlarm(
      this.ctx,
      this.ctx.storage,
      (fn) => this.ctx.blockConcurrencyWhile(fn),
      runtimeEnv as CoverageShipEnv,
      installationId,
      nowIso,
      log,
      durationScale,
    );
    for (const alert of shippedAlerts) {
      if (alert.code === "AL-11") {
        await raiseAl11GrantFromOutbox(
          runtimeEnv,
          alert.alert_key,
          alert.body,
        );
      } else if (alert.code === "AL-12") {
        await raiseAl12GrantFromOutbox(
          runtimeEnv,
          alert.alert_key,
          alert.body,
        );
      } else if (alert.code === "AL-19") {
        await raiseAl19FromOutbox(runtimeEnv, alert.alert_key, alert.body);
      } else if (alert.code === "AL-17") {
        await raiseAl17FromOutbox(runtimeEnv, alert.alert_key, alert.body);
      }
    }
  }
}

const AIP_CONTRACT_VERSION_HEADER = "Aip-Contract-Version";
const FEED_CONSUMER = "backend-feed";

function parseRequestedFeedVersion(request: Request): number | null {
  const raw = request.headers.get(AIP_CONTRACT_VERSION_HEADER);
  if (raw === null) {
    return null;
  }
  if (!/^(0|[1-9][0-9]*)$/.test(raw)) {
    return Number.MIN_SAFE_INTEGER;
  }
  return Number(raw);
}

function base64UrlDecode(segment: string): Uint8Array | null {
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    return null;
  }
}

function parseJwtKid(token: string): string | null {
  const segment = token.split(".")[0];
  if (!segment) {
    return null;
  }
  const headerBytes = base64UrlDecode(segment);
  if (headerBytes === null) {
    return null;
  }
  try {
    const header = JSON.parse(new TextDecoder().decode(headerBytes)) as {
      kid?: unknown;
    };
    return typeof header.kid === "string" && header.kid.length > 0
      ? header.kid
      : null;
  } catch {
    return null;
  }
}

async function importIssuerPublicKey(
  keyRow: Record<string, unknown>,
): Promise<CryptoKey | null> {
  if (typeof keyRow.public_key !== "string") {
    return null;
  }
  const rawBytes = base64UrlDecode(keyRow.public_key);
  if (rawBytes === null) {
    return null;
  }
  try {
    return await crypto.subtle.importKey(
      "raw",
      rawBytes,
      { name: "Ed25519" },
      false,
      ["verify"],
    );
  } catch {
    return null;
  }
}

function issuerKeyUsable(
  keyRow: Record<string, unknown>,
  nowSeconds: number,
): boolean {
  const status = keyRow.status;
  if (status === "revoked") {
    return false;
  }
  if (status !== "active" && status !== "retiring") {
    return false;
  }
  if (typeof keyRow.not_before === "string") {
    const notBeforeMs = Date.parse(keyRow.not_before);
    if (
      !Number.isNaN(notBeforeMs) &&
      nowSeconds < Math.floor(notBeforeMs / 1000)
    ) {
      return false;
    }
  }
  if (typeof keyRow.not_after === "string") {
    const notAfterMs = Date.parse(keyRow.not_after);
    if (
      !Number.isNaN(notAfterMs) &&
      nowSeconds >= Math.floor(notAfterMs / 1000)
    ) {
      return false;
    }
  }
  return true;
}

function feedUnauthorizedResponse(): Response {
  return new Response(null, { status: 401 });
}

async function verifyFeedBearerToken(
  request: Request,
  runtimeEnv: Env,
): Promise<{ ok: true; token: string } | { ok: false; response: Response }> {
  const header = request.headers.get("Authorization");
  if (header === null || !header.startsWith("Bearer ")) {
    return { ok: false, response: feedUnauthorizedResponse() };
  }
  const token = header.slice("Bearer ".length).trim();
  if (token.length === 0) {
    return { ok: false, response: feedUnauthorizedResponse() };
  }

  const kid = parseJwtKid(token);
  if (kid === null) {
    return { ok: false, response: feedUnauthorizedResponse() };
  }

  const reader = createD1ConfigReader(runtimeEnv.DB, runtimeEnv.R2);
  const nowMs = await clockNowMs(runtimeEnv);
  const nowSeconds = Math.floor(nowMs / 1000);
  let keyRow: Record<string, unknown>;
  try {
    keyRow = await loadConfig(
      isolateConfigCache,
      reader,
      "issuer_keys",
      kid,
      noopLogger,
      nowMs,
    );
  } catch (error) {
    if (error instanceof ConfigCacheMissError) {
      return { ok: false, response: feedUnauthorizedResponse() };
    }
    throw error;
  }

  if (!issuerKeyUsable(keyRow, nowSeconds)) {
    return { ok: false, response: feedUnauthorizedResponse() };
  }

  const publicKey = await importIssuerPublicKey(keyRow);
  if (publicKey === null) {
    return { ok: false, response: feedUnauthorizedResponse() };
  }

  const claimsResult = await validateTokenClaims({
    jwt: token,
    audience: "ai-platform-feed",
    issuerId: runtimeEnv.ISSUER_ID,
    publicKey,
    kid,
  });
  if (!claimsResult.ok) {
    return { ok: false, response: feedUnauthorizedResponse() };
  }

  return { ok: true, token };
}

async function handleFeedCoverageRequest(
  request: Request,
  runtimeEnv: Env,
  feedVersion: number,
): Promise<Response> {
  const url = new URL(request.url);
  const afterRaw = url.searchParams.get("after");
  const after =
    afterRaw === null || afterRaw === ""
      ? 0
      : Number.isInteger(Number(afterRaw))
        ? Number(afterRaw)
        : 0;

  const limitRaw = url.searchParams.get("limit");
  const parsedLimit =
    limitRaw === null || limitRaw === "" ? null : Number(limitRaw);
  const limit =
    parsedLimit === null ||
    !Number.isInteger(parsedLimit) ||
    parsedLimit < 1 ||
    parsedLimit > 200
      ? 200
      : parsedLimit;

  const auth = await verifyFeedBearerToken(request, runtimeEnv);
  if (!auth.ok) {
    return auth.response;
  }

  const pageRows = await runtimeEnv.DB.prepare(
    `SELECT event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq,
            kind, at, snapshot
     FROM coverage_event
     WHERE feed_seq > ?
     ORDER BY feed_seq ASC
     LIMIT ?`,
  )
    .bind(after, limit)
    .all<{
      event_id: string;
      feed_seq: number;
      org_id: string;
      installation_id: string;
      binding_epoch: number;
      clinic_seq: number;
      kind: string;
      at: string;
      snapshot: string;
    }>();

  const events = (pageRows.results ?? []).map((row) => ({
    event_id: row.event_id,
    feed_seq: row.feed_seq,
    org_id: row.org_id,
    installation_id: row.installation_id,
    binding_epoch: row.binding_epoch,
    clinic_seq: row.clinic_seq,
    kind: row.kind,
    at: row.at,
    snapshot: JSON.parse(row.snapshot) as Record<string, unknown>,
  }));

  const nextAfter =
    events.length > 0 ? events[events.length - 1]!.feed_seq : after;

  const moreRow = await runtimeEnv.DB.prepare(
    `SELECT feed_seq FROM coverage_event WHERE feed_seq > ? LIMIT 1`,
  )
    .bind(nextAfter)
    .first<{ feed_seq: number }>();

  const pullAt = await clockNowIso(runtimeEnv);
  await runtimeEnv.DB.prepare(
    `INSERT INTO feed_consumer (consumer, last_pull_at, last_cursor)
     VALUES (?, ?, ?)
     ON CONFLICT(consumer) DO UPDATE SET
       last_pull_at = excluded.last_pull_at,
       last_cursor = excluded.last_cursor`,
  )
    .bind(FEED_CONSUMER, pullAt, nextAfter)
    .run();

  return withAipContractVersion(
    Response.json({
      contract_version: feedVersion,
      after,
      events,
      next_after: nextAfter,
      has_more: moreRow !== null,
    }),
    feedVersion,
  );
}

export { VendorEntrypoint } from "./vendor/entrypoint";

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
      const contractVersion = requireAipContractVersion(request);
      if (!contractVersion.ok) {
        return contractVersion.response;
      }
      const discoveryResponse = await handleDiscoveryRequest(
        request,
        runtimeEnv,
        makeLog("discovery/index.ts"),
      );
      return withAipContractVersion(
        discoveryResponse,
        contractVersion.version,
      );
    }

    if (url.pathname === "/v1/feed/coverage" && request.method === "GET") {
      const requestedFeedVersion = parseRequestedFeedVersion(request);
      const feedNegotiated = negotiate(
        CHANNEL_VERSIONS.platformFeed,
        requestedFeedVersion,
      );
      if (!feedNegotiated.ok) {
        return Response.json(
          {
            code: feedNegotiated.code,
            accepted_versions: feedNegotiated.accepted_versions,
          },
          { status: 400 },
        );
      }
      return handleFeedCoverageRequest(
        request,
        runtimeEnv,
        feedNegotiated.version,
      );
    }

    if (url.pathname === "/v1/requests" && request.method === "POST") {
      const contractVersion = requireAipContractVersion(request);
      if (!contractVersion.ok) {
        return contractVersion.response;
      }
      const liveResponse = await handleLivePostRequest(
        request,
        runtimeEnv,
        ctx,
      );
      return withAipContractVersion(liveResponse, contractVersion.version);
    }

    if (
      request.method === "GET" &&
      url.pathname.startsWith("/v1/requests/")
    ) {
      const reference = url.pathname.slice("/v1/requests/".length);
      if (!reference) {
        return new Response(null, { status: 404 });
      }
      const contractVersion = requireAipContractVersion(request);
      if (!contractVersion.ok) {
        return contractVersion.response;
      }
      const echoAipContractVersion = (response: Response) =>
        withAipContractVersion(response, contractVersion.version);
      const getLog = makeLog("journal/index.ts", { request_reference: reference });

      const auth = await authenticateGetRequest(request, runtimeEnv, getLog);
      if (!auth.ok) {
        // Prefer 401 for missing/invalid token; suspended maps to taxonomy HTTP status.
        const status = liveHttpStatusForCode(auth.code) ?? 401;
        return echoAipContractVersion(
          Response.json(getRequestAuthErrorBody(auth.code), { status }),
        );
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
        return echoAipContractVersion(new Response(null, { status: 404 }));
      }

      getLog.info("get_request_served", { state: result.state });

      if (result.state === "Completed") {
        if ("result" in result) {
          return echoAipContractVersion(
            Response.json({
              state: "Completed",
              result: result.result,
            }),
          );
        }
        return echoAipContractVersion(Response.json({ state: "Completed" }));
      }

      if ("pending" in result && result.pending) {
        return echoAipContractVersion(
          Response.json({ state: result.state, pending: true }),
        );
      }

      if (result.state === "Failed") {
        return echoAipContractVersion(
          Response.json({
            state: "Failed",
            terminal_error_code: result.terminalErrorCode,
          }),
        );
      }

      if (result.state === "AwaitingContext") {
        return echoAipContractVersion(
          Response.json({ state: "AwaitingContext" }),
        );
      }

      return echoAipContractVersion(Response.json({ state: "Cancelled" }));
    }

    if (url.pathname === "/v1/coverage" && request.method === "GET") {
      const contractVersion = requireAipContractVersion(request);
      if (!contractVersion.ok) {
        return contractVersion.response;
      }
      const coverageResponse = await handleCoverageReadRequest(
        request,
        runtimeEnv,
        makeLog("coverage-read/index.ts"),
      );
      return withAipContractVersion(
        coverageResponse,
        contractVersion.version,
      );
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
    try {
      await flushRejectionCounters(
        { DB: runtimeEnv.DB },
        makeLog("rate-limit/index.ts"),
      );
    } catch (error) {
      log.error("scheduled_flush_failed", {
        error: error instanceof Error ? error.message : String(error),
      });
    }
    if (cron === "0 3 * * *") {
      log.info("scheduled_retention_purge_start");
      try {
        await runRetentionPurge({
          db: runtimeEnv.DB,
          r2: runtimeEnv.R2,
          resolveRetentionClass: createManifestRetentionClassResolver(),
          logger: makeLog("retention/index.ts"),
        });
        log.info("scheduled_retention_purge_complete");
      } catch (error) {
        log.error("scheduled_retention_purge_failed", {
          error: error instanceof Error ? error.message : String(error),
        });
      }
      try {
        await sendDailyAl18ForHeldBindings(runtimeEnv);
      } catch (error) {
        log.error("scheduled_al18_held_failed", {
          error: error instanceof Error ? error.message : String(error),
        });
      }
    } else if (cron === "0 4 * * *") {
      log.info("scheduled_rollup_start");
      const rollupLog = makeLog("rollup/index.ts");
      try {
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
      } catch (error) {
        log.error("scheduled_rollup_failed", {
          error: error instanceof Error ? error.message : String(error),
        });
      }
    } else if (cron === "*/5 * * * *") {
      log.info("scheduled_five_minute_start");
      try {
        await reconcileGraceUsage(
          { DO: runtimeEnv.DO, DB: runtimeEnv.DB },
          undefined,
          makeLog("credit/index.ts"),
        );
      } catch (error) {
        log.error("scheduled_reconcile_failed", {
          error: error instanceof Error ? error.message : String(error),
        });
      }
      await runFiveMinuteCron(runtimeEnv);
      log.info("scheduled_five_minute_complete");
    }

    log.debug("scheduled_cron_complete", { cron });
  },
};
