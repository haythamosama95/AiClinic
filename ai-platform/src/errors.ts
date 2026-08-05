export type TaxonomyCode =
  | "unauthenticated"
  | "installation_suspended"
  | "forbidden_capability"
  | "rate_limited"
  | "quota_exhausted"
  | "request_too_large"
  | "context_required"
  | "context_invalid"
  | "conversation_budget_exhausted"
  | "capability_unknown"
  | "capability_retired"
  | "capability_disabled"
  | "provider_unavailable"
  | "provider_rejected"
  | "validation_failed"
  | "cancelled"
  | "timeout"
  | "internal_error";

export interface TaxonomyEntry {
  code: TaxonomyCode;
  httpStatus: number;
  retryable: string;
  consumesQuota: string;
}

const TAXONOMY: Record<TaxonomyCode, TaxonomyEntry> = {
  unauthenticated: {
    code: "unauthenticated",
    httpStatus: 401,
    retryable: "After re-mint",
    consumesQuota: "No",
  },
  installation_suspended: {
    code: "installation_suspended",
    httpStatus: 403,
    retryable: "No",
    consumesQuota: "No",
  },
  forbidden_capability: {
    code: "forbidden_capability",
    httpStatus: 403,
    retryable: "No",
    consumesQuota: "No",
  },
  rate_limited: {
    code: "rate_limited",
    httpStatus: 429,
    retryable: "Yes, after `retry_after`",
    consumesQuota: "No",
  },
  quota_exhausted: {
    code: "quota_exhausted",
    httpStatus: 429,
    retryable: "Not until period reset",
    consumesQuota: "No",
  },
  request_too_large: {
    code: "request_too_large",
    httpStatus: 413,
    retryable: "No",
    consumesQuota: "No",
  },
  context_required: {
    code: "context_required",
    httpStatus: 422,
    retryable: "Yes, after resolving",
    consumesQuota: "No",
  },
  context_invalid: {
    code: "context_invalid",
    httpStatus: 422,
    retryable: "No",
    consumesQuota: "No",
  },
  conversation_budget_exhausted: {
    code: "conversation_budget_exhausted",
    httpStatus: 409,
    retryable: "No, within this conversation",
    consumesQuota: "No",
  },
  capability_unknown: {
    code: "capability_unknown",
    httpStatus: 404,
    retryable: "No",
    consumesQuota: "No",
  },
  capability_retired: {
    code: "capability_retired",
    httpStatus: 404,
    retryable: "No",
    consumesQuota: "No",
  },
  capability_disabled: {
    code: "capability_disabled",
    httpStatus: 503,
    retryable: "Later",
    consumesQuota: "No",
  },
  provider_unavailable: {
    code: "provider_unavailable",
    httpStatus: 503,
    retryable: "Yes",
    consumesQuota: "Partially, recorded",
  },
  provider_rejected: {
    code: "provider_rejected",
    httpStatus: 422,
    retryable: "No",
    consumesQuota: "Yes",
  },
  validation_failed: {
    code: "validation_failed",
    httpStatus: 422,
    retryable: "Yes, at user discretion",
    consumesQuota: "Yes",
  },
  cancelled: {
    code: "cancelled",
    httpStatus: 499,
    retryable: "—",
    consumesQuota: "Partially, recorded",
  },
  timeout: {
    code: "timeout",
    httpStatus: 504,
    retryable: "Yes",
    consumesQuota: "Partially, recorded",
  },
  internal_error: {
    code: "internal_error",
    httpStatus: 500,
    retryable: "Yes",
    consumesQuota: "No",
  },
};

/** Closed ordered list of every A2 taxonomy code — single source for exhaustiveness tests. */
export const ALL_TAXONOMY_CODES = Object.keys(TAXONOMY) as TaxonomyCode[];

const TAXONOMY_CODE_SET = new Set<string>(ALL_TAXONOMY_CODES);

export function isTaxonomyCode(code: string): code is TaxonomyCode {
  return TAXONOMY_CODE_SET.has(code);
}

export function classifyErrorCode(code: string): TaxonomyCode {
  if (isTaxonomyCode(code)) {
    return code;
  }
  return "internal_error";
}

export function getTaxonomyEntry(code: TaxonomyCode): TaxonomyEntry {
  return TAXONOMY[code];
}

export function isRetrySafe(retryable: string): boolean {
  return retryable !== "No" && retryable !== "—";
}

export function liveHttpStatusForCode(code: TaxonomyCode): number | null {
  if (code === "cancelled") {
    return null;
  }
  return getTaxonomyEntry(code).httpStatus;
}

export interface SupplementaryFieldInput {
  retryAfter?: number;
  periodReset?: string;
}

export function supplementaryFieldsForCode(
  code: TaxonomyCode,
  input: SupplementaryFieldInput,
): Record<string, number | string> {
  if (code === "rate_limited") {
    return { retry_after: input.retryAfter ?? 0 };
  }
  if (code === "quota_exhausted") {
    // Omit empty admin-path values — concurrency-mapped refusals must populate
    // periodReset from the entitlement snapshot (F4), never emit "".
    if (input.periodReset === undefined || input.periodReset === "") {
      return {};
    }
    return { period_reset: input.periodReset };
  }
  return {};
}

export interface ErrorBodyInput {
  code: string;
  requestReference: string;
  traceId: string;
}

export interface ErrorBody {
  code: TaxonomyCode;
  request_reference: string;
  trace_id: string;
  retry_safe: boolean;
}

export function buildErrorBody(input: ErrorBodyInput): ErrorBody {
  if (input.code === "context_requested") {
    throw new Error("context_requested is not a taxonomy error code");
  }

  const classified = classifyErrorCode(input.code);
  const entry = getTaxonomyEntry(classified);

  return {
    code: classified,
    request_reference: input.requestReference,
    trace_id: input.traceId,
    retry_safe: isRetrySafe(entry.retryable),
  };
}
