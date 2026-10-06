import { CHANNEL_VERSIONS } from "vendor-contracts";
import { clockNowIso, clockNowMs } from "../clock";
import { sendPlatformEmail, type SendEmailEnv } from "./email";

export type AlertEnv = SendEmailEnv & {
  DB: D1Database;
  ALERT_EMAIL_TO: string;
  HEARTBEAT_URL: string;
};

export type CoverageAlertEnv = SendEmailEnv & {
  DB: D1Database;
  ALERT_EMAIL_TO: string;
};

const ONE_HOUR_MS = 60 * 60 * 1000;

const FIVE_MINUTE_CRON = "*/5 * * * *";
const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const AL20_ALERT_KEY = "AL-20";

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

function al13EmailText(body: Al13Body): string {
  return JSON.stringify(body);
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

function al13IssuerKeyEmailText(body: Al13IssuerKeyBody): string {
  return JSON.stringify(body);
}

function parseAl13IssuerKeyAlertKey(
  alertKey: string,
): { kid: string; kind: Al13IssuerKeyKind } | null {
  const prefix = "AL-13:issuer_key:";
  if (!alertKey.startsWith(prefix)) {
    return null;
  }
  const rest = alertKey.slice(prefix.length);
  const separator = rest.lastIndexOf(":");
  if (separator <= 0) {
    return null;
  }
  const kid = rest.slice(0, separator);
  const kind = rest.slice(separator + 1);
  if (kind !== "register" && kind !== "retire" && kind !== "revoke") {
    return null;
  }
  return { kid, kind };
}

function issuerKeyHpMethod(kind: Al13IssuerKeyKind): string {
  if (kind === "register") {
    return "registerIssuerKey";
  }
  if (kind === "retire") {
    return "retireIssuerKey";
  }
  return "revokeIssuerKey";
}

async function readIssuerKeyForAlert(
  db: D1Database,
  kid: string,
): Promise<{
  public_key: string;
  not_before: string;
  not_after: string;
} | null> {
  return db
    .prepare(
      `SELECT public_key, not_before, not_after FROM issuer_key WHERE kid = ?`,
    )
    .bind(kid)
    .first<{ public_key: string; not_before: string; not_after: string }>();
}

async function rebuildAl13IssuerKeyOperation(
  db: D1Database,
  kid: string,
  kind: Al13IssuerKeyKind,
): Promise<Record<string, unknown> | null> {
  const method = issuerKeyHpMethod(kind);
  const audit = await db
    .prepare(
      `SELECT actor, assertion_sha256, recorded_at
       FROM control_audit
       WHERE action = ? AND target = ? AND assertion_sha256 IS NOT NULL
       ORDER BY recorded_at DESC
       LIMIT 1`,
    )
    .bind(method, kid)
    .first<{
      actor: string;
      assertion_sha256: string;
      recorded_at: string;
    }>();
  if (audit === null) {
    return null;
  }
  const used = await db
    .prepare(
      `SELECT credential_id FROM assertion_used WHERE challenge_sha256 = ?`,
    )
    .bind(audit.assertion_sha256)
    .first<{ credential_id: string }>();
  const contractVersion = CHANNEL_VERSIONS.vendorEntrypoint;
  const params: Record<string, unknown> = {
    contract_version: contractVersion,
    access_jwt: "",
    kid,
    signer_credential_id: used?.credential_id ?? "",
  };
  if (kind === "register") {
    const row = await readIssuerKeyForAlert(db, kid);
    if (row === null) {
      return null;
    }
    params.public_key = row.public_key;
    params.not_before = row.not_before;
    params.not_after = row.not_after;
  }
  return {
    op: method,
    params,
    actor_email: audit.actor,
    issued_at: audit.recorded_at,
    nonce: audit.assertion_sha256,
    contract_version: contractVersion,
  };
}

async function readPlatformAlertSendState(
  db: D1Database,
  alertKey: string,
): Promise<"sent" | "unsent" | null> {
  const row = await db
    .prepare("SELECT send_state FROM platform_alert WHERE alert_key = ?")
    .bind(alertKey)
    .first<{ send_state: string }>();
  if (row === null) {
    return null;
  }
  return row.send_state === "sent" ? "sent" : "unsent";
}

async function sendAl13IssuerKeyBody(
  env: AlertEnv,
  body: Al13IssuerKeyBody,
  alertKey: string,
): Promise<void> {
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject: "AL-13",
    text: al13IssuerKeyEmailText(body),
  };
  try {
    await sendPlatformEmail(env, message);
    await markAlertSent(env.DB, alertKey);
  } catch {
    const nowIso = await clockNowIso(env);
    await markAlertUnsent(env.DB, alertKey, nowIso);
  }
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

function al13ServiceKeyEmailText(body: Al13ServiceKeyBody): string {
  return JSON.stringify(body);
}

function parseAl13ServiceKeyAlertKey(
  alertKey: string,
): { kid: string; kind: Al13ServiceKeyKind } | null {
  const prefix = "AL-13:service_key:";
  if (!alertKey.startsWith(prefix)) {
    return null;
  }
  const rest = alertKey.slice(prefix.length);
  const separator = rest.lastIndexOf(":");
  if (separator <= 0) {
    return null;
  }
  const kid = rest.slice(0, separator);
  const kind = rest.slice(separator + 1);
  if (kind !== "register" && kind !== "revoke") {
    return null;
  }
  return { kid, kind };
}

function serviceKeyHpMethod(kind: Al13ServiceKeyKind): string {
  return kind === "register" ? "registerServiceKey" : "revokeServiceKey";
}

async function readServiceKeyForAlert(
  db: D1Database,
  kid: string,
): Promise<{
  public_key: string;
  not_before: string;
  not_after: string;
} | null> {
  return db
    .prepare(
      `SELECT public_key, not_before, not_after FROM service_key WHERE kid = ?`,
    )
    .bind(kid)
    .first<{ public_key: string; not_before: string; not_after: string }>();
}

async function rebuildAl13ServiceKeyOperation(
  db: D1Database,
  kid: string,
  kind: Al13ServiceKeyKind,
): Promise<Record<string, unknown> | null> {
  const method = serviceKeyHpMethod(kind);
  const audit = await db
    .prepare(
      `SELECT actor, assertion_sha256, recorded_at
       FROM control_audit
       WHERE action = ? AND target = ? AND assertion_sha256 IS NOT NULL
       ORDER BY recorded_at DESC
       LIMIT 1`,
    )
    .bind(method, kid)
    .first<{
      actor: string;
      assertion_sha256: string;
      recorded_at: string;
    }>();
  if (audit === null) {
    return null;
  }
  const used = await db
    .prepare(
      `SELECT credential_id FROM assertion_used WHERE challenge_sha256 = ?`,
    )
    .bind(audit.assertion_sha256)
    .first<{ credential_id: string }>();
  const contractVersion = CHANNEL_VERSIONS.vendorEntrypoint;
  const params: Record<string, unknown> = {
    contract_version: contractVersion,
    access_jwt: "",
    kid,
    signer_credential_id: used?.credential_id ?? "",
  };
  if (kind === "register") {
    const row = await readServiceKeyForAlert(db, kid);
    if (row === null) {
      return null;
    }
    params.public_key = row.public_key;
    params.not_before = row.not_before;
    params.not_after = row.not_after;
  }
  return {
    op: method,
    params,
    actor_email: audit.actor,
    issued_at: audit.recorded_at,
    nonce: audit.assertion_sha256,
    contract_version: contractVersion,
  };
}

async function sendAl13ServiceKeyBody(
  env: AlertEnv,
  body: Al13ServiceKeyBody,
  alertKey: string,
): Promise<void> {
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject: "AL-13",
    text: al13ServiceKeyEmailText(body),
  };
  try {
    await sendPlatformEmail(env, message);
    await markAlertSent(env.DB, alertKey);
  } catch {
    const nowIso = await clockNowIso(env);
    await markAlertUnsent(env.DB, alertKey, nowIso);
  }
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
  const priorSendState = await readPlatformAlertSendState(env.DB, alertKey);
  if (priorSendState === "sent") {
    const nowIso = await clockNowIso(env);
    await upsertPlatformAlert(env.DB, alertKey, "AL-13", nowIso);
    return;
  }

  const nowIso = await clockNowIso(env);
  await upsertPlatformAlert(env.DB, alertKey, "AL-13", nowIso);

  const body: Al13ServiceKeyBody = {
    code: "AL-13",
    kid: input.kid,
    operation: input.operation,
  };
  await sendAl13ServiceKeyBody(env, body, alertKey);
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
  const priorSendState = await readPlatformAlertSendState(env.DB, alertKey);
  if (priorSendState === "sent") {
    const nowIso = await clockNowIso(env);
    await upsertPlatformAlert(env.DB, alertKey, "AL-13", nowIso);
    return;
  }

  const nowIso = await clockNowIso(env);
  await upsertPlatformAlert(env.DB, alertKey, "AL-13", nowIso);

  const body: Al13IssuerKeyBody = {
    code: "AL-13",
    kid: input.kid,
    operation: input.operation,
  };
  await sendAl13IssuerKeyBody(env, body, alertKey);
}

