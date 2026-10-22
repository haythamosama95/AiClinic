import { clockNowIso } from "../clock";
import { sendPlatformEmail, type SendEmailEnv } from "./email";

export type AlertEnv = SendEmailEnv & {
  DB: D1Database;
  ALERT_EMAIL_TO: string;
  HEARTBEAT_URL: string;
  HEARTBEAT_URL_PLATFORM?: string;
};

export type CoverageAlertEnv = SendEmailEnv & {
  DB: D1Database;
  ALERT_EMAIL_TO: string;
};

const ONE_HOUR_MS = 60 * 60 * 1000;

const FIVE_MINUTE_CRON = "*/5 * * * *";
const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const AL20_ALERT_KEY = "AL-20";

// R9-PAL1: a delivery attempt holds a lease for this long. A crashed owner
// releases the row when the lease expires; a live owner acknowledges it first.
const ALERT_LEASE_MS = 2 * 60 * 1000;
// Failure backoff: the first retry runs on the next five-minute tick, then
// 5, 10, 20, 40 and 60 minutes (capped).
const ALERT_BACKOFF_BASE_MS = 5 * 60 * 1000;
const ALERT_BACKOFF_CAP_MS = 60 * 60 * 1000;

export type Al13Kind = "bootstrap" | "register" | "revoke";

export type Al13Body = {
  code: "AL-13";
  credential_id: string;
  operator_email: string;
  kind: Al13Kind;
  operation: Record<string, unknown> | null;
};

function al13AlertKey(credentialId: string, kind: Al13Kind): string {
  return `AL-13:${credentialId}:${kind}`;
}

export type Al13IssuerKeyKind = "register" | "retire" | "revoke";

export type Al13IssuerKeyBody = {
  code: "AL-13";
  kid: string;
  operation: Record<string, unknown> | null;
};

function al13IssuerKeyAlertKey(kid: string, kind: Al13IssuerKeyKind): string {
  return `AL-13:issuer_key:${kid}:${kind}`;
}

export type Al13ServiceKeyKind = "register" | "revoke";

export type Al13ServiceKeyBody = {
  code: "AL-13";
  kid: string;
  operation: Record<string, unknown> | null;
};

function al13ServiceKeyAlertKey(kid: string, kind: Al13ServiceKeyKind): string {
  return `AL-13:service_key:${kid}:${kind}`;
}

export type Al20Body = {
  code: "AL-20";
};

/**
 * Canonical JSON with sorted object keys. The stored body and any later
 * identity check use this form, so the same accepted payload always compares
 * equal regardless of property order.
 */
export function stableAlertJson(value: unknown): string {
  return JSON.stringify(canonicalAlertValue(value));
}

function canonicalAlertValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(canonicalAlertValue);
  }
  if (value !== null && typeof value === "object") {
    const source = value as Record<string, unknown>;
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(source).sort()) {
      out[key] = canonicalAlertValue(source[key]);
    }
    return out;
  }
  return value;
}

export type DurableAlertInput = {
  alertKey: string;
  code: string;
  body: Record<string, unknown>;
  nowIso: string;
  channelVersion?: number | null;
  originEventId?: string | null;
};

/**
 * Records the immutable original body of an alert before any send is
 * attempted (R9-PAL1 step 1). A matching key with a different stored body is
 * an explicit conflict and is never overwritten. A legacy row without a body
 * is filled only from this exact accepted payload.
 */
