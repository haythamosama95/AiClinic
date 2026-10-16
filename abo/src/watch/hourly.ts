import { CHANNEL_VERSIONS } from "vendor-contracts";
import { raiseAlert, sendDueAlerts, type AlertEnv } from "../alert/index.js";
import { loadIssuerPins, type BillingAuthEnv } from "../clinic-api/auth.js";
import { clockNowMs, type ClockEnv } from "../clock.js";

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

async function raiseAl15IfFeedStale(env: WatchEnv, nowMs: number): Promise<void> {
  let lastPullAt: string | null | undefined;
  try {
    const response = await env.PLATFORM.feedConsumerHealth({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    });
    if (response.result === "ok" && typeof response.detail === "string") {
      const detail = JSON.parse(response.detail) as {
        last_pull_at?: string | null;
      };
      lastPullAt = detail.last_pull_at;
    }
  } catch {
    await raiseAlert(env, "AL-15", "AL-15:feed", "feed");
    return;
  }

  if (lastPullAt === null || lastPullAt === undefined) {
    await raiseAlert(env, "AL-15", "AL-15:feed", "feed");
    return;
  }

  const lastPullMs = Date.parse(lastPullAt);
  if (Number.isNaN(lastPullMs) || nowMs - lastPullMs > FIVE_MINUTES_MS) {
    await raiseAlert(env, "AL-15", "AL-15:feed", "feed");
  }
}

async function raiseAl22ForIssuerPinMismatch(env: WatchEnv): Promise<void> {
  const pins = await loadIssuerPins(env);
  const contractArgs = { contract_version: CHANNEL_VERSIONS.vendorEntrypoint };

  let issuerKeys: IssuerKeyRow[] = [];
  try {
    const response = await env.PLATFORM.listIssuerKeys(contractArgs);
    if (response.result === "ok" && typeof response.detail === "string") {
      issuerKeys = JSON.parse(response.detail) as IssuerKeyRow[];
    }
  } catch {
    return;
  }

  const platformByKid = new Map<string, string>();
  for (const key of issuerKeys) {
    platformByKid.set(key.kid, key.public_key);
  }

  for (const [kid, publicKey] of platformByKid) {
    if (pins.get(kid) !== publicKey) {
      await raiseAlert(env, "AL-22", `AL-22:issuer:${kid}`, kid);
    }
  }

  for (const [kid] of pins) {
    if (!platformByKid.has(kid)) {
      await raiseAlert(env, "AL-22", `AL-22:issuer:${kid}`, kid);
    }
  }
}

async function raiseAl22ForUnannouncedCredentials(env: WatchEnv): Promise<void> {
  let credentials: OperatorCredentialRow[] = [];
  try {
    const response = await env.PLATFORM.listOperatorCredentials({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    });
    if (response.result === "ok" && typeof response.detail === "string") {
      credentials = JSON.parse(response.detail) as OperatorCredentialRow[];
    }
  } catch {
    return;
  }

  let seenRows: Array<{
    credential_id: string;
    public_key_cose: string;
    alg: string;
  }> = [];
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
    return;
  }

  const seenTriples = new Set(
    seenRows.map(
      (row) => `${row.credential_id}:${row.public_key_cose}:${row.alg}`,
    ),
  );

  for (const credential of credentials) {
    const triple = `${credential.credential_id}:${credential.public_key_cose}:${credential.alg}`;
    if (!seenTriples.has(triple)) {
      await raiseAlert(
        env,
        "AL-22",
        `AL-22:credential:${credential.credential_id}`,
        credential.credential_id,
      );
    }
  }
}

export async function runHourlyWatch(env: WatchEnv): Promise<void> {
  const nowMs = await clockNowMs(env);
  await raiseAl15IfFeedStale(env, nowMs);
  await raiseAl22ForIssuerPinMismatch(env);
  await raiseAl22ForUnannouncedCredentials(env);
  await sendDueAlerts(env);
}
