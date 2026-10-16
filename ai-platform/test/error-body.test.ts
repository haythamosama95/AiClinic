import { describe, expect, it } from "vitest";
import { buildErrorBody } from "../src/errors";

const SAMPLE_CODES = [
  "unauthenticated",
  "installation_suspended",
  "forbidden_capability",
  "rate_limited",
  "quota_exhausted",
  "request_too_large",
  "context_required",
  "context_invalid",
  "conversation_budget_exhausted",
  "capability_unknown",
  "capability_retired",
  "capability_disabled",
  "provider_unavailable",
  "provider_rejected",
  "validation_failed",
  "timeout",
  "internal_error",
] as const;

const REQUEST_REFERENCE = "7QK4-2B9F";
const TRACE_ID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";

describe("error body shape (T20)", () => {
  it.each(SAMPLE_CODES)(
    "builds exactly {code, request_reference, trace_id, retry_safe} for %s",
    (code) => {
      const body = buildErrorBody({
        code,
        requestReference: REQUEST_REFERENCE,
        traceId: TRACE_ID,
      });

      expect(Object.keys(body).sort()).toEqual([
        "code",
        "request_reference",
        "retry_safe",
        "trace_id",
      ]);
      expect(body.code).toBe(code);
      expect(body.request_reference).toBe(REQUEST_REFERENCE);
      expect(body.trace_id).toBe(TRACE_ID);
      expect(typeof body.retry_safe).toBe("boolean");
    },
  );
});
