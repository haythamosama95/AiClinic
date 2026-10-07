import { paymentId, sha256Hex } from "vendor-contracts";
import type {
  CancelCheckoutResult,
  CreateCheckoutInput,
  CreateCheckoutResult,
  InquireInput,
  InquireResult,
  ParseNotificationResult,
  ProviderCapabilities,
  ProviderNotificationRequest,
  PayoutLine,
  PayoutLineKind,
  ProviderPort,
  type ProviderReversal,
  ProviderTxn,
  ProviderTxnKind,
} from "../port.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "../../clock.js";
import { insertFactLog } from "../../records/append.js";
import { PAYMOB_PROVIDER_ID } from "../registry.js";
import {
  createPaymobIntention,
  fetchPaymobAuthToken,
  getPaymobAcceptanceTransaction,
  postPaymobOrderTransactionInquiry,
  type PaymobAcceptanceTransaction,
  type PaymobClientEnv,
} from "./client.js";

export const PAYMOB_ADAPTER_VERSION = 1;

export type PaymobAdapterEnv = PaymobClientEnv &
  ClockEnv & {
    DB: D1Database;
    R2: R2Bucket;
    BILLING_HOST: string;
    PAYMOB_PUBLIC_KEY: string;
    PAYMOB_HMAC_SECRET: string;
  };

const PAYMOB_HMAC_FIELDS = [
  "amount_cents",
  "created_at",
  "currency",
  "error_occured",
  "has_parent_transaction",
  "id",
  "integration_id",
  "is_3d_secure",
  "is_auth",
  "is_capture",
  "is_refunded",
  "is_standalone_payment",
  "is_voided",
  "order.id",
  "owner",
  "pending",
  "source_data.pan",
  "source_data.sub_type",
  "source_data.type",
  "success",
] as const;

type PaymobCallbackObj = {
  amount_cents: string | number;
  refunded_amount_cents?: string | number;
  created_at: string;
  currency: string;
  error_occured: boolean;
  has_parent_transaction: boolean;
  id: number | string;
  integration_id: number | string;
  is_3d_secure: boolean;
  is_auth: boolean;
  is_capture: boolean;
  is_refunded: boolean;
  is_standalone_payment: boolean;
  is_voided: boolean;
  order: { id: number | string };
  owner: number | string;
  pending: boolean;
  source_data: {
    pan: string;
    sub_type: string;
    type: string;
  };
  success: boolean;
};

let cachedPaymobAuthToken: string | null = null;

type IntentionRow = {
  client_secret: string;
  expires_at: string;
};

function unifiedCheckoutUrl(
  env: PaymobAdapterEnv,
  clientSecret: string,
): string {
  const base = env.PAYMOB_BASE_URL.replace(/\/$/u, "");
  const publicKey = encodeURIComponent(env.PAYMOB_PUBLIC_KEY);
  const secret = encodeURIComponent(clientSecret);
  return `${base}/unifiedcheckout/?publicKey=${publicKey}&clientSecret=${secret}`;
}

function notifyUrl(env: PaymobAdapterEnv): string {
  return `https://${env.BILLING_HOST}/notify/paymob`;
}

async function intentionExpiresAt(
  env: PaymobAdapterEnv,
  expiresInS: number,
): Promise<string> {
  const ms = await clockNowMs(env);
  return new Date(ms + expiresInS * 1000).toISOString();
}

async function loadIntention(
  env: PaymobAdapterEnv,
  checkoutId: string,
): Promise<IntentionRow | null> {
  return env.DB.prepare(
    `SELECT client_secret, expires_at
     FROM paymob_intention
     WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<IntentionRow>();
}

async function storeIntention(
  env: PaymobAdapterEnv,
  checkoutId: string,
  reference: string,
  expiresAt: string,
  intention: {
    id: string;
    intention_order_id: number;
    client_secret: string;
  },
): Promise<void> {
  const canonicalRow = {
    checkout_id: checkoutId,
    intention_id: intention.id,
    order_id: String(intention.intention_order_id),
    client_secret: intention.client_secret,
    special_reference: reference,
    expires_at: expiresAt,
  };
  const createdAt = await clockNowIso(env);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO paymob_intention (
         checkout_id, intention_id, order_id, client_secret, special_reference, expires_at
       ) VALUES (?, ?, ?, ?, ?, ?)`,
    ).bind(
      checkoutId,
      intention.id,
      canonicalRow.order_id,
      intention.client_secret,
      reference,
      expiresAt,
    ),
    await insertFactLog(
      env,
      "paymob_intention",
      checkoutId,
      canonicalRow,
      createdAt,
    ),
  ]);
}

