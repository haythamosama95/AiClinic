import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";

export type AlertEnv = ClockEnv & {
  DB: D1Database;
  ALERT_EMAIL_TO: string;
  SEND_EMAIL: {
    send(message: {
      from: string;
      to: string;
      subject: string;
      text: string;
    }): Promise<void>;
  };
  CLOUDFLARE_ACCOUNT_ID: string;
  R2_BUCKET_NAME: string;
  R2_LOCK_READ_TOKEN: string;
};

const ONE_HOUR_MS = 60 * 60 * 1000;
const ONE_DAY_MS = 24 * ONE_HOUR_MS;

const EXPORT_LAG_ALERT_KEY = "AL-16:export-lag";
const R2_LOCK_ALERT_KEY = "AL-16:r2-lock";
const ALERT_CODE = "AL-16";

type AlertRow = {
  alert_key: string;
  code: string;
  active: number;
  unsent: number;
  last_sent_at: string | null;
  next_send_at: string | null;
  detail_id: string;
};

function alertEmailText(detailId: string): string {
  return `${ALERT_CODE} ${detailId}`;
}

async function readAlert(
  db: D1Database,
  alertKey: string,
): Promise<AlertRow | null> {
  return db
    .prepare(
      `SELECT alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id
       FROM alert WHERE alert_key = ?`,
    )
    .bind(alertKey)
    .first<AlertRow>();
}

async function activateExportLagAlert(
  env: AlertEnv,
  detailId: string,
): Promise<void> {
  const existing = await readAlert(env.DB, EXPORT_LAG_ALERT_KEY);
  if (existing === null) {
    await env.DB.prepare(
      `INSERT INTO alert (
        alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id
      ) VALUES (?, ?, 1, 1, NULL, NULL, ?)`,
    )
      .bind(EXPORT_LAG_ALERT_KEY, ALERT_CODE, detailId)
      .run();
    return;
  }

  const unsent =
    existing.active === 0 ||
    existing.unsent === 1 ||
    existing.last_sent_at === null
      ? 1
      : existing.unsent;

  await env.DB.prepare(
    `UPDATE alert
     SET active = 1, unsent = ?, detail_id = ?
     WHERE alert_key = ?`,
  )
    .bind(unsent, detailId, EXPORT_LAG_ALERT_KEY)
    .run();
}

async function clearAlert(env: AlertEnv, alertKey: string): Promise<void> {
  const existing = await readAlert(env.DB, alertKey);
  if (existing === null) {
    return;
  }
  await env.DB.prepare(
    `UPDATE alert SET active = 0, unsent = 0 WHERE alert_key = ?`,
  )
    .bind(alertKey)
    .run();
}

type OldestUnexported = {
  fact_seq: number;
  created_at: string;
};

async function oldestUnexportedFact(
  db: D1Database,
): Promise<OldestUnexported | null> {
  return db
    .prepare(
      `SELECT fl.fact_seq, fl.created_at
       FROM fact_log fl
       LEFT JOIN fact_export fe ON fl.fact_seq = fe.fact_seq
       WHERE fe.fact_seq IS NULL
       ORDER BY fl.fact_seq ASC
       LIMIT 1`,
    )
    .first<OldestUnexported>();
}

async function clearExportLagWhenResolved(env: AlertEnv): Promise<void> {
  const existing = await readAlert(env.DB, EXPORT_LAG_ALERT_KEY);
  if (existing === null || existing.active === 0) {
    return;
  }
  if (existing.last_sent_at !== null) {
    return;
  }
  await clearAlert(env, EXPORT_LAG_ALERT_KEY);
}

export async function markExportLagIfDue(env: AlertEnv): Promise<void> {
  const nowMs = await clockNowMs(env);
  const oldest = await oldestUnexportedFact(env.DB);
  if (oldest !== null) {
    const createdMs = Date.parse(oldest.created_at);
    if (nowMs - createdMs > ONE_HOUR_MS) {
      await activateExportLagAlert(env, String(oldest.fact_seq));
      return;
    }
    await clearExportLagWhenResolved(env);
    return;
  }

  await clearExportLagWhenResolved(env);
}

async function markRepeatDueIfNeeded(
  env: AlertEnv,
  row: AlertRow,
  nowIso: string,
): Promise<void> {
  if (row.active !== 1 || row.next_send_at === null) {
    return;
  }
  if (row.next_send_at > nowIso) {
    return;
  }
  await env.DB.prepare(
    `UPDATE alert SET unsent = 1 WHERE alert_key = ?`,
  )
    .bind(row.alert_key)
    .run();
}

async function sendAlertRow(env: AlertEnv, row: AlertRow): Promise<void> {
  const nowIso = await clockNowIso(env);
  const nowMs = await clockNowMs(env);
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject: ALERT_CODE,
    text: alertEmailText(row.detail_id),
  };
  try {
    await env.SEND_EMAIL.send(message);
    const nextSendAt = new Date(nowMs + ONE_DAY_MS).toISOString();
    await env.DB.prepare(
      `UPDATE alert
       SET unsent = 0, last_sent_at = ?, next_send_at = ?
       WHERE alert_key = ?`,
    )
      .bind(nowIso, nextSendAt, row.alert_key)
      .run();
  } catch {
    await env.DB.prepare(
      `UPDATE alert SET unsent = 1 WHERE alert_key = ?`,
    )
      .bind(row.alert_key)
      .run();
  }
}

export async function sendDueAlerts(env: AlertEnv): Promise<void> {
  const nowIso = await clockNowIso(env);
  const rows = await env.DB.prepare(
    `SELECT alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id
     FROM alert`,
  ).all<AlertRow>();

  for (const row of rows.results ?? []) {
    await markRepeatDueIfNeeded(env, row, nowIso);
  }

  const dueRows = await env.DB.prepare(
    `SELECT alert_key, code, active, unsent, last_sent_at, next_send_at, detail_id
     FROM alert WHERE unsent = 1 AND active = 1`,
  ).all<AlertRow>();

  for (const row of dueRows.results ?? []) {
    await sendAlertRow(env, row);
  }
}
