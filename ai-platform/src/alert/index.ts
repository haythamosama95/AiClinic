import { CHANNEL_VERSIONS } from "vendor-contracts";
import { clockNowIso } from "../clock";
import { sendPlatformEmail, type SendEmailEnv } from "./email";

export type AlertEnv = SendEmailEnv & {
  DB: D1Database;
  ALERT_EMAIL_TO: string;
  HEARTBEAT_URL: string;
};

const FIVE_MINUTE_CRON = "*/5 * * * *";

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
    if (row.code !== "AL-13") {
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

export async function runFiveMinuteCron(env: AlertEnv): Promise<void> {
  await runFiveMinuteJob(env, "alert_retry", () =>
    retryUnsentPlatformAlerts(env),
  );
  await runFiveMinuteJob(env, "heartbeat", () => pingPlatformHeartbeat(env));
}
