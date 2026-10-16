import {
  assertExactlyOneTerminal,
  type CanonicalError,
  type CanonicalRequest,
  type CanonicalResult,
  type CanonicalStreamChunk,
  type TimingBreakdown,
} from "../contracts/canonical";
import { getTaxonomyEntry, type TaxonomyCode } from "../errors";
import { setRetryabilityFromClassification } from "./classify";
import type {
  ProviderInvokeOptions,
  ProviderInvokeResult,
  ProviderPort,
} from "./port";
import { readSseDataPayloads, readUtf8Body } from "./readable-body";
import { withRawBody } from "./raw-body";

export const DEEPSEEK_API_KEY_BINDING = "DEEPSEEK_API_KEY";

const DEEPSEEK_API_URL = "https://api.deepseek.com/chat/completions";
/** Default pin — must match platform-default routing policy `model_id` for deepseek. */
export const DEEPSEEK_DEFAULT_MODEL = "deepseek-v4-flash";
const PROVIDER_ID = "deepseek";

/**
 * Provider response body size limit (bytes). Mirrors ingress
 * `INGRESS_BODY_SIZE_LIMIT` (1 MiB) so a hostile/malfunctioning endpoint
 * cannot exhaust isolate memory via an unbounded buffered body.
 */
export const PROVIDER_RESPONSE_BODY_SIZE_LIMIT = 1_048_576;

export type DeepSeekTransportResponse = {
  status: number;
  headers: Record<string, string>;
  body: string | ReadableStream<Uint8Array>;
};

export type DeepSeekTransportRequest = {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
  signal?: AbortSignal;
};

export type DeepSeekTransport = {
  fetch(
    url: string,
    init: DeepSeekTransportRequest,
  ): DeepSeekTransportResponse | Promise<DeepSeekTransportResponse>;
};

export type SecretStorePort = {
  getSecret(name: string): string | undefined;
};

export type DeepSeekAdapterOptions = {
  transport: DeepSeekTransport;
  secretStore: SecretStorePort;
  timeoutMs?: number;
  /** Pinned model id sent on the wire; defaults to {@link DEEPSEEK_DEFAULT_MODEL}. */
  modelId?: string;
};

type DeepSeekWireRole = "system" | "user" | "assistant" | "tool";

type DeepSeekWireRequest = {
  model: string;
  messages: Array<{ role: DeepSeekWireRole; content: string }>;
  temperature?: number;
  max_tokens?: number;
  stop?: string[];
  stream?: boolean;
  stream_options?: { include_usage: boolean };
  response_format?: { type: string };
};

type DeepSeekUsage = {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  prompt_cache_hit_tokens?: number;
};

type DeepSeekChoice = {
  message?: { content?: string };
  delta?: { content?: string };
  finish_reason?: string | null;
};

type DeepSeekResponse = {
  id?: string;
  choices?: DeepSeekChoice[];
  usage?: DeepSeekUsage;
  error?: {
    message?: string;
    type?: string;
    code?: string;
  };
};

function consumesBudget(code: TaxonomyCode): boolean {
  const { consumesQuota } = getTaxonomyEntry(code);
  return consumesQuota !== "No";
}

function createCanonicalError(
  code: TaxonomyCode,
  nativeCode: string,
  nativeMessage: string,
  consumedBudgetOverride?: boolean,
  retryAfterMs?: number,
): CanonicalError {
  return setRetryabilityFromClassification({
    taxonomyCode: code,
    retryability: false,
    providerNative: {
      code: nativeCode,
      message: nativeMessage,
    },
    consumedBudget:
      consumedBudgetOverride !== undefined
        ? consumedBudgetOverride
        : consumesBudget(code),
    ...(retryAfterMs !== undefined ? { retryAfterMs } : {}),
  });
}

function headerValue(
  headers: Record<string, string>,
  name: string,
): string | undefined {
  const want = name.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === want) {
      return value;
    }
  }
  return undefined;
}

/**
 * Parse HTTP `Retry-After` as either delta-seconds or HTTP-date.
 * Returns milliseconds remaining, or undefined when absent/unparseable.
 */
