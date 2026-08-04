import type {
  CanonicalError,
  CanonicalRequest,
  CanonicalResult,
  CanonicalStreamChunk,
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

/** Port-named options for a single invoke (deadline remains on CanonicalRequest). */
export type ProviderInvokeOptions = {
  signal?: AbortSignal;
};

/**
 * Discriminated invoke result — success, classified error, truncation, or malformed.
 * Success and truncation carry an ordered chunk sequence ending with exactly one
 * terminal chunk (assert via `assertExactlyOneTerminal`).
 */
export type ProviderInvokeResult =
  | {
      kind: "success";
      result: CanonicalResult;
      chunks: readonly CanonicalStreamChunk[];
    }
  | {
      kind: "error";
      error: CanonicalError;
      /** Optional partial stream observed before the failure (D3 regenerating path). */
      chunks?: readonly CanonicalStreamChunk[];
    }
  | {
      kind: "truncation";
      result: CanonicalResult;
      chunks: readonly CanonicalStreamChunk[];
    }
  | {
      kind: "malformed";
      error: CanonicalError;
      /** Optional partial stream observed before the malformed outcome. */
      chunks?: readonly CanonicalStreamChunk[];
    };

/** Every provider adapter implements this port. */
export interface ProviderPort {
  invoke(
    request: CanonicalRequest,
    options?: ProviderInvokeOptions,
  ): Promise<ProviderInvokeResult>;
}
