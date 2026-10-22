/**
 * P4.2 — coverage_view refresh on the minute cron (H-XW).
 */

import { env } from "cloudflare:test";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { beforeEach, describe, expect, it } from "vitest";
import { handleGetSubscription } from "../../src/clinic-api/billing-reads";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import { applySql, runScheduled } from "./harness";
import {
  refreshCoverageView,
  type CoverageViewEnv,
} from "../../src/coverage/view";
import {
  resetCrossWorkerHarness,
  setupCrossWorkerHarness,
  setupPlatformCoverageFeed,
} from "./cross-worker-harness";

async function ensureCheckoutMigration(): Promise<void> {
  try {
    await applySql(checkoutMigrationSql);
  } catch {
    // Migration not present yet.
  }
}

beforeEach(async () => {
  await resetCrossWorkerHarness();
  await setupCrossWorkerHarness();
  await ensureCheckoutMigration();
});

describe("coverage view cron", () => {
  it("E2E-P4.2-08 minute cron updates coverage_view and ignores an older pair", async () => {
    const orgId = "org-coverage-view-08";
    await setupPlatformCoverageFeed(orgId);

    await runScheduled("* * * * *");

    const row = await env.DB.prepare(
      `SELECT org_id, binding_epoch, clinic_seq, snapshot
       FROM coverage_view WHERE org_id = ?`,
    )
      .bind(orgId)
      .first<{
        org_id: string;
        binding_epoch: number;
        clinic_seq: number;
        snapshot: string;
      }>();
    expect(row).not.toBeNull();
    expect(row!.snapshot.length).toBeGreaterThan(0);

    const cursor = await env.DB.prepare(
      `SELECT feed_seq FROM feed_cursor WHERE id = 1`,
    ).first<{ feed_seq: number }>();
    expect(cursor).not.toBeNull();
    expect(cursor!.feed_seq).toBeGreaterThan(0);

    const raisedEpoch = row!.binding_epoch + 10;
    const raisedSeq = row!.clinic_seq + 10;
    const raisedSnapshot = row!.snapshot;

    await env.DB.prepare(
      `UPDATE coverage_view SET binding_epoch = ?, clinic_seq = ? WHERE org_id = ?`,
    )
      .bind(raisedEpoch, raisedSeq, orgId)
      .run();

    await env.DB.prepare(`UPDATE feed_cursor SET feed_seq = 0 WHERE id = 1`).run();

    await runScheduled("* * * * *");

    const after = await env.DB.prepare(
      `SELECT binding_epoch, clinic_seq, snapshot FROM coverage_view WHERE org_id = ?`,
    )
      .bind(orgId)
      .first<{
        binding_epoch: number;
        clinic_seq: number;
        snapshot: string;
      }>();
    expect(after).not.toBeNull();
    expect(after!.binding_epoch).toBe(raisedEpoch);
    expect(after!.clinic_seq).toBe(raisedSeq);
    expect(after!.snapshot).toBe(raisedSnapshot);
  });
});

type StubPage = {
  events: Record<string, unknown>[];
  next_after: number;
  has_more: boolean;
};

function r7a1Snapshot(bindingEpoch: number, clinicSeq: number, marker: string) {
  return {
    contract_version: 1,
    state: "active",
    suspended: false,
    term: null,
    queued_count: 0,
    held_count: 0,
    coverage_through: marker,
    binding_epoch: bindingEpoch,
    clinic_seq: clinicSeq,
  };
}

function r7a1Event(
  orgId: string,
  feedSeq: number,
  bindingEpoch: number,
  clinicSeq: number,
  marker: string,
): Record<string, unknown> {
  return {
    event_id: crypto.randomUUID(),
    feed_seq: feedSeq,
    org_id: orgId,
    installation_id: crypto.randomUUID(),
    binding_epoch: bindingEpoch,
    clinic_seq: clinicSeq,
    kind: "snapshot",
    at: "2026-04-01T12:00:00.000Z",
    snapshot: r7a1Snapshot(bindingEpoch, clinicSeq, marker),
  };
}

function r7a1Platform(pages: StubPage[]) {
  let index = 0;
  return {
    readCoverageEvents: async (args: Record<string, unknown>) => {
      const page = pages[Math.min(index, pages.length - 1)]!;
      index += 1;
      return {
        result: "ok",
        detail: JSON.stringify({
          after: args.after,
          events: page.events,
          next_after: page.next_after,
          has_more: page.has_more,
        }),
      };
    },
  };
}

async function r7a1Stored(orgId: string) {
  return env.DB.prepare(
    `SELECT binding_epoch, clinic_seq, snapshot FROM coverage_view WHERE org_id = ?`,
  )
    .bind(orgId)
    .first<{ binding_epoch: number; clinic_seq: number; snapshot: string }>();
}

