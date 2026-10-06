/**
 * P3.10 — Control-plane port to VendorEntrypoint (E2E-P3.10-01…07).
 */

import { env, SELF } from "cloudflare:test";
import wranglerToml from "../../wrangler.toml?raw";
import { subscriptionRef } from "vendor-contracts";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clearConfigCache,
  coverClinic,
  fakePolicyDocument,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  getAiRequest,
  getCapabilities,
  getRoutingPolicy,
  invoke,
  mintAat,
  mintVendorAccessJwt,
  newClinic,
  newScenario,
  POLICY_ID,
  registerVisitSummaryCapability,
  resetPlatformState,
  r2Exists,
  runScheduled,
  setupPromotedFakePolicy,
  setupVendorHarness,
  vendorCall,
  VENDOR_OPERATOR_EMAIL,
  type VendorResultEnvelope,
} from "./harness";

const INSTALLATION_ID = "11111111-1111-4111-8111-111111111111";

type P310VendorMethod =
  | "publishRoutingPolicy"
  | "canaryRoutingPolicy"
  | "promoteRoutingPolicy"
  | "armKillSwitch"
  | "deprecateCapability"
  | "retireCapability"
  | "beginTokenContractRotation"
  | "supportLookup";

const p310VendorCall = vendorCall as (
  method: P310VendorMethod,
  args: Record<string, unknown>,
  opts?: { accessJwt?: string; assertion?: Record<string, unknown> },
) => Promise<VendorResultEnvelope>;

function expectClassHOk(envelope: VendorResultEnvelope): Record<string, unknown> {
  expect(envelope.result).toBe("ok");
  expect(envelope.code).toBe("");
  expect(envelope).not.toHaveProperty("receipt");
  expect(envelope.detail.length).toBeGreaterThan(0);
  return JSON.parse(envelope.detail) as Record<string, unknown>;
}

async function controlPost(path: string): Promise<Response> {
  return SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    }),
  );
}

async function controlGet(path: string): Promise<Response> {
  return SELF.fetch(new Request(`${GATEWAY_ORIGIN}${path}`, { method: "GET" }));
}

function triggerCrons(): string[] {
  const match = wranglerToml.match(
    /\[triggers\][\s\S]*?crons\s*=\s*\[([^\]]+)\]/u,
  )?.[1];
  if (!match) {
    throw new Error("wrangler.toml [triggers].crons not found");
  }
  return [...match.matchAll(/"([^"]+)"/gu)].map((entry) => entry[1]!);
}

function formerControlPaths(): string[] {
  const cap = CAPABILITY_ID;
  const ver = CAPABILITY_VERSION;
  const policy = POLICY_ID;
  const policyVer = "1";
  const planId = "probe-plan";
  return [
    `/control/installations/${INSTALLATION_ID}/suspend`,
    `/control/installations/${INSTALLATION_ID}/resume`,
    `/control/installations/${INSTALLATION_ID}/delete`,
    `/control/installations/${INSTALLATION_ID}/purge`,
    `/control/installations/${INSTALLATION_ID}/entitle`,
    `/control/installations/${INSTALLATION_ID}/override`,
    `/control/capabilities/${cap}/versions/${ver}/deprecate`,
    `/control/capabilities/${cap}/versions/${ver}/retire`,
    `/control/capabilities/${cap}/versions/${ver}/activate`,
    `/control/capabilities/${cap}/versions/${ver}/promote`,
    "/control/routing-policies/publish",
    `/control/routing-policies/${policy}/versions/${policyVer}/canary`,
    `/control/routing-policies/${policy}/versions/${policyVer}/promote`,
    `/control/routing-policies/${policy}/versions/${policyVer}/rollback`,
    "/control/token-contract/begin-rotation",
    "/control/token-contract/retire",
    "/control/support/lookup",
    "/control/kill-switches/arm",
    "/control/kill-switches/disarm",
    "/control/plans/create",
    `/control/plans/${planId}/update`,
    `/control/plans/${planId}/delete`,
    "/control/credit-price/activate",
  ];
}

function manifestLifecycle(
  body: Record<string, unknown> | null,
  capabilityId: string,
): string | undefined {
  const manifests = body?.manifests as Array<{
    Identity?: { capabilityId?: string; lifecycleState?: string };
  }>;
  return manifests?.find((entry) => entry.Identity?.capabilityId === capabilityId)
    ?.Identity?.lifecycleState;
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
});

