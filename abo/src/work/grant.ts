import {
  canonicalize,
  CHANNEL_VERSIONS,
  grantIdPaid,
  sha256Hex,
  signCompactJws,
  verifyCompactJws,
} from "vendor-contracts";
import { raiseAlert, type AlertEnv } from "../alert/index.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";

const LEASE_MS = 60_000;
const MIN_BACKOFF_MS = 60_000;
const MAX_BACKOFF_MS = 15 * 60_000;
const GRANT_BATCH_LIMIT = 50;
const AL04_AFTER_MS = 5 * 60_000;
const GATE_ROW_ID = 1;

type GrantResult =
  | "applied"
  | "already_applied"
  | "transient"
  | "rejected"
  | "conflict";

type AboGrantKey = {
  kid: string;
  pkcs8: string;
  public_key: string;
};

type PlatformPublicKey = {
  kid: string;
  public_key: string;
};

type ServiceKeyRow = {
  kid: string;
  status: string;
  not_before: string;
  not_after: string;
};

type WorkRow = {
  work_id: string;
  kind: string;
  subject_id: string;
  state: string;
  attempts: number;
  next_attempt_at: string | null;
  lease_until: string | null;
  last_error: string | null;
};

type PaymentRow = {
  payment_id: string;
  org_id: string;
  checkout_id: string;
  paid_at: string;
  disposition: string;
};

type CheckoutRow = {
  checkout_id: string;
  org_id: string;
  plan_id: string;
  plan_version: number;
  term_count: number;
  allowance_credits: number;
  grace_days: number;
  grace_cap_rule: string;
};

export type GrantEnv = ClockEnv &
  AlertEnv & {
    DB: D1Database;
    ABO_GRANT_KEY: string;
    PLATFORM_PUBLIC_KEYS: string;
    TEST_CLOCK?: string;
    PLATFORM: {
      grant(args: Record<string, unknown>): Promise<Record<string, unknown>>;
      listServiceKeys(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
    };
  };

function base64UrlDecode(segment: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/u.test(segment)) {
    return null;
  }
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
  } catch {
    return null;
  }
}

function envelopeB64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function jwsHeaderKid(jws: string): string | null {
  const [headerSegment] = jws.split(".");
  if (!headerSegment) {
    return null;
  }
  const headerBytes = base64UrlDecode(headerSegment);
  if (headerBytes === null) {
    return null;
  }
  try {
    const header = JSON.parse(new TextDecoder().decode(headerBytes)) as {
      kid?: string;
    };
    return typeof header.kid === "string" ? header.kid : null;
  } catch {
    return null;
  }
}

function parseAboGrantKey(json: string): AboGrantKey | null {
  try {
    const parsed = JSON.parse(json) as Partial<AboGrantKey>;
    if (
      typeof parsed.kid !== "string" ||
      typeof parsed.pkcs8 !== "string" ||
      typeof parsed.public_key !== "string"
    ) {
      return null;
    }
    return {
      kid: parsed.kid,
      pkcs8: parsed.pkcs8,
      public_key: parsed.public_key,
    };
  } catch {
    return null;
  }
}

function parsePlatformPublicKeys(json: string): PlatformPublicKey[] {
  try {
    const parsed = JSON.parse(json) as unknown;
    if (!Array.isArray(parsed)) {
      return [];
    }
    const keys: PlatformPublicKey[] = [];
    for (const item of parsed) {
      if (
        typeof item === "object" &&
        item !== null &&
        typeof (item as PlatformPublicKey).kid === "string" &&
        typeof (item as PlatformPublicKey).public_key === "string"
      ) {
        keys.push(item as PlatformPublicKey);
      }
    }
    return keys;
  } catch {
    return [];
  }
}

async function importEd25519PrivateKey(pkcs8B64: string): Promise<CryptoKey | null> {
  const pkcs8 = base64UrlDecode(pkcs8B64);
  if (pkcs8 === null) {
    return null;
  }
  try {
    return crypto.subtle.importKey(
      "pkcs8",
      pkcs8,
      { name: "Ed25519" },
      false,
      ["sign"],
    );
  } catch {
    return null;
  }
}

