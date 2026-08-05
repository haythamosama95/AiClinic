import type { Manifest } from "../manifest";

/** §13.6.2 — platform constant for byte-to-token conversion. */
export const TOKENS_PER_BYTE_DIVISOR = 4;

/** §13.6.2 — platform safety margin applied to the byte estimate. */
export const ESTIMATE_SAFETY_FACTOR = 1.15;

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

/**
 * §13.6.2 byte-based estimator.
 * `promptArtifactByteLength` is the known UTF-8 byte length of prompt artifacts
 * bound to the capability (system instruction, rule fragments, etc.) — included
 * in the measured input alongside the serialized filtered context / intent /
 * transcript.
 */
export function estimateInputTokens(
  serializedInput: string,
  promptArtifactByteLength = 0,
): number {
  const artifactBytes = isFiniteNumber(promptArtifactByteLength)
    ? Math.max(0, promptArtifactByteLength)
    : 0;
  const utf8ByteLength =
    new TextEncoder().encode(serializedInput).byteLength + artifactBytes;
  return (
    Math.ceil(utf8ByteLength / TOKENS_PER_BYTE_DIVISOR) * ESTIMATE_SAFETY_FACTOR
  );
}

export type PreflightResult =
  | { ok: true }
  | { ok: false; code: "request_too_large" };

/**
 * Serialize the stage-7 pre-flight input. Conversational legs MUST include the
 * validated transcript so growth is priced by the existing estimator (H2).
 */
export function serializePreflightInput(input: {
  filteredContext: Record<string, unknown>;
  userIntent: string;
  transcript?: unknown;
}): string {
  if (input.transcript === undefined) {
    return JSON.stringify({
      filteredContext: input.filteredContext,
      userIntent: input.userIntent,
    });
  }

  return JSON.stringify({
    filteredContext: input.filteredContext,
    userIntent: input.userIntent,
    transcript: input.transcript,
  });
}

export function runCostPreflight(
  manifest: Manifest,
  serializedInput: string,
  promptArtifactByteLength = 0,
): PreflightResult {
  if (
    !isFiniteNumber(promptArtifactByteLength) ||
    promptArtifactByteLength < 0
  ) {
    return { ok: false, code: "request_too_large" };
  }

  const { maxOutputTokens, maxInputTokens, perRequestCostCeiling } =
    manifest.Economics;

  // Fail closed: non-numeric Economics disable both predicates under `>` —
  // reject rather than wave the request through to a paid provider call.
  if (
    !isFiniteNumber(maxOutputTokens) ||
    !isFiniteNumber(maxInputTokens) ||
    !isFiniteNumber(perRequestCostCeiling)
  ) {
    return { ok: false, code: "request_too_large" };
  }

  const estimatedInputTokens = estimateInputTokens(
    serializedInput,
    promptArtifactByteLength,
  );

  if (
    estimatedInputTokens + maxOutputTokens > perRequestCostCeiling ||
    estimatedInputTokens > maxInputTokens
  ) {
    return { ok: false, code: "request_too_large" };
  }

  return { ok: true };
}
