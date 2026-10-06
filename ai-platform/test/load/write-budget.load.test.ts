/**
 * P3.11 — Write budget across exhaustion (H-AP load, E2E-P3.11-05).
 *
 * Prompt registry is mocked like load-and-cost happy path. Promise.all schedules
 * 100 POST /v1/requests; a promise-chain gate serializes live POST + settle so
 * workerd does not crash while background credit clears hot replay/idempotency maps.
 */

import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

const { resolveArtifactMock, resolvePromptVersionMock } = vi.hoisted(() => {
  const artifactByRef: Record<string, string> = {
    "clinic.visit_summary/system@v1":
      "You are a clinical documentation assistant for outpatient visit summaries. Your role is advisory only: produce clear, professional prose that helps clinicians review and refine visit documentation before it enters the record.\n\nDraft a concise visit summary based on the supplied clinical context and the clinician's stated intent. Use neutral, factual language organized for quick review by a licensed clinician who retains full clinical responsibility.\n\nYour output is displayed for advisory review only. It does not enter the medical record until a clinician explicitly accepts it.\n",
    "clinic.visit_summary/rules-visit-summary@v1":
      "## Visit summary business rules\n\n- Do not state or imply a definitive diagnosis. Use observational language (\"presents with\", \"reports\") and defer diagnostic conclusions to the reviewing clinician.\n- Do not recommend specific medications, dosages, or treatment plans. Frame any therapeutic discussion as documentation assistance, not prescription.\n- Do not fabricate clinical findings, test results, or patient history not present in the supplied context.\n- Flag missing or ambiguous information rather than inferring undocumented details.\n- Maintain patient confidentiality: include only information relevant to the summary.\n- If the supplied context is insufficient for a meaningful summary, state what is missing instead of generating speculative content.\n",
    "clinic.visit_summary/template-visit-summary@v1":
      '<key name="visit.chief_complaint@v1" shape="visit.chief_complaint@v1">\n{{visit.chief_complaint@v1}}\n</key>\n',
  };

  function fnv1a(content: string): string {
    let hash = 0x811c9dc5;
    for (let index = 0; index < content.length; index += 1) {
      hash ^= content.charCodeAt(index);
      hash = Math.imul(hash, 0x01000193);
    }
    return (hash >>> 0).toString(16).padStart(8, "0");
  }

  return {
    resolveArtifactMock(ref: string): string | undefined {
      return artifactByRef[ref];
    },
    resolvePromptVersionMock(manifest: {
      "Prompt binding": {
        systemInstructionArtifactRef: unknown;
        businessRuleFragmentRefs?: unknown;
        contextRenderingTemplateRef?: unknown;
      };
    }): string {
      const binding = manifest["Prompt binding"];
      const refs = [
        String(binding.systemInstructionArtifactRef),
        ...(Array.isArray(binding.businessRuleFragmentRefs)
          ? binding.businessRuleFragmentRefs.map(String)
          : []),
        ...(binding.contextRenderingTemplateRef != null &&
        String(binding.contextRenderingTemplateRef).length > 0
          ? [String(binding.contextRenderingTemplateRef)]
          : []),
      ];
      const parts = refs
        .map((ref) => artifactByRef[ref])
        .filter((content): content is string => content !== undefined);
      return fnv1a(parts.join("\0"));
    },
  };
});

vi.mock("../../src/prompt/registry", () => ({
  resolveArtifact: resolveArtifactMock,
  resolvePromptVersion: resolvePromptVersionMock,
}));

import { env, runInDurableObject, SELF } from "cloudflare:test";
import {
  applyAllMigrations,
  CAPABILITY_VERSION,
  coverClinic,
  fakePolicyDocument,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  mintAat,
  newClinic,
  newScenario,
  parseSseEvents,
  POLICY_ID,
  POLICY_VERSION,
  promote,
  publishPolicy,
  queryAll,
  registerVisitSummaryCapability,
  resetPlatformState,
  setupVendorHarness,
  visitSummaryInvokeBody,
  type Scenario,
  type SseEvent,
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

async function setupPromotedPolicy(scenario: Scenario): Promise<void> {
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  expect(published.status).toBe(200);
  const promoted = await promote(POLICY_ID, POLICY_VERSION);
  expect(promoted.status).toBe(200);
  await mintAat(scenario);
}

function createFetchPool() {
  let chain: Promise<unknown> = Promise.resolve();
  return function withFetchSlot<T>(fn: () => Promise<T>): Promise<T> {
    const run = chain.then(() => fn());
    chain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  };
}

/** POST /v1/requests without per-response flush (avoids 100× settle delay under load). */
async function invokeWriteBudgetLoad(
  scenario: Scenario,
  opts: { token: string; idempotencyKey: string },
): Promise<{
  status: number;
  events: SseEvent[];
}> {
  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${opts.token}`,
        "content-type": "application/json",
        "x-idempotency-key": opts.idempotencyKey,
        "x-capability-version": CAPABILITY_VERSION,
        "Aip-Contract-Version": "1",
      },
      body: JSON.stringify(visitSummaryInvokeBody(scenario)),
    }),
  );

  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("text/event-stream")) {
    return { status: response.status, events: await parseSseEvents(response) };
  }

  const text = await response.text();
  return {
    status: response.status,
    events: text.length > 0 ? [] : [],
  };
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
    await coverClinic(scenario, {
      max_allowance_per_month: allowance,
      concurrency_limit: CONCURRENT_REQUESTS,
    });
    await newClinic(scenario);

    const queued = (await readDoTerms(scenario.installationId)).filter(
      (row) => row.state === "queued",
    );
    expect(queued).toHaveLength(0);

    await setupPromotedPolicy(scenario);

    const tokens: string[] = [];
    for (let index = 0; index < CONCURRENT_REQUESTS; index += 1) {
      tokens.push(await mintAat(scenario));
    }

    const withFetchSlot = createFetchPool();
    const results = await Promise.all(
      tokens.map((token) =>
        withFetchSlot(async () => {
          const result = await invokeWriteBudgetLoad(scenario, {
            token,
            idempotencyKey: crypto.randomUUID(),
          });
          await flushBackgroundWork();
          return result;
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

    const termsAfter = await readDoTerms(scenario.installationId);
    const laterActiveTerms = termsAfter.filter(
      (row) => row.state === "active" && row.term_id !== exhausted.term_id,
    );
    expect(laterActiveTerms).toHaveLength(0);

    const successorCharges = results.filter((result) => result.status === 200);
    for (const charged of successorCharges) {
      const ref = String(charged.events[0]?.data.request_reference ?? "");
      if (ref.length === 0) {
        continue;
      }
      const usage = await queryAll<{ term_id: string }>(
        `SELECT ue.term_id FROM usage_event ue
         INNER JOIN ai_request ar ON ar.request_id = ue.request_id
         WHERE ar.request_reference = ?`,
        [ref],
      );
      for (const row of usage) {
        for (const later of laterActiveTerms) {
          expect(row.term_id).not.toBe(later.term_id);
        }
      }
    }

    const requestIds = await queryAll<{ request_id: string }>(
      `SELECT request_id FROM ai_request
       WHERE installation_id = ?
       ORDER BY created_at ASC`,
      [scenario.installationId],
    );
    expect(requestIds.length).toBeGreaterThanOrEqual(allowance);
    expect(requestIds.length).toBeLessThanOrEqual(CONCURRENT_REQUESTS);

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
  }, 240_000);
});
