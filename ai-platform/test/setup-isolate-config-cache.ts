import { beforeEach } from "vitest";
import { env } from "cloudflare:test";
import { isolateConfigCache } from "../src/config-cache";

/**
 * Unit fixtures clear `issuer_key` and `tenant_binding` after their own
 * schema apply. Create the tables when that apply did not.
 */
async function ensureIssuerBindingTables(): Promise<void> {
  const db = (env as { DB?: D1Database }).DB;
  if (db === undefined) {
    return;
  }
  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS issuer_key (
        kid TEXT PRIMARY KEY NOT NULL,
        issuer TEXT NOT NULL,
        public_key TEXT NOT NULL,
        status TEXT NOT NULL,
        not_before TEXT NOT NULL,
        not_after TEXT NOT NULL,
        registered_by TEXT NOT NULL,
        assertion_sha256 TEXT NOT NULL
      )`,
    )
    .run();
  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS tenant_binding (
        org_id TEXT NOT NULL,
        installation_id TEXT NOT NULL,
        epoch INTEGER NOT NULL,
        status TEXT NOT NULL,
        retired_at TEXT,
        reason TEXT,
        created_at TEXT NOT NULL,
        PRIMARY KEY (org_id, epoch)
      )`,
    )
    .run();
  await db
    .prepare(
      `CREATE UNIQUE INDEX IF NOT EXISTS tenant_binding_one_live_org
       ON tenant_binding (org_id)
       WHERE status IN ('active', 'held_for_transfer')`,
    )
    .run();
}

beforeEach(async () => {
  isolateConfigCache.clear();
  await ensureIssuerBindingTables();
});
