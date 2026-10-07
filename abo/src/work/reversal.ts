import {
  canonicalize,
  CHANNEL_VERSIONS,
  grantIdPaid,
  humanRef,
  paymentId,
  sha256Hex,
  signCompactJws,
  ulid,
  verifyReceiptSignature,
} from "vendor-contracts";
import { raiseAlert, type AlertEnv } from "../alert/index.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import { PAYMOB_PROVIDER_ID, providerForId } from "../provider/registry.js";
import type { PaymobAdapterEnv } from "../provider/paymob/adapter.js";
import type { ProviderTxn } from "../provider/port.js";

const LEASE_MS = 60_000;
const MIN_BACKOFF_MS = 60_000;
const MAX_BACKOFF_MS = 15 * 60_000;
const GATE_ROW_ID = 1;
const STAGING_GRACE_MS = 7 * 60 * 1000;

type ReversalEffect =
  | "tombstone"
  | "end_current"
  | "remove_queued"
  | "none"
  | "review_partial";

type AboGrantKey = {
  kid: string;
  pkcs8: string;
  public_key: string;
};

type PlatformPublicKey = {
  kid: string;
  public_key: string;
};

type PaymentRow = {
  payment_id: string;
  org_id: string;
  amount_minor: number;
};

type ReversalRow = {
  reversal_id: string;
  payment_id: string;
  cumulative_reversed_minor: number;
  effect: ReversalEffect;
  evidence_sha256: string;
  detected_via: string;
};

type WorkRow = {
  work_id: string;
  kind: string;
  subject_id: string;
  dedupe_key: string;
  state: string;
  attempts: number;
  next_attempt_at: string | null;
  lease_until: string | null;
  last_error: string | null;
};

type RecentTerm = {
  term_id?: string;
  state?: string;
  ends_at?: string;
  grace_ends_at?: string;
};

