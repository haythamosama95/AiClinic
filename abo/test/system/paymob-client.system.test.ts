import { describe, expect, it, vi } from "vitest";
import {
  createPaymobIntention,
  fetchPaymobAuthToken,
  getPaymobAcceptanceTransaction,
  postPaymobOrderTransactionInquiry,
  type PaymobClientEnv,
} from "../../src/provider/paymob/client";

function clientEnv(
  baseUrl: string,
  fetch: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>,
): PaymobClientEnv {
  return {
    PAYMOB_BASE_URL: baseUrl,
    PAYMOB_SECRET_KEY: "secret",
    PAYMOB_API_KEY: "api-key",
    PAYMOB_CARD_INTEGRATION_ID: "123",
    PAYMOB_STUB: { fetch: vi.fn(fetch) } as unknown as Fetcher,
  };
}

describe("R3-C3: Paymob client URL composition", () => {
  it("uses the pinned absolute paths for an origin with a trailing slash", async () => {
    const urls: string[] = [];
    const env = clientEnv("https://accept.paymob.com/", async (input) => {
      urls.push(String(input));
      if (String(input).endsWith("/api/auth/tokens")) {
        return Response.json({ token: "auth-token" });
      }
      if (String(input).endsWith("/api/ecommerce/orders/transaction_inquiry")) {
        return Response.json({ id: 456 });
      }
      if (String(input).endsWith("/api/acceptance/transactions/txn%2F1")) {
        return Response.json({
          id: "txn/1",
          success: true,
          pending: false,
          is_refunded: false,
          is_voided: false,
          has_parent_transaction: false,
          amount_cents: 100,
          currency: "EGP",
          order: { id: 456 },
        });
      }
      return Response.json({
        id: "intent-1",
        intention_order_id: 456,
        client_secret: "client-secret",
      });
    });

    await createPaymobIntention(env, {
      amount_minor: 100,
      item_name: "Clinic plan",
      payer: { name: "Patient Example", email: "p@example.test", phone: "+201000000000" },
      reference: "checkout-1",
      return_url: "https://billing.example.test/return",
      notify_url: "https://billing.example.test/notify",
    });
    await fetchPaymobAuthToken(env);
    await postPaymobOrderTransactionInquiry(env, "auth-token", "456");
    await getPaymobAcceptanceTransaction(env, "auth-token", "txn/1");

    expect(urls).toEqual([
      "https://accept.paymob.com/v1/intention/",
      "https://accept.paymob.com/api/auth/tokens",
      "https://accept.paymob.com/api/ecommerce/orders/transaction_inquiry",
      "https://accept.paymob.com/api/acceptance/transactions/txn%2F1",
    ]);
  });

  it("rejects paths, queries, fragments, and insecure non-local origins before fetch", async () => {
    const fetch = vi.fn(async () => Response.json({ token: "must-not-be-read" }));

    for (const baseUrl of [
      "https://accept.paymob.com/api",
      "https://accept.paymob.com/?mode=test",
      "https://accept.paymob.com/#fragment",
      "http://accept.paymob.com",
    ]) {
      const outcome = await fetchPaymobAuthToken(clientEnv(baseUrl, fetch));
      expect(outcome).toEqual({ outcome: "error" });
    }

    expect(fetch).not.toHaveBeenCalled();
  });

  it("permits HTTP only for an explicitly stubbed local transport", async () => {
    const fetch = vi.fn(async () => Response.json({ token: "auth-token" }));
    const outcome = await fetchPaymobAuthToken(
      clientEnv("http://localhost:8787/", fetch),
    );

    expect(outcome).toEqual({ outcome: "ok", data: { token: "auth-token" } });
    expect(fetch).toHaveBeenCalledWith(
      "http://localhost:8787/api/auth/tokens",
      expect.any(Object),
    );
  });
});
