/**
 * P3.5 — Term boundaries, grace and renewal (H-AP, E2E-P3.5-01–08).
 */

import { env, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { addDuration } from "../../src/coverage/calendar";
import {
  applyAllMigrations,
  coverClinic,
  fakePolicyDocument,
  flushBackgroundWork,
  getAiRequest,
  getUsageEvents,
  invoke,
  mintAat,
  newClinic,
  newScenario,
  POLICY_ID,
  POLICY_VERSION,
  promote,
  publishPolicy,
  registerVisitSummaryCapability,
  resetPlatformState,
  setTestClock,
  setupVendorHarness,
  terminalEventTypes,
  type Scenario,
} from "./harness";

const QUOTA_WEIGHT = 1;
const GRACE_DAYS = 7;

const FEB_1_10 = "2026-02-01T10:00:00.000Z";
const MAR_1_10 = "2026-03-01T10:00:00.000Z";
const MAR_4_10 = "2026-03-04T10:00:00.000Z";
const MAR_27_10 = "2026-03-27T10:00:00.000Z";
const APR_1_10 = "2026-04-01T10:00:00.000Z";
const MAY_1_14 = "2026-05-01T14:00:00.000Z";
const JUN_1_14 = "2026-06-01T14:00:00.000Z";

const doGetReal = env.DO.get.bind(env.DO);

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

type DoTermRow = {
  term_id: string;
  state: string;
  starts_at: string | null;
  ends_at: string | null;
  calendar_start: string | null;
  allowance: number | null;
  end_reason: string | null;
  used_final: number | null;
  grace_ends_at: string | null;
  grace_days: number | null;
  position: number;
};

async function readDoTerms(installationId: string): Promise<DoTermRow[]> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect<DoTermRow>(
      state,
      `SELECT term_id, state, starts_at, ends_at, calendar_start, allowance, end_reason,
              used_final, grace_ends_at, grace_days, position
       FROM term ORDER BY position ASC`,
    ),
  );
}

async function readHotUsage(
  installationId: string,
): Promise<{ used: number; reserved: number; grace_base_used: number }> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ used: number; reserved: number; grace_base_used: number }>(
        state,
        "SELECT used, reserved, grace_base_used FROM hot LIMIT 1",
      ),
  );
  return {
    used: rows[0]?.used ?? 0,
    reserved: rows[0]?.reserved ?? 0,
    grace_base_used: rows[0]?.grace_base_used ?? 0,
  };
}

async function runQuotaAlarm(installationId: string): Promise<void> {
  await runDurableObjectAlarm(quotaDoStub(installationId));
}

async function setupPromotedPolicy(scenario: Scenario): Promise<string> {
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  expect(published.status).toBe(200);
  const promoted = await promote(POLICY_ID, POLICY_VERSION);
  expect(promoted.status).toBe(200);
  return await mintAat(scenario);
}

async function completeChargedRequest(
  scenario: Scenario,
  token: string,
): Promise<string | null> {
  const invoked = await invoke(scenario, {
    token,
    idempotencyKey: crypto.randomUUID(),
  });
  expect(invoked.status).toBe(200);
  expect(terminalEventTypes(invoked.events)).toEqual(["completed"]);
  await flushBackgroundWork();
  const ref = String(invoked.events[0]?.data.request_reference);
  const request = await getAiRequest(ref);
  const usage = await getUsageEvents(String(request?.request_id));
  expect(usage).toHaveLength(1);
  return usage[0]?.term_id ? String(usage[0].term_id) : null;
}

function unscaledTermDays(startIso: string, endIso: string): number {
  const ms = Date.parse(endIso) - Date.parse(startIso);
  return ms / (24 * 60 * 60 * 1000);
}

function graceAllowanceCeiling(
  allowance: number,
  graceDays: number,
  termStartIso: string,
  termEndIso: string,
): number {
  const termDays = unscaledTermDays(termStartIso, termEndIso);
  return Math.ceil((allowance * graceDays) / termDays);
}

function graceAllowanceRemaining(
  allowance: number,
  graceBaseUsed: number,
  graceDays: number,
  termStartIso: string,
  termEndIso: string,
): number {
  const ceiling = graceAllowanceCeiling(
    allowance,
    graceDays,
    termStartIso,
    termEndIso,
  );
  return Math.min(allowance - graceBaseUsed, ceiling);
}

