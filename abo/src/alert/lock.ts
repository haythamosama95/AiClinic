import type { AlertEnv } from "./index.js";

const R2_LOCK_ALERT_KEY = "AL-16:r2-lock";
const ALERT_CODE = "AL-16";

type LockRule = {
  enabled?: boolean;
  condition?: { type?: string };
  prefix?: string;
};

type LockResponse = {
  success?: boolean;
  result?: { rules?: LockRule[] };
};

function lockIsPresent(body: LockResponse): boolean {
  if (body.success !== true) {
    return false;
  }
  const rules = body.result?.rules ?? [];
  return rules.some(
    (rule) =>
      rule.enabled === true &&
      rule.condition?.type === "Indefinite" &&
      (rule.prefix === "ledger/" || rule.prefix === ""),
  );
}

async function clearR2LockAlert(env: AlertEnv): Promise<void> {
  await env.DB.prepare(
    `UPDATE alert SET active = 0, unsent = 0 WHERE alert_key = ?`,
  )
    .bind(R2_LOCK_ALERT_KEY)
    .run();
}

async function markR2LockAlertDue(env: AlertEnv): Promise<void> {
  const existing = await env.DB.prepare(
    `SELECT alert_key FROM alert WHERE alert_key = ?`,
  )
    .bind(R2_LOCK_ALERT_KEY)
    .first<{ alert_key: string }>();

  if (existing === null) {
    await env.DB.prepare(
      `INSERT INTO alert (
        alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id
      ) VALUES (?, ?, 1, 1, NULL, NULL, ?)`,
    )
      .bind(R2_LOCK_ALERT_KEY, ALERT_CODE, "r2-lock")
      .run();
    return;
  }

  await env.DB.prepare(
    `UPDATE alert SET active = 1, unsent = 1, detail_id = ? WHERE alert_key = ?`,
  )
    .bind("r2-lock", R2_LOCK_ALERT_KEY)
    .run();
}

export async function checkR2BucketLock(env: AlertEnv): Promise<void> {
  const url =
    `https://api.cloudflare.com/client/v4/accounts/${env.CLOUDFLARE_ACCOUNT_ID}` +
    `/r2/buckets/${env.R2_BUCKET_NAME}/lock`;
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: { Authorization: `Bearer ${env.R2_LOCK_READ_TOKEN}` },
    });
    const body = (await response.json()) as LockResponse;
    if (body.success !== true) {
      return;
    }
    if (lockIsPresent(body)) {
      await clearR2LockAlert(env);
      return;
    }
    await markR2LockAlertDue(env);
  } catch {
    // Non-success or thrown fetch leaves the r2-lock alert unchanged.
  }
}
