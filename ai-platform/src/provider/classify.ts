import type { CanonicalError } from "../contracts/canonical";
import { getTaxonomyEntry, isRetrySafe, type TaxonomyCode } from "../errors";

export type FailureClassification = "retryable" | "terminal";

/**
 * Maps every taxonomy code to exactly one adapter classification, derived from
 * A2's retryability column via `isRetrySafe`.
 */
export function classifyFailure(code: TaxonomyCode): FailureClassification {
  const { retryable } = getTaxonomyEntry(code);
  return isRetrySafe(retryable) ? "retryable" : "terminal";
}

/**
 * Sets `retryability` on a canonical error from its taxonomy code classification.
 */
export function setRetryabilityFromClassification(
  error: CanonicalError,
): CanonicalError {
  const classification = classifyFailure(error["taxonomy code"]);
  return {
    ...error,
    retryability: classification === "retryable",
  };
}