export async function persistDurableAlertBody(
  db: D1Database,
  input: DurableAlertInput,
  options: { countRepeat: boolean },
): Promise<void> {
  const bodyJson = stableAlertJson(input.body);
  await db
    .prepare(
      `INSERT INTO platform_alert
         (alert_key, code, severity, first_at, last_at, count, send_state, next_send_at, resolved_at,
          body_json, body_state, channel_version, origin_event_id, attempts)
       VALUES (?, ?, 'high', ?, ?, 1, 'unsent', NULL, NULL, ?, 'stored', ?, ?, 0)
       ON CONFLICT(alert_key) DO NOTHING`,
    )
    .bind(
      input.alertKey,
      input.code,
      input.nowIso,
      input.nowIso,
      bodyJson,
      input.channelVersion ?? null,
      input.originEventId ?? null,
    )
    .run();

  const row = await db
    .prepare(
      `SELECT code, body_json, body_state FROM platform_alert WHERE alert_key = ?`,
    )
    .bind(input.alertKey)
    .first<{ code: string; body_json: string | null; body_state: string }>();
  if (row === null) {
    throw new Error(`alert_persist_missing:${input.alertKey}`);
  }
  if (row.code !== input.code) {
    throw new Error(`alert_code_conflict:${input.alertKey}`);
  }
  if (row.body_state === "stored") {
    if (row.body_json !== bodyJson) {
      throw new Error(`alert_body_conflict:${input.alertKey}`);
    }
  } else {
    await db
      .prepare(
        `UPDATE platform_alert
         SET body_json = ?, body_state = 'stored',
             channel_version = COALESCE(channel_version, ?),
             origin_event_id = COALESCE(origin_event_id, ?)
         WHERE alert_key = ? AND body_state = 'incomplete'`,
      )
      .bind(
        bodyJson,
        input.channelVersion ?? null,
        input.originEventId ?? null,
        input.alertKey,
      )
      .run();
  }

  if (options.countRepeat) {
    await db
      .prepare(
        `UPDATE platform_alert SET last_at = ?, count = count + 1 WHERE alert_key = ?`,
      )
      .bind(input.nowIso, input.alertKey)
      .run();
  }
}

export function isAlertBodyConflictError(error: unknown): boolean {
  return error instanceof Error
    && (error.message.startsWith("alert_body_conflict:")
      || error.message.startsWith("alert_code_conflict:"));
}

/**
 * Records a conflicting alert body for the operator (R9-PAL1). The record is
 * its own durable row with a fixed body, so repeated conflicts neither resend
 * nor overwrite it. The conflicting body itself is never stored here.
 */
async function recordAlertBodyConflict(
  db: D1Database,
  input: DurableAlertInput,
  error: unknown,
): Promise<void> {
  const message = error instanceof Error ? error.message : String(error);
  console.log(
    JSON.stringify({
      code: "alert_body_conflict",
      alert_key: input.alertKey,
      alert_code: input.code,
      error: message,
    }),
  );
  await persistDurableAlertBody(
    db,
    {
      alertKey: `alert_body_conflict:${input.alertKey}`,
      code: "alert_body_conflict",
      body: {
        code: "alert_body_conflict",
        alert_key: input.alertKey,
        alert_code: input.code,
      },
      nowIso: input.nowIso,
    },
    { countRepeat: false },
  );
}

/**
 * Persists an alert body for a mutation or outbox row that has already
 * committed (R9-PAL1). A body conflict must not turn a committed change into
 * an error: it is logged and recorded for the operator, and `false` tells the
 * caller to skip delivery. Non-conflict failures still throw.
 */
export async function persistCommittedAlertBody(
  db: D1Database,
  input: DurableAlertInput,
  options: { countRepeat: boolean },
): Promise<boolean> {
  try {
    await persistDurableAlertBody(db, input, options);
    return true;
  } catch (error) {
    if (!isAlertBodyConflictError(error)) {
      throw error;
    }
    await recordAlertBodyConflict(db, input, error);
    return false;
  }
}

/**
 * Kill-switch AL-19 identity (R9-PAL1). Each arm or disarm transition has its
 * own key, so arm, disarm and arm again each produce a distinct durable alert.
 */
export type KillSwitchTransition = {
  action: "arm" | "disarm";
  changed_at: string;
};

export function al19KillSwitchAlertKey(
  scope: string,
  target: string,
  transition: KillSwitchTransition,
): string {
  return `AL-19:kill_switch:${transition.action}:${scope}:${target}:${transition.changed_at}`;
}

/**
 * Builds the AL-19 body insert so it commits in the same D1 batch as the
 * kill-switch transition (R9-PAL1 step 1). It runs only when the preceding
 * audit row was written (changes() chain). The post-commit
 * persistCommittedAlertBody call still verifies the stored body, handles
 * conflicts, and delivers.
 */
