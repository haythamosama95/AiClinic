import {
  canonicalize,
  CHANNEL_VERSIONS,
  grantIdPaid,
  sha256Hex,
  signCompactJws,
  ulid,
} from "vendor-contracts";
import { refreshCoverageView } from "./coverage/view.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "./clock.js";
import {
  PAYMOB_PROVIDER_ID,
  providerForId,
  type ProviderRegistryEnv,
} from "./provider/registry.js";
import type { ProviderTxn } from "./provider/port.js";
import { insertFactLog } from "./records/append.js";
import { runReconciliation } from "./reconciliation/run.js";
import { runDueGrantWork } from "./work/grant.js";
import { recordRebuiltPaidConfirmation } from "./work/runner.js";

type LedgerLine = {
  fact_seq: number;
  table: string;
  key: string;
  row_sha256: string;
  row?: Record<string, unknown>;
};

type CheckoutRow = {
  checkout_id: string;
  org_id: string;
  offer_id: string;
  offer_version: number;
  charged_price_minor: number;
  currency: string;
  billing_contact_version: number;
  opened_with_coverage_through: string | null;
  contract_version: number;
};

type AboGrantKey = {
  kid: string;
  pkcs8: string;
  public_key: string;
};

type GrantCheckoutRow = {
  checkout_id: string;
  org_id: string;
  plan_id: string;
  plan_version: number;
  term_count: number;
  allowance_credits: number;
  grace_days: number;
  grace_cap_rule: string;
};

type GrantPaymentRow = {
  payment_id: string;
  org_id: string;
  checkout_id: string;
  paid_at: string;
};