function parseRetryAfterMs(
  headers: Record<string, string>,
): number | undefined {
  const raw = headerValue(headers, "retry-after");
  if (raw === undefined) {
    return undefined;
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  if (/^\d+$/.test(trimmed)) {
    return Number(trimmed) * 1000;
  }
  const whenMs = Date.parse(trimmed);
  if (Number.isNaN(whenMs)) {
    return undefined;
  }
  return Math.max(0, whenMs - Date.now());
}

function utf8ByteLength(text: string): number {
  return new TextEncoder().encode(text).byteLength;
}

function isDeclaredBodyOverLimit(headers: Record<string, string>): boolean {
  const contentLength = headerValue(headers, "content-length");
  if (contentLength === undefined) {
    return false;
  }
  const declared = Number(contentLength);
  return (
    Number.isFinite(declared) && declared > PROVIDER_RESPONSE_BODY_SIZE_LIMIT
  );
}

function isStringBodyOverLimit(body: string): boolean {
  return utf8ByteLength(body) > PROVIDER_RESPONSE_BODY_SIZE_LIMIT;
}

function resolveTimeoutMs(
  request: CanonicalRequest,
  options: DeepSeekAdapterOptions,
): number {
  const deadline =
    typeof request.deadline === "number" ? request.deadline : undefined;
  if (options.timeoutMs !== undefined && deadline !== undefined) {
    return Math.min(options.timeoutMs, deadline);
  }
  return options.timeoutMs ?? deadline ?? 30_000;
}

function mapRoleToDeepSeek(role: string): DeepSeekWireRole {
  if (role === "system") {
    return "system";
  }
  if (role === "assistant") {
    return "assistant";
  }
  return "user";
}

function mapCanonicalToWire(
  request: CanonicalRequest,
  modelId: string,
): DeepSeekWireRequest {
  const sampling = request.samplingConstraints;
  const outputFormat = request.formatDirective;
  const stopConditions = request.stopConditions;

  const wire: DeepSeekWireRequest = {
    model: modelId,
    messages: request.parts.map((part) => ({
      role: mapRoleToDeepSeek(part.role),
      content: part.content,
    })),
    stream: Boolean(request.stream),
  };

  if (wire.stream) {
    wire.stream_options = { include_usage: true };
  }
  if (typeof sampling?.temperature === "number") {
    wire.temperature = sampling.temperature;
  }
  if (typeof request.maxOutputTokens === "number") {
    wire.max_tokens = request.maxOutputTokens;
  }
  if (Array.isArray(stopConditions) && stopConditions.length > 0) {
    wire.stop = [...stopConditions];
  }
  if (outputFormat?.type === "json") {
    wire.response_format = { type: "json_object" };
  }

  return wire;
}

function mapUsage(
  usage: DeepSeekUsage | undefined,
): CanonicalResult["usage"] {
  return {
    input: usage?.prompt_tokens ?? 0,
    output: usage?.completion_tokens ?? 0,
    cached: usage?.prompt_cache_hit_tokens ?? 0,
  };
}

function mapFinishReason(
  finishReason: string | null | undefined,
): CanonicalResult["finishReason"] {
  if (finishReason === "length") {
    return "length";
  }
  return "stop";
}

function buildTiming(providerMs: number): TimingBreakdown {
  return {
    queue_ms: 0,
    provider_ms: providerMs,
    total_ms: providerMs,
  };
}

function buildResult(
  response: DeepSeekResponse,
  content: string,
  finishReason: string | null | undefined,
  providerMs: number,
  modelId: string,
): CanonicalResult {
  return {
    finalContent: { type: "text", text: content },
    usage: mapUsage(response.usage),
    providerModel: {
      provider: PROVIDER_ID,
      model: modelId,
    },
    finishReason: mapFinishReason(finishReason),
    providerRequestId: response.id ?? "deepseek-unknown",
    timing: buildTiming(providerMs),
  };
}

function isContentFiltered(body: DeepSeekResponse): boolean {
  const message = body.error?.message?.toLowerCase() ?? "";
  const type = body.error?.type?.toLowerCase() ?? "";
  const code = body.error?.code?.toLowerCase() ?? "";
  return (
    type.includes("content_filter") ||
    code.includes("content_filter") ||
    message.includes("content policy") ||
    message.includes("content filter")
  );
}

function classifyHttpFailure(
  status: number,
  body: DeepSeekResponse,
): TaxonomyCode {
  if (status === 401 || status === 403) {
    return "provider_rejected";
  }
  if (status === 429) {
    return "rate_limited";
  }
  if (status >= 500) {
    return "internal_error";
  }
  if (isContentFiltered(body)) {
    return "provider_rejected";
  }
  return "provider_rejected";
}

function classifyProviderErrorFrame(body: DeepSeekResponse): TaxonomyCode {
  if (isContentFiltered(body)) {
    return "provider_rejected";
  }
  const type = (body.error?.type ?? "").toLowerCase();
  const code = (body.error?.code ?? "").toLowerCase();
  // Server-side first — structured type/code tokens only.
  if (
    type.includes("server") ||
    code.includes("server") ||
    type.includes("insufficient_system_resource") ||
    code.includes("insufficient_system_resource")
  ) {
    return "internal_error";
  }
  if (type.includes("rate_limit") || code.includes("rate_limit")) {
    return "rate_limited";
  }
  return "provider_rejected";
}

function normalizeStreamChunks(
  events: DeepSeekResponse[],
): CanonicalStreamChunk[] {
  const chunks: CanonicalStreamChunk[] = [];
  let sequence = 0;
  let usage: DeepSeekUsage | undefined;
  let sawUsage = false;

  for (const event of events) {
    if (event.usage) {
      usage = event.usage;
      sawUsage = true;
    }
    const choice = event.choices?.[0];
    const delta = choice?.delta?.content;
    if (typeof delta === "string" && delta.length > 0) {
      chunks.push({
        sequenceNumber: sequence,
        kind: "text_delta",
        payload: { text: delta },
        terminal: false,
      });
      sequence += 1;
    }
  }

  if (sawUsage) {
    chunks.push({
      sequenceNumber: sequence,
      kind: "usage",
      payload: mapUsage(usage),
      terminal: false,
    });
    sequence += 1;
  } else {
    chunks.push({
      sequenceNumber: sequence,
      kind: "provider_note",
      payload: { note: "usage_absent" },
      terminal: false,
    });
    sequence += 1;
  }

  chunks.push({
    sequenceNumber: sequence,
    kind: "text_delta",
    payload: { text: "" },
    terminal: true,
  });

  assertExactlyOneTerminal(chunks);
  return chunks;
}

function minimalTerminalChunks(
  text: string,
  usageAbsent: boolean,
): readonly CanonicalStreamChunk[] {
  const chunks: CanonicalStreamChunk[] = [];
  let sequence = 0;

  if (usageAbsent) {
    chunks.push({
      sequenceNumber: sequence,
      kind: "provider_note",
      payload: { note: "usage_absent" },
      terminal: false,
    });
    sequence += 1;
  }

  chunks.push({
    sequenceNumber: sequence,
    kind: "text_delta",
    payload: { text },
    terminal: true,
  });

  assertExactlyOneTerminal(chunks);
  return chunks;
}

function createTimeoutOutcome(): ProviderInvokeResult {
  return {
    kind: "error",
    error: createCanonicalError(
      "timeout",
      "deadline_exceeded",
      "DeepSeek request exceeded adapter deadline",
    ),
  };
}

function createCancelledOutcome(): ProviderInvokeResult {
  return {
    kind: "error",
    error: createCanonicalError(
      "cancelled",
      "aborted",
      "DeepSeek request aborted by caller signal",
    ),
  };
}

function finishReasonErrorOutcome(
  finishReason: string,
): ProviderInvokeResult | null {
  if (finishReason === "content_filter") {
    return {
      kind: "error",
      error: createCanonicalError(
        "provider_rejected",
        "content_filter",
        "Content filtered by provider",
      ),
    };
  }
  if (finishReason === "insufficient_system_resource") {
    return {
      kind: "error",
      error: createCanonicalError(
        "internal_error",
        "insufficient_system_resource",
        "Provider lacked system resources to complete the request",
      ),
    };
  }
  return null;
}

type AbortGuard = {
  signal: AbortSignal;
  cleanup: () => void;
  wasTimeout: () => boolean;
};

function createAbortGuard(
  timeoutMs: number,
  callerSignal?: AbortSignal,
): AbortGuard {
  const controller = new AbortController();
  let timedOut = false;

  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);

  const onCallerAbort = (): void => {
    controller.abort();
  };

  if (callerSignal) {
    if (callerSignal.aborted) {
      controller.abort();
    } else {
      callerSignal.addEventListener("abort", onCallerAbort, { once: true });
    }
  }

  return {
    signal: controller.signal,
    wasTimeout: () => timedOut,
    cleanup: () => {
      clearTimeout(timer);
      callerSignal?.removeEventListener("abort", onCallerAbort);
    },
  };
}

