import { sha256Hex, ulid } from "vendor-contracts";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import { raiseAlert } from "../alert/index.js";
import { PAYMOB_PROVIDER_ID, providerForId } from "../provider/registry.js";
import type { PaymobAdapterEnv } from "../provider/paymob/adapter.js";

const NOTIFY_ADAPTER_VERSION = 1;
import type { ProviderNotificationRequest } from "../provider/port.js";
import { runDueGrantWork, type GrantEnv } from "../work/grant.js";
import { runConfirmForWorkId } from "../work/runner.js";

const MAX_NOTIFY_BODY_BYTES = 1_048_576;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 60;
const HMAC_RAW_BODY_HOURLY_CAP = 10;
const AL02_WINDOW_MS = 15 * 60 * 1000;
const AL02_THRESHOLD = 3;

export type NotifyIntakeEnv = PaymobAdapterEnv &
  ClockEnv & {
    R2: R2Bucket;
    PAYMOB_HMAC_SECRET: string;
  };

function emptyResponse(status: number): Response {
  return new Response(null, { status });
}

function neutralReturnHtml(): Response {
  const html =
    "<!DOCTYPE html><html><body><p>Please return to your clinic application.</p></body></html>";
  return new Response(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

function connectingIp(request: Request): string {
  return request.headers.get("CF-Connecting-IP") ?? "unknown";
}

async function newId(env: NotifyIntakeEnv, bumpMs = 0): Promise<string> {
  const nowMs = (await clockNowMs(env)) + bumpMs;
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

async function checkNotifyRate(
  env: NotifyIntakeEnv,
  ip: string,
): Promise<boolean> {
  const nowMs = await clockNowMs(env);
  const windowStart = Math.floor(nowMs / RATE_LIMIT_WINDOW_MS) * RATE_LIMIT_WINDOW_MS;
  const row = await env.DB.prepare(
    `SELECT window_start_ms, hits FROM notify_rate WHERE ip = ?`,
  )
    .bind(ip)
    .first<{ window_start_ms: number; hits: number }>();

  if (row === null) {
    await env.DB.prepare(
      `INSERT INTO notify_rate (ip, window_start_ms, hits) VALUES (?, ?, 1)`,
    )
      .bind(ip, windowStart)
      .run();
    return true;
  }

  if (row.window_start_ms !== windowStart) {
    await env.DB.prepare(
      `UPDATE notify_rate SET window_start_ms = ?, hits = 1 WHERE ip = ?`,
    )
      .bind(windowStart, ip)
      .run();
    return true;
  }

  if (row.hits >= RATE_LIMIT_MAX) {
    return false;
  }

  await env.DB.prepare(`UPDATE notify_rate SET hits = hits + 1 WHERE ip = ?`)
    .bind(ip)
    .run();
  return true;
}

async function hmacFailuresInWindow(
  env: NotifyIntakeEnv,
  nowMs: number,
  windowMs: number,
): Promise<number> {
  const listed = await env.R2.list({ prefix: "hmac-invalid/" });
  let count = 0;
  for (const object of listed.objects) {
    const uploadedMs = object.uploaded.getTime();
    if (nowMs - uploadedMs <= windowMs) {
      count += 1;
    }
  }
  return count;
}

async function hmacRawBodiesInHour(env: NotifyIntakeEnv, nowMs: number): Promise<number> {
  const listed = await env.R2.list({ prefix: "hmac-invalid/" });
  let count = 0;
  for (const object of listed.objects) {
    if (nowMs - object.uploaded.getTime() > 60 * 60 * 1000) {
      continue;
    }
    const body = await env.R2.get(object.key);
    if (body === null) {
      continue;
    }
    const text = await body.text();
    if (text.length > 0) {
      count += 1;
    }
  }
  return count;
}

async function recordInvalidHmac(
  env: NotifyIntakeEnv,
  rawBody: string,
): Promise<void> {
  const nowMs = await clockNowMs(env);
  const nowIso = await clockNowIso(env);
  const day = nowIso.slice(0, 10);
  const objectId = await newId(env);
  const key = `hmac-invalid/${day}/${objectId}`;

  const rawInHour = await hmacRawBodiesInHour(env, nowMs);
  const payload = rawInHour < HMAC_RAW_BODY_HOURLY_CAP ? rawBody : "";
  await env.R2.put(key, payload);

  const failures15m = await hmacFailuresInWindow(env, nowMs, AL02_WINDOW_MS);
  if (failures15m >= AL02_THRESHOLD) {
    await raiseAlert(env, "AL-02", "AL-02:hmac-invalid", objectId);
  }
}

async function scheduleConfirmForCheckout(
  env: NotifyIntakeEnv,
  checkoutId: string,
): Promise<void> {
  const dedupeKey = `confirm-schedule:${checkoutId}`;
  const existing = await env.DB.prepare(
    `SELECT work_id FROM work WHERE dedupe_key = ?`,
  )
    .bind(dedupeKey)
    .first<{ work_id: string }>();
  if (existing !== null) {
    return;
  }

  const nowIso = await clockNowIso(env);
  const workId = await newId(env);
  await env.DB.prepare(
    `INSERT INTO work (
       work_id, kind, subject_id, dedupe_key, state, attempts,
       next_attempt_at, lease_until, last_error, opened_at
     ) VALUES (?, 'confirm', ?, ?, 'open', 0, ?, NULL, NULL, ?)`,
  )
    .bind(workId, checkoutId, dedupeKey, nowIso, nowIso)
    .run();
}

async function claimNotifyBodyDedupe(
  env: NotifyIntakeEnv,
  bodySha256: string,
): Promise<boolean> {
  const nowIso = await clockNowIso(env);
  const result = await env.DB.prepare(
    `INSERT INTO paymob_state_seen (dedupe_key, source, first_seen_at)
     VALUES (?, 'notify_body', ?)
     ON CONFLICT(dedupe_key) DO NOTHING`,
  )
    .bind(`notify-body:${bodySha256}`, nowIso)
    .run();
  return (result.meta.changes ?? 0) > 0;
}

async function insertEnqueuedNotificationAndConfirm(
  env: NotifyIntakeEnv,
  params: {
    notificationId: string;
    bodySha256: string;
    bodyR2Key: string;
    checkoutId: string;
    channel: "processed" | "response";
  },
): Promise<string | null> {
  if (!(await claimNotifyBodyDedupe(env, params.bodySha256))) {
    return null;
  }

  const nowIso = await clockNowIso(env);
  const confirmId = await newId(env);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO notification (
         notification_id, provider_id, channel, hmac_valid, body_r2_key,
         body_sha256, dedupe_key, checkout_id, disposition, adapter_version
       ) VALUES (?, ?, ?, 1, ?, ?, ?, ?, 'enqueued', ?)`,
    ).bind(
      params.notificationId,
      PAYMOB_PROVIDER_ID,
      params.channel,
      params.bodyR2Key,
      params.bodySha256,
      params.bodySha256,
      params.checkoutId,
      NOTIFY_ADAPTER_VERSION,
    ),
    env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, last_error, opened_at
       ) VALUES (?, 'confirm', ?, ?, 'open', 0, ?, NULL, NULL, ?)`,
    ).bind(
      confirmId,
      params.checkoutId,
      `confirm:${params.notificationId}`,
      nowIso,
      nowIso,
    ),
  ]);
  return confirmId;
}

