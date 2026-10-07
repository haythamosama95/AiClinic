import { CHANNEL_VERSIONS } from "vendor-contracts";
import { raiseAlert, type AlertEnv } from "../alert/index.js";
import { clockNowMs, type ClockEnv } from "../clock.js";

const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const THIRTY_DAYS_MS = 30 * ONE_DAY_MS;
const EXPORT_LAG_ALERT_KEY = "AL-16:export-lag";
const R2_LOCK_ALERT_KEY = "AL-16:r2-lock";

type IssuerKeyRow = {
  kid: string;
  public_key: string;
  status: string;
  not_before: string;
  not_after: string;
};

type ServiceKeyRow = {
  kid: string;
  status: string;
  not_before: string;
  not_after: string;
};

type GrantRow = {
  grant_id: string;
  source_kind: string;
  envelope: string;
};

type FindingRow = {
  finding_id: string;
  kind: string;
  subject: string;
  detail: string;
  detected_at: string;
};

type WorkRow = {
  work_id: string;
  kind: string;
  subject_id: string;
  state: string;
  opened_at: string;
};

type AlertRow = {
  alert_key: string;
  code: string;
  active: number;
  detail_id: string;
};

type JobRunRow = {
  job: string;
  last_run_at: string;
};

type ChannelVersionRow = {
  channel: string;
  contract_version: number;
  received: number;
  unsupported: number;
};

type CountRow = {
  label: string;
  count: number;
};

