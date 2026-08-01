import type {
  CanonicalError,
  CanonicalRequest,
  CanonicalResult,
  CanonicalStreamChunk,
} from "../contracts/canonical";
import { getTaxonomyEntry, type TaxonomyCode } from "../errors";
import { setRetryabilityFromClassification } from "./classify";
import type { ProviderInvokeResult, ProviderPort } from "./port";

export const DEEPSEEK_API_KEY_BINDING = "DEEPSEEK_API_KEY";

const DEEPSEEK_API_URL = "https://api.deepseek.com/chat/completions";
const DEEPSEEK_MODEL = "deepseek-chat";
const PROVIDER_ID = "deepseek";

export type DeepSeekTransportResponse = {
  status: number;
  headers: Record<string, string>;
  body: string;
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

export type LoggerSink = {
  log(level: string, message: string, meta?: Record<string, unknown>): void;
};

export type JournalSink = {
  emit(record: Record<string, unknown>): void;
};

export type DeepSeekAdapterOptions = {
  transport: DeepSeekTransport;
  secretStore: SecretStorePort;
  logger?: LoggerSink;
  journal?: JournalSink;
  timeoutMs?: number;
};

type DeepSeekInvokeOutcome = ProviderInvokeResult & {
  streamChunks?: readonly CanonicalStreamChunk[];
};

type DeepSeekWireRequest = {
  model: string;
  messages: Array<{ role: string; content: string }>;
  temperature?: number;
  max_tokens?: number;
  stop?: string[];
  stream?: boolean;
  response_format?: { type: string };
};

type DeepSeekUsage = {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
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
): CanonicalError {
  return setRetryabilityFromClassification({
    "taxonomy code": code,
    retryability: false,
    "provider-native code and message": {
      code: nativeCode,
      message: nativeMessage,
    },
    "whether the attempt consumed budget": consumesBudget(code),
  });
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

function mapCanonicalToWire(request: CanonicalRequest): DeepSeekWireRequest {
  const sampling = request["sampling constraints"] as
    | { temperature?: number }
    | undefined;
  const outputFormat = request["output format directive"] as
    | { type?: string }
    | undefined;
  const stopConditions = request["stop conditions"] as string[];

  const wire: DeepSeekWireRequest = {
    model: DEEPSEEK_MODEL,
    messages: request["ordered role-tagged message parts"] as Array<{
      role: string;
      content: string;
    }>,
    stream: Boolean(request["stream flag"]),
  };

  if (typeof sampling?.temperature === "number") {
    wire.temperature = sampling.temperature;
  }
  if (typeof request["max output tokens"] === "number") {
    wire.max_tokens = request["max output tokens"];
  }
  if (Array.isArray(stopConditions) && stopConditions.length > 0) {
    wire.stop = stopConditions;
  }
  if (outputFormat?.type === "json") {
    wire.response_format = { type: "json_object" };
  }

  return wire;
}

function mapUsage(
  usage: DeepSeekUsage | undefined,
): CanonicalResult["usage counters"] {
  return {
    input: usage?.prompt_tokens ?? 0,
    output: usage?.completion_tokens ?? 0,
    cached: 0,
  };
}

function mapFinishReason(
  finishReason: string | null | undefined,
): CanonicalResult["finish reason"] {
  if (finishReason === "length") {
    return "length";
  }
  return "stop";
}

function buildResult(
  response: DeepSeekResponse,
  content: string,
  finishReason: string | null | undefined,
): CanonicalResult {
  return {
    "final content": { type: "text", text: content },
    "usage counters": mapUsage(response.usage),
    "provider+model actually used": {
      provider: PROVIDER_ID,
      model: DEEPSEEK_MODEL,
    },
    "finish reason": mapFinishReason(finishReason),
    "provider request id": response.id ?? "deepseek-unknown",
    "timing breakdown": { queue_ms: 0, provider_ms: 0, total_ms: 0 },
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
    message.includes("content filter") ||
    message.includes("safety")
  );
}

function classifyHttpFailure(
  status: number,
  body: DeepSeekResponse,
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

function parseSseEvents(body: string): DeepSeekResponse[] {
  const events: DeepSeekResponse[] = [];
  for (const line of body.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) {
      continue;
    }
    const payload = trimmed.slice("data:".length).trim();
    if (payload === "[DONE]" || payload.length === 0) {
      continue;
    }
    try {
      events.push(JSON.parse(payload) as DeepSeekResponse);
    } catch {
      // skip malformed SSE lines
    }
  }
  return events;
}

function normalizeStreamChunks(
  events: DeepSeekResponse[],
): CanonicalStreamChunk[] {
  const chunks: CanonicalStreamChunk[] = [];
  let sequence = 0;
  let assembled = "";
  let finishReason: string | null | undefined;
  let usage: DeepSeekUsage | undefined;

  for (const event of events) {
    usage = event.usage ?? usage;
    const choice = event.choices?.[0];
    const delta = choice?.delta?.content;
    if (typeof delta === "string" && delta.length > 0) {
      assembled += delta;
      chunks.push({
        "sequence number": sequence,
        kind: "text_delta",
        payload: { text: delta },
        "terminal flag": false,
      });
      sequence += 1;
    }
    if (choice?.finish_reason) {
      finishReason = choice.finish_reason;
    }
  }

  if (usage) {
    chunks.push({
      "sequence number": sequence,
      kind: "usage",
      payload: mapUsage(usage),
      "terminal flag": false,
    });
    sequence += 1;
  }

  chunks.push({
    "sequence number": sequence,
    kind: "text_delta",
    payload: { text: assembled },
    "terminal flag": true,
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
): DeepSeekInvokeOutcome {
  const error = createCanonicalError(
    "timeout",
    "deadline_exceeded",
    "DeepSeek request exceeded adapter deadline",
  );
  safeEmitLog(logger, "warn", "deepseek.timeout", {
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

export class DeepSeekAdapter implements ProviderPort {
  private readonly transport: DeepSeekTransport;
  private readonly secretStore: SecretStorePort;
  private readonly logger?: LoggerSink;
  private readonly journal?: JournalSink;
  private readonly defaultTimeoutMs?: number;

  constructor(options: DeepSeekAdapterOptions) {
    this.transport = options.transport;
    this.secretStore = options.secretStore;
    this.logger = options.logger;
    this.journal = options.journal;
    this.defaultTimeoutMs = options.timeoutMs;
  }

  invoke(request: CanonicalRequest): DeepSeekInvokeOutcome {
    const timeoutMs = resolveTimeoutMs(request, {
      transport: this.transport,
      secretStore: this.secretStore,
      timeoutMs: this.defaultTimeoutMs,
    });

    const apiKey = this.secretStore.getSecret(DEEPSEEK_API_KEY_BINDING);
    if (!apiKey) {
      const error = createCanonicalError(
        "provider_rejected",
        "missing_api_key",
        "DeepSeek API key not found in secret store",
      );
      safeEmitLog(this.logger, "error", "deepseek.credentials_missing", {
        provider: PROVIDER_ID,
      });
      safeEmitJournal(this.journal, {
        event: "provider.credentials_missing",
        provider: PROVIDER_ID,
      });
      return { kind: "error", error };
    }

    const wireBody = mapCanonicalToWire(request);
    const controller = new AbortController();
    const fetchInit: DeepSeekTransportRequest = {
      url: DEEPSEEK_API_URL,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(wireBody),
      signal: controller.signal,
    };

    const fetchResult = this.transport.fetch(DEEPSEEK_API_URL, fetchInit);

    if (!(fetchResult instanceof Promise)) {
      return this.handleTransportResponse(
        fetchResult,
        request,
        wireBody.stream,
      );
    }

    const timeoutTimer = setTimeout(() => {
      controller.abort();
    }, timeoutMs);

    const response = waitForPromiseOutcome(fetchResult, timeoutMs);
    clearTimeout(timeoutTimer);

    if (response === undefined) {
      return createTimeoutOutcome(this.logger, this.journal);
    }

    return this.handleTransportResponse(response, request, wireBody.stream);
  }

  private handleTransportResponse(
    response: DeepSeekTransportResponse,
    request: CanonicalRequest,
    isStream: boolean | undefined,
  ): DeepSeekInvokeOutcome {
    const contentType =
      response.headers["content-type"] ??
      response.headers["Content-Type"] ??
      "";

    if (response.status < 200 || response.status >= 300) {
      let parsed: DeepSeekResponse = {};
      try {
        parsed = JSON.parse(response.body) as DeepSeekResponse;
      } catch {
        parsed = {};
      }
      const taxonomy = classifyHttpFailure(response.status, parsed);
      const error = createCanonicalError(
        taxonomy,
        String(parsed.error?.code ?? response.status),
        parsed.error?.message ?? `HTTP ${response.status}`,
      );
      safeEmitLog(this.logger, "warn", "deepseek.provider_error", {
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

    let parsed: DeepSeekResponse;
    try {
      parsed = JSON.parse(response.body) as DeepSeekResponse;
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
        parsed.error?.code ?? "content_filter",
        parsed.error?.message ?? "Content filtered by provider",
      );
      return { kind: "error", error };
    }

    const choice = parsed.choices?.[0];
    const content = choice?.message?.content ?? "";
    const finishReason = choice?.finish_reason ?? "stop";
    const result = buildResult(parsed, content, finishReason);

    safeEmitLog(this.logger, "info", "deepseek.invoke_complete", {
      provider: PROVIDER_ID,
      request_reference: (
        request["correlation ids"] as { request_reference?: string }
      )?.request_reference,
    });
    safeEmitJournal(this.journal, {
      event: "provider.invoke_complete",
      provider: PROVIDER_ID,
    });

    if (finishReason === "length") {
      return { kind: "truncation", result };
    }

    return { kind: "success", result };
  }

  private handleStreamResponse(body: string): DeepSeekInvokeOutcome {
    const events = parseSseEvents(body);
    const streamChunks = normalizeStreamChunks(events);

    const lastEvent = events[events.length - 1];
    const choice = lastEvent?.choices?.[0];
    const finishReason = choice?.finish_reason ?? "stop";
    let assembled = "";
    for (const event of events) {
      const delta = event.choices?.[0]?.delta?.content;
      if (typeof delta === "string") {
        assembled += delta;
      }
    }

    const result = buildResult(lastEvent ?? {}, assembled, finishReason);

    return {
      kind: finishReason === "length" ? "truncation" : "success",
      result,
      streamChunks,
    };
  }
}