async function awaitTransportResponse(
  fetchResult: DeepSeekTransportResponse | Promise<DeepSeekTransportResponse>,
  guard: AbortGuard,
): Promise<DeepSeekTransportResponse | null> {
  if (guard.signal.aborted) {
    return null;
  }

  const abortPromise = new Promise<null>((resolve) => {
    guard.signal.addEventListener("abort", () => resolve(null), {
      once: true,
    });
  });

  return Promise.race([Promise.resolve(fetchResult), abortPromise]);
}

export class DeepSeekAdapter implements ProviderPort {
  private readonly transport: DeepSeekTransport;
  private readonly secretStore: SecretStorePort;
  private readonly defaultTimeoutMs?: number;
  private readonly modelId: string;

  constructor(options: DeepSeekAdapterOptions) {
    this.transport = options.transport;
    this.secretStore = options.secretStore;
    this.defaultTimeoutMs = options.timeoutMs;
    this.modelId = options.modelId ?? DEEPSEEK_DEFAULT_MODEL;
  }

  async invoke(
    request: CanonicalRequest,
    options?: ProviderInvokeOptions,
  ): Promise<ProviderInvokeResult> {
    const timeoutMs = resolveTimeoutMs(request, {
      transport: this.transport,
      secretStore: this.secretStore,
      timeoutMs: this.defaultTimeoutMs,
    });

    const apiKey = this.secretStore.getSecret(DEEPSEEK_API_KEY_BINDING);
    if (!apiKey) {
      return {
        kind: "error",
        error: createCanonicalError(
          "provider_rejected",
          "missing_api_key",
          "DeepSeek API key not found in secret store",
          false,
        ),
      };
    }

    const wireBody = mapCanonicalToWire(request, this.modelId);
    const guard = createAbortGuard(timeoutMs, options?.signal);
    const fetchInit: DeepSeekTransportRequest = {
      url: DEEPSEEK_API_URL,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(wireBody),
      signal: guard.signal,
    };

    const startedAt = Date.now();
    try {
      const fetchResult = this.transport.fetch(DEEPSEEK_API_URL, fetchInit);
      const response = await awaitTransportResponse(fetchResult, guard);
      if (response === null) {
        return guard.wasTimeout()
          ? createTimeoutOutcome()
          : createCancelledOutcome();
      }
      return await this.handleTransportResponse(
        response,
        request,
        wireBody.stream,
        startedAt,
        {
          onStreamChunk: options?.onStreamChunk,
          signal: guard.signal,
          wasTimeout: guard.wasTimeout,
        },
      );
    } catch {
      if (guard.signal.aborted) {
        return guard.wasTimeout()
          ? createTimeoutOutcome()
          : createCancelledOutcome();
      }
      return {
        kind: "error",
        error: createCanonicalError(
          "internal_error",
          "transport_failure",
          "DeepSeek transport failed",
        ),
      };
    } finally {
      guard.cleanup();
    }
  }

