import { isTaxonomyCode, type TaxonomyCode } from "../errors";

/**
 * Field-name manifest for the four §5.3 canonical inference elements.
 * Identifiers match amended §5.3 Field column; the guard test (T-A3-05 / T-A3-10)
 * exercises them.
 */
export const CANONICAL_FIELD_MANIFEST = {
  request: [
    "parts",
    "formatDirective",
    "samplingConstraints",
    "maxOutputTokens",
    "stopConditions",
    "toolDeclarations",
    "stream",
    "deadline",
    "correlationIds",
  ],
  streamChunk: ["sequenceNumber", "kind", "payload", "terminal"],
  result: [
    "finalContent",
    "usage",
    "providerModel",
    "finishReason",
    "providerRequestId",
    "timing",
  ],
  error: [
    "taxonomyCode",
    "retryability",
    "providerNative",
    "consumedBudget",
  ],
} as const;

const PROVIDER_SHAPED_FIELD_NAMES = new Set([
  "messages",
  "completion",
  "n",
  "frequency_penalty",
  "top_p",
  "logprobs",
]);

/** Closed §5.3 message-part role tags. */
export const CANONICAL_MESSAGE_ROLES = [
  "system",
  "user",
  "assistant",
  "data",
] as const;

export type CanonicalMessageRole = (typeof CANONICAL_MESSAGE_ROLES)[number];

export type CanonicalMessagePart = {
  role: CanonicalMessageRole;
  content: string;
};

/** Output format directive — free text / JSON-with-schema, or composer mode pin. */
export type OutputFormatDirective = {
  type?: string;
  schema?: unknown;
  mode?: string;
  outputSchemaRef?: string | null;
};

export type SamplingConstraints = {
  temperature?: number;
  top_k?: number;
  allowedLanguages?: readonly string[];
};

export type CorrelationIds = {
  request_reference: string;
  trace_id: string;
};

/** §5.3 canonical request — typed fields keyed by amended identifiers. */
export type CanonicalRequest = {
  parts: readonly CanonicalMessagePart[];
  formatDirective: OutputFormatDirective;
  samplingConstraints: SamplingConstraints;
  maxOutputTokens: number;
  stopConditions: readonly string[];
  toolDeclarations: readonly unknown[];
  stream: boolean;
  deadline: number | null;
  correlationIds: CorrelationIds;
};

export type UsageCounters = {
  input: number;
  output: number;
  cached: number;
};

export type ProviderModelUsed = {
  provider: string;
  model: string;
};

export type TimingBreakdown = {
  queue_ms: number;
  provider_ms: number;
  total_ms: number;
};

/** Final content may be free text or structured object. */
export type FinalContent = {
  type?: string;
  text?: string;
  [key: string]: unknown;
};

/** §5.3 canonical result — typed fields keyed by amended identifiers. */
export type CanonicalResult = {
  finalContent: FinalContent;
  usage: UsageCounters;
  providerModel: ProviderModelUsed;
  finishReason: string;
  providerRequestId: string;
  timing: TimingBreakdown;
};

/** Closed, exhaustive chunk-kind set (§5.3). */
export const CANONICAL_CHUNK_KINDS = [
  "text_delta",
  "partial_structured",
  "usage",
  "provider_note",
] as const;

export type CanonicalChunkKind = (typeof CANONICAL_CHUNK_KINDS)[number];

/** §5.3 canonical stream chunk — `kind` is the closed chunk-kind union. */
export type CanonicalStreamChunk = {
  sequenceNumber: number;
  kind: CanonicalChunkKind;
  payload: unknown;
  terminal: boolean;
};

export type ProviderNativeDiagnostic = {
  code: string;
  message: string;
};

/** §5.3 canonical error — `taxonomyCode` binds to A2's frozen set. */
export type CanonicalError = {
  taxonomyCode: TaxonomyCode;
  retryability: boolean;
  providerNative: ProviderNativeDiagnostic;
  consumedBudget: boolean;
  /**
   * Optional provider Retry-After hint in milliseconds (runtime handoff to
   * invocation). Not a §5.3 wire-manifest field — omit before encode.
   */
  retryAfterMs?: number;
};

export function assertNoProviderShapedFieldNames(
  keys: readonly string[],
): void {
  for (const key of keys) {
    if (PROVIDER_SHAPED_FIELD_NAMES.has(key)) {
      throw new Error(`Provider-shaped field name rejected: ${key}`);
    }
  }
}

