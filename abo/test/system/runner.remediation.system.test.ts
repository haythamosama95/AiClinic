/** RM08 runner recovery and payment atomicity coverage (R3-C5). */

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { grantIdPaid } from "vendor-contracts";
import successFixture from "../fixtures/paymob/success.json";
import leaseTokenMigrationSql from "../../migrations/0010_work_lease_token.sql?raw";
import {
  applyAllAboMigrations,
  applySql,
  resetHarnessState,
  scriptPaymobInquiry,
  setClock,
  setD1BatchThrows,
  tableCount,
} from "./harness";
import { runDueConfirmWork } from "../../src/work/runner";

type Callback = {
  type: string;
  obj: { id: string | number; [key: string]: unknown };
};

const AMOUNT_MINOR = 800;
const CURRENCY = "EGP";
const CHECKOUT_ID = "01JRM08RUNNER000000000001";
const TXN_ID = 99001;

async function seedCheckout(checkoutId = CHECKOUT_ID): Promise<void> {
  const now = "2026-01-15T09:00:00.000Z";
  await env.DB.prepare(
    `INSERT INTO checkout (
       checkout_id, reference, org_id, created_by_sub, billing_token_jti,
       client_request_id, offer_id, offer_version, plan_id, plan_version,
       term_unit, term_count, allowance_credits, grace_days, grace_cap_rule,
       list_price_minor, charged_price_minor, currency, terms_version,
       billing_contact_version, billing_contact_sha256, opened_with_coverage_through,
       coverage_source, provider_id, initiator, expires_at, contract_version
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      checkoutId,
      `CK-${checkoutId}`,
      "org-rm08-runner",
      "admin-sub",
      "jti-rm08",
      `client-${checkoutId}`,
      "01JHARNESSOFFERPUBLISH001",
      1,
      "plan-pro",
      1,
      "month",
      1,
      100,
      7,
      "proportional",
      AMOUNT_MINOR,
      AMOUNT_MINOR,
      CURRENCY,
      1,
      1,
      "sha256-billing-contact",
      null,
      "none",
      "paymob",
      "administrator",
      "2026-01-15T10:30:00.000Z",
      1,
    )
    .run();
  await env.DB.prepare(
    `INSERT INTO checkout_status (checkout_id, state, last_event_at) VALUES (?, 'open', ?)`,
  )
    .bind(checkoutId, now)
    .run();
  await env.DB.prepare(
    `INSERT INTO paymob_intention (
       checkout_id, intention_id, order_id, client_secret, special_reference, expires_at
     ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(checkoutId, "intention-rm08", "9001", "secret", "special", "2026-01-15T10:30:00.000Z")
    .run();
}

async function seedNotification(
  notificationId: string,
  checkoutId = CHECKOUT_ID,
  workState: "open" | "done" | "none" = "open",
): Promise<void> {
  const fixture = successFixture as Callback;
  const body = JSON.stringify({ type: fixture.type, obj: { ...fixture.obj, id: TXN_ID } });
  const bodyKey = `evidence/${notificationId}`;
  await env.R2.put(bodyKey, body);
  await env.DB.prepare(
    `INSERT INTO notification (
       notification_id, provider_id, channel, hmac_valid, body_r2_key,
       body_sha256, dedupe_key, checkout_id, disposition, adapter_version
     ) VALUES (?, 'paymob', 'processed', 1, ?, 'sha256-body', ?, ?, 'enqueued', 1)`,
  )
    .bind(notificationId, bodyKey, `body:${notificationId}`, checkoutId)
    .run();
  if (workState !== "none") {
    const state = workState;
    await env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts, next_attempt_at,
         lease_until, lease_token, last_error, opened_at
       ) VALUES (?, 'confirm', ?, ?, ?, 0, NULL, NULL, NULL, NULL, '2026-01-15T09:00:00.000Z')`,
    )
      .bind(`work-${notificationId}`, checkoutId, `confirm:${notificationId}`, state)
      .run();
  }
}

beforeEach(async () => {
  await resetHarnessState();
  await applyAllAboMigrations();
  try {
    await applySql(leaseTokenMigrationSql);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!/duplicate column name: lease_token/i.test(message)) {
      throw error;
    }
  }
  await setClock("2026-01-15T09:30:00.000Z");
  await scriptPaymobInquiry("bound_success");
  await seedCheckout();
});

describe("RM08 confirm runner — R3-C5", () => {
  it("R3-C5 recovers a legacy success marker that has no payment", async () => {
    await seedNotification("notify-legacy-seen", CHECKOUT_ID, "done");
    await env.DB.prepare(
      `INSERT INTO paymob_state_seen (dedupe_key, source, first_seen_at)
       VALUES (?, 'confirm', '2026-01-15T09:10:00.000Z')`,
    )
      .bind(`paymob|${TXN_ID}|payment_succeeded|0`)
      .run();

    await runDueConfirmWork(env);

    expect(await tableCount("payment")).toBe(1);
    expect(await tableCount("fact_log")).toBeGreaterThan(0);
    const paid = await env.DB.prepare(
      `SELECT payment_id FROM payment WHERE checkout_id = ?`,
    )
      .bind(CHECKOUT_ID)
      .first<{ payment_id: string }>();
    const grantWork = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant' AND dedupe_key = ?`,
    )
      .bind(`grant:${paid?.payment_id}`)
      .first<{ n: number }>();
    expect(grantWork?.n).toBe(1);
    const work = await env.DB.prepare(
      `SELECT state FROM work WHERE dedupe_key = ?`,
    )
      .bind("confirm:notify-legacy-seen")
      .first<{ state: string }>();
    expect(work?.state).toBe("done");
  });

  it("R3-C5 retains a marker-only notify_body claim pending authenticated redelivery", async () => {
    const bodyHash = "d".repeat(64);
    await env.DB.prepare(
      `INSERT INTO paymob_state_seen (dedupe_key, source, first_seen_at)
       VALUES (?, 'notify_body', '2026-01-15T09:10:00.000Z')`,
    )
      .bind(`notify-body:${bodyHash}`)
      .run();

    await runDueConfirmWork(env);

    const marker = await env.DB.prepare(
      `SELECT 1 FROM paymob_state_seen WHERE dedupe_key = ? AND source = 'notify_body'`,
    )
      .bind(`notify-body:${bodyHash}`)
      .first();
    expect(marker).not.toBeNull();
    expect(await tableCount("notification")).toBe(0);
    expect(await tableCount("payment")).toBe(0);
    expect(await tableCount("work")).toBe(0);
  });

  it("R3-C5 restores missing confirm work from an enqueued body claim", async () => {
    await seedNotification("notify-without-work", CHECKOUT_ID, "none");

    await runDueConfirmWork(env);

    expect(await tableCount("payment")).toBe(1);
    const work = await env.DB.prepare(
      `SELECT state FROM work WHERE dedupe_key = ?`,
    )
      .bind("confirm:notify-without-work")
      .first<{ state: string }>();
    expect(work?.state).toBe("done");
  });

  it("R3-C5 treats a replayed payment identity as one outcome and retains grant work", async () => {
    await seedNotification("notify-first-attempt");
    await runDueConfirmWork(env);
    await seedNotification("notify-replayed-payment");

    await runDueConfirmWork(env);

    expect(await tableCount("payment")).toBe(1);
    const grantWork = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant'`,
    ).first<{ n: number }>();
    expect(grantWork?.n).toBe(1);
  });

  it("R3-C5 does not reopen work when the payment grant is already applied", async () => {
    await seedNotification("notify-applied-grant");
    await runDueConfirmWork(env);
    const payment = await env.DB.prepare(
      `SELECT payment_id FROM payment WHERE checkout_id = ?`,
    )
      .bind(CHECKOUT_ID)
      .first<{ payment_id: string }>();
    const grantId = await grantIdPaid(payment!.payment_id);
    await env.DB.prepare(
      `INSERT INTO grant_outcome (grant_id, result, at) VALUES (?, 'applied', '2026-01-15T09:31:00.000Z')`,
    )
      .bind(grantId)
      .run();
    await env.DB.prepare(`DELETE FROM work WHERE dedupe_key = ?`)
      .bind(`grant:${payment!.payment_id}`)
      .run();
    await seedNotification("notify-applied-grant-replay");

    await runDueConfirmWork(env);

    const grantWork = await env.DB.prepare(
      `SELECT 1 FROM work WHERE dedupe_key = ?`,
    )
      .bind(`grant:${payment!.payment_id}`)
      .first();
    expect(grantWork).toBeNull();
    expect(await tableCount("payment")).toBe(1);
  });

  it("R3-C5 a replaced lease token makes every confirmation batch statement a no-op", async () => {
    await seedNotification("notify-stale-owner");
    const batch = env.DB.batch.bind(env.DB);
    const batchSpy = vi.spyOn(env.DB, "batch").mockImplementation(async (statements) => {
      await env.DB.prepare(
        `UPDATE work SET lease_token = 'replacement-token' WHERE dedupe_key = ?`,
      )
        .bind("confirm:notify-stale-owner")
        .run();
      return batch(statements);
    });

    try {
      await runDueConfirmWork(env);
    } finally {
      batchSpy.mockRestore();
    }

    expect(await tableCount("paymob_state_seen")).toBe(0);
    expect(await tableCount("inquiry_result")).toBe(0);
    expect(await tableCount("payment")).toBe(0);
    expect(await tableCount("fact_log")).toBe(0);
    expect(await tableCount("checkout_event")).toBe(0);
    expect(await tableCount("paymob_txn")).toBe(0);
    const checkoutStatus = await env.DB.prepare(
      `SELECT state FROM checkout_status WHERE checkout_id = ?`,
    )
      .bind(CHECKOUT_ID)
      .first<{ state: string }>();
    expect(checkoutStatus?.state).toBe("open");
    const confirmWork = await env.DB.prepare(
      `SELECT state FROM work WHERE dedupe_key = ?`,
    )
      .bind("confirm:notify-stale-owner")
      .first<{ state: string }>();
    expect(confirmWork?.state).toBe("open");
    const grantWork = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant'`,
    ).first<{ n: number }>();
    expect(grantWork?.n).toBe(0);
  });

  it("R3-C5 leaves no marker, payment, fact, or grant work when the outcome batch fails", async () => {
    await seedNotification("notify-batch-failure");
    setD1BatchThrows(true);

    await runDueConfirmWork(env);

    expect(await tableCount("paymob_state_seen")).toBe(0);
    expect(await tableCount("inquiry_result")).toBe(0);
    expect(await tableCount("payment")).toBe(0);
    const grantWork = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM work WHERE kind = 'grant'`,
    ).first<{ n: number }>();
    expect(grantWork?.n).toBe(0);
  });
});