export function buildAl19KillSwitchAlertStatement(
  db: D1Database,
  input: {
    scope: string;
    target: string;
    transition: KillSwitchTransition;
    nowIso: string;
  },
): D1PreparedStatement {
  const body = {
    code: "AL-19",
    action: input.transition.action,
    scope: input.scope,
    target: input.target,
    changed_at: input.transition.changed_at,
  };
  return db
    .prepare(
      `INSERT INTO platform_alert
         (alert_key, code, severity, first_at, last_at, count, send_state, next_send_at, resolved_at,
          body_json, body_state, channel_version, origin_event_id, attempts)
       SELECT ?, 'AL-19', 'high', ?, ?, 1, 'unsent', NULL, NULL, ?, 'stored', NULL, NULL, 0
       WHERE changes() > 0
       ON CONFLICT(alert_key) DO NOTHING`,
    )
    .bind(
      al19KillSwitchAlertKey(input.scope, input.target, input.transition),
      input.nowIso,
      input.nowIso,
      stableAlertJson(body),
    );
}

/**
 * Legacy rows written before R9-PAL1 have no recoverable body. They stay
 * unsent and are listed here so the operator can adjudicate them. Nothing
 * sends them automatically.
 */
export async function listIncompleteUnsentPlatformAlerts(
  db: D1Database,
): Promise<Array<{ alert_key: string; code: string; first_at: string; last_at: string; count: number }>> {
  const rows = await db
    .prepare(
      `SELECT alert_key, code, first_at, last_at, count FROM platform_alert
       WHERE body_state = 'incomplete' AND send_state = 'unsent'
       ORDER BY first_at ASC`,
    )
    .all<{ alert_key: string; code: string; first_at: string; last_at: string; count: number }>();
  return rows.results ?? [];
}

/**
 * Repeat scheduling for a recurring condition: reopens a resolved or sent row
 * so the leased dispatcher sends it again. One-shot events never call this.
 */
async function reopenAlertForRepeat(
  db: D1Database,
  alertKey: string,
  nowIso: string,
): Promise<void> {
  await db
    .prepare(
      `UPDATE platform_alert
       SET send_state = 'unsent', next_send_at = NULL, resolved_at = NULL,
           last_at = ?, count = count + 1
       WHERE alert_key = ?`,
    )
    .bind(nowIso, alertKey)
    .run();
}

function nextSendAfterSuccess(code: string, nowIso: string): string | null {
  const nowMs = Date.parse(nowIso);
  if (code === "AL-17") {
    return new Date(nowMs + ONE_HOUR_MS).toISOString();
  }
  if (code === "AL-20") {
    return new Date(nowMs + ONE_DAY_MS).toISOString();
  }
  return null;
}

/**
 * Backoff after the failure that makes `failures` total failures. The first
 * failure retries on the next tick; later ones grow to a bounded cap.
 */
function nextSendAfterFailure(failures: number, nowIso: string): string {
  const delayMs = failures <= 1
    ? 0
    : Math.min(ALERT_BACKOFF_BASE_MS * 2 ** Math.min(failures - 2, 16), ALERT_BACKOFF_CAP_MS);
  return new Date(Date.parse(nowIso) + delayMs).toISOString();
}

/**
 * Single leased delivery path for every supported code (R9-PAL1 step 2).
 * Only the lease owner sends. Email is at-least-once across a lost
 * acknowledgement; a successfully acknowledged one-shot is never sent again.
 */