async function importEd25519PublicKey(publicKeyB64: string): Promise<CryptoKey | null> {
  const bytes = base64UrlDecode(publicKeyB64);
  if (bytes === null || bytes.byteLength !== 32) {
    return null;
  }
  try {
    return crypto.subtle.importKey("raw", bytes, "Ed25519", true, ["verify"]);
  } catch {
    return null;
  }
}

function backoffMs(env: GrantEnv, attempts: number): number {
  if (env.TEST_CLOCK === "1") {
    return 0;
  }
  const exponent = Math.max(0, attempts - 1);
  return Math.min(MAX_BACKOFF_MS, MIN_BACKOFF_MS * 2 ** exponent);
}

function parseWaitIso(lastError: string | null): string | null {
  if (lastError === null || !lastError.startsWith("wait:")) {
    return null;
  }
  return lastError.slice("wait:".length);
}

async function readSigningGatePaused(env: GrantEnv): Promise<boolean> {
  try {
    const row = await env.DB.prepare(
      `SELECT paused FROM signing_key_gate WHERE id = ?`,
    )
      .bind(GATE_ROW_ID)
      .first<{ paused: number }>();
    return row?.paused === 1;
  } catch {
    return false;
  }
}

async function writeSigningGate(
  env: GrantEnv,
  paused: number,
  checkedAt: string,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO signing_key_gate (id, paused, checked_at) VALUES (?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET paused = excluded.paused, checked_at = excluded.checked_at`,
  )
    .bind(GATE_ROW_ID, paused, checkedAt)
    .run();
}

async function clearAlertActive(env: GrantEnv, alertKey: string): Promise<void> {
  await env.DB.prepare(`UPDATE alert SET active = 0 WHERE alert_key = ?`)
    .bind(alertKey)
    .run();
}

function serviceKeyActive(
  keys: ServiceKeyRow[],
  kid: string,
  nowMs: number,
): boolean {
  const row = keys.find((key) => key.kid === kid);
  if (row === undefined || row.status !== "active") {
    return false;
  }
  const notBeforeMs = Date.parse(row.not_before);
  const notAfterMs = Date.parse(row.not_after);
  if (Number.isNaN(notBeforeMs) || Number.isNaN(notAfterMs)) {
    return false;
  }
  return nowMs >= notBeforeMs && nowMs <= notAfterMs;
}

export async function refreshSigningKeyCheck(env: GrantEnv): Promise<void> {
  const aboKey = parseAboGrantKey(env.ABO_GRANT_KEY);
  const kid = aboKey?.kid ?? null;
  const nowIso = await clockNowIso(env);
  const nowMs = await clockNowMs(env);
  const alertKey = kid === null ? "AL-23:missing" : `AL-23:${kid}`;

  let keys: ServiceKeyRow[] = [];
  try {
    const response = await env.PLATFORM.listServiceKeys({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    });
    if (response.result === "ok" && typeof response.detail === "string") {
      keys = JSON.parse(response.detail) as ServiceKeyRow[];
    } else {
      await writeSigningGate(env, 1, nowIso);
      await raiseAlert(env, "AL-23", alertKey, kid ?? "missing");
      return;
    }
  } catch {
    await writeSigningGate(env, 1, nowIso);
    await raiseAlert(env, "AL-23", alertKey, kid ?? "missing");
    return;
  }

  if (kid === null || !serviceKeyActive(keys, kid, nowMs)) {
    await writeSigningGate(env, 1, nowIso);
    await raiseAlert(env, "AL-23", alertKey, kid ?? "missing");
    return;
  }

  await writeSigningGate(env, 0, nowIso);
  await clearAlertActive(env, alertKey);
}

async function takeGrantWork(
  env: GrantEnv,
  workId: string,
): Promise<WorkRow | null> {
  const nowMs = await clockNowMs(env);
  const nowIso = new Date(nowMs).toISOString();
  const leaseUntil = new Date(nowMs + LEASE_MS).toISOString();

  const leased = await env.DB.prepare(
    `UPDATE work
     SET lease_until = ?
     WHERE work_id = ?
       AND kind = 'grant'
       AND state = 'open'
       AND (lease_until IS NULL OR lease_until <= ?)
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)`,
  )
    .bind(leaseUntil, workId, nowIso, nowIso)
    .run();
  if ((leased.meta.changes ?? 0) === 0) {
    return null;
  }

  return env.DB.prepare(
    `SELECT work_id, kind, subject_id, state, attempts, next_attempt_at,
            lease_until, last_error
     FROM work WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(workId, leaseUntil)
    .first<WorkRow>();
}

