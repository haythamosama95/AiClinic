/**
 * P4.2 — coverage_view refresh on the minute cron (H-XW).
 */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import checkoutMigrationSql from "../../migrations/0002_checkout.sql?raw";
import { applySql, runScheduled } from "./harness";
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
