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

/** Adapter surface for checkout creation in this unit. */
export interface ProviderPort {
  capabilities(): ProviderCapabilities;
  createCheckout(input: CreateCheckoutInput): Promise<CreateCheckoutResult>;
  cancelCheckout(checkout_id: string): Promise<CancelCheckoutResult>;
}
