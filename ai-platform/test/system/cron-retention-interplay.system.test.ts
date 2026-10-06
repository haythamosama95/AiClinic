/**
 * Suite 8 — cron retention interplay (plan §4, SYS-8.1–SYS-8.4).
 */

import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  clearConfigCache,
  count,
  coverClinic,
  DEFAULT_ENTITLE_PAYLOAD,
  flushBackgroundWork,
  getAiRequest,
  getEntitlement,
  getRequest,
  invoke,
  mintAat,
  newScenario,
  vendorSupportLookup,
  queryAll,
  registerVisitSummaryCapability,
  resetPlatformState,
  r2Exists,
  runScheduled,
  setupPromotedFakePolicy,
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

describe("cron retention interplay", () => {
  it("SYS-8.1 — Retention purge keeps usage_event money row", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario);

    const invoked = await invoke(scenario);
    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();

    const request = await getAiRequest(ref);
    const requestId = String(request?.request_id);
    const usageBefore = await env.DB.prepare(
      "SELECT usage_event_id, request_id, tokens, cost FROM usage_event WHERE request_id = ?",
    )
      .bind(requestId)
      .first<{
        usage_event_id: string;
        request_id: string;
        tokens: number;
        cost: number;
      }>();
    expect(usageBefore).toBeTruthy();

    await env.DB.prepare(
      `UPDATE ai_request
       SET created_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-91 days')
       WHERE request_id = ?`,
    )
      .bind(requestId)
      .run();

    await runScheduled("0 3 * * *");

    expect(await count("ai_request", "request_id = ?", [requestId])).toBe(0);
    expect(await count("ai_attempt", "request_id = ?", [requestId])).toBe(0);
    expect(await r2Exists(`request/${requestId}/envelope`)).toBe(false);

    const usageAfter = await env.DB.prepare(
      "SELECT usage_event_id, request_id, tokens, cost FROM usage_event WHERE usage_event_id = ?",
    )
      .bind(usageBefore!.usage_event_id)
      .first<{
        usage_event_id: string;
        request_id: string | null;
        tokens: number;
        cost: number;
      }>();
    expect(usageAfter?.request_id).toBeNull();
    expect(usageAfter?.tokens).toBe(usageBefore?.tokens);
    expect(usageAfter?.cost).toBe(usageBefore?.cost);

    const clientGet = await getRequest(token, ref);
    expect(clientGet.status).toBe(404);

    const lookup = await vendorSupportLookup({ reference: ref });
    expect(lookup.status).toBe(404);
    const lookupBody = lookup.json as { error?: string };
    expect(lookupBody.error).toBe("not_found");
  });

  it("SYS-8.2 — Usage rollup upsert", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);

    await invoke(scenario);
    await invoke(scenario);
    await flushBackgroundWork();

    const usageTotals = await env.DB.prepare(
      `SELECT COUNT(*) AS request_count, SUM(tokens) AS tokens, SUM(cost) AS cost
       FROM usage_event WHERE installation_id = ? AND period = ?`,
    )
      .bind(
        scenario.installationId,
        periodFromEntitleStart(DEFAULT_ENTITLE_PAYLOAD.period_start),
      )
      .first<{
        request_count: number;
        tokens: number;
        cost: number;
      }>();

    await runScheduled("0 4 * * *");

    const rollup = await env.DB.prepare(
      "SELECT rollup_id, dimensions, request_count, tokens, cost FROM usage_rollup",
    ).all<{
      rollup_id: string;
      dimensions: string;
      request_count: number;
      tokens: number;
      cost: number;
    }>();
    expect(rollup.results?.length).toBeGreaterThanOrEqual(1);

    const match = (rollup.results ?? []).find((row) => {
      const dimensions = JSON.parse(row.dimensions) as {
        installation_id?: string;
        period?: string;
      };
      return (
        dimensions.installation_id === scenario.installationId &&
        dimensions.period ===
          periodFromEntitleStart(DEFAULT_ENTITLE_PAYLOAD.period_start)
      );
    });
    expect(match).toBeTruthy();
    expect(match?.request_count).toBe(usageTotals?.request_count);
    expect(match?.tokens).toBe(usageTotals?.tokens);
    expect(match?.cost).toBe(usageTotals?.cost);

    const rollupCountBefore = rollup.results?.length ?? 0;
    await runScheduled("0 4 * * *");
    const rollupAfter = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM usage_rollup",
    ).first<{ c: number }>();
    expect(rollupAfter?.c).toBe(rollupCountBefore);
  });

  it("SYS-8.3 — Fallback admission uniqueness and */5 drain", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    await coverClinic(scenario);

    const mirror = await env.DB.prepare(
      `SELECT term_snapshot FROM coverage_mirror WHERE installation_id = ?`,
    )
      .bind(scenario.installationId)
      .first<{ term_snapshot: string }>();
    const termRef =
      typeof mirror?.term_snapshot === "string"
        ? (JSON.parse(mirror.term_snapshot) as { ref?: string }).ref ?? "term-sys83"
        : "term-sys83";

    const requestId = crypto.randomUUID();
    const idempotencyKey = "verify-fallback-1";
    const admittedAt = new Date().toISOString();

    await env.DB.prepare(
      `INSERT INTO fallback_admission (
         installation_id, idempotency_key, term_id, request_id, weight, admitted_at, state
       ) VALUES (?, ?, ?, ?, ?, ?, 'pending')`,
    )
      .bind(
        scenario.installationId,
        idempotencyKey,
        termRef,
        requestId,
        1,
        admittedAt,
      )
      .run();

    await env.DB.prepare(
      `INSERT INTO ai_request (
         request_id, request_reference, installation_id, actor_id, branch_id,
         capability_id, capability_version, prompt_artifact_hash, idempotency_key,
         trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
         payload_pointer, conversation_id, turn_ordinal
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL)`,
    )
      .bind(
        requestId,
        "FB83-0001",
        scenario.installationId,
        scenario.actorId,
        scenario.branchId,
        "clinic.visit_summary",
        "1.0.0",
        "prompt/fb83@v1",
        idempotencyKey,
        "01FB83000000000000000001",
        "Accepted",
        admittedAt,
        admittedAt,
      )
      .run();

    let duplicateRejected = false;
    try {
      await env.DB.prepare(
        `INSERT INTO fallback_admission (
           installation_id, idempotency_key, term_id, request_id, weight, admitted_at, state
         ) VALUES (?, ?, ?, ?, ?, ?, 'pending')`,
      )
        .bind(
          scenario.installationId,
          idempotencyKey,
          termRef,
          crypto.randomUUID(),
          1,
          admittedAt,
        )
        .run();
    } catch {
      duplicateRejected = true;
    }
    expect(duplicateRejected).toBe(true);

    await runScheduled("*/5 * * * *");

    const row = await env.DB.prepare(
      `SELECT state FROM fallback_admission WHERE request_id = ?`,
    )
      .bind(requestId)
      .first<{ state: string }>();

    expect(row?.state).toBe("settled");

    const pendingBefore = await count(
      "fallback_admission",
      "installation_id = ? AND state = 'pending'",
      [scenario.installationId],
    );
    await invoke(scenario);
    const pendingAfter = await count(
      "fallback_admission",
      "installation_id = ? AND state = 'pending'",
      [scenario.installationId],
    );
    expect(pendingAfter).toBe(pendingBefore);
  });

  it("SYS-8.4 — Rejection counters lower bound", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario);

    await env.DB.prepare(
      "UPDATE entitlement SET allowed_capabilities = '[]' WHERE installation_id = ?",
    )
      .bind(scenario.installationId)
      .run();
    clearConfigCache();

    const response = await invoke(scenario, { token });
    expect(response.status).toBe(403);
    expect(response.body?.code).toBe("forbidden_capability");

    await runScheduled("0 4 * * *");

    const counters = await queryAll<{
      counter_id: string;
      dimension_set: string;
      count: number;
    }>("SELECT counter_id, dimension_set, count FROM platform_counter");

    const match = counters.find((row) => {
      const dimensions = JSON.parse(row.dimension_set) as {
        error_code?: string;
      };
      return dimensions.error_code === "forbidden_capability";
    });
    expect(match).toBeTruthy();
    expect(match?.count).toBeGreaterThanOrEqual(1);
  });
});
