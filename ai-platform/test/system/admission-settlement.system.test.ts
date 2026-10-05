/**
 * P3.4 — Admission and settlement against terms (H-AP, E2E-P3.4-01–12).
 */

import { env, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
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
  queryAll,
  queryOne,
  registerVisitSummaryCapability,
  resetPlatformState,
  setTestClock,
  setupVendorHarness,
  terminalEventTypes,
  coverClinic,
  type Scenario,
} from "./harness";
import { addDuration } from "../../src/coverage/calendar";

const QUOTA_WEIGHT = 1;
const W_MAX = QUOTA_WEIGHT;

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

type DoTermRow = {
  term_id: string;
  state: string;
  starts_at: string | null;
  ends_at: string | null;
  allowance: number | null;
  used_final: number | null;
};

async function readDoTerms(installationId: string): Promise<DoTermRow[]> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect<DoTermRow>(
      state,
      "SELECT term_id, state, starts_at, ends_at, allowance, used_final FROM term",
    ),
  );
}

async function readHotUsage(
  installationId: string,
): Promise<{ used: number; reserved: number }> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ used: number; reserved: number }>(
        state,
        "SELECT used, reserved FROM hot LIMIT 1",
      ),
  );
  return { used: rows[0]?.used ?? 0, reserved: rows[0]?.reserved ?? 0 };
}

type CoverageEventRow = {
  kind: string;
  snapshot: string;
};

async function listBandCrossedEvents(orgId: string): Promise<
  Array<{ kind: string; band: string | undefined }>
> {
  const rows = await queryAll<CoverageEventRow>(
    "SELECT kind, snapshot FROM coverage_event WHERE org_id = ? AND kind = 'band_crossed' ORDER BY feed_seq ASC",
    [orgId],
  );
  return rows.map((row) => {
    const snapshot = JSON.parse(row.snapshot) as {
      term?: { band?: string };
    };
    return { kind: row.kind, band: snapshot.term?.band };
  });
}

async function completeChargedRequest(
  scenario: Scenario,
  token: string,
): Promise<void> {
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  expect(published.status).toBe(200);
  const promoted = await promote(POLICY_ID, POLICY_VERSION);
  expect(promoted.status).toBe(200);

  const invoked = await invoke(scenario, {
    token,
    idempotencyKey: crypto.randomUUID(),
  });
  expect(invoked.status).toBe(200);
  expect(terminalEventTypes(invoked.events)).toEqual(["completed"]);
  await flushBackgroundWork();
}

async function postUntilAllowanceConsumed(
  scenario: Scenario,
  token: string,
  allowance: number,
): Promise<void> {
  for (let attempt = 0; attempt < allowance + 2; attempt += 1) {
    const hot = await readHotUsage(scenario.installationId);
    if (hot.used + hot.reserved >= allowance) {
      return;
    }
    await completeChargedRequest(scenario, token);
  }
  throw new Error("allowance was not reached");
}

async function shipCoverageOutbox(installationId: string): Promise<void> {
  await runDurableObjectAlarm(quotaDoStub(installationId));
}

async function readHotReservations(
  installationId: string,
): Promise<Array<Record<string, unknown>>> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ reservations: string }>(
        state,
        "SELECT reservations FROM hot LIMIT 1",
      ),
  );
  const raw = rows[0]?.reservations;
  if (!raw) {
    return [];
  }
  return JSON.parse(raw) as Array<Record<string, unknown>>;
}

