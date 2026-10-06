/**
 * H-ABO system-test harness (P4.1).
 */

import { env, SELF } from "cloudflare:test";
import { createIssuer } from "vendor-contracts/testkit";
import recordsMigrationSql from "../../migrations/0001_records.sql?raw";

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
    R2: R2Bucket;
    BILLING_HOST: string;
    OPS_HOST: string;
    HEARTBEAT_URL: string;
    ALERT_EMAIL_TO: string;
    ISSUER_ID: string;
    ISSUER_KEYS: string;
    CLOUDFLARE_ACCOUNT_ID: string;
    R2_BUCKET_NAME: string;
    R2_LOCK_READ_TOKEN: string;
    TEST_CLOCK: string;
    PAYMOB_STUB: Fetcher;
    PAYMOB_BASE_URL: string;
    PAYMOB_HMAC_SECRET: string;
    PAYMOB_API_KEY: string;
    SEND_EMAIL: {
      send(message: {
        from: string;
        to: string;
        subject: string;
        text: string;
      }): Promise<void>;
    };
  }
}

export const BILLING_ORIGIN = `https://${env.BILLING_HOST}`;
export const OPS_ORIGIN = `https://${env.OPS_HOST}`;

const DEFAULT_LOCK_BODY = {
  success: true,
  result: {
    rules: [
      {
        enabled: true,
        condition: { type: "Indefinite" },
        prefix: "ledger/",
      },
    ],
  },
};

let lockRulesBody: unknown = DEFAULT_LOCK_BODY;
let lockMockReady = false;

const heartbeatHarness = {
  capturedFetches: [] as string[],
  fetchThrows: false,
  interceptReady: false,
};

export const harnessState = {
  capturedEmails: [] as Array<{
    from: string;
    to: string;
    subject: string;
    text: string;
  }>,
  sendEmailThrows: false,
};

export const sendEmailBinding = {
  async send(message: {
    from: string;
    to: string;
    subject: string;
    text: string;
  }): Promise<void> {
    if (harnessState.sendEmailThrows) {
      throw new Error("send_email failure injected by harness");
    }
    harnessState.capturedEmails.push({ ...message });
  },
};

function splitSqlStatements(sql: string): string[] {
  const withoutComments = sql.replace(/--[^\n]*\n/g, "\n");
  const statements: string[] = [];
  let start = 0;
  let index = 0;
  let beginDepth = 0;

  const pushStatement = (end: number): void => {
    const chunk = withoutComments.slice(start, end).trim();
    if (chunk.length > 0) {
      statements.push(chunk);
    }
    start = end;
  };

  while (index < withoutComments.length) {
    const remaining = withoutComments.slice(index);
    const beginMatch = remaining.match(/^\s*BEGIN\b/i);
    if (beginMatch) {
      beginDepth += 1;
      index += beginMatch[0].length;
      continue;
    }
    const endMatch = remaining.match(/^\s*END\s*;/i);
    if (endMatch) {
      beginDepth = Math.max(0, beginDepth - 1);
      index += endMatch[0].length;
      if (beginDepth === 0) {
        pushStatement(index);
      }
      continue;
    }
    if (withoutComments[index] === ";" && beginDepth === 0) {
      index += 1;
      pushStatement(index);
      continue;
    }
    index += 1;
  }

  pushStatement(withoutComments.length);
  return statements;
}

export async function applySql(sql: string): Promise<void> {
  for (const statement of splitSqlStatements(sql)) {
    try {
      await env.DB.prepare(statement).run();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!/already exists/i.test(message)) {
        throw error;
      }
    }
  }
}

export async function applyRecordsMigration(): Promise<void> {
  try {
    await applySql(recordsMigrationSql);
  } catch {
    // Migration not added yet.
  }
}

async function ensureHarnessSchema(): Promise<void> {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS harness_test_clock (
       id TEXT PRIMARY KEY,
       now_iso TEXT NOT NULL
     )`,
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS harness_issuer_pin (
       kid TEXT PRIMARY KEY,
       public_key TEXT NOT NULL
     )`,
  ).run();
}

export async function setClock(isoUtc: string): Promise<void> {
  await ensureHarnessSchema();
  await env.DB.prepare(
    `INSERT OR REPLACE INTO harness_test_clock (id, now_iso) VALUES ('default', ?)`,
  )
    .bind(isoUtc)
    .run();
}

