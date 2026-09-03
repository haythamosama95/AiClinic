/**
 * Suite 7 — settlement integrity (plan §4, SYS-7.1–SYS-7.5).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  count,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollScenario,
  entitleScenario,
  fakePolicyDocument,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  getAiRequest,
  getAttempts,
  getRequest,
  getR2Json,
  invoke,
  mintAat,
  newScenario,
  operatorFetchRaw,
  POLICY_ID,
  POLICY_VERSION,
  publishPolicy,
  promote,
  registerVisitSummaryCapability,
  resetPlatformState,
  r2Exists,
  setupPromotedFakePolicy,
  visitSummaryInvokeBody,
  type Scenario,
} from "./harness";

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
});

function periodFromEntitleStart(periodStart: string): string {
  return periodStart.slice(0, 7);
}

async function completeRequest(scenario: Scenario): Promise<{
  ref: string;
  requestId: string;
  idempotencyKey: string;
}> {
  const idempotencyKey = crypto.randomUUID();
  const invoked = await invoke(scenario, { idempotencyKey });
  expect(invoked.status).toBe(200);
  const ref = String(invoked.events[0]?.data.request_reference);
  await flushBackgroundWork();
  const request = await getAiRequest(ref);
  return {
    ref,
    requestId: String(request?.request_id),
    idempotencyKey,
  };
}

async function failWithEmptyChain(scenario: Scenario): Promise<{
  ref: string;
  requestId: string;
  idempotencyKey: string;
}> {
  const document = fakePolicyDocument(POLICY_ID, "2", {
    ruleId: "all-excluded",
    overrides: [
      {
        installation_id: scenario.installationId,
        exclude_providers: ["fake"],
      },
    ],
  });
  await publishPolicy(POLICY_ID, "2", document);
  await promote(POLICY_ID, "2");

  const idempotencyKey = crypto.randomUUID();
  const invoked = await invoke(scenario, { idempotencyKey });
  expect(invoked.status).toBe(200);
  expect(invoked.events.find((event) => event.event === "failed")).toBeTruthy();
  const ref = String(invoked.events[0]?.data.request_reference);
  await flushBackgroundWork();
  const request = await getAiRequest(ref);
  return {
    ref,
    requestId: String(request?.request_id),
    idempotencyKey,
  };
}

describe("settlement integrity", () => {
  it("SYS-7.1 — Completed settlement columns and envelope", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const { ref, requestId } = await completeRequest(scenario);

    const request = await getAiRequest(ref);
    expect(request?.state).toBe("Completed");
    expect(request?.terminal_error_code).toBeNull();
    expect(request?.payload_pointer).toBe(`request/${requestId}/envelope`);
    expect(String(request?.payload_pointer)).not.toMatch(/\.json$/);

    const attempts = await getAttempts(requestId);
    expect(attempts).toHaveLength(1);
    const attempt = attempts[0]!;
    expect(attempt.attempt_no).toBe(1);
    expect(attempt.provider).toBe("fake");
    expect(attempt.outcome).toBe("success");
    expect(Number(attempt.latency_ms)).toBeGreaterThanOrEqual(0);
    expect(attempt.error_code).toBeNull();

    const usage = await env.DB.prepare(
      "SELECT * FROM usage_event WHERE request_id = ?",
    )
      .bind(requestId)
      .all<Record<string, unknown>>();
    expect(usage.results).toHaveLength(1);
    const usageRow = usage.results![0]!;
    expect(usageRow.installation_id).toBe(scenario.installationId);
    expect(usageRow.period).toBe(
      periodFromEntitleStart(DEFAULT_ENTITLE_PAYLOAD.period_start),
    );
    expect(usageRow.quota_weight).toBe(1);
    expect(usageRow.tokens).toBe(
      Number(attempt.tokens_in) + Number(attempt.tokens_out),
    );
    expect(usageRow.cost).toBe(attempt.cost);

    const envelope = await getR2Json(`request/${requestId}/envelope`);
    const result = envelope.result as {
      usage?: { input?: number; output?: number };
      finishReason?: string;
    };
    expect(result.usage).toBeTruthy();
    expect(result.finishReason).toBe("stop");
  });

  it("SYS-7.2 — Failed settlement empty chain", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const { ref, requestId } = await failWithEmptyChain(scenario);
    const token = await mintAat(scenario);

    const request = await getAiRequest(ref);
    expect(request?.state).toBe("Failed");
    expect(request?.terminal_error_code).toBe("provider_unavailable");

    const attempts = await getAttempts(requestId);
    expect(attempts.length).toBeGreaterThanOrEqual(1);
    const failureAttempt = attempts.find(
      (row) => row.outcome === "terminal_failure",
    );
    expect(failureAttempt).toBeTruthy();
    expect(Number(failureAttempt?.tokens_in)).toBe(0);
    expect(Number(failureAttempt?.tokens_out)).toBe(0);
    expect(Number(failureAttempt?.cost)).toBe(0);
    expect(failureAttempt?.error_code).toBe("provider_unavailable");

    const usageCount = await count("usage_event", "request_id = ?", [requestId]);
    expect(usageCount).toBe(1);

    const envelope = await getR2Json(`request/${requestId}/envelope`);
    const attemptsEnvelope = envelope.attempts as Array<{
      payload?: { reason?: string };
    }>;
    expect(attemptsEnvelope[0]?.payload?.reason).toBe("no_provider_attempt");

    const clientGet = await getRequest(token, ref);
    expect(clientGet.status).toBe(200);
    expect(clientGet.body?.state).toBe("Failed");
    expect(clientGet.body?.terminal_error_code).toBe("provider_unavailable");
  });

  it("SYS-7.3 — Cancelled settlement after accepted", async () => {
    const fakeMod = await import("../../src/provider/fake");
    let invokeEntered = false;
    const invokeSpy = vi.spyOn(fakeMod, "FakeAdapter").mockImplementation(
      () =>
        ({
          async invoke(
            _request: unknown,
            options?: { signal?: AbortSignal },
          ) {
            invokeEntered = true;
            const signal = options?.signal;
            await new Promise<void>((resolve, reject) => {
              if (signal?.aborted) {
                reject(
                  new DOMException("The operation was aborted.", "AbortError"),
                );
                return;
              }
              const timer = setTimeout(() => resolve(), 5_000);
              signal?.addEventListener(
                "abort",
                () => {
                  clearTimeout(timer);
                  reject(
                    new DOMException(
                      "The operation was aborted.",
                      "AbortError",
                    ),
                  );
                },
                { once: true },
              );
            });
            return {
              kind: "success" as const,
              result: {
                finalContent: { type: "text" as const, text: "never" },
                usage: { input: 1, output: 1, cached: 0 },
                providerModel: { provider: "fake", model: "fake-v1" },
                finishReason: "stop" as const,
                providerRequestId: "cancel",
                timing: { queue_ms: 0, provider_ms: 1, total_ms: 1 },
              },
              chunks: [],
            };
          },
        }) as never,
    );

    try {
      const scenario = await newScenario();
      await setupPromotedFakePolicy(scenario);
      const controller = new AbortController();
      const token = await mintAat(scenario);
      const fetchPromise = SELF.fetch(
        new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
          method: "POST",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
            "x-idempotency-key": crypto.randomUUID(),
            "x-capability-version": CAPABILITY_VERSION,
          },
          body: JSON.stringify(visitSummaryInvokeBody(scenario)),
          signal: controller.signal,
        }),
      );
      for (let i = 0; i < 40 && !invokeEntered; i += 1) {
        await new Promise((resolve) => setTimeout(resolve, 25));
      }
      controller.abort();
      try {
        await fetchPromise;
      } catch {
        // Client abort may reject the fetch.
      }
      await flushBackgroundWork();
      await new Promise((resolve) => setTimeout(resolve, 200));

      const request = await env.DB.prepare(
        "SELECT request_id, request_reference, state, completed_at, terminal_error_code, payload_pointer FROM ai_request WHERE installation_id = ? ORDER BY created_at DESC LIMIT 1",
      )
        .bind(scenario.installationId)
        .first<{
          request_id: string;
          request_reference: string;
          state: string;
          completed_at: string | null;
          terminal_error_code: string | null;
          payload_pointer: string | null;
        }>();
      expect(request?.state).toBe("Cancelled");
      expect(request?.completed_at).toBeTruthy();
      expect(request?.terminal_error_code).toBeNull();

      const usageCount = await count("usage_event", "request_id = ?", [
        request!.request_id,
      ]);
      expect(usageCount).toBe(1);
      expect(await r2Exists(String(request?.payload_pointer))).toBe(true);
    } finally {
      invokeSpy.mockRestore();
    }
  });

  it("SYS-7.4 — Exactly-once under replay", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);

    const completed = await completeRequest(scenario);
    const failed = await failWithEmptyChain(scenario);

    const fakeMod = await import("../../src/provider/fake");
    let invokeEntered = false;
    const invokeSpy = vi.spyOn(fakeMod, "FakeAdapter").mockImplementation(
      () =>
        ({
          async invoke(
            _request: unknown,
            options?: { signal?: AbortSignal },
          ) {
            invokeEntered = true;
            const signal = options?.signal;
            await new Promise<void>((resolve, reject) => {
              if (signal?.aborted) {
                reject(
                  new DOMException("The operation was aborted.", "AbortError"),
                );
                return;
              }
              const timer = setTimeout(() => resolve(), 5_000);
              signal?.addEventListener(
                "abort",
                () => {
                  clearTimeout(timer);
                  reject(
                    new DOMException(
                      "The operation was aborted.",
                      "AbortError",
                    ),
                  );
                },
                { once: true },
              );
            });
            return {
              kind: "success" as const,
              result: {
                finalContent: { type: "text" as const, text: "never" },
                usage: { input: 0, output: 0, cached: 0 },
                providerModel: { provider: "fake", model: "fake-v1" },
                finishReason: "stop" as const,
                providerRequestId: "cancel-replay",
                timing: { queue_ms: 0, provider_ms: 0, total_ms: 0 },
              },
              chunks: [],
            };
          },
        }) as never,
    );

    let cancelledKey = crypto.randomUUID();
    try {
      const controller = new AbortController();
      const token = await mintAat(scenario);
      const fetchPromise = SELF.fetch(
        new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
          method: "POST",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
            "x-idempotency-key": cancelledKey,
            "x-capability-version": CAPABILITY_VERSION,
          },
          body: JSON.stringify(visitSummaryInvokeBody(scenario)),
          signal: controller.signal,
        }),
      );
      for (let i = 0; i < 40 && !invokeEntered; i += 1) {
        await new Promise((resolve) => setTimeout(resolve, 25));
      }
      controller.abort();
      try {
        await fetchPromise;
      } catch {
        // Expected on abort.
      }
      await flushBackgroundWork();
      await new Promise((resolve) => setTimeout(resolve, 200));

      const cancelledRow = await env.DB.prepare(
        "SELECT request_id, request_reference FROM ai_request WHERE idempotency_key = ?",
      )
        .bind(cancelledKey)
        .first<{ request_id: string; request_reference: string }>();
      expect(cancelledRow?.request_id).toBeTruthy();

      const terminals: Array<{
        label: string;
        ref: string;
        requestId: string;
        idempotencyKey: string;
      }> = [
        {
          label: "completed",
          ref: completed.ref,
          requestId: completed.requestId,
          idempotencyKey: completed.idempotencyKey,
        },
        {
          label: "failed",
          ref: failed.ref,
          requestId: failed.requestId,
          idempotencyKey: failed.idempotencyKey,
        },
        {
          label: "cancelled",
          ref: String(cancelledRow?.request_reference),
          requestId: String(cancelledRow?.request_id),
          idempotencyKey: cancelledKey,
        },
      ];

      for (const terminal of terminals) {
        const attemptsBefore = await count("ai_attempt", "request_id = ?", [
          terminal.requestId,
        ]);
        const usageBefore = await count("usage_event", "request_id = ?", [
          terminal.requestId,
        ]);
        const envelopeBefore = await r2Exists(
          `request/${terminal.requestId}/envelope`,
        );

        const replay = await invoke(scenario, {
          idempotencyKey: terminal.idempotencyKey,
        });
        expect(replay.status).toBe(200);

        expect(
          await count("ai_attempt", "request_id = ?", [terminal.requestId]),
        ).toBe(attemptsBefore);
        expect(
          await count("usage_event", "request_id = ?", [terminal.requestId]),
        ).toBe(usageBefore);
        expect(
          await r2Exists(`request/${terminal.requestId}/envelope`),
        ).toBe(envelopeBefore);
      }
    } finally {
      invokeSpy.mockRestore();
    }
  });

  it("SYS-7.5 — Client cannot read internals", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const { ref } = await completeRequest(scenario);
    const token = await mintAat(scenario);

    const other = await newScenario();
    await enrollScenario(other);
    await entitleScenario(other);
    const otherToken = await mintAat(other);

    const clientGet = await getRequest(token, ref);
    expect(clientGet.status).toBe(200);
    expect(clientGet.body).not.toHaveProperty("attempts");
    expect(clientGet.body).not.toHaveProperty("envelope");
    expect(clientGet.body).not.toHaveProperty("request_id");
    expect(clientGet.body).not.toHaveProperty("installation_id");

    const unauth = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/requests/${ref}`),
    );
    expect(unauth.status).toBe(401);

    const wrongInstallation = await getRequest(otherToken, ref);
    expect(wrongInstallation.status).toBe(404);
    expect(wrongInstallation.body).toBeNull();

    const listRoot = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/requests/`, {
        headers: { authorization: `Bearer ${token}` },
      }),
    );
    expect(listRoot.status).toBe(404);

    const lookup = await operatorFetchRaw(
      `/control/support/lookup?reference=${encodeURIComponent(ref)}`,
    );
    expect(lookup.status).toBe(200);
    const lookupBody = (await lookup.json()) as Record<string, unknown>;
    expect(lookupBody.request).toBeTruthy();
    expect(lookupBody.attempts).toBeTruthy();
    expect(lookupBody.envelope).toBeTruthy();
    expect(clientGet.body).not.toHaveProperty("attempts");
  });
});
