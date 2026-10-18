import { canonicalize, sha256Hex, ulid } from "vendor-contracts";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import { raiseAlert } from "../alert/index.js";
import {
  PAYMOB_ADAPTER_VERSION,
  PAYMOB_PROVIDER_ID,
  providerForId,
  type ProviderRegistryEnv,
} from "../provider/registry.js";

import type { ProviderNotificationRequest } from "../provider/port.js";
import { runMinuteInquiryBudget } from "../work/inquiry-budget.js";
import { recordReversalFromProviderTxn } from "../work/reversal.js";
import type { ReversalEnv } from "../work/reversal.js";
import { runConfirmForWorkId } from "../work/runner.js";
import type { GrantEnv } from "../work/grant.js";

const MAX_NOTIFY_BODY_BYTES = 1_048_576;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 60;
const HMAC_RAW_BODY_HOURLY_CAP = 10;
const AL02_WINDOW_MS = 15 * 60 * 1000;
const AL02_THRESHOLD = 3;
const AL23_PARSE_ALERT_KEY = "AL-23:notification-parse";

export type NotifyIntakeEnv = ProviderRegistryEnv &
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
  const admitted = await env.DB.prepare(
    `INSERT INTO notify_rate (ip, window_start_ms, hits) VALUES (?, ?, 1)
     ON CONFLICT (ip) DO UPDATE SET
       window_start_ms = excluded.window_start_ms,
       hits = CASE
         WHEN notify_rate.window_start_ms <> excluded.window_start_ms THEN 1
         ELSE notify_rate.hits + 1
       END
     WHERE notify_rate.window_start_ms <> excluded.window_start_ms
       OR notify_rate.hits < ?
     RETURNING ip`,
  )
    .bind(ip, windowStart, RATE_LIMIT_MAX)
    .first<{ ip: string }>();

  return admitted !== null;
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
    if (
      nowMs - object.uploaded.getTime() <= 60 * 60 * 1000 &&
      object.size > 0
    ) {
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
  await env.R2.put(
    key,
    rawInHour < HMAC_RAW_BODY_HOURLY_CAP ? rawBody : "",
  );

  const failures15m = await hmacFailuresInWindow(env, nowMs, AL02_WINDOW_MS);
  if (failures15m >= AL02_THRESHOLD) {
    await raiseAlert(env, "AL-02", "AL-02:hmac-invalid", objectId);
  }
}