export async function pinIssuer(
  kid: string,
  publicKey: CryptoKey,
): Promise<void> {
  await ensureHarnessSchema();
  const raw = await crypto.subtle.exportKey("raw", publicKey);
  const publicKeyB64 = base64UrlEncode(new Uint8Array(raw));
  await env.DB.prepare(
    `INSERT OR REPLACE INTO harness_issuer_pin (kid, public_key) VALUES (?, ?)`,
  )
    .bind(kid, publicKeyB64)
    .run();
}

export function billingFetch(
  path: string,
  init?: RequestInit,
): Promise<Response> {
  return SELF.fetch(
    new Request(`${BILLING_ORIGIN}${path}`, {
      ...init,
      headers: init?.headers,
    }),
  );
}

export function opsFetch(path: string, init?: RequestInit): Promise<Response> {
  return SELF.fetch(
    new Request(`${OPS_ORIGIN}${path}`, {
      ...init,
      headers: init?.headers,
    }),
  );
}

export async function newIssuer() {
  return createIssuer({ issuerId: env.ISSUER_ID });
}

export async function mintBilling(
  issuer: Awaited<ReturnType<typeof newIssuer>>,
  claims: {
    sub: string;
    org: string;
    role: string;
    branch: string;
    iat: number;
    exp: number;
    jti: string;
  },
): Promise<string> {
  return issuer.mintBilling(claims);
}

export async function mintAi(
  issuer: Awaited<ReturnType<typeof newIssuer>>,
  claims: {
    sub: string;
    org: string;
    role: string;
    branch: string;
    scopes: string[];
    iat: number;
    exp: number;
    jti: string;
  },
): Promise<string> {
  return issuer.mintAi(claims);
}

export async function r2Put(key: string, body: string): Promise<void> {
  await env.R2.put(key, body);
}

export async function r2GetText(key: string): Promise<string | null> {
  const object = await env.R2.get(key);
  if (!object) {
    return null;
  }
  return object.text();
}

export function setLockRulesBody(body: unknown): void {
  lockRulesBody = body;
}

async function ensureLockRulesMock(): Promise<void> {
  if (lockMockReady) {
    return;
  }
  const { fetchMock } = await import("cloudflare:test");
  const accountId = env.CLOUDFLARE_ACCOUNT_ID;
  const bucketName = env.R2_BUCKET_NAME;
  const path = `/client/v4/accounts/${accountId}/r2/buckets/${bucketName}/lock`;
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock
    .get("https://api.cloudflare.com")
    .intercept({ path, method: "GET" })
    .reply(() => ({
      statusCode: 200,
      data: JSON.stringify(lockRulesBody),
    }))
    .persist();
  lockMockReady = true;
}

async function ensureHeartbeatFetchMock(): Promise<void> {
  if (heartbeatHarness.interceptReady) {
    return;
  }
  const { fetchMock } = await import("cloudflare:test");
  const heartbeatUrl = env.HEARTBEAT_URL;
  const parsed = new URL(heartbeatUrl);
  await ensureLockRulesMock();
  fetchMock
    .get(parsed.origin)
    .intercept({ path: parsed.pathname, method: "GET" })
    .reply(() => {
      heartbeatHarness.capturedFetches.push(heartbeatUrl);
      if (heartbeatHarness.fetchThrows) {
        throw new Error("heartbeat fetch failure injected by harness");
      }
      return { statusCode: 200, data: "ok" };
    })
    .persist();
  heartbeatHarness.interceptReady = true;
}

export function setSendEmailThrows(throws: boolean): void {
  harnessState.sendEmailThrows = throws;
}

export function setHeartbeatFetchThrows(throws: boolean): void {
  heartbeatHarness.fetchThrows = throws;
}

export function clearCapturedHeartbeatFetches(): void {
  heartbeatHarness.capturedFetches.length = 0;
}

export function getCapturedHeartbeatFetches(): ReadonlyArray<string> {
  return heartbeatHarness.capturedFetches;
}

export function clearCapturedEmails(): void {
  harnessState.capturedEmails.length = 0;
}

export function getCapturedEmails(): ReadonlyArray<{
  from: string;
  to: string;
  subject: string;
  text: string;
}> {
  return harnessState.capturedEmails;
}

let paymobMockReady = false;
let intakeR2PutThrows = false;
let d1BatchThrows = false;
let r2PutWrapped = false;
let dbBatchWrapped = false;

export type PaymobInquiryScript =
  | "bound_success"
  | "unbound"
  | "amount_mismatch"
  | "reversed"
  | "pending"
  | "timeout"
  | "rate_limit";

