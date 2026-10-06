import { canonicalize, sha256Hex } from "vendor-contracts";
import { clockNowIso, type ClockEnv } from "../clock.js";

export type AppendEnv = ClockEnv & {
  DB: D1Database;
};

export type OfferRow = {
  offer_id: string;
  code: string;
  contract_version: number;
};

export async function appendOffer(env: AppendEnv, row: OfferRow): Promise<void> {
  const canonicalRow = {
    offer_id: row.offer_id,
    code: row.code,
    contract_version: row.contract_version,
  };
  const createdAt = await clockNowIso(env);
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO offer (offer_id, code, contract_version) VALUES (?, ?, ?)`,
    ).bind(row.offer_id, row.code, row.contract_version),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind("offer", row.offer_id, rowSha256, createdAt),
  ]);
}
