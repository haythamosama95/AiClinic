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
import type { PaymobAdapterEnv } from "./provider/paymob/adapter.js";
import { PAYMOB_PROVIDER_ID, providerForId } from "./provider/registry.js";
import type { ProviderTxn } from "./provider/port.js";
import { insertFactLog } from "./records/append.js";
import { runReconciliation } from "./reconciliation/run.js";
import { runDueGrantWork } from "./work/grant.js";
import { recordPaidConfirmation } from "./work/runner.js";

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

export type RebuildEnv = PaymobAdapterEnv &
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
  const listed = await env.R2.list({ prefix: "ledger/" });
  const lines: LedgerLine[] = [];
  for (const object of listed.objects) {
    const body = await env.R2.get(object.key);
    if (body === null) {
      continue;
    }
    const parsed = JSON.parse(await body.text()) as LedgerLine;
    lines.push(parsed);
  }
  lines.sort((left, right) => left.fact_seq - right.fact_seq);
  return lines;
}

async function replayLedger(env: RebuildEnv, lines: LedgerLine[]): Promise<void> {
  const exportedAt = await clockNowIso(env);
  for (const line of lines) {
    const row = line.row;
    if (row === undefined) {
      continue;
    }
    await ledgerInsertStatement(env, line.table, row).run();
    await (
      await insertFactLog(
        env,
        line.table,
        line.key,
        row,
        factCreatedAt(row),
      )
    ).run();
    await env.DB.prepare(
      `INSERT INTO fact_export (fact_seq, exported_at) VALUES (?, ?)`,
    )
      .bind(line.fact_seq, exportedAt)
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
  const recorded = await recordPaidConfirmation(env, {
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

async function ensurePaymobIntentions(
  env: RebuildEnv,
  provider: NonNullable<ReturnType<typeof providerForId>>,
): Promise<void> {
  const checkouts = await env.DB.prepare(
    `SELECT c.checkout_id, c.reference, c.charged_price_minor, c.currency
     FROM checkout c
     LEFT JOIN payment p ON p.checkout_id = c.checkout_id
     LEFT JOIN paymob_intention pi ON pi.checkout_id = c.checkout_id
     WHERE p.payment_id IS NULL AND pi.checkout_id IS NULL`,
  ).all<{
    checkout_id: string;
    reference: string;
    charged_price_minor: number;
    currency: string;
  }>();

  for (const checkout of checkouts.results ?? []) {
    await provider.createCheckout({
      checkout_id: checkout.checkout_id,
      reference: checkout.reference,
      amount_minor: checkout.charged_price_minor,
      currency: checkout.currency,
      item_name: "Clinic subscription",
      payer: {
        name: "",
        email: "",
        phone: "",
      },
      expires_in_s: 1800,
      return_url: `https://${env.BILLING_HOST}/return/paymob`,
      notify_url: `https://${env.BILLING_HOST}/notify/paymob`,
    });
  }
}

async function inquireGapPayments(
  env: RebuildEnv,
  provider: NonNullable<ReturnType<typeof providerForId>>,
  options: RebuildOptions,
): Promise<string[]> {
  const gapFilledPaymentIds: string[] = [];
  await ensurePaymobIntentions(env, provider);

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
      if (!inquiry.bound) {
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