export async function deliverDurableAlert(
  env: CoverageAlertEnv,
  alertKey: string,
): Promise<boolean> {
  const nowIso = await clockNowIso(env);
  const leaseToken = crypto.randomUUID();
  const leaseExpiresAt = new Date(Date.parse(nowIso) + ALERT_LEASE_MS).toISOString();
  const claimed = await env.DB.prepare(
    `UPDATE platform_alert
     SET lease_token = ?, lease_expires_at = ?
     WHERE alert_key = ? AND send_state = 'unsent' AND body_state = 'stored'
       AND resolved_at IS NULL
       AND (next_send_at IS NULL OR next_send_at <= ?)
       AND (lease_expires_at IS NULL OR lease_expires_at <= ?)`,
  )
    .bind(leaseToken, leaseExpiresAt, alertKey, nowIso, nowIso)
    .run();
  if ((claimed.meta?.changes ?? 0) !== 1) {
    return false;
  }

  const row = await env.DB.prepare(
    `SELECT code, body_json, attempts FROM platform_alert
     WHERE alert_key = ? AND lease_token = ?`,
  )
    .bind(alertKey, leaseToken)
    .first<{ code: string; body_json: string; attempts: number }>();
  if (row === null) {
    return false;
  }

  try {
    await sendPlatformEmail(env, {
      from: env.ALERT_EMAIL_TO,
      to: env.ALERT_EMAIL_TO,
      subject: row.code,
      text: row.body_json,
    });
  } catch {
    await env.DB.prepare(
      `UPDATE platform_alert
       SET send_state = 'unsent', next_send_at = ?, attempts = attempts + 1,
           lease_token = NULL, lease_expires_at = NULL
       WHERE alert_key = ? AND lease_token = ?`,
    )
      .bind(nextSendAfterFailure(row.attempts + 1, nowIso), alertKey, leaseToken)
      .run();
    return false;
  }

  await env.DB.prepare(
    `UPDATE platform_alert
     SET send_state = 'sent', next_send_at = ?, attempts = 0,
         lease_token = NULL, lease_expires_at = NULL
     WHERE alert_key = ? AND lease_token = ?`,
  )
    .bind(nextSendAfterSuccess(row.code, nowIso), alertKey, leaseToken)
    .run();
  return true;
}

export async function raiseAl13(
  env: AlertEnv,
  input: {
    credentialId: string;
    operatorEmail: string;
    kind: Al13Kind;
    operation: Record<string, unknown> | null;
  },
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const alertKey = al13AlertKey(input.credentialId, input.kind);
  const body: Al13Body = {
    code: "AL-13",
    credential_id: input.credentialId,
    operator_email: input.operatorEmail,
    kind: input.kind,
    operation: input.operation,
  };
  const persisted = await persistCommittedAlertBody(
    env.DB,
    { alertKey, code: "AL-13", body, nowIso },
    { countRepeat: true },
  );
  if (!persisted) {
    return;
  }
  await deliverDurableAlert(env, alertKey);
}

export async function raiseAl13Bootstrap(
  env: AlertEnv,
  input: {
    credentialId: string;
    operatorEmail: string;
  },
): Promise<void> {
  await raiseAl13(env, {
    credentialId: input.credentialId,
    operatorEmail: input.operatorEmail,
    kind: "bootstrap",
    operation: null,
  });
}

export async function insertDoRebuildMismatchAlert(
  db: D1Database,
  installationId: string,
  nowIso: string,
  reason?: string,
): Promise<void> {
  const alertKey = reason === undefined
    ? `do-rebuild:${installationId}`
    : `do-rebuild:${installationId}:${reason}`;
  // The five-minute dispatcher sends this row; the rebuild path has no mail binding.
  await persistDurableAlertBody(
    db,
    {
      alertKey,
      code: "do_rebuild_mismatch",
      body: {
        code: "do_rebuild_mismatch",
        installation_id: installationId,
        reason: reason ?? null,
      },
      nowIso,
    },
    { countRepeat: true },
  );
}

export async function raiseAl13ServiceKey(
  env: AlertEnv,
  input: {
    kid: string;
    kind: Al13ServiceKeyKind;
    operation: Record<string, unknown> | null;
  },
): Promise<void> {
  const alertKey = al13ServiceKeyAlertKey(input.kid, input.kind);
  const nowIso = await clockNowIso(env);
  const body: Al13ServiceKeyBody = {
    code: "AL-13",
    kid: input.kid,
    operation: input.operation,
  };
  const persisted = await persistCommittedAlertBody(
    env.DB,
    { alertKey, code: "AL-13", body, nowIso },
    { countRepeat: true },
  );
  if (!persisted) {
    return;
  }
  await deliverDurableAlert(env, alertKey);
}