async function releaseLease(env: GrantEnv, workId: string, leaseUntil: string): Promise<void> {
  await env.DB.prepare(
    `UPDATE work SET lease_until = NULL WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(workId, leaseUntil)
    .run();
}

async function releaseLeaseRetry(
  env: GrantEnv,
  work: WorkRow,
  leaseUntil: string,
  lastError: string,
): Promise<void> {
  const nowMs = await clockNowMs(env);
  const attempts = work.attempts + 1;
  const nextAttempt = new Date(
    nowMs + backoffMs(env, attempts),
  ).toISOString();
  await env.DB.prepare(
    `UPDATE work
     SET attempts = ?, next_attempt_at = ?, lease_until = NULL, last_error = ?
     WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(attempts, nextAttempt, lastError, work.work_id, leaseUntil)
    .run();
}

async function loadPayment(
  env: GrantEnv,
  paymentId: string,
): Promise<PaymentRow | null> {
  return env.DB.prepare(
    `SELECT payment_id, org_id, checkout_id, paid_at, disposition
     FROM payment WHERE payment_id = ?`,
  )
    .bind(paymentId)
    .first<PaymentRow>();
}

async function loadCheckout(
  env: GrantEnv,
  checkoutId: string,
): Promise<CheckoutRow | null> {
  return env.DB.prepare(
    `SELECT checkout_id, org_id, plan_id, plan_version, term_count,
            allowance_credits, grace_days, grace_cap_rule
     FROM checkout WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<CheckoutRow>();
}

async function paymentFactSha256(
  env: GrantEnv,
  paymentId: string,
): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT row_sha256 FROM fact_log WHERE "table" = 'payment' AND key = ?`,
  )
    .bind(paymentId)
    .first<{ row_sha256: string }>();
  return row?.row_sha256 ?? null;
}

async function grantRequestExists(
  env: GrantEnv,
  grantId: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM grant_request WHERE grant_id = ?`,
  )
    .bind(grantId)
    .first();
  return row !== null;
}

function buildEnvelopeWithoutApprovals(input: {
  contractVersion: number;
  grantId: string;
  orgId: string;
  planId: string;
  planVersion: number;
  termCount: number;
  allowanceCredits: number;
  graceDays: number;
  graceCapRule: string;
  paidAt: string;
  paymentId: string;
  contentSha256: string;
}): Record<string, unknown> {
  return {
    contract_version: input.contractVersion,
    grant_id: input.grantId,
    org_id: input.orgId,
    kind: "term",
    placement: "queue",
    source: { kind: "paid", ref: input.paymentId },
    plan: { plan_id: input.planId, plan_version: input.planVersion },
    duration: { unit: "month", count: input.termCount },
    allowance_credits: input.allowanceCredits,
    grace: { days: input.graceDays, cap_rule: input.graceCapRule },
    paid_at: input.paidAt,
    evidence: {
      content_sha256: input.contentSha256,
    },
  };
}

async function buildGrantEnvelope(
  payment: PaymentRow,
  checkout: CheckoutRow,
  contentSha256: string,
): Promise<{
  envelope: Record<string, unknown>;
  envelopeBytes: Uint8Array;
  grantId: string;
}> {
  const contractVersion = CHANNEL_VERSIONS.vendorEntrypoint;
  const grantId = await grantIdPaid(payment.payment_id);
  const base = buildEnvelopeWithoutApprovals({
    contractVersion,
    grantId,
    orgId: payment.org_id,
    planId: checkout.plan_id,
    planVersion: checkout.plan_version,
    termCount: checkout.term_count,
    allowanceCredits: checkout.allowance_credits,
    graceDays: checkout.grace_days,
    graceCapRule: checkout.grace_cap_rule,
    paidAt: payment.paid_at,
    paymentId: payment.payment_id,
    contentSha256,
  });
  const approval = {
    op: "grant",
    params: base,
    actor_email: "",
    issued_at: payment.paid_at,
    nonce: grantId,
    contract_version: contractVersion,
  };
  const envelope = {
    ...base,
    evidence: {
      content_sha256: contentSha256,
      approvals: [approval],
    },
  };
  const envelopeBytes = canonicalize(envelope);
  return { envelope, envelopeBytes, grantId };
}

async function verifyGrantReceipt(
  env: GrantEnv,
  receipt: Record<string, unknown>,
): Promise<boolean> {
  const signature =
    typeof receipt.signature === "string" ? receipt.signature : null;
  if (signature === null) {
    return false;
  }
  const kid = jwsHeaderKid(signature);
  if (kid === null) {
    return false;
  }
  const configured = parsePlatformPublicKeys(env.PLATFORM_PUBLIC_KEYS);
  const match = configured.find((key) => key.kid === kid);
  if (match === undefined) {
    return false;
  }
  const publicKey = await importEd25519PublicKey(match.public_key);
  if (publicKey === null) {
    return false;
  }
  return verifyCompactJws({ jws: signature, publicKey, kid });
}

function grantRequestCanonical(input: {
  grantId: string;
  orgId: string;
  paymentId: string;
  envelopeText: string;
  envelopeSha256: string;
}): Record<string, unknown> {
  return {
    grant_id: input.grantId,
    org_id: input.orgId,
    source_kind: "paid",
    source_ref: input.paymentId,
    envelope: input.envelopeText,
    envelope_sha256: input.envelopeSha256,
    assertion: null,
  };
}

function grantOutcomeCanonical(input: {
  grantId: string;
  result: GrantResult;
  aboKid: string | null;
  aboSignature: string | null;
  receipt: Record<string, unknown> | null;
  termIds: string[] | null;
  at: string;
}): Record<string, unknown> {
  return {
    grant_id: input.grantId,
    result: input.result,
    abo_kid: input.aboKid,
    abo_signature: input.aboSignature,
    receipt: input.receipt === null ? null : JSON.stringify(input.receipt),
    term_ids: input.termIds === null ? null : JSON.stringify(input.termIds),
    at: input.at,
  };
}

function factLogStatement(
  env: GrantEnv,
  table: string,
  key: string,
  rowSha256: string,
  createdAt: string,
): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
  ).bind(table, key, rowSha256, createdAt);
}

function insertGrantRequestIfAbsent(
  env: GrantEnv,
  grantId: string,
  orgId: string,
  paymentId: string,
  envelopeText: string,
  envelopeSha256: string,
): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT OR IGNORE INTO grant_request (
       grant_id, org_id, source_kind, source_ref, envelope, envelope_sha256, assertion
     ) VALUES (?, ?, 'paid', ?, ?, ?, NULL)`,
  ).bind(grantId, orgId, paymentId, envelopeText, envelopeSha256);
}