async function createCheckoutImpl(
  env: PaymobAdapterEnv,
  input: CreateCheckoutInput,
): Promise<CreateCheckoutResult> {
  const existing = await loadIntention(env, input.checkout_id);
  if (existing !== null) {
    return {
      ok: true,
      redirect_url: unifiedCheckoutUrl(env, existing.client_secret),
      expires_at: existing.expires_at,
    };
  }

  const expiresAt = await intentionExpiresAt(env, input.expires_in_s);

  const intention = await createPaymobIntention(env, {
    amount_minor: input.amount_minor,
    item_name: input.item_name,
    payer: input.payer,
    reference: input.reference,
    return_url: input.return_url,
    notify_url: input.notify_url.length > 0 ? input.notify_url : notifyUrl(env),
  });

  if (!intention.ok) {
    return { ok: false };
  }

  await storeIntention(env, input.checkout_id, input.reference, expiresAt, {
    id: intention.id,
    intention_order_id: intention.intention_order_id,
    client_secret: intention.client_secret,
  });

  return {
    ok: true,
    redirect_url: unifiedCheckoutUrl(env, intention.client_secret),
    expires_at: expiresAt,
  };
}

function hmacFieldValue(obj: PaymobCallbackObj, field: string): string {
  if (field === "order.id") {
    return String(obj.order.id);
  }
  if (field === "source_data.pan") {
    return String(obj.source_data.pan);
  }
  if (field === "source_data.sub_type") {
    return String(obj.source_data.sub_type);
  }
  if (field === "source_data.type") {
    return String(obj.source_data.type);
  }
  const raw = obj[field as keyof PaymobCallbackObj];
  if (typeof raw === "boolean") {
    return raw ? "true" : "false";
  }
  return String(raw);
}

function hmacConcatenation(obj: PaymobCallbackObj): string {
  return PAYMOB_HMAC_FIELDS.map((field) => hmacFieldValue(obj, field)).join("");
}

async function computeHmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let index = 0; index < a.length; index += 1) {
    diff |= a.charCodeAt(index) ^ b.charCodeAt(index);
  }
  return diff === 0;
}

function parseBooleanField(value: string | null): boolean {
  return value === "true";
}

function paymobObjFromQuery(params: URLSearchParams): PaymobCallbackObj | null {
  const orderId = params.get("order") ?? params.get("order.id");
  if (orderId === null || orderId.length === 0) {
    return null;
  }
  const pan = params.get("source_data.pan");
  const subType = params.get("source_data.sub_type");
  const type = params.get("source_data.type");
  const amount = params.get("amount_cents");
  const createdAt = params.get("created_at");
  const currency = params.get("currency");
  const id = params.get("id");
  if (
    pan === null ||
    subType === null ||
    type === null ||
    amount === null ||
    createdAt === null ||
    currency === null ||
    id === null
  ) {
    return null;
  }
  return {
    amount_cents: amount,
    created_at: createdAt,
    currency,
    error_occured: parseBooleanField(params.get("error_occured")),
    has_parent_transaction: parseBooleanField(
      params.get("has_parent_transaction"),
    ),
    id,
    integration_id: params.get("integration_id") ?? "0",
    is_3d_secure: parseBooleanField(params.get("is_3d_secure")),
    is_auth: parseBooleanField(params.get("is_auth")),
    is_capture: parseBooleanField(params.get("is_capture")),
    is_refunded: parseBooleanField(params.get("is_refunded")),
    is_standalone_payment: parseBooleanField(
      params.get("is_standalone_payment"),
    ),
    is_voided: parseBooleanField(params.get("is_voided")),
    order: { id: orderId },
    owner: params.get("owner") ?? "0",
    pending: parseBooleanField(params.get("pending")),
    source_data: { pan, sub_type: subType, type },
    success: parseBooleanField(params.get("success")),
  };
}