  private async handleTransportResponse(
    response: DeepSeekTransportResponse,
    _request: CanonicalRequest,
    isStream: boolean | undefined,
    startedAt: number,
    streamOpts: {
      onStreamChunk?: (chunk: CanonicalStreamChunk) => void;
      signal: AbortSignal;
      wasTimeout: () => boolean;
    },
  ): Promise<ProviderInvokeResult> {
    if (isDeclaredBodyOverLimit(response.headers)) {
      return {
        kind: "error",
        error: createCanonicalError(
          "internal_error",
          "response_too_large",
          "Provider response exceeded body size limit",
        ),
      };
    }
    if (
      typeof response.body === "string" &&
      isStringBodyOverLimit(response.body)
    ) {
      return {
        kind: "error",
        error: createCanonicalError(
          "internal_error",
          "response_too_large",
          "Provider response exceeded body size limit",
        ),
      };
    }

    const contentType =
      response.headers["content-type"] ??
      response.headers["Content-Type"] ??
      "";

    if (response.status < 200 || response.status >= 300) {
      const read = await readUtf8Body(response.body, {
        byteLimit: PROVIDER_RESPONSE_BODY_SIZE_LIMIT,
        signal: streamOpts.signal,
      });
      if (!read.ok) {
        if (read.reason === "over_limit") {
          return {
            kind: "error",
            error: createCanonicalError(
              "internal_error",
              "response_too_large",
              "Provider response exceeded body size limit",
            ),
          };
        }
        return streamOpts.wasTimeout()
          ? createTimeoutOutcome()
          : createCancelledOutcome();
      }
      let parsed: DeepSeekResponse = {};
      try {
        parsed = JSON.parse(read.text) as DeepSeekResponse;
      } catch {
        parsed = {};
      }
      const taxonomy = classifyHttpFailure(response.status, parsed);
      const retryAfterMs = parseRetryAfterMs(response.headers);
      return withRawBody(
        {
          kind: "error",
          error: createCanonicalError(
            taxonomy,
            String(parsed.error?.code ?? response.status),
            parsed.error?.message ?? `HTTP ${response.status}`,
            undefined,
            retryAfterMs,
          ),
        },
        read.text,
      );
    }

    if (isStream || contentType.includes("text/event-stream")) {
      return this.handleStreamResponse(response.body, startedAt, streamOpts);
    }

    const read = await readUtf8Body(response.body, {
      byteLimit: PROVIDER_RESPONSE_BODY_SIZE_LIMIT,
      signal: streamOpts.signal,
    });
    if (!read.ok) {
      if (read.reason === "over_limit") {
        return {
          kind: "error",
          error: createCanonicalError(
            "internal_error",
            "response_too_large",
            "Provider response exceeded body size limit",
          ),
        };
      }
      return streamOpts.wasTimeout()
        ? createTimeoutOutcome()
        : createCancelledOutcome();
    }

    const providerMs = Math.max(0, Date.now() - startedAt);
    let parsed: DeepSeekResponse;
    try {
      parsed = JSON.parse(read.text) as DeepSeekResponse;
    } catch {
      return withRawBody(
        {
          kind: "malformed",
          error: createCanonicalError(
            "internal_error",
            "malformed_response",
            "Provider returned unparseable JSON",
          ),
        },
        read.text,
      );
    }

    if (isContentFiltered(parsed)) {
      return withRawBody(
        {
          kind: "error",
          error: createCanonicalError(
            "provider_rejected",
            parsed.error?.code ?? "content_filter",
            parsed.error?.message ?? "Content filtered by provider",
          ),
        },
        read.text,
      );
    }

    const choice = parsed.choices?.[0];
    const content = choice?.message?.content ?? "";
    const finishReason = choice?.finish_reason ?? "stop";

    const finishError = finishReasonErrorOutcome(finishReason);
    if (finishError) {
      return withRawBody(finishError, read.text);
    }

    const usageAbsent = parsed.usage === undefined;
    const result = buildResult(
      parsed,
      content,
      finishReason,
      providerMs,
      this.modelId,
    );
    const chunks = minimalTerminalChunks(content, usageAbsent);

    if (finishReason === "length") {
      return withRawBody({ kind: "truncation", result, chunks }, read.text);
    }

    return withRawBody({ kind: "success", result, chunks }, read.text);
  }