async function insertDuplicateNotification(
  env: NotifyIntakeEnv,
  params: {
    notificationId: string;
    bodySha256: string;
    bodyR2Key: string;
    checkoutId: string | null;
    channel: "processed" | "response";
  },
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO notification (
       notification_id, provider_id, channel, hmac_valid, body_r2_key,
       body_sha256, dedupe_key, checkout_id, disposition, adapter_version
     ) VALUES (?, ?, ?, 1, ?, ?, ?, ?, 'duplicate', ?)`,
  )
    .bind(
      params.notificationId,
      PAYMOB_PROVIDER_ID,
      params.channel,
      params.bodyR2Key,
      params.bodySha256,
      params.bodySha256,
      params.checkoutId,
      NOTIFY_ADAPTER_VERSION,
    )
    .run();
}

async function insertUnmatchedNotification(
  env: NotifyIntakeEnv,
  params: {
    notificationId: string;
    bodySha256: string;
    bodyR2Key: string;
    channel: "processed" | "response";
  },
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO notification (
       notification_id, provider_id, channel, hmac_valid, body_r2_key,
       body_sha256, dedupe_key, checkout_id, disposition, adapter_version
     ) VALUES (?, ?, ?, 1, ?, ?, ?, NULL, 'unmatched', ?)`,
  )
    .bind(
      params.notificationId,
      PAYMOB_PROVIDER_ID,
      params.channel,
      params.bodyR2Key,
      params.bodySha256,
      params.bodySha256,
      NOTIFY_ADAPTER_VERSION,
    )
    .run();
}

