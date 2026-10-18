import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import workLeaseMigrationSql from "../../migrations/0010_work_lease_token.sql?raw";
import { applySql } from "./harness";

describe("R3-C5 work lease token migration", () => {
  const suffix = crypto.randomUUID().replaceAll("-", "");
  const workTable = `work_lease_test_${suffix}`;
  const factTable = `fact_log_lease_test_${suffix}`;
  const paymentTable = `payment_lease_test_${suffix}`;
  const seedId = `r3-c5-migration-${suffix}`;
  const isolatedMigrationSql = workLeaseMigrationSql
    .replace(/\bwork\b/gu, workTable)
    .replace("work_lease_token_unique", `${workTable}_lease_token_unique`)
    .replace(/^\s*--.*(?:\r?\n|$)/gmu, "")
    .trim();

  beforeAll(async () => {
    await env.DB.prepare(
      `CREATE TABLE ${workTable} (
         work_id TEXT NOT NULL PRIMARY KEY,
         kind TEXT NOT NULL,
         subject_id TEXT NOT NULL,
         dedupe_key TEXT NOT NULL UNIQUE,
         state TEXT NOT NULL,
         attempts INTEGER NOT NULL,
         next_attempt_at TEXT,
         lease_until TEXT,
         last_error TEXT,
         opened_at TEXT NOT NULL
       )`,
    ).run();
    await env.DB.prepare(
      `CREATE TABLE ${factTable} (
         fact_id TEXT PRIMARY KEY,
         created_at TEXT NOT NULL
       )`,
    ).run();
    await env.DB.prepare(
      `CREATE TABLE ${paymentTable} (
         payment_id TEXT PRIMARY KEY
       )`,
    ).run();
    await env.DB.prepare(
      `INSERT INTO ${workTable} (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, last_error, opened_at
       ) VALUES (?, 'confirm', ?, ?, 'open', 1, NULL, ?, NULL, ?)`,
    )
      .bind(seedId, seedId, seedId, new Date(Date.now() + 60_000).toISOString(), new Date().toISOString())
      .run();
    await applySql(isolatedMigrationSql);
  });

  afterAll(async () => {
    await env.DB.prepare(`DROP TABLE IF EXISTS ${paymentTable}`).run();
    await env.DB.prepare(`DROP TABLE IF EXISTS ${factTable}`).run();
    await env.DB.prepare(`DROP TABLE IF EXISTS ${workTable}`).run();
  });

  it("R3-C5: backfills a distinct token for an already leased row and enforces uniqueness", async () => {
    const row = await env.DB.prepare(
      `SELECT lease_until, lease_token FROM ${workTable} WHERE work_id = ?`,
    )
      .bind(seedId)
      .first<{ lease_until: string | null; lease_token: string | null }>();

    expect(row?.lease_until).not.toBeNull();
    expect(row?.lease_token).toMatch(/^[0-9a-f]{32}$/u);

    await expect(
      env.DB.prepare(
        `INSERT INTO ${workTable} (
           work_id, kind, subject_id, dedupe_key, state, attempts,
           next_attempt_at, lease_until, lease_token, last_error, opened_at
         ) VALUES (?, 'confirm', ?, ?, 'open', 1, NULL, NULL, ?, NULL, ?)`,
      )
        .bind(`${seedId}-duplicate`, `${seedId}-duplicate`, `${seedId}-duplicate`, row!.lease_token, new Date().toISOString())
        .run(),
    ).rejects.toThrow();
  });

  it("R3-C5: a stale owner's fenced batch leaves no fact, payment, or completion", async () => {
    const workId = `${seedId}-stale`;
    const staleToken = "stale-owner-token";
    await env.DB.prepare(
      `INSERT INTO ${workTable} (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, lease_token, last_error, opened_at
       ) VALUES (?, 'confirm', ?, ?, 'open', 1, NULL, ?, ?, NULL, ?)`,
    )
      .bind(workId, workId, workId, new Date(Date.now() + 60_000).toISOString(), staleToken, new Date().toISOString())
      .run();
    await env.DB.prepare(`UPDATE ${workTable} SET lease_token = ? WHERE work_id = ?`)
      .bind("replacement-owner-token", workId)
      .run();

    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO ${factTable} (fact_id, created_at)
         SELECT ?, ?
         WHERE EXISTS (
           SELECT 1 FROM ${workTable} WHERE work_id = ? AND state = 'open' AND lease_token = ?
         )`,
      ).bind(workId, new Date().toISOString(), workId, staleToken),
      env.DB.prepare(
        `INSERT INTO ${paymentTable} (payment_id)
         SELECT ?
         WHERE EXISTS (
           SELECT 1 FROM ${workTable} WHERE work_id = ? AND state = 'open' AND lease_token = ?
         )`,
      ).bind(workId, workId, staleToken),
      env.DB.prepare(
        `UPDATE ${workTable} SET state = 'done', lease_until = NULL, lease_token = NULL
         WHERE work_id = ? AND state = 'open' AND lease_token = ?`,
      ).bind(workId, staleToken),
    ]);

    const result = await env.DB.prepare(
      `SELECT state,
              (SELECT COUNT(*) FROM ${factTable} WHERE fact_id = ?) AS fact_count,
              (SELECT COUNT(*) FROM ${paymentTable} WHERE payment_id = ?) AS payment_count
       FROM ${workTable} WHERE work_id = ?`,
    )
      .bind(workId, workId, workId)
      .first<{ state: string; fact_count: number; payment_count: number }>();

    expect(result).toEqual({ state: "open", fact_count: 0, payment_count: 0 });
  });
});
