import {
  assertExactlyOneTerminal,
  type CanonicalError,
  type CanonicalRequest,
  type CanonicalResult,
  type CanonicalStreamChunk,
} from "../contracts/canonical";
import { getTaxonomyEntry, type TaxonomyCode } from "../errors";
import { setRetryabilityFromClassification } from "./classify";
import type {
  ProviderInvokeOptions,
  ProviderInvokeResult,
  ProviderPort,
} from "./port";

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

export type DeepSeekAdapterOptions = {
  transport: DeepSeekTransport;
  secretStore: SecretStorePort;
  timeoutMs?: number;
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
  const sampling = request.samplingConstraints;
  const outputFormat = request.formatDirective;
  const stopConditions = request.stopConditions;

  const wire: DeepSeekWireRequest = {
    model: DEEPSEEK_MODEL,
    messages: request.parts.map((part) => ({
      role: part.role,
      content: part.content,
    })),
    stream: Boolean(request.stream),
  };

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
    cached: 0,
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

function buildResult(
  response: DeepSeekResponse,
  content: string,
  finishReason: string | null | undefined,
): CanonicalResult {
  return {
    finalContent: { type: "text", text: content },
    usage: mapUsage(response.usage),
    providerModel: {
      provider: PROVIDER_ID,
      model: DEEPSEEK_MODEL,
    },
    finishReason: mapFinishReason(finishReason),
    providerRequestId: response.id ?? "deepseek-unknown",
    timing: { queue_ms: 0, provider_ms: 0, total_ms: 0 },
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
  let usage: DeepSeekUsage | undefined;

  for (const event of events) {
    usage = event.usage ?? usage;
    const choice = event.choices?.[0];
    const delta = choice?.delta?.content;
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

  assertExactlyOneTerminal(chunks);
  return chunks;
}

function minimalTerminalChunks(text: string): readonly CanonicalStreamChunk[] {
  const chunks: CanonicalStreamChunk[] = [
    {
      sequenceNumber: 0,
      kind: "text_delta",
      payload: { text },
      terminal: true,
    },
  ];
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

  constructor(options: DeepSeekAdapterOptions) {
    this.transport = options.transport;
    this.secretStore = options.secretStore;
    this.defaultTimeoutMs = options.timeoutMs;
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
        ),
      };
    }

    const wireBody = mapCanonicalToWire(request);
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

    try {
      const fetchResult = this.transport.fetch(DEEPSEEK_API_URL, fetchInit);
      const response = await awaitTransportResponse(fetchResult, guard);
      if (response === null) {
        return guard.wasTimeout()
          ? createTimeoutOutcome()
          : createCancelledOutcome();
      }
      return this.handleTransportResponse(
        response,
        request,
        wireBody.stream,
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

  private handleTransportResponse(
    response: DeepSeekTransportResponse,
    _request: CanonicalRequest,
    isStream: boolean | undefined,
  ): ProviderInvokeResult {
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
      return {
        kind: "error",
        error: createCanonicalError(
          taxonomy,
          String(parsed.error?.code ?? response.status),
          parsed.error?.message ?? `HTTP ${response.status}`,
        ),
      };
    }

    if (isStream || contentType.includes("text/event-stream")) {
      return this.handleStreamResponse(response.body);
    }

    let parsed: DeepSeekResponse;
    try {
      parsed = JSON.parse(response.body) as DeepSeekResponse;
    } catch {
      return {
        kind: "malformed",
        error: createCanonicalError(
          "internal_error",
          "malformed_response",
          "Provider returned unparseable JSON",
        ),
      };
    }

    if (isContentFiltered(parsed)) {
      return {
        kind: "error",
        error: createCanonicalError(
          "provider_rejected",
          parsed.error?.code ?? "content_filter",
          parsed.error?.message ?? "Content filtered by provider",
        ),
      };
    }

    const choice = parsed.choices?.[0];
    const content = choice?.message?.content ?? "";
    const finishReason = choice?.finish_reason ?? "stop";
    const result = buildResult(parsed, content, finishReason);
    const chunks = minimalTerminalChunks(content);

    if (finishReason === "length") {
      return { kind: "truncation", result, chunks };
    }

    return { kind: "success", result, chunks };
  }

  private handleStreamResponse(body: string): ProviderInvokeResult {
    const events = parseSseEvents(body);
    const chunks = normalizeStreamChunks(events);

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
      chunks,
    };
  }
}