export type RebuildEnv = ProviderRegistryEnv &
  ClockEnv & {
    DB: D1Database;
    R2: R2Bucket;
    ABO_GRANT_KEY: string;
    PLATFORM: {
      grant(args: Record<string, unknown>): Promise<Record<string, unknown>>;
      listGrants(args: Record<string, unknown>): Promise<Record<string, unknown>>;
      readCoverageEvents(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
    };
  };

export type RebuildOptions = {
  providerTransactionReferences: string[];
};

async function newId(env: RebuildEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

function factCreatedAt(row: Record<string, unknown>): string {
  for (const field of [
    "at",
    "confirmed_at",
    "detected_at",
    "created_at",
    "paid_at",
    "opened_at",
  ]) {
    const value = row[field];
    if (typeof value === "string" && value.length > 0) {
      return value;
    }
  }
  return new Date(0).toISOString();
}

function ledgerInsertStatement(
  env: RebuildEnv,
  table: string,
  row: Record<string, unknown>,
): D1PreparedStatement {
  const columns = Object.keys(row);
  const placeholders = columns.map(() => "?").join(", ");
  const values = columns.map((column) => row[column]);
  return env.DB.prepare(
    `INSERT INTO ${table} (${columns.join(", ")}) VALUES (${placeholders})`,
  ).bind(...values);
}

async function listLedgerLines(env: RebuildEnv): Promise<LedgerLine[]> {
  const lines: LedgerLine[] = [];
  let cursor: string | undefined;
  let truncated = true;
  while (truncated) {
    const listed = await env.R2.list({ prefix: "ledger/", cursor });
    for (const object of listed.objects) {
      const body = await env.R2.get(object.key);
      if (body === null) {
        continue;
      }
      const parsed = JSON.parse(await body.text()) as LedgerLine;
      lines.push(parsed);
    }
    truncated = listed.truncated;
    cursor = listed.truncated ? listed.cursor : undefined;
  }
  lines.sort((left, right) => left.fact_seq - right.fact_seq);
  return lines;
}

async function replayLedger(env: RebuildEnv, lines: LedgerLine[]): Promise<void> {
  const exportedAt = await clockNowIso(env);
  const checkoutCreatedAt = new Map<string, string>();
  for (const line of lines) {
    if (line.table !== "checkout" || line.row === undefined) {
      continue;
    }
    const createdAt = line.row.created_at;
    if (typeof createdAt === "string" && createdAt.length > 0) {
      checkoutCreatedAt.set(line.key, createdAt);
    }
  }
  // Older checkout facts predate checkout.created_at. Their immutable opened
  // event is the authoritative admission timestamp used to restore the new
  // projection column while the row is first inserted under append-only rules.
  for (const line of lines) {
    if (
      line.table !== "checkout_event" ||
      line.row === undefined ||
      line.row.kind !== "opened" ||
      typeof line.row.checkout_id !== "string" ||
      typeof line.row.at !== "string" ||
      line.row.at.length === 0
    ) {
      continue;
    }
    if (!checkoutCreatedAt.has(line.row.checkout_id)) {
      checkoutCreatedAt.set(line.row.checkout_id, line.row.at);
    }
  }

  for (const line of lines) {
    const row = line.row;
    if (row === undefined) {
      continue;
    }
    const admissionAt = line.table === "checkout"
      ? checkoutCreatedAt.get(line.key)
      : undefined;
    const insertedRow = line.table === "checkout" &&
        (typeof row.created_at !== "string" || row.created_at.length === 0) &&
        admissionAt !== undefined
      ? { ...row, created_at: admissionAt }
      : row;
    await ledgerInsertStatement(env, line.table, insertedRow).run();
    await (
      await insertFactLog(
        env,
        line.table,
        line.key,
        row,
        admissionAt ?? factCreatedAt(row),
      )
    ).run();
    await env.DB.prepare(
      `INSERT INTO fact_export (fact_seq, exported_at) VALUES (?, ?)`,
    )
      .bind(line.fact_seq, exportedAt)
      .run();
  }
}

type IntentionAttemptEventRow = {
  event_key: string;
  checkout_id: string;
  attempt_no: number;
  state: "pending" | "created" | "abandoned_unconfirmed";
  lease_token: string;
  lease_until: string;
  special_reference: string;
  intention_id: string | null;
  order_id: string | null;
  client_secret: string | null;
  expires_at: string | null;
  started_at: string | null;
  finished_at: string | null;
  event_at: string;
};

async function appendLegacyAttemptEvent(
  env: RebuildEnv,
  event: IntentionAttemptEventRow,
): Promise<void> {
  const existing = await env.DB.prepare(
    `SELECT 1 FROM paymob_intention_attempt_event WHERE event_key = ?`,
  )
    .bind(event.event_key)
    .first();
  if (existing === null) {
    await ledgerInsertStatement(
      env,
      "paymob_intention_attempt_event",
      event as unknown as Record<string, unknown>,
    ).run();
  }

  // Migration-created legacy events are derived from old facts and have no
  // fact_log entry. Add one so a subsequent ledger export carries the event.
  const fact = await env.DB.prepare(
    `SELECT 1 FROM fact_log
     WHERE "table" = 'paymob_intention_attempt_event' AND key = ? LIMIT 1`,
  )
    .bind(event.event_key)
    .first();
  if (fact === null) {
    await (
      await insertFactLog(
        env,
        "paymob_intention_attempt_event",
        event.event_key,
        event as unknown as Record<string, unknown>,
        event.event_at,
      )
    ).run();
  }
}

async function ensureLegacyAttemptEvents(env: RebuildEnv): Promise<void> {
  const intentions = await env.DB.prepare(
    `SELECT pi.checkout_id, pi.intention_id, pi.order_id, pi.client_secret,
            pi.special_reference, pi.expires_at, c.created_at
     FROM paymob_intention pi
     INNER JOIN checkout c ON c.checkout_id = pi.checkout_id`,
  ).all<{
    checkout_id: string;
    intention_id: string;
    order_id: string;
    client_secret: string;
    special_reference: string;
    expires_at: string;
    created_at: string | null;
  }>();
  for (const intention of intentions.results ?? []) {
    const eventKey = `${intention.checkout_id}:1:created:legacy`;
    const prior = await env.DB.prepare(
      `SELECT event_key FROM paymob_intention_attempt_event
       WHERE checkout_id = ? AND attempt_no = 1 LIMIT 1`,
    )
      .bind(intention.checkout_id)
      .first<{ event_key: string }>();
    if (prior !== null && prior.event_key !== eventKey) {
      continue;
    }
    const eventAt = intention.created_at ?? intention.expires_at;
    await appendLegacyAttemptEvent(env, {
      event_key: eventKey,
      checkout_id: intention.checkout_id,
      attempt_no: 1,
      state: "created",
      lease_token: "legacy",
      lease_until: intention.expires_at,
      special_reference: intention.special_reference,
      intention_id: intention.intention_id,
      order_id: intention.order_id,
      client_secret: intention.client_secret,
      expires_at: intention.expires_at,
      started_at: intention.created_at,
      finished_at: intention.created_at,
      event_at: eventAt,
    });
  }

  const failedCheckouts = await env.DB.prepare(
    `SELECT c.checkout_id, c.reference, c.expires_at, c.created_at,
            COALESCE(cs.last_event_at, (
              SELECT MAX(oe.at) FROM checkout_event oe
              WHERE oe.checkout_id = c.checkout_id AND oe.kind = 'open_failed'
            ), c.created_at, c.expires_at) AS failed_at
     FROM checkout c
     INNER JOIN checkout_status cs ON cs.checkout_id = c.checkout_id
     LEFT JOIN paymob_intention pi ON pi.checkout_id = c.checkout_id
     WHERE cs.state = 'open_failed' AND pi.checkout_id IS NULL`,
  ).all<{
    checkout_id: string;
    reference: string;
    expires_at: string;
    created_at: string | null;
    failed_at: string;
  }>();
  for (const checkout of failedCheckouts.results ?? []) {
    const eventKey = `${checkout.checkout_id}:1:abandoned_unconfirmed:legacy`;
    const prior = await env.DB.prepare(
      `SELECT event_key FROM paymob_intention_attempt_event
       WHERE checkout_id = ? AND attempt_no = 1 LIMIT 1`,
    )
      .bind(checkout.checkout_id)
      .first<{ event_key: string }>();
    if (prior !== null && prior.event_key !== eventKey) {
      continue;
    }
    await appendLegacyAttemptEvent(env, {
      event_key: eventKey,
      checkout_id: checkout.checkout_id,
      attempt_no: 1,
      state: "abandoned_unconfirmed",
      lease_token: "legacy",
      lease_until: checkout.expires_at,
      special_reference: checkout.reference,
      intention_id: null,
      order_id: null,
      client_secret: null,
      expires_at: null,
      started_at: checkout.created_at,
      finished_at: checkout.failed_at,
      event_at: checkout.failed_at,
    });
  }
}

async function rebuildIntentionAttempts(env: RebuildEnv): Promise<void> {
  const listed = await env.DB.prepare(
    `SELECT event_key, checkout_id, attempt_no, state, lease_token, lease_until,
            special_reference, intention_id, order_id, client_secret, expires_at,
            started_at, finished_at, event_at
     FROM paymob_intention_attempt_event ORDER BY rowid ASC`,
  ).all<IntentionAttemptEventRow>();
  const latest = new Map<string, IntentionAttemptEventRow>();
  for (const event of listed.results ?? []) {
    latest.set(`${event.checkout_id}:${event.attempt_no}`, event);
  }

  // paymob_intention_attempt is an operational projection. Replacing it from
  // append-only event rows prevents ledger replay from trying to insert every
  // historical snapshot into its (checkout_id, attempt_no) primary key.
  await env.DB.prepare(`DELETE FROM paymob_intention_attempt`).run();
  for (const event of latest.values()) {
    await env.DB.prepare(
      `INSERT INTO paymob_intention_attempt (
         checkout_id, attempt_no, state, lease_token, lease_until,
         special_reference, intention_id, order_id, client_secret, expires_at,
         started_at, finished_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        event.checkout_id,
        event.attempt_no,
        event.state,
        event.lease_token,
        event.lease_until,
        event.special_reference,
        event.intention_id,
        event.order_id,
        event.client_secret,
        event.expires_at,
        event.started_at,
        event.finished_at,
      )
      .run();
  }
}

function checkoutStatusFromEventKind(kind: string): string {
  if (kind === "opened") {
    return "open";
  }
  if (kind === "late_paid") {
    return "paid_late";
  }
  return kind;
}

async function recomputeCheckoutStatus(env: RebuildEnv): Promise<void> {
  const checkouts = await env.DB.prepare(
    `SELECT checkout_id FROM checkout`,
  ).all<{ checkout_id: string }>();
  for (const checkout of checkouts.results ?? []) {
    const latest = await env.DB.prepare(
      `SELECT kind, at FROM checkout_event
       WHERE checkout_id = ?
       ORDER BY at DESC, rowid DESC
       LIMIT 1`,
    )
      .bind(checkout.checkout_id)
      .first<{ kind: string; at: string }>();

    const payment = await env.DB.prepare(
      `SELECT classification, confirmed_at FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkout.checkout_id)
      .first<{ classification: string; confirmed_at: string }>();

    let state: string | null = null;
    let lastEventAt: string | null = null;
    if (latest !== null) {
      state = checkoutStatusFromEventKind(latest.kind);
      lastEventAt = latest.at;
    }
    if (payment !== null) {
      const paidState =
        payment.classification === "late" ? "paid_late" : "paid";
      const paidAtMs = Date.parse(payment.confirmed_at);
      const eventAtMs = lastEventAt === null ? Number.NaN : Date.parse(lastEventAt);
      if (
        state === null ||
        state === "open" ||
        (!Number.isNaN(paidAtMs) &&
          !Number.isNaN(eventAtMs) &&
          paidAtMs >= eventAtMs)
      ) {
        state = paidState;
        lastEventAt = payment.confirmed_at;
      }
    }
    if (state === null || lastEventAt === null) {
      continue;
    }
    await env.DB.prepare(
      `INSERT INTO checkout_status (checkout_id, state, last_event_at)
       VALUES (?, ?, ?)`,
    )
      .bind(checkout.checkout_id, state, lastEventAt)
      .run();
  }
}

async function loadCheckout(
  env: RebuildEnv,
  checkoutId: string,
): Promise<CheckoutRow | null> {
  return env.DB.prepare(
    `SELECT checkout_id, org_id, offer_id, offer_version, charged_price_minor,
            currency, billing_contact_version, opened_with_coverage_through,
            contract_version
     FROM checkout WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<CheckoutRow>();
}

async function paymentExists(
  env: RebuildEnv,
  paymentId: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM payment WHERE payment_id = ?`,
  )
    .bind(paymentId)
    .first();
  return row !== null;
}

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

async function loadGrantPayment(
  env: RebuildEnv,
  paymentId: string,
): Promise<GrantPaymentRow | null> {
  return env.DB.prepare(
    `SELECT payment_id, org_id, checkout_id, paid_at
     FROM payment WHERE payment_id = ?`,
  )
    .bind(paymentId)
    .first<GrantPaymentRow>();
}

async function loadGrantCheckout(
  env: RebuildEnv,
  checkoutId: string,
): Promise<GrantCheckoutRow | null> {
  return env.DB.prepare(
    `SELECT checkout_id, org_id, plan_id, plan_version, term_count,
            allowance_credits, grace_days, grace_cap_rule
     FROM checkout WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<GrantCheckoutRow>();
}

async function paymentFactSha256(
  env: RebuildEnv,
  paymentId: string,
): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT row_sha256 FROM fact_log WHERE "table" = 'payment' AND key = ?`,
  )
    .bind(paymentId)
    .first<{ row_sha256: string }>();
  return row?.row_sha256 ?? null;
}

async function grantOutcomeExists(
  env: RebuildEnv,
  grantId: string,
): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM grant_outcome WHERE grant_id = ?`,
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
  payment: GrantPaymentRow,
  checkout: GrantCheckoutRow,
  contentSha256: string,
): Promise<{
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
  return { envelopeBytes, grantId };
}

async function preapplyPlatformGrant(
  env: RebuildEnv,
  paymentId: string,
): Promise<void> {
  const grantId = await grantIdPaid(paymentId);
  if (await grantOutcomeExists(env, grantId)) {
    return;
  }

  const payment = await loadGrantPayment(env, paymentId);
  if (payment === null) {
    return;
  }
  const checkout = await loadGrantCheckout(env, payment.checkout_id);
  if (checkout === null) {
    return;
  }
  const contentSha256 = await paymentFactSha256(env, paymentId);
  if (contentSha256 === null) {
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

  const { envelopeBytes } = await buildGrantEnvelope(
    payment,
    checkout,
    contentSha256,
  );
  const aboSignature = await signCompactJws({
    payload: envelopeBytes,
    privateKey,
    kid: aboKey.kid,
  });

  await env.PLATFORM.grant({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
    abo_kid: aboKey.kid,
    abo_signature: aboSignature,
    envelope_b64: envelopeB64(envelopeBytes),
  });
}

async function preapplyPlatformGrants(
  env: RebuildEnv,
  paymentIds: Iterable<string>,
): Promise<void> {
  for (const paymentId of paymentIds) {
    await preapplyPlatformGrant(env, paymentId);
  }
}

async function awaitPlatformGrantInList(
  env: RebuildEnv,
  grantId: string,
): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const grants = await parsePlatformGrants(env);
    if (
      grants?.some((grant) => String(grant.grant_id ?? "") === grantId) === true
    ) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}

async function awaitGapGrantsInList(
  env: RebuildEnv,
  paymentIds: Iterable<string>,
): Promise<void> {
  for (const paymentId of paymentIds) {
    await awaitPlatformGrantInList(env, await grantIdPaid(paymentId));
  }
}

async function maybeRecordSucceededPayment(
  env: RebuildEnv,
  checkoutId: string,
  confirmedTxn: ProviderTxn,
  paymobTxnId?: string,
): Promise<boolean> {
  if (confirmedTxn.kind !== "payment_succeeded") {
    return false;
  }
  if (await paymentExists(env, confirmedTxn.payment_id)) {
    return false;
  }
  const checkout = await loadCheckout(env, checkoutId);
  if (checkout === null) {
    return false;
  }
  const nowIso = await clockNowIso(env);
  const inquiryId = await newId(env);
  const recorded = await recordRebuiltPaidConfirmation(env, {
    checkout,
    confirmedTxn,
    inquiryId,
    evidenceSha256: await sha256Hex(new TextEncoder().encode("")),
    nowIso,
    paymobTxnId,
  });
  return recorded;
}

async function paidGrantIdsFromPayments(env: RebuildEnv): Promise<Set<string>> {
  const rows = await env.DB.prepare(`SELECT payment_id FROM payment`).all<{
    payment_id: string;
  }>();
  const grantIds = new Set<string>();
  for (const row of rows.results ?? []) {
    grantIds.add(await grantIdPaid(row.payment_id));
  }
  return grantIds;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

async function parsePlatformGrants(
  env: RebuildEnv,
): Promise<Record<string, unknown>[] | null> {
  const envelope = await env.PLATFORM.listGrants({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
  });
  if (envelope.result !== "ok" || typeof envelope.detail !== "string") {
    return null;
  }
  const parsed = JSON.parse(envelope.detail) as unknown;
  return Array.isArray(parsed) ? (parsed as Record<string, unknown>[]) : [];
}

async function inquireGapPayments(
  env: RebuildEnv,
  provider: NonNullable<ReturnType<typeof providerForId>>,
  options: RebuildOptions,
): Promise<string[]> {
  const gapFilledPaymentIds: string[] = [];

  // Explicit transaction references are the operator's stated repair target.
  // Give them the shared inquiry slots before broad recovery scans consume the
  // per-minute cap; remaining scans stay read-only when they are deferred.
  for (const reference of options.providerTransactionReferences) {
    const candidates = await env.DB.prepare(
      `SELECT pi.checkout_id
       FROM paymob_intention pi
       LEFT JOIN payment p ON p.checkout_id = pi.checkout_id
       WHERE p.payment_id IS NULL`,
    ).all<{ checkout_id: string }>();
    for (const candidate of candidates.results ?? []) {
      const inquiry = await provider.inquire({
        checkout_id: candidate.checkout_id,
        paymob_txn_id: reference,
      });
      if (!inquiry.bound || inquiry.deferred) {
        continue;
      }
      for (const txn of inquiry.transactions) {
        const recorded = await maybeRecordSucceededPayment(
          env,
          candidate.checkout_id,
          txn,
          reference,
        );
        if (recorded) {
          gapFilledPaymentIds.push(txn.payment_id);
        }
      }
    }
  }

  const checkouts = await env.DB.prepare(
    `SELECT checkout_id FROM checkout`,
  ).all<{ checkout_id: string }>();
  for (const checkout of checkouts.results ?? []) {
    await provider.inquire({ checkout_id: checkout.checkout_id });
  }

  const payments = await env.DB.prepare(
    `SELECT payment_id FROM payment`,
  ).all<{ payment_id: string }>();
  for (const payment of payments.results ?? []) {
    await provider.inquire({ payment_id: payment.payment_id });
  }

  const paidGrantIds = await paidGrantIdsFromPayments(env);
  const grants = await parsePlatformGrants(env);
  if (grants !== null) {
    for (const grant of grants) {
      if (grant.source_kind !== "paid") {
        continue;
      }
      const grantId = String(grant.grant_id ?? "");
      if (grantId.length === 0 || paidGrantIds.has(grantId)) {
        continue;
      }
      const source = grant.source;
      const paymentId =
        isRecord(source) && typeof source.ref === "string" ? source.ref : null;
      if (paymentId === null || await paymentExists(env, paymentId)) {
        continue;
      }
      const inquiry = await provider.inquire({ payment_id: paymentId });
      if (!inquiry.bound) {
        continue;
      }
      for (const txn of inquiry.transactions) {
        const recorded = await maybeRecordSucceededPayment(
          env,
          txn.checkout_id,
          txn,
        );
        if (recorded) {
          gapFilledPaymentIds.push(txn.payment_id);
        }
      }
    }
  }

  return gapFilledPaymentIds;
}

export async function rebuildAbo(
  env: RebuildEnv,
  options: RebuildOptions,
): Promise<void> {
  const lines = await listLedgerLines(env);
  await replayLedger(env, lines);
  await recomputeCheckoutStatus(env);
  await ensureLegacyAttemptEvents(env);
  await rebuildIntentionAttempts(env);
  await refreshCoverageView(env);

  const provider = providerForId(env, PAYMOB_PROVIDER_ID);
  if (provider !== null) {
    const gapFilledPaymentIds = await inquireGapPayments(env, provider, options);
    await preapplyPlatformGrants(env, gapFilledPaymentIds);
    await awaitGapGrantsInList(env, gapFilledPaymentIds);
    await runDueGrantWork(env, 100);
    await refreshCoverageView(env);
  }

  await runReconciliation(env);
}