async function enterGraceAtTermEnd(scenario: Scenario): Promise<DoTermRow> {
  const terms = await readDoTerms(scenario.installationId);
  const active = terms.find((row) => row.state === "active");
  expect(active?.ends_at).toBeTruthy();
  await setTestClock(String(active!.ends_at));
  await runQuotaAlarm(scenario.installationId);
  const after = await readDoTerms(scenario.installationId);
  const grace = after.find((row) => row.state === "grace");
  expect(grace).toBeTruthy();
  return grace!;
}

async function lapseGraceAtEnd(scenario: Scenario): Promise<void> {
  const terms = await readDoTerms(scenario.installationId);
  const grace = terms.find((row) => row.state === "grace");
  expect(grace?.grace_ends_at).toBeTruthy();
  await setTestClock(String(grace!.grace_ends_at));
  await runQuotaAlarm(scenario.installationId);
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

describe("term boundaries, grace and renewal", () => {
  it("E2E-P3.5-01 A9 renewal paid five days early queues and activates at the old end", async () => {
    const scenario = await newScenario();
    await setTestClock(MAR_1_10);
    await coverClinic(scenario);

    const t1AfterFirst = (await readDoTerms(scenario.installationId)).find(
      (row) => row.state === "active",
    );
    expect(t1AfterFirst).toBeTruthy();
    const allowanceBefore = t1AfterFirst!.allowance;
    const hotBeforeRenewal = await readHotUsage(scenario.installationId);

    await setTestClock(MAR_27_10);
    await coverClinic(scenario);

    const midTerms = await readDoTerms(scenario.installationId);
    const t1Mid = midTerms.find((row) => row.term_id === t1AfterFirst!.term_id);
    const t2Queued = midTerms.find((row) => row.state === "queued");
    expect(t2Queued).toBeTruthy();
    expect(t1Mid?.allowance).toBe(allowanceBefore);
    const hotMid = await readHotUsage(scenario.installationId);
    expect(hotMid.used).toBe(hotBeforeRenewal.used);
    expect(hotMid.reserved).toBe(hotBeforeRenewal.reserved);

    await setTestClock(APR_1_10);
    await runQuotaAlarm(scenario.installationId);

    const after = await readDoTerms(scenario.installationId);
    const t1Ended = after.find((row) => row.term_id === t1AfterFirst!.term_id);
    const t2Active = after.find((row) => row.state === "active");
    expect(t1Ended?.state).toBe("ended");
    expect(t1Ended?.end_reason).toBe("expired");
    expect(t2Active).toBeTruthy();
    expect(t2Active?.starts_at).toBe(APR_1_10);
    expect(t2Active?.calendar_start).toBe(APR_1_10);
    expect(t2Active?.ends_at).toBe(MAY_1_10);
    expect(t2Active?.allowance).toBe(allowanceBefore);
    const hotAfter = await readHotUsage(scenario.installationId);
    expect(hotAfter.used).toBe(0);
  });

  it("E2E-P3.5-02 A10 unpaid end enters grace then lapses as expired", async () => {
    const scenario = await newScenario();
    await setTestClock(FEB_1_10);
    await coverClinic(scenario);
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

    const active = (await readDoTerms(scenario.installationId)).find(
      (row) => row.state === "active",
    );
    expect(active?.ends_at).toBeTruthy();

    const graceTerm = await enterGraceAtTermEnd(scenario);
    expect(graceTerm.term_id).toBe(active!.term_id);

    const admittedTermId = await completeChargedRequest(scenario, token);
    expect(admittedTermId).toBe(graceTerm.term_id);

    await lapseGraceAtEnd(scenario);

    const denied = await invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(denied.status).toBe(403);
    expect(denied.body?.code).toBe("coverage_lapsed");
    expect(denied.body?.coverage_reason).toBe("expired");
  });

  it("E2E-P3.5-03 The reservation that takes the last grace credit ends grace_exhausted", async () => {
    const allowance = 7;
    const scenario = await newScenario();
    await setTestClock(FEB_1_10);
    await coverClinic(scenario, { max_allowance_per_month: allowance });
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

    const activeBeforeGrace = (await readDoTerms(scenario.installationId)).find(
      (row) => row.state === "active",
    );
    expect(activeBeforeGrace?.starts_at).toBeTruthy();
    expect(activeBeforeGrace?.ends_at).toBeTruthy();

    const graceTerm = await enterGraceAtTermEnd(scenario);
    const hotInGrace = await readHotUsage(scenario.installationId);
    const remaining = graceAllowanceRemaining(
      allowance,
      hotInGrace.grace_base_used,
      graceTerm.grace_days ?? GRACE_DAYS,
      String(activeBeforeGrace!.starts_at),
      String(activeBeforeGrace!.ends_at),
    );
    expect(remaining).toBeGreaterThan(0);

    for (let index = 0; index < remaining - 1; index += 1) {
      await completeChargedRequest(scenario, token);
    }

    const lastAdmission = await invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(lastAdmission.status).toBe(200);
    await flushBackgroundWork();

    const ended = (await readDoTerms(scenario.installationId)).find(
      (row) => row.term_id === graceTerm.term_id,
    );
    expect(ended?.state).toBe("ended");
    expect(ended?.end_reason).toBe("grace_exhausted");

    const denied = await invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(denied.status).toBe(403);
    expect(denied.body?.code).toBe("coverage_lapsed");
    expect(denied.body?.coverage_reason).toBe("grace_exhausted");
  });

  it("E2E-P3.5-04 A grant on day three of grace keeps the old calendar", async () => {
    const scenario = await newScenario();
    await setTestClock(FEB_1_10);
    await coverClinic(scenario);
    await newClinic(scenario);
    const token = await setupPromotedPolicy(scenario);

    const t1 = (await readDoTerms(scenario.installationId)).find(
      (row) => row.state === "active",
    );
    const t1EndsAt = String(t1?.ends_at);
    expect(t1EndsAt.length).toBeGreaterThan(0);

    const graceTerm = await enterGraceAtTermEnd(scenario);
    expect(graceTerm.term_id).toBe(t1!.term_id);

    const dayThreeOfGrace = addDuration(t1EndsAt, "day", 3);
    await setTestClock(dayThreeOfGrace);
    await completeChargedRequest(scenario, token);
    const hotAfterUsage = await readHotUsage(scenario.installationId);
    expect(hotAfterUsage.used).toBeGreaterThanOrEqual(QUOTA_WEIGHT);

    await setTestClock(MAR_4_10);
    await coverClinic(scenario);

    const terms = await readDoTerms(scenario.installationId);
    const t1Ended = terms.find((row) => row.term_id === t1!.term_id);
    const t2Active = terms.find((row) => row.state === "active");
    expect(t2Active).toBeTruthy();
    expect(t2Active?.calendar_start).toBe(t1EndsAt);
    expect(t2Active?.ends_at).toBe(addDuration(t1EndsAt, "month", 1));
    expect(t1Ended?.state).toBe("ended");
    expect(t1Ended?.end_reason).toBe("renewed");
    expect(t1Ended?.used_final).toBe(hotAfterUsage.used);
  });

  it("E2E-P3.5-05 A11 a lapsed clinic paid two months later starts now", async () => {
    const scenario = await newScenario();
    await setTestClock(FEB_1_10);
    await coverClinic(scenario);

    const active = (await readDoTerms(scenario.installationId)).find(
      (row) => row.state === "active",
    );
    const t1EndsAt = String(active?.ends_at);
    expect(t1EndsAt.length).toBeGreaterThan(0);

    await enterGraceAtTermEnd(scenario);
    const grace = (await readDoTerms(scenario.installationId)).find(
      (row) => row.state === "grace",
    );
    expect(grace?.grace_ends_at).toBe(addDuration(t1EndsAt, "day", GRACE_DAYS));

    await lapseGraceAtEnd(scenario);
    const lapsedTerms = await readDoTerms(scenario.installationId);
    expect(lapsedTerms.some((row) => row.state === "grace")).toBe(false);
    expect(lapsedTerms.some((row) => row.state === "active")).toBe(false);

    await setTestClock(MAY_1_14);
    await coverClinic(scenario);

    const activeAfterPay = (await readDoTerms(scenario.installationId)).find(
      (row) => row.state === "active",
    );
    expect(activeAfterPay).toBeTruthy();
    expect(activeAfterPay?.starts_at).toBe(MAY_1_14);
    expect(activeAfterPay?.calendar_start).toBe(MAY_1_14);
    expect(activeAfterPay?.ends_at).toBe(JUN_1_14);
  });
});
