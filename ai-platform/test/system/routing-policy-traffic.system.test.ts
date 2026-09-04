/**
 * Suite 4 — routing policy traffic (plan §4, SYS-4.1–SYS-4.8).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  canary,
  clearConfigCache,
  count,
  enrollScenario,
  entitleScenario,
  fakePolicyDocument,
  fakePolicyTarget,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  getAiRequest,
  getRoutingPolicy,
  getR2Json,
  invoke,
  mintAat,
  newScenario,
  operatorFetch,
  POLICY_ID,
  publishPolicy,
  promote,
  registerVisitSummaryCapability,
  resetPlatformState,
  rollback,
  r2Exists,
  setupPromotedFakePolicy,
  terminalEventTypes,
} from "./harness";

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
});

function assertSseOrder(events: { event: string }[]): void {
  expect(events[0]?.event).toBe("accepted");
  const terminals = terminalEventTypes(events);
  expect(terminals).toHaveLength(1);
  const terminalIndex = events.findIndex((event) =>
    ["completed", "failed", "cancelled", "context_requested"].includes(
      event.event,
    ),
  );
  expect(events.slice(terminalIndex + 1)).toHaveLength(0);
}

async function insertProviderKillSwitch(providerId: string): Promise<void> {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO kill_switch (scope, target, active, changed_at, changed_by)
     VALUES ('provider', ?, 1, datetime('now'), 'system-test')`,
  )
    .bind(providerId)
    .run();
  clearConfigCache();
}

describe("routing policy traffic", () => {
  it("SYS-4.1 — Publish validation & immutability", async () => {
    const probePolicyId = "probe-publish";
    const version = "1";
    const validDocument = fakePolicyDocument(probePolicyId, version);
    const publishUrl = "/control/routing-policies/publish";

    const invalidJson = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}${publishUrl}`, {
        method: "POST",
        headers: {
          authorization: "Bearer test-operator-bearer-token",
          "content-type": "application/json",
        },
        body: "not-json",
      }),
    );
    expect(invalidJson.status).toBe(400);
    const invalidJsonBody = (await invalidJson.json()) as { error?: string };
    expect(invalidJsonBody.error).toBe("invalid_json");

    const missingDoc = await operatorFetch(publishUrl, {});
    expect(missingDoc.status).toBe(400);
    expect(missingDoc.json.error).toBe("missing_document");

    const nullDoc = await operatorFetch(publishUrl, { document: null });
    expect(nullDoc.status).toBe(400);
    expect(nullDoc.json.error).toBe("missing_document");

    const { policy_id: _policyId, ...missingPolicyIdDocument } = validDocument;
    const missingPolicyId = await operatorFetch(publishUrl, {
      document: missingPolicyIdDocument,
    });
    expect(missingPolicyId.status).toBe(400);
    expect(missingPolicyId.json.error).toBe("invalid_policy_identity");

    const stringVersion = await operatorFetch(publishUrl, {
      document: { ...validDocument, policy_version: "1" },
    });
    expect(stringVersion.status).toBe(400);
    expect(stringVersion.json.error).toBe("invalid_policy_identity");

    expect(await count("routing_policy")).toBe(0);
    expect(
      await r2Exists(`control/routing-policy/${probePolicyId}/${version}.json`),
    ).toBe(false);

    const legacyPublish = await SELF.fetch(
      new Request(
        `${GATEWAY_ORIGIN}/control/routing-policies/${probePolicyId}/versions/${version}/publish`,
        {
          method: "POST",
          headers: {
            authorization: "Bearer test-operator-bearer-token",
            "content-type": "application/json",
          },
          body: JSON.stringify({ document: validDocument }),
        },
      ),
    );
    expect(legacyPublish.status).toBe(404);

    const unreferencedPolicyId = "unreferenced-probe";
    const unreferencedDocument = fakePolicyDocument(unreferencedPolicyId, version);
    const unreferenced = await publishPolicy(
      unreferencedPolicyId,
      version,
      unreferencedDocument,
    );
    expect(unreferenced.status).toBe(200);
    expect(unreferenced.json.warnings).toEqual(["unreferenced_policy"]);
    expect(
      await r2Exists(
        `control/routing-policy/${unreferencedPolicyId}/${version}.json`,
      ),
    ).toBe(true);
    expect(
      await count("routing_policy", "policy_id = ? AND version = ?", [
        unreferencedPolicyId,
        version,
      ]),
    ).toBe(1);

    const first = await publishPolicy(probePolicyId, version, validDocument);
    expect(first.status).toBe(200);

    const pointer = `control/routing-policy/${probePolicyId}/${version}.json`;
    const storedBefore = await getR2Json(pointer);
    expect(storedBefore.policy_id).toBe(probePolicyId);

    const tampered = fakePolicyDocument(probePolicyId, version, {
      ruleId: "tampered-rule",
    });
    const duplicate = await publishPolicy(probePolicyId, version, tampered);
    expect(duplicate.status).toBe(409);
    expect(duplicate.json.error).toBe("already_published");

    const storedAfter = await getR2Json(pointer);
    expect(storedAfter.rules).toEqual(storedBefore.rules);
    expect(await count("routing_policy", "policy_id = ? AND version = ?", [
      probePolicyId,
      version,
    ])).toBe(1);
  });

  it("SYS-4.2 — Canary split two installations", async () => {
    const i0 = await newScenario();
    const i1 = await newScenario();
    await enrollScenario(i0);
    await enrollScenario(i1);
    expect((await entitleScenario(i0)).status).toBe(200);
    expect((await entitleScenario(i1)).status).toBe(200);

    const v1Document = fakePolicyDocument(POLICY_ID, "1", { ruleId: "active-v1" });
    const v2Document = fakePolicyDocument(POLICY_ID, "2", { ruleId: "canary-v2" });
    expect((await publishPolicy(POLICY_ID, "1", v1Document)).status).toBe(200);
    expect((await publishPolicy(POLICY_ID, "2", v2Document)).status).toBe(200);
    expect((await promote(POLICY_ID, "1")).status).toBe(200);
    expect((await canary(POLICY_ID, "2", [i0.installationId])).status).toBe(200);

    const i0Invoke = await invoke(i0);
    expect(i0Invoke.status).toBe(200);
    assertSseOrder(i0Invoke.events);
    const i0Ref = String(i0Invoke.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const i0Request = await getAiRequest(i0Ref);
    const i0Decision = JSON.parse(String(i0Request?.routing_decision)) as {
      policy_version?: number;
      rule_id?: string;
    };
    expect(i0Decision.policy_version).toBe(2);
    expect(i0Decision.rule_id).toBe("canary-v2");

    const i1Invoke = await invoke(i1);
    expect(i1Invoke.status).toBe(200);
    assertSseOrder(i1Invoke.events);
    const i1Ref = String(i1Invoke.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const i1Request = await getAiRequest(i1Ref);
    const i1Decision = JSON.parse(String(i1Request?.routing_decision)) as {
      policy_version?: number;
      rule_id?: string;
    };
    expect(i1Decision.policy_version).toBe(1);
    expect(i1Decision.rule_id).toBe("active-v1");
  });

  it("SYS-4.3 — Promote & rollback semantics", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);

    const v1Document = fakePolicyDocument(POLICY_ID, "1");
    const v2Document = fakePolicyDocument(POLICY_ID, "2", { ruleId: "promoted-v2" });
    await publishPolicy(POLICY_ID, "1", v1Document);
    await publishPolicy(POLICY_ID, "2", v2Document);
    await promote(POLICY_ID, "1");
    await canary(POLICY_ID, "2", [scenario.installationId]);

    const promoted = await promote(POLICY_ID, "2");
    expect(promoted.status).toBe(200);

    const v2Row = await getRoutingPolicy(POLICY_ID, "2");
    const v1Row = await getRoutingPolicy(POLICY_ID, "1");
    expect(v2Row?.status).toBe("active");
    expect(v2Row?.canary_installation_ids).toBeNull();
    expect(v1Row?.status).toBe("superseded");

    const canaryOnActive = await canary(POLICY_ID, "2", [scenario.installationId]);
    expect(canaryOnActive.status).toBe(409);
    expect(canaryOnActive.json.error).toBe("illegal_policy_transition");

    const rolledBack = await rollback(POLICY_ID, "2");
    expect(rolledBack.status).toBe(200);
    expect((await getRoutingPolicy(POLICY_ID, "1"))?.status).toBe("active");
    expect((await getRoutingPolicy(POLICY_ID, "2"))?.status).toBe("superseded");

    await env.DB.prepare(
      "UPDATE routing_policy SET status = 'published' WHERE policy_id = ? AND version = '2'",
    )
      .bind(POLICY_ID)
      .run();
    clearConfigCache();

    const rollbackNoSuperseded = await rollback(POLICY_ID, "1");
    expect(rollbackNoSuperseded.status).toBe(409);
    expect(rollbackNoSuperseded.json.error).toBe("illegal_policy_transition");
  });

  it("SYS-4.4 — Version tie-break", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);

    const baseDocument = fakePolicyDocument(POLICY_ID, "1");
    for (const version of ["9", "10", "11"]) {
      const document = {
        ...baseDocument,
        policy_version: Number(version),
        rules: [
          {
            ...(baseDocument.rules as Record<string, unknown>[])[0],
            rule_id: `tie-break-v${version}`,
          },
        ],
      };
      expect((await publishPolicy(POLICY_ID, version, document)).status).toBe(200);
    }

    const equalActiveFrom = "2026-08-03T12:00:00.000Z";
    await env.DB.prepare(
      `UPDATE routing_policy
       SET active_from = ?
       WHERE policy_id = ? AND version IN ('9', '10', '11')`,
    )
      .bind(equalActiveFrom, POLICY_ID)
      .run();
    await env.DB.prepare(
      `UPDATE routing_policy SET status = 'superseded'
       WHERE policy_id = ? AND version IN ('9', '10')`,
    )
      .bind(POLICY_ID)
      .run();
    await env.DB.prepare(
      `UPDATE routing_policy SET status = 'active'
       WHERE policy_id = ? AND version = '11'`,
    )
      .bind(POLICY_ID)
      .run();
    clearConfigCache();

    const rolledBack = await rollback(POLICY_ID, "11");
    expect(rolledBack.status).toBe(200);

    const activeRow = await env.DB.prepare(
      "SELECT version, status FROM routing_policy WHERE policy_id = ? AND status = 'active'",
    )
      .bind(POLICY_ID)
      .first<{ version: string; status: string }>();
    expect(activeRow?.version).toBe("10");
    expect(activeRow?.status).toBe("active");

    const supersededNine = await getRoutingPolicy(POLICY_ID, "9");
    expect(supersededNine?.status).toBe("superseded");
  });

  it("SYS-4.5 — Missing R2 document", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);

    const policy = await getRoutingPolicy(POLICY_ID, "1");
    const pointer = String(policy?.content_pointer);
    const backup = JSON.stringify(await getR2Json(pointer));

    await env.R2.delete(pointer);
    clearConfigCache();

    const invoked = await invoke(scenario);
    expect(invoked.status).toBe(200);
    assertSseOrder(invoked.events);
    expect(invoked.events[1]?.event).toBe("failed");
    expect(invoked.events[1]?.data.code).toBe("internal_error");

    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const request = await getAiRequest(ref);
    expect(request?.routing_decision).toBeNull();

    await env.R2.put(pointer, backup, {
      httpMetadata: { contentType: "application/json" },
    });
    clearConfigCache();
    expect(await r2Exists(pointer)).toBe(true);
  });

  it("SYS-4.6 — Fail-closed target filters", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);

    async function promoteAndInvoke(
      document: Record<string, unknown>,
      version: string,
    ): Promise<ReturnType<typeof invoke>> {
      await publishPolicy(POLICY_ID, version, document);
      await promote(POLICY_ID, version);
      return invoke(scenario);
    }

    const undersizedDocument = fakePolicyDocument(POLICY_ID, "20", {
      targets: [fakePolicyTarget("fake-v1", { minContextWindow: 1_000 })],
    });
    const undersized = await promoteAndInvoke(undersizedDocument, "20");
    expect(undersized.events[1]?.event).toBe("failed");
    expect(undersized.events[1]?.data.code).toBe("provider_unavailable");
    const undersizedRef = String(undersized.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const undersizedDecision = JSON.parse(
      String((await getAiRequest(undersizedRef))?.routing_decision),
    ) as { chain?: unknown[]; excluded?: Array<{ reason_code?: string }> };
    expect(undersizedDecision.chain).toEqual([]);
    expect(undersizedDecision.excluded?.[0]?.reason_code).toBe(
      "context_window_too_small",
    );

    const malformedLanguagesDocument = fakePolicyDocument(POLICY_ID, "21", {
      targets: [
        fakePolicyTarget("bogus-malformed", {
          providerId: "bogus-malformed",
          languages: "en" as unknown as string[],
        }),
        fakePolicyTarget("fake-v1"),
      ],
    });
    const malformed = await promoteAndInvoke(malformedLanguagesDocument, "21");
    expect(malformed.events.some((event) => event.event === "completed")).toBe(true);
    const malformedRef = String(malformed.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const malformedDecision = JSON.parse(
      String((await getAiRequest(malformedRef))?.routing_decision),
    ) as { excluded?: Array<{ reason_code?: string }> };
    expect(
      malformedDecision.excluded?.some(
        (entry) => entry.reason_code === "feature_unsupported",
      ),
    ).toBe(true);

    const latencyDocument = fakePolicyDocument(POLICY_ID, "22", {
      targets: [fakePolicyTarget("fake-v1", { latencyClass: "interactive" })],
    });
    const latency = await promoteAndInvoke(latencyDocument, "22");
    expect(latency.events[1]?.data.code).toBe("provider_unavailable");
    const latencyRef = String(latency.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const latencyDecision = JSON.parse(
      String((await getAiRequest(latencyRef))?.routing_decision),
    ) as { excluded?: Array<{ reason_code?: string }> };
    expect(
      latencyDecision.excluded?.some(
        (entry) => entry.reason_code === "feature_unsupported",
      ),
    ).toBe(true);

    const premiumCostDocument = fakePolicyDocument(POLICY_ID, "23", {
      targets: [fakePolicyTarget("fake-v1", { costClass: "premium" })],
    });
    const premiumCost = await promoteAndInvoke(premiumCostDocument, "23");
    expect(premiumCost.events[1]?.data.code).toBe("provider_unavailable");
    const premiumRef = String(premiumCost.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const premiumDecision = JSON.parse(
      String((await getAiRequest(premiumRef))?.routing_decision),
    ) as { excluded?: Array<{ reason_code?: string }> };
    expect(
      premiumDecision.excluded?.some(
        (entry) => entry.reason_code === "cost_class_excluded",
      ),
    ).toBe(true);
  });

  it("SYS-4.7 — Overrides & exclusions", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);

    const excludeDocument = fakePolicyDocument(POLICY_ID, "30", {
      overrides: [
        {
          installation_id: scenario.installationId,
          exclude_providers: ["fake"],
        },
      ],
    });
    await publishPolicy(POLICY_ID, "30", excludeDocument);
    await promote(POLICY_ID, "30");

    const excluded = await invoke(scenario);
    expect(excluded.events[1]?.event).toBe("failed");
    expect(excluded.events[1]?.data.code).toBe("provider_unavailable");
    const excludedRef = String(excluded.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const excludedDecision = JSON.parse(
      String((await getAiRequest(excludedRef))?.routing_decision),
    ) as { chain?: unknown[]; excluded?: Array<{ reason_code?: string }> };
    expect(excludedDecision.chain).toEqual([]);
    expect(
      excludedDecision.excluded?.some(
        (entry) => entry.reason_code === "installation_excluded",
      ),
    ).toBe(true);

    const forceCostDocument = fakePolicyDocument(POLICY_ID, "31", {
      targets: [fakePolicyTarget("fake-v1", { costClass: "economy" })],
      overrides: [
        {
          installation_id: scenario.installationId,
          force_cost_class: "economy",
        },
        {
          installation_id: scenario.installationId,
          exclude_providers: ["fake"],
        },
      ],
    });
    await publishPolicy(POLICY_ID, "31", forceCostDocument);
    await promote(POLICY_ID, "31");

    const forced = await invoke(scenario);
    expect(forced.events.some((event) => event.event === "completed")).toBe(true);
    const forcedRef = String(forced.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const forcedDecision = JSON.parse(
      String((await getAiRequest(forcedRef))?.routing_decision),
    ) as { cost_class_source?: string };
    expect(forcedDecision.cost_class_source).toBe("installation_override");
  });

  it("SYS-4.8 — Provider kill-switch failover", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);

    const failoverDocument = fakePolicyDocument(POLICY_ID, "40", {
      targets: [
        fakePolicyTarget("deepseek-v4-flash", { providerId: "deepseek" }),
        fakePolicyTarget("fake-v1"),
      ],
    });
    await publishPolicy(POLICY_ID, "40", failoverDocument);
    await promote(POLICY_ID, "40");
    await insertProviderKillSwitch("deepseek");

    const failover = await invoke(scenario);
    expect(failover.status).toBe(200);
    assertSseOrder(failover.events);
    expect(failover.events.some((event) => event.event === "completed")).toBe(true);
    const failoverRef = String(failover.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const failoverDecision = JSON.parse(
      String((await getAiRequest(failoverRef))?.routing_decision),
    ) as {
      chain?: Array<{ provider_id?: string }>;
      excluded?: Array<{ provider_id?: string; reason_code?: string }>;
    };
    expect(failoverDecision.chain?.[0]?.provider_id).toBe("fake");
    expect(
      failoverDecision.excluded?.some(
        (entry) =>
          entry.provider_id === "deepseek" && entry.reason_code === "kill_switch",
      ),
    ).toBe(true);

    await env.DB.prepare(
      "DELETE FROM kill_switch WHERE scope = 'provider' AND target = 'deepseek'",
    ).run();
    await insertProviderKillSwitch("fake");

    const fakeKilled = await invoke(scenario);
    expect(fakeKilled.status).toBe(503);
    expect(fakeKilled.body?.code).toBe("capability_disabled");
    expect(fakeKilled.events).toHaveLength(0);
  });
});
