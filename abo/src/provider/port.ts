/**
 * Payment-provider port (launch slice). Domain modules import this module and
 * `registry.ts` only — not Paymob adapter or client code.
 */

export type ProviderCapabilities = {
  methods: string[];
  cancel_checkout: boolean;
  refunds: boolean;
  mandates: boolean;
  payouts: boolean;
  pending_notifications: boolean;
};

export type CreateCheckoutPayer = {
  name: string;
  email: string;
  phone: string;
};

export type CreateCheckoutInput = {
  checkout_id: string;
  /** Precommitted provider-intention attempt being claimed by this call. */
  attempt_no: number;
  lease_token: string;
  reference: string;
  amount_minor: number;
  currency: string;
  item_name: string;
  payer: CreateCheckoutPayer;
  expires_in_s: number;
  return_url: string;
  notify_url: string;
};

export type CreateCheckoutSuccess = {
  ok: true;
  redirect_url: string;
  expires_at: string;
};

export type CreateCheckoutFailure = {
  ok: false;
};

export type CreateCheckoutResult = CreateCheckoutSuccess | CreateCheckoutFailure;

export type CancelCheckoutResult =
  | { result: "unsupported" }
  | { result: "cancelled" };

export type ProviderTxnKind =
  | "payment_succeeded"
  | "payment_failed"
  | "payment_pending"
  | "reversal";

export type ProviderReversalKind = "refund" | "void" | "chargeback" | "unknown";

export type ProviderReversal = {
  kind: ProviderReversalKind;
  amount_minor: number;
  cumulative_reversed_minor: number;
  /** True only when the authenticated original-parent inquiry supplied a valid cumulative. */
  cumulative_verified: boolean;
  /**
   * R9-AO2: adapter-owned opaque identity of this reversal transaction (matches payout CSV lines),
   * or null when the adapter gave none. Computed by the adapter, never by the domain layer.
   */
  reversal_ref: string | null;
};

/** Normalised provider transaction (04 §5.2). */
export type ProviderTxn = {
  kind: ProviderTxnKind;
  checkout_id: string;
  payment_id: string;
  amount_minor: number;
  currency: string;
  occurred_at: string;
  dedupe_key: string;
  reversal?: ProviderReversal;
  /** Paymob acceptance transaction id (adapter only). */
  provider_txn_id?: string;
  /** Paymob acceptance order id attached to this confirmed transaction (adapter only). */
  provider_order_id?: string;
  /** Paymob parent transaction id for child refunds (adapter only). */
  provider_parent_txn_id?: string | null;
};

/** Raw notify request surface passed to the adapter (04 §5.1). */
export type ProviderNotificationRequest = {
  method: string;
  query: string;
  headers: Headers;
  body: string;
};

export type ParseNotificationResult = {
  authentic: boolean;
  events: ProviderTxn[];
  /** False when the request could not be parsed as a provider notification. */
  parseable?: boolean;
};

export type InquireByCheckout = {
  checkout_id: string;
  /** Paymob acceptance transaction id from the notification being confirmed. */
  paymob_txn_id?: string;
};

export type InquireByPayment = {
  payment_id: string;
};

export type InquireInput = InquireByCheckout | InquireByPayment;

export type InquireResult = {
  bound: boolean;
  transactions: ProviderTxn[];
  /** Exact authenticated provider response bodies, captured before normalization. */
  evidence?: Array<{
    role: "transaction" | "order";
    raw_body: string;
    sha256: string;
  }>;
  /** The shared per-minute inquiry reservation was unavailable; retry the work later. */
  deferred?: boolean;
  /** Provider inquiry was attempted but its result could not be obtained. */
  unavailable?: boolean;
  /** No transaction identity is known and automatic order enumeration is not enabled. */
  discovery_unavailable?: boolean;
};

export type PayoutLineKind =
  | "payment"
  | "refund"
  | "chargeback"
  | "fee"
  | "other";

export type PayoutLine = {
  kind: PayoutLineKind;
  payment_id: string | null;
  gross_minor: number;
  fee_minor: number;
  net_minor: number;
  settled_at: string;
  /**
   * R9-AO2: opaque, adapter-owned identity of a refund or chargeback line. Null for every other
   * kind. Reconciliation compares it for equality only and never parses it.
   */
  reversal_ref: string | null;
  /** R9-AO2: positive normalized reversal amount for refund and chargeback lines, else null. */
  reversal_amount_minor: number | null;
};

/** One rejected payout-file line. `line_no` is 1-based over physical lines (the header is 1). */
export type PayoutLineError = {
  line_no: number;
  reason: string;
};

/**
 * Typed payout-file parse result (R9-AO7). A file is accepted only when every row is valid, at
 * least one row exists, and all rows settle in the same UTC month. `period` is that month (YYYY-MM).
 */
export type PayoutLinesResult =
  | { ok: true; period: string; lines: PayoutLine[] }
  | { ok: false; errors: PayoutLineError[] };

/** Adapter surface for checkout creation in this unit. */
export interface ProviderPort {
  capabilities(): ProviderCapabilities;
  createCheckout(input: CreateCheckoutInput): Promise<CreateCheckoutResult>;
  cancelCheckout(checkout_id: string): Promise<CancelCheckoutResult>;
  parseNotification(
    request: ProviderNotificationRequest,
  ): Promise<ParseNotificationResult>;
  inquire(input: InquireInput): Promise<InquireResult>;
  payoutLines(file: Uint8Array): Promise<PayoutLinesResult>;
}
