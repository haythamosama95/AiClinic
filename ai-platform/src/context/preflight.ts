import type { Manifest } from "../manifest";

/** §13.6.2 — platform constant for byte-to-token conversion. */
export const TOKENS_PER_BYTE_DIVISOR = 4;

/** §13.6.2 — platform safety margin applied to the byte estimate. */
export const ESTIMATE_SAFETY_FACTOR = 1.15;

export function estimateInputTokens(serializedInput: string): number {
  const utf8ByteLength = new TextEncoder().encode(serializedInput).byteLength;
  return (
    Math.ceil(utf8ByteLength / TOKENS_PER_BYTE_DIVISOR) * ESTIMATE_SAFETY_FACTOR
  );
}

export type PreflightResult =
  | { ok: true }
  | { ok: false; code: "request_too_large" };

export function runCostPreflight(
  manifest: Manifest,
  serializedInput: string,
): PreflightResult {
  const estimatedInputTokens = estimateInputTokens(serializedInput);
  const { maxOutputTokens, maxInputTokens, perRequestCostCeiling } =
    manifest.Economics;

  if (
    estimatedInputTokens + maxOutputTokens > perRequestCostCeiling ||
    estimatedInputTokens > maxInputTokens
  ) {
    return { ok: false, code: "request_too_large" };
  }

  return { ok: true };
}
