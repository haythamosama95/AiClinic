import type { BillingClaims } from "./auth.js";
import { clinicErrorResponse } from "./version.js";

export type RateSuccess = {
  ok: true;
};

export type RateFailure = {
  ok: false;
  response: Response;
};

async function ensureTokenUseTable(db: D1Database): Promise<void> {
  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS token_use (
        jti TEXT NOT NULL PRIMARY KEY,
        org_id TEXT NOT NULL,
        hits INTEGER NOT NULL
      )`,
    )
    .run();
  await db
    .prepare(
      `CREATE INDEX IF NOT EXISTS token_use_org_id ON token_use (org_id)`,
    )
    .run();
}

export async function checkTokenRate(
  db: D1Database,
  claims: BillingClaims,
  contractVersion: number,
): Promise<RateSuccess | RateFailure> {
  await ensureTokenUseTable(db);
  const existing = await db
    .prepare(`SELECT hits FROM token_use WHERE jti = ?`)
    .bind(claims.jti)
    .first<{ hits: number }>();

  if (existing !== null && existing.hits >= 60) {
    return {
      ok: false,
      response: clinicErrorResponse("rate_limited", 429, contractVersion),
    };
  }

  if (existing === null) {
    await db
      .prepare(
        `INSERT INTO token_use (jti, org_id, hits) VALUES (?, ?, 1)`,
      )
      .bind(claims.jti, claims.org)
      .run();
  } else {
    await db
      .prepare(`UPDATE token_use SET hits = hits + 1 WHERE jti = ?`)
      .bind(claims.jti)
      .run();
  }

  return { ok: true };
}
