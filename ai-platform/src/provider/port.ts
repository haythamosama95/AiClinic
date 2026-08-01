import type {
  CanonicalError,
  CanonicalRequest,
  CanonicalResult,
} from "../contracts/canonical";
import type { TaxonomyCode } from "../errors";

/**
 * Typed adapter boundary (§4.3.8). Adapters own authentication, request/response
 * mapping, stream-chunk normalization, structured-output mechanics, timeouts, and
 * classifying every failure as retryable or terminal. Adapters do not own retry
 * decisions, fallback decisions, or logging policy.
 */

/** Scripted outcome for the deterministic fake adapter (Clarification Q2). */
export type ScriptedOutcome =
  | "success"
  | "truncation"
  | "malformed"
  | `retryable:${TaxonomyCode}`
  | `terminal:${TaxonomyCode}`;

/** Discriminated invoke result — success, classified error, truncation, or malformed. */
export type ProviderInvokeResult =
  | { kind: "success"; result: CanonicalResult }
  | { kind: "error"; error: CanonicalError }
  | { kind: "truncation"; result: CanonicalResult }
  | { kind: "malformed"; error: CanonicalError };

/** Every provider adapter implements this port. */
export interface ProviderPort {
  invoke(request: CanonicalRequest): ProviderInvokeResult;
}