export type ReversalEnv = PaymobAdapterEnv &
  ClockEnv &
  AlertEnv & {
    R2: R2Bucket;
    ABO_GRANT_KEY: string;
    PLATFORM_PUBLIC_KEYS: string;
    TEST_CLOCK?: string;
    PLATFORM: {
      voidForReversal(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
      getCoverage(args: Record<string, unknown>): Promise<Record<string, unknown>>;
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

function backoffMs(env: ReversalEnv, attempts: number): number {
  if (env.TEST_CLOCK === "1") {
    return 0;
  }
  const exponent = Math.max(0, attempts - 1);
  return Math.min(MAX_BACKOFF_MS, MIN_BACKOFF_MS * 2 ** exponent);
}

async function newId(env: ReversalEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

export async function resolveParentTxnRef(
  env: ReversalEnv,
  txn: ProviderTxn,
): Promise<string> {
  if (txn.provider_parent_txn_id !== undefined && txn.provider_parent_txn_id !== null) {
    return txn.provider_parent_txn_id;
  }
  if (txn.provider_txn_id !== undefined) {
    return txn.provider_txn_id;
  }
  if (txn.payment_id !== undefined) {
    const txnRow = await env.DB.prepare(
      `SELECT txn_id FROM paymob_txn WHERE payment_id = ? AND parent_txn_id IS NULL`,
    )
      .bind(txn.payment_id)
      .first<{ txn_id: string }>();
    if (txnRow !== null) {
      return txnRow.txn_id;
    }
  }
  return "unknown";
}

export async function paymentIdForParentRef(
  parentRef: string,
): Promise<string> {
  return paymentId(PAYMOB_PROVIDER_ID, parentRef);
}

export function reversalDedupeKey(
  parentRef: string,
  cumulativeReversedMinor: number,
): string {
  return `paymob:${parentRef}:reversal:${cumulativeReversedMinor}`;
}

export async function reversalIdFromDedupeKey(dedupeKey: string): Promise<string> {
  return sha256Hex(new TextEncoder().encode(`reversal:${dedupeKey}`));
}

async function loadPayment(
  env: ReversalEnv,
  paymentIdValue: string,
): Promise<PaymentRow | null> {
  return env.DB.prepare(
    `SELECT payment_id, org_id, amount_minor FROM payment WHERE payment_id = ?`,
  )
    .bind(paymentIdValue)
    .first<PaymentRow>();
}

async function grantOutcomeApplied(
  env: ReversalEnv,
  grantId: string,
): Promise<{ result: string; term_ids: string[] } | null> {
  const row = await env.DB.prepare(
    `SELECT result, term_ids FROM grant_outcome WHERE grant_id = ?`,
  )
    .bind(grantId)
    .first<{ result: string; term_ids: string | null }>();
  if (row === null) {
    return null;
  }
  if (row.result !== "applied" && row.result !== "already_applied") {
    return null;
  }
  let termIds: string[] = [];
  if (row.term_ids !== null) {
    try {
      const parsed = JSON.parse(row.term_ids) as unknown;
      if (Array.isArray(parsed)) {
        termIds = parsed.filter((value): value is string => typeof value === "string");
      }
    } catch {
      termIds = [];
    }
  }
  return { result: row.result, term_ids: termIds };
}

async function recentTermsForOrg(
  env: ReversalEnv,
  orgId: string,
): Promise<RecentTerm[]> {
  try {
    const envelope = await env.PLATFORM.getCoverage({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      org_id: orgId,
    });
    if (envelope.result !== "ok" || typeof envelope.detail !== "string") {
      return [];
    }
    const parsed = JSON.parse(envelope.detail) as {
      recent_terms?: RecentTerm[];
    };
    return parsed.recent_terms ?? [];
  } catch {
    return [];
  }
}

function graceEndsMs(env: ReversalEnv, term: RecentTerm): number | null {
  if (term.grace_ends_at !== undefined && term.grace_ends_at.length > 0) {
    const graceMs = Date.parse(term.grace_ends_at);
    return Number.isNaN(graceMs) ? null : graceMs;
  }
  if (
    env.TEST_CLOCK === "1" &&
    term.ends_at !== undefined &&
    term.ends_at.length > 0
  ) {
    const endsMs = Date.parse(term.ends_at);
    return Number.isNaN(endsMs) ? null : endsMs + STAGING_GRACE_MS;
  }
  return null;
}

async function effectiveTermState(
  env: ReversalEnv,
  term: RecentTerm,
): Promise<string | undefined> {
  const state = term.state;
  if (state === undefined) {
    return undefined;
  }
  const nowMs = await clockNowMs(env);
  const graceMs = graceEndsMs(env, term);
  if (state === "active" && term.ends_at !== undefined && term.ends_at.length > 0) {
    const endsMs = Date.parse(term.ends_at);
    if (!Number.isNaN(endsMs) && nowMs >= endsMs) {
      if (graceMs !== null && nowMs >= graceMs) {
        return "ended";
      }
      return "grace";
    }
  }
  if (state === "grace") {
    if (graceMs !== null && nowMs >= graceMs) {
      return "ended";
    }
  }
  return state;
}

export async function determineReversalEffect(
  env: ReversalEnv,
  paymentIdValue: string,
  isFull: boolean,
): Promise<ReversalEffect> {
  if (!isFull) {
    return "review_partial";
  }

  const grantId = await grantIdPaid(paymentIdValue);
  const outcome = await grantOutcomeApplied(env, grantId);
  if (outcome === null) {
    return "tombstone";
  }

  const payment = await loadPayment(env, paymentIdValue);
  if (payment === null) {
    return "tombstone";
  }

  const recentTerms = await recentTermsForOrg(env, payment.org_id);
  const termId = outcome.term_ids[0];
  if (termId === undefined) {
    return "remove_queued";
  }

  const match = recentTerms.find((term) => term.term_id === termId);
  if (match === undefined) {
    return "remove_queued";
  }
  const termState = await effectiveTermState(env, match);
  if (termState === "active" || termState === "grace") {
    return "end_current";
  }
  if (termState === "ended") {
    return "none";
  }
  return "remove_queued";
}

function needsVoid(effect: ReversalEffect): boolean {
  return (
    effect === "tombstone" ||
    effect === "end_current" ||
    effect === "remove_queued"
  );
}

async function reversalExists(dedupeKey: string, env: ReversalEnv): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM reversal WHERE dedupe_key = ?`,
  )
    .bind(dedupeKey)
    .first();
  return row !== null;
}

async function findingExists(
  env: ReversalEnv,
  reversalId: string,
  kind: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM finding WHERE subject = ? AND kind = ?`,
  )
    .bind(reversalId, kind)
    .first();
  return row !== null;
}

async function reversalOutcomeExists(
  env: ReversalEnv,
  reversalId: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM reversal_outcome WHERE reversal_id = ?`,
  )
    .bind(reversalId)
    .first();
  return row !== null;
}

async function verifyVoidReceipt(
  env: ReversalEnv,
  receipt: Record<string, unknown>,
): Promise<boolean> {
  const kid = typeof receipt.kid === "string" ? receipt.kid : null;
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
  return verifyReceiptSignature({ receipt, publicKey });
}

export function inquiryAgreesWithReversal(
  txn: ProviderTxn,
  parentRef: string,
  cumulativeReversedMinor: number,
): boolean {
  if (txn.kind !== "reversal") {
    return false;
  }
  const txnParent = txn.provider_parent_txn_id ?? txn.provider_txn_id;
  if (txnParent !== undefined && txnParent !== parentRef) {
    return false;
  }
  const cumulative =
    txn.reversal?.cumulative_reversed_minor ?? txn.amount_minor;
  return cumulative >= cumulativeReversedMinor;
}

async function insertReversalRow(
  env: ReversalEnv,
  input: {
    reversalId: string;
    paymentIdValue: string;
    reference: string;
    amountMinor: number;
    cumulativeReversedMinor: number;
    isFull: boolean;
    detectedVia: "notification" | "inquiry";
    evidenceSha256: string;
    effect: ReversalEffect;
    dedupeKey: string;
  },
): Promise<boolean> {
  const nowIso = await clockNowIso(env);
  const canonical = {
    reversal_id: input.reversalId,
    payment_id: input.paymentIdValue,
    reference: input.reference,
    amount_minor: input.amountMinor,
    kind: "refund",
    is_full: input.isFull ? 1 : 0,
    source: "provider",
    cumulative_reversed_minor: input.cumulativeReversedMinor,
    detected_via: input.detectedVia,
    recorded_by: "abo",
    evidence_sha256: input.evidenceSha256,
    effect: input.effect,
    dedupe_key: input.dedupeKey,
  };
  const rowSha = await sha256Hex(canonicalize(canonical));
  const result = await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO reversal (
         reversal_id, payment_id, reference, amount_minor, kind, is_full,
         source, cumulative_reversed_minor, detected_via, recorded_by,
         evidence_sha256, effect, dedupe_key
       ) VALUES (?, ?, ?, ?, 'refund', ?, 'provider', ?, ?, 'abo', ?, ?, ?)`,
    ).bind(
      input.reversalId,
      input.paymentIdValue,
      input.reference,
      input.amountMinor,
      input.isFull ? 1 : 0,
      input.cumulativeReversedMinor,
      input.detectedVia,
      input.evidenceSha256,
      input.effect,
      input.dedupeKey,
    ),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, created_at) VALUES (?, ?, ?, ?)`,
    ).bind("reversal", input.reversalId, rowSha, nowIso),
  ]);
  return (result[0]?.meta.changes ?? 0) > 0;
}

export async function recordReversalFromProviderTxn(
  env: ReversalEnv,
  txn: ProviderTxn,
  detectedVia: "notification" | "inquiry",
  evidenceSha256: string,
  paymentIdOverride?: string,
): Promise<string | null> {
  if (txn.kind !== "reversal") {
    return null;
  }

  const parentRef = await resolveParentTxnRef(env, txn);
  const paymentIdValue =
    paymentIdOverride ?? (await paymentIdForParentRef(parentRef));
  const cumulative =
    txn.reversal?.cumulative_reversed_minor ?? txn.amount_minor;
  const dedupeKey = reversalDedupeKey(parentRef, cumulative);

  if (await reversalExists(dedupeKey, env)) {
    return null;
  }

  const payment = await loadPayment(env, paymentIdValue);
  const paymentAmount = payment?.amount_minor ?? txn.amount_minor;
  const isFull =
    txn.reversal?.is_full === true || cumulative >= paymentAmount;
  const effect = await determineReversalEffect(env, paymentIdValue, isFull);
  const reversalId = await reversalIdFromDedupeKey(dedupeKey);
  const reference = humanRef("REV", reversalId);

  const inserted = await insertReversalRow(env, {
    reversalId,
    paymentIdValue,
    reference,
    amountMinor: txn.amount_minor,
    cumulativeReversedMinor: cumulative,
    isFull,
    detectedVia,
    evidenceSha256,
    effect,
    dedupeKey,
  });
  if (!inserted) {
    return null;
  }

  await env.DB.prepare(
    `UPDATE work SET state = 'done', lease_until = NULL
     WHERE kind = 'sweep_payment' AND subject_id = ? AND state = 'open'`,
  )
    .bind(paymentIdValue)
    .run();

  await raiseAlert(env, "AL-06", `AL-06:${reversalId}`, reversalId);

  if (needsVoid(effect) && detectedVia === "inquiry") {
    await insertReverseWorkRow(env, reversalId);
    const reversal = await loadReversal(env, reversalId);
    if (reversal !== null) {
      await callVoidForReversal(env, reversal);
    }
  }

  return reversalId;
}

async function loadReversal(
  env: ReversalEnv,
  reversalId: string,
): Promise<ReversalRow | null> {
  return env.DB.prepare(
    `SELECT reversal_id, payment_id, cumulative_reversed_minor, effect,
            evidence_sha256, detected_via
     FROM reversal WHERE reversal_id = ?`,
  )
    .bind(reversalId)
    .first<ReversalRow>();
}

async function readSigningGatePaused(env: ReversalEnv): Promise<boolean> {
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

export type ReversalVerifyResult = {
  inquired: boolean;
  agreed: boolean;
};

async function recordInquiryDisagreesFinding(
  env: ReversalEnv,
  reversalId: string,
): Promise<void> {
  if (await findingExists(env, reversalId, "inquiry_disagrees")) {
    return;
  }
  const nowIso = await clockNowIso(env);
  const findingId = await newId(env);
  await env.DB.prepare(
    `INSERT INTO finding (finding_id, kind, subject, detail, detected_at)
     VALUES (?, 'inquiry_disagrees', ?, '', ?)`,
  )
    .bind(findingId, reversalId, nowIso)
    .run();
}

export async function verifyNotificationReversal(
  env: ReversalEnv,
  reversalId: string,
): Promise<ReversalVerifyResult> {
  const reversal = await loadReversal(env, reversalId);
  if (reversal === null) {
    return { inquired: false, agreed: false };
  }
  if (!needsVoid(reversal.effect)) {
    return { inquired: false, agreed: false };
  }
  if (await reversalOutcomeExists(env, reversalId)) {
    return { inquired: false, agreed: false };
  }
  if (await reverseWorkExists(env, reversalId)) {
    return { inquired: false, agreed: true };
  }
  if (await findingExists(env, reversalId, "inquiry_disagrees")) {
    return { inquired: false, agreed: false };
  }

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider === null) {
    return { inquired: false, agreed: false };
  }

  const payment = await loadPayment(env, reversal.payment_id);
  if (payment === null) {
    return { inquired: false, agreed: false };
  }

  const checkoutRow = await env.DB.prepare(
    `SELECT checkout_id FROM payment WHERE payment_id = ?`,
  )
    .bind(reversal.payment_id)
    .first<{ checkout_id: string }>();
  if (checkoutRow === null) {
    return { inquired: false, agreed: false };
  }

  const txnRow = await env.DB.prepare(
    `SELECT txn_id FROM paymob_txn
     WHERE payment_id = ? AND parent_txn_id IS NULL
     ORDER BY txn_id ASC LIMIT 1`,
  )
    .bind(reversal.payment_id)
    .first<{ txn_id: string }>();

  const inquiry = await provider.inquire({
    checkout_id: checkoutRow.checkout_id,
    paymob_txn_id: txnRow?.txn_id,
  });
  if (!inquiry.bound) {
    return { inquired: false, agreed: false };
  }
  if (inquiry.transactions.length === 0) {
    return { inquired: true, agreed: false };
  }

  const inquiryTxn = inquiry.transactions[0]!;
  const resolvedParent = await resolveParentTxnRef(env, inquiryTxn);
  const agrees = inquiryAgreesWithReversal(
    inquiryTxn,
    resolvedParent,
    reversal.cumulative_reversed_minor,
  );
  if (!agrees) {
    if (inquiry.transactions.length > 0) {
      await recordInquiryDisagreesFinding(env, reversalId);
    }
    return { inquired: true, agreed: false };
  }

  await insertReverseWorkRow(env, reversalId);
  await callVoidForReversal(env, reversal);
  return { inquired: true, agreed: true };
}

async function callVoidForReversal(
  env: ReversalEnv,
  reversal: ReversalRow,
): Promise<void> {
  if (await readSigningGatePaused(env)) {
    return;
  }

  const aboKey = parseAboGrantKey(env.ABO_GRANT_KEY);
  if (aboKey === null) {
    return;
  }
  const privateKey = await importEd25519PrivateKey(aboKey.pkcs8);
  if (privateKey === null) {
    return;
  }

  const grantId = await grantIdPaid(reversal.payment_id);
  const signedBody = {
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    grant_id: grantId,
    reversal_id: reversal.reversal_id,
    reason: reversal.effect,
    evidence_sha256: reversal.evidence_sha256,
    partial: false,
  };
  const aboSignature = await signCompactJws({
    payload: canonicalize(signedBody),
    privateKey,
    kid: aboKey.kid,
  });

  let platformResult: Record<string, unknown>;
  try {
    platformResult = await env.PLATFORM.voidForReversal({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      grant_id: grantId,
      reversal_id: reversal.reversal_id,
      reason: reversal.effect,
      evidence_sha256: reversal.evidence_sha256,
      partial: false,
      abo_kid: aboKey.kid,
      abo_signature: aboSignature,
    });
  } catch {
    await insertReverseWorkRow(env, reversal.reversal_id);
    return;
  }

  const result = platformResult.result;
  const nowIso = await clockNowIso(env);

  if (result === "transient") {
    await insertReverseWorkRow(env, reversal.reversal_id);
    return;
  }

  if (result === "applied" || result === "already_applied") {
    const receipt = platformResult.receipt;
    if (
      typeof receipt !== "object" ||
      receipt === null ||
      Array.isArray(receipt)
    ) {
      await insertReverseWorkRow(env, reversal.reversal_id);
      return;
    }
    const receiptRecord = receipt as Record<string, unknown>;
    if (!(await verifyVoidReceipt(env, receiptRecord))) {
      await parkReverseWorkRow(env, reversal.reversal_id, "receipt_unverified");
      return;
    }
    await env.DB.prepare(
      `INSERT INTO reversal_outcome (reversal_id, result, receipt, at)
       VALUES (?, ?, ?, ?)`,
    )
      .bind(
        reversal.reversal_id,
        result,
        JSON.stringify(receiptRecord),
        nowIso,
      )
      .run();
    await env.DB.prepare(
      `DELETE FROM work WHERE kind = 'reverse' AND subject_id = ?`,
    )
      .bind(reversal.reversal_id)
      .run();
    return;
  }

  if (result === "conflict" || result === "rejected") {
    await parkReverseWorkRow(env, reversal.reversal_id, String(result));
  }
}

export async function insertReverseWorkRow(
  env: ReversalEnv,
  reversalId: string,
): Promise<void> {
  const dedupeKey = `reverse:${reversalId}`;
  const existing = await env.DB.prepare(
    `SELECT work_id FROM work WHERE dedupe_key = ?`,
  )
    .bind(dedupeKey)
    .first();
  if (existing !== null) {
    return;
  }
  const nowIso = await clockNowIso(env);
  const workId = await newId(env);
  await env.DB.prepare(
    `INSERT INTO work (
       work_id, kind, subject_id, dedupe_key, state, attempts,
       next_attempt_at, lease_until, last_error, opened_at
     ) VALUES (?, 'reverse', ?, ?, 'open', 0, ?, NULL, NULL, ?)`,
  )
    .bind(workId, reversalId, dedupeKey, nowIso, nowIso)
    .run();
}

async function parkReverseWorkRow(
  env: ReversalEnv,
  reversalId: string,
  lastError: string,
): Promise<void> {
  const dedupeKey = `reverse:${reversalId}`;
  const existing = await env.DB.prepare(
    `SELECT work_id FROM work WHERE dedupe_key = ?`,
  )
    .bind(dedupeKey)
    .first<{ work_id: string }>();
  if (existing !== null) {
    await env.DB.prepare(
      `UPDATE work SET state = 'parked', lease_until = NULL, last_error = ?
       WHERE work_id = ?`,
    )
      .bind(lastError, existing.work_id)
      .run();
    return;
  }
  const nowIso = await clockNowIso(env);
  const workId = await newId(env);
  await env.DB.prepare(
    `INSERT INTO work (
       work_id, kind, subject_id, dedupe_key, state, attempts,
       next_attempt_at, lease_until, last_error, opened_at
     ) VALUES (?, 'reverse', ?, ?, 'parked', 0, ?, NULL, ?, ?)`,
  )
    .bind(workId, reversalId, dedupeKey, nowIso, lastError, nowIso)
    .run();
}

async function reverseWorkExists(
  env: ReversalEnv,
  reversalId: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM work WHERE kind = 'reverse' AND subject_id = ?`,
  )
    .bind(reversalId)
    .first();
  return row !== null;
}

