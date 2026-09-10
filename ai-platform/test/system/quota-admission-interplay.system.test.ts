/**
 * Suite 5 — quota admission interplay (plan §4, SYS-5.1–SYS-5.8).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clearConfigCache,
  count,
  enrollScenario,
  entitleScenario,
  fakePolicyDocument,
  fakePolicyTarget,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  getAiRequest,
  getAttempts,
  getR2Json,
  getUsageEvents,
  invoke,
  mintAat,
  newScenario,
  POLICY_ID,
  publishPolicy,
  promote,
  registerVisitSummaryCapability,
  resetPlatformState,
  setupPromotedFakePolicy,
  terminalEventTypes,
  visitSummaryInvokeBody,
  type EntitlePayload,
} from "./harness";

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
});

function assertSseOrder(events: { event: string }[]): void {
  expect(events[0]?.event).toBe("accepted");
  const terminals = terminalEventTypes(events);
  expect(terminals).toHaveLength(1);
  const terminalIndex = events.findIndex((event) =>
    ["completed", "failed", "cancelled", "context_requested"].includes(
      event.event,
    ),
  );
  expect(events.slice(terminalIndex + 1)).toHaveLength(0);
}

function quotaEntitlePayload(overrides: Partial<EntitlePayload> = {}): EntitlePayload {
  return {
    period_start: "2026-08-01T00:00:00.000Z",
    period_end: "2026-09-01T00:00:00.000Z",
    request_quota: 2,
    token_budget: 500_000,
    cost_budget: 50.0,
    soft_threshold: 0.5,
    allowed_capabilities: [CAPABILITY_ID],
    grants: [
      {
        capability_id: CAPABILITY_ID,
        capability_version: CAPABILITY_VERSION,
        scope: "installation",
      },
      {
        capability_id: CAPABILITY_ID,
        capability_version: CAPABILITY_VERSION,
        scope: "plan",
      },
    ],
    ...overrides,
  };
}

async function setupQuotaScenario(
  payload: EntitlePayload = quotaEntitlePayload(),
): Promise<Awaited<ReturnType<typeof newScenario>>> {
  const scenario = await newScenario();
  await setupPromotedFakePolicy(scenario, payload);
  return scenario;
}

function degradedTierPolicyDocument(version: string): Record<string, unknown> {
  return fakePolicyDocument(POLICY_ID, version, {
    canaryRules: [
      {
        rule_id: "standard-tier",
        match: { tiers: ["standard"] },
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: [],
        },
        targets: [
          fakePolicyTarget("bogus-standard", { providerId: "bogus-standard" }),
        ],
      },
      {
        rule_id: "degraded-tier",
        match: { tiers: ["degraded"] },
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: [],
        },
        targets: [fakePolicyTarget("fake-v1")],
      },
      {
        rule_id: "catch-all",
        match: {},
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: ["en"],
        },
        targets: [fakePolicyTarget("fake-v1")],
      },
    ],
  });
}

describe("quota admission interplay", () => {
  it("SYS-5.1 — Request-quota exhaustion", async () => {
    const scenario = await setupQuotaScenario(
      quotaEntitlePayload({ request_quota: 2 }),
    );

    const first = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(first.status).toBe(200);
    assertSseOrder(first.events);

    const second = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(second.status).toBe(200);
    assertSseOrder(second.events);

    expect(await count("ai_request")).toBe(2);

    const third = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(third.status).toBe(429);
    expect(third.body?.code).toBe("quota_exhausted");
    expect(third.body?.retry_safe).toBe(true);
    expect(third.body).not.toHaveProperty("retry_after");
    expect(third.body?.period_reset).toBe("2026-09-01T00:00:00.000Z");
    expect(await count("ai_request")).toBe(2);
  });

  it("SYS-5.2 — Soft-threshold degraded tier", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    // G2: degraded is driven by the credit ratio (creditsUsed / credit_budget).
    // credit_budget 2 + one settled credit (quotaWeight 1) crosses the 0.5
    // threshold while leaving budget for the second admission.
    await entitleScenario(
      scenario,
      quotaEntitlePayload({ request_quota: 2, credit_budget: 2 }),
    );

    const policyDocument = degradedTierPolicyDocument("50");
    await publishPolicy(POLICY_ID, "50", policyDocument);
    await promote(POLICY_ID, "50");

    const first = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(first.status).toBe(200);
    expect(first.events[0]?.data.degraded_notice).toBeUndefined();
    const firstRef = String(first.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const firstRequest = await getAiRequest(firstRef);
    expect(firstRequest?.routing_tier).toBe("standard");
    const firstDecision = JSON.parse(
      String(firstRequest?.routing_decision),
    ) as { rule_id?: string; routing_tier?: string };
    expect(firstDecision.rule_id).toBe("standard-tier");
    expect(firstDecision.routing_tier).toBe("standard");

    const second = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(second.status).toBe(200);
    expect(second.events[0]?.data.degraded_notice).toBe(true);
    const secondRef = String(second.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const secondRequest = await getAiRequest(secondRef);
    expect(secondRequest?.routing_tier).toBe("degraded");
    const secondDecision = JSON.parse(
      String(secondRequest?.routing_decision),
    ) as { rule_id?: string; routing_tier?: string };
    expect(secondDecision.rule_id).toBe("degraded-tier");
    expect(secondDecision.routing_tier).toBe("degraded");

    // Raise the credit budget too: two settled credits (2 >= 2) would
    // otherwise exhaust G2 credit remaining-budget before this third invoke.
    await env.DB.prepare(
      "UPDATE entitlement SET soft_threshold = 0, request_quota = 100, credit_budget = 100 WHERE installation_id = ?",
    )
      .bind(scenario.installationId)
      .run();
    clearConfigCache();

    const third = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(third.status).toBe(200);
    expect(third.events[0]?.data.degraded_notice).toBeUndefined();
    const thirdRef = String(third.events[0]?.data.request_reference);
    await flushBackgroundWork();
    expect((await getAiRequest(thirdRef))?.routing_tier).toBe("standard");
  });

  it("SYS-5.3 — Client cannot inject tier", async () => {
    const scenario = await setupQuotaScenario();

    const invoked = await invoke(scenario, {
      body: visitSummaryInvokeBody(scenario, {
        routing_tier: "degraded",
        degraded: true,
        degraded_notice: true,
      }),
    });
    expect(invoked.status).toBe(200);
    expect(invoked.events[0]?.data.degraded_notice).toBeUndefined();

    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const request = await getAiRequest(ref);
    expect(request?.routing_tier).toBe("standard");
    const decision = JSON.parse(String(request?.routing_decision)) as {
      routing_tier?: string;
    };
    expect(decision.routing_tier).toBe("standard");
  });

  it("SYS-5.4 — JTI replay", async () => {
    const scenario = await setupQuotaScenario();
    const token = await mintAat(scenario);
    const beforeCount = await count("ai_request");

    const first = await invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(first.status).toBe(200);

    const replay = await invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(replay.status).toBe(401);
    expect(replay.body?.code).toBe("unauthenticated");
    expect(await count("ai_request")).toBe(beforeCount + 1);
  });

  it("SYS-5.5 — Idempotent replay of completed", async () => {
    const scenario = await setupQuotaScenario();
    const idempotencyKey = crypto.randomUUID();

    const first = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey,
    });
    expect(first.status).toBe(200);
    assertSseOrder(first.events);
    const ref = String(first.events[0]?.data.request_reference);
    await flushBackgroundWork();

    const requestBefore = await getAiRequest(ref);
    const attemptsBefore = await getAttempts(String(requestBefore?.request_id));
    const usageBefore = await getUsageEvents(String(requestBefore?.request_id));
    const pointerBefore = String(requestBefore?.payload_pointer);
    const envelopeBefore = await getR2Json(pointerBefore);
    const routingBefore = requestBefore?.routing_decision;

    const replay = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey,
    });
    expect(replay.status).toBe(200);
    expect(replay.events[0]?.event).toBe("accepted");
    expect(replay.events[1]?.event).toBe("completed");
    const completed = replay.events[1]?.data.result as {
      finalContent?: { text?: string; authoritative?: boolean };
    };
    expect(completed?.finalContent?.text).toBe("Prior request completed.");
    expect(completed?.finalContent?.authoritative).toBe(true);
    expect(replay.events.some((event) => event.event === "text_delta")).toBe(false);

    expect(await count("ai_request")).toBe(1);
    expect(await getAttempts(String(requestBefore?.request_id))).toHaveLength(
      attemptsBefore.length,
    );
    expect(await getUsageEvents(String(requestBefore?.request_id))).toHaveLength(
      usageBefore.length,
    );

    const requestAfter = await getAiRequest(ref);
    expect(requestAfter?.routing_decision).toBe(routingBefore);
    expect(requestAfter?.payload_pointer).toBe(pointerBefore);
    const envelopeAfter = await getR2Json(pointerBefore);
    expect(envelopeAfter).toEqual(envelopeBefore);
  });

  it("SYS-5.6 — Replay of failed and cancelled", async () => {
    const failedScenario = await newScenario();
    await enrollScenario(failedScenario);
    await entitleScenario(failedScenario);

    const emptyChainDocument = fakePolicyDocument(POLICY_ID, "60", {
      targets: [fakePolicyTarget("fake-v1", { minContextWindow: 1_000 })],
    });
    await publishPolicy(POLICY_ID, "60", emptyChainDocument);
    await promote(POLICY_ID, "60");

    const failedKey = crypto.randomUUID();
    const failed = await invoke(failedScenario, {
      token: await mintAat(failedScenario),
      idempotencyKey: failedKey,
    });
    expect(failed.events[1]?.event).toBe("failed");
    expect(failed.events[1]?.data.code).toBe("provider_unavailable");
    await flushBackgroundWork();
    const failedAttemptsBefore = await count("ai_attempt");

    const failedReplay = await invoke(failedScenario, {
      token: await mintAat(failedScenario),
      idempotencyKey: failedKey,
    });
    expect(failedReplay.events[1]?.event).toBe("failed");
    expect(failedReplay.events[1]?.data.code).toBe("provider_unavailable");
    expect(await count("ai_attempt")).toBe(failedAttemptsBefore);

    const cancelledScenario = await newScenario();
    await enrollScenario(cancelledScenario);
    await entitleScenario(
      cancelledScenario,
      quotaEntitlePayload({ request_quota: 100 }),
    );
    const cancelledPolicy = fakePolicyDocument(POLICY_ID, "61", {
      targets: [
        {
          ...fakePolicyTarget("bogus-v1", { providerId: "bogus-primary" }),
          // Enough retry attempts that the invocation is still inside
          // backoff when the client abort lands below: the loop-top
          // callerSignal check then journals Cancelled instead of losing
          // the race to a terminal provider_unavailable (Failed).
          max_attempts: 5,
        },
      ],
    });
    await publishPolicy(POLICY_ID, "61", cancelledPolicy);
    await promote(POLICY_ID, "61");
    clearConfigCache();

    const cancelledKey = crypto.randomUUID();
    const cancelledToken = await mintAat(cancelledScenario);
    const controller = new AbortController();
    const cancelFetch = SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${cancelledToken}`,
          "content-type": "application/json",
          "x-idempotency-key": cancelledKey,
          "x-capability-version": CAPABILITY_VERSION,
        },
        body: JSON.stringify(visitSummaryInvokeBody(cancelledScenario)),
        signal: controller.signal,
      }),
    );

    let acceptedInJournal = false;
    for (let attempt = 0; attempt < 200; attempt += 1) {
      const row = await env.DB.prepare(
        `SELECT state FROM ai_request
         WHERE installation_id = ? AND idempotency_key = ?`,
      )
        .bind(cancelledScenario.installationId, cancelledKey)
        .first<{ state: string }>();
      if (row?.state === "Accepted") {
        acceptedInJournal = true;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 5));
    }
    expect(acceptedInJournal).toBe(true);
    controller.abort();
    await cancelFetch.catch(() => undefined);

    // Wait for a stably terminal journal row (same robustness pattern as the
    // e2e waitForCancelledJournal helper) instead of a fixed sleep: under
    // full-pool load the cancel settlement can lag the client abort.
    let cancelledRow: { state: string; idempotency_key: string } | null = null;
    for (let attempt = 0; attempt < 80; attempt += 1) {
      await flushBackgroundWork();
      cancelledRow = await env.DB.prepare(
        `SELECT state, idempotency_key FROM ai_request
         WHERE installation_id = ? AND idempotency_key = ?`,
      )
        .bind(cancelledScenario.installationId, cancelledKey)
        .first<{ state: string; idempotency_key: string }>();
      if (cancelledRow != null && cancelledRow.state !== "Accepted") {
        break;
      }
    }
    expect(cancelledRow?.idempotency_key).toBe(cancelledKey);
    expect(cancelledRow?.state).toBe("Cancelled");

    const cancelledReplay = await invoke(cancelledScenario, {
      token: await mintAat(cancelledScenario),
      idempotencyKey: cancelledKey,
    });
    expect(cancelledReplay.events[0]?.event).toBe("accepted");
    expect(cancelledReplay.events[1]?.event).toBe("cancelled");
    expect(cancelledReplay.events[1]?.data.code).toBeUndefined();
  });

  it("SYS-5.7 — Token & cost ceilings", async () => {
    // G2: token/cost counters are settlement-only; remaining-budget exhaustion
    // is request-quota or credit-budget. Seed the credit ceiling so the same
    // 429 quota_exhausted wire behaviour is asserted.
    const tokenScenario = await setupQuotaScenario(
      quotaEntitlePayload({ request_quota: 100, credit_budget: 1 }),
    );
    const tokenFirst = await invoke(tokenScenario, {
      token: await mintAat(tokenScenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(tokenFirst.status).toBe(200);
    await flushBackgroundWork();

    const tokenSecond = await invoke(tokenScenario, {
      token: await mintAat(tokenScenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(tokenSecond.status).toBe(429);
    expect(tokenSecond.body?.code).toBe("quota_exhausted");
    expect(tokenSecond.body).not.toHaveProperty("retry_after");

    const costScenario = await newScenario();
    await enrollScenario(costScenario);
    await entitleScenario(
      costScenario,
      quotaEntitlePayload({ request_quota: 100, credit_budget: 0 }),
    );
    const costPolicy = fakePolicyDocument(POLICY_ID, "70");
    await publishPolicy(POLICY_ID, "70", costPolicy);
    await promote(POLICY_ID, "70");
    clearConfigCache();

    const costRefused = await invoke(costScenario, {
      token: await mintAat(costScenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(costRefused.status).toBe(429);
    expect(costRefused.body?.code).toBe("quota_exhausted");
    expect(costRefused.body).not.toHaveProperty("retry_after");
  });

  it("SYS-5.8 — Period rollover", async () => {
    const scenario = await setupQuotaScenario(
      quotaEntitlePayload({ request_quota: 2 }),
    );

    await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: crypto.randomUUID(),
    });
    await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: crypto.randomUUID(),
    });
    await flushBackgroundWork();

    const exhausted = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(exhausted.status).toBe(429);
    expect(exhausted.body?.code).toBe("quota_exhausted");

    await env.DB.prepare(
      `UPDATE entitlement
       SET period_start = '2026-09-01T00:00:00.000Z',
           period_end = '2026-10-01T00:00:00.000Z',
           request_quota = 100,
           token_budget = 500000,
           cost_budget = 50.0,
           soft_threshold = 0.5
       WHERE installation_id = ?`,
    )
      .bind(scenario.installationId)
      .run();
    clearConfigCache();

    const afterRollover = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey: crypto.randomUUID(),
    });
    expect(afterRollover.status).toBe(200);
    assertSseOrder(afterRollover.events);

    const ref = String(afterRollover.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const request = await getAiRequest(ref);
    const usage = await getUsageEvents(String(request?.request_id));
    expect(usage).toHaveLength(1);
    expect(usage[0]?.period).toBe("2026-09");
  });
});