  private async handleStreamResponse(
    body: string | ReadableStream<Uint8Array>,
    startedAt: number,
    streamOpts: {
      onStreamChunk?: (chunk: CanonicalStreamChunk) => void;
      signal: AbortSignal;
      wasTimeout: () => boolean;
    },
  ): Promise<ProviderInvokeResult> {
    const events: DeepSeekResponse[] = [];
    let hadMalformedLine = false;
    const rawPayloads: string[] = [];

    let sse;
    try {
      sse = await readSseDataPayloads(body, {
        byteLimit: PROVIDER_RESPONSE_BODY_SIZE_LIMIT,
        signal: streamOpts.signal,
        onPayload: (payload) => {
          if (payload === "[DONE]") {
            return;
          }
          rawPayloads.push(payload);
          let event: DeepSeekResponse;
          try {
            event = JSON.parse(payload) as DeepSeekResponse;
          } catch {
            hadMalformedLine = true;
            return;
          }
          events.push(event);
          const delta = event.choices?.[0]?.delta?.content;
          if (typeof delta === "string" && delta.length > 0) {
            streamOpts.onStreamChunk?.({
              sequenceNumber: events.length - 1,
              kind: "text_delta",
              payload: { text: delta },
              terminal: false,
            });
          }
        },
      });
    } catch {
      return {
        kind: "error",
        error: createCanonicalError(
          "internal_error",
          "transport_failure",
          "DeepSeek transport failed",
        ),
      };
    }

    const rawText = rawPayloads.join("\n");
    const attach = (result: ProviderInvokeResult): ProviderInvokeResult =>
      withRawBody(result, rawText.length > 0 ? rawText : undefined);

    const providerMs = Math.max(0, Date.now() - startedAt);

    if (sse.overLimit) {
      return attach({
        kind: "error",
        error: createCanonicalError(
          "internal_error",
          "response_too_large",
          "Provider response exceeded body size limit",
        ),
      });
    }
    if (sse.aborted) {
      return streamOpts.wasTimeout()
        ? createTimeoutOutcome()
        : createCancelledOutcome();
    }

    const { sawDone } = sse;

    if (hadMalformedLine) {
      return attach({
        kind: "malformed",
        error: createCanonicalError(
          "internal_error",
          "malformed_response",
          "Provider returned unparseable SSE data line",
        ),
      });
    }

    for (const event of events) {
      if (event.error) {
        const taxonomy = classifyProviderErrorFrame(event);
        return attach({
          kind: "error",
          error: createCanonicalError(
            taxonomy,
            String(event.error.code ?? event.error.type ?? "provider_error"),
            event.error.message ?? "Provider stream error frame",
          ),
        });
      }
    }

    let finishReason: string | null | undefined;
    let hadFinishReason = false;
    let assembled = "";
    let lastEvent: DeepSeekResponse = {};
    let usage: DeepSeekUsage | undefined;

    for (const event of events) {
      lastEvent = event;
      if (event.usage) {
        usage = event.usage;
      }
      const choice = event.choices?.[0];
      const delta = choice?.delta?.content;
      if (typeof delta === "string") {
        assembled += delta;
      }
      const eventFinish = choice?.finish_reason;
      if (typeof eventFinish === "string" && eventFinish.length > 0) {
        finishReason = eventFinish;
        hadFinishReason = true;
      }
    }

    if (hadFinishReason && finishReason) {
      const finishError = finishReasonErrorOutcome(finishReason);
      if (finishError) {
        return attach(finishError);
      }
    }

    const responseForResult: DeepSeekResponse = {
      ...lastEvent,
      usage,
      id: lastEvent.id,
    };
    const effectiveFinish =
      !sawDone && !hadFinishReason ? "length" : (finishReason ?? "stop");
    const chunks = normalizeStreamChunks(events);
    const result = buildResult(
      responseForResult,
      assembled,
      effectiveFinish,
      providerMs,
      this.modelId,
    );

    if (!sawDone && !hadFinishReason) {
      return attach({ kind: "truncation", result, chunks });
    }

    if (finishReason === "length") {
      return attach({ kind: "truncation", result, chunks });
    }

    return attach({ kind: "success", result, chunks });
  }
}