describe("P3.10 control-plane port", () => {
  it("E2E-P3.10-01 former /control paths are 404 and the worker boots without the bearer", async () => {
    Reflect.deleteProperty(env as object, "OPERATOR_BEARER_TOKEN");
    expect("OPERATOR_BEARER_TOKEN" in env).toBe(false);

    const bootProbe = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, { method: "GET" }),
    );
    expect(bootProbe.status).toBeGreaterThanOrEqual(400);
    expect(bootProbe.status).toBeLessThan(500);

    for (const path of formerControlPaths()) {
      const response = await controlPost(path);
      expect(response.status).toBe(404);
    }

    const quota = await controlGet(
      `/control/installations/${INSTALLATION_ID}/quota`,
    );
    expect(quota.status).toBe(404);
  });

  it("E2E-P3.10-02 routing policy publish canary promote and traffic follows", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const accessJwt = await mintVendorAccessJwt();

    const v1Document = fakePolicyDocument(POLICY_ID, "1", { ruleId: "active-v1" });
    const v2Document = fakePolicyDocument(POLICY_ID, "2", { ruleId: "promoted-v2" });

    expectClassHOk(
      await p310VendorCall(
        "publishRoutingPolicy",
        { document: v1Document },
        { accessJwt },
      ),
    );
    expectClassHOk(
      await p310VendorCall(
        "publishRoutingPolicy",
        { document: v2Document },
        { accessJwt },
      ),
    );
    expectClassHOk(
      await p310VendorCall(
        "promoteRoutingPolicy",
        { policy_id: POLICY_ID, version: "1" },
        { accessJwt },
      ),
    );
    expectClassHOk(
      await p310VendorCall(
        "canaryRoutingPolicy",
        {
          policy_id: POLICY_ID,
          version: "2",
          installation_ids: [scenario.installationId],
        },
        { accessJwt },
      ),
    );
    expectClassHOk(
      await p310VendorCall(
        "promoteRoutingPolicy",
        { policy_id: POLICY_ID, version: "2" },
        { accessJwt },
      ),
    );

    clearConfigCache();

    const v2Row = await getRoutingPolicy(POLICY_ID, "2");
    const v1Row = await getRoutingPolicy(POLICY_ID, "1");
    expect(v2Row?.status).toBe("active");
    expect(v1Row?.status).toBe("superseded");

    const invoked = await invoke(scenario);
    expect(invoked.status).toBe(200);
    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();
    const request = await getAiRequest(ref);
    const decision = JSON.parse(String(request?.routing_decision)) as {
      policy_version?: number;
      rule_id?: string;
    };
    expect(decision.policy_version).toBe(2);
    expect(decision.rule_id).toBe("promoted-v2");
  });

  it("E2E-P3.10-03 kill switch answers capability_disabled and raises AL-19", async () => {
    await setupVendorHarness();
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const accessJwt = await mintVendorAccessJwt();

    expectClassHOk(
      await p310VendorCall(
        "armKillSwitch",
        { scope: "capability", target: CAPABILITY_ID },
        { accessJwt },
      ),
    );
    clearConfigCache();

    const disabled = await invoke(scenario);
    expect(disabled.status).toBe(503);
    expect(disabled.body?.code).toBe("capability_disabled");

    const alert = await env.DB.prepare(
      "SELECT code FROM platform_alert WHERE code = ? ORDER BY last_at DESC LIMIT 1",
    )
      .bind("AL-19")
      .first<{ code: string }>();
    expect(alert?.code).toBe("AL-19");

    const audit = await env.DB.prepare(
      `SELECT actor, assertion_sha256 FROM control_audit
       WHERE action = 'kill_switch_capability' AND target = ?
       ORDER BY recorded_at DESC LIMIT 1`,
    )
      .bind(CAPABILITY_ID)
      .first<{ actor: string; assertion_sha256: string | null }>();
    expect(audit?.actor).toBe(VENDOR_OPERATOR_EMAIL);
    expect(audit?.assertion_sha256).toBeNull();
  });

  it("E2E-P3.10-04 capability deprecate and retire show on discovery", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario, {
      role: "clinician",
      scopes: ["ai.visit_summary", "ai.access"],
    });
    const accessJwt = await mintVendorAccessJwt();

    expectClassHOk(
      await p310VendorCall(
        "deprecateCapability",
        {
          capability_id: CAPABILITY_ID,
          capability_version: CAPABILITY_VERSION,
          successor_id: CAPABILITY_ID,
        },
        { accessJwt },
      ),
    );
    clearConfigCache();

    const deprecatedCaps = await getCapabilities(token);
    expect(deprecatedCaps.status).toBe(200);
    expect(manifestLifecycle(deprecatedCaps.body, CAPABILITY_ID)).toBe(
      "deprecated",
    );

    await env.DB.prepare(
      `UPDATE capability_grant SET retire_after = '2020-01-01T00:00:00.000Z'
       WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
         AND lifecycle_state = 'deprecated'`,
    )
      .bind(CAPABILITY_ID, CAPABILITY_VERSION)
      .run();
    clearConfigCache();

    expectClassHOk(
      await p310VendorCall(
        "retireCapability",
        {
          capability_id: CAPABILITY_ID,
          capability_version: CAPABILITY_VERSION,
        },
        { accessJwt },
      ),
    );
    clearConfigCache();

    const retiredCaps = await getCapabilities(token);
    expect(retiredCaps.status).toBe(200);
    expect(manifestLifecycle(retiredCaps.body, CAPABILITY_ID)).toBe("retired");
  });

  it("E2E-P3.10-05 token-contract rotation leaves version 2 current", async () => {
    const accessJwt = await mintVendorAccessJwt();

    expectClassHOk(
      await p310VendorCall("beginTokenContractRotation", {}, { accessJwt }),
    );

    const row = await env.DB.prepare(
      "SELECT ver, retired_at FROM token_contract WHERE ver = '2'",
    ).first<{ ver: string; retired_at: string | null }>();
    expect(row?.ver).toBe("2");
    expect(row?.retired_at).toBeNull();

    const repeat = await p310VendorCall(
      "beginTokenContractRotation",
      {},
      { accessJwt },
    );
    expect(repeat.result).toBe("ok");
    expect(repeat.code).toBe("");
  });

  it("E2E-P3.10-06 supportLookup by subscription ref and by reference", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const accessJwt = await mintVendorAccessJwt();

    const invoked = await invoke(scenario);
    expect(invoked.status).toBe(200);
    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();

    const byRef = expectClassHOk(
      await p310VendorCall("supportLookup", { reference: ref }, { accessJwt }),
    );
    expect(byRef.request).toBeTruthy();
    expect(byRef.envelope).toBeTruthy();

    const subRef = await subscriptionRef(scenario.orgId);
    const bySubscription = expectClassHOk(
      await p310VendorCall(
        "supportLookup",
        { subscription_ref: subRef },
        { accessJwt },
      ),
    );
    const requests = bySubscription.requests as Array<{
      requestReference?: string;
    }>;
    expect(Array.isArray(requests)).toBe(true);
    expect(
      requests.some((entry) => entry.requestReference === ref),
    ).toBe(true);
  });

  it("E2E-P3.10-07 monthly period close is gone and 0 3 and 0 4 run retention and rollup", async () => {
    const crons = triggerCrons();
    expect(crons).toContain("0 3 * * *");
    expect(crons).toContain("0 4 * * *");
    expect(crons).toContain("*/5 * * * *");
    expect(crons).not.toContain("0 5 1 * *");

    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const invoked = await invoke(scenario);
    expect(invoked.status).toBe(200);
    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();

    const request = await getAiRequest(ref);
    const requestId = String(request?.request_id);
    expect(requestId.length).toBeGreaterThan(0);

    await env.DB.prepare(
      `UPDATE ai_request
       SET created_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-91 days')
       WHERE request_id = ?`,
    )
      .bind(requestId)
      .run();

    await runScheduled("0 3 * * *");
    expect(await getAiRequest(ref)).toBeNull();
    expect(await r2Exists(`request/${requestId}/envelope`)).toBe(false);

    await invoke(scenario);
    await flushBackgroundWork();

    await runScheduled("0 4 * * *");
    const rollup = await env.DB.prepare(
      "SELECT dimensions FROM usage_rollup",
    ).all<{ dimensions: string }>();
    expect(rollup.results?.length).toBeGreaterThanOrEqual(1);
    const hasTermDimension = (rollup.results ?? []).some((row) => {
      const dimensions = JSON.parse(row.dimensions) as { term_id?: string };
      return typeof dimensions.term_id === "string" && dimensions.term_id.length > 0;
    });
    expect(hasTermDimension).toBe(true);
  });
});
