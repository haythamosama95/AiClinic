/**
 * H-PAY stub (P4.2 cross-worker harness; P4.3 inquiry scripts).
 */

let mode = "ok";
let inquiryScript = "bound_success";
let inquiryAmountCents = "800";
let intentionOrderId = "9001";
let lastIntentionBody = null;

const DEFAULT_AMOUNT_CENTS = "800";
const DEFAULT_TXN_ID = "99001";
const DEFAULT_ORDER_ID = "9001";
const UNBOUND_ORDER_ID = "99999";

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function transactionPayload(orderId, overrides = {}) {
  return {
    id: DEFAULT_TXN_ID,
    success: true,
    pending: false,
    is_refunded: false,
    is_voided: false,
    has_parent_transaction: false,
    amount_cents: inquiryAmountCents,
    currency: "EGP",
    order: { id: orderId },
    ...overrides,
  };
}

function inquiryOrderBody(orderId) {
  return {
    id: orderId,
    amount_cents: inquiryAmountCents,
    currency: "EGP",
  };
}

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/__script" && request.method === "POST") {
      const body = await request.json();
      if (body.mode === "ok" || body.mode === "refuse" || body.mode === "timeout") {
        mode = body.mode;
      }
      if (typeof body.inquiry === "string" && body.inquiry.length > 0) {
        inquiryScript = body.inquiry;
      }
      if (body.amount_cents !== undefined && body.amount_cents !== null) {
        inquiryAmountCents = String(body.amount_cents);
      }
      if (
        body.intention_order_id !== undefined &&
        body.intention_order_id !== null
      ) {
        intentionOrderId = String(body.intention_order_id);
      }
      return new Response(null, { status: 204 });
    }

    if (url.pathname === "/__last" && request.method === "GET") {
      return jsonResponse(lastIntentionBody ?? {});
    }

    if (url.pathname === "/api/auth/tokens" && request.method === "POST") {
      return jsonResponse({ token: "stub-token" });
    }

    if (
      (url.pathname === "/v1/intention/" || url.pathname === "/v1/intention") &&
      request.method === "POST"
    ) {
      const body = await request.json();
      lastIntentionBody = body;

      if (mode === "refuse") {
        return jsonResponse({ message: "refused" }, 500);
      }

      if (mode === "timeout") {
        return new Promise(() => {
          // Intentionally never settles so the client abort fires.
        });
      }

      return jsonResponse({
        id: "intention-stub-id",
        intention_order_id: Number(intentionOrderId),
        client_secret: "stub-client-secret",
      });
    }

    if (
      url.pathname === "/api/ecommerce/orders/transaction_inquiry" &&
      request.method === "POST"
    ) {
      if (inquiryScript === "timeout") {
        return new Promise(() => {});
      }
      if (inquiryScript === "rate_limit") {
        return new Response(null, { status: 429 });
      }

      let requestedOrderId = DEFAULT_ORDER_ID;
      try {
        const body = await request.json();
        if (body.order_id !== undefined && body.order_id !== null) {
          requestedOrderId = String(body.order_id);
        }
      } catch {
        // Use default order id.
      }

      if (inquiryScript === "unbound") {
        return jsonResponse(inquiryOrderBody(UNBOUND_ORDER_ID));
      }

      return jsonResponse(
        inquiryOrderBody(requestedOrderId || DEFAULT_ORDER_ID),
      );
    }

    const txnMatch = /^\/api\/acceptance\/transactions\/([^/]+)$/u.exec(
      url.pathname,
    );
    if (txnMatch !== null && request.method === "GET") {
      const txnId = txnMatch[1];

      if (inquiryScript === "timeout") {
        return new Promise(() => {});
      }
      if (inquiryScript === "rate_limit") {
        return new Response(null, { status: 429 });
      }

      if (inquiryScript === "unbound") {
        return jsonResponse(transactionPayload(UNBOUND_ORDER_ID, { id: txnId }));
      }
      if (inquiryScript === "amount_mismatch") {
        return jsonResponse(
          transactionPayload(DEFAULT_ORDER_ID, {
            id: txnId,
            amount_cents: "999999",
          }),
        );
      }
      if (inquiryScript === "reversed") {
        return jsonResponse(
          transactionPayload(DEFAULT_ORDER_ID, {
            id: txnId,
            is_refunded: true,
            refunded_amount_cents: DEFAULT_AMOUNT_CENTS,
          }),
        );
      }
      if (inquiryScript === "partial_refund") {
        return jsonResponse(
          transactionPayload(DEFAULT_ORDER_ID, {
            id: txnId,
            is_refunded: true,
            refunded_amount_cents: "400",
          }),
        );
      }
      if (inquiryScript === "pending") {
        return jsonResponse(
          transactionPayload(DEFAULT_ORDER_ID, {
            id: txnId,
            success: false,
            pending: true,
          }),
        );
      }

      if (txnId === "99002") {
        return jsonResponse(
          transactionPayload(DEFAULT_ORDER_ID, {
            id: txnId,
            success: false,
          }),
        );
      }

      if (txnId === "99004") {
        return jsonResponse(
          transactionPayload(DEFAULT_ORDER_ID, {
            id: txnId,
            has_parent_transaction: true,
            parent_transaction: { id: 99003 },
          }),
        );
      }

      return jsonResponse(transactionPayload(DEFAULT_ORDER_ID, { id: txnId }));
    }

    return new Response("not found", { status: 404 });
  },
};
