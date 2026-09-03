/**
 * Suite 8 — cron retention interplay (plan §4, SYS-8.1–SYS-8.4).
 */

import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  clearConfigCache,
  count,
  DEFAULT_ENTITLE_PAYLOAD,
  flushBackgroundWork,
  getAiRequest,
  getEntitlement,
  getRequest,
  invoke,
  mintAat,
  newScenario,
  operatorFetchRaw,
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

    const lookup = await operatorFetchRaw(
      `/control/support/lookup?reference=${encodeURIComponent(ref)}`,
    );
    expect(lookup.status).toBe(404);
    const lookupBody = (await lookup.json()) as { error?: string };
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

  it("SYS-8.3 — Grace queue reconciliation and uniqueness", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario);
    const jti = JSON.parse(
      atob(token.split(".")[1]!.replace(/-/g, "+").replace(/_/g, "/")),
    ) as { jti: string };

    const graceRequestId = crypto.randomUUID();
    const idempotencyKey = "verify-grace-1";
    const queuedAt = new Date().toISOString();

    const entitlement = await getEntitlement(scenario.installationId);
    const entitlementJson = JSON.stringify({
      plan: entitlement?.plan,
      period_bounds: {
        period_start: entitlement?.period_start,
        period_end: entitlement?.period_end,
      },
      request_quota: entitlement?.request_quota,
      token_cost_budget: {
        token_budget: entitlement?.token_budget,
        cost_budget: entitlement?.cost_budget,
      },
      allowed_capabilities: JSON.parse(
        String(entitlement?.allowed_capabilities ?? "[]"),
      ),
      soft_threshold: entitlement?.soft_threshold,
      status: entitlement?.status,
    });

    await env.DB.prepare(
      `INSERT INTO grace_admission_queue (
        grace_request_id, installation_id, idempotency_key, jti, request_reference,
        entitlement_json, usage_tokens, usage_cost, partial, queued_at,
        reconcile_attempts, reconcile_first_seen_at_ms, status
      ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, 0, NULL, 'pending')`,
    )
      .bind(
        graceRequestId,
        scenario.installationId,
        idempotencyKey,
        jti.jti,
        "GRCE-0001",
        entitlementJson,
        queuedAt,
      )
      .run();

    let duplicateRejected = false;
    try {
      await env.DB.prepare(
        `INSERT INTO grace_admission_queue (
          grace_request_id, installation_id, idempotency_key, jti, request_reference,
          entitlement_json, usage_tokens, usage_cost, partial, queued_at,
          reconcile_attempts, reconcile_first_seen_at_ms, status
        ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, 0, NULL, 'pending')`,
      )
        .bind(
          crypto.randomUUID(),
          scenario.installationId,
          idempotencyKey,
          jti.jti,
          "GRCE-0002",
          entitlementJson,
          queuedAt,
        )
        .run();
    } catch {
      duplicateRejected = true;
    }
    expect(duplicateRejected).toBe(true);

    await runScheduled("0 3 * * *");

    const row = await env.DB.prepare(
      `SELECT status, reconcile_attempts, reconcile_first_seen_at_ms,
              usage_tokens, usage_cost, partial
       FROM grace_admission_queue WHERE grace_request_id = ?`,
    )
      .bind(graceRequestId)
      .first<{
        status: string;
        reconcile_attempts: number;
        reconcile_first_seen_at_ms: number | null;
        usage_tokens: number | null;
        usage_cost: number | null;
        partial: number | null;
      }>();

    expect(row).toBeTruthy();
    const reconciled =
      row?.status === "reconciled" ||
      row?.status === "dropped" ||
      (row?.status === "pending" &&
        Number(row.reconcile_attempts) >= 1 &&
        row.reconcile_first_seen_at_ms != null);
    expect(reconciled).toBe(true);
    expect(row?.usage_tokens).toBeNull();
    expect(row?.usage_cost).toBeNull();
    expect(row?.partial).toBeNull();

    const healthyGrace = await count(
      "grace_admission_queue",
      "installation_id = ? AND status = 'pending'",
      [scenario.installationId],
    );
    await invoke(scenario);
    const healthyGraceAfter = await count(
      "grace_admission_queue",
      "installation_id = ? AND status = 'pending'",
      [scenario.installationId],
    );
    expect(healthyGraceAfter).toBe(healthyGrace);
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
