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

export type GeminiAdapterOptions = {
  transport: GeminiTransport;
  secretStore: SecretStorePort;
  timeoutMs?: number;
};

type GeminiWireRequest = {
  contents: Array<{
    role: string;
    parts: Array<{ text: string }>;
  }>;
  systemInstruction?: {
    parts: Array<{ text: string }>;
  };
  generationConfig?: {
    temperature?: number;
    maxOutputTokens?: number;
    stopSequences?: string[];
    topK?: number;
    responseMimeType?: string;
    responseSchema?: unknown;
  };
  tools?: Array<{
    functionDeclarations: unknown[];
  }>;
};

type GeminiUsage = {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  totalTokenCount?: number;
  cachedContentTokenCount?: number;
};

type GeminiCandidate = {
  content?: { parts?: Array<{ text?: string }>; role?: string };
  finishReason?: string;
};

type GeminiResponse = {
  responseId?: string;
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

type ParseSseResult = {
  events: GeminiResponse[];
  hadMalformedLine: boolean;
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
  if (role === "data") {
    return "user";
  }
  return "user";
}

function mapCanonicalToWire(request: CanonicalRequest): {
  wire: GeminiWireRequest;
  isStream: boolean;
} {
  const sampling = request.samplingConstraints;
  const outputFormat = request.formatDirective;
  const stopConditions = request.stopConditions;
  const isStream = Boolean(request.stream);

  const systemTexts: string[] = [];
  const contentParts: Array<{ role: string; text: string }> = [];

  for (const part of request.parts) {
    if (part.role === "system") {
      systemTexts.push(part.content);
      continue;
    }
    contentParts.push({
      role: mapRoleToGemini(part.role),
      text: part.content,
    });
  }

  const contents: GeminiWireRequest["contents"] = [];
  for (const part of contentParts) {
    const last = contents[contents.length - 1];
    if (last && last.role === part.role) {
      last.parts.push({ text: part.text });
    } else {
      contents.push({
        role: part.role,
        parts: [{ text: part.text }],
      });
    }
  }

  const wire: GeminiWireRequest = {
    contents,
    generationConfig: {},
  };

  if (systemTexts.length > 0) {
    wire.systemInstruction = {
      parts: [{ text: systemTexts.join("\n") }],
    };
  }

  if (typeof sampling?.temperature === "number") {
    wire.generationConfig!.temperature = sampling.temperature;
  }
  if (typeof sampling?.top_k === "number") {
    wire.generationConfig!.topK = sampling.top_k;
  }
  if (typeof request.maxOutputTokens === "number") {
    wire.generationConfig!.maxOutputTokens = request.maxOutputTokens;
  }
  if (Array.isArray(stopConditions) && stopConditions.length > 0) {
    wire.generationConfig!.stopSequences = [...stopConditions];
  }
  if (outputFormat?.type === "json") {
    wire.generationConfig!.responseMimeType = "application/json";
    if (outputFormat.schema !== undefined) {
      wire.generationConfig!.responseSchema = outputFormat.schema;
    }
  }

  if (
    wire.generationConfig &&
    Object.keys(wire.generationConfig).length === 0
  ) {
    delete wire.generationConfig;
  }

  if (
    Array.isArray(request.toolDeclarations) &&
    request.toolDeclarations.length > 0
  ) {
    const functionDeclarations = request.toolDeclarations.filter(
      (declaration): declaration is object =>
        typeof declaration === "object" &&
        declaration !== null &&
        !Array.isArray(declaration),
    );
    if (functionDeclarations.length > 0) {
      wire.tools = [{ functionDeclarations }];
    }
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
    cached: usage?.cachedContentTokenCount ?? 0,
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

function buildTiming(providerMs: number): TimingBreakdown {
  return {
    queue_ms: 0,
    provider_ms: providerMs,
    total_ms: providerMs,
  };
}

function buildResult(
  response: GeminiResponse,
  content: string,
  finishReason: string | null | undefined,
  providerMs: number,
): CanonicalResult {
  return {
    finalContent: { type: "text", text: content },
    usage: mapUsage(response.usageMetadata),
    providerModel: {
      provider: PROVIDER_ID,
      model: GEMINI_MODEL,
    },
    finishReason: mapFinishReason(finishReason),
    providerRequestId: response.responseId ?? "gemini-unknown",
    timing: buildTiming(providerMs),
  };
}

function extractCandidateText(
  candidate: GeminiCandidate | undefined,
): string {
  const parts = candidate?.content?.parts;
  if (!parts || parts.length === 0) {
    return "";
  }
  return parts
    .map((part) => (typeof part.text === "string" ? part.text : ""))
    .join("");
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

function classifyProviderErrorFrame(body: GeminiResponse): TaxonomyCode {
  if (isContentFiltered(body)) {
    return "provider_rejected";
  }
  const status = (body.error?.status ?? "").toUpperCase();
  const message = (body.error?.message ?? "").toLowerCase();
  if (
    status === "RESOURCE_EXHAUSTED" ||
    status.includes("RATE") ||
    message.includes("rate") ||
    message.includes("quota")
  ) {
    return "rate_limited";
  }
  if (
    status === "INTERNAL" ||
    status === "UNAVAILABLE" ||
    status === "DEADLINE_EXCEEDED" ||
    status.includes("SERVER") ||
    (typeof body.error?.code === "number" && body.error.code >= 500)
  ) {
    return "internal_error";
  }
  if (status.includes("SAFETY") || message.includes("safety")) {
    return "provider_rejected";
  }
  return "provider_rejected";
}

function parseSseEvents(body: string): ParseSseResult {
  const events: GeminiResponse[] = [];
  let hadMalformedLine = false;

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
      hadMalformedLine = true;
    }
  }

  return { events, hadMalformedLine };
}

function normalizeStreamChunks(
  events: GeminiResponse[],
): CanonicalStreamChunk[] {
  const chunks: CanonicalStreamChunk[] = [];
  let sequence = 0;
  let usage: GeminiUsage | undefined;
  let sawUsage = false;

  for (const event of events) {
    if (event.usageMetadata) {
      usage = event.usageMetadata;
      sawUsage = true;
    }
    const delta = extractCandidateText(event.candidates?.[0]);
    if (delta.length > 0) {
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
      "Gemini request exceeded adapter deadline",
    ),
  };
}

function createCancelledOutcome(): ProviderInvokeResult {
  return {
    kind: "error",
    error: createCanonicalError(
      "cancelled",
      "aborted",
      "Gemini request aborted by caller signal",
    ),
  };
}

function finishReasonErrorOutcome(
  finishReason: string,
): ProviderInvokeResult | null {
  const upper = finishReason.toUpperCase();
  if (upper === "SAFETY" || upper === "BLOCKLIST") {
    return {
      kind: "error",
      error: createCanonicalError(
        "provider_rejected",
        upper,
        "Content filtered by provider",
      ),
    };
  }
  if (upper === "RECITATION" || upper === "OTHER" || upper === "SPII") {
    return {
      kind: "error",
      error: createCanonicalError(
        "provider_rejected",
        upper,
        "Provider rejected the request",
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
  fetchResult: GeminiTransportResponse | Promise<GeminiTransportResponse>,
  guard: AbortGuard,
): Promise<GeminiTransportResponse | null> {
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

export class GeminiAdapter implements ProviderPort {
  private readonly transport: GeminiTransport;
  private readonly secretStore: SecretStorePort;
  private readonly defaultTimeoutMs?: number;

  constructor(options: GeminiAdapterOptions) {
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

    const apiKey = this.secretStore.getSecret(GEMINI_API_KEY_BINDING);
    if (!apiKey) {
      return {
        kind: "error",
        error: createCanonicalError(
          "provider_rejected",
          "missing_api_key",
          "Gemini API key not found in secret store",
          false,
        ),
      };
    }

    const { wire, isStream } = mapCanonicalToWire(request);
    const apiUrl = buildApiUrl(isStream);
    const guard = createAbortGuard(timeoutMs, options?.signal);
    const fetchInit: GeminiTransportRequest = {
      url: apiUrl,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify(wire),
      signal: guard.signal,
    };

    const startedAt = Date.now();
    try {
      const fetchResult = this.transport.fetch(apiUrl, fetchInit);
      const response = await awaitTransportResponse(fetchResult, guard);
      const providerMs = Math.max(0, Date.now() - startedAt);
      if (response === null) {
        return guard.wasTimeout()
          ? createTimeoutOutcome()
          : createCancelledOutcome();
      }
      return this.handleTransportResponse(
        response,
        request,
        isStream,
        providerMs,
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
          "Gemini transport failed",
        ),
      };
    } finally {
      guard.cleanup();
    }
  }

  private handleTransportResponse(
    response: GeminiTransportResponse,
    _request: CanonicalRequest,
    isStream: boolean,
    providerMs: number,
  ): ProviderInvokeResult {
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
      return {
        kind: "error",
        error: createCanonicalError(
          taxonomy,
          String(parsed.error?.status ?? parsed.error?.code ?? response.status),
          parsed.error?.message ?? `HTTP ${response.status}`,
        ),
      };
    }

    if (isStream || contentType.includes("text/event-stream")) {
      return this.handleStreamResponse(response.body, providerMs);
    }

    let parsed: GeminiResponse;
    try {
      parsed = JSON.parse(response.body) as GeminiResponse;
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
          parsed.candidates?.[0]?.finishReason ??
            parsed.promptFeedback?.blockReason ??
            "SAFETY",
          "Content filtered by provider",
        ),
      };
    }

    const candidate = parsed.candidates?.[0];
    const content = extractCandidateText(candidate);
    const finishReason = candidate?.finishReason ?? "STOP";

    const finishError = finishReasonErrorOutcome(finishReason);
    if (finishError) {
      return finishError;
    }

    const usageAbsent = parsed.usageMetadata === undefined;
    const result = buildResult(parsed, content, finishReason, providerMs);
    const chunks = minimalTerminalChunks(content, usageAbsent);

    if (finishReason === "MAX_TOKENS") {
      return { kind: "truncation", result, chunks };
    }

    return { kind: "success", result, chunks };
  }

  private handleStreamResponse(
    body: string,
    providerMs: number,
  ): ProviderInvokeResult {
    const { events, hadMalformedLine } = parseSseEvents(body);

    if (hadMalformedLine) {
      return {
        kind: "malformed",
        error: createCanonicalError(
          "internal_error",
          "malformed_response",
          "Provider returned unparseable SSE data line",
        ),
      };
    }

    for (const event of events) {
      if (event.error) {
        const taxonomy = classifyProviderErrorFrame(event);
        return {
          kind: "error",
          error: createCanonicalError(
            taxonomy,
            String(event.error.status ?? event.error.code ?? "provider_error"),
            event.error.message ?? "Provider stream error frame",
          ),
        };
      }
    }

    for (const event of events) {
      if (isContentFiltered(event)) {
        return {
          kind: "error",
          error: createCanonicalError(
            "provider_rejected",
            event.candidates?.[0]?.finishReason ??
              event.promptFeedback?.blockReason ??
              "SAFETY",
            "Content filtered by provider",
          ),
        };
      }
    }

    let finishReason: string | null | undefined;
    let hadFinishReason = false;
    let assembled = "";
    let lastEvent: GeminiResponse = {};
    let usage: GeminiUsage | undefined;

    for (const event of events) {
      lastEvent = event;
      if (event.usageMetadata) {
        usage = event.usageMetadata;
      }
      const candidate = event.candidates?.[0];
      assembled += extractCandidateText(candidate);
      const eventFinish = candidate?.finishReason;
      if (typeof eventFinish === "string" && eventFinish.length > 0) {
        finishReason = eventFinish;
        hadFinishReason = true;
      }
    }

    if (hadFinishReason && finishReason) {
      const finishError = finishReasonErrorOutcome(finishReason);
      if (finishError) {
        return finishError;
      }
    }

    const responseForResult: GeminiResponse = {
      ...lastEvent,
      usageMetadata: usage,
      responseId: lastEvent.responseId,
    };
    const effectiveFinish = !hadFinishReason
      ? "length"
      : (finishReason ?? "STOP");
    const chunks = normalizeStreamChunks(events);
    const result = buildResult(
      responseForResult,
      assembled,
      effectiveFinish,
      providerMs,
    );

    if (!hadFinishReason) {
      return { kind: "truncation", result, chunks };
    }

    if (finishReason === "MAX_TOKENS") {
      return { kind: "truncation", result, chunks };
    }

    return { kind: "success", result, chunks };
  }
}
