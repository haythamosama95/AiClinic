/**
 * Suite 10 — capability lifecycle (plan §4, SYS-10.1–SYS-10.3).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clearConfigCache,
  enrollScenario,
  entitleScenario,
  GATEWAY_ORIGIN,
  getAudits,
  getCapabilities,
  invoke,
  mintAat,
  newScenario,
  operatorFetch,
  registerVisitSummaryCapability,
  resetPlatformState,
  setupPromotedFakePolicy,
  type Scenario,
} from "./harness";

const COHORT_NAME = "probe-cohort";
const CAPABILITY_PIN = `${CAPABILITY_ID}@${CAPABILITY_VERSION}`;
const COHORT_TARGET = `${CAPABILITY_PIN}:${COHORT_NAME}`;

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

async function activate(
  version: string,
  body: Record<string, unknown>,
  auth: "operator" | "none" = "operator",
): Promise<{ status: number; json: Record<string, unknown> }> {
  if (auth === "none") {
    const response = await SELF.fetch(
      new Request(
        `${GATEWAY_ORIGIN}/control/capabilities/${CAPABILITY_ID}/versions/${version}/activate`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(body),
        },
      ),
    );
    const text = await response.text();
    clearConfigCache();
    return {
      status: response.status,
      json: text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : {},
    };
  }
  const response = await operatorFetch(
    `/control/capabilities/${CAPABILITY_ID}/versions/${version}/activate`,
    body,
  );
  clearConfigCache();
  return response;
}

async function promoteCapability(
  version: string = CAPABILITY_VERSION,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const result = await operatorFetch(
    `/control/capabilities/${CAPABILITY_ID}/versions/${version}/promote`,
    {},
  );
  clearConfigCache();
  return result;
}

async function deprecate(
  version: string,
  body: Record<string, unknown> = { successor_id: CAPABILITY_ID },
): Promise<{ status: number; json: Record<string, unknown> }> {
  const result = await operatorFetch(
    `/control/capabilities/${CAPABILITY_ID}/versions/${version}/deprecate`,
    body,
  );
  clearConfigCache();
  return result;
}

async function retire(version: string = CAPABILITY_VERSION): Promise<{
  status: number;
  json: Record<string, unknown>;
}> {
  const result = await operatorFetch(
    `/control/capabilities/${CAPABILITY_ID}/versions/${version}/retire`,
    {},
  );
  clearConfigCache();
  return result;
}

async function globalOverlay(): Promise<Record<string, unknown> | null> {
  return env.DB.prepare(
    `SELECT lifecycle_state, successor_id, deprecated_at, retire_after, revoked_at
     FROM capability_grant
     WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
     ORDER BY changed_at DESC LIMIT 1`,
  )
    .bind(CAPABILITY_ID, CAPABILITY_VERSION)
    .first<Record<string, unknown>>();
}

async function prepareEntitled(scenario: Scenario): Promise<void> {
  await enrollScenario(scenario);
  const entitled = await entitleScenario(scenario);
  expect(entitled.status).toBe(200);
}

describe("capability lifecycle", () => {
  it("SYS-10.1 — Cohort activate & promote", async () => {
    const scenario = await newScenario();
    await prepareEntitled(scenario);

    const auditsBefore = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM control_audit WHERE action = 'cohort_activate'",
    ).first<{ c: number }>();

    const noAuth = await activate(CAPABILITY_VERSION, {
      installation_ids: [scenario.installationId],
    }, "none");
    expect(noAuth.status).toBe(401);
    expect(noAuth.json.error).toBe("unauthorized");

    const auditsAfterNoAuth = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM control_audit WHERE action = 'cohort_activate'",
    ).first<{ c: number }>();
    expect(auditsAfterNoAuth?.c).toBe(auditsBefore?.c ?? 0);

    const missingIds = await activate(CAPABILITY_VERSION, { installation_ids: [] });
    expect(missingIds.status).toBe(400);
    expect(missingIds.json.error).toBe("missing_installation_ids");

    const unknownInstall = await activate(CAPABILITY_VERSION, {
      installation_ids: ["00000000-0000-0000-0000-000000000000"],
    });
    expect(unknownInstall.status).toBe(404);
    expect(unknownInstall.json.error).toBe("installation_not_found");

    const unknownVersion = await activate("9.9.9", {
      installation_ids: [scenario.installationId],
    });
    expect(unknownVersion.status).toBe(404);
    expect(unknownVersion.json.error).toBe("capability_not_found");

    const activated = await activate(CAPABILITY_VERSION, {
      installation_ids: [scenario.installationId],
      cohort_name: COHORT_NAME,
    });
    expect(activated.status).toBe(200);

    const activateAudits = await getAudits("cohort_activate", COHORT_TARGET);
    expect(activateAudits.length).toBeGreaterThanOrEqual(1);
    const activateAudit = activateAudits[activateAudits.length - 1]!;
    expect(activateAudit.before_pointer).toBeTruthy();
    const beforeMap = JSON.parse(String(activateAudit.before_pointer)) as Record<
      string,
      string | null
    >;
    expect(beforeMap[scenario.installationId]).toBe(CAPABILITY_VERSION);
    expect(activateAudit.after_pointer).toBe(CAPABILITY_VERSION);

    const grant = await env.DB.prepare(
      `SELECT capability_version, revoked_at FROM capability_grant
       WHERE scope = ? AND capability_id = ?`,
    )
      .bind(`installation:${scenario.installationId}`, CAPABILITY_ID)
      .first<{ capability_version: string; revoked_at: string | null }>();
    expect(grant?.capability_version).toBe(CAPABILITY_VERSION);
    expect(grant?.revoked_at).toBeNull();

    const promoted = await promoteCapability();
    expect(promoted.status).toBe(200);

    const promoteAudits = await getAudits("cohort_promote", CAPABILITY_PIN);
    expect(promoteAudits.length).toBeGreaterThanOrEqual(1);
    const promoteAudit = promoteAudits[promoteAudits.length - 1]!;
    expect(promoteAudit.before_pointer).toBeTruthy();
    expect(promoteAudit.after_pointer).toBe(CAPABILITY_VERSION);
  });

  it("SYS-10.2 — Deprecate lifecycle", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario, {
      role: "clinician",
      scopes: ["ai.visit_summary", "ai.access"],
    });

    const missingSuccessor = await deprecate(CAPABILITY_VERSION, {});
    expect(missingSuccessor.status).toBe(400);
    expect(missingSuccessor.json.error).toBe("missing_successor_id");

    const unknownSuccessor = await deprecate(CAPABILITY_VERSION, {
      successor_id: "clinic.not_in_registry",
    });
    expect(unknownSuccessor.status).toBe(400);
    expect(unknownSuccessor.json.error).toBe("unknown_successor");

    const unknownVersion = await deprecate("9.9.9");
    expect(unknownVersion.status).toBe(404);
    expect(unknownVersion.json.error).toBe("capability_not_found");

    const deprecated = await deprecate(CAPABILITY_VERSION, {
      successor_id: CAPABILITY_ID,
    });
    expect(deprecated.status).toBe(200);

    const overlay = await globalOverlay();
    expect(overlay?.lifecycle_state).toBe("deprecated");
    expect(overlay?.successor_id).toBe(CAPABILITY_ID);
    expect(overlay?.deprecated_at).toBeTruthy();
    expect(overlay?.revoked_at).toBeTruthy();
    const deprecatedAt = Date.parse(String(overlay?.deprecated_at));
    const retireAfter = Date.parse(String(overlay?.retire_after));
    expect(retireAfter - deprecatedAt).toBeCloseTo(90 * 24 * 60 * 60 * 1000, -3);

    const deprecateAudits = await getAudits("deprecate", CAPABILITY_PIN);
    expect(deprecateAudits.length).toBeGreaterThanOrEqual(1);
    expect(deprecateAudits[deprecateAudits.length - 1]?.after_pointer).toBe(CAPABILITY_ID);

    const idempotent = await deprecate(CAPABILITY_VERSION, {
      successor_id: CAPABILITY_ID,
    });
    expect(idempotent.status).toBe(200);
    const overlayAfterIdempotent = await globalOverlay();
    expect(overlayAfterIdempotent?.deprecated_at).toBe(overlay?.deprecated_at);
    expect(overlayAfterIdempotent?.retire_after).toBe(overlay?.retire_after);

    const differentSuccessor = await deprecate(CAPABILITY_VERSION, {
      successor_id: `${CAPABILITY_ID}@${CAPABILITY_VERSION}`,
    });
    expect(differentSuccessor.status).toBe(409);
    expect(differentSuccessor.json.error).toBe("already_deprecated");

    const whileDeprecated = await invoke(scenario, { token });
    expect(whileDeprecated.status).toBe(200);
    expect(whileDeprecated.events[0]?.event).toBe("accepted");
    expect(whileDeprecated.events.some((event) => event.event === "completed")).toBe(true);
  });

  it("SYS-10.3 — Retire lifecycle", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario, {
      role: "clinician",
      scopes: ["ai.visit_summary", "ai.access"],
    });

    await d1Run(
      `DELETE FROM capability_grant WHERE scope = 'global' AND capability_id = ?`,
      CAPABILITY_ID,
    );

    const notDeprecated = await retire();
    expect(notDeprecated.status).toBe(400);
    expect(notDeprecated.json.error).toBe("not_deprecated");

    await deprecate(CAPABILITY_VERSION, { successor_id: CAPABILITY_ID });

    const overlapActive = await retire();
    expect(overlapActive.status).toBe(400);
    expect(overlapActive.json.error).toBe("overlap_window_active");

    await d1Run(
      `UPDATE capability_grant SET retire_after = '2020-01-01T00:00:00.000Z'
       WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
         AND lifecycle_state = 'deprecated'`,
      CAPABILITY_ID,
      CAPABILITY_VERSION,
    );

    const retired = await retire();
    expect(retired.status).toBe(200);

    const overlay = await globalOverlay();
    expect(overlay?.lifecycle_state).toBe("retired");
    expect(overlay?.successor_id).toBe(CAPABILITY_ID);

    const retireAudits = await getAudits("retire", CAPABILITY_PIN);
    expect(retireAudits.length).toBeGreaterThanOrEqual(1);
    expect(retireAudits[retireAudits.length - 1]?.after_pointer).toBe(CAPABILITY_ID);

    const beforeRequests = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request",
    ).first<{ c: number }>();
    const invokeRetired = await invoke(scenario, { token });
    expect(invokeRetired.status).toBe(404);
    expect(invokeRetired.body?.code).toBe("capability_retired");
    expect(invokeRetired.body?.retry_safe).toBe(false);
    const afterRequests = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_request",
    ).first<{ c: number }>();
    expect(afterRequests?.c).toBe(beforeRequests?.c ?? 0);

    const caps = await getCapabilities(token);
    expect(caps.status).toBe(200);
    const manifests = caps.body?.manifests as Array<{ Identity?: { capabilityId?: string } }>;
    expect(manifests ?? []).toHaveLength(0);

    const deprecateAfterRetire = await deprecate(CAPABILITY_VERSION, {
      successor_id: CAPABILITY_ID,
    });
    expect(deprecateAfterRetire.status).toBe(409);
    expect(deprecateAfterRetire.json.error).toBe("already_retired");
  });
});
