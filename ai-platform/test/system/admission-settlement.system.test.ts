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
  ensureDefaultCohortGrants,
  waitForSettledRequest,
  type Scenario,
} from "./harness";
import { addDuration } from "../../src/coverage/calendar";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { getPerRequestWriteCounts } from "../../src/quota-do/index";

const QUOTA_WEIGHT = 1;
const W_MAX = QUOTA_WEIGHT;
const doGetReal = env.DO.get.bind(env.DO);

async function harnessNowMs(): Promise<number> {
  const row = await queryOne<{ now_iso: string }>(
    "SELECT now_iso FROM harness_test_clock WHERE id = 'default'",
  );
  if (row?.now_iso) {
    const parsed = Date.parse(row.now_iso);
    if (!Number.isNaN(parsed)) {
      return parsed;
    }
  }
  return Date.now();
}

function quotaDoStub(installationId: string) {
  return doGetReal(env.DO.idFromName(installationId));
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

async function completeChargedRequest(scenario: Scenario): Promise<void> {
  const invoked = await invoke(scenario, {
    token: await mintAat(scenario),
    idempotencyKey: crypto.randomUUID(),
  });
  expect(invoked.status).toBe(200);
  expect(terminalEventTypes(invoked.events)).toEqual(["completed"]);
  await flushBackgroundWork();
  // The usage credit (which appends band_crossed / term-end outbox rows to
  // the DO) runs in waitUntil after the SSE response. Poll for the ledger
  // row instead of a fixed sleep so the shipCoverageOutbox flush that
  // follows always drains a settled DO (E2E-P3.4-08 flake: missing band
  // event).
  const ref = String(invoked.events[0]?.data.request_reference);
  const request = await getAiRequest(ref);
  const usageStarted = Date.now();
  let usageCount = await count("usage_event", "request_id = ?", [
    String(request?.request_id),
  ]);
  while (usageCount < 1 && Date.now() - usageStarted < 8000) {
    await flushBackgroundWork();
    usageCount = await count("usage_event", "request_id = ?", [
      String(request?.request_id),
    ]);
  }
  expect(usageCount).toBe(1);
}

async function postUntilAllowanceConsumed(
  scenario: Scenario,
  allowance: number,
): Promise<void> {
  for (let attempt = 0; attempt < allowance; attempt += 1) {
    await completeChargedRequest(scenario);
  }
}

async function shipCoverageOutbox(installationId: string): Promise<void> {
  await runDurableObjectAlarm(quotaDoStub(installationId));
  // The alarm handler re-arms the next boundary on WALL CLOCK (syncAlarm's
  // 5 s floor); the DO alarm path cannot read the D1 harness clock, so a
  // slow runner lets it fire mid-test and apply term boundaries with real
  // time (E2E-P3.4-08 flake: band events from a mutated term). Cancel the
  // re-armed timer so state reads stay deterministic.
  await runInDurableObject(quotaDoStub(installationId), async (_instance, state) => {
    await state.storage.deleteAlarm();
  });
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
  const targetName = env.DO.idFromName(installationId).toString();
  const originalGet = env.DO.get.bind(env.DO);
  const wrappedStubs = new WeakSet<object>();
  const fetchSpies: Array<ReturnType<typeof vi.spyOn>> = [];
  let restored = false;

  const getSpy = vi.spyOn(env.DO, "get").mockImplementation((id) => {
    const stub = originalGet(id);
    if (id.toString() !== targetName) {
      return stub;
    }
    if (!wrappedStubs.has(stub)) {
      wrappedStubs.add(stub);
      const originalFetch = stub.fetch.bind(stub);
      const forward = (fwdInput: RequestInfo, fwdInit?: RequestInit) =>
        originalFetch(fwdInput, fwdInit);
      fetchSpies.push(
        vi.spyOn(stub, "fetch").mockImplementation(async (input, init) => {
          const request =
            input instanceof Request ? input : new Request(input, init);
          const contentType = request.headers.get("content-type") ?? "";
          if (
            request.method.toUpperCase() !== "POST" ||
            !contentType.includes("json")
          ) {
            return originalFetch(input, init);
          }
          const text = await request.clone().text();
          if (text.trim().length === 0) {
            return originalFetch(input, init);
          }
          const body = JSON.parse(text) as Record<string, unknown>;
          return handler(body, forward);
        }),
      );
    }
    return stub;
  });

  return () => {
    if (restored) {
      return;
    }
    restored = true;
    getSpy.mockRestore();
    for (const spy of fetchSpies) {
      spy.mockRestore();
    }
  };
}

async function seedOpenReservations(
  scenario: Scenario,
  count: number,
): Promise<void> {
  const { CHANNEL_VERSIONS } = await import("vendor-contracts");
  const stub = quotaDoStub(scenario.installationId);
  const nowMs = await harnessNowMs();
  for (let index = 0; index < count; index += 1) {
    const response = await stub.fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        kind: "admission",
        now: nowMs,
        jti: crypto.randomUUID(),
        installationId: scenario.installationId,
        idempotencyKey: crypto.randomUUID(),
        requestReference: `CONC-SEED-${index}`,
        capabilityId: CAPABILITY_ID,
        quotaWeight: QUOTA_WEIGHT,
        orgId: scenario.orgId,
      }),
    });
    expect(response.ok).toBe(true);
    const body = (await response.json()) as { outcome?: string };
    expect(body.outcome).toBe("admitted");
  }
}

