import type {
  CanonicalError,
  CanonicalRequest,
  CanonicalResult,
  CanonicalStreamChunk,
} from "../contracts/canonical";
import { getTaxonomyEntry, type TaxonomyCode } from "../errors";
import { setRetryabilityFromClassification } from "./classify";
import type { ProviderInvokeResult, ProviderPort } from "./port";

export const GEMINI_API_KEY_BINDING = "GEMINI_API_KEY";

const GEMINI_MODEL = "gemini-1.5-flash";
const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";
const PROVIDER_ID = "gemini";

export type GeminiTransportResponse = {
  status: number;
  headers: Record<string, string>;
  body: string;
};

export type GeminiTransportRequest = {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
  signal?: AbortSignal;
};

export type GeminiTransport = {
  fetch(
    url: string,
    init: GeminiTransportRequest,
  ): GeminiTransportResponse | Promise<GeminiTransportResponse>;
};

export type SecretStorePort = {
  getSecret(name: string): string | undefined;
};

export type LoggerSink = {
  log(level: string, message: string, meta?: Record<string, unknown>): void;
};

export type JournalSink = {
  emit(record: Record<string, unknown>): void;
};

export type GeminiAdapterOptions = {
  transport: GeminiTransport;
  secretStore: SecretStorePort;
  logger?: LoggerSink;
  journal?: JournalSink;
  timeoutMs?: number;
};

type GeminiInvokeOutcome = ProviderInvokeResult & {
  streamChunks?: readonly CanonicalStreamChunk[];
};

type GeminiWireRequest = {
  contents: Array<{
    role: string;
    parts: Array<{ text: string }>;
  }>;
  generationConfig?: {
    temperature?: number;
    maxOutputTokens?: number;
    stopSequences?: string[];
    responseMimeType?: string;
  };
};

type GeminiUsage = {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  totalTokenCount?: number;
};

type GeminiCandidate = {
  content?: { parts?: Array<{ text?: string }>; role?: string };
  finishReason?: string;
};

type GeminiResponse = {
  candidates?: GeminiCandidate[];
  usageMetadata?: GeminiUsage;
  error?: {
    code?: number;
    message?: string;
    status?: string;
  };
  promptFeedback?: {
    blockReason?: string;
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
): CanonicalError {
  return setRetryabilityFromClassification({
    taxonomyCode: code,
    retryability: false,
    providerNative: {
      code: nativeCode,
      message: nativeMessage,
    },
    consumedBudget: consumesBudget(code),
  });
}

function resolveTimeoutMs(
  request: CanonicalRequest,
  options: GeminiAdapterOptions,
): number {
  const deadline =
    typeof request.deadline === "number" ? request.deadline : undefined;
  if (options.timeoutMs !== undefined && deadline !== undefined) {
    return Math.min(options.timeoutMs, deadline);
  }
  return options.timeoutMs ?? deadline ?? 30_000;
}

function mapRoleToGemini(role: string): string {
  if (role === "assistant") {
    return "model";
  }
  return role;
}

function mapCanonicalToWire(request: CanonicalRequest): {
  wire: GeminiWireRequest;
  isStream: boolean;
} {
  const sampling = request.samplingConstraints;
  const outputFormat = request.formatDirective;
  const stopConditions = request.stopConditions;
  const isStream = Boolean(request.stream);

  const wire: GeminiWireRequest = {
    contents: request.parts.map((part) => ({
      role: mapRoleToGemini(part.role),
      parts: [{ text: part.content }],
    })),
    generationConfig: {},
  };

  if (typeof sampling?.temperature === "number") {
    wire.generationConfig!.temperature = sampling.temperature;
  }
  if (typeof request.maxOutputTokens === "number") {
    wire.generationConfig!.maxOutputTokens = request.maxOutputTokens;
  }
  if (Array.isArray(stopConditions) && stopConditions.length > 0) {
    wire.generationConfig!.stopSequences = [...stopConditions];
  }
  if (outputFormat?.type === "json") {
    wire.generationConfig!.responseMimeType = "application/json";
  }

  if (
    wire.generationConfig &&
    Object.keys(wire.generationConfig).length === 0
  ) {
    delete wire.generationConfig;
  }

  return { wire, isStream };
}

function buildApiUrl(isStream: boolean): string {
  const action = isStream ? "streamGenerateContent" : "generateContent";
  const suffix = isStream ? "?alt=sse" : "";
  return `${GEMINI_API_BASE}/${GEMINI_MODEL}:${action}${suffix}`;
}

function mapUsage(
  usage: GeminiUsage | undefined,
): CanonicalResult["usage"] {
  return {
    input: usage?.promptTokenCount ?? 0,
    output: usage?.candidatesTokenCount ?? 0,
    cached: 0,
  };
}

function mapFinishReason(
  finishReason: string | null | undefined,
): CanonicalResult["finishReason"] {
  if (finishReason === "MAX_TOKENS" || finishReason === "length") {
    return "length";
  }
  return "stop";
}

function buildResult(
  response: GeminiResponse,
  content: string,
  finishReason: string | null | undefined,
): CanonicalResult {
  return {
    finalContent: { type: "text", text: content },
    usage: mapUsage(response.usageMetadata),
    providerModel: {
      provider: PROVIDER_ID,
      model: GEMINI_MODEL,
    },
    finishReason: mapFinishReason(finishReason),
    providerRequestId: "gemini-unknown",
    timing: { queue_ms: 0, provider_ms: 0, total_ms: 0 },
  };
}

function isContentFiltered(body: GeminiResponse): boolean {
  const blockReason = body.promptFeedback?.blockReason?.toUpperCase() ?? "";
  if (blockReason.length > 0) {
    return true;
  }
  const finishReason = body.candidates?.[0]?.finishReason?.toUpperCase() ?? "";
  return finishReason === "SAFETY" || finishReason === "BLOCKLIST";
}

function classifyHttpFailure(
  status: number,
  body: GeminiResponse,
): TaxonomyCode {
  if (isContentFiltered(body)) {
    return "provider_rejected";
  }
  if (status === 401 || status === 403) {
    return "provider_rejected";
  }
  if (status === 429) {
    return "rate_limited";
  }
  if (status >= 500) {
    return "internal_error";
  }
  return "provider_rejected";
}

function parseSseEvents(body: string): GeminiResponse[] {
  const events: GeminiResponse[] = [];
  for (const line of body.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) {
      continue;
    }
    const payload = trimmed.slice("data:".length).trim();
    if (payload.length === 0) {
      continue;
    }
    try {
      events.push(JSON.parse(payload) as GeminiResponse);
    } catch {
      // skip malformed SSE lines
    }
  }
  return events;
}