async function maybeRaiseAl04(
  env: GrantEnv,
  workId: string,
  lastError: string | null,
): Promise<void> {
  const waitIso = parseWaitIso(lastError);
  if (waitIso === null) {
    return;
  }
  const waitMs = Date.parse(waitIso);
  if (Number.isNaN(waitMs)) {
    return;
  }
  const nowMs = await clockNowMs(env);
  if (nowMs - waitMs < AL04_AFTER_MS) {
    return;
  }
  await raiseAlert(env, "AL-04", `AL-04:${workId}`, workId);
}

async function handleTransientFailure(
  env: GrantEnv,
  work: WorkRow,
  leaseUntil: string,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  const waitIso = parseWaitIso(work.last_error);
  const lastError = waitIso === null ? `wait:${nowIso}` : work.last_error!;
  await releaseLeaseRetry(env, work, leaseUntil, lastError);
  await maybeRaiseAl04(env, work.work_id, lastError);
}

async function processGrantWork(env: GrantEnv, work: WorkRow): Promise<void> {
  const leaseUntil = work.lease_until;
  if (leaseUntil === null) {
    return;
  }

  const payment = await loadPayment(env, work.subject_id);
  if (payment === null || payment.disposition !== "grant") {
    await env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL, last_error = NULL
       WHERE work_id = ? AND lease_until = ?`,
    )
      .bind(work.work_id, leaseUntil)
      .run();
    return;
  }

  const checkout = await loadCheckout(env, payment.checkout_id);
  if (checkout === null) {
    await env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL, last_error = NULL
       WHERE work_id = ? AND lease_until = ?`,
    )
      .bind(work.work_id, leaseUntil)
      .run();
    return;
  }

  const contentSha256 = await paymentFactSha256(env, payment.payment_id);
  if (contentSha256 === null) {
    await releaseLeaseRetry(env, work, leaseUntil, "missing_payment_fact");
    return;
  }

  const aboKey = parseAboGrantKey(env.ABO_GRANT_KEY);
  if (aboKey === null) {
    await handleTransientFailure(env, work, leaseUntil);
    return;
  }
  const privateKey = await importEd25519PrivateKey(aboKey.pkcs8);
  if (privateKey === null) {
    await handleTransientFailure(env, work, leaseUntil);
    return;
  }

  const { envelope, envelopeBytes, grantId } = await buildGrantEnvelope(
    payment,
    checkout,
    contentSha256,
  );
  const envelopeText = new TextDecoder().decode(envelopeBytes);
  const envelopeSha256 = await sha256Hex(envelopeBytes);
  const aboSignature = await signCompactJws({
    payload: envelopeBytes,
    privateKey,
    kid: aboKey.kid,
  });

  let platformResult: Record<string, unknown>;
  try {
    platformResult = await env.PLATFORM.grant({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      abo_kid: aboKey.kid,
      abo_signature: aboSignature,
      envelope_b64: envelopeB64(envelopeBytes),
    });
  } catch {
    await handleTransientFailure(env, work, leaseUntil);
    return;
  }

  const result = platformResult.result;
  const nowIso = await clockNowIso(env);

  if (result === "transient") {
    await handleTransientFailure(env, work, leaseUntil);
    return;
  }

  if (result === "applied" || result === "already_applied") {
    const receipt = platformResult.receipt;
    if (
      typeof receipt !== "object" ||
      receipt === null ||
      Array.isArray(receipt)
    ) {
      await handleTransientFailure(env, work, leaseUntil);
      return;
    }
    const receiptRecord = receipt as Record<string, unknown>;
    const verified = await verifyGrantReceipt(env, receiptRecord);
    if (!verified) {
      const statements: D1PreparedStatement[] = [];
      if (!(await grantRequestExists(env, grantId))) {
        statements.push(
          insertGrantRequestIfAbsent(
            env,
            grantId,
            payment.org_id,
            payment.payment_id,
            envelopeText,
            envelopeSha256,
          ),
        );
      }
      statements.push(
        env.DB.prepare(
          `UPDATE work
           SET state = 'parked', lease_until = NULL, last_error = 'receipt_unverified'
           WHERE work_id = ? AND lease_until = ?`,
        ).bind(work.work_id, leaseUntil),
      );
      await env.DB.batch(statements);
      await raiseAlert(env, "AL-07", `AL-07:${work.work_id}`, work.work_id);
      return;
    }

    const termIds = Array.isArray(receiptRecord.term_ids)
      ? receiptRecord.term_ids.filter(
          (value): value is string => typeof value === "string",
        )
      : [];
    const requestCanonical = grantRequestCanonical({
      grantId,
      orgId: payment.org_id,
      paymentId: payment.payment_id,
      envelopeText,
      envelopeSha256,
    });
    const outcomeCanonical = grantOutcomeCanonical({
      grantId,
      result: result as GrantResult,
      aboKid: aboKey.kid,
      aboSignature,
      receipt: receiptRecord,
      termIds,
      at: nowIso,
    });
    const requestSha = await sha256Hex(canonicalize(requestCanonical));
    const outcomeSha = await sha256Hex(canonicalize(outcomeCanonical));

    const statements: D1PreparedStatement[] = [
      insertGrantRequestIfAbsent(
        env,
        grantId,
        payment.org_id,
        payment.payment_id,
        envelopeText,
        envelopeSha256,
      ),
      env.DB.prepare(
        `INSERT INTO grant_outcome (
           grant_id, result, abo_kid, abo_signature, receipt, term_ids, at
         ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        grantId,
        result,
        aboKey.kid,
        aboSignature,
        JSON.stringify(receiptRecord),
        JSON.stringify(termIds),
        nowIso,
      ),
      factLogStatement(env, "grant_request", grantId, requestSha, nowIso),
      factLogStatement(env, "grant_outcome", grantId, outcomeSha, nowIso),
      env.DB.prepare(
        `UPDATE work SET state = 'done', lease_until = NULL, last_error = NULL
         WHERE work_id = ? AND lease_until = ?`,
      ).bind(work.work_id, leaseUntil),
    ];

    try {
      const results = await env.DB.batch(statements);
      const workIdx = statements.length - 1;
      if ((results[workIdx]?.meta.changes ?? 0) === 0) {
        throw new Error("lease_lost");
      }
      await clearAlertActive(env, `AL-04:${work.work_id}`);
    } catch {
      await releaseLease(env, work.work_id, leaseUntil);
    }
    return;
  }

  if (result === "conflict" || result === "rejected") {
    const requestCanonical = grantRequestCanonical({
      grantId,
      orgId: payment.org_id,
      paymentId: payment.payment_id,
      envelopeText,
      envelopeSha256,
    });
    const outcomeCanonical = grantOutcomeCanonical({
      grantId,
      result: result as GrantResult,
      aboKid: null,
      aboSignature: null,
      receipt: null,
      termIds: null,
      at: nowIso,
    });
    const requestSha = await sha256Hex(canonicalize(requestCanonical));
    const outcomeSha = await sha256Hex(canonicalize(outcomeCanonical));

    const statements: D1PreparedStatement[] = [
      insertGrantRequestIfAbsent(
        env,
        grantId,
        payment.org_id,
        payment.payment_id,
        envelopeText,
        envelopeSha256,
      ),
      env.DB.prepare(
        `INSERT INTO grant_outcome (
           grant_id, result, abo_kid, abo_signature, receipt, term_ids, at
         ) VALUES (?, ?, NULL, NULL, NULL, NULL, ?)`,
      ).bind(grantId, result, nowIso),
      factLogStatement(env, "grant_request", grantId, requestSha, nowIso),
      factLogStatement(env, "grant_outcome", grantId, outcomeSha, nowIso),
      env.DB.prepare(
        `UPDATE work
         SET state = 'parked', lease_until = NULL, last_error = ?
         WHERE work_id = ? AND lease_until = ?`,
      ).bind(String(result), work.work_id, leaseUntil),
    ];

    try {
      const results = await env.DB.batch(statements);
      const workIdx = statements.length - 1;
      if ((results[workIdx]?.meta.changes ?? 0) === 0) {
        throw new Error("lease_lost");
      }
      await raiseAlert(env, "AL-07", `AL-07:${work.work_id}`, work.work_id);
    } catch {
      await releaseLease(env, work.work_id, leaseUntil);
    }
    return;
  }

  await handleTransientFailure(env, work, leaseUntil);
}

export async function runDueGrantWork(
  env: GrantEnv,
  limit = GRANT_BATCH_LIMIT,
): Promise<void> {
  if (await readSigningGatePaused(env)) {
    return;
  }

  const nowIso = await clockNowIso(env);
  const due = await env.DB.prepare(
    `SELECT work_id FROM work
     WHERE kind = 'grant'
       AND state = 'open'
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
     ORDER BY next_attempt_at ASC
     LIMIT ?`,
  )
    .bind(nowIso, limit)
    .all<{ work_id: string }>();

  for (const row of due.results ?? []) {
    try {
      const work = await takeGrantWork(env, row.work_id);
      if (work === null) {
        continue;
      }
      await processGrantWork(env, work);
    } catch {
      // Single row failure must not throw out of cron.
    }
  }
}
