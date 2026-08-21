import type {
  CanonicalError,
  CanonicalRequest,
  CanonicalResult,
  CanonicalStreamChunk,
} from "../contracts/canonical";
import type { TaxonomyCode } from "../errors";
import type { CapturedRawBody } from "./raw-body";

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
  /**
   * Live stream channel — adapters call this as each normalized chunk is
   * produced, before `invoke` resolves. Invocation relays `text_delta` onto
   * the existing sink so the broker can emit while the provider call is open.
   */
  onStreamChunk?: (chunk: CanonicalStreamChunk) => void;
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
      rawBody?: CapturedRawBody;
    }
  | {
      kind: "error";
      error: CanonicalError;
      /** Optional partial stream observed before the failure (D3 regenerating path). */
      chunks?: readonly CanonicalStreamChunk[];
      rawBody?: CapturedRawBody;
    }
  | {
      kind: "truncation";
      result: CanonicalResult;
      chunks: readonly CanonicalStreamChunk[];
      rawBody?: CapturedRawBody;
    }
  | {
      kind: "malformed";
      error: CanonicalError;
      /** Optional partial stream observed before the malformed outcome. */
      chunks?: readonly CanonicalStreamChunk[];
      rawBody?: CapturedRawBody;
    };

/** Every provider adapter implements this port. */
export interface ProviderPort {
  invoke(
    request: CanonicalRequest,
    options?: ProviderInvokeOptions,
  ): Promise<ProviderInvokeResult>;
}