function normalizeStreamChunks(
  events: GeminiResponse[],
): CanonicalStreamChunk[] {
  const chunks: CanonicalStreamChunk[] = [];
  let sequence = 0;
  let assembled = "";
  let finishReason: string | null | undefined;
  let usage: GeminiUsage | undefined;

  for (const event of events) {
    usage = event.usageMetadata ?? usage;
    const candidate = event.candidates?.[0];
    const delta = candidate?.content?.parts?.[0]?.text;
    if (typeof delta === "string" && delta.length > 0) {
      assembled += delta;
      chunks.push({
        sequenceNumber: sequence,
        kind: "text_delta",
        payload: { text: delta },
        terminal: false,
      });
      sequence += 1;
    }
    if (candidate?.finishReason) {
      finishReason = candidate.finishReason;
    }
  }

  if (usage) {
    chunks.push({
      sequenceNumber: sequence,
      kind: "usage",
      payload: mapUsage(usage),
      terminal: false,
    });
    sequence += 1;
  }

  chunks.push({
    sequenceNumber: sequence,
    kind: "text_delta",
    payload: { text: assembled },
    terminal: true,
  });

  return chunks;
}

function safeEmitLog(
  logger: LoggerSink | undefined,
  level: string,
  message: string,
  meta?: Record<string, unknown>,
): void {
  logger?.log(level, message, meta);
}

function safeEmitJournal(
  journal: JournalSink | undefined,
  record: Record<string, unknown>,
): void {
  journal?.emit(record);
}

function createTimeoutOutcome(
  logger: LoggerSink | undefined,
  journal: JournalSink | undefined,
): GeminiInvokeOutcome {
  const error = createCanonicalError(
    "timeout",
    "deadline_exceeded",
    "Gemini request exceeded adapter deadline",
  );
  safeEmitLog(logger, "warn", "gemini.timeout", {
    provider: PROVIDER_ID,
  });
  safeEmitJournal(journal, {
    event: "provider.timeout",
    provider: PROVIDER_ID,
  });
  return { kind: "error", error };
}

function waitForPromiseOutcome<T>(
  promise: Promise<T>,
  timeoutMs: number,
): T | undefined {
  let settled = false;
  let value: T | undefined;
  let error: unknown;

  void promise.then(
    (resolved) => {
      value = resolved;
      settled = true;
    },
    (reason) => {
      error = reason;
      settled = true;
    },
  );

  const deadline = Date.now() + timeoutMs;
  while (!settled && Date.now() < deadline) {
  }

  if (!settled) {
    return undefined;
  }
  if (error !== undefined) {
    throw error;
  }
  return value;
}

export class GeminiAdapter implements ProviderPort {
  private readonly transport: GeminiTransport;
  private readonly secretStore: SecretStorePort;
  private readonly logger?: LoggerSink;
  private readonly journal?: JournalSink;
  private readonly defaultTimeoutMs?: number;

  constructor(options: GeminiAdapterOptions) {
    this.transport = options.transport;
    this.secretStore = options.secretStore;
    this.logger = options.logger;
    this.journal = options.journal;
    this.defaultTimeoutMs = options.timeoutMs;
  }

