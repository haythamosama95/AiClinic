/**
 * P7.3 — contract version matrix platform channels (E2E-P7.3-01).
 */

import { env, SELF } from "cloudflare:test";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_VERSION,
  GATEWAY_ORIGIN,
  mintAat,
  mintFeedToken,
  newScenario,
  parseSseEvents,
  registerVisitSummaryCapability,
  resetPlatformState,
  setupPromotedFakePolicy,
  vendorCall,
  visitSummaryInvokeBody,
} from "../system/harness";

const RECEIVER_CURRENT = CHANNEL_VERSIONS.platformClinic;
const ACCEPTED_VERSIONS = [RECEIVER_CURRENT - 1, RECEIVER_CURRENT];
const FEED_CURRENT = CHANNEL_VERSIONS.platformFeed;
const DO_CURRENT = CHANNEL_VERSIONS.platformDo;
const VENDOR_CURRENT = CHANNEL_VERSIONS.vendorEntrypoint;

const DO_RPC_URL = "https://quota-do.internal/rpc";

function quotaDoStub(installationId: string) {
  return env.DO.get(env.DO.idFromName(installationId));
}

async function fetchGatewayObjectRpc(
  installationId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  return quotaDoStub(installationId).fetch(DO_RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function expectClinicRouteRefusal(
  request: Request,
  table: string,
): Promise<void> {
  const before = await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table}`)
    .first<{ n: number }>();
  const response = await SELF.fetch(request);
  expect(response.status).toBe(400);
  const body = (await response.json()) as Record<string, unknown>;
  expect(body.code).toBe("contract_version_unsupported");
  expect(body.accepted_versions).toEqual(ACCEPTED_VERSIONS);
  const after = await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table}`)
    .first<{ n: number }>();
  expect(after?.n).toBe(before?.n);
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
});

describe("E2E-P7.3-01", () => {
  it("E2E-P7.3-01", async () => {
    for (const version of [undefined, "0", "3"] as const) {
      const headers: Record<string, string> = {
        authorization: "Bearer invalid-token",
      };
      if (version !== undefined) {
        headers["Aip-Contract-Version"] = version;
      }

      await expectClinicRouteRefusal(
        new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, { headers }),
        "installation",
      );
      await expectClinicRouteRefusal(
        new Request(`${GATEWAY_ORIGIN}/v1/coverage`, { headers }),
        "installation",
      );
      await expectClinicRouteRefusal(
        new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
          method: "POST",
          headers: {
            ...headers,
            "content-type": "application/json",
            "x-idempotency-key": crypto.randomUUID(),
            "x-capability-version": CAPABILITY_VERSION,
          },
          body: JSON.stringify({ capability_id: "clinic.visit_summary" }),
        }),
        "ai_request",
      );
    }

    const scenario = await newScenario();
    const token = await mintAat(scenario);

    const okCapabilities = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, {
        headers: {
          authorization: `Bearer ${token}`,
          "Aip-Contract-Version": String(RECEIVER_CURRENT),
        },
      }),
    );
    expect(okCapabilities.status).toBe(200);
    expect(okCapabilities.headers.get("Aip-Contract-Version")).toBe(
      String(RECEIVER_CURRENT),
    );

    const okPrevious = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, {
        headers: {
          authorization: `Bearer ${token}`,
          "Aip-Contract-Version": String(RECEIVER_CURRENT - 1),
        },
      }),
    );
    expect(okPrevious.status).toBe(200);
    expect(okPrevious.headers.get("Aip-Contract-Version")).toBe(
      String(RECEIVER_CURRENT - 1),
    );

    await setupPromotedFakePolicy(scenario);
    const streamToken = await mintAat(scenario);
    const streamResponse = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${streamToken}`,
          "content-type": "application/json",
          "x-idempotency-key": crypto.randomUUID(),
          "x-capability-version": CAPABILITY_VERSION,
          "Aip-Contract-Version": String(RECEIVER_CURRENT),
        },
        body: JSON.stringify(visitSummaryInvokeBody(scenario)),
      }),
    );
    expect(streamResponse.status).toBe(200);
    expect(streamResponse.headers.get("Aip-Contract-Version")).toBe(
      String(RECEIVER_CURRENT),
    );
    const events = await parseSseEvents(streamResponse);
    expect(events.length).toBeGreaterThan(0);

    const feedToken = await mintFeedToken();
    const feedRefused = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/feed/coverage?after=0&limit=1`, {
        headers: {
          authorization: `Bearer ${feedToken}`,
          "Aip-Contract-Version": "0",
        },
      }),
    );
    expect(feedRefused.status).toBe(400);
    const feedBody = (await feedRefused.json()) as Record<string, unknown>;
    expect(feedBody.code).toBe("contract_version_unsupported");

    const feedOk = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/feed/coverage?after=0&limit=1`, {
        headers: {
          authorization: `Bearer ${feedToken}`,
          "Aip-Contract-Version": String(FEED_CURRENT),
        },
      }),
    );
    expect(feedOk.status).toBe(200);
    expect(feedOk.headers.get("Aip-Contract-Version")).toBe(String(FEED_CURRENT));

    const vendorMissing = await vendorCall("listOperatorCredentials", {});
    expect(vendorMissing.result).toBe("rejected");
    expect(vendorMissing.code).toBe("contract_version_unsupported");

    const vendorOk = await vendorCall("listOperatorCredentials", {
      contract_version: VENDOR_CURRENT,
    });
    expect(vendorOk.result).toBe("ok");

    const installationId = crypto.randomUUID();
    const doAccepted = await fetchGatewayObjectRpc(installationId, {
      contract_version: DO_CURRENT - 1,
      kind: "inspect",
    });
    expect(doAccepted.ok).toBe(true);
    const doAcceptedBody = (await doAccepted.json()) as Record<string, unknown>;
    expect(doAcceptedBody.contract_version).toBe(DO_CURRENT - 1);

    const doRefused = await fetchGatewayObjectRpc(installationId, {
      kind: "inspect",
    });
    expect(doRefused.ok).toBe(true);
    const doRefusedBody = (await doRefused.json()) as Record<string, unknown>;
    expect(doRefusedBody.result).toBe("rejected");
    expect(doRefusedBody.code).toBe("contract_version_unsupported");
    expect(doRefusedBody.accepted_versions).toEqual(ACCEPTED_VERSIONS);
    expect(doRefusedBody.contract_version).toBe(DO_CURRENT);

    const badVerToken = await mintAat(scenario, { ver: "1" });
    const tokenRefused = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, {
        headers: {
          authorization: `Bearer ${badVerToken}`,
          "Aip-Contract-Version": String(RECEIVER_CURRENT),
        },
      }),
    );
    expect(tokenRefused.status).toBe(401);
  });
});