async function r7a1Cursor(): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT feed_seq FROM feed_cursor WHERE id = 1`,
  ).first<{ feed_seq: number }>();
  return row?.feed_seq ?? 0;
}

describe("R7-A1 coverage view admission", () => {
  beforeEach(async () => {
    await env.DB.prepare(`UPDATE feed_cursor SET feed_seq = 0 WHERE id = 1`).run();
  });

  it("R7-A1-01: a late older or equal pair cannot replace a newer stored snapshot", async () => {
    const orgId = crypto.randomUUID();
    await env.DB.prepare(
      `INSERT INTO coverage_view (org_id, binding_epoch, clinic_seq, snapshot)
       VALUES (?, 2, 1, ?)`,
    )
      .bind(orgId, JSON.stringify(r7a1Snapshot(2, 1, "newer")))
      .run();

    await refreshCoverageView({
      DB: env.DB,
      PLATFORM: r7a1Platform([
        {
          events: [
            r7a1Event(orgId, 1, 1, 6, "late-old-epoch"),
            r7a1Event(orgId, 2, 2, 1, "equal-pair"),
          ],
          next_after: 2,
          has_more: false,
        },
      ]),
    } as unknown as CoverageViewEnv);

    const stored = await r7a1Stored(orgId);
    expect(stored).not.toBeNull();
    expect(stored!.binding_epoch).toBe(2);
    expect(stored!.clinic_seq).toBe(1);
    expect(stored!.snapshot).toBe(JSON.stringify(r7a1Snapshot(2, 1, "newer")));
    expect(await r7a1Cursor()).toBe(2);
  });

  it("R7-A1-02: a newer pair replaces the snapshot and advances the cursor", async () => {
    const orgId = crypto.randomUUID();
    await refreshCoverageView({
      DB: env.DB,
      PLATFORM: r7a1Platform([
        {
          events: [r7a1Event(orgId, 1, 1, 5, "first"), r7a1Event(orgId, 2, 1, 6, "second")],
          next_after: 2,
          has_more: false,
        },
      ]),
    } as unknown as CoverageViewEnv);

    const stored = await r7a1Stored(orgId);
    expect(stored!.clinic_seq).toBe(6);
    expect(stored!.snapshot).toBe(JSON.stringify(r7a1Snapshot(1, 6, "second")));
    expect(await r7a1Cursor()).toBe(2);
  });

  it("R7-A1-03: a rejected event is not applied and the cursor does not pass it", async () => {
    const orgId = crypto.randomUUID();
    const rejected = r7a1Event(orgId, 2, 1, 2, "rejected");
    rejected.snapshot = { contract_version: 1 };
    await refreshCoverageView({
      DB: env.DB,
      PLATFORM: r7a1Platform([
        {
          events: [
            r7a1Event(orgId, 1, 1, 1, "accepted"),
            rejected,
            r7a1Event(orgId, 3, 1, 3, "after-rejected"),
          ],
          next_after: 3,
          has_more: false,
        },
      ]),
    } as unknown as CoverageViewEnv);

    const stored = await r7a1Stored(orgId);
    expect(stored!.clinic_seq).toBe(1);
    expect(await r7a1Cursor()).toBe(1);
  });

  it("R7-A1-04: overlapping refreshes leave the highest accepted pair", async () => {
    const orgId = crypto.randomUUID();
    const late = r7a1Platform([
      { events: [r7a1Event(orgId, 1, 1, 6, "late")], next_after: 1, has_more: false },
    ]);
    const newer = r7a1Platform([
      { events: [r7a1Event(orgId, 2, 2, 1, "newer")], next_after: 2, has_more: false },
    ]);
    await Promise.all([
      refreshCoverageView({ DB: env.DB, PLATFORM: newer } as unknown as CoverageViewEnv),
      refreshCoverageView({ DB: env.DB, PLATFORM: late } as unknown as CoverageViewEnv),
    ]);

    const stored = await r7a1Stored(orgId);
    expect(stored!.binding_epoch).toBe(2);
    expect(stored!.clinic_seq).toBe(1);
    expect(stored!.snapshot).toBe(JSON.stringify(r7a1Snapshot(2, 1, "newer")));
    expect(await r7a1Cursor()).toBe(2);
  });

  it("R7-A1 fallback read after transfer observes the new-epoch snapshot", async () => {
    const orgId = crypto.randomUUID();
    await env.DB.prepare(
      `INSERT INTO coverage_view (org_id, binding_epoch, clinic_seq, snapshot)
       VALUES (?, 1, 6, ?)`,
    )
      .bind(orgId, JSON.stringify(r7a1Snapshot(1, 6, "old-epoch")))
      .run();

    await refreshCoverageView({
      DB: env.DB,
      PLATFORM: r7a1Platform([
        {
          events: [r7a1Event(orgId, 1, 2, 1, "new-epoch")],
          next_after: 1,
          has_more: false,
        },
      ]),
    } as unknown as CoverageViewEnv);

    // The platform read is unavailable, so the subscription read falls back to coverage_view.
    const response = await handleGetSubscription(
      {
        DB: env.DB,
        PLATFORM: {
          getCoverage: async () => ({ result: "unavailable", detail: "" }),
        },
      },
      orgId,
      CHANNEL_VERSIONS.aboClinic,
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      snapshot: { binding_epoch: number; clinic_seq: number; coverage_through: string };
    };
    expect(body.snapshot.binding_epoch).toBe(2);
    expect(body.snapshot.clinic_seq).toBe(1);
    expect(body.snapshot.coverage_through).toBe("new-epoch");
  });
});