function wrapQuotaDoFetch(
  installationId: string,
  handler: (
    body: Record<string, unknown>,
    forward: (input: RequestInfo, init?: RequestInit) => Promise<Response>,
  ) => Promise<Response>,
): () => void {
  const stub = quotaDoStub(installationId);
  const original = stub.fetch.bind(stub);
  const spy = vi.spyOn(stub, "fetch").mockImplementation(async (input, init) => {
    const request =
      input instanceof Request ? input : new Request(input, init);
    const body = (await request.clone().json()) as Record<string, unknown>;
    return handler(body, (fwdInput, fwdInit) => original(fwdInput, fwdInit));
  });
  return () => {
    spy.mockRestore();
  };
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

  it("E2E-P3.4-05 Reaching the allowance with nothing queued exhausts the term", async () => {
    const allowance = 3;
    const scenario = await newScenario();
    await setTestClock("2026-04-01T12:00:00.000Z");
    await coverClinic(scenario, { max_allowance_per_month: allowance });
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

    await postUntilAllowanceConsumed(scenario, token, allowance);

    const terms = await readDoTerms(scenario.installationId);
    const exhausted = terms.filter((row) => row.state === "exhausted");
    expect(exhausted).toHaveLength(1);
    expect(terms.some((row) => row.state === "grace")).toBe(false);

    const denied = await invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(denied.status).toBe(403);
    expect(denied.body?.code).toBe("allowance_exhausted");
  });

  it("E2E-P3.4-06 Exhaustion activates the queued term at that instant", async () => {
    const allowance = 2;
    const scenario = await newScenario();
    const activationInstant = "2026-05-15T09:30:00.000Z";
    await setTestClock(activationInstant);
    await coverClinic(scenario, { max_allowance_per_month: allowance });
    await coverClinic(scenario, { max_allowance_per_month: allowance });
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

    const before = await readDoTerms(scenario.installationId);
    const queuedBefore = before.filter((row) => row.state === "queued");
    expect(queuedBefore).toHaveLength(1);

    await postUntilAllowanceConsumed(scenario, token, allowance);

    const after = await readDoTerms(scenario.installationId);
    const active = after.find((row) => row.state === "active");
    expect(active).toBeTruthy();
    expect(active?.allowance).toBe(allowance);
    expect(active?.starts_at).toBeTruthy();
    expect(active?.ends_at).toBe(
      addDuration(String(active?.starts_at), "month", 1),
    );

    const hot = await readHotUsage(scenario.installationId);
    expect(hot.used + hot.reserved).toBeLessThanOrEqual(allowance);
  });

  it("E2E-P3.4-07 Two concurrent requests near the allowance exhaust once", async () => {
    const allowance = 5;
    const scenario = await newScenario();
    await setTestClock("2026-06-01T08:00:00.000Z");
    await coverClinic(scenario, { max_allowance_per_month: allowance });
    await coverClinic(scenario, { max_allowance_per_month: allowance });
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

    for (let index = 0; index < allowance - 1; index += 1) {
      await completeChargedRequest(scenario, token);
    }

    const beforeHot = await readHotUsage(scenario.installationId);
    expect(beforeHot.used + beforeHot.reserved).toBe(allowance - 1);

    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    expect(published.status).toBe(200);
    const promoted = await promote(POLICY_ID, POLICY_VERSION);
    expect(promoted.status).toBe(200);

    const [first, second] = await Promise.all([
      invoke(scenario, {
        token,
        idempotencyKey: crypto.randomUUID(),
      }),
      invoke(scenario, {
        token,
        idempotencyKey: crypto.randomUUID(),
      }),
    ]);
    await flushBackgroundWork();

    const exhaustedTerms = (await readDoTerms(scenario.installationId)).filter(
      (row) => row.state === "exhausted",
    );
    expect(exhaustedTerms).toHaveLength(1);
    const exhaustedUsed =
      exhaustedTerms[0]?.used_final ?? (await readHotUsage(scenario.installationId)).used;
    expect(exhaustedUsed).toBeLessThanOrEqual(allowance + (W_MAX - 1));

    const termEndedCount = await count(
      "coverage_event",
      "org_id = ? AND kind = 'term_ended'",
      [scenario.orgId],
    );
    expect(termEndedCount).toBeGreaterThanOrEqual(1);

    const statuses = [first.status, second.status];
    expect(statuses.some((status) => status === 200)).toBe(true);
    const refused = [first, second].filter(
      (result) =>
        result.status === 403 &&
        (result.body?.code === "allowance_exhausted" ||
          result.body?.code === "coverage_lapsed"),
    );
    const successorCharge = [first, second].filter((result) => {
      if (result.status !== 200) {
        return false;
      }
      const ref = String(result.events[0]?.data.request_reference ?? "");
      return ref.length > 0;
    });
    expect(refused.length + successorCharge.length).toBeGreaterThanOrEqual(1);
  });

  it("E2E-P3.4-08 Crossing 75 percent and 90 percent emits one band event each", async () => {
    const allowance = 10;
    const scenario = await newScenario();
    await setTestClock("2026-07-01T10:00:00.000Z");
    await coverClinic(scenario, { max_allowance_per_month: allowance });
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

    for (let index = 0; index < 8; index += 1) {
      await completeChargedRequest(scenario, token);
    }
    await shipCoverageOutbox(scenario.installationId);

    let bandEvents = await listBandCrossedEvents(scenario.orgId);
    expect(bandEvents.filter((event) => event.band === "75")).toHaveLength(1);

    await completeChargedRequest(scenario, token);
    await shipCoverageOutbox(scenario.installationId);

    bandEvents = await listBandCrossedEvents(scenario.orgId);
    expect(bandEvents.filter((event) => event.band === "90")).toHaveLength(1);

    const band90Count = bandEvents.filter((event) => event.band === "90").length;
    await completeChargedRequest(scenario, token);
    await shipCoverageOutbox(scenario.installationId);

    bandEvents = await listBandCrossedEvents(scenario.orgId);
    expect(bandEvents.filter((event) => event.band === "90")).toHaveLength(
      band90Count,
    );
  });

  it("E2E-P3.4-09 A provider call that consumes nothing releases the reservation", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const token = await mintAat(scenario);

    const usedBefore = await readHotUsed(scenario.installationId);
    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION, {
      targets: [],
    });
    const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    expect(published.status).toBe(200);
    const promoted = await promote(POLICY_ID, POLICY_VERSION);
    expect(promoted.status).toBe(200);

    const invoked = await invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(invoked.status).toBe(200);
    await flushBackgroundWork();

    const usedAfter = await readHotUsed(scenario.installationId);
    expect(usedAfter).toBe(usedBefore);
    expect(await readHotReservations(scenario.installationId)).toHaveLength(0);
  });

  it("E2E-P3.4-10 A reservation older than 15 minutes is charged once", async () => {
    const scenario = await newScenario();
    await setTestClock("2026-08-01T12:00:00.000Z");
    await coverClinic(scenario);
    await newClinic(scenario);
    const token = await mintAat(scenario);

    let creditCalls = 0;
    let swallowedCreditBody: Record<string, unknown> | null = null;
    const restoreFetch = wrapQuotaDoFetch(
      scenario.installationId,
      async (body, forward) => {
        if (body.kind === "credit" && creditCalls === 0) {
          creditCalls += 1;
          swallowedCreditBody = body;
          return new Response(JSON.stringify({ kind: "credit", ok: true }), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          });
        }
        return forward("https://quota-do.internal/rpc", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
      },
    );

    try {
      const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
      const published = await publishPolicy(
        POLICY_ID,
        POLICY_VERSION,
        document,
      );
      expect(published.status).toBe(200);
      const promoted = await promote(POLICY_ID, POLICY_VERSION);
      expect(promoted.status).toBe(200);

      const invoked = await invoke(scenario, {
        token,
        idempotencyKey: crypto.randomUUID(),
      });
      expect(invoked.status).toBe(200);
      await flushBackgroundWork();

      expect(swallowedCreditBody).toBeTruthy();
      expect(await readHotReservations(scenario.installationId).then((r) => r.length)).toBeGreaterThan(0);

      await setTestClock("2026-08-01T12:16:00.000Z");

      const document2 = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
      await publishPolicy(POLICY_ID, POLICY_VERSION, document2);
      await promote(POLICY_ID, POLICY_VERSION);

      const second = await invoke(scenario, {
        token,
        idempotencyKey: crypto.randomUUID(),
      });
      expect(second.status).toBe(200);
      await flushBackgroundWork();

      await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

      const ref = String(invoked.events[0]?.data.request_reference);
      const request = await getAiRequest(ref);
      const requestId = String(request?.request_id);
      const usage = await getUsageEvents(requestId);
      expect(usage).toHaveLength(1);

      const hotBeforeReplay = await readHotUsage(scenario.installationId);
      if (swallowedCreditBody) {
        await quotaDoStub(scenario.installationId).fetch(
          "https://quota-do.internal/rpc",
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(swallowedCreditBody),
          },
        );
      }
      const hotAfterReplay = await readHotUsage(scenario.installationId);
      expect(hotAfterReplay.used).toBe(hotBeforeReplay.used);
      expect(hotAfterReplay.reserved).toBe(hotBeforeReplay.reserved);
      const usageAfterReplay = await getUsageEvents(requestId);
      expect(usageAfterReplay).toHaveLength(1);
    } finally {
      restoreFetch();
    }
  });

  it("E2E-P3.4-11 A replayed jti or idempotency key returns the stored answer", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const token = await mintAat(scenario);

    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    await promote(POLICY_ID, POLICY_VERSION);

    const idempotencyKey = crypto.randomUUID();
    const first = await invoke(scenario, { token, idempotencyKey });
    expect(first.status).toBe(200);
    await flushBackgroundWork();

    const hotAfterFirst = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, state) =>
        sqlSelect<Record<string, unknown>>(state, "SELECT * FROM hot LIMIT 1"),
    );

    const replayIdempotency = await invoke(scenario, { token, idempotencyKey });
    expect(replayIdempotency.status).toBe(first.status);
    expect(replayIdempotency.body).toEqual(first.body);
    expect(replayIdempotency.events).toEqual(first.events);

    const sharedJti = crypto.randomUUID();
    const tokenA = await mintAat(scenario, { jti: sharedJti });
    const tokenB = await mintAat(scenario, { jti: sharedJti });
    const keyA = crypto.randomUUID();
    const keyB = crypto.randomUUID();
    const jtiFirst = await invoke(scenario, {
      token: tokenA,
      idempotencyKey: keyA,
    });
    expect(jtiFirst.status).toBe(200);
    await flushBackgroundWork();
    const jtiReplay = await invoke(scenario, {
      token: tokenB,
      idempotencyKey: keyB,
    });
    expect(jtiReplay.status).toBe(jtiFirst.status);
    expect(jtiReplay.body).toEqual(jtiFirst.body);

    const hotAfterReplay = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, state) =>
        sqlSelect<Record<string, unknown>>(state, "SELECT * FROM hot LIMIT 1"),
    );
    expect(JSON.stringify(hotAfterReplay)).toBe(JSON.stringify(hotAfterFirst));
  });

  it("E2E-P3.4-12 A DO version rejection is coverage_unknown", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const token = await mintAat(scenario);

    const restoreFetch = wrapQuotaDoFetch(
      scenario.installationId,
      async (body, forward) => {
        if (body.kind === "admission") {
          return new Response(
            JSON.stringify({
              result: "rejected",
              code: "contract_version_unsupported",
            }),
            { status: 200, headers: { "Content-Type": "application/json" } },
          );
        }
        return forward("https://quota-do.internal/rpc", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
      },
    );

    try {
      const denied = await invoke(scenario, { token });
      expect(denied.status).toBe(503);
      expect(denied.body?.code).toBe("coverage_unknown");
      expect(denied.body?.retry_after).toBeTruthy();
    } finally {
      restoreFetch();
    }
  });
});