export type Al20Body = {
  code: "AL-20";
};

function al20EmailText(): string {
  return JSON.stringify({ code: "AL-20" } satisfies Al20Body);
}

async function markAl20AlertSent(
  db: D1Database,
  nextSendAtIso: string,
): Promise<void> {
  await db
    .prepare(
      `UPDATE platform_alert
       SET send_state = 'sent', next_send_at = ?
       WHERE alert_key = ?`,
    )
    .bind(nextSendAtIso, AL20_ALERT_KEY)
    .run();
}

async function sendAl20Body(env: AlertEnv): Promise<void> {
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject: "AL-20",
    text: al20EmailText(),
  };
  try {
    await sendPlatformEmail(env, message);
    const nowMs = await clockNowMs(env);
    const nextSendAt = new Date(nowMs + ONE_DAY_MS).toISOString();
    await markAl20AlertSent(env.DB, nextSendAt);
  } catch {
    const nowIso = await clockNowIso(env);
    await markAlertUnsent(env.DB, AL20_ALERT_KEY, nowIso);
  }
}

export async function raiseAl20(env: AlertEnv): Promise<void> {
  const nowIso = await clockNowIso(env);
  await upsertPlatformAlert(env.DB, AL20_ALERT_KEY, "AL-20", nowIso);
  await sendAl20Body(env);
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
    await sendAl20Body(env);
    return;
  }

  await env.DB.prepare(
    `UPDATE platform_alert SET resolved_at = ? WHERE alert_key = ?`,
  )
    .bind(nowIso, AL20_ALERT_KEY)
    .run();
}

