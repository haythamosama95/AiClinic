/**
 * Suite 2 — lifecycle interplay (plan §4, SYS-2.1–SYS-2.6).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { INSTALLATION_KEY_TTL_DAYS } from "../../src/control/lifecycle";
import {
  applyAllMigrations,
  clearConfigCache,
  count,
  enrollPayload,
  enrollScenario,
  entitleScenario,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  getAiRequest,
  getAudits,
  getCapabilities,
  getEntitlement,
  invoke,
  mintAat,
  newScenario,
  operatorFetch,
  registerVisitSummaryCapability,
  resetPlatformState,
  setupPromotedFakePolicy,
  terminalEventTypes,
  type Scenario,
  type TestKeypair,
} from "./harness";

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
});

function base64urlEncode(data: string | Uint8Array): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

async function generateKeypair(kid: string): Promise<TestKeypair> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const rawPublicKey = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  return {
    publicKey: keyPair.publicKey,
    privateKey: keyPair.privateKey,
    kid,
    publicKeyB64: base64urlEncode(new Uint8Array(rawPublicKey)),
  };
}

async function ensureInstallationKeyActive(installationId: string): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const key = await env.DB.prepare(
      "SELECT valid_from FROM installation_key WHERE installation_id = ? AND revoked_at IS NULL ORDER BY valid_from DESC LIMIT 1",
    )
      .bind(installationId)
      .first<{ valid_from: string }>();
    const validFromMs = Date.parse(String(key?.valid_from));
    const verifierNowMs = Math.floor(Date.now() / 1000) * 1000;
    if (!Number.isNaN(validFromMs) && verifierNowMs >= validFromMs) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error("installation key not yet within validity window");
}

async function mintAatWithKeypair(
  scenario: Scenario,
  keypair: TestKeypair,
  overrides: { ver?: string } = {},
): Promise<string> {
  await ensureInstallationKeyActive(scenario.installationId);
  const payload = {
    iss: scenario.installationId,
    aud: "ai-platform",
    sub: scenario.actorId,
    org: scenario.orgId,
    branch: scenario.branchId,
    role: "clinician",
    scopes: ["ai.visit_summary", "ai.access"],
    jti: crypto.randomUUID(),
    iat: Math.floor(Date.now() / 1000) - 30,
    exp: Math.floor(Date.now() / 1000) + 300,
    ver: "1",
    ...overrides,
  };
  const header = { alg: "EdDSA", kid: keypair.kid };
  const headerB64 = base64urlEncode(JSON.stringify(header));
  const payloadB64 = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    keypair.privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64urlEncode(new Uint8Array(signature))}`;
}

async function controlPost(
  path: string,
  body?: Record<string, unknown>,
  authorization?: string,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const headers: Record<string, string> = {};
  if (body !== undefined) {
    headers["content-type"] = "application/json";
  }
  if (authorization !== undefined) {
    headers.authorization = authorization;
  }
  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}${path}`, {
      method: "POST",
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    }),
  );
  const text = await response.text();
  const json = text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : {};
  return { status: response.status, json };
}

function assertInvokeCompleted(events: { event: string }[]): void {
  expect(events[0]?.event).toBe("accepted");
  expect(terminalEventTypes(events)).toEqual(["completed"]);
}

describe("lifecycle interplay", () => {
  it("SYS-2.1 — Suspend blocks, resume restores", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);

    const beforeInvoke = await invoke(scenario);
    expect(beforeInvoke.status).toBe(200);
    assertInvokeCompleted(beforeInvoke.events);

    const suspended = await operatorFetch(
      `/control/installations/${scenario.installationId}/suspend`,
      {},
    );
    expect(suspended.status).toBe(200);
    clearConfigCache();

    const installation = await env.DB.prepare(
      "SELECT status FROM installation WHERE installation_id = ?",
    )
      .bind(scenario.installationId)
      .first<{ status: string }>();
    expect(installation?.status).toBe("suspended");
    expect(await getAudits("suspend", scenario.installationId)).toHaveLength(1);

    const beforeRequests = await count("ai_request");
    const token = await mintAat(scenario);
    const blockedInvoke = await invoke(scenario, { token });
    expect(blockedInvoke.status).toBe(403);
    expect(blockedInvoke.body?.code).toBe("installation_suspended");
    expect(blockedInvoke.body?.retry_safe).toBe(false);
    expect(await count("ai_request")).toBe(beforeRequests);

    const caps = await getCapabilities(token);
    expect(caps.status).toBe(403);
    expect(caps.body?.code).toBe("installation_suspended");
    expect(caps.body?.retry_safe).toBe(false);

    const resumed = await operatorFetch(
      `/control/installations/${scenario.installationId}/resume`,
      {},
    );
    expect(resumed.status).toBe(200);
    clearConfigCache();
    expect(await getAudits("resume", scenario.installationId)).toHaveLength(1);

    const afterResume = await invoke(scenario);
    expect(afterResume.status).toBe(200);
    assertInvokeCompleted(afterResume.events);
  });

  it("SYS-2.2 — Illegal transitions", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);

    const firstSuspend = await operatorFetch(
      `/control/installations/${scenario.installationId}/suspend`,
      {},
    );
    expect(firstSuspend.status).toBe(200);

    const secondSuspend = await operatorFetch(
      `/control/installations/${scenario.installationId}/suspend`,
      {},
    );
    expect(secondSuspend.status).toBe(409);
    expect(secondSuspend.json.error).toBe("illegal_lifecycle_transition");

    await operatorFetch(
      `/control/installations/${scenario.installationId}/resume`,
      {},
    );
    clearConfigCache();

    const resumeWhileActive = await operatorFetch(
      `/control/installations/${scenario.installationId}/resume`,
      {},
    );
    expect(resumeWhileActive.status).toBe(409);
    expect(resumeWhileActive.json.error).toBe("illegal_lifecycle_transition");

    const deleted = await operatorFetch(
      `/control/installations/${scenario.installationId}/delete`,
      {},
    );
    expect(deleted.status).toBe(200);
    clearConfigCache();

    const resumeAfterDelete = await operatorFetch(
      `/control/installations/${scenario.installationId}/resume`,
      {},
    );
    expect(resumeAfterDelete.status).toBe(409);
    expect(resumeAfterDelete.json.error).toBe("illegal_lifecycle_transition");
  });

  it("SYS-2.3 — Rotate additive overlap and revoke-key", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const k0Keypair = scenario.keypair;
    const k0Token = await mintAat(scenario);

    const k0Invoke = await invoke(scenario, { token: k0Token });
    expect(k0Invoke.status).toBe(200);
    assertInvokeCompleted(k0Invoke.events);

    const k1Kid = crypto.randomUUID();
    const k1Keypair = await generateKeypair(k1Kid);
    const rotated = await operatorFetch(
      `/control/installations/${scenario.installationId}/rotate`,
      {
        kid: k1Kid,
        public_key: k1Keypair.publicKeyB64,
        algorithm: "EdDSA",
      },
    );
    expect(rotated.status).toBe(200);
    clearConfigCache();

    const k1Key = await env.DB.prepare(
      "SELECT key_id, valid_from, valid_until, revoked_at FROM installation_key WHERE key_id = ?",
    )
      .bind(k1Kid)
      .first<{
        key_id: string;
        valid_from: string;
        valid_until: string;
        revoked_at: string | null;
      }>();
    expect(k1Key?.revoked_at).toBeNull();
    const expectedUntil = new Date(
      Date.parse(k1Key!.valid_from) + INSTALLATION_KEY_TTL_DAYS * 24 * 60 * 60 * 1000,
    ).toISOString();
    expect(k1Key?.valid_until).toBe(expectedUntil);

    const k0Row = await env.DB.prepare(
      "SELECT revoked_at FROM installation_key WHERE key_id = ?",
    )
      .bind(k0Keypair.kid)
      .first<{ revoked_at: string | null }>();
    expect(k0Row?.revoked_at).toBeNull();

    const k0AfterRotateToken = await mintAatWithKeypair(scenario, k0Keypair);
    const k0AfterRotate = await invoke(scenario, { token: k0AfterRotateToken });
    expect(k0AfterRotate.status).toBe(200);
    assertInvokeCompleted(k0AfterRotate.events);

    await ensureInstallationKeyActive(scenario.installationId);
    const k1Token = await mintAatWithKeypair(scenario, k1Keypair);
    const k1Invoke = await invoke(scenario, { token: k1Token });
    expect(k1Invoke.status).toBe(200);
    assertInvokeCompleted(k1Invoke.events);

    const revokeK0 = await operatorFetch(
      `/control/installations/${scenario.installationId}/revoke-key`,
      { kid: k0Keypair.kid },
    );
    expect(revokeK0.status).toBe(200);
    clearConfigCache();

    const k0AfterRevokeToken = await mintAatWithKeypair(scenario, k0Keypair);
    const k0AfterRevoke = await invoke(scenario, { token: k0AfterRevokeToken });
    expect(k0AfterRevoke.status).toBe(401);
    expect(k0AfterRevoke.body?.code).toBe("unauthenticated");

    const repeatRevoke = await operatorFetch(
      `/control/installations/${scenario.installationId}/revoke-key`,
      { kid: k0Keypair.kid },
    );
    expect(repeatRevoke.status).toBe(409);
    expect(repeatRevoke.json.error).toBe("key_already_revoked");

    const revokeLast = await operatorFetch(
      `/control/installations/${scenario.installationId}/revoke-key`,
      { kid: k1Kid },
    );
    expect(revokeLast.status).toBe(409);
    expect(revokeLast.json.error).toBe("cannot_revoke_last_active_key");
  });

  it("SYS-2.4 — Delete then purge", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);

    const completed = await invoke(scenario);
    expect(completed.status).toBe(200);
    assertInvokeCompleted(completed.events);
    const ref = String(completed.events[0]?.data.request_reference);
    await flushBackgroundWork();

    const request = await getAiRequest(ref);
    const envelopeKey = String(request?.payload_pointer);
    expect(
      await count("ai_request", "installation_id = ?", [scenario.installationId]),
    ).toBeGreaterThan(0);

    const deleted = await operatorFetch(
      `/control/installations/${scenario.installationId}/delete`,
      {},
    );
    expect(deleted.status).toBe(200);
    clearConfigCache();

    const deletedRow = await env.DB.prepare(
      "SELECT status FROM installation WHERE installation_id = ?",
    )
      .bind(scenario.installationId)
      .first<{ status: string }>();
    expect(deletedRow?.status).toBe("deleted");

    const token = await mintAat(scenario);
    const blocked = await invoke(scenario, { token });
    expect(blocked.status).toBe(401);
    expect(blocked.body?.code).toBe("unauthenticated");

    const purged = await operatorFetch(
      `/control/installations/${scenario.installationId}/purge`,
      {},
    );
    expect(purged.status).toBe(200);
    expect(purged.json).toEqual({});

    expect(
      await count("installation", "installation_id = ?", [scenario.installationId]),
    ).toBe(0);
    expect(
      await count("installation_key", "installation_id = ?", [scenario.installationId]),
    ).toBe(0);
    expect(
      await count("entitlement", "installation_id = ?", [scenario.installationId]),
    ).toBe(0);
    expect(
      await count(
        "capability_grant",
        "scope = ?",
        [`installation:${scenario.installationId}`],
      ),
    ).toBe(0);
    expect(
      await count("ai_request", "installation_id = ?", [scenario.installationId]),
    ).toBe(0);
    expect(
      await count("ai_attempt", "request_id = ?", [request?.request_id]),
    ).toBe(0);
    expect(
      await count("usage_event", "request_id = ?", [request?.request_id]),
    ).toBe(0);

    const envelopeHead = await env.R2.head(envelopeKey);
    expect(envelopeHead).toBeNull();

    const purgeAudits = await getAudits("purge_installation", scenario.installationId);
    expect(purgeAudits.length).toBeGreaterThanOrEqual(1);

    const afterPurge = await invoke(scenario, { token });
    expect(afterPurge.status).toBe(401);
    expect(afterPurge.body?.code).toBe("unauthenticated");
  });

  it("SYS-2.5 — Re-enroll after purge is fresh", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    await operatorFetch(`/control/installations/${scenario.installationId}/delete`, {});
    await operatorFetch(`/control/installations/${scenario.installationId}/purge`, {});
    clearConfigCache();

    const reEnrolled = await enrollScenario(scenario);
    expect(reEnrolled.status).toBe(200);

    const entitlement = await getEntitlement(scenario.installationId);
    expect(entitlement?.status).toBe("pending");
    expect(entitlement?.request_quota).toBe(0);
    expect(entitlement?.allowed_capabilities).toBe("[]");

    const token = await mintAat(scenario);
    const gated = await invoke(scenario, { token });
    expect(gated.status).toBe(403);
    expect(gated.body?.code).toBe("forbidden_capability");
  });

  it("SYS-2.6 — Operator auth matrix", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    await entitleScenario(scenario);
    const staffToken = await mintAat(scenario);
    const rotateKid = crypto.randomUUID();
    const rotateKeypair = await generateKeypair(rotateKid);

    const routes: Array<{
      label: string;
      path: string;
      body?: Record<string, unknown>;
    }> = [
      {
        label: "enroll",
        path: `/control/installations/${scenario.installationId}/enroll`,
        body: enrollPayload(scenario),
      },
      {
        label: "suspend",
        path: `/control/installations/${scenario.installationId}/suspend`,
        body: {},
      },
      {
        label: "resume",
        path: `/control/installations/${scenario.installationId}/resume`,
        body: {},
      },
      {
        label: "rotate",
        path: `/control/installations/${scenario.installationId}/rotate`,
        body: {
          kid: rotateKid,
          public_key: rotateKeypair.publicKeyB64,
          algorithm: "EdDSA",
        },
      },
      {
        label: "revoke-key",
        path: `/control/installations/${scenario.installationId}/revoke-key`,
        body: { kid: scenario.kid },
      },
      {
        label: "delete",
        path: `/control/installations/${scenario.installationId}/delete`,
        body: {},
      },
      {
        label: "purge",
        path: `/control/installations/${scenario.installationId}/purge`,
        body: {},
      },
      {
        label: "entitle",
        path: `/control/installations/${scenario.installationId}/entitle`,
        body: {
          period_start: "2026-07-01T00:00:00.000Z",
          period_end: "2026-09-01T00:00:00.000Z",
          request_quota: 100,
          token_budget: 1000,
          cost_budget: 10,
          soft_threshold: 0.8,
          allowed_capabilities: ["clinic.visit_summary"],
          grants: [
            {
              capability_id: "clinic.visit_summary",
              capability_version: "1.0.0",
              scope: "installation",
            },
          ],
        },
      },
      {
        label: "begin-rotation",
        path: "/control/token-contract/begin-rotation",
        body: { ver: "2" },
      },
      {
        label: "retire",
        path: "/control/token-contract/retire",
        body: { ver: "1" },
      },
    ];

    for (const route of routes) {
      const auditBefore = await count("control_audit");

      const noBearer = await controlPost(route.path, route.body);
      expect(noBearer.status, `${route.label} no bearer`).toBe(401);
      expect(noBearer.json.error).toBe("unauthorized");

      const wrongBearer = await controlPost(
        route.path,
        route.body,
        "Bearer definitely-not-the-operator-token",
      );
      expect(wrongBearer.status, `${route.label} wrong bearer`).toBe(401);
      expect(wrongBearer.json.error).toBe("unauthorized");

      const staffBearer = await controlPost(
        route.path,
        route.body,
        `Bearer ${staffToken}`,
      );
      expect(staffBearer.status, `${route.label} staff AAT`).toBe(401);
      expect(staffBearer.json.error).toBe("unauthorized");

      const auditAfter = await count("control_audit");
      expect(auditAfter, `${route.label} audit unchanged`).toBe(auditBefore);
    }
  });
});