async function directDoAdmission(
  scenario: Scenario,
  input: { now: number; jti?: string; idempotencyKey?: string; requestReference?: string; requestId?: string },
): Promise<Record<string, unknown>> {
  const response = await quotaDoStub(scenario.installationId).fetch("https://quota-do.internal/rpc", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contract_version: CHANNEL_VERSIONS.platformDo,
      kind: "admission",
      now: input.now,
      requestId: input.requestId,
      jti: input.jti ?? crypto.randomUUID(),
      installationId: scenario.installationId,
      idempotencyKey: input.idempotencyKey ?? crypto.randomUUID(),
      requestReference: input.requestReference ?? crypto.randomUUID(),
      capabilityId: CAPABILITY_ID,
      quotaWeight: QUOTA_WEIGHT,
      orgId: scenario.orgId,
    }),
  });
  return await response.json() as Record<string, unknown>;
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
  vi.restoreAllMocks();
  await resetPlatformState();
  registerVisitSummaryCapability();
  await setupVendorHarness();
});

describe("admission settlement against terms", () => {
  it("E2E-P3.4-01 CP-B paid grant then issuer token lists the plan and completes a request charged to the term", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    await ensureDefaultCohortGrants(scenario);
    const token = await mintAat(scenario);

    const mirror = await queryOne<Record<string, unknown>>(
      "SELECT * FROM coverage_mirror WHERE installation_id = ?",
      [scenario.installationId],
    );
    expect(mirror).toBeTruthy();
    const termSnapshot = JSON.parse(String(mirror!.term_snapshot)) as {
      term?: { capabilities?: string[] };
    };
    expect(termSnapshot.term?.capabilities).toContain(CAPABILITY_ID);

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
    await waitForSettledRequest(ref);
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

    const binding = await queryOne<{ installation_id: string }>(
      "SELECT installation_id FROM tenant_binding WHERE org_id = ? AND status = 'active'",
      [scenario.orgId],
    );
    expect(binding?.installation_id).toBe(scenario.installationId);

    await seedOpenReservations(scenario, 16);
    expect(await readHotReservations(scenario.installationId)).toHaveLength(16);

    const limited = await invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(limited.status).toBe(429);
    expect(limited.body?.code).toBe("concurrency_limited");
    expect(limited.body?.retry_after).toBeTruthy();
    expect(limited.body?.code).not.toBe("rate_limited");
  });

  it("R5-A1/R5-A2: predecessor reservations keep their term attribution after successor activation", async () => {
    const scenario = await newScenario();
    await setTestClock("2026-04-01T12:00:00.000Z");
    await coverClinic(scenario, { max_allowance_per_month: 3 });
    await coverClinic(scenario, { max_allowance_per_month: 3 });
    await newClinic(scenario);
    const firstTerm = (await readDoTerms(scenario.installationId)).find((row) => row.state === "active")!;
    const now = await harnessNowMs();
    const firstJti = crypto.randomUUID();
    const firstKey = crypto.randomUUID();
    const secondJti = crypto.randomUUID();
    const secondKey = crypto.randomUUID();
    const first = await directDoAdmission(scenario, { now, jti: firstJti, idempotencyKey: firstKey });
    const second = await directDoAdmission(scenario, { now, jti: secondJti, idempotencyKey: secondKey });
    expect(first.outcome).toBe("admitted");
    expect(second.outcome).toBe("admitted");

    const successorAdmission = await directDoAdmission(scenario, {
      now: Date.parse(String(firstTerm.ends_at)) + 1,
    });
    expect(successorAdmission.outcome).toBe("admitted");
    const afterActivation = await readDoTerms(scenario.installationId);
    const ended = afterActivation.find((row) => row.term_id === firstTerm.term_id);
    const active = afterActivation.find((row) => row.state === "active");
    expect(ended?.used_final).toBe(0);
    expect(active?.term_id).not.toBe(firstTerm.term_id);
    expect(active?.allowance).toBe(3);

    const stub = quotaDoStub(scenario.installationId);
    const consumedId = String(first.reservation_id);
    const credit = await stub.fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        kind: "credit",
        installationId: scenario.installationId,
        requestId: consumedId,
        reservation_id: consumedId,
        requestReference: "R5-A2-consumed-old-term",
        usage: { tokens: 1, cost: 0 },
        partial: false,
        credits: 1,
      }),
    });
    expect((await credit.json() as Record<string, unknown>).ok).toBe(true);
    const releasedId = String(second.reservation_id);
    const release = await stub.fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        kind: "release",
        installationId: scenario.installationId,
        requestId: releasedId,
        idempotencyKey: secondKey,
        jti: secondJti,
      }),
    });
    expect((await release.json() as Record<string, unknown>).ok).toBe(true);

    const afterSettlement = await readDoTerms(scenario.installationId);
    expect(afterSettlement.find((row) => row.term_id === firstTerm.term_id)?.used_final).toBe(1);
    expect(await readHotUsed(scenario.installationId)).toBe(0);
  });

  it("R5-A7: a temporary concurrency refusal is reevaluated for the same idempotency key", async () => {
    const scenario = await newScenario();
    await setTestClock("2026-04-01T12:00:00.000Z");
    await coverClinic(scenario, { concurrency_limit: 1, max_allowance_per_month: 3 });
    await newClinic(scenario);
    const now = await harnessNowMs();
    const heldJti = crypto.randomUUID();
    const heldKey = crypto.randomUUID();
    const held = await directDoAdmission(scenario, { now, jti: heldJti, idempotencyKey: heldKey });
    expect(held.outcome).toBe("admitted");
    const retryKey = crypto.randomUUID();
    const deniedRequestId = crypto.randomUUID();
    const denied = await directDoAdmission(scenario, { now, idempotencyKey: retryKey, requestId: deniedRequestId });
    expect(denied.outcome).toBe("concurrency_exhausted");
    expect(getPerRequestWriteCounts(deniedRequestId)).toBeUndefined();

    const release = await quotaDoStub(scenario.installationId).fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        kind: "release",
        installationId: scenario.installationId,
        requestId: String(held.reservation_id),
        idempotencyKey: heldKey,
        jti: heldJti,
      }),
    });
    expect((await release.json() as Record<string, unknown>).ok).toBe(true);
    const retried = await directDoAdmission(scenario, { now, idempotencyKey: retryKey });
    expect(retried.outcome).toBe("admitted");
  });

  it("R5-A2: exhaustion closes at settled usage and stays final after reservation release", async () => {
    const scenario = await newScenario();
    await setTestClock("2026-04-01T12:00:00.000Z");
    await coverClinic(scenario, { max_allowance_per_month: 1 });
    await newClinic(scenario);
    const now = await harnessNowMs();
    const jti = crypto.randomUUID();
    const idempotencyKey = crypto.randomUUID();
    const admitted = await directDoAdmission(scenario, { now, jti, idempotencyKey });
    expect(admitted.outcome).toBe("admitted");
    const exhausted = (await readDoTerms(scenario.installationId)).find((row) => row.state === "exhausted");
    expect(exhausted?.used_final).toBe(0);

    const release = await quotaDoStub(scenario.installationId).fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        kind: "release",
        installationId: scenario.installationId,
        requestId: String(admitted.reservation_id),
        idempotencyKey,
        jti,
      }),
    });
    expect((await release.json() as Record<string, unknown>).ok).toBe(true);
    expect((await readDoTerms(scenario.installationId)).find((row) => row.term_id === exhausted?.term_id)?.state).toBe("exhausted");
    expect((await readDoTerms(scenario.installationId)).find((row) => row.term_id === exhausted?.term_id)?.used_final).toBe(0);
  });

  it("E2E-P3.4-05 Reaching the allowance with nothing queued exhausts the term", async () => {
    const allowance = 3;
    const scenario = await newScenario();
    await setTestClock("2026-04-01T12:00:00.000Z");
    await coverClinic(scenario, { max_allowance_per_month: allowance });
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

    await postUntilAllowanceConsumed(scenario, allowance);

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

    await postUntilAllowanceConsumed(scenario, allowance);

    const after = await readDoTerms(scenario.installationId);
    const active = after.find((row) => row.state === "active");
    expect(active).toBeTruthy();
    expect(active?.allowance).toBe(allowance);
    expect(active?.starts_at).toBeTruthy();
    expect(active?.ends_at).toBe(
      addDuration(String(active?.starts_at), "month", 1, "staging"),
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
      await completeChargedRequest(scenario);
    }

    const beforeHot = await readHotUsage(scenario.installationId);
    expect(beforeHot.used + beforeHot.reserved).toBe(allowance - 1);

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
    await shipCoverageOutbox(scenario.installationId);

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
      await completeChargedRequest(scenario);
    }
    await shipCoverageOutbox(scenario.installationId);

    let bandEvents = await listBandCrossedEvents(scenario.orgId);
    expect(bandEvents.filter((event) => event.band === "75")).toHaveLength(1);

    await completeChargedRequest(scenario);
    await shipCoverageOutbox(scenario.installationId);

    bandEvents = await listBandCrossedEvents(scenario.orgId);
    expect(bandEvents.filter((event) => event.band === "90")).toHaveLength(1);

    const band90Count = bandEvents.filter((event) => event.band === "90").length;
    await completeChargedRequest(scenario);
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
      for (let flush = 0; flush < 5; flush += 1) {
        await flushBackgroundWork();
      }

      restoreFetch();

      expect(swallowedCreditBody).toBeTruthy();
      expect(await readHotReservations(scenario.installationId).then((r) => r.length)).toBeGreaterThan(0);

      await setTestClock(
        new Date((await harnessNowMs()) + 16 * 60 * 1000).toISOString(),
      );

      const second = await invoke(scenario, {
        token: await mintAat(scenario, { jti: crypto.randomUUID() }),
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
        const replay = await quotaDoStub(scenario.installationId).fetch(
          "https://quota-do.internal/rpc",
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(swallowedCreditBody),
          },
        );
        const replayBody = (await replay.json()) as { ok?: boolean };
        expect(replayBody.ok).toBe(true);
      }
      const hotAfterReplay = await readHotUsage(scenario.installationId);
      expect(hotAfterReplay.used).toBe(hotBeforeReplay.used);
      expect(hotAfterReplay.reserved).toBe(hotBeforeReplay.reserved);
      const usageAfterReplay = await getUsageEvents(requestId);
      expect(usageAfterReplay).toHaveLength(1);

      await shipCoverageOutbox(scenario.installationId);
      for (let settle = 0; settle < 10; settle += 1) {
        await flushBackgroundWork();
      }
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

    await waitForSettledRequest(String(first.events[0]?.data.request_reference));
    const replayIdempotency = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey,
    });
    expect(replayIdempotency.status).toBe(first.status);
    expect(replayIdempotency.body).toEqual(first.body);
    // A replay returns the persisted terminal answer. It does not replay
    // provisional stream chunks from the original provider call.
    expect(
      replayIdempotency.events.filter((event) => event.event === "completed"),
    ).toEqual(first.events.filter((event) => event.event === "completed"));

    const sharedJti = crypto.randomUUID();
    const tokenA = await mintAat(scenario, { jti: sharedJti });
    const keyA = crypto.randomUUID();
    const keyB = crypto.randomUUID();
    const jtiFirst = await invoke(scenario, {
      token: tokenA,
      idempotencyKey: keyA,
    });
    expect(jtiFirst.status).toBe(200);
    await flushBackgroundWork();
    const hotAfterJtiFirst = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, state) =>
        sqlSelect<Record<string, unknown>>(state, "SELECT * FROM hot LIMIT 1"),
    );
    const jtiReplay = await invoke(scenario, {
      token: tokenA,
      idempotencyKey: keyB,
    });
    // B4 treats a repeated token jti as an authentication replay, even though
    // P3.4's broad replay wording also mentions jti alongside idempotency keys.
    expect(jtiReplay.status).toBe(401);
    expect(jtiReplay.body?.code).toBe("unauthenticated");

    const hotAfterReplay = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, state) =>
        sqlSelect<Record<string, unknown>>(state, "SELECT * FROM hot LIMIT 1"),
    );
    expect(JSON.stringify(hotAfterReplay)).toBe(
      JSON.stringify(hotAfterJtiFirst),
    );
  });

  it("E2E-P3.4-12 A DO version rejection is coverage_unknown", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

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
