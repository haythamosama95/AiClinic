const INTENTION_EXPIRATION_S = 1800;
const PROVIDER_HTTP_ABORT_MS = 10_000;
const TEST_CLOCK_PROVIDER_HTTP_ABORT_MS = 500;

export type PaymobClientEnv = {
  PAYMOB_BASE_URL: string;
  PAYMOB_SECRET_KEY: string;
  PAYMOB_API_KEY?: string;
  PAYMOB_CARD_INTEGRATION_ID: string;
  TEST_CLOCK?: string;
  PAYMOB_STUB?: Fetcher;
};

export type PaymobPayer = {
  name: string;
  email: string;
  phone: string;
};

export type CreatePaymobIntentionInput = {
  amount_minor: number;
  item_name: string;
  payer: PaymobPayer;
  reference: string;
  return_url: string;
  notify_url: string;
};

export type CreatePaymobIntentionResult =
  | {
      ok: true;
      id: string;
      intention_order_id: number;
      client_secret: string;
    }
  | { ok: false };

export type PaymobInquiryHttpOutcome<T> =
  | { outcome: "ok"; data: T }
  | { outcome: "timeout" }
  | { outcome: "rate_limit" }
  | { outcome: "unauthorized" }
  | { outcome: "error" };

export type PaymobAuthTokenResult = PaymobInquiryHttpOutcome<{ token: string }>;

export type PaymobOrderInquiry = {
  id: string | number;
  amount_cents?: string | number;
  currency?: string;
};

export type PaymobAcceptanceTransaction = {
  id: string | number;
  success: boolean;
  pending: boolean;
  is_refunded: boolean;
  is_voided: boolean;
  has_parent_transaction: boolean;
  amount_cents: string | number;
  currency: string;
  order: { id: string | number };
  refunded_amount_cents?: string | number;
  parent_transaction?: { id: string | number };
};

function providerHttpAbortMs(env: PaymobClientEnv): number {
  return env.TEST_CLOCK === "1"
    ? TEST_CLOCK_PROVIDER_HTTP_ABORT_MS
    : PROVIDER_HTTP_ABORT_MS;
}

function paymobBaseUrl(baseUrl: string): string {
  return baseUrl.replace(/\/$/u, "");
}

function splitPayerName(name: string): { first_name: string; last_name: string } {
  const trimmed = name.trim();
  const space = trimmed.indexOf(" ");
  if (space === -1) {
    return { first_name: trimmed, last_name: trimmed };
  }
  return {
    first_name: trimmed.slice(0, space),
    last_name: trimmed.slice(space + 1).trim() || trimmed.slice(0, space),
  };
}

function intentionUrl(baseUrl: string): string {
  return `${paymobBaseUrl(baseUrl)}/v1/intention/`;
}

function authTokenUrl(baseUrl: string): string {
  return `${paymobBaseUrl(baseUrl)}/api/auth/tokens`;
}

function orderTransactionInquiryUrl(baseUrl: string): string {
  return `${paymobBaseUrl(baseUrl)}/api/ecommerce/orders/transaction_inquiry`;
}

function acceptanceTransactionUrl(baseUrl: string, txnId: string): string {
  const encoded = encodeURIComponent(txnId);
  return `${paymobBaseUrl(baseUrl)}/api/acceptance/transactions/${encoded}`;
}

async function paymobProviderFetch(
  env: PaymobClientEnv,
  url: string,
  init: RequestInit,
): Promise<Response | "timeout"> {
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    providerHttpAbortMs(env),
  );

  try {
    return env.PAYMOB_STUB
      ? await env.PAYMOB_STUB.fetch(url, {
          ...init,
          signal: controller.signal,
        })
      : await fetch(url, { ...init, signal: controller.signal });
  } catch {
    return "timeout";
  } finally {
    clearTimeout(timeout);
  }
}

