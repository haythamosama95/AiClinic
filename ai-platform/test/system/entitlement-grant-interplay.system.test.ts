/**
 * Suite 3 — entitlement-grant interplay (plan §4, SYS-3.1–SYS-3.5).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clearConfigCache,
  count,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollScenario,
  entitleScenario,
  fakePolicyDocument,
  getCapabilities,
  getEntitlement,
  getGrants,
  invoke,
  mintAat,
  newScenario,
  operatorFetch,
  OPERATOR_BEARER,
  POLICY_ID,
  POLICY_VERSION,
  promote,
  publishPolicy,
  registerVisitSummaryCapability,
  GATEWAY_ORIGIN,
  resetPlatformState,
  setupPromotedFakePolicy,
  type EntitlePayload,
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

async function d1Run(sql: string, ...params: unknown[]): Promise<void> {
  await env.DB.prepare(sql).bind(...params).run();
  clearConfigCache();
}

async function restoreEntitlementBaseline(scenario: Scenario): Promise<void> {
  await d1Run(
    `UPDATE entitlement
     SET allowed_capabilities = ?, plan = 'standard', status = 'active'
     WHERE installation_id = ?`,
    JSON.stringify([CAPABILITY_ID]),
    scenario.installationId,
  );
  for (const scope of [
    `installation:${scenario.installationId}`,
    "plan:standard",
  ]) {
    const existing = await env.DB.prepare(
      `SELECT grant_id FROM capability_grant
       WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL`,
    )
      .bind(scope, CAPABILITY_ID)
      .first<{ grant_id: string }>();
    if (!existing) {
      await d1Run(
        `INSERT INTO capability_grant (
           grant_id, scope, capability_id, capability_version,
           granted_at, revoked_at, changed_at, changed_by
         ) VALUES (?, ?, ?, ?, datetime('now'), NULL, datetime('now'), 'restore')`,
        crypto.randomUUID(),
        scope,
        CAPABILITY_ID,
        CAPABILITY_VERSION,
      );
    } else {
      await d1Run(
        `UPDATE capability_grant SET capability_version = ?
         WHERE grant_id = ?`,
        CAPABILITY_VERSION,
        existing.grant_id,
      );
    }
  }
  clearConfigCache();
}

async function assertInvokeBaselinePasses(scenario: Scenario): Promise<void> {
  const token = await mintAat(scenario);
  const invoked = await invoke(scenario, { token });
  expect(invoked.status).toBe(200);
  expect(invoked.events[0]?.event).toBe("accepted");
  expect(invoked.events.some((event) => event.event === "completed")).toBe(true);
}

async function assertForbiddenCapability(
  scenario: Scenario,
  opts: { capabilityVersion?: string } = {},
): Promise<void> {
  const before = await count("ai_request");
  const token = await mintAat(scenario, { role: "clinician", scopes: ["ai.visit_summary", "ai.access"] });
  const invoked = await invoke(scenario, {
    token,
    capabilityVersion: opts.capabilityVersion,
  });
  expect(invoked.status).toBe(403);
  expect(invoked.body?.code).toBe("forbidden_capability");
  expect(invoked.body?.retry_safe).toBe(false);
  expect(await count("ai_request")).toBe(before);
}

describe("entitlement-grant interplay", () => {
  it("SYS-3.1 — Independent switches matrix", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    await assertInvokeBaselinePasses(scenario);

    await d1Run(
      `UPDATE entitlement SET allowed_capabilities = '[]' WHERE installation_id = ?`,
      scenario.installationId,
    );
    await assertForbiddenCapability(scenario);
    await restoreEntitlementBaseline(scenario);
    await assertInvokeBaselinePasses(scenario);

    await d1Run(
      `DELETE FROM capability_grant
       WHERE scope = ? OR scope = 'plan:standard'`,
      `installation:${scenario.installationId}`,
    );
    await assertForbiddenCapability(scenario);
    await restoreEntitlementBaseline(scenario);
    await assertInvokeBaselinePasses(scenario);

    const token = await mintAat(scenario, {
      role: "clinician",
      scopes: ["ai.visit_summary", "ai.access"],
    });
    const versionMismatch = await invoke(scenario, {
      token,
      capabilityVersion: "9.9.9",
    });
    expect(versionMismatch.status).toBe(403);
    expect(versionMismatch.body?.code).toBe("forbidden_capability");
    expect(versionMismatch.body?.retry_safe).toBe(false);

    await d1Run(
      `UPDATE capability_grant SET capability_version = '9.9.9'
       WHERE capability_id = ? AND revoked_at IS NULL`,
      CAPABILITY_ID,
    );
    const beforeUnknown = await count("ai_request");
    const unknownVersion = await invoke(scenario, {
      token,
      capabilityVersion: "9.9.9",
    });
    expect(unknownVersion.status).toBe(404);
    expect(unknownVersion.body?.code).toBe("capability_unknown");
    expect(unknownVersion.body?.retry_safe).toBe(false);
    expect(await count("ai_request")).toBe(beforeUnknown);
    await restoreEntitlementBaseline(scenario);
    await assertInvokeBaselinePasses(scenario);

    await d1Run(
      `UPDATE entitlement SET plan = 'starter' WHERE installation_id = ?`,
      scenario.installationId,
    );
    await assertForbiddenCapability(scenario);
    await d1Run(
      `UPDATE entitlement SET plan = 'verify' WHERE installation_id = ?`,
      scenario.installationId,
    );
    await assertForbiddenCapability(scenario);
    await restoreEntitlementBaseline(scenario);
    await assertInvokeBaselinePasses(scenario);

    await d1Run(
      `UPDATE entitlement SET status = 'suspended' WHERE installation_id = ?`,
      scenario.installationId,
    );
    await assertForbiddenCapability(scenario);
    await restoreEntitlementBaseline(scenario);
    await assertInvokeBaselinePasses(scenario);
  });

  it("SYS-3.2 — Role & scope enforcement", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);

    const doctorNoScope = await mintAat(scenario, {
      role: "doctor",
      scopes: ["ai.access"],
    });
    const missingScope = await invoke(scenario, { token: doctorNoScope });
    expect(missingScope.status).toBe(403);
    expect(missingScope.body?.code).toBe("forbidden_capability");
    expect(missingScope.body?.retry_safe).toBe(false);

    const doctorWithScope = await mintAat(scenario, {
      role: "doctor",
      scopes: ["ai.visit_summary", "ai.access"],
    });
    const wrongRole = await invoke(scenario, { token: doctorWithScope });
    expect(wrongRole.status).toBe(403);
    expect(wrongRole.body?.code).toBe("forbidden_capability");
    expect(wrongRole.body?.retry_safe).toBe(false);

    const clinician = await mintAat(scenario, {
      role: "clinician",
      scopes: ["ai.visit_summary", "ai.access"],
    });
    const passing = await invoke(scenario, { token: clinician });
    expect(passing.status).toBe(200);
    expect(passing.events[0]?.event).toBe("accepted");
    expect(passing.events.some((event) => event.event === "completed")).toBe(true);
  });

  it("SYS-3.3 — Kill-switch scopes vs discovery/invoke", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario, {
      role: "clinician",
      scopes: ["ai.visit_summary", "ai.access"],
    });

    const noHttpWriter = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/control/kill-switch`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${OPERATOR_BEARER}`,
          "content-type": "application/json",
        },
        body: "{}",
      }),
    );
    expect(noHttpWriter.status).toBe(404);

    const scopes: Array<{ scope: string; target: string }> = [
      { scope: "installation", target: scenario.installationId },
      { scope: "capability", target: CAPABILITY_ID },
      { scope: "global", target: "global" },
    ];

    for (const killSwitch of scopes) {
      await d1Run(
        `INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
         VALUES (?, ?, 1, datetime('now'), 'system-test')`,
        killSwitch.scope,
        killSwitch.target,
      );

      const caps = await getCapabilities(token);
      expect(caps.status).toBe(200);
      const manifests = caps.body?.manifests as Array<{ Identity?: { capabilityId?: string } }>;
      expect(manifests?.map((m) => m.Identity?.capabilityId)).toContain(CAPABILITY_ID);

      const before = await count("ai_request");
      const disabled = await invoke(scenario, { token });
      expect(disabled.status).toBe(503);
      expect(disabled.body?.code).toBe("capability_disabled");
      expect(disabled.body?.retry_safe).toBe(true);
      expect(await count("ai_request")).toBe(before);

      await d1Run(
        `DELETE FROM kill_switch WHERE scope = ? AND target = ?`,
        killSwitch.scope,
        killSwitch.target,
      );
    }

    const restored = await invoke(scenario, { token });
    expect(restored.status).toBe(200);
    expect(restored.events.some((event) => event.event === "completed")).toBe(true);
  });

  it("SYS-3.4 — Entitle does not overreach", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);

    const entitlementBefore = await getEntitlement(scenario.installationId);
    const planBefore = String(entitlementBefore?.plan);
    const routingPoliciesBefore = await count("routing_policy");

    const entitled = await entitleScenario(scenario);
    expect(entitled.status).toBe(200);
    expect(entitled.json.status).toBe("active");
    expect(entitled.json).not.toHaveProperty("token");
    expect(entitled.json).not.toHaveProperty("access_token");

    expect(await count("routing_policy")).toBe(routingPoliciesBefore);

    const installation = await env.DB.prepare(
      "SELECT status FROM installation WHERE installation_id = ?",
    )
      .bind(scenario.installationId)
      .first<{ status: string }>();
    expect(installation?.status).toBe("active");

    const entitlementAfter = await getEntitlement(scenario.installationId);
    expect(entitlementAfter?.plan).toBe(planBefore);
    expect(entitlementAfter?.status).toBe("active");
  });

  it("SYS-3.5 — Entitlement uniqueness & validation", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);

    const entitlement = await getEntitlement(scenario.installationId);
    expect(entitlement).toBeTruthy();

    await expect(
      env.DB.prepare(
        `INSERT INTO entitlement (
           entitlement_id, installation_id, plan, period_start, period_end,
           request_quota, token_budget, cost_budget, allowed_capabilities,
           soft_threshold, status
         ) VALUES (?, ?, 'standard', ?, ?, 0, 0, 0, '[]', 0, 'pending')`,
      ).bind(
        crypto.randomUUID(),
        scenario.installationId,
        DEFAULT_ENTITLE_PAYLOAD.period_start,
        DEFAULT_ENTITLE_PAYLOAD.period_end,
      ).run(),
    ).rejects.toThrow();

    expect(await count("entitlement", "installation_id = ?", [scenario.installationId])).toBe(1);

    const unknownInstall = await operatorFetch(
      `/control/installations/${crypto.randomUUID()}/entitle`,
      DEFAULT_ENTITLE_PAYLOAD as unknown as Record<string, unknown>,
    );
    expect(unknownInstall.status).toBe(404);
    expect(unknownInstall.json.error).toBe("installation_not_found");

    const invalidCases: Array<{ label: string; payload: EntitlePayload }> = [
      {
        label: "non-ISO period_start",
        payload: { ...DEFAULT_ENTITLE_PAYLOAD, period_start: "not-an-iso-instant" },
      },
      {
        label: "date-only period_start",
        payload: { ...DEFAULT_ENTITLE_PAYLOAD, period_start: "2026-08-01" },
      },
      {
        label: "non-ISO period_end",
        payload: { ...DEFAULT_ENTITLE_PAYLOAD, period_end: "tomorrow" },
      },
      {
        label: "period_start == period_end",
        payload: {
          ...DEFAULT_ENTITLE_PAYLOAD,
          period_start: "2026-08-01T00:00:00.000Z",
          period_end: "2026-08-01T00:00:00.000Z",
        },
      },
      {
        label: "period_start > period_end",
        payload: {
          ...DEFAULT_ENTITLE_PAYLOAD,
          period_start: "2026-09-01T00:00:00.000Z",
          period_end: "2026-08-01T00:00:00.000Z",
        },
      },
      {
        label: "negative request_quota",
        payload: { ...DEFAULT_ENTITLE_PAYLOAD, request_quota: -1 },
      },
      {
        label: "fractional request_quota",
        payload: { ...DEFAULT_ENTITLE_PAYLOAD, request_quota: 1.5 as unknown as number },
      },
      {
        label: "negative token_budget",
        payload: { ...DEFAULT_ENTITLE_PAYLOAD, token_budget: -1 },
      },
      {
        label: "negative cost_budget",
        payload: { ...DEFAULT_ENTITLE_PAYLOAD, cost_budget: -1 },
      },
      {
        label: "soft_threshold out of range",
        payload: { ...DEFAULT_ENTITLE_PAYLOAD, soft_threshold: 1.5 },
      },
      {
        label: "allowed_capabilities not string[]",
        payload: {
          ...DEFAULT_ENTITLE_PAYLOAD,
          allowed_capabilities: [1] as unknown as string[],
        },
      },
      {
        label: "empty grants",
        payload: { ...DEFAULT_ENTITLE_PAYLOAD, grants: [] },
      },
      {
        label: "global grant scope",
        payload: {
          ...DEFAULT_ENTITLE_PAYLOAD,
          grants: [
            {
              capability_id: CAPABILITY_ID,
              capability_version: CAPABILITY_VERSION,
              scope: "global" as "installation",
            },
          ],
        },
      },
    ];

    for (const { payload } of invalidCases) {
      const result = await entitleScenario(scenario, payload);
      expect(result.status).toBe(400);
      expect(result.json.error).toBe("invalid_payload");

      const row = await getEntitlement(scenario.installationId);
      expect(row?.status).toBe("pending");
      expect(await getGrants(`installation:${scenario.installationId}`)).toHaveLength(0);
    }
  });

  it("SYS-3.6 — Multi-installation same-plan entitle", async () => {
    const i0 = await newScenario();
    const i1 = await newScenario();
    await enrollScenario(i0);
    await enrollScenario(i1);

    expect((await entitleScenario(i0, DEFAULT_ENTITLE_PAYLOAD)).status).toBe(200);
    expect((await entitleScenario(i1, DEFAULT_ENTITLE_PAYLOAD)).status).toBe(200);

    const livePlanGrants = await env.DB.prepare(
      `SELECT grant_id FROM capability_grant
       WHERE scope = 'plan:standard' AND capability_id = ? AND revoked_at IS NULL`,
    )
      .bind(CAPABILITY_ID)
      .all<{ grant_id: string }>();
    expect(livePlanGrants.results?.length).toBe(1);

    const liveI0 = (await getGrants(`installation:${i0.installationId}`)).filter(
      (grant) => grant.revoked_at === null,
    );
    const liveI1 = (await getGrants(`installation:${i1.installationId}`)).filter(
      (grant) => grant.revoked_at === null,
    );
    expect(liveI0).toHaveLength(1);
    expect(liveI1).toHaveLength(1);

    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    expect((await publishPolicy(POLICY_ID, POLICY_VERSION, document)).status).toBe(200);
    expect((await promote(POLICY_ID, POLICY_VERSION)).status).toBe(200);

    for (const scenario of [i0, i1]) {
      const token = await mintAat(scenario, {
        role: "clinician",
        scopes: ["ai.visit_summary", "ai.access"],
      });
      const result = await invoke(scenario, { token });
      expect(result.status).toBe(200);
      expect(result.events[0]?.event).toBe("accepted");
      expect(result.events.some((event) => event.event === "completed")).toBe(true);
    }
  });
});