async function upsertPlatformAlert(
  db: D1Database,
  alertKey: string,
  code: string,
  nowIso: string,
): Promise<void> {
  const existing = await db
    .prepare("SELECT alert_key FROM platform_alert WHERE alert_key = ?")
    .bind(alertKey)
    .first<{ alert_key: string }>();

  if (existing) {
    await db
      .prepare(
        `UPDATE platform_alert
         SET last_at = ?, count = count + 1
         WHERE alert_key = ?`,
      )
      .bind(nowIso, alertKey)
      .run();
    return;
  }

  await db
    .prepare(
      `INSERT INTO platform_alert
         (alert_key, code, severity, first_at, last_at, count, send_state, next_send_at, resolved_at)
       VALUES (?, ?, 'high', ?, ?, 1, 'unsent', NULL, NULL)`,
    )
    .bind(alertKey, code, nowIso, nowIso)
    .run();
}

async function markAlertSent(db: D1Database, alertKey: string): Promise<void> {
  await db
    .prepare(
      `UPDATE platform_alert SET send_state = 'sent', next_send_at = NULL WHERE alert_key = ?`,
    )
    .bind(alertKey)
    .run();
}

async function markAlertUnsent(
  db: D1Database,
  alertKey: string,
  nowIso: string,
): Promise<void> {
  await db
    .prepare(
      `UPDATE platform_alert SET send_state = 'unsent', next_send_at = ? WHERE alert_key = ?`,
    )
    .bind(nowIso, alertKey)
    .run();
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
  await upsertPlatformAlert(env.DB, alertKey, "AL-13", nowIso);

  const body: Al13Body = {
    code: "AL-13",
    credential_id: input.credentialId,
    operator_email: input.operatorEmail,
    kind: input.kind,
    operation: input.operation,
  };
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject: "AL-13",
    text: al13EmailText(body),
  };

  try {
    await sendPlatformEmail(env, message);
    await markAlertSent(env.DB, alertKey);
  } catch {
    await markAlertUnsent(env.DB, alertKey, nowIso);
  }
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
): Promise<void> {
  const alertKey = `do-rebuild:${installationId}`;
  await db
    .prepare(
      `INSERT INTO platform_alert
         (alert_key, code, severity, first_at, last_at, count, send_state, next_send_at, resolved_at)
       VALUES (?, ?, 'high', ?, ?, 1, 'unsent', NULL, NULL)`,
    )
    .bind(alertKey, "do_rebuild_mismatch", nowIso, nowIso)
    .run();
}

