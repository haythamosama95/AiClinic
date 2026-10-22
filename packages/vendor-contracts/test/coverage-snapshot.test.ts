import { describe, expect, it } from "vitest";
import {
  projectCoverageSnapshot,
  validateCoverageSnapshot,
} from "vendor-contracts";
import coverageSnapshotVector from "../vectors/coverage-snapshot.json";

function fullSnapshot(): Record<string, unknown> {
  return {
    contract_version: 1,
    state: "grace",
    reason: "expired",
    suspended: false,
    term: {
      ref: "TERM-009",
      plan_display_name: "Live Monthly",
      starts_at: "2026-01-15T10:00:00.000Z",
      ends_at: "2026-02-15T10:00:00.000Z",
      grace_ends_at: "2026-02-22T10:00:00.000Z",
      allowance: 10000,
      used: 9100,
      band: "90",
      capabilities: ["text"],
      max_cost_class: "standard",
    },
    queued_count: 0,
    held_count: 0,
    coverage_through: "2026-02-15T10:00:00.000Z",
    binding_epoch: 1,
    clinic_seq: 42,
    terms: [{ term_id: "TERM-009" }],
    grace_base_used: 0,
    accounting_seq: 7,
    awaiting_transfer: 0,
    transfer_pending: 0,
  };
}

describe("RM36 R7-A1 projectCoverageSnapshot", () => {
  it("RM36 R7-A1 projectCoverageSnapshot strips the extra keys and term capabilities/max_cost_class, keeps reason, and is idempotent", () => {
    const input = fullSnapshot();
    const before = structuredClone(input);

    const projected = projectCoverageSnapshot(input);

    expect(projected).toEqual({
      contract_version: 1,
      state: "grace",
      reason: "expired",
      suspended: false,
      term: {
        ref: "TERM-009",
        plan_display_name: "Live Monthly",
        starts_at: "2026-01-15T10:00:00.000Z",
        ends_at: "2026-02-15T10:00:00.000Z",
        grace_ends_at: "2026-02-22T10:00:00.000Z",
        allowance: 10000,
        used: 9100,
        band: "90",
      },
      queued_count: 0,
      held_count: 0,
      coverage_through: "2026-02-15T10:00:00.000Z",
      binding_epoch: 1,
      clinic_seq: 42,
    });
    expect(validateCoverageSnapshot(projected)).toEqual({ ok: true });

    // The input is not mutated.
    expect(input).toEqual(before);

    // Idempotent on an already-closed snapshot.
    expect(projectCoverageSnapshot(projected)).toEqual(projected);
  });

  it("keeps a null term and omits reason when the input has none", () => {
    const { reason: _reason, ...withoutReason } = coverageSnapshotVector;
    const projected = projectCoverageSnapshot({
      ...withoutReason,
      term: null,
      accounting_seq: 3,
    });
    expect(projected.term).toBeNull();
    expect("reason" in projected).toBe(false);
    expect("accounting_seq" in projected).toBe(false);
    expect(validateCoverageSnapshot(projected)).toEqual({ ok: true });
  });
});
