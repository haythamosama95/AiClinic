import { expect, vi } from "vitest";
import type { CreditIdempotencyState } from "../../src/quota-do";

/**
 * Catalog-pinned creditUsage profile. Omit `partial` / `idempotencyState` /
 * `usage` when the catalog does not pin that field; do not invent values.
 */
export type CreditUsageExpectation = {
  times: number;
  partial?: boolean;
  idempotencyState?: CreditIdempotencyState;
  usage?: { tokens: number; cost?: number };
};

/** S10-001 completed settlement (and "as S10-001" / completed tokens-30 paths). */
export const COMPLETED_CREDIT: CreditUsageExpectation = {
  times: 1,
  partial: false,
  usage: { tokens: 30, cost: 0.005 },
};

/** S10-007: one credit, partial false; usage / idempotencyState not pinned. */
export const COMPLETED_PARTIAL_FALSE: CreditUsageExpectation = {
  times: 1,
  partial: false,
};

/** S10-003 / S10-004: failed partial consume, zero usage. */
export const FAILED_PARTIAL_ZERO: CreditUsageExpectation = {
  times: 1,
  partial: true,
  idempotencyState: "failed",
  usage: { tokens: 0, cost: 0 },
};

/** S10-005 / S10-010 / S10-012: failed partial consume; usage not pinned. */
export const FAILED_PARTIAL: CreditUsageExpectation = {
  times: 1,
  partial: true,
  idempotencyState: "failed",
};

/** S10-009: provider_rejected full consume. */
export const FAILED_FULL_CONSUME: CreditUsageExpectation = {
  times: 1,
  partial: false,
  idempotencyState: "failed",
};

/** S10-020…S10-028 validation_failed broker/worker credit. */
export const VALIDATION_FAILED_CREDIT: CreditUsageExpectation = {
  times: 1,
  partial: false,
  idempotencyState: "failed",
  usage: { tokens: 30, cost: 0.005 },
};

/**
 * S10-032: broker failed credit, exactly once. Catalog pins partial false;
 * usage payload is not pinned on the credit call.
 */
export const VALIDATION_FAILED_SINGLE_CREDIT: CreditUsageExpectation = {
  times: 1,
  partial: false,
  idempotencyState: "failed",
};

/** S10-013: streamed-chars cancel credit. */
export const CANCELLED_STREAMED: CreditUsageExpectation = {
  times: 1,
  partial: true,
  idempotencyState: "cancelled",
  usage: { tokens: 8, cost: 0.0016 },
};

/** S10-014: zero-usage cancel credit. */
export const CANCELLED_ZERO: CreditUsageExpectation = {
  times: 1,
  partial: true,
  idempotencyState: "cancelled",
  usage: { tokens: 0, cost: 0 },
};

/** S10-016 / S10-018 / S10-019 replay: no credit. */
export const NO_CREDIT: CreditUsageExpectation = { times: 0 };

/**
 * HARNESS-GAP: creditUsage is not on the frozen barrel. Catalog stage-10
 * pins call count / partial / idempotencyState / usage via this spy.
 */
export async function spyCreditUsage() {
  const creditMod = await import("../../src/credit");
  return vi.spyOn(creditMod, "creditUsage");
}

export type CreditUsageSpy = Awaited<ReturnType<typeof spyCreditUsage>>;

function creditCallInput(
  spy: CreditUsageSpy,
  callIndex: number,
): Record<string, unknown> {
  const input = spy.mock.calls[callIndex]?.[0] as
    | Record<string, unknown>
    | undefined;
  expect(input).toBeDefined();
  return input!;
}

export function assertCreditUsage(
  spy: CreditUsageSpy,
  expected: CreditUsageExpectation,
): void {
  expect(spy).toHaveBeenCalledTimes(expected.times);
  if (expected.times === 0) {
    return;
  }

  for (let i = 0; i < expected.times; i += 1) {
    const input = creditCallInput(spy, i);
    if (expected.partial !== undefined) {
      expect(input.partial).toBe(expected.partial);
    }
    if (expected.idempotencyState !== undefined) {
      expect(input.idempotencyState).toBe(expected.idempotencyState);
    }
    if (expected.usage !== undefined) {
      const usage = input.usage as
        | { tokens?: number; cost?: number }
        | undefined;
      expect(usage?.tokens).toBe(expected.usage.tokens);
      if (expected.usage.cost !== undefined) {
        expect(Number(usage?.cost)).toBeCloseTo(expected.usage.cost, 6);
      }
    }
  }
}
