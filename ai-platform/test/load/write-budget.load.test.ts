/**
 * P3.11 — Write budget across exhaustion (H-AP load, E2E-P3.11-05).
 */

import { env, runInDurableObject } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  applyAllMigrations,
  coverClinic,
  fakePolicyDocument,
  flushBackgroundWork,
  invoke,
  mintAat,
  newClinic,
  newScenario,
  POLICY_ID,
  POLICY_VERSION,
  promote,
  publishPolicy,
  queryAll,
  registerVisitSummaryCapability,
  resetPlatformState,
  setupVendorHarness,
  type Scenario,
} from "../system/harness";

const W_MAX = 1;
const CONCURRENT_REQUESTS = 100;

type RequestWriteCounts = {
  hot: number;
  events: number;
};

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

async function readPerRequestWriteCounts(
  installationId: string,
  requestId: string,
): Promise<RequestWriteCounts | null> {
  return runInDurableObject(quotaDoStub(installationId), async () => {
    const mod = await import("../../src/quota-do/index.ts");
    const reader = (
      mod as {
        getPerRequestWriteCounts?: (
          id: string,
        ) => RequestWriteCounts | undefined;
      }
    ).getPerRequestWriteCounts;
    if (reader === undefined) {
      return null;
    }
    return reader(requestId) ?? null;
  });
}

async function readDoTerms(installationId: string): Promise<
  Array<{
    term_id: string;
    state: string;
    allowance: number | null;
    used_final: number | null;
  }>
> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect(
      state,
      "SELECT term_id, state, allowance, used_final FROM term ORDER BY position ASC",
    ),
  );
}

async function readHotUsed(installationId: string): Promise<number> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ used: number }>(state, "SELECT used FROM hot LIMIT 1"),
  );
  return rows[0]?.used ?? 0;
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

describe("write budget across exhaustion", () => {
  it("E2E-P3.11-05 A34 100 concurrent requests across exhaustion stay inside the write budget", async () => {
    const allowance = CONCURRENT_REQUESTS - 1;
    const scenario = await newScenario();
    await coverClinic(scenario, { max_allowance_per_month: allowance });
    await newClinic(scenario);

    const queued = (await readDoTerms(scenario.installationId)).filter(
      (row) => row.state === "queued",
    );
    expect(queued).toHaveLength(0);

    const token = await setupPromotedPolicy(scenario);

    const results = await Promise.all(
      Array.from({ length: CONCURRENT_REQUESTS }, () =>
        invoke(scenario, {
          token,
          idempotencyKey: crypto.randomUUID(),
        }),
      ),
    );
    await flushBackgroundWork();

    expect(results.some((result) => result.status === 200)).toBe(true);

    const exhaustedTerms = (await readDoTerms(scenario.installationId)).filter(
      (row) => row.state === "exhausted",
    );
    expect(exhaustedTerms).toHaveLength(1);
    const exhausted = exhaustedTerms[0]!;
    const exhaustedUsed =
      exhausted.used_final ?? (await readHotUsed(scenario.installationId));
    expect(exhaustedUsed).toBeLessThanOrEqual(allowance + (W_MAX - 1));

    const successorCharges = results.filter((result) => result.status === 200);
    for (const charged of successorCharges) {
      const ref = String(charged.events[0]?.data.request_reference ?? "");
      if (ref.length === 0) {
        continue;
      }
      const usage = await queryAll<{ term_id: string }>(
        "SELECT term_id FROM usage_event WHERE request_reference = ?",
        [ref],
      );
      for (const row of usage) {
        expect(row.term_id).not.toBe(exhausted.term_id);
      }
    }

    const requestIds = await queryAll<{ request_id: string }>(
      `SELECT request_id FROM ai_request
       WHERE installation_id = ?
       ORDER BY created_at ASC`,
      [scenario.installationId],
    );
    expect(requestIds.length).toBe(CONCURRENT_REQUESTS);

    let exhaustRequestId: string | null = null;
    for (const row of requestIds) {
      const counts = await readPerRequestWriteCounts(
        scenario.installationId,
        row.request_id,
      );
      expect(counts).not.toBeNull();
      expect(counts!.hot).toBeLessThanOrEqual(2);
      if (counts!.events > 0) {
        if (exhaustRequestId === null) {
          exhaustRequestId = row.request_id;
        } else {
          expect(row.request_id).toBe(exhaustRequestId);
        }
      } else {
        expect(counts!.events).toBe(0);
      }
    }
    expect(exhaustRequestId).not.toBeNull();
  });
});