async function ensurePaymobFetchMock(): Promise<void> {
  if (paymobMockReady) {
    return;
  }
  const { fetchMock } = await import("cloudflare:test");
  const baseUrl = env.PAYMOB_BASE_URL;
  const origin = new URL(baseUrl).origin;
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock
    .get(origin)
    .intercept({ path: () => true, method: () => true })
    .reply(async (opts) => {
      try {
        const pathPart = typeof opts.path === "string" ? opts.path : "/";
        const target = new URL(pathPart, baseUrl).toString();
        const response = await env.PAYMOB_STUB.fetch(target, {
          method: opts.method,
          headers: opts.headers as HeadersInit | undefined,
          body: opts.body as BodyInit | undefined,
          signal: opts.signal as AbortSignal | undefined,
        });
        const data = await response.arrayBuffer();
        return {
          statusCode: response.status,
          data: new TextDecoder().decode(data),
        };
      } catch {
        return { statusCode: 502, data: "paymob stub forward failed" };
      }
    })
    .persist();
  paymobMockReady = true;
}

function ensureR2PutWrapper(): void {
  if (r2PutWrapped) {
    return;
  }
  const originalPut = env.R2.put.bind(env.R2);
  env.R2.put = async (
    key: string,
    value:
      | ReadableStream
      | ArrayBuffer
      | ArrayBufferView
      | string
      | null
      | Blob,
    options?: R2PutOptions,
  ): Promise<R2Object | null> => {
    if (intakeR2PutThrows) {
      intakeR2PutThrows = false;
      throw new Error("R2 put failure injected by harness");
    }
    return originalPut(key, value, options);
  };
  r2PutWrapped = true;
}

function ensureD1BatchWrapper(): void {
  if (dbBatchWrapped) {
    return;
  }
  const originalBatch = env.DB.batch.bind(env.DB);
  env.DB.batch = async (
    statements: D1PreparedStatement[],
  ): Promise<D1Result[]> => {
    if (d1BatchThrows) {
      d1BatchThrows = false;
      throw new Error("D1 batch failure injected by harness");
    }
    return originalBatch(statements);
  };
  dbBatchWrapped = true;
}

export function setIntakeR2PutThrows(active: boolean): void {
  intakeR2PutThrows = active;
  ensureR2PutWrapper();
}

export function setD1BatchThrows(active: boolean): void {
  d1BatchThrows = active;
  ensureD1BatchWrapper();
}

export async function scriptPaymobInquiry(
  script: PaymobInquiryScript,
): Promise<void> {
  await env.PAYMOB_STUB.fetch("http://paymob.stub/__script", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ inquiry: script }),
  });
}

export async function runScheduled(cron: string): Promise<void> {
  await ensureHeartbeatFetchMock();
  const workerModule = await import("../../src/worker");
  await workerModule.default.scheduled(
    { cron, scheduledTime: Date.now(), noRetry() {} },
    env as never,
    {} as ExecutionContext,
  );
}

export async function tableCount(table: string): Promise<number> {
  try {
    const row = await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first<{
      n: number;
    }>();
    return row?.n ?? 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return 0;
    }
    throw error;
  }
}

export async function setupHarness(): Promise<void> {
  await applyRecordsMigration();
  await ensureHarnessSchema();
  await ensureHeartbeatFetchMock();
  await ensurePaymobFetchMock();
  Object.assign(env.SEND_EMAIL, sendEmailBinding);
  lockRulesBody = DEFAULT_LOCK_BODY;
  harnessState.sendEmailThrows = false;
  heartbeatHarness.fetchThrows = false;
  intakeR2PutThrows = false;
  d1BatchThrows = false;
  clearCapturedEmails();
  clearCapturedHeartbeatFetches();
  await setClock(new Date().toISOString());
  try {
    await scriptPaymobInquiry("bound_success");
  } catch {
    // PAYMOB_STUB binding not configured yet.
  }
}

export async function resetHarnessState(): Promise<void> {
  await setupHarness();
  await env.DB.prepare("DELETE FROM harness_test_clock").run();
  await env.DB.prepare("DELETE FROM harness_issuer_pin").run();
  for (const table of ["token_use", "billing_contact"]) {
    try {
      await env.DB.prepare(`DELETE FROM ${table}`).run();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!/no such table/i.test(message)) {
        throw error;
      }
    }
  }
  await setClock(new Date().toISOString());
}