export async function handlePostNotifyPaymob(
  request: Request,
  env: NotifyIntakeEnv,
  ctx: ExecutionContext,
): Promise<Response> {
  const ip = connectingIp(request);
  const body = await request.text();
  if (body.length > MAX_NOTIFY_BODY_BYTES) {
    return emptyResponse(413);
  }

  if (!(await checkNotifyRate(env, ip))) {
    return emptyResponse(429);
  }

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return emptyResponse(500);
  }

  const url = new URL(request.url);
  const parseRequest: ProviderNotificationRequest = {
    method: "POST",
    query: `${url.search}`,
    headers: request.headers,
    body,
  };
  const parsed = await provider.parseNotification(parseRequest);
  if (!parsed.authentic) {
    await recordInvalidHmac(env, body);
    return emptyResponse(401);
  }

  const bodySha256 = await sha256Hex(new TextEncoder().encode(body));
  const checkoutId = parsed.events[0]?.checkout_id ?? null;
  const notificationId = await newId(env);
  const bodyR2Key = `evidence/notification/${notificationId}`;

  try {
    await env.R2.put(bodyR2Key, body);
  } catch {
    return emptyResponse(500);
  }

  let confirmWorkId: string | null = null;
  try {
    if (checkoutId === null) {
      await insertUnmatchedNotification(env, {
        notificationId,
        bodySha256,
        bodyR2Key,
        channel: "processed",
      });
    } else {
      confirmWorkId = await insertEnqueuedNotificationAndConfirm(env, {
        notificationId,
        bodySha256,
        bodyR2Key,
        checkoutId,
        channel: "processed",
      });
      if (confirmWorkId === null) {
        const duplicateId = await newId(env, 1);
        const duplicateR2Key = `evidence/notification/${duplicateId}`;
        await env.R2.put(duplicateR2Key, body);
        await insertDuplicateNotification(env, {
          notificationId: duplicateId,
          bodySha256,
          bodyR2Key: duplicateR2Key,
          checkoutId,
          channel: "processed",
        });
      }
    }
  } catch {
    return emptyResponse(500);
  }

  if (confirmWorkId !== null) {
    const grantEnv = env as NotifyIntakeEnv & GrantEnv;
    const confirmAndGrant = runConfirmForWorkId(env, confirmWorkId).then(() =>
      runDueGrantWork(grantEnv),
    );
    ctx.waitUntil(confirmAndGrant);
    await confirmAndGrant;
  }

  return emptyResponse(200);
}

export async function handleGetNotifyPaymob(
  request: Request,
  env: NotifyIntakeEnv,
): Promise<Response> {
  const url = new URL(request.url);
  const query = url.search.startsWith("?") ? url.search.slice(1) : url.search;
  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return emptyResponse(500);
  }

  const parsed = await provider.parseNotification({
    method: "GET",
    query: url.search,
    headers: request.headers,
    body: query,
  });
  if (!parsed.authentic) {
    await recordInvalidHmac(env, query);
    return emptyResponse(401);
  }

  const checkoutId = parsed.events[0]?.checkout_id ?? null;
  if (checkoutId !== null) {
    await scheduleConfirmForCheckout(env, checkoutId);
  }

  return emptyResponse(200);
}

export async function handleGetReturnPaymob(
  _request: Request,
  env: NotifyIntakeEnv,
): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT c.checkout_id
     FROM checkout c
     INNER JOIN checkout_status cs ON cs.checkout_id = c.checkout_id
     WHERE cs.state = 'open'`,
  ).all<{ checkout_id: string }>();

  for (const row of rows.results ?? []) {
    await scheduleConfirmForCheckout(env, row.checkout_id);
  }

  return neutralReturnHtml();
}
