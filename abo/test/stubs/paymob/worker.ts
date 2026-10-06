/**
 * H-PAY stub (P4.2 cross-worker harness).
 */

let mode = "ok";
let lastIntentionBody = null;

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/__script" && request.method === "POST") {
      const body = await request.json();
      if (body.mode === "ok" || body.mode === "refuse" || body.mode === "timeout") {
        mode = body.mode;
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
        intention_order_id: 9001,
        client_secret: "stub-client-secret",
      });
    }

    return new Response("not found", { status: 404 });
  },
};
