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
  const admitted = await db
    .prepare(
      `INSERT INTO token_use (jti, org_id, hits) VALUES (?, ?, 1)
       ON CONFLICT (jti) DO UPDATE SET hits = token_use.hits + 1
       WHERE token_use.hits < 60
       RETURNING jti`,
    )
    .bind(claims.jti, claims.org)
    .first<{ jti: string }>();

  if (admitted === null) {
    return {
      ok: false,
      response: clinicErrorResponse("rate_limited", 429, contractVersion),
    };
  }

  return { ok: true };
}
