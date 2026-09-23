/**
 * G4 — Billing period close (scheduled job).
 * M1 — credit_price fixtures withdrawn; period-close issues no invoices until M2
 * (purchase-proof / paid-amount pricing). Do not assert G-era credits×price invoices.
 */
import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import planCatalogueSql from "../migrations/20260911120000_plan_catalogue.sql?raw";
import quotaWeightMigrationSql from "../migrations/20260911180000_usage_rollup_quota_weight.sql?raw";
import invoiceMigrationSql from "../migrations/20260911200000_invoice.sql?raw";
import { runPeriodClose } from "../src/period-close";
import * as rollup from "../src/rollup";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

const FIXTURE_PERIOD = "2026-08";
const FIXTURE_PERIOD_START = "2026-08-01T00:00:00.000Z";
const FIXTURE_PERIOD_END = "2026-09-01T00:00:00.000Z";
const FIXTURE_ORG_ID = "org-period-close-001";
const FIXTURE_INSTALLATION_1 = "inst-close-001";
const FIXTURE_INSTALLATION_2 = "inst-close-002";

type UsageRollupRow = {
  rollup_id: string;
  dimensions: string;
  request_count: number;
  tokens: number;
  cost: number;
  quota_weight: number;
};

type InvoiceRow = {
  installation_id: string;
  period: string;
  credits_consumed: number;
  total: number;
  status: string;
  issued_at: string;
};

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);

  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function rollupIdFor(installationId: string, period: string): Promise<string> {
  const dimensions = JSON.stringify({ installation_id: installationId, period });
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(dimensions),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function seedInstallation(installationId: string): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO installation (
      installation_id, org_id, display_name, status, region, enrolled_at
    ) VALUES (?, ?, ?, 'active', 'us-east-1', ?)`,
  )
    .bind(
      installationId,
      FIXTURE_ORG_ID,
      `Close Clinic ${installationId}`,
      FIXTURE_PERIOD_START,
    )
    .run();
}

async function seedEntitlement(
  installationId: string,
  status: string = "active",
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO entitlement (
      entitlement_id, installation_id, plan, period_start, period_end,
      request_quota, token_budget, cost_budget, credit_budget,
      allowed_capabilities, soft_threshold, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      `ent-${installationId}`,
      installationId,
      "professional",
      FIXTURE_PERIOD_START,
      FIXTURE_PERIOD_END,
      10_000,
      10_000_000,
      1_000,
      10_000,
      JSON.stringify(["ai.access"]),
      0.8,
      status,
    )
    .run();
}

async function seedUsageRollup(options: {
  installationId: string;
  period?: string;
  quotaWeight: number;
  requestCount?: number;
  tokens?: number;
  cost?: number;
}): Promise<void> {
  const period = options.period ?? FIXTURE_PERIOD;
  const dimensions = JSON.stringify({
    installation_id: options.installationId,
    period,
  });
  const rollupId = await rollupIdFor(options.installationId, period);
  await env.DB.prepare(
    `INSERT INTO usage_rollup (
       rollup_id, dimensions, request_count, tokens, cost, quota_weight
     ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      rollupId,
      dimensions,
      options.requestCount ?? 1,
      options.tokens ?? 999_999,
      options.cost ?? 999.99,
      options.quotaWeight,
    )
    .run();
}

async function fetchAllUsageRollup(): Promise<UsageRollupRow[]> {
  const result = await env.DB.prepare(
    `SELECT rollup_id, dimensions, request_count, tokens, cost, quota_weight
     FROM usage_rollup
     ORDER BY rollup_id`,
  ).all<UsageRollupRow>();
  return result.results ?? [];
}

async function countInvoices(): Promise<number> {
  const row = await env.DB.prepare("SELECT COUNT(*) AS count FROM invoice").first<{
    count: number;
  }>();
  return row?.count ?? 0;
}

async function fetchInvoice(
  installationId: string,
  period: string = FIXTURE_PERIOD,
): Promise<InvoiceRow | null> {
  return env.DB.prepare(
    `SELECT installation_id, period, credits_consumed, total, status, issued_at
     FROM invoice
     WHERE installation_id = ? AND period = ?`,
  )
    .bind(installationId, period)
    .first<InvoiceRow>();
}