export async function processPendingNotificationReversals(
  env: ReversalEnv,
  options?: {
    budgetRemaining?: number;
    onInquired?: () => void | Promise<void>;
  },
): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT reversal_id FROM reversal
     WHERE detected_via = 'notification'
       AND effect IN ('tombstone', 'end_current', 'remove_queued')
       AND reversal_id NOT IN (SELECT reversal_id FROM reversal_outcome)`,
  ).all<{ reversal_id: string }>();

  let remaining = options?.budgetRemaining ?? Number.POSITIVE_INFINITY;

  for (const row of rows.results ?? []) {
    if (remaining <= 0) {
      break;
    }
    if (await reverseWorkExists(env, row.reversal_id)) {
      continue;
    }
    if (await findingExists(env, row.reversal_id, "inquiry_disagrees")) {
      continue;
    }
    const result = await verifyNotificationReversal(env, row.reversal_id);
    if (result.inquired) {
      remaining -= 1;
      await options?.onInquired?.();
    }
  }
}

async function takeReverseWork(
  env: ReversalEnv,
  workId: string,
): Promise<WorkRow | null> {
  if (await readSigningGatePaused(env)) {
    return null;
  }

  const nowMs = await clockNowMs(env);
  const nowIso = new Date(nowMs).toISOString();
  const leaseUntil = new Date(nowMs + LEASE_MS).toISOString();

  const leased = await env.DB.prepare(
    `UPDATE work
     SET lease_until = ?
     WHERE work_id = ?
       AND kind = 'reverse'
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
    `SELECT work_id, kind, subject_id, dedupe_key, state, attempts,
            next_attempt_at, lease_until, last_error
     FROM work WHERE work_id = ? AND lease_until = ?`,
  )
    .bind(workId, leaseUntil)
    .first<WorkRow>();
}

