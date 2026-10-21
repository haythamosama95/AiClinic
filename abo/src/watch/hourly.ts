import { CHANNEL_VERSIONS } from "vendor-contracts";
import {
  deactivateAlert,
  raiseAlert,
  sendDueAlerts,
  type AlertEnv,
} from "../alert/index.js";
import { loadIssuerPins, type BillingAuthEnv } from "../clinic-api/auth.js";
import { clockNowMs, type ClockEnv } from "../clock.js";
import type { JobOutcome } from "../scheduler/jobs.js";

const FIVE_MINUTES_MS = 5 * 60 * 1000;

type IssuerKeyRow = {
  kid: string;
  public_key: string;
  status: string;
  not_before: string;
  not_after: string;
};

type OperatorCredentialRow = {
  credential_id: string;
  public_key_cose: string;
  alg: string;
};

export type WatchEnv = ClockEnv &
  AlertEnv &
  BillingAuthEnv & {
    DB: D1Database;
    PLATFORM: {
      listIssuerKeys(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
      listOperatorCredentials(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
      feedConsumerHealth(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
    };
  };

export async function rememberOperatorCredential(
  db: D1Database,
  credential: {
    credential_id: string;
    public_key_cose: string;
    alg: string;
  },
): Promise<void> {
  try {
    await db
      .prepare(
        `INSERT OR IGNORE INTO seen_operator_credential (
           credential_id, public_key_cose, alg
         ) VALUES (?, ?, ?)`,
      )
      .bind(
        credential.credential_id,
        credential.public_key_cose,
        credential.alg,
      )
      .run();
  } catch {
    // Missing table is ignored.
  }
}

const AL15_KEY = "AL-15:feed";
const AL22_ISSUER_PREFIX = "AL-22:issuer:";
const AL22_CREDENTIAL_PREFIX = "AL-22:credential:";

// R9-AO5: returns false when the read is unknown (thrown, refused or malformed). An
// unknown read raises as before and clears nothing.
async function reconcileAl15Feed(env: WatchEnv, nowMs: number): Promise<boolean> {
  let lastPullAt: string | null | undefined;
  try {
    const response = await env.PLATFORM.feedConsumerHealth({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    });
    if (response.result !== "ok" || typeof response.detail !== "string") {
      await raiseAlert(env, "AL-15", AL15_KEY, "feed");
      return false;
    }
    const detail = JSON.parse(response.detail) as {
      last_pull_at?: string | null;
    };
    if (detail.last_pull_at === undefined) {
      await raiseAlert(env, "AL-15", AL15_KEY, "feed");
      return false;
    }
    lastPullAt = detail.last_pull_at;
  } catch {
    await raiseAlert(env, "AL-15", AL15_KEY, "feed");
    return false;
  }

  if (lastPullAt === null) {
    await raiseAlert(env, "AL-15", AL15_KEY, "feed");
    return true;
  }

  const lastPullMs = Date.parse(lastPullAt);
  if (Number.isNaN(lastPullMs)) {
    await raiseAlert(env, "AL-15", AL15_KEY, "feed");
    return false;
  }
  if (nowMs - lastPullMs > FIVE_MINUTES_MS) {
    await raiseAlert(env, "AL-15", AL15_KEY, "feed");
    return true;
  }
  // A valid fresh health result proves recovery, so the repeat stops.
  await deactivateAlert(env, AL15_KEY);
  return true;
}

// Deactivates active alerts with the given prefix whose mismatch is not in the current set.
async function clearResolvedAl22(
  env: WatchEnv,
  prefix: string,
  currentKeys: ReadonlySet<string>,
): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT alert_key FROM alert WHERE active = 1 AND alert_key LIKE ?`,
  )
    .bind(`${prefix}%`)
    .all<{ alert_key: string }>();
  for (const row of rows.results ?? []) {
    const key = row.alert_key.slice(prefix.length);
    if (!currentKeys.has(key)) {
      await deactivateAlert(env, row.alert_key);
    }
  }
}

async function reconcileAl22Issuer(env: WatchEnv): Promise<boolean> {
  const pins = await loadIssuerPins(env);
  const contractArgs = { contract_version: CHANNEL_VERSIONS.vendorEntrypoint };

  let issuerKeys: IssuerKeyRow[];
  try {
    const response = await env.PLATFORM.listIssuerKeys(contractArgs);
    if (response.result !== "ok" || typeof response.detail !== "string") {
      return false;
    }
    const parsed = JSON.parse(response.detail) as unknown;
    if (!Array.isArray(parsed)) {
      return false;
    }
    issuerKeys = parsed as IssuerKeyRow[];
  } catch {
    return false;
  }

  const platformByKid = new Map<string, string>();
  for (const key of issuerKeys) {
    platformByKid.set(key.kid, key.public_key);
  }

  const mismatched = new Set<string>();
  for (const [kid, publicKey] of platformByKid) {
    if (pins.get(kid) !== publicKey) {
      mismatched.add(kid);
    }
  }
  for (const [kid] of pins) {
    if (!platformByKid.has(kid)) {
      mismatched.add(kid);
    }
  }
  for (const kid of mismatched) {
    await raiseAlert(env, "AL-22", `${AL22_ISSUER_PREFIX}${kid}`, kid);
  }
  await clearResolvedAl22(env, AL22_ISSUER_PREFIX, mismatched);
  return true;
}

async function reconcileAl22Credentials(env: WatchEnv): Promise<boolean> {
  let credentials: OperatorCredentialRow[];
  try {
    const response = await env.PLATFORM.listOperatorCredentials({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    });
    if (response.result !== "ok" || typeof response.detail !== "string") {
      return false;
    }
    const parsed = JSON.parse(response.detail) as unknown;
    if (!Array.isArray(parsed)) {
      return false;
    }
    credentials = parsed as OperatorCredentialRow[];
  } catch {
    return false;
  }

  let seenRows: Array<{
    credential_id: string;
    public_key_cose: string;
    alg: string;
  }>;
  try {
    const result = await env.DB.prepare(
      `SELECT credential_id, public_key_cose, alg
       FROM seen_operator_credential`,
    ).all<{
      credential_id: string;
      public_key_cose: string;
      alg: string;
    }>();
    seenRows = result.results ?? [];
  } catch {
    return false;
  }

  const seenTriples = new Set(
    seenRows.map(
      (row) => `${row.credential_id}:${row.public_key_cose}:${row.alg}`,
    ),
  );

  const unannounced = new Set<string>();
  for (const credential of credentials) {
    const triple = `${credential.credential_id}:${credential.public_key_cose}:${credential.alg}`;
    if (!seenTriples.has(triple)) {
      unannounced.add(credential.credential_id);
    }
  }
  for (const credentialId of unannounced) {
    await raiseAlert(
      env,
      "AL-22",
      `${AL22_CREDENTIAL_PREFIX}${credentialId}`,
      credentialId,
    );
  }
  await clearResolvedAl22(env, AL22_CREDENTIAL_PREFIX, unannounced);
  return true;
}

// R9-CRON1 / R9-AO5: the watch job is succeeded only when all three reads were complete.
export async function runHourlyWatch(env: WatchEnv): Promise<JobOutcome> {
  const nowMs = await clockNowMs(env);
  const al15 = await reconcileAl15Feed(env, nowMs);
  const issuer = await reconcileAl22Issuer(env);
  const credentials = await reconcileAl22Credentials(env);
  await sendDueAlerts(env);
  return al15 && issuer && credentials ? "succeeded" : "failed";
}