function parseAl13AlertKey(
  alertKey: string,
): { credentialId: string; kind: Al13Kind } | null {
  const prefix = "AL-13:";
  if (!alertKey.startsWith(prefix)) {
    return null;
  }
  const rest = alertKey.slice(prefix.length);
  const separator = rest.lastIndexOf(":");
  if (separator <= 0) {
    return null;
  }
  const credentialId = rest.slice(0, separator);
  const kind = rest.slice(separator + 1);
  if (kind !== "bootstrap" && kind !== "register" && kind !== "revoke") {
    return null;
  }
  return { credentialId, kind };
}

async function readOperatorCredentialForAlert(
  db: D1Database,
  credentialId: string,
): Promise<{ operator_email: string; public_key_cose: string; alg: string } | null> {
  return db
    .prepare(
      `SELECT operator_email, public_key_cose, alg
       FROM operator_credential WHERE credential_id = ?`,
    )
    .bind(credentialId)
    .first<{ operator_email: string; public_key_cose: string; alg: string }>();
}

async function rebuildAl13Operation(
  db: D1Database,
  credentialId: string,
  kind: Al13Kind,
): Promise<Record<string, unknown> | null> {
  if (kind === "bootstrap") {
    return null;
  }
  const method =
    kind === "register"
      ? "registerOperatorCredential"
      : "revokeOperatorCredential";
  const audit = await db
    .prepare(
      `SELECT actor, assertion_sha256, recorded_at
       FROM control_audit
       WHERE action = ? AND target = ? AND assertion_sha256 IS NOT NULL
       ORDER BY recorded_at DESC
       LIMIT 1`,
    )
    .bind(method, credentialId)
    .first<{
      actor: string;
      assertion_sha256: string;
      recorded_at: string;
    }>();
  if (audit === null) {
    return null;
  }
  const used = await db
    .prepare(
      `SELECT credential_id FROM assertion_used WHERE challenge_sha256 = ?`,
    )
    .bind(audit.assertion_sha256)
    .first<{ credential_id: string }>();
  const contractVersion = CHANNEL_VERSIONS.vendorEntrypoint;
  const params: Record<string, unknown> = {
    contract_version: contractVersion,
    access_jwt: "",
    credential_id: credentialId,
    signer_credential_id: used?.credential_id ?? "",
  };
  if (kind === "register") {
    const row = await readOperatorCredentialForAlert(db, credentialId);
    if (row === null) {
      return null;
    }
    params.attestation = {
      alg: row.alg,
      public_key: row.public_key_cose,
    };
  }
  return {
    op: method,
    params,
    actor_email: audit.actor,
    issued_at: audit.recorded_at,
    nonce: audit.assertion_sha256,
    contract_version: contractVersion,
  };
}

async function sendScheduledJobFailedBody(
  env: AlertEnv,
  alertKey: string,
  job: string,
): Promise<void> {
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject: "scheduled_job_failed",
    text: JSON.stringify({
      code: "scheduled_job_failed",
      cron: FIVE_MINUTE_CRON,
      job,
    }),
  };
  try {
    await sendPlatformEmail(env, message);
    await markAlertSent(env.DB, alertKey);
  } catch {
    const nowIso = await clockNowIso(env);
    await markAlertUnsent(env.DB, alertKey, nowIso);
  }
}

async function sendAl13Body(
  env: AlertEnv,
  body: Al13Body,
  alertKey: string,
): Promise<void> {
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject: "AL-13",
    text: al13EmailText(body),
  };
  try {
    await sendPlatformEmail(env, message);
    await markAlertSent(env.DB, alertKey);
  } catch {
    const nowIso = await clockNowIso(env);
    await markAlertUnsent(env.DB, alertKey, nowIso);
  }
}

