/**
 * Suite 9 — token contract rotation (plan §4, SYS-9.1–SYS-9.3).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  clearConfigCache,
  count,
  enrollScenario,
  GATEWAY_ORIGIN,
  getAudits,
  invoke,
  mintAat,
  newScenario,
  operatorFetch,
  registerVisitSummaryCapability,
  resetPlatformState,
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

function assertIdentityPasses(status: number): void {
  expect(status).not.toBe(401);
}

describe("token contract rotation", () => {
  it("SYS-9.1 — Begin-rotation dual-accept", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);

    const began = await operatorFetch("/control/token-contract/begin-rotation", {
      ver: "2",
    });
    expect(began.status).toBe(200);
    expect(began.json.ver).toBe("2");
    clearConfigCache();

    const contracts = await env.DB.prepare(
      "SELECT ver, retired_at, changed_by FROM token_contract ORDER BY ver",
    ).all<{ ver: string; retired_at: string | null; changed_by: string }>();
    const live = (contracts.results ?? []).filter((row) => row.retired_at === null);
    expect(live).toHaveLength(2);
    expect(live.map((row) => row.ver).sort()).toEqual(["1", "2"]);
    expect(live.find((row) => row.ver === "1")?.changed_by).toBe("seed");

    const tokenV1 = await mintAat(scenario, { ver: "1" });
    const invokeV1 = await invoke(scenario, { token: tokenV1 });
    assertIdentityPasses(invokeV1.status);
    expect(invokeV1.status).toBe(200);
    expect(terminalEventTypes(invokeV1.events)).toEqual(["completed"]);

    const tokenV2 = await mintAat(scenario, { ver: "2" });
    const invokeV2 = await invoke(scenario, { token: tokenV2 });
    assertIdentityPasses(invokeV2.status);
    expect(invokeV2.status).toBe(200);
    expect(terminalEventTypes(invokeV2.events)).toEqual(["completed"]);
  });

  it("SYS-9.2 — Retire cuts old ver", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);

    const began = await operatorFetch("/control/token-contract/begin-rotation", {
      ver: "2",
    });
    expect(began.status).toBe(200);
    clearConfigCache();

    const retired = await operatorFetch("/control/token-contract/retire", {
      ver: "2",
    });
    expect(retired.status).toBe(200);
    expect(retired.json.ver).toBe("2");
    expect(retired.json.retired_at).toBeTruthy();
    clearConfigCache();

    const row = await env.DB.prepare(
      "SELECT ver, retired_at FROM token_contract WHERE ver = ?",
    )
      .bind("2")
      .first<{ ver: string; retired_at: string | null }>();
    expect(row?.retired_at).toBe(retired.json.retired_at);

    const beginAudits = await getAudits("token_contract_begin_rotation", "2");
    expect(beginAudits).toHaveLength(1);
    const retireAudits = await getAudits("token_contract_retire", "2");
    expect(retireAudits).toHaveLength(1);

    const tokenV2 = await mintAat(scenario, { ver: "2" });
    const blocked = await invoke(scenario, { token: tokenV2 });
    expect(blocked.status).toBe(401);
    expect(blocked.body?.code).toBe("unauthenticated");

    const tokenV1 = await mintAat(scenario, { ver: "1" });
    const allowed = await invoke(scenario, { token: tokenV1 });
    assertIdentityPasses(allowed.status);
    expect(allowed.status).toBe(200);
    expect(terminalEventTypes(allowed.events)).toEqual(["completed"]);
  });

  it("SYS-9.3 — Auth & validation", async () => {
    const scenario = await newScenario();
    await enrollScenario(scenario);
    const staffToken = await mintAat(scenario);

    const routes = [
      {
        path: "/control/token-contract/begin-rotation",
        body: { ver: "2" },
      },
      {
        path: "/control/token-contract/retire",
        body: { ver: "1" },
      },
    ] as const;

    for (const route of routes) {
      const auditBefore = await count("control_audit");

      const noBearer = await controlPost(route.path, route.body);
      expect(noBearer.status).toBe(401);
      expect(noBearer.json.error).toBe("unauthorized");

      const staffBearer = await controlPost(
        route.path,
        route.body,
        `Bearer ${staffToken}`,
      );
      expect(staffBearer.status).toBe(401);
      expect(staffBearer.json.error).toBe("unauthorized");

      const auditAfter = await count("control_audit");
      expect(auditAfter).toBe(auditBefore);
    }
  });
});
