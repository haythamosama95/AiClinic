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
  is_full: boolean;
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
};

/** Adapter surface for checkout creation in this unit. */
export interface ProviderPort {
  capabilities(): ProviderCapabilities;
  createCheckout(input: CreateCheckoutInput): Promise<CreateCheckoutResult>;
  cancelCheckout(checkout_id: string): Promise<CancelCheckoutResult>;
  parseNotification(
    request: ProviderNotificationRequest,
  ): Promise<ParseNotificationResult>;
  inquire(input: InquireInput): Promise<InquireResult>;
}
