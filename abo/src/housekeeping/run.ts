import { clockNowMs, type ClockEnv } from "../clock.js";

const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const RETENTION_DAYS_MS = 90 * ONE_DAY_MS;
const HMAC_INVALID_RETENTION_DAYS = 30;

export type HousekeepingEnv = ClockEnv & {
  DB: D1Database;
  R2: R2Bucket;
};

export async function runHousekeeping(env: HousekeepingEnv): Promise<void> {
  const nowMs = await clockNowMs(env);
  const retentionCutoff = new Date(nowMs - RETENTION_DAYS_MS).toISOString();

  await env.DB.prepare(
    `DELETE FROM work WHERE state = 'done' AND opened_at < ?`,
  )
    .bind(retentionCutoff)
    .run();

  await env.DB.prepare(`DELETE FROM alert WHERE last_sent_at < ?`)
    .bind(retentionCutoff)
    .run();

  const hmacCutoffDay = new Date(
    nowMs - HMAC_INVALID_RETENTION_DAYS * ONE_DAY_MS,
  )
    .toISOString()
    .slice(0, 10);

  const listed = await env.R2.list({ prefix: "hmac-invalid/" });
  for (const object of listed.objects) {
    const parts = object.key.split("/");
    if (parts.length < 3) {
      continue;
    }
    const day = parts[1];
    if (day !== undefined && day < hmacCutoffDay) {
      await env.R2.delete(object.key);
    }
  }
}