export function isCanonicalChunkKind(
  kind: string,
): kind is CanonicalChunkKind {
  return (CANONICAL_CHUNK_KINDS as readonly string[]).includes(kind);
}

export function assertExactlyOneTerminal(
  sequence: readonly Pick<CanonicalStreamChunk, "terminal">[],
): void {
  if (sequence.length === 0) {
    throw new Error("Chunk sequence must not be empty");
  }

  const terminalCount = sequence.filter(
    (chunk) => chunk.terminal === true,
  ).length;

  if (terminalCount !== 1) {
    throw new Error(
      `Expected exactly one terminal chunk, found ${terminalCount}`,
    );
  }
}

function pickManifestKeys(
  value: Record<string, unknown>,
  manifestKeys: readonly string[],
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of manifestKeys) {
    if (key in value) {
      out[key] = value[key];
    }
  }
  return out;
}

/**
 * Fail closed: reject provider-shaped and unknown keys on codec I/O.
 * Silent stripping would hide upstream drift (§5.3 / T-A3-05, T-A3-08).
 */
function assertOnlyManifestKeys(
  value: Record<string, unknown>,
  manifestKeys: readonly string[],
): void {
  const allowed = new Set<string>(manifestKeys);
  const present = Object.keys(value);
  assertNoProviderShapedFieldNames(present);
  for (const key of present) {
    if (!allowed.has(key)) {
      throw new Error(`Unknown canonical field rejected: ${key}`);
    }
  }
}

function encodeFromManifest(
  value: Record<string, unknown>,
  manifestKeys: readonly string[],
): string {
  assertNoProviderShapedFieldNames(manifestKeys);
  assertOnlyManifestKeys(value, manifestKeys);
  return JSON.stringify(pickManifestKeys(value, manifestKeys));
}

function decodeFromManifest<T>(
  wire: string,
  manifestKeys: readonly string[],
  validate?: (decoded: Record<string, unknown>) => T,
): T {
  const parsed = JSON.parse(wire) as Record<string, unknown>;
  assertOnlyManifestKeys(parsed, manifestKeys);
  const decoded = pickManifestKeys(parsed, manifestKeys);
  return validate ? validate(decoded) : (decoded as T);
}

export function encodeCanonicalRequest(value: CanonicalRequest): string {
  return encodeFromManifest(
    value as Record<string, unknown>,
    CANONICAL_FIELD_MANIFEST.request,
  );
}

export function decodeCanonicalRequest(wire: string): CanonicalRequest {
  return decodeFromManifest(wire, CANONICAL_FIELD_MANIFEST.request);
}

export function encodeCanonicalChunk(value: CanonicalStreamChunk): string {
  return encodeFromManifest(
    value as Record<string, unknown>,
    CANONICAL_FIELD_MANIFEST.streamChunk,
  );
}

export function decodeCanonicalChunk(wire: string): CanonicalStreamChunk {
  return decodeFromManifest(
    wire,
    CANONICAL_FIELD_MANIFEST.streamChunk,
    (decoded) => {
      const kind = decoded.kind;
      if (typeof kind !== "string" || !isCanonicalChunkKind(kind)) {
        throw new Error(`Unrecognised chunk kind: ${kind}`);
      }
      return decoded as CanonicalStreamChunk;
    },
  );
}

export function encodeCanonicalResult(value: CanonicalResult): string {
  return encodeFromManifest(
    value as Record<string, unknown>,
    CANONICAL_FIELD_MANIFEST.result,
  );
}

export function decodeCanonicalResult(wire: string): CanonicalResult {
  return decodeFromManifest(wire, CANONICAL_FIELD_MANIFEST.result);
}

export function encodeCanonicalError(value: CanonicalError): string {
  return encodeFromManifest(
    value as Record<string, unknown>,
    CANONICAL_FIELD_MANIFEST.error,
  );
}

export function decodeCanonicalError(wire: string): CanonicalError {
  return decodeFromManifest(
    wire,
    CANONICAL_FIELD_MANIFEST.error,
    (decoded) => {
      const code = decoded.taxonomyCode;
      if (typeof code !== "string" || !isTaxonomyCode(code)) {
        throw new Error(`Unrecognised taxonomy code: ${code}`);
      }
      return decoded as CanonicalError;
    },
  );
}