export async function retryUnsentPlatformAlerts(env: AlertEnv): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT alert_key, code FROM platform_alert WHERE send_state = 'unsent'`,
  ).all<{ alert_key: string; code: string }>();

  for (const row of rows.results ?? []) {
    if (row.code === "scheduled_job_failed") {
      const prefix = "scheduled_job_failed:";
      const job = row.alert_key.startsWith(prefix)
        ? row.alert_key.slice(prefix.length)
        : "";
      await sendScheduledJobFailedBody(env, row.alert_key, job);
      continue;
    }
    if (row.code === "AL-20") {
      await sendAl20Body(env);
      continue;
    }
    if (row.code === "AL-11") {
      continue;
    }
    if (row.code === "AL-17") {
      const nowMs = await clockNowMs(env);
      const nextSendAt = new Date(nowMs + ONE_HOUR_MS).toISOString();
      const body =
        row.alert_key === "AL-17:global"
          ? { code: "AL-17" }
          : {
              code: "AL-17",
              org_id: row.alert_key.slice("AL-17:clinic:".length),
            };
      await sendAl17Body(env, body, row.alert_key, nextSendAt);
      continue;
    }
    if (row.code !== "AL-13") {
      continue;
    }
    const issuerParsed = parseAl13IssuerKeyAlertKey(row.alert_key);
    if (issuerParsed !== null) {
      const operation = await rebuildAl13IssuerKeyOperation(
        env.DB,
        issuerParsed.kid,
        issuerParsed.kind,
      );
      const body: Al13IssuerKeyBody = {
        code: "AL-13",
        kid: issuerParsed.kid,
        operation,
      };
      await sendAl13IssuerKeyBody(env, body, row.alert_key);
      continue;
    }
    const serviceKeyParsed = parseAl13ServiceKeyAlertKey(row.alert_key);
    if (serviceKeyParsed !== null) {
      const operation = await rebuildAl13ServiceKeyOperation(
        env.DB,
        serviceKeyParsed.kid,
        serviceKeyParsed.kind,
      );
      const body: Al13ServiceKeyBody = {
        code: "AL-13",
        kid: serviceKeyParsed.kid,
        operation,
      };
      await sendAl13ServiceKeyBody(env, body, row.alert_key);
      continue;
    }
    const parsed = parseAl13AlertKey(row.alert_key);
    if (parsed === null) {
      continue;
    }
    const credential = await readOperatorCredentialForAlert(
      env.DB,
      parsed.credentialId,
    );
    if (credential === null) {
      continue;
    }
    const operation = await rebuildAl13Operation(
      env.DB,
      parsed.credentialId,
      parsed.kind,
    );
    const body: Al13Body = {
      code: "AL-13",
      credential_id: parsed.credentialId,
      operator_email: credential.operator_email,
      kind: parsed.kind,
      operation,
    };
    await sendAl13Body(env, body, row.alert_key);
  }
}

export async function pingPlatformHeartbeat(env: AlertEnv): Promise<void> {
  const response = await fetch(env.HEARTBEAT_URL);
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
  await upsertPlatformAlert(env.DB, alertKey, "scheduled_job_failed", nowIso);
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

async function sendAl11GrantBody(
  env: CoverageAlertEnv,
  body: Record<string, unknown>,
  alertKey: string,
): Promise<void> {
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject: "AL-11",
    text: JSON.stringify(body),
  };
  try {
    await sendPlatformEmail(env, message);
    await markAlertSent(env.DB, alertKey);
  } catch {
    const nowIso = await clockNowIso(env);
    await markAlertUnsent(env.DB, alertKey, nowIso);
  }
}

async function sendAl17Body(
  env: CoverageAlertEnv,
  body: Record<string, unknown>,
  alertKey: string,
  nextSendAt: string,
): Promise<void> {
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject: "AL-17",
    text: JSON.stringify(body),
  };
  try {
    await sendPlatformEmail(env, message);
    await env.DB.prepare(
      `UPDATE platform_alert SET send_state = 'sent', next_send_at = ? WHERE alert_key = ?`,
    )
      .bind(nextSendAt, alertKey)
      .run();
  } catch {
    const nowIso = await clockNowIso(env);
    await markAlertUnsent(env.DB, alertKey, nowIso);
  }
}

export async function raiseAl11GrantFromOutbox(
  env: CoverageAlertEnv,
  alertKey: string,
  body: Record<string, unknown>,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const existing = await readPlatformAlertSendState(env.DB, alertKey);
  if (existing === "sent") {
    return;
  }
  await upsertPlatformAlert(env.DB, alertKey, "AL-11", nowIso);
  await sendAl11GrantBody(env, body, alertKey);
}

export async function raiseAl11Transfer(
  env: CoverageAlertEnv,
  transferId: string,
  orgId: string,
): Promise<void> {
  const alertKey = `AL-11:transfer:${transferId}`;
  const nowIso = await clockNowIso(env);
  const existing = await readPlatformAlertSendState(env.DB, alertKey);
  if (existing === "sent") {
    return;
  }
  const body = { code: "AL-11", transfer_id: transferId, org_id: orgId };
  await upsertPlatformAlert(env.DB, alertKey, "AL-11", nowIso);
  await sendAl11GrantBody(env, body, alertKey);
}

export async function raiseAl18HeldBinding(
  env: CoverageAlertEnv,
  orgId: string,
  installationId: string,
): Promise<void> {
  const alertKey = `AL-18:${installationId}`;
  const nowIso = await clockNowIso(env);
  const existing = await readPlatformAlertSendState(env.DB, alertKey);
  if (existing === "sent") {
    return;
  }
  const body = { code: "AL-18", org_id: orgId, installation_id: installationId };
  await upsertPlatformAlert(env.DB, alertKey, "AL-18", nowIso);
  await sendCoverageAlertBody(env, "AL-18", body, alertKey);
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
    if (alert === null) {
      await upsertPlatformAlert(env.DB, alertKey, "AL-18", nowIso);
    } else {
      await env.DB.prepare(
        `UPDATE platform_alert SET last_at = ?, count = count + 1 WHERE alert_key = ?`,
      )
        .bind(nowIso, alertKey)
        .run();
    }
    const body = {
      code: "AL-18",
      org_id: row.org_id,
      installation_id: row.installation_id,
    };
    await sendCoverageAlertBody(env, "AL-18", body, alertKey);
  }
}

async function sendCoverageAlertBody(
  env: CoverageAlertEnv,
  subject: string,
  body: Record<string, unknown>,
  alertKey: string,
): Promise<void> {
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject,
    text: JSON.stringify(body),
  };
  try {
    await sendPlatformEmail(env, message);
    await markAlertSent(env.DB, alertKey);
  } catch {
    const nowIso = await clockNowIso(env);
    await markAlertUnsent(env.DB, alertKey, nowIso);
  }
}

export async function raiseAl12GrantFromOutbox(
  env: CoverageAlertEnv,
  alertKey: string,
  body: Record<string, unknown>,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const existing = await readPlatformAlertSendState(env.DB, alertKey);
  if (existing === "sent") {
    return;
  }
  await upsertPlatformAlert(env.DB, alertKey, "AL-12", nowIso);
  await sendCoverageAlertBody(env, "AL-12", body, alertKey);
}

export async function raiseAl19FromOutbox(
  env: CoverageAlertEnv,
  alertKey: string,
  body: Record<string, unknown>,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const existing = await readPlatformAlertSendState(env.DB, alertKey);
  if (existing === "sent") {
    return;
  }
  await upsertPlatformAlert(env.DB, alertKey, "AL-19", nowIso);
  await sendCoverageAlertBody(env, "AL-19", body, alertKey);
}

export async function raiseAl17FromOutbox(
  env: CoverageAlertEnv,
  alertKey: string,
  body: Record<string, unknown>,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const nowMs = await clockNowMs(env);
  const nextSendAt = new Date(nowMs + ONE_HOUR_MS).toISOString();
  await upsertPlatformAlert(env.DB, alertKey, "AL-17", nowIso);
  await env.DB.prepare(
    `UPDATE platform_alert SET next_send_at = ? WHERE alert_key = ?`,
  )
    .bind(nextSendAt, alertKey)
    .run();
  await sendAl17Body(env, body, alertKey, nextSendAt);
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
  const nowMs = await clockNowMs(env);
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
    const body =
      row.alert_key === "AL-17:global"
        ? { code: "AL-17" }
        : {
            code: "AL-17",
            org_id: row.alert_key.slice("AL-17:clinic:".length),
          };
    const nextSendAt = new Date(nowMs + ONE_HOUR_MS).toISOString();
    await sendAl17Body(env, body, row.alert_key, nextSendAt);
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
