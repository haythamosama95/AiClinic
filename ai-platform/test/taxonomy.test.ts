import { describe, expect, it } from "vitest";
import {
  buildErrorBody,
  classifyErrorCode,
  getTaxonomyEntry,
  isRetrySafe,
  liveHttpStatusForCode,
  supplementaryFieldsForCode,
} from "../src/errors";

const TAXONOMY_TABLE = [
  {
    code: "unauthenticated",
    httpStatus: 401,
    retryable: "After re-mint",
    consumesQuota: "No",
  },
  {
    code: "installation_suspended",
    httpStatus: 403,
    retryable: "No",
    consumesQuota: "No",
  },
  {
    code: "forbidden_capability",
    httpStatus: 403,
    retryable: "No",
    consumesQuota: "No",
  },
  {
    code: "rate_limited",
    httpStatus: 429,
    retryable: "Yes, after `retry_after`",
    consumesQuota: "No",
  },
  {
    code: "quota_exhausted",
    httpStatus: 429,
    retryable: "Not until period reset",
    consumesQuota: "No",
  },
  {
    code: "request_too_large",
    httpStatus: 413,
    retryable: "No",
    consumesQuota: "No",
  },
  {
    code: "context_required",
    httpStatus: 422,
    retryable: "Yes, after resolving",
    consumesQuota: "No",
  },
  {
    code: "context_invalid",
    httpStatus: 422,
    retryable: "No",
    consumesQuota: "No",
  },
  {
    code: "conversation_budget_exhausted",
    httpStatus: 409,
    retryable: "No, within this conversation",
    consumesQuota: "No",
  },
  {
    code: "capability_unknown",
    httpStatus: 404,
    retryable: "No",
    consumesQuota: "No",
  },
  {
    code: "capability_retired",
    httpStatus: 404,
    retryable: "No",
    consumesQuota: "No",
  },
  {
    code: "capability_disabled",
    httpStatus: 503,
    retryable: "Later",
    consumesQuota: "No",
  },
  {
    code: "provider_unavailable",
    httpStatus: 503,
    retryable: "Yes",
    consumesQuota: "Partially, recorded",
  },
  {
    code: "provider_rejected",
    httpStatus: 422,
    retryable: "No",
    consumesQuota: "Yes",
  },
  {
    code: "validation_failed",
    httpStatus: 422,
    retryable: "Yes, at user discretion",
    consumesQuota: "Yes",
  },
  {
    code: "cancelled",
    httpStatus: 499,
    retryable: "—",
    consumesQuota: "Partially, recorded",
  },
  {
    code: "timeout",
    httpStatus: 504,
    retryable: "Yes",
    consumesQuota: "Partially, recorded",
  },
  {
    code: "internal_error",
    httpStatus: 500,
    retryable: "Yes",
    consumesQuota: "No",
  },
] as const;

describe.each(TAXONOMY_TABLE)(
  "taxonomy per-code contract (T1–T18)",
  ({ code, httpStatus, retryable, consumesQuota }) => {
    it(`${code} maps to HTTP ${httpStatus} with retryability "${retryable}" and quota "${consumesQuota}"`, () => {
      const entry = getTaxonomyEntry(code);

      expect(entry.httpStatus).toBe(httpStatus);
      expect(entry.retryable).toBe(retryable);
      expect(entry.consumesQuota).toBe(consumesQuota);

      const body = buildErrorBody({
        code,
        requestReference: "7QK4-2B9F",
        traceId: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
      });

      expect(body.code).toBe(code);
    });
  },
);

describe("taxonomy unrecognised code (T19)", () => {
  it("treats an unrecognised code as internal_error and never surfaces it raw", () => {
    const classified = classifyErrorCode("totally_unknown_provider_code");
    const entry = getTaxonomyEntry(classified);

    expect(classified).toBe("internal_error");
    expect(entry.httpStatus).toBe(500);
    expect(classified).not.toBe("totally_unknown_provider_code");
  });
});

describe("taxonomy context_requested (T24)", () => {
  it("refuses to build an error body for context_requested", () => {
    expect(() =>
      buildErrorBody({
        code: "context_requested",
        requestReference: "7QK4-2B9F",
        traceId: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
      }),
    ).toThrow();
  });
});

describe("taxonomy 429 payload distinction (T26)", () => {
  const retryAfter = 120;
  const periodReset = "2026-08-01T00:00:00.000Z";

  it("rate_limited carries retry_after and not the period reset instant", () => {
    const fields = supplementaryFieldsForCode("rate_limited", {
      retryAfter,
      periodReset,
    });

    expect(fields).toHaveProperty("retry_after", retryAfter);
    expect(fields).not.toHaveProperty("period_reset");
  });

  it("quota_exhausted carries the period reset instant and not retry_after", () => {
    const fields = supplementaryFieldsForCode("quota_exhausted", {
      retryAfter,
      periodReset,
    });

    expect(fields).toHaveProperty("period_reset", periodReset);
    expect(fields).not.toHaveProperty("retry_after");
  });

  it("quota_exhausted omits period_reset when no actionable value is supplied", () => {
    expect(supplementaryFieldsForCode("quota_exhausted", {})).not.toHaveProperty(
      "period_reset",
    );
    expect(
      supplementaryFieldsForCode("quota_exhausted", { periodReset: "" }),
    ).not.toHaveProperty("period_reset");
  });
});

describe("taxonomy retry_safe mapping (T29)", () => {
  it("is false for Retryable values No and —", () => {
    expect(isRetrySafe("No")).toBe(false);
    expect(isRetrySafe("—")).toBe(false);

    for (const { code, retryable } of TAXONOMY_TABLE) {
      if (retryable === "No" || retryable === "—") {
        const body = buildErrorBody({
          code,
          requestReference: "7QK4-2B9F",
          traceId: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
        });
        expect(body.retry_safe).toBe(false);
      }
    }
  });

  it("is true for every other Retryable value", () => {
    const trueValues = [
      "After re-mint",
      "Yes, after `retry_after`",
      "Not until period reset",
      "Yes, after resolving",
      "No, within this conversation",
      "Later",
      "Yes",
      "Yes, at user discretion",
    ] as const;

    for (const retryable of trueValues) {
      expect(isRetrySafe(retryable)).toBe(true);
    }

    for (const { code, retryable } of TAXONOMY_TABLE) {
      if (retryable !== "No" && retryable !== "—") {
        const body = buildErrorBody({
          code,
          requestReference: "7QK4-2B9F",
          traceId: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
        });
        expect(body.retry_safe).toBe(true);
      }
    }
  });
});

describe("taxonomy cancelled live socket rule (T16)", () => {
  it("classifies cancelled to 499 for journaling but never emits 499 on a live socket", () => {
    const entry = getTaxonomyEntry("cancelled");
    expect(entry.httpStatus).toBe(499);

    const liveStatus = liveHttpStatusForCode("cancelled");
    expect(liveStatus).not.toBe(499);
    expect(liveStatus).toBeNull();
  });
});
