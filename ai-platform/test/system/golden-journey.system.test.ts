/**
 * Suite 1 — golden journey (plan §4, SYS-1.1–SYS-1.10).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { INSTALLATION_KEY_TTL_DAYS } from "../../src/control/lifecycle";
import { VISIT_CHIEF_COMPLAINT_V1 } from "../../src/context";
import {
  applyAllMigrations,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollScenario,
  entitleScenario,
  fakePolicyDocument,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  getAiRequest,
  getAttempts,
  getAudits,
  getCapabilities,
  getEntitlement,
  getGrants,
  getRequest,
  getR2Json,
  getUsageEvents,
  invoke,
  mintAat,
  newScenario,
  OPERATOR_ID,
  operatorFetch,
  operatorFetchRaw,
  PLATFORM_TABLES,
  POLICY_ID,
  POLICY_REF,
  POLICY_VERSION,
  publishPolicy,
  promote,
  r2Exists,
  registerVisitSummaryCapability,
  resetPlatformState,
  terminalEventTypes,
  visitSummaryInvokeBody,
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

describe("golden journey", () => {
  it("SYS-1.1 — Boot & health", async () => {
    const response = await SELF.fetch(new Request(`${GATEWAY_ORIGIN}/health`));
    expect(response.status).toBe(200);
    const body = (await response.json()) as { environment?: string };
    expect(body.environment).toBeTruthy();

    const tables = await env.DB.prepare(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ).all<{ name: string }>();
    const names = (tables.results ?? []).map((row) => row.name);
    for (const table of PLATFORM_TABLES) {
      expect(names).toContain(table);
    }
    expect(names.filter((name) => PLATFORM_TABLES.includes(name as never)).length).toBe(
      PLATFORM_TABLES.length,
    );
  });

  it("SYS-1.2 — Enroll → storage truth", async () => {
    const scenario = await newScenario();
    const enrolled = await enrollScenario(scenario);
    expect(enrolled.status).toBe(200);
    expect(enrolled.json.platform_base_url).toBe(GATEWAY_ORIGIN);

    const installation = await env.DB.prepare(
      "SELECT installation_id, org_id, display_name, status, region, enrolled_at FROM installation WHERE installation_id = ?",
    )
      .bind(scenario.installationId)
      .first<{
        installation_id: string;
        org_id: string;
        display_name: string;
        status: string;
        region: string;
        enrolled_at: string;
      }>();
    expect(installation?.status).toBe("active");
    expect(installation?.org_id).toBe(scenario.orgId);

    const key = await env.DB.prepare(
      "SELECT key_id, valid_from, valid_until, revoked_at FROM installation_key WHERE installation_id = ?",
    )
      .bind(scenario.installationId)
      .first<{
        key_id: string;
        valid_from: string;
        valid_until: string;
        revoked_at: string | null;
      }>();
    expect(key?.key_id).toBe(scenario.kid);
    expect(key?.revoked_at).toBeNull();
    const expectedUntil = new Date(
      Date.parse(key!.valid_from) + INSTALLATION_KEY_TTL_DAYS * 24 * 60 * 60 * 1000,
    ).toISOString();
    expect(key?.valid_until).toBe(expectedUntil);

    const entitlement = await getEntitlement(scenario.installationId);
    expect(entitlement?.status).toBe("pending");
    expect(entitlement?.request_quota).toBe(0);
    expect(entitlement?.token_budget).toBe(0);
    expect(entitlement?.cost_budget).toBe(0);
    expect(entitlement?.allowed_capabilities).toBe("[]");
    expect(entitlement?.soft_threshold).toBe(0);

    const audits = await getAudits("enroll", scenario.installationId);
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.action).toBe("enroll");

    const reEnroll = await enrollScenario(scenario);
    expect(reEnroll.status).toBe(409);
    expect(reEnroll.json.error).toBe("already_enrolled");
  });

  it("SYS-1.3 — Pending gates runtime", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    const token = await mintAat(scenario);
    const beforeRequests = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request",
    ).first<{ c: number }>();

    const caps = await getCapabilities(token);
    expect(caps.status).toBe(200);
    expect(caps.body?.manifests).toEqual([]);

    const invoked = await invoke(scenario, { token });
    expect(invoked.status).toBe(403);
    expect(invoked.body?.code).toBe("forbidden_capability");

    const afterRequests = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request",
    ).first<{ c: number }>();
    expect(afterRequests?.c).toBe(beforeRequests?.c ?? 0);
  });

  it("SYS-1.4 — Entitle → grants", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    const entitled = await entitleScenario(scenario);
    expect(entitled.status).toBe(200);
    expect(entitled.json.status).toBe("active");

    const entitlement = await getEntitlement(scenario.installationId);
    expect(entitlement?.period_start).toBe(DEFAULT_ENTITLE_PAYLOAD.period_start);
    expect(entitlement?.period_end).toBe(DEFAULT_ENTITLE_PAYLOAD.period_end);
    expect(entitlement?.request_quota).toBe(DEFAULT_ENTITLE_PAYLOAD.request_quota);
    expect(entitlement?.token_budget).toBe(DEFAULT_ENTITLE_PAYLOAD.token_budget);
    expect(entitlement?.cost_budget).toBe(DEFAULT_ENTITLE_PAYLOAD.cost_budget);
    expect(entitlement?.allowed_capabilities).toBe(
      JSON.stringify(DEFAULT_ENTITLE_PAYLOAD.allowed_capabilities),
    );
    expect(entitlement?.soft_threshold).toBe(DEFAULT_ENTITLE_PAYLOAD.soft_threshold);
    expect(entitlement?.status).toBe("active");
    expect(entitlement?.plan).toBe("standard");

    const installationGrants = await getGrants(`installation:${scenario.installationId}`);
    const planGrants = await getGrants("plan:standard");
    expect(installationGrants).toHaveLength(1);
    expect(planGrants).toHaveLength(1);
    for (const grant of [...installationGrants, ...planGrants]) {
      expect(grant.capability_id).toBe(CAPABILITY_ID);
      expect(grant.capability_version).toBe(CAPABILITY_VERSION);
      expect(grant.revoked_at).toBeNull();
      expect(grant.lifecycle_state).toBeNull();
      expect(grant.successor_id).toBeNull();
      expect(grant.deprecated_at).toBeNull();
      expect(grant.retire_after).toBeNull();
    }

    const audits = await getAudits("entitle", scenario.installationId);
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.after_pointer).toBe(
      JSON.stringify(DEFAULT_ENTITLE_PAYLOAD.allowed_capabilities),
    );

    const reEntitle = await entitleScenario(scenario);
    expect(reEntitle.status).toBe(409);
    expect(reEntitle.json.error).toBe("not_pending");
  });

  it("SYS-1.5 — Discovery after entitle", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);
    const token = await mintAat(scenario);

    const caps = await getCapabilities(token);
    expect(caps.status).toBe(200);
    expect(caps.etag).toBeTruthy();
    const manifests = caps.body?.manifests as Record<string, unknown>[];
    expect(manifests).toHaveLength(1);
    const manifest = manifests[0] as Record<string, Record<string, unknown>>;
    expect(manifest.Identity).toBeTruthy();
    expect(manifest.Interaction).toBeTruthy();
    expect(manifest.Input).toBeTruthy();
    expect(manifest["Context requirements"]).toBeTruthy();
    expect(manifest.Output).toBeTruthy();
    expect(manifest.Governance).toBeTruthy();
    expect(manifest.Identity.capabilityId).toBe(CAPABILITY_ID);
    expect(manifest.Identity.version).toBe(CAPABILITY_VERSION);
    expect(manifest.Identity.title).toBe("Visit summary");
    expect(manifest.Identity.lifecycleState).toBe("active");
    expect(manifest.Output.mode).toBe("prose");
    expect(manifest.Governance.acceptanceMode).toBe("advisory_display");
    expect(manifest.Access).toBeUndefined();
    expect(manifest.Routing).toBeUndefined();
    expect(manifest.Economics).toBeUndefined();
    expect(manifest["Prompt binding"]).toBeUndefined();

    const cached = await getCapabilities(token, caps.etag!);
    expect(cached.status).toBe(304);
    expect(cached.body).toBeNull();
  });

  it("SYS-1.6 — Publish → not served", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);
    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    expect(published.status).toBe(200);

    const policy = await env.DB.prepare(
      "SELECT status, content_pointer FROM routing_policy WHERE policy_id = ? AND version = ?",
    )
      .bind(POLICY_ID, POLICY_VERSION)
      .first<{ status: string; content_pointer: string }>();
    expect(policy?.status).toBe("published");
    expect(policy?.content_pointer).toBe(
      `control/routing-policy/${POLICY_ID}/${POLICY_VERSION}.json`,
    );
    const stored = await getR2Json(policy!.content_pointer);
    expect(stored.policy_id).toBe(POLICY_ID);

    const invoked = await invoke(scenario);
    expect(invoked.status).toBe(200);
    assertSseOrder(invoked.events);
    expect(invoked.events[1]?.event).toBe("failed");
    expect(invoked.events[1]?.data.code).toBe("internal_error");
  });

  it("SYS-1.7 — Promote → invoke completes", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);
    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    const promoted = await promote(POLICY_ID, POLICY_VERSION);
    expect(promoted.status).toBe(200);

    const invoked = await invoke(scenario);
    expect(invoked.status).toBe(200);
    expect(invoked.headers.get("content-type")).toContain("text/event-stream");
    assertSseOrder(invoked.events);
    expect(invoked.events.some((event) => event.event === "text_delta")).toBe(true);
    expect(invoked.events.find((event) => event.event === "completed")).toBeTruthy();
    const completed = invoked.events.find((event) => event.event === "completed");
    const result = completed?.data.result as {
      finalContent?: { text?: string };
    };
    expect(result?.finalContent?.text).toBe("Fake adapter summary.");
  });

  it("SYS-1.8 — Journal + settlement consistency", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);
    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    await promote(POLICY_ID, POLICY_VERSION);

    const traceId = "01SYS1TRACE000000000001";
    const invoked = await invoke(scenario, { traceId });
    expect(invoked.status).toBe(200);
    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();

    const request = await getAiRequest(ref);
    expect(request?.state).toBe("Completed");
    expect(request?.completed_at).toBeTruthy();
    expect(request?.terminal_error_code).toBeNull();
    expect(request?.payload_pointer).toBe(`request/${request?.request_id}/envelope`);

    const routingDecision = JSON.parse(
      String(request?.routing_decision),
    ) as Record<string, unknown>;
    expect(routingDecision.policy_id).toBe(POLICY_ID);
    expect(routingDecision.rule_id).toBe("catch-all");
    expect(Array.isArray(routingDecision.chain)).toBe(true);
    expect((routingDecision.chain as unknown[]).length).toBeGreaterThan(0);

    const attempts = await getAttempts(String(request?.request_id));
    expect(attempts).toHaveLength(1);
    expect(attempts[0]?.outcome).toBe("success");

    const usageEvents = await getUsageEvents(String(request?.request_id));
    expect(usageEvents).toHaveLength(1);
    expect(usageEvents[0]?.period).toBe(
      periodFromEntitleStart(DEFAULT_ENTITLE_PAYLOAD.period_start),
    );
    expect(usageEvents[0]?.tokens).toBe(
      Number(attempts[0]?.tokens_in) + Number(attempts[0]?.tokens_out),
    );
    expect(usageEvents[0]?.cost).toBe(attempts[0]?.cost);
  });

  it("SYS-1.9 — Envelope completeness", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);
    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    await promote(POLICY_ID, POLICY_VERSION);

    const invoked = await invoke(scenario, {
      body: visitSummaryInvokeBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          drop_me: "must-not-reach-envelope",
          [VISIT_CHIEF_COMPLAINT_V1]: {
            visit_id: crypto.randomUUID(),
            complaint: "Headache for three days.",
            recorded_at: new Date().toISOString(),
          },
        },
      }),
    });
    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();

    const request = await getAiRequest(ref);
    const envelopeKey = String(request?.payload_pointer);
    expect(await r2Exists(envelopeKey)).toBe(true);
    expect(await r2Exists(`${envelopeKey}.json`)).toBe(false);
    expect(
      await r2Exists(`request/${request?.request_id}/attempts`),
    ).toBe(false);

    const envelope = await getR2Json(envelopeKey);
    expect(Object.keys(envelope).sort()).toEqual(
      ["attempts", "context", "prompt", "result"].sort(),
    );
    const context = envelope.context as Record<string, unknown>;
    expect("org" in context).toBe(false);
    expect("branch" in context).toBe(false);
    expect("drop_me" in context).toBe(false);
    expect(context[VISIT_CHIEF_COMPLAINT_V1]).toBeTruthy();
  });

  it("SYS-1.10 — Client GET + support lookup", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);
    const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
    await publishPolicy(POLICY_ID, POLICY_VERSION, document);
    await promote(POLICY_ID, POLICY_VERSION);

    const token = await mintAat(scenario);
    const invoked = await invoke(scenario, { token });
    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();

    const auditBefore = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM control_audit",
    ).first<{ c: number }>();

    const clientGet = await getRequest(token, ref);
    expect(clientGet.status).toBe(200);
    expect(clientGet.body?.state).toBe("Completed");
    expect(clientGet.body?.result).toBeTruthy();
    expect(clientGet.body).not.toHaveProperty("attempts");
    expect(clientGet.body).not.toHaveProperty("envelope");

    const lookup = await operatorFetchRaw(
      `/control/support/lookup?reference=${encodeURIComponent(ref)}`,
      undefined,
    );
    expect(lookup.status).toBe(200);
    const lookupBody = (await lookup.json()) as {
      request?: { requestId?: string };
      attempts?: unknown[];
      envelope?: Record<string, unknown>;
    };
    expect(lookupBody.request).toBeTruthy();
    expect(lookupBody.attempts).toBeTruthy();
    expect(lookupBody.envelope).toBeTruthy();

    const request = await getAiRequest(ref);
    expect(lookupBody.request?.requestId).toBe(request?.request_id);

    const auditAfter = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM control_audit",
    ).first<{ c: number }>();
    expect(auditAfter?.c).toBe(auditBefore?.c);
  });
});
