const INTENTION_EXPIRATION_S = 1800;
const INTENTION_ABORT_MS = 10_000;
const TEST_CLOCK_INTENTION_ABORT_MS = 500;

export type PaymobClientEnv = {
  PAYMOB_BASE_URL: string;
  PAYMOB_SECRET_KEY: string;
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

function intentionAbortMs(env: PaymobClientEnv): number {
  return env.TEST_CLOCK === "1"
    ? TEST_CLOCK_INTENTION_ABORT_MS
    : INTENTION_ABORT_MS;
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
  const base = baseUrl.replace(/\/$/u, "");
  return `${base}/v1/intention/`;
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

  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    intentionAbortMs(env),
  );

  const intentionRequest = intentionUrl(env.PAYMOB_BASE_URL);
  const requestInit: RequestInit = {
    method: "POST",
    headers: {
      Authorization: `Token ${env.PAYMOB_SECRET_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: controller.signal,
  };
  try {
    const response = env.PAYMOB_STUB
      ? await env.PAYMOB_STUB.fetch(intentionRequest, requestInit)
      : await fetch(intentionRequest, requestInit);

    if (!response.ok) {
      return { ok: false };
    }

    const parsed = parseIntentionResponse(await response.json());
    return parsed ?? { ok: false };
  } catch {
    return { ok: false };
  } finally {
    clearTimeout(timeout);
  }
}