async function recordUnparseableNotification(
  env: NotifyIntakeEnv,
  rawBody: string,
  rawBytes: Uint8Array,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const notificationId = await newId(env);
  const bodySha256 = await sha256Hex(rawBytes);
  const bodyR2Key = `evidence/notification/${notificationId}`;
  await env.R2.put(bodyR2Key, rawBody);
  await env.DB.prepare(
    `INSERT INTO notification (
       notification_id, provider_id, channel, hmac_valid, body_r2_key,
       body_sha256, dedupe_key, checkout_id, disposition, adapter_version
     ) VALUES (?, ?, 'processed', 0, ?, ?, ?, NULL, 'unparseable', ?)`
  )
    .bind(
      notificationId,
      PAYMOB_PROVIDER_ID,
      bodyR2Key,
      bodySha256,
      bodySha256,
      PAYMOB_ADAPTER_VERSION,
    )
    .run();
  await raiseAlert(env, "AL-23", AL23_PARSE_ALERT_KEY, notificationId);
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

async function insertEnqueuedNotificationAndConfirm(
  env: NotifyIntakeEnv,
  params: {
    notificationId: string;
    bodySha256: string;
    bodyR2Key: string;
    checkoutId: string;
    channel: "processed" | "response";
  },
): Promise<{ confirmWorkId: string | null; duplicate: boolean }> {
  const nowIso = await clockNowIso(env);
  const confirmId = await newId(env);
  const notificationRow = {
    notification_id: params.notificationId,
    provider_id: PAYMOB_PROVIDER_ID,
    channel: params.channel,
    hmac_valid: 1,
    body_r2_key: params.bodyR2Key,
    body_sha256: params.bodySha256,
    dedupe_key: params.bodySha256,
    checkout_id: params.checkoutId,
    disposition: "enqueued",
    adapter_version: PAYMOB_ADAPTER_VERSION,
  };
  const notificationRowBytes = canonicalize(notificationRow);
  const notificationRowJson = new TextDecoder().decode(notificationRowBytes);
  const notificationRowSha256 = await sha256Hex(notificationRowBytes);
  const readOriginalConfirmWork = async (): Promise<{
    notification_id: string;
    body_r2_key: string;
    work_id: string | null;
  } | null> =>
    env.DB.prepare(
      `SELECT n.notification_id, n.body_r2_key, w.work_id
       FROM notification n
       LEFT JOIN work w ON w.dedupe_key = 'confirm:' || n.notification_id
       WHERE n.dedupe_key = ? AND n.disposition = 'enqueued'
       ORDER BY n.notification_id
       LIMIT 1`,
    )
      .bind(params.bodySha256)
      .first<{
        notification_id: string;
        body_r2_key: string;
        work_id: string | null;
      }>();

  const results = await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO paymob_state_seen (dedupe_key, source, first_seen_at)
       VALUES (?, 'notify_body', ?)
       ON CONFLICT(dedupe_key) DO NOTHING`,
    ).bind(`notify-body:${params.bodySha256}`, nowIso),
    env.DB.prepare(
      `INSERT INTO notification (
         notification_id, provider_id, channel, hmac_valid, body_r2_key,
         body_sha256, dedupe_key, checkout_id, disposition, adapter_version
       ) SELECT ?, ?, ?, 1, ?, ?, ?, ?, 'enqueued', ?
         WHERE changes() = 1`,
    ).bind(
      params.notificationId,
      PAYMOB_PROVIDER_ID,
      params.channel,
      params.bodyR2Key,
      params.bodySha256,
      params.bodySha256,
      params.checkoutId,
      PAYMOB_ADAPTER_VERSION,
    ),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
       SELECT 'notification', ?, ?, ?, ?
       WHERE EXISTS (
         SELECT 1 FROM notification
         WHERE notification_id = ? AND disposition = 'enqueued'
       )`,
    ).bind(
      params.notificationId,
      notificationRowSha256,
      notificationRowJson,
      nowIso,
      params.notificationId,
    ),
    env.DB.prepare(
      `INSERT INTO work (
         work_id, kind, subject_id, dedupe_key, state, attempts,
         next_attempt_at, lease_until, last_error, opened_at
       ) SELECT ?, 'confirm', ?, ?, 'open', 0, ?, NULL, NULL, ?
         WHERE EXISTS (
           SELECT 1 FROM notification
           WHERE notification_id = ? AND disposition = 'enqueued'
         )`,
    ).bind(
      confirmId,
      params.checkoutId,
      `confirm:${params.notificationId}`,
      nowIso,
      nowIso,
      params.notificationId,
    ),
  ]);
  if ((results[1]?.meta.changes ?? 0) === 0) {
    // Re-read the committed original pair. A body marker left by an older
    // build may have no notification row; an authenticated redelivery is the
    // bounded source from which that missing durable evidence can be rebuilt.
    let original = await readOriginalConfirmWork();
    if (original === null) {
      const recoveryWorkId = await newId(env);
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO notification (
             notification_id, provider_id, channel, hmac_valid, body_r2_key,
             body_sha256, dedupe_key, checkout_id, disposition, adapter_version
           ) SELECT ?, ?, ?, 1, ?, ?, ?, ?, 'enqueued', ?
             WHERE EXISTS (
               SELECT 1 FROM paymob_state_seen WHERE dedupe_key = ?
             ) AND NOT EXISTS (
               SELECT 1 FROM notification
               WHERE dedupe_key = ? AND disposition = 'enqueued'
             )`,
        ).bind(
          params.notificationId,
          PAYMOB_PROVIDER_ID,
          params.channel,
          params.bodyR2Key,
          params.bodySha256,
          params.bodySha256,
          params.checkoutId,
          PAYMOB_ADAPTER_VERSION,
          `notify-body:${params.bodySha256}`,
          params.bodySha256,
        ),
        env.DB.prepare(
          `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
           SELECT 'notification', ?, ?, ?, ?
           WHERE EXISTS (
             SELECT 1 FROM notification
             WHERE notification_id = ? AND disposition = 'enqueued'
           )`,
        ).bind(
          params.notificationId,
          notificationRowSha256,
          notificationRowJson,
          nowIso,
          params.notificationId,
        ),
        env.DB.prepare(
          `INSERT INTO work (
             work_id, kind, subject_id, dedupe_key, state, attempts,
             next_attempt_at, lease_until, last_error, opened_at
           ) SELECT ?, 'confirm', ?, ?, 'open', 0, ?, NULL, NULL, ?
             WHERE EXISTS (
               SELECT 1 FROM notification
               WHERE notification_id = ? AND disposition = 'enqueued'
             )`,
        ).bind(
          recoveryWorkId,
          params.checkoutId,
          `confirm:${params.notificationId}`,
          nowIso,
          nowIso,
          params.notificationId,
        ),
      ]);
      original = await readOriginalConfirmWork();
    } else if (original.work_id === null) {
      const recoveredWorkId = await newId(env);
      await env.DB.prepare(
        `INSERT INTO work (
           work_id, kind, subject_id, dedupe_key, state, attempts,
           next_attempt_at, lease_until, last_error, opened_at
         ) SELECT ?, 'confirm', ?, ?, 'open', 0, ?, NULL, NULL, ?
           WHERE EXISTS (
             SELECT 1 FROM notification
             WHERE notification_id = ? AND disposition = 'enqueued'
           ) AND NOT EXISTS (
             SELECT 1 FROM work WHERE dedupe_key = ?
           )`,
      )
        .bind(
          recoveredWorkId,
          params.checkoutId,
          `confirm:${original.notification_id}`,
          nowIso,
          nowIso,
          original.notification_id,
          `confirm:${original.notification_id}`,
        )
        .run();
      original = await readOriginalConfirmWork();
    }
    return { confirmWorkId: original?.work_id ?? null, duplicate: true };
  }
  return { confirmWorkId: confirmId, duplicate: false };
}

async function readBoundedNotifyBody(
  request: Request,
): Promise<Uint8Array | null> {
  const contentLength = request.headers.get("Content-Length");
  if (contentLength !== null && /^\d+$/u.test(contentLength)) {
    const declaredBytes = Number(contentLength);
    if (Number.isSafeInteger(declaredBytes) && declaredBytes > MAX_NOTIFY_BODY_BYTES) {
      return null;
    }
  }

  if (request.body === null) {
    return new Uint8Array();
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      totalBytes += value.byteLength;
      if (totalBytes > MAX_NOTIFY_BODY_BYTES) {
        return null;
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
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
      PAYMOB_ADAPTER_VERSION,
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
      PAYMOB_ADAPTER_VERSION,
    )
    .run();
}

async function recordUnmatchedNotificationAndAlert(
  env: NotifyIntakeEnv,
  params: {
    notificationId: string;
    bodySha256: string;
    bodyR2Key: string;
    channel: "processed" | "response";
  },
): Promise<void> {
  await insertUnmatchedNotification(env, params);
  await raiseAlert(
    env,
    "AL-05",
    `AL-05:unmatched:${params.bodySha256}`,
    params.notificationId,
  );
}

export async function handlePostNotifyPaymob(
  request: Request,
  env: NotifyIntakeEnv,
  ctx: ExecutionContext,
): Promise<Response> {
  const ip = connectingIp(request);
  let bodyBytes: Uint8Array | null;
  try {
    bodyBytes = await readBoundedNotifyBody(request);
  } catch {
    return emptyResponse(400);
  }
  if (bodyBytes === null) {
    return emptyResponse(413);
  }
  let body: string;
  try {
    body = new TextDecoder("utf-8", { fatal: true }).decode(bodyBytes);
  } catch {
    return emptyResponse(400);
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
  if (parsed.parseable === false) {
    try {
      await recordUnparseableNotification(env, body, bodyBytes);
    } catch {
      return emptyResponse(500);
    }
    return emptyResponse(200);
  }
  if (!parsed.authentic) {
    // Authentication rejection is independent of the best-effort diagnostic
    // evidence path. R2/AL-02 failures must not turn an invalid signature into
    // an infrastructure 503 (and a retry must still be rejected as 401).
    try {
      await recordInvalidHmac(env, body);
    } catch {
      // The untrusted callback remains rejected even when diagnostics fail.
    }
    return emptyResponse(401);
  }

  const bodySha256 = await sha256Hex(bodyBytes);
  const event = parsed.events[0] ?? null;
  const checkoutId = event?.checkout_id ?? null;
  const notificationId = await newId(env);
  const bodyR2Key = `evidence/notification/${notificationId}`;

  try {
    await env.R2.put(bodyR2Key, body);
  } catch {
    return emptyResponse(500);
  }

  // The adapter only supplies a checkout id after resolving the callback's
  // authenticated provider order id against a stored attempt. Do not recover
  // a checkout from raw merchant_reference/special_reference fields here:
  // Paymob's callback HMAC does not cover those fields. Retain the evidence
  // and alert, but never create confirm/reversal work without that binding.
  if (event === null || checkoutId === null) {
    try {
      await recordUnmatchedNotificationAndAlert(env, {
        notificationId,
        bodySha256,
        bodyR2Key,
        channel: "processed",
      });
    } catch {
      return emptyResponse(500);
    }
    return emptyResponse(200);
  }

  const existingPayment =
    await env.DB.prepare(
      `SELECT payment_id FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ payment_id: string }>();

  // A reversal callback before any payment is the first inquiry: confirm it
  // so the payment is recorded as reversed_before_grant. Later reversals of
  // an existing payment stay on the reversal recorder.
  if (
    event !== null &&
    event.kind === "reversal" &&
    existingPayment !== null
  ) {
    try {
      await env.DB.prepare(
        `INSERT INTO notification (
           notification_id, provider_id, channel, hmac_valid, body_r2_key,
           body_sha256, dedupe_key, checkout_id, disposition, adapter_version
         ) VALUES (?, ?, 'processed', 1, ?, ?, ?, ?, 'enqueued', ?)`,
      )
        .bind(
          notificationId,
          PAYMOB_PROVIDER_ID,
          bodyR2Key,
          bodySha256,
          bodySha256,
          checkoutId,
          PAYMOB_ADAPTER_VERSION,
        )
        .run();
      const reversalEnv = env as NotifyIntakeEnv & ReversalEnv;
      await recordReversalFromProviderTxn(
        reversalEnv,
        event,
        "notification",
        bodySha256,
      );
    } catch {
      return emptyResponse(500);
    }
    return emptyResponse(200);
  }

  let confirmWorkId: string | null = null;
  try {
    const intakeResult = await insertEnqueuedNotificationAndConfirm(env, {
      notificationId,
      bodySha256,
      bodyR2Key,
      checkoutId,
      channel: "processed",
    });
    confirmWorkId = intakeResult.confirmWorkId;
    if (intakeResult.duplicate) {
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
  } catch {
    return emptyResponse(500);
  }

  if (confirmWorkId !== null) {
    const budgetEnv = env as NotifyIntakeEnv & ReversalEnv & GrantEnv;
    const confirmAndGrant = runConfirmForWorkId(env, confirmWorkId).then(() =>
      runMinuteInquiryBudget(budgetEnv),
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
  if (parsed.parseable === false) {
    try {
      await recordUnparseableNotification(
        env,
        query,
        new TextEncoder().encode(query),
      );
    } catch {
      return emptyResponse(500);
    }
    return emptyResponse(200);
  }
  if (!parsed.authentic) {
    try {
      await recordInvalidHmac(env, query);
    } catch {
      // The untrusted callback remains rejected even when diagnostics fail.
    }
    return emptyResponse(401);
  }

  const event = parsed.events[0] ?? null;
  const checkoutId = event?.checkout_id ?? null;
  if (event === null || checkoutId === null) {
    const bodyBytes = new TextEncoder().encode(query);
    const bodySha256 = await sha256Hex(bodyBytes);
    const notificationId = await newId(env);
    const bodyR2Key = `evidence/notification/${notificationId}`;
    try {
      await env.R2.put(bodyR2Key, query);
      await recordUnmatchedNotificationAndAlert(env, {
        notificationId,
        bodySha256,
        bodyR2Key,
        channel: "processed",
      });
    } catch {
      return emptyResponse(500);
    }
    return emptyResponse(200);
  }

  await scheduleConfirmForCheckout(env, checkoutId);

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
