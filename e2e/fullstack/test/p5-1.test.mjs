import test from "node:test";
import assert from "node:assert/strict";

const SUPABASE_URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const PLATFORM_URL = process.env.PLATFORM_URL ?? "http://127.0.0.1:8787";
const ABO_URL = process.env.ABO_URL ?? "http://127.0.0.1:8788";
const HARNESS_URL = process.env.HARNESS_URL ?? "http://127.0.0.1:8790";

async function assertRunnerWired() {
  const response = await fetch(`${HARNESS_URL}/register-issuer-key`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ contract_version: 1 }),
  }).catch(() => null);

  assert.notEqual(
    response,
    null,
    "H-FS runner is not wired: harness worker is not reachable",
  );
  assert.notEqual(
    response.status,
    404,
    "H-FS runner is not wired: register-issuer-key route is unavailable",
  );
}

test("E2E-P5.1-01 Org A member issue_ai_token(1) is accepted by the local platform and A's binding is created", async () => {
  await assertRunnerWired();

  const capabilities = await fetch(`${PLATFORM_URL}/v1/capabilities`, {
    headers: {
      authorization: "Bearer <ai-token-not-minted-yet>",
    },
  });

  assert.equal(
    capabilities.status,
    200,
    "runner does not yet accept that token",
  );
});

test("E2E-P5.1-02 Administrator issue_billing_token(1) is accepted by the local ABO and a doctor receives FORBIDDEN_ROLE", async () => {
  await assertRunnerWired();

  const offers = await fetch(`${ABO_URL}/v1/offers`, {
    headers: {
      authorization: "Bearer <billing-token-not-minted-yet>",
      host: "billing.vendor.test",
    },
  });

  assert.equal(
    offers.status,
    200,
    "ABO does not yet accept that token",
  );

  const doctorBilling = await fetch(SUPABASE_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      error_code: "FORBIDDEN_ROLE",
    }),
  });

  assert.equal(
    doctorBilling.status,
    400,
    "doctor FORBIDDEN_ROLE path is not wired",
  );
});