export async function raiseAl13IssuerKey(
  env: AlertEnv,
  input: {
    kid: string;
    kind: Al13IssuerKeyKind;
    operation: Record<string, unknown> | null;
  },
): Promise<void> {
  const alertKey = al13IssuerKeyAlertKey(input.kid, input.kind);
  const nowIso = await clockNowIso(env);
  const body: Al13IssuerKeyBody = {
    code: "AL-13",
    kid: input.kid,
    operation: input.operation,
  };
  const persisted = await persistCommittedAlertBody(
    env.DB,
    { alertKey, code: "AL-13", body, nowIso },
    { countRepeat: true },
  );
  if (!persisted) {
    return;
  }
  await deliverDurableAlert(env, alertKey);
}

export async function raiseAl20(env: AlertEnv): Promise<void> {
  const nowIso = await clockNowIso(env);
  const body: Al20Body = { code: "AL-20" };
  await persistDurableAlertBody(
    env.DB,
    { alertKey: AL20_ALERT_KEY, code: "AL-20", body, nowIso },
    { countRepeat: false },
  );
  await reopenAlertForRepeat(env.DB, AL20_ALERT_KEY, nowIso);
  await deliverDurableAlert(env, AL20_ALERT_KEY);
}

async function countEpochOneBindingsLast24Hours(
  db: D1Database,
  nowIso: string,
): Promise<number> {
  const nowMs = Date.parse(nowIso);
  const windowStart = new Date(nowMs - ONE_DAY_MS).toISOString();
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS count
       FROM tenant_binding
       WHERE epoch = 1 AND created_at > ?`,
    )
    .bind(windowStart)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function retryDueAl20Alerts(env: AlertEnv): Promise<void> {
  const nowIso = await clockNowIso(env);
  const row = await env.DB.prepare(
    `SELECT alert_key, next_send_at, resolved_at
     FROM platform_alert
     WHERE alert_key = ?`,
  )
    .bind(AL20_ALERT_KEY)
    .first<{
      alert_key: string;
      next_send_at: string | null;
      resolved_at: string | null;
    }>();
  if (row === null || row.resolved_at !== null) {
    return;
  }
  if (row.next_send_at === null || row.next_send_at > nowIso) {
    return;
  }

  const count = await countEpochOneBindingsLast24Hours(env.DB, nowIso);
  if (count > 50) {
    await reopenAlertForRepeat(env.DB, AL20_ALERT_KEY, nowIso);
    await deliverDurableAlert(env, AL20_ALERT_KEY);
    return;
  }

  await env.DB.prepare(
    `UPDATE platform_alert SET resolved_at = ? WHERE alert_key = ?`,
  )
    .bind(nowIso, AL20_ALERT_KEY)
    .run();
}

export async function raiseAl11GrantFromOutbox(
  env: CoverageAlertEnv,
  alertKey: string,
  body: Record<string, unknown>,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  await persistDurableAlertBody(
    env.DB,
    { alertKey, code: "AL-11", body, nowIso },
    { countRepeat: false },
  );
  await deliverDurableAlert(env, alertKey);
}

export async function raiseAl11Transfer(
  env: CoverageAlertEnv,
  transferId: string,
  orgId: string,
): Promise<void> {
  const alertKey = `AL-11:transfer:${transferId}`;
  const nowIso = await clockNowIso(env);
  const body = { code: "AL-11", transfer_id: transferId, org_id: orgId };
  await persistDurableAlertBody(
    env.DB,
    { alertKey, code: "AL-11", body, nowIso },
    { countRepeat: true },
  );
  await deliverDurableAlert(env, alertKey);
}

export async function raiseAl18HeldBinding(
  env: CoverageAlertEnv,
  orgId: string,
  installationId: string,
): Promise<void> {
  const alertKey = `AL-18:${installationId}`;
  const nowIso = await clockNowIso(env);
  const body = { code: "AL-18", org_id: orgId, installation_id: installationId };
  await persistDurableAlertBody(
    env.DB,
    { alertKey, code: "AL-18", body, nowIso },
    { countRepeat: true },
  );
  await deliverDurableAlert(env, alertKey);
}

export async function sendDailyAl18ForHeldBindings(
  env: CoverageAlertEnv,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const cutoffIso = new Date(Date.parse(nowIso) - ONE_DAY_MS).toISOString();
  const rows = await env.DB.prepare(
    `SELECT org_id, installation_id FROM tenant_binding WHERE status = 'held_for_transfer'`,
  ).all<{ org_id: string; installation_id: string }>();

  for (const row of rows.results ?? []) {
    const alertKey = `AL-18:${row.installation_id}`;
    const alert = await env.DB.prepare(
      `SELECT last_at FROM platform_alert WHERE alert_key = ? AND code = 'AL-18'`,
    )
      .bind(alertKey)
      .first<{ last_at: string }>();
    if (alert !== null && alert.last_at > cutoffIso) {
      continue;
    }
    const body = {
      code: "AL-18",
      org_id: row.org_id,
      installation_id: row.installation_id,
    };
    await persistDurableAlertBody(
      env.DB,
      { alertKey, code: "AL-18", body, nowIso },
      { countRepeat: false },
    );
    if (alert !== null) {
      await reopenAlertForRepeat(env.DB, alertKey, nowIso);
    }
    await deliverDurableAlert(env, alertKey);
  }
}

export async function raiseAl12GrantFromOutbox(
  env: CoverageAlertEnv,
  alertKey: string,
  body: Record<string, unknown>,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  await persistDurableAlertBody(
    env.DB,
    { alertKey, code: "AL-12", body, nowIso },
    { countRepeat: false },
  );
  await deliverDurableAlert(env, alertKey);
}

export async function raiseAl19FromOutbox(
  env: CoverageAlertEnv,
  alertKey: string,
  body: Record<string, unknown>,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const persisted = await persistCommittedAlertBody(
    env.DB,
    { alertKey, code: "AL-19", body, nowIso },
    { countRepeat: false },
  );
  if (!persisted) {
    return;
  }
  await deliverDurableAlert(env, alertKey);
}

export async function raiseAl17FromOutbox(
  env: CoverageAlertEnv,
  alertKey: string,
  body: Record<string, unknown>,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  await persistDurableAlertBody(
    env.DB,
    { alertKey, code: "AL-17", body, nowIso },
    { countRepeat: false },
  );
  await reopenAlertForRepeat(env.DB, alertKey, nowIso);
  await deliverDurableAlert(env, alertKey);
}

async function countPaidGrantsForOrgLast24Hours(
  db: D1Database,
  orgId: string,
  nowIso: string,
): Promise<number> {
  const windowStart = new Date(Date.parse(nowIso) - ONE_DAY_MS).toISOString();
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS count FROM grant_ledger
       WHERE source_kind = 'paid' AND org_id = ? AND applied_at >= ?`,
    )
    .bind(orgId, windowStart)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function countGlobalPaidGrantsLastHour(
  db: D1Database,
  nowIso: string,
): Promise<number> {
  const windowStart = new Date(Date.parse(nowIso) - ONE_HOUR_MS).toISOString();
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS count FROM grant_ledger
       WHERE source_kind = 'paid' AND applied_at >= ?`,
    )
    .bind(windowStart)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function al17ConditionStillHolds(
  env: AlertEnv,
  alertKey: string,
  nowIso: string,
): Promise<boolean> {
  if (alertKey === "AL-17:global") {
    const count = await countGlobalPaidGrantsLastHour(env.DB, nowIso);
    return count > 20;
  }
  const prefix = "AL-17:clinic:";
  if (!alertKey.startsWith(prefix)) {
    return false;
  }
  const orgId = alertKey.slice(prefix.length);
  const count = await countPaidGrantsForOrgLast24Hours(env.DB, orgId, nowIso);
  return count > 3;
}

async function retryDueAl17Alerts(env: AlertEnv): Promise<void> {
  const nowIso = await clockNowIso(env);
  const rows = await env.DB.prepare(
    `SELECT alert_key, next_send_at, resolved_at
     FROM platform_alert
     WHERE code = 'AL-17' AND resolved_at IS NULL`,
  ).all<{
    alert_key: string;
    next_send_at: string | null;
    resolved_at: string | null;
  }>();

  for (const row of rows.results ?? []) {
    if (row.next_send_at === null || row.next_send_at > nowIso) {
      continue;
    }
    const stillHolds = await al17ConditionStillHolds(env, row.alert_key, nowIso);
    if (!stillHolds) {
      await env.DB.prepare(
        `UPDATE platform_alert SET resolved_at = ? WHERE alert_key = ?`,
      )
        .bind(nowIso, row.alert_key)
        .run();
      continue;
    }
    await reopenAlertForRepeat(env.DB, row.alert_key, nowIso);
    await deliverDurableAlert(env, row.alert_key);
  }
}

/**
 * The one dispatcher for every due, unsent alert with a stored body
 * (R9-PAL1 step 2). Rows without a stored body remain explicit incomplete
 * evidence for the operator and are never sent.
 */
export async function retryUnsentPlatformAlerts(env: AlertEnv): Promise<void> {
  const nowIso = await clockNowIso(env);
  const rows = await env.DB.prepare(
    `SELECT alert_key FROM platform_alert
     WHERE send_state = 'unsent' AND body_state = 'stored' AND resolved_at IS NULL
       AND (next_send_at IS NULL OR next_send_at <= ?)
       AND (lease_expires_at IS NULL OR lease_expires_at <= ?)
     ORDER BY last_at ASC
     LIMIT 100`,
  )
    .bind(nowIso, nowIso)
    .all<{ alert_key: string }>();

  for (const row of rows.results ?? []) {
    await deliverDurableAlert(env, row.alert_key);
  }
}

// R9-RT2: the platform_5min stream pings its own configured URL. HEARTBEAT_URL is the fallback
// only while HEARTBEAT_URL_PLATFORM is unset, so the platform stream never shares a URL with
// an ABO stream once the per-stream variable is provisioned.
export async function pingPlatformHeartbeat(env: AlertEnv): Promise<void> {
  const own = env.HEARTBEAT_URL_PLATFORM;
  const url = typeof own === "string" && own.length > 0 ? own : env.HEARTBEAT_URL;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`heartbeat fetch failed: ${response.status}`);
  }
}

async function insertScheduledJobFailedAlert(
  env: AlertEnv,
  job: string,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const alertKey = `scheduled_job_failed:${job}`;
  await persistDurableAlertBody(
    env.DB,
    {
      alertKey,
      code: "scheduled_job_failed",
      body: { code: "scheduled_job_failed", cron: FIVE_MINUTE_CRON, job },
      nowIso,
    },
    { countRepeat: true },
  );
}

function logScheduledJobFailure(
  cron: string,
  job: string,
  error: unknown,
): void {
  const message = error instanceof Error ? error.message : String(error);
  console.log(
    JSON.stringify({
      cron,
      job,
      error: message,
      code: "scheduled_job_failed",
    }),
  );
}

async function runFiveMinuteJob(
  env: AlertEnv,
  job: "alert_retry" | "heartbeat",
  run: () => Promise<void>,
): Promise<void> {
  try {
    await run();
  } catch (error) {
    logScheduledJobFailure(FIVE_MINUTE_CRON, job, error);
    await insertScheduledJobFailedAlert(env, job);
  }
}

export async function runFiveMinuteCron(env: AlertEnv): Promise<void> {
  await runFiveMinuteJob(env, "alert_retry", async () => {
    await retryUnsentPlatformAlerts(env);
    await retryDueAl20Alerts(env);
    await retryDueAl17Alerts(env);
  });
  await runFiveMinuteJob(env, "heartbeat", () => pingPlatformHeartbeat(env));
}