async function mapInquiryResponse<T>(
  response: Response | "timeout",
  parse: (data: unknown) => T | null,
): Promise<PaymobInquiryHttpOutcome<T>> {
  if (response === "timeout") {
    return { outcome: "timeout" };
  }
  if (response.status === 429) {
    return { outcome: "rate_limit" };
  }
  if (response.status === 401) {
    return { outcome: "unauthorized" };
  }
  if (!response.ok) {
    return { outcome: "error" };
  }

  return parseJsonBody(response, parse);
}

async function parseJsonBody<T>(
  response: Response,
  parse: (data: unknown) => T | null,
): Promise<PaymobInquiryHttpOutcome<T>> {
  try {
    const data: unknown = await response.json();
    const parsed = parse(data);
    return parsed === null ? { outcome: "error" } : { outcome: "ok", data: parsed };
  } catch {
    return { outcome: "error" };
  }
}

function parseAuthTokenResponse(data: unknown): { token: string } | null {
  if (data === null || typeof data !== "object") {
    return null;
  }
  const token = (data as Record<string, unknown>).token;
  if (typeof token !== "string" || token.length === 0) {
    return null;
  }
  return { token };
}

function parseOrderInquiryResponse(data: unknown): PaymobOrderInquiry | null {
  if (data === null || typeof data !== "object") {
    return null;
  }
  const record = data as Record<string, unknown>;
  const id = record.id;
  if (
    (typeof id !== "string" && typeof id !== "number") ||
    (typeof id === "number" && !Number.isFinite(id))
  ) {
    return null;
  }
  return {
    id,
    amount_cents: record.amount_cents as string | number | undefined,
    currency:
      typeof record.currency === "string" ? record.currency : undefined,
  };
}

function parseAcceptanceTransactionResponse(
  data: unknown,
): PaymobAcceptanceTransaction | null {
  if (data === null || typeof data !== "object") {
    return null;
  }
  const record = data as Record<string, unknown>;
  const id = record.id;
  const order = record.order;
  if (
    (typeof id !== "string" && typeof id !== "number") ||
    (typeof id === "number" && !Number.isFinite(id)) ||
    order === null ||
    typeof order !== "object"
  ) {
    return null;
  }
  const orderRecord = order as Record<string, unknown>;
  const orderId = orderRecord.id;
  if (
    (typeof orderId !== "string" && typeof orderId !== "number") ||
    (typeof orderId === "number" && !Number.isFinite(orderId))
  ) {
    return null;
  }

  if (
    typeof record.success !== "boolean" ||
    typeof record.pending !== "boolean" ||
    typeof record.is_refunded !== "boolean" ||
    typeof record.is_voided !== "boolean" ||
    typeof record.has_parent_transaction !== "boolean" ||
    typeof record.currency !== "string"
  ) {
    return null;
  }

  const amountCents = record.amount_cents;
  if (
    (typeof amountCents !== "string" && typeof amountCents !== "number") ||
    (typeof amountCents === "number" && !Number.isFinite(amountCents))
  ) {
    return null;
  }

  const refundedAmount = record.refunded_amount_cents;
  const refundedAmountCents =
    refundedAmount === undefined
      ? undefined
      : typeof refundedAmount === "string" || typeof refundedAmount === "number"
        ? refundedAmount
        : undefined;

  let parentTransaction: { id: string | number } | undefined;
  const parent = record.parent_transaction;
  if (parent !== null && typeof parent === "object") {
    const parentRecord = parent as Record<string, unknown>;
    const parentId = parentRecord.id;
    if (
      (typeof parentId === "string" || typeof parentId === "number") &&
      (typeof parentId !== "number" || Number.isFinite(parentId))
    ) {
      parentTransaction = { id: parentId };
    }
  }

  return {
    id,
    success: record.success,
    pending: record.pending,
    is_refunded: record.is_refunded,
    is_voided: record.is_voided,
    has_parent_transaction: record.has_parent_transaction,
    amount_cents: amountCents,
    currency: record.currency,
    order: { id: orderId },
    refunded_amount_cents: refundedAmountCents,
    parent_transaction: parentTransaction,
  };
}

