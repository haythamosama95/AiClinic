/**
 * RM36 (R7-PS2) — coverage snapshot state and reason for empty and terminal coverage.
 */

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  projectCoverageSnapshot,
  validateCoverageSnapshot,
} from "vendor-contracts";
import { buildCoverageSnapshot } from "../src/quota-do/coverage";

function hotRow(overrides: Record<string, unknown> = {}) {
  return {
    suspended: 0,
    active_term_id: null,
    used: 0,
    reserved: 0,
    grace_base_used: 0,
    reservations: "[]",
    replay: "{}",
    idempotency: "{}",
    band_emitted: "{}",
    binding_epoch: 1,
    clinic_seq: 4,
    next_alarm_at: null,
    transfer_pending: 0,
    transferred_out_to: null,
    ...overrides,
  };
}

function termRow(overrides: Record<string, unknown>) {
  return {
    term_id: "term-1",
    grant_id: "grant-1",
    origin_grant_id: "grant-1",
    position: 1,
    state: "ended",
    end_reason: null,
    plan_snapshot: "{}",
    allowance: 100,
    used_final: 10,
    duration_unit: "month",
    duration_count: 1,
    grace_days: 7,
    grace_cap: "proportional",
    calendar_start: "2026-04-01T00:00:00.000Z",
    starts_at: "2026-04-01T00:00:00.000Z",
    ends_at: "2026-05-01T00:00:00.000Z",
    grace_ends_at: null,
    ended_at: "2026-05-01T00:00:00.000Z",
    ...overrides,
  };
}

function build(hot: Record<string, unknown>, terms: Record<string, unknown>[]) {
  return buildCoverageSnapshot({
    vendorContractVersion: 1,
    orgId: "org-rm36",
    hot: hotRow(hot) as never,
    terms: terms as never,
  });
}

describe("R7-PS2 coverage snapshot states", () => {
  it("R7-PS2-01: a DO that never applied a term reports state and reason none", () => {
    const snapshot = build({}, []);
    expect(snapshot.state).toBe("none");
    expect(snapshot.reason).toBe("none");
    expect(snapshot.term).toBeNull();
    expect(snapshot.queued_count).toBe(0);
    expect(snapshot.held_count).toBe(0);
  });

  it("R7-PS2-01b: a never-granted DO keeps the suspended overlay", () => {
    const snapshot = build({ suspended: 1 }, []);
    expect(snapshot.state).toBe("none");
    expect(snapshot.suspended).toBe(true);
  });

  it("R7-PS2-02: an exhausted last term reports the exhausted reason", () => {
    const snapshot = build(
      { active_term_id: null },
      [termRow({ state: "exhausted", end_reason: "exhausted", position: 1 })],
    );
    expect(snapshot.state).toBe("exhausted");
    expect(snapshot.reason).toBe("exhausted");
  });

  it("R7-PS2-03: a transferred-out identity reports the transferred reason", () => {
    const snapshot = build({ transferred_out_to: "org-other" }, []);
    expect(snapshot.state).toBe("transferred");
    expect(snapshot.reason).toBe("transferred");
  });

  it("R7-PS2-04: a pending transfer keeps precedence over an active term (R7-PS1 guard)", () => {
    const snapshot = build(
      { transfer_pending: 1 },
      [
        termRow({
          state: "active",
          end_reason: null,
          ended_at: null,
          ends_at: "2026-05-01T00:00:00.000Z",
        }),
      ],
    );
    expect(snapshot.state).toBe("transfer_pending");
    expect(snapshot.reason).toBe("transfer_pending");
    expect(snapshot.term).not.toBeNull();
  });
});

describe("RM36 R7-A1 platform coverage egress", () => {
  // The four egress sites (feed, readCoverageEvents, getCoverage, coverage-read)
  // apply projectCoverageSnapshot to the stored or DO-built snapshot. The Workers
  // routes themselves run only in the Workers suites; this test covers the state
  // matrix through the same projection and checks each egress is wired.
  const egressFiles = [
    { file: "../src/worker.ts", minCalls: 1 },
    { file: "../src/vendor/entrypoint.ts", minCalls: 2 },
    { file: "../src/coverage-read/index.ts", minCalls: 1 },
  ];

  it("RM36 R7-A1: feed, readCoverageEvents, getCoverage and coverage-read snapshots pass validateCoverageSnapshot for none, active, grace, lapsed, exhausted, reversed, transferred and transfer_pending", () => {
    for (const { file, minCalls } of egressFiles) {
      const source = readFileSync(new URL(file, import.meta.url), "utf8");
      const calls = source.split("projectCoverageSnapshot(").length - 1;
      expect(calls, file).toBeGreaterThanOrEqual(minCalls);
    }

    const cases: Array<[string, Record<string, unknown>, Record<string, unknown>[]]> = [
      ["none", {}, []],
      [
        "active",
        { active_term_id: "term-1", used: 10, accounting_seq: 7 },
        [termRow({ state: "active", end_reason: null, ended_at: null })],
      ],
      [
        "grace",
        { active_term_id: "term-1", used: 10, accounting_seq: 7 },
        [
          termRow({
            state: "grace",
            end_reason: null,
            ended_at: null,
            grace_ends_at: "2026-05-08T00:00:00.000Z",
          }),
        ],
      ],
      [
        "lapsed",
        {},
        [termRow({ state: "ended", end_reason: "expired" })],
      ],
      [
        "exhausted",
        {},
        [termRow({ state: "exhausted", end_reason: "exhausted" })],
      ],
      [
        "reversed",
        {},
        [termRow({ state: "ended", end_reason: "reversed" })],
      ],
      ["transferred", { transferred_out_to: "org-other" }, []],
      [
        "transfer_pending",
        { transfer_pending: 1, active_term_id: "term-1", used: 10 },
        [termRow({ state: "active", end_reason: null, ended_at: null })],
      ],
    ];

    for (const [state, hot, terms] of cases) {
      const built = build(hot, terms);
      expect(built.state, state).toBe(state);

      // Egress order: DO-built snapshot, then JSON round trip as stored, then projection.
      const stored = JSON.parse(JSON.stringify(built)) as Record<string, unknown>;
      const projected = projectCoverageSnapshot(stored);
      expect(validateCoverageSnapshot(projected), state).toEqual({ ok: true });
      expect(projected.state, state).toBe(state);
    }
  });

  it("RM36 R7-A1: D1 coverage_event and the DO outbox keep terms and accounting_seq", () => {
    const built = build(
      { active_term_id: "term-1", used: 10, accounting_seq: 7 },
      [termRow({ state: "active", end_reason: null, ended_at: null })],
    );
    // The stored and outboxed copy is the full DO-built snapshot.
    expect(Array.isArray(built.terms)).toBe(true);
    expect((built.terms as unknown[]).length).toBe(1);
    expect(built.accounting_seq).toBe(7);

    // Projecting for egress must not strip the internal copy.
    projectCoverageSnapshot(built);
    expect(Array.isArray(built.terms)).toBe(true);
    expect(built.accounting_seq).toBe(7);

    // Write paths (DO builder, outbox, D1 coverage_event) never project.
    for (const file of [
      "../src/quota-do/coverage.ts",
      "../src/quota-do/index.ts",
    ]) {
      const source = readFileSync(new URL(file, import.meta.url), "utf8");
      expect(source.includes("projectCoverageSnapshot"), file).toBe(false);
    }
  });
});
