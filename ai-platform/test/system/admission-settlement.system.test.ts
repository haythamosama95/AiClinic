/**
 * P3.4 — Admission and settlement against terms (H-AP, E2E-P3.4-01–12).
 */

import { env, runInDurableObject } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_ID,
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

/** Paid-grant helper; real export lands in harness.ts at T013 (FR-014). */
async function coverClinic(scenario: Scenario): Promise<void> {
  const harnessModule = await import("./harness");
  const fn = (harnessModule as { coverClinic?: (s: Scenario) => Promise<void> })
    .coverClinic;
  expect(fn).toBeTypeOf("function");
  await fn!(scenario);
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
});