function buildIntentionBody(
  env: PaymobClientEnv,
  input: CreatePaymobIntentionInput,
): Record<string, unknown> | null {
  const integrationId = Number(env.PAYMOB_CARD_INTEGRATION_ID);
  if (!Number.isFinite(integrationId)) {
    return null;
  }

  const { first_name, last_name } = splitPayerName(input.payer.name);

  return {
    amount: input.amount_minor,
    currency: "EGP",
    payment_methods: [integrationId],
    items: [
      {
        name: input.item_name,
        amount: input.amount_minor,
        quantity: 1,
      },
    ],
    billing_data: {
      first_name,
      last_name,
      email: input.payer.email,
      phone_number: input.payer.phone,
    },
    special_reference: input.reference,
    expiration: INTENTION_EXPIRATION_S,
    notification_url: input.notify_url,
    redirection_url: input.return_url,
  };
}

function parseIntentionResponse(
  data: unknown,
): CreatePaymobIntentionResult | null {
  if (data === null || typeof data !== "object") {
    return null;
  }
  const record = data as Record<string, unknown>;
  const id = record.id;
  const clientSecret = record.client_secret;
  const orderId = record.intention_order_id;
  if (typeof id !== "string" || typeof clientSecret !== "string") {
    return null;
  }
  if (typeof orderId !== "number" || !Number.isFinite(orderId)) {
    return null;
  }
  return {
    ok: true,
    id,
    intention_order_id: orderId,
    client_secret: clientSecret,
  };
}

export async function createPaymobIntention(
  env: PaymobClientEnv,
  input: CreatePaymobIntentionInput,
): Promise<CreatePaymobIntentionResult> {
  const body = buildIntentionBody(env, input);
  if (body === null) {
    return { ok: false };
  }

  const response = await paymobProviderFetch(env, intentionUrl(env.PAYMOB_BASE_URL), {
    method: "POST",
    headers: {
      Authorization: `Token ${env.PAYMOB_SECRET_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (response === "timeout") {
    return { ok: false };
  }
  if (!response.ok) {
    return { ok: false };
  }

  try {
    const parsed = parseIntentionResponse(await response.json());
    return parsed ?? { ok: false };
  } catch {
    return { ok: false };
  }
}

export async function fetchPaymobAuthToken(
  env: PaymobClientEnv,
): Promise<PaymobAuthTokenResult> {
  const apiKey = env.PAYMOB_API_KEY;
  if (apiKey === undefined || apiKey.length === 0) {
    return { outcome: "error" };
  }

  const response = await paymobProviderFetch(
    env,
    authTokenUrl(env.PAYMOB_BASE_URL),
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ api_key: apiKey }),
    },
  );
  return await mapInquiryResponse(response, parseAuthTokenResponse);
}

export async function postPaymobOrderTransactionInquiry(
  env: PaymobClientEnv,
  authToken: string,
  orderId: string,
): Promise<PaymobInquiryHttpOutcome<PaymobOrderInquiry>> {
  const response = await paymobProviderFetch(
    env,
    orderTransactionInquiryUrl(env.PAYMOB_BASE_URL),
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${authToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ order_id: orderId }),
    },
  );
  return await mapInquiryResponse(response, parseOrderInquiryResponse);
}

export async function getPaymobAcceptanceTransaction(
  env: PaymobClientEnv,
  authToken: string,
  txnId: string,
): Promise<PaymobInquiryHttpOutcome<PaymobAcceptanceTransaction>> {
  const response = await paymobProviderFetch(
    env,
    acceptanceTransactionUrl(env.PAYMOB_BASE_URL, txnId),
    {
      method: "GET",
      headers: {
        Authorization: `Bearer ${authToken}`,
      },
    },
  );
  return await mapInquiryResponse(response, parseAcceptanceTransactionResponse);
}