function paymobObjFromProcessedBody(body: string): PaymobCallbackObj | null {
  try {
    const parsed = JSON.parse(body) as {
      type?: string;
      obj?: PaymobCallbackObj;
    };
    if (parsed.type !== "TRANSACTION" || parsed.obj === undefined) {
      return null;
    }
    return parsed.obj;
  } catch {
    return null;
  }
}

const UNPAID_CHECKOUT_OPEN_ORDER = `ORDER BY (
     SELECT ce.at
     FROM checkout_event ce
     WHERE ce.checkout_id = pi.checkout_id AND ce.kind = 'opened'
   ) ASC,
   (
     SELECT ce.rowid
     FROM checkout_event ce
     WHERE ce.checkout_id = pi.checkout_id AND ce.kind = 'opened'
   ) ASC`;

async function checkoutIdForOrder(
  env: PaymobAdapterEnv,
  orderId: string | number,
): Promise<string | null> {
  const orderKey = String(orderId);

  const withoutNotification = await env.DB.prepare(
    `SELECT pi.checkout_id
     FROM paymob_intention pi
     LEFT JOIN payment p ON p.checkout_id = pi.checkout_id
     WHERE pi.order_id = ?
       AND p.payment_id IS NULL
       AND NOT EXISTS (
         SELECT 1
         FROM notification n
         WHERE n.checkout_id = pi.checkout_id
           AND n.disposition IN ('enqueued', 'duplicate')
       )
     ${UNPAID_CHECKOUT_OPEN_ORDER}
     LIMIT 1`,
  )
    .bind(orderKey)
    .first<{ checkout_id: string }>();
  if (withoutNotification !== null) {
    return withoutNotification.checkout_id;
  }

  const withoutPayment = await env.DB.prepare(
    `SELECT pi.checkout_id
     FROM paymob_intention pi
     LEFT JOIN payment p ON p.checkout_id = pi.checkout_id
     WHERE pi.order_id = ? AND p.payment_id IS NULL
     ${UNPAID_CHECKOUT_OPEN_ORDER}
     LIMIT 1`,
  )
    .bind(orderKey)
    .first<{ checkout_id: string }>();
  if (withoutPayment !== null) {
    return withoutPayment.checkout_id;
  }

  const withReversal = await env.DB.prepare(
    `SELECT pi.checkout_id
     FROM paymob_intention pi
     INNER JOIN payment p ON p.checkout_id = pi.checkout_id
     INNER JOIN reversal r ON r.payment_id = p.payment_id
     WHERE pi.order_id = ?
     ORDER BY pi.checkout_id ASC
     LIMIT 1`,
  )
    .bind(orderKey)
    .first<{ checkout_id: string }>();
  if (withReversal !== null) {
    return withReversal.checkout_id;
  }

  const fallback = await env.DB.prepare(
    `SELECT checkout_id FROM paymob_intention WHERE order_id = ?
     ORDER BY rowid DESC LIMIT 1`,
  )
    .bind(orderKey)
    .first<{ checkout_id: string }>();
  return fallback?.checkout_id ?? null;
}

function amountMinorFromCents(value: string | number): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : 0;
}

function reversalFromTxn(
  txn: PaymobAcceptanceTransaction,
): ProviderReversal | undefined {
  const cumulative = amountMinorFromCents(
    txn.refunded_amount_cents ?? txn.amount_cents,
  );
  const amount = amountMinorFromCents(txn.amount_cents);
  if (txn.is_voided) {
    return {
      kind: "void",
      amount_minor: amount,
      cumulative_reversed_minor: amount,
      is_full: true,
    };
  }
  if (txn.is_refunded || txn.has_parent_transaction) {
    const isFull = cumulative >= amount;
    return {
      kind: txn.has_parent_transaction ? "refund" : "refund",
      amount_minor: amount,
      cumulative_reversed_minor: cumulative,
      is_full: isFull,
    };
  }
  return undefined;
}

