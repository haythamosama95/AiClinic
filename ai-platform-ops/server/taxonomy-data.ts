/** Static copy of ai-platform/src/errors.ts taxonomy — do not import Workers code. */
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

export type TaxonomyEntry = {
  code: TaxonomyCode;
  httpStatus: number;
  retryable: string;
  consumesQuota: string;
};

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

export const ALL_TAXONOMY_CODES = Object.keys(TAXONOMY) as TaxonomyCode[];

export function getTaxonomyEntry(code: TaxonomyCode): TaxonomyEntry {
  return TAXONOMY[code];
}

export function isTaxonomyCode(code: string): code is TaxonomyCode {
  return Object.hasOwn(TAXONOMY, code);
}