  invoke(request: CanonicalRequest): GeminiInvokeOutcome {
    const timeoutMs = resolveTimeoutMs(request, {
      transport: this.transport,
      secretStore: this.secretStore,
      timeoutMs: this.defaultTimeoutMs,
    });

    const apiKey = this.secretStore.getSecret(GEMINI_API_KEY_BINDING);
    if (!apiKey) {
      const error = createCanonicalError(
        "provider_rejected",
        "missing_api_key",
        "Gemini API key not found in secret store",
      );
      safeEmitLog(this.logger, "error", "gemini.credentials_missing", {
        provider: PROVIDER_ID,
      });
      safeEmitJournal(this.journal, {
        event: "provider.credentials_missing",
        provider: PROVIDER_ID,
      });
      return { kind: "error", error };
    }

    const { wire, isStream } = mapCanonicalToWire(request);
    const apiUrl = buildApiUrl(isStream);
    const controller = new AbortController();
    const fetchInit: GeminiTransportRequest = {
      url: apiUrl,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify(wire),
      signal: controller.signal,
    };

    const fetchResult = this.transport.fetch(apiUrl, fetchInit);

    if (!(fetchResult instanceof Promise)) {
      return this.handleTransportResponse(fetchResult, request, isStream);
    }

    const timeoutTimer = setTimeout(() => {
      controller.abort();
    }, timeoutMs);

    const response = waitForPromiseOutcome(fetchResult, timeoutMs);
    clearTimeout(timeoutTimer);

    if (response === undefined) {
      return createTimeoutOutcome(this.logger, this.journal);
    }

    return this.handleTransportResponse(response, request, isStream);
  }

  private handleTransportResponse(
    response: GeminiTransportResponse,
    request: CanonicalRequest,
    isStream: boolean,
  ): GeminiInvokeOutcome {
    const contentType =
      response.headers["content-type"] ??
      response.headers["Content-Type"] ??
      "";

    if (response.status < 200 || response.status >= 300) {
      let parsed: GeminiResponse = {};
      try {
        parsed = JSON.parse(response.body) as GeminiResponse;
      } catch {
        parsed = {};
      }
      const taxonomy = classifyHttpFailure(response.status, parsed);
      const error = createCanonicalError(
        taxonomy,
        String(parsed.error?.status ?? parsed.error?.code ?? response.status),
        parsed.error?.message ?? `HTTP ${response.status}`,
      );
      safeEmitLog(this.logger, "warn", "gemini.provider_error", {
        provider: PROVIDER_ID,
        status: response.status,
        taxonomy,
      });
      safeEmitJournal(this.journal, {
        event: "provider.error",
        provider: PROVIDER_ID,
        status: response.status,
        taxonomy,
      });
      return { kind: "error", error };
    }

    if (isStream || contentType.includes("text/event-stream")) {
      return this.handleStreamResponse(response.body);
    }

    let parsed: GeminiResponse;
    try {
      parsed = JSON.parse(response.body) as GeminiResponse;
    } catch {
      const error = createCanonicalError(
        "internal_error",
        "malformed_response",
        "Provider returned unparseable JSON",
      );
      return { kind: "malformed", error };
    }

    if (isContentFiltered(parsed)) {
      const error = createCanonicalError(
        "provider_rejected",
        parsed.candidates?.[0]?.finishReason ?? "SAFETY",
        "Content filtered by provider",
      );
      return { kind: "error", error };
    }

    const candidate = parsed.candidates?.[0];
    const content = candidate?.content?.parts?.[0]?.text ?? "";
    const finishReason = candidate?.finishReason ?? "STOP";
    const result = buildResult(parsed, content, finishReason);

    safeEmitLog(this.logger, "info", "gemini.invoke_complete", {
      provider: PROVIDER_ID,
      request_reference: request.correlationIds.request_reference,
    });
    safeEmitJournal(this.journal, {
      event: "provider.invoke_complete",
      provider: PROVIDER_ID,
    });

    if (finishReason === "MAX_TOKENS") {
      return { kind: "truncation", result };
    }

    return { kind: "success", result };
  }

  private handleStreamResponse(body: string): GeminiInvokeOutcome {
    const events = parseSseEvents(body);
    const streamChunks = normalizeStreamChunks(events);

    const lastEvent = events[events.length - 1];
    const candidate = lastEvent?.candidates?.[0];
    const finishReason = candidate?.finishReason ?? "STOP";
    let assembled = "";
    for (const event of events) {
      const delta = event.candidates?.[0]?.content?.parts?.[0]?.text;
      if (typeof delta === "string") {
        assembled += delta;
      }
    }

    const result = buildResult(lastEvent ?? {}, assembled, finishReason);

    return {
      kind: finishReason === "MAX_TOKENS" ? "truncation" : "success",
      result,
      streamChunks,
    };
  }
}
