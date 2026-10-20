import { clockNowIso, type ClockEnv } from "./clock.js";

export type RecoveryFenceEnv = ClockEnv & { DB: D1Database };

type FenceRow = {
  active: number;
  owner_token: string | null;
  lease_until: string | null;
};

const LEASE_MS = 5 * 60_000;

function leaseUntil(now: string): string {
  return new Date(Date.parse(now) + LEASE_MS).toISOString();
}

async function row(env: RecoveryFenceEnv): Promise<FenceRow | null> {
  try {
    return await env.DB.prepare(
      `SELECT active, owner_token, lease_until FROM abo_recovery_fence WHERE id = 1`,
    ).first<FenceRow>();
  } catch (error) {
    if (/no such table/iu.test(error instanceof Error ? error.message : String(error))) {
      return null;
    }
    throw error;
  }
}

export async function assertAboRecoveryPublished(env: RecoveryFenceEnv): Promise<void> {
  if ((await row(env))?.active === 1) {
    throw new Error("abo_recovery_in_progress");
  }
}

export async function isAboRecoveryActive(env: RecoveryFenceEnv): Promise<boolean> {
  return (await row(env))?.active === 1;
}

export async function acquireAboRecovery(env: RecoveryFenceEnv): Promise<string> {
  const now = await clockNowIso(env);
  const token = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO abo_recovery_fence (
       id, active, generation, owner_token, lease_until, updated_at
     ) VALUES (1, 0, 0, NULL, NULL, ?)`,
  ).bind(now).run();
  const acquired = await env.DB.prepare(
    `UPDATE abo_recovery_fence
     SET active = 1, generation = generation + 1, owner_token = ?, lease_until = ?, updated_at = ?
     WHERE id = 1 AND (active = 0 OR lease_until IS NULL OR lease_until <= ?)`,
  ).bind(token, leaseUntil(now), now, now).run();
  if ((acquired.meta.changes ?? 0) !== 1) {
    throw new Error("abo_recovery_already_owned");
  }
  return token;
}

export async function renewAboRecovery(
  env: RecoveryFenceEnv,
  token: string,
): Promise<void> {
  const now = await clockNowIso(env);
  const renewed = await env.DB.prepare(
    `UPDATE abo_recovery_fence SET lease_until = ?, updated_at = ?
     WHERE id = 1 AND active = 1 AND owner_token = ?`,
  ).bind(leaseUntil(now), now, token).run();
  if ((renewed.meta.changes ?? 0) !== 1) {
    throw new Error("abo_recovery_ownership_lost");
  }
}

export async function publishAboRecovery(
  env: RecoveryFenceEnv,
  token: string,
): Promise<void> {
  const now = await clockNowIso(env);
  const published = await env.DB.prepare(
    `UPDATE abo_recovery_fence
     SET active = 0, owner_token = NULL, lease_until = NULL, updated_at = ?
     WHERE id = 1 AND active = 1 AND owner_token = ?`,
  ).bind(now, token).run();
  if ((published.meta.changes ?? 0) !== 1) {
    throw new Error("abo_recovery_ownership_lost");
  }
}