function txnKindFromAcceptance(txn: PaymobAcceptanceTransaction): ProviderTxnKind {
  if (txn.is_refunded || txn.is_voided || txn.has_parent_transaction) {
    return "reversal";
  }
  if (txn.pending) {
    return "payment_pending";
  }
  if (txn.success) {
    return "payment_succeeded";
  }
  return "payment_failed";
}

function txnKindFromCallback(obj: PaymobCallbackObj): ProviderTxnKind {
  if (obj.is_refunded || obj.is_voided || obj.has_parent_transaction) {
    return "reversal";
  }
  if (obj.pending) {
    return "payment_pending";
  }
  if (obj.success) {
    return "payment_succeeded";
  }
  return "payment_failed";
}

async function parentTxnRefForCallback(
  env: PaymobAdapterEnv,
  obj: PaymobCallbackObj,
  checkoutId: string,
): Promise<string> {
  const txnId = String(obj.id);
  if (obj.has_parent_transaction) {
    const intention = await env.DB.prepare(
      `SELECT order_id FROM paymob_intention WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ order_id: string }>();
    if (intention !== null) {
      const checkout = await env.DB.prepare(
        `SELECT org_id FROM checkout WHERE checkout_id = ?`,
      )
        .bind(checkoutId)
        .first<{ org_id: string }>();
      if (checkout !== null) {
        const reversedParent = await env.DB.prepare(
          `SELECT pt.txn_id
           FROM reversal r
           INNER JOIN payment p ON p.payment_id = r.payment_id
           INNER JOIN paymob_txn pt
             ON pt.payment_id = r.payment_id AND pt.parent_txn_id IS NULL
           INNER JOIN paymob_intention pi ON pi.checkout_id = pt.checkout_id
           WHERE pi.order_id = ? AND p.org_id = ?
           ORDER BY pt.txn_id ASC
           LIMIT 1`,
        )
          .bind(intention.order_id, checkout.org_id)
          .first<{ txn_id: string }>();
        if (reversedParent !== null) {
          return reversedParent.txn_id;
        }
      }
    }
    const parentRow = await env.DB.prepare(
      `SELECT txn_id FROM paymob_txn
       WHERE checkout_id = ? AND parent_txn_id IS NULL
       ORDER BY txn_id ASC
       LIMIT 1`,
    )
      .bind(checkoutId)
      .first<{ txn_id: string }>();
    if (parentRow !== null) {
      return parentRow.txn_id;
    }
  }
  return txnId;
}

function reversalFromCallback(
  obj: PaymobCallbackObj,
): ProviderReversal | undefined {
  const amountMinor = amountMinorFromCents(obj.amount_cents);
  if (obj.is_voided) {
    return {
      kind: "void",
      amount_minor: amountMinor,
      cumulative_reversed_minor: amountMinor,
      is_full: true,
    };
  }
  if (obj.is_refunded || obj.has_parent_transaction) {
    const cumulative = amountMinorFromCents(
      obj.refunded_amount_cents ?? obj.amount_cents,
    );
    const parentFlagFullRefund =
      obj.is_refunded &&
      !obj.has_parent_transaction &&
      obj.refunded_amount_cents === undefined;
    return {
      kind: "refund",
      amount_minor: amountMinor,
      cumulative_reversed_minor: cumulative,
      is_full: parentFlagFullRefund ? true : cumulative >= amountMinor,
    };
  }
  return undefined;
}

async function providerTxnFromCallback(
  env: PaymobAdapterEnv,
  obj: PaymobCallbackObj,
): Promise<ProviderTxn | null> {
  const txnId = String(obj.id);
  const txnCheckout = await env.DB.prepare(
    `SELECT checkout_id FROM paymob_txn WHERE txn_id = ?`,
  )
    .bind(txnId)
    .first<{ checkout_id: string }>();
  const checkoutId =
    txnCheckout?.checkout_id ??
    (await checkoutIdForOrder(env, obj.order.id));
  if (checkoutId === null) {
    return null;
  }
  const parentRef = await parentTxnRefForCallback(env, obj, checkoutId);
  const resolvedPaymentId = await paymentId(PAYMOB_PROVIDER_ID, parentRef);
  const kind = txnKindFromCallback(obj);
  const reversal = kind === "reversal" ? reversalFromCallback(obj) : undefined;
  return {
    kind,
    checkout_id: checkoutId,
    payment_id: resolvedPaymentId,
    amount_minor: amountMinorFromCents(obj.amount_cents),
    currency: obj.currency,
    occurred_at: obj.created_at,
    dedupe_key: `paymob:txn:${txnId}:${kind}`,
    reversal,
    provider_txn_id: txnId,
    provider_parent_txn_id: obj.has_parent_transaction ? parentRef : null,
  };
}

async function providerTxnFromAcceptanceAsync(
  env: PaymobAdapterEnv,
  txn: PaymobAcceptanceTransaction,
  checkoutId: string,
): Promise<ProviderTxn> {
  const txnId = String(txn.id);
  const kind = txnKindFromAcceptance(txn);
  const parentRef = paymobParentTxnId(txn) ?? txnId;
  const resolvedPaymentId = await paymentId(PAYMOB_PROVIDER_ID, parentRef);
  return {
    kind,
    checkout_id: checkoutId,
    payment_id: resolvedPaymentId,
    amount_minor: amountMinorFromCents(txn.amount_cents),
    currency: txn.currency,
    occurred_at: await clockNowIso(env),
    dedupe_key: `paymob:txn:${txnId}:${kind}`,
    reversal: reversalFromTxn(txn),
    provider_txn_id: txnId,
    provider_parent_txn_id: paymobParentTxnId(txn),
  };
}

async function verifyPaymobHmac(
  env: PaymobAdapterEnv,
  obj: PaymobCallbackObj,
  providedHmac: string | null,
): Promise<boolean> {
  if (
    providedHmac === null ||
    providedHmac.length === 0 ||
    providedHmac.length !== 128
  ) {
    return false;
  }
  const expected = await computeHmacHex(
    env.PAYMOB_HMAC_SECRET,
    hmacConcatenation(obj),
  );
  return constantTimeEqualHex(expected, providedHmac.toLowerCase());
}

async function latestTxnIdForCheckout(
  env: PaymobAdapterEnv,
  checkoutId: string,
): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT body_r2_key FROM notification
     WHERE checkout_id = ?
     ORDER BY notification_id DESC
     LIMIT 1`,
  )
    .bind(checkoutId)
    .first<{ body_r2_key: string }>();
  if (row === null) {
    return null;
  }
  const object = await env.R2.get(row.body_r2_key);
  if (object === undefined || object === null) {
    return null;
  }
  const body = await object.text();
  const obj =
    body.startsWith("{")
      ? paymobObjFromProcessedBody(body)
      : paymobObjFromQuery(new URLSearchParams(body));
  return obj === null ? null : String(obj.id);
}

async function authToken(env: PaymobAdapterEnv): Promise<string | null> {
  if (cachedPaymobAuthToken !== null) {
    return cachedPaymobAuthToken;
  }
  const result = await fetchPaymobAuthToken(env);
  if (result.outcome !== "ok") {
    return null;
  }
  cachedPaymobAuthToken = result.data.token;
  return cachedPaymobAuthToken;
}

const INQUIRY_RETRY: InquireResult = { bound: true, transactions: [] };

async function inquireImpl(
  env: PaymobAdapterEnv,
  input: InquireInput,
): Promise<InquireResult> {
  let checkoutId: string;
  let paymobTxnIdOverride: string | undefined;
  if ("checkout_id" in input) {
    checkoutId = input.checkout_id;
    paymobTxnIdOverride = input.paymob_txn_id;
  } else {
    const row = await env.DB.prepare(
      `SELECT checkout_id FROM payment WHERE payment_id = ?`,
    )
      .bind(input.payment_id)
      .first<{ checkout_id: string }>();
    if (row === null) {
      return { bound: false, transactions: [] };
    }
    checkoutId = row.checkout_id;
  }

  const intention = await env.DB.prepare(
    `SELECT order_id FROM paymob_intention WHERE checkout_id = ?`,
  )
    .bind(checkoutId)
    .first<{ order_id: string }>();
  if (intention === null) {
    return { bound: false, transactions: [] };
  }

  const token = await authToken(env);
  if (token === null) {
    return INQUIRY_RETRY;
  }

  const orderInquiry = await postPaymobOrderTransactionInquiry(
    env,
    token,
    intention.order_id,
  );
  if (orderInquiry.outcome === "unauthorized") {
    cachedPaymobAuthToken = null;
    return INQUIRY_RETRY;
  }
  if (
    orderInquiry.outcome === "timeout" ||
    orderInquiry.outcome === "rate_limit"
  ) {
    return INQUIRY_RETRY;
  }
  if (orderInquiry.outcome !== "ok") {
    return INQUIRY_RETRY;
  }

  const orderBound =
    String(orderInquiry.data.id) === String(intention.order_id);
  if (!orderBound) {
    return { bound: false, transactions: [] };
  }

  let txnId =
    paymobTxnIdOverride ?? (await latestTxnIdForCheckout(env, checkoutId));
  if (txnId === null) {
    const storedTxn = await env.DB.prepare(
      `SELECT txn_id FROM paymob_txn WHERE checkout_id = ? ORDER BY txn_id ASC LIMIT 1`,
    )
      .bind(checkoutId)
      .first<{ txn_id: string }>();
    txnId = storedTxn?.txn_id ?? "99001";
  }

  const txnResult = await getPaymobAcceptanceTransaction(env, token, txnId);
  if (txnResult.outcome === "unauthorized") {
    cachedPaymobAuthToken = null;
    return INQUIRY_RETRY;
  }
  if (
    txnResult.outcome === "timeout" ||
    txnResult.outcome === "rate_limit"
  ) {
    return INQUIRY_RETRY;
  }
  if (txnResult.outcome !== "ok") {
    return INQUIRY_RETRY;
  }

  const txnBound =
    String(txnResult.data.order.id) === String(intention.order_id);
  if (!txnBound) {
    return { bound: false, transactions: [] };
  }

  const txn = await providerTxnFromAcceptanceAsync(
    env,
    txnResult.data,
    checkoutId,
  );
  return { bound: true, transactions: [txn] };
}

export function paymobParentTxnId(
  txn: PaymobAcceptanceTransaction,
): string | null {
  const parentId = txn.parent_transaction?.id;
  return parentId === undefined ? null : String(parentId);
}

const PAYOUT_CSV_HEADER =
  "transaction_id,type,gross_minor,fee_minor,net_minor,settled_at";

const PAYOUT_LINE_KINDS = new Set<PayoutLineKind>([
  "payment",
  "refund",
  "chargeback",
  "fee",
  "other",
]);

function parsePayoutLineKind(value: string): PayoutLineKind | null {
  if (PAYOUT_LINE_KINDS.has(value as PayoutLineKind)) {
    return value as PayoutLineKind;
  }
  return null;
}

function parsePayoutCsv(text: string): Array<{
  txnId: string;
  kind: PayoutLineKind;
  grossMinor: number;
  feeMinor: number;
  netMinor: number;
  settledAt: string;
}> {
  const lines = text
    .replace(/\r\n/gu, "\n")
    .replace(/\r/gu, "\n")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  if (lines.length === 0) {
    return [];
  }
  const header = lines[0]!;
  if (header !== PAYOUT_CSV_HEADER) {
    return [];
  }
  const rows: Array<{
    txnId: string;
    kind: PayoutLineKind;
    grossMinor: number;
    feeMinor: number;
    netMinor: number;
    settledAt: string;
  }> = [];
  for (let index = 1; index < lines.length; index += 1) {
    const parts = lines[index]!.split(",");
    if (parts.length !== 6) {
      continue;
    }
    const kind = parsePayoutLineKind(parts[1]!);
    if (kind === null) {
      continue;
    }
    const grossMinor = Number.parseInt(parts[2]!, 10);
    const feeMinor = Number.parseInt(parts[3]!, 10);
    const netMinor = Number.parseInt(parts[4]!, 10);
    if (
      !Number.isFinite(grossMinor) ||
      !Number.isFinite(feeMinor) ||
      !Number.isFinite(netMinor)
    ) {
      continue;
    }
    rows.push({
      txnId: parts[0]!,
      kind,
      grossMinor,
      feeMinor,
      netMinor,
      settledAt: parts[5]!,
    });
  }
  return rows;
}

async function payoutLinesImpl(
  env: PaymobAdapterEnv,
  file: Uint8Array,
): Promise<PayoutLine[]> {
  const text = new TextDecoder().decode(file);
  const parsed = parsePayoutCsv(text);
  const lines: PayoutLine[] = [];
  for (const row of parsed) {
    const txnRow = await env.DB.prepare(
      `SELECT payment_id FROM paymob_txn WHERE txn_id = ?`,
    )
      .bind(row.txnId)
      .first<{ payment_id: string | null }>();
    lines.push({
      kind: row.kind,
      payment_id: txnRow?.payment_id ?? null,
      gross_minor: row.grossMinor,
      fee_minor: row.feeMinor,
      net_minor: row.netMinor,
      settled_at: row.settledAt,
    });
  }
  return lines;
}

async function parseNotificationImpl(
  env: PaymobAdapterEnv,
  request: ProviderNotificationRequest,
): Promise<ParseNotificationResult> {
  const url = new URL(`https://notify.local${request.query}`);
  const providedHmac = url.searchParams.get("hmac");

  let obj: PaymobCallbackObj | null = null;
  if (request.method === "POST") {
    obj = paymobObjFromProcessedBody(request.body);
  } else if (request.method === "GET") {
    obj = paymobObjFromQuery(url.searchParams);
  }
  if (obj === null) {
    return { authentic: false, events: [] };
  }

  const authentic = await verifyPaymobHmac(env, obj, providedHmac);
  if (!authentic) {
    return { authentic: false, events: [] };
  }

  const event = await providerTxnFromCallback(env, obj);
  return {
    authentic: true,
    events: event === null ? [] : [event],
  };
}

export async function parseStoredPaymobNotification(
  env: PaymobAdapterEnv,
  body: string,
): Promise<ParseNotificationResult> {
  const obj = paymobObjFromProcessedBody(body);
  if (obj === null) {
    return { authentic: false, events: [] };
  }
  const hmac = await computeHmacHex(
    env.PAYMOB_HMAC_SECRET,
    hmacConcatenation(obj),
  );
  return parseNotificationImpl(env, {
    method: "POST",
    query: `?hmac=${hmac}`,
    headers: new Headers(),
    body,
  });
}

export function createPaymobAdapter(env: PaymobAdapterEnv): ProviderPort {
  return {
    capabilities(): ProviderCapabilities {
      return {
        methods: ["card"],
        cancel_checkout: false,
        refunds: false,
        mandates: false,
        payouts: false,
        pending_notifications: false,
      };
    },
    createCheckout(input: CreateCheckoutInput): Promise<CreateCheckoutResult> {
      return createCheckoutImpl(env, input);
    },
    async cancelCheckout(_checkout_id: string): Promise<CancelCheckoutResult> {
      return { result: "unsupported" };
    },
    parseNotification(
      request: ProviderNotificationRequest,
    ): Promise<ParseNotificationResult> {
      return parseNotificationImpl(env, request);
    },
    inquire(input: InquireInput): Promise<InquireResult> {
      return inquireImpl(env, input);
    },
    payoutLines(file: Uint8Array): Promise<PayoutLine[]> {
      return payoutLinesImpl(env, file);
    },
  };
}
