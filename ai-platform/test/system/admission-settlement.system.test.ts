/**
 * P3.4 — Admission and settlement against terms (H-AP, E2E-P3.4-01–12).
 */

import { env, runInDurableObject } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_ID,
  count,
  fakePolicyDocument,
  flushBackgroundWork,
  getAiRequest,
  getCapabilities,
  getUsageEvents,
  invoke,
  mintAat,
  newClinic,
  newScenario,
  POLICY_ID,
  POLICY_VERSION,
  promote,
  publishPolicy,
  queryOne,
  registerVisitSummaryCapability,
  resetPlatformState,
  setupVendorHarness,
  terminalEventTypes,
  type Scenario,
} from "./harness";

const QUOTA_WEIGHT = 1;

function quotaDoStub(installationId: string) {
  return env.DO.get(env.DO.idFromName(installationId));
}

function sqlSelect<T extends Record<string, unknown>>(
  state: DurableObjectState,
  query: string,
): T[] {
  const storage = state.storage as DurableObjectStorage & {
    sql?: { exec: (q: string) => Iterable<T> };
  };
  if (!storage.sql) {
    return [];
  }
  return [...storage.sql.exec(query)];
}

async function readHotUsed(installationId: string): Promise<number> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ used: number }>(state, "SELECT used FROM hot LIMIT 1"),
  );
  return rows[0]?.used ?? 0;
}

async function readActiveTermId(installationId: string): Promise<string | null> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ term_id: string }>(
        state,
        "SELECT term_id FROM term WHERE state = 'active' LIMIT 1",
      ),
  );
  return rows[0]?.term_id ?? null;
}

type CoverClinicOptions = {
  capabilities?: string[];
  concurrency_limit?: number;
  max_allowance_per_month?: number;
};

/** Paid-grant helper; real export lands in harness.ts at T013 (FR-014). */
async function coverClinic(
  scenario: Scenario,
  opts?: CoverClinicOptions,
): Promise<void> {
  const harnessModule = await import("./harness");
  const fn = (
    harnessModule as {
      coverClinic?: (s: Scenario, o?: CoverClinicOptions) => Promise<void>;
    }
  ).coverClinic;
  expect(fn).toBeTypeOf("function");
  await fn!(scenario, opts);
}

async function setupPromotedPolicy(scenario: Scenario): Promise<string> {
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  expect(published.status).toBe(200);
  const promoted = await promote(POLICY_ID, POLICY_VERSION);
  expect(promoted.status).toBe(200);
  return await mintAat(scenario);
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
  await setupVendorHarness();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
  await setupVendorHarness();
});

describe("admission settlement against terms", () => {
  it("E2E-P3.4-01 CP-B paid grant then issuer token lists the plan and completes a request charged to the term", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const token = await mintAat(scenario);

    const mirror = await queryOne<Record<string, unknown>>(
      "SELECT * FROM coverage_mirror WHERE installation_id = ?",
      [scenario.installationId],
    );
    expect(mirror).toBeTruthy();
    const termSnapshot = JSON.parse(String(mirror!.term_snapshot)) as {
      capabilities?: string[];
    };
    expect(termSnapshot.capabilities).toContain(CAPABILITY_ID);

    const caps = await getCapabilities(token);
    expect(caps.status).toBe(200);
    const manifests = caps.body?.manifests as Array<{
      Identity?: { capabilityId?: string };
    }>;
    expect(manifests?.map((m) => m.Identity?.capabilityId)).toContain(
      CAPABILITY_ID,
    );

    const activeTermId = await readActiveTermId(scenario.installationId);
    expect(activeTermId).toBeTruthy();

    const usedBefore = await readHotUsed(scenario.installationId);

    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    expect(published.status).toBe(200);
    const promoted = await promote(POLICY_ID, POLICY_VERSION);
    expect(promoted.status).toBe(200);

    const invoked = await invoke(scenario, { token });
    expect(invoked.status).toBe(200);
    expect(terminalEventTypes(invoked.events)).toEqual(["completed"]);
    await flushBackgroundWork();

    const ref = String(invoked.events[0]?.data.request_reference);
    const request = await getAiRequest(ref);
    expect(request?.request_id).toBeTruthy();

    const usage = await getUsageEvents(String(request?.request_id));
    expect(usage).toHaveLength(1);
    expect(usage[0]?.term_id).toBe(activeTermId);

    const usedAfter = await readHotUsed(scenario.installationId);
    expect(usedAfter).toBe(usedBefore + QUOTA_WEIGHT);
  });

  it("E2E-P3.4-02 An org that was never granted is coverage_lapsed and writes no journal row", async () => {
    const scenario = await newScenario();
    await newClinic(scenario);
    const token = await mintAat(scenario);

    const aiRequestsBefore = await count(
      "ai_request",
      "installation_id = ?",
      [scenario.installationId],
    );
    const usageBefore = await count(
      "usage_event",
      "installation_id = ?",
      [scenario.installationId],
    );

    const denied = await invoke(scenario, { token });
    expect(denied.status).toBe(403);
    expect(denied.body?.code).toBe("coverage_lapsed");
    expect(denied.body?.coverage_reason).toBe("none");

    const aiRequestsAfter = await count(
      "ai_request",
      "installation_id = ?",
      [scenario.installationId],
    );
    const usageAfter = await count(
      "usage_event",
      "installation_id = ?",
      [scenario.installationId],
    );
    expect(aiRequestsAfter).toBe(aiRequestsBefore);
    expect(usageAfter).toBe(usageBefore);
  });

  it("E2E-P3.4-03 A capability outside the plan snapshot is forbidden_capability", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario, { capabilities: [] });
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

    const denied = await invoke(scenario, { token });
    expect(denied.status).toBe(403);
    expect(denied.body?.code).toBe("forbidden_capability");
  });

  it("E2E-P3.4-04 The 17th in-flight request is concurrency_limited", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario, { concurrency_limit: 16 });
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

    const fakeMod = await import("../../src/provider/fake");
    const invokeSpy = vi.spyOn(fakeMod, "FakeAdapter").mockImplementation(
      () =>
        ({
          async invoke(
            _request: unknown,
            options?: { signal?: AbortSignal },
          ) {
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
                finalContent: { type: "text" as const, text: "held" },
                usage: { input: 1, output: 1, cached: 0 },
                providerModel: { provider: "fake", model: "fake-v1" },
                finishReason: "stop" as const,
                providerRequestId: "concurrency-hold",
                timing: { queue_ms: 0, provider_ms: 1, total_ms: 1 },
              },
              chunks: [],
            };
          },
        }) as never,
    );

    const controllers = Array.from({ length: 17 }, () => new AbortController());
    try {
      const results = await Promise.all(
        controllers.map((controller) =>
          invoke(scenario, {
            token,
            idempotencyKey: crypto.randomUUID(),
            signal: controller.signal,
          }),
        ),
      );

      const limited = results.filter(
        (result) => result.body?.code === "concurrency_limited",
      );
      expect(limited).toHaveLength(1);
      expect(limited[0]?.status).toBe(429);
      expect(limited[0]?.body?.retry_after).toBeTruthy();
      expect(limited[0]?.body?.code).not.toBe("rate_limited");
    } finally {
      for (const controller of controllers) {
        controller.abort();
      }
      invokeSpy.mockRestore();
    }
  });
});