async function releaseReverseLeaseRetry(
  env: ReversalEnv,
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

export async function processReverseWork(
  env: ReversalEnv,
  workId: string,
): Promise<void> {
  const work = await takeReverseWork(env, workId);
  if (work === null) {
    return;
  }
  const leaseUntil = work.lease_until;
  if (leaseUntil === null) {
    return;
  }

  const reversal = await loadReversal(env, work.subject_id);
  if (reversal === null) {
    await env.DB.prepare(
      `UPDATE work SET state = 'done', lease_until = NULL WHERE work_id = ? AND lease_until = ?`,
    )
      .bind(work.work_id, leaseUntil)
      .run();
    return;
  }

  if (await reversalOutcomeExists(env, reversal.reversal_id)) {
    await env.DB.prepare(
      `DELETE FROM work WHERE work_id = ? AND lease_until = ?`,
    )
      .bind(work.work_id, leaseUntil)
      .run();
    return;
  }

  try {
    await callVoidForReversal(env, reversal);
    if (await reversalOutcomeExists(env, reversal.reversal_id)) {
      await env.DB.prepare(
        `DELETE FROM work WHERE work_id = ? AND lease_until = ?`,
      )
        .bind(work.work_id, leaseUntil)
        .run();
    } else {
      await releaseReverseLeaseRetry(env, work, leaseUntil, "void_pending");
    }
  } catch {
    await releaseReverseLeaseRetry(env, work, leaseUntil, "void_failed");
  }
}