async function clearPeriodCloseTables(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM invoice"),
    env.DB.prepare("DELETE FROM usage_rollup"),
    env.DB.prepare("DELETE FROM entitlement"),
    env.DB.prepare("DELETE FROM installation"),
  ]);
}

beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, planCatalogueSql);
  await applyPlatformSchema(env.DB, quotaWeightMigrationSql);
  await applyPlatformSchema(env.DB, invoiceMigrationSql);
});

beforeEach(async () => {
  await clearPeriodCloseTables();
});

describe("close_one_invoice_per_active_installation", () => {
  it("issues no invoice until M2 owns paid-amount pricing (M1 interim no-op)", async () => {
    await seedInstallation(FIXTURE_INSTALLATION_1);
    await seedEntitlement(FIXTURE_INSTALLATION_1);
    await seedUsageRollup({
      installationId: FIXTURE_INSTALLATION_1,
      quotaWeight: 100,
    });

    await runPeriodClose({ db: env.DB, period: FIXTURE_PERIOD });

    expect(await countInvoices()).toBe(0);
    expect(await fetchInvoice(FIXTURE_INSTALLATION_1)).toBeNull();
  });
});

describe("close_one_invoice_each_of_two_active_installations", () => {
  it("issues no invoices for either installation until M2", async () => {
    await seedInstallation(FIXTURE_INSTALLATION_1);
    await seedInstallation(FIXTURE_INSTALLATION_2);
    await seedEntitlement(FIXTURE_INSTALLATION_1);
    await seedEntitlement(FIXTURE_INSTALLATION_2);
    await seedUsageRollup({
      installationId: FIXTURE_INSTALLATION_1,
      quotaWeight: 40,
    });
    await seedUsageRollup({
      installationId: FIXTURE_INSTALLATION_2,
      quotaWeight: 60,
    });

    await runPeriodClose({ db: env.DB, period: FIXTURE_PERIOD });

    expect(await countInvoices()).toBe(0);
    expect(await fetchInvoice(FIXTURE_INSTALLATION_1)).toBeNull();
    expect(await fetchInvoice(FIXTURE_INSTALLATION_2)).toBeNull();
  });
});

describe("close_rerun_idempotent", () => {
  it("remains a no-op on re-run with no invoice rows", async () => {
    await seedInstallation(FIXTURE_INSTALLATION_1);
    await seedEntitlement(FIXTURE_INSTALLATION_1);
    await seedUsageRollup({
      installationId: FIXTURE_INSTALLATION_1,
      quotaWeight: 25,
    });

    await runPeriodClose({ db: env.DB, period: FIXTURE_PERIOD });
    expect(await countInvoices()).toBe(0);

    await runPeriodClose({ db: env.DB, period: FIXTURE_PERIOD });

    expect(await countInvoices()).toBe(0);
    expect(await fetchInvoice(FIXTURE_INSTALLATION_1)).toBeNull();
  });
});

describe("close_zero_consumption_no_invoice", () => {
  it("issues no invoice when quota_weight sums to zero", async () => {
    await seedInstallation(FIXTURE_INSTALLATION_1);
    await seedEntitlement(FIXTURE_INSTALLATION_1);
    await seedUsageRollup({
      installationId: FIXTURE_INSTALLATION_1,
      quotaWeight: 0,
    });

    await runPeriodClose({ db: env.DB, period: FIXTURE_PERIOD });

    expect(await countInvoices()).toBe(0);
    expect(await fetchInvoice(FIXTURE_INSTALLATION_1)).toBeNull();
  });
});

describe("close_freezes_usage_rollup_without_rewriting_rows", () => {
  it("leaves usage_rollup unchanged and does not invoke runRollup", async () => {
    const runRollupSpy = vi.spyOn(rollup, "runRollup");

    await seedInstallation(FIXTURE_INSTALLATION_1);
    await seedEntitlement(FIXTURE_INSTALLATION_1);
    await seedUsageRollup({
      installationId: FIXTURE_INSTALLATION_1,
      quotaWeight: 30,
    });

    const before = await fetchAllUsageRollup();
    await runPeriodClose({ db: env.DB, period: FIXTURE_PERIOD });
    const after = await fetchAllUsageRollup();

    expect(after).toEqual(before);
    expect(runRollupSpy).not.toHaveBeenCalled();
    expect(await countInvoices()).toBe(0);

    runRollupSpy.mockRestore();
  });
});
