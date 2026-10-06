import type {
  CancelCheckoutResult,
  CreateCheckoutInput,
  CreateCheckoutResult,
  ProviderCapabilities,
  ProviderPort,
} from "../port.js";
import { clockNowMs, type ClockEnv } from "../../clock.js";
import {
  createPaymobIntention,
  type PaymobClientEnv,
} from "./client.js";

export type PaymobAdapterEnv = PaymobClientEnv &
  ClockEnv & {
    DB: D1Database;
    BILLING_HOST: string;
    PAYMOB_PUBLIC_KEY: string;
  };

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
  await env.DB.prepare(
    `INSERT INTO paymob_intention (
       checkout_id, intention_id, order_id, client_secret, special_reference, expires_at
     ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      checkoutId,
      intention.id,
      String(intention.intention_order_id),
      intention.client_secret,
      reference,
      expiresAt,
    )
    .run();
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
  };
}