export type DigestEnv = ClockEnv &
  AlertEnv & {
    DB: D1Database;
    PLATFORM: {
      listIssuerKeys(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
      listServiceKeys(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
      feedConsumerHealth(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
    };
  };

function keyExpiresWithin30Days(notAfter: string, nowMs: number): boolean {
  const notAfterMs = Date.parse(notAfter);
  if (Number.isNaN(notAfterMs)) {
    return false;
  }
  return notAfterMs > nowMs && notAfterMs <= nowMs + THIRTY_DAYS_MS;
}

async function raiseAl14ForExpiringKeys(
  env: DigestEnv,
  nowMs: number,
): Promise<void> {
  const contractArgs = { contract_version: CHANNEL_VERSIONS.vendorEntrypoint };

  let issuerKeys: IssuerKeyRow[] = [];
  try {
    const response = await env.PLATFORM.listIssuerKeys(contractArgs);
    if (response.result === "ok" && typeof response.detail === "string") {
      issuerKeys = JSON.parse(response.detail) as IssuerKeyRow[];
    }
  } catch {
    // Platform read failures must not block the digest.
  }

  for (const key of issuerKeys) {
    if (keyExpiresWithin30Days(key.not_after, nowMs)) {
      await raiseAlert(env, "AL-14", `AL-14:${key.kid}`, key.kid);
    }
  }

  let serviceKeys: ServiceKeyRow[] = [];
  try {
    const response = await env.PLATFORM.listServiceKeys(contractArgs);
    if (response.result === "ok" && typeof response.detail === "string") {
      serviceKeys = JSON.parse(response.detail) as ServiceKeyRow[];
    }
  } catch {
    // Platform read failures must not block the digest.
  }

  for (const key of serviceKeys) {
    if (keyExpiresWithin30Days(key.not_after, nowMs)) {
      await raiseAlert(env, "AL-14", `AL-14:${key.kid}`, key.kid);
    }
  }
}

async function countSince(
  db: D1Database,
  sql: string,
  sinceIso: string,
): Promise<number> {
  const row = await db.prepare(sql).bind(sinceIso).first<{ n: number }>();
  return row?.n ?? 0;
}

async function oldestUnexportedFactSeq(db: D1Database): Promise<number | null> {
  const row = await db
    .prepare(
      `SELECT fl.fact_seq
       FROM fact_log fl
       LEFT JOIN fact_export fe ON fl.fact_seq = fe.fact_seq
       WHERE fe.fact_seq IS NULL
       ORDER BY fl.fact_seq ASC
       LIMIT 1`,
    )
    .first<{ fact_seq: number }>();
  return row?.fact_seq ?? null;
}

async function readFeedConsumerHealth(
  env: DigestEnv,
): Promise<string | null> {
  try {
    const response = await env.PLATFORM.feedConsumerHealth({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    });
    if (response.result === "ok" && typeof response.detail === "string") {
      const detail = JSON.parse(response.detail) as {
        last_pull_at?: string | null;
      };
      return detail.last_pull_at ?? null;
    }
  } catch {
    // Platform read failures must not block the digest.
  }
  return null;
}

function grantEnvelopeDetails(envelopeJson: string): {
  operatorEmail: string;
  reason: string;
  dayCount: string;
  allowanceCredits: string;
  isAdjustment: boolean;
} {
  try {
    const envelope = JSON.parse(envelopeJson) as {
      source?: { operator_email?: string; reason?: string };
      duration?: { count?: number };
      allowance_credits?: number;
      adjustment?: unknown;
    };
    return {
      operatorEmail: envelope.source?.operator_email ?? "",
      reason: envelope.source?.reason ?? "",
      dayCount: String(envelope.duration?.count ?? ""),
      allowanceCredits: String(envelope.allowance_credits ?? ""),
      isAdjustment: envelope.adjustment !== undefined,
    };
  } catch {
    return {
      operatorEmail: "",
      reason: "",
      dayCount: "",
      allowanceCredits: "",
      isAdjustment: false,
    };
  }
}

async function buildDigestBody(env: DigestEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const sinceIso = new Date(nowMs - ONE_DAY_MS).toISOString();
  const lines: string[] = [];

  lines.push("ABO daily digest");
  lines.push(`window_start=${sinceIso}`);

  const checkoutCount = await countSince(
    env.DB,
    `SELECT COUNT(*) AS n FROM checkout_event
     WHERE kind = 'opened' AND at >= ?`,
    sinceIso,
  );
  lines.push(`checkouts_24h=${checkoutCount}`);

  const paymentCounts = await env.DB.prepare(
    `SELECT classification AS label, COUNT(*) AS count
     FROM payment WHERE paid_at >= ?
     GROUP BY classification ORDER BY classification`,
  )
    .bind(sinceIso)
    .all<CountRow>();
  lines.push("payments_24h_by_classification:");
  for (const row of paymentCounts.results ?? []) {
    lines.push(`  ${row.label}=${row.count}`);
  }

  const grantCounts = await env.DB.prepare(
    `SELECT gr.source_kind AS label, COUNT(*) AS count
     FROM grant_request gr
     INNER JOIN fact_log fl
       ON fl."table" = 'grant_request' AND fl.key = gr.grant_id
     WHERE fl.created_at >= ?
     GROUP BY gr.source_kind
     ORDER BY gr.source_kind`,
  )
    .bind(sinceIso)
    .all<CountRow>();
  lines.push("grants_by_source_kind:");
  for (const row of grantCounts.results ?? []) {
    lines.push(`  ${row.label}=${row.count}`);
  }

  const reversalCount = await countSince(
    env.DB,
    `SELECT COUNT(*) AS n
     FROM reversal r
     INNER JOIN reversal_outcome ro ON r.reversal_id = ro.reversal_id
     WHERE ro.at >= ?`,
    sinceIso,
  );
  lines.push(`reversals_24h=${reversalCount}`);

  const alertCount = await countSince(
    env.DB,
    `SELECT COUNT(*) AS n FROM alert WHERE last_sent_at >= ?`,
    sinceIso,
  );
  lines.push(`alerts_sent_24h=${alertCount}`);

  lines.push("grants:");
  const grants = await env.DB.prepare(
    `SELECT grant_id, source_kind, envelope FROM grant_request ORDER BY grant_id`,
  ).all<GrantRow>();
  for (const grant of grants.results ?? []) {
    const details = grantEnvelopeDetails(grant.envelope);
    lines.push(`  grant_id=${grant.grant_id}`);
    lines.push(`  source_kind=${grant.source_kind}`);
    lines.push(`  operator=${details.operatorEmail}`);
    lines.push(`  reason=${details.reason}`);
    lines.push(`  length_days=${details.dayCount}`);
    lines.push(`  allowance=${details.allowanceCredits}`);
    if (details.isAdjustment) {
      lines.push(`  adjustment=true`);
    }
  }

  lines.push("open_findings:");
  const findings = await env.DB.prepare(
    `SELECT f.finding_id, f.kind, f.subject, f.detail, f.detected_at
     FROM finding f
     LEFT JOIN finding_resolution fr ON f.finding_id = fr.finding_id
     WHERE fr.finding_id IS NULL
     ORDER BY f.finding_id`,
  ).all<FindingRow>();
  for (const finding of findings.results ?? []) {
    lines.push(
      `  ${finding.finding_id} kind=${finding.kind} subject=${finding.subject} detail=${finding.detail} at=${finding.detected_at}`,
    );
  }

  lines.push("parked_work:");
  const workRows = await env.DB.prepare(
    `SELECT work_id, kind, subject_id, state, opened_at
     FROM work WHERE state = 'parked' ORDER BY work_id`,
  ).all<WorkRow>();
  for (const work of workRows.results ?? []) {
    lines.push(
      `  ${work.work_id} kind=${work.kind} subject=${work.subject_id} state=${work.state} opened_at=${work.opened_at}`,
    );
  }

  lines.push("open_alerts:");
  const alertRows = await env.DB.prepare(
    `SELECT alert_key, code, active, detail_id
     FROM alert WHERE active = 1 ORDER BY alert_key`,
  ).all<AlertRow>();
  for (const alert of alertRows.results ?? []) {
    lines.push(
      `  ${alert.alert_key} code=${alert.code} detail=${alert.detail_id}`,
    );
  }

  lines.push("scheduled_job_runs:");
  try {
    const jobRuns = await env.DB.prepare(
      `SELECT job, last_run_at FROM scheduled_job_run ORDER BY job`,
    ).all<JobRunRow>();
    for (const job of jobRuns.results ?? []) {
      lines.push(`  ${job.job} last_run_at=${job.last_run_at}`);
    }
  } catch {
    // Missing table is ignored.
  }

  const lastPullAt = await readFeedConsumerHealth(env);
  lines.push(`backend_last_pull=${lastPullAt ?? "null"}`);

  const exportLagSeq = await oldestUnexportedFactSeq(env.DB);
  lines.push(`export_lag_fact_seq=${exportLagSeq ?? "none"}`);

  const exportLagAlert = await env.DB.prepare(
    `SELECT active, detail_id FROM alert WHERE alert_key = ?`,
  )
    .bind(EXPORT_LAG_ALERT_KEY)
    .first<{ active: number; detail_id: string }>();
  lines.push(
    `export_lag_alert_active=${exportLagAlert?.active ?? 0} detail=${exportLagAlert?.detail_id ?? ""}`,
  );

  const r2LockAlert = await env.DB.prepare(
    `SELECT active, detail_id FROM alert WHERE alert_key = ?`,
  )
    .bind(R2_LOCK_ALERT_KEY)
    .first<{ active: number; detail_id: string }>();
  lines.push(
    `r2_lock_alert_active=${r2LockAlert?.active ?? 0} detail=${r2LockAlert?.detail_id ?? ""}`,
  );

  lines.push("keys_expiring_within_30_days:");
  const contractArgs = { contract_version: CHANNEL_VERSIONS.vendorEntrypoint };
  try {
    const issuerResponse = await env.PLATFORM.listIssuerKeys(contractArgs);
    if (issuerResponse.result === "ok" && typeof issuerResponse.detail === "string") {
      const issuerKeys = JSON.parse(issuerResponse.detail) as IssuerKeyRow[];
      for (const key of issuerKeys) {
        if (keyExpiresWithin30Days(key.not_after, nowMs)) {
          lines.push(`  issuer kid=${key.kid} not_after=${key.not_after}`);
        }
      }
    }
  } catch {
    // Platform read failures must not block the digest.
  }
  try {
    const serviceResponse = await env.PLATFORM.listServiceKeys(contractArgs);
    if (serviceResponse.result === "ok" && typeof serviceResponse.detail === "string") {
      const serviceKeys = JSON.parse(serviceResponse.detail) as ServiceKeyRow[];
      for (const key of serviceKeys) {
        if (keyExpiresWithin30Days(key.not_after, nowMs)) {
          lines.push(`  service kid=${key.kid} not_after=${key.not_after}`);
        }
      }
    }
  } catch {
    // Platform read failures must not block the digest.
  }

  lines.push("channel_version_seen:");
  try {
    const versionRows = await env.DB.prepare(
      `SELECT channel, contract_version, received, unsupported
       FROM channel_version_seen
       WHERE channel IN ('aboClinic', 'aboConsole')
       ORDER BY channel, contract_version`,
    ).all<ChannelVersionRow>();
    for (const row of versionRows.results ?? []) {
      lines.push(
        `  ${row.channel} version=${row.contract_version} received=${row.received} contract_version_unsupported=${row.unsupported}`,
      );
    }
  } catch {
    // Missing table is ignored.
  }

  return lines.join("\n");
}

async function sendDigestEmail(env: DigestEnv, body: string): Promise<void> {
  const message = {
    from: env.ALERT_EMAIL_TO,
    to: env.ALERT_EMAIL_TO,
    subject: "digest",
    text: body,
  };
  try {
    await env.SEND_EMAIL.send(message);
  } catch {
    await env.SEND_EMAIL.send(message);
  }
}

export async function runDailyDigest(env: DigestEnv): Promise<void> {
  const nowMs = await clockNowMs(env);
  await raiseAl14ForExpiringKeys(env, nowMs);
  const body = await buildDigestBody(env);
  await sendDigestEmail(env, body);
}
