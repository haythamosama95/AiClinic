import { isTaxonomyCode, type TaxonomyCode } from "../errors";

/**
 * Field-name manifest for the four §5.3 canonical inference elements.
 * Types and codec derive from this; the guard test (T-A3-05) exercises it.
 */
export const CANONICAL_FIELD_MANIFEST = {
  request: [
    "ordered role-tagged message parts",
    "output format directive",
    "sampling constraints",
    "max output tokens",
    "stop conditions",
    "tool/function declarations (reserved for future)",
    "stream flag",
    "deadline",
    "correlation ids",
  ],
  streamChunk: [
    "sequence number",
    "kind",
    "payload",
    "terminal flag",
  ],
  result: [
    "final content",
    "usage counters",
    "provider+model actually used",
    "finish reason",
    "provider request id",
    "timing breakdown",
  ],
  error: [
    "taxonomy code",
    "retryability",
    "provider-native code and message",
    "whether the attempt consumed budget",
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

type ManifestRecord<Keys extends readonly string[]> = {
  [K in Keys[number]]: unknown;
};

/** §5.3 canonical request — field names derived from the manifest. */
export type CanonicalRequest = ManifestRecord<
  typeof CANONICAL_FIELD_MANIFEST.request
>;

/** §5.3 canonical result — field names derived from the manifest. */
export type CanonicalResult = ManifestRecord<
  typeof CANONICAL_FIELD_MANIFEST.result
>;

/** Closed, exhaustive chunk-kind set (§5.3). */
export const CANONICAL_CHUNK_KINDS = [
  "text_delta",
  "partial_structured",
  "usage",
  "provider_note",
] as const;

export type CanonicalChunkKind = (typeof CANONICAL_CHUNK_KINDS)[number];

type StreamChunkBase = ManifestRecord<
  typeof CANONICAL_FIELD_MANIFEST.streamChunk
>;

/** §5.3 canonical stream chunk — `kind` is the closed chunk-kind union. */
export type CanonicalStreamChunk = Omit<StreamChunkBase, "kind"> & {
  kind: CanonicalChunkKind;
};

type ErrorBase = ManifestRecord<typeof CANONICAL_FIELD_MANIFEST.error>;

/** §5.3 canonical error — `taxonomy code` binds to A2's frozen set. */
export type CanonicalError = Omit<ErrorBase, "taxonomy code"> & {
  "taxonomy code": TaxonomyCode;
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
  sequence: readonly Pick<CanonicalStreamChunk, "terminal flag">[],
): void {
  if (sequence.length === 0) {
    throw new Error("Chunk sequence must not be empty");
  }

  const terminalCount = sequence.filter(
    (chunk) => chunk["terminal flag"] === true,
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

function encodeFromManifest(
  value: Record<string, unknown>,
  manifestKeys: readonly string[],
): string {
  assertNoProviderShapedFieldNames(manifestKeys);
  return JSON.stringify(pickManifestKeys(value, manifestKeys));
}

function decodeFromManifest<T>(
  wire: string,
  manifestKeys: readonly string[],
  validate?: (decoded: Record<string, unknown>) => T,
): T {
  const parsed = JSON.parse(wire) as Record<string, unknown>;
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
      const kind = decoded["kind"];
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

export function encodeCanonicalError(
  value: CanonicalError | ErrorBase,
): string {
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
      const code = decoded["taxonomy code"];
      if (typeof code !== "string" || !isTaxonomyCode(code)) {
        throw new Error(`Unrecognised taxonomy code: ${code}`);
      }
      return decoded as CanonicalError;
    },
  );
}
