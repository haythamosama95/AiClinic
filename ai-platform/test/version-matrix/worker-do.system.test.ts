/**
 * P7.3 — Worker N / DO N+1 pairing (E2E-P7.3-05).
 */

import { env, SELF } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_VERSION,
  GATEWAY_ORIGIN,
  mintAat,
  newScenario,
  registerVisitSummaryCapability,
  resetPlatformState,
  setupPromotedFakePolicy,
  visitSummaryInvokeBody,
} from "../system/harness";

const WORKER_VERSION = 1;
const DO_RECEIVER_CURRENT = 2;
const ACCEPTED_VERSIONS = [1, 2];

const DO_RPC_URL = "https://quota-do.internal/rpc";

function quotaDoStub(installationId: string) {
  return env.DO.get(env.DO.idFromName(installationId));
}

async function postAdmissionRequest({
  token,
  contractVersion,
  idempotencyKey,
}: {
  token: string;
  contractVersion?: number;
  idempotencyKey: string;
}) {
  const headers: Record<string, string> = {
    authorization: `Bearer ${token}`,
    "content-type": "application/json",
    "x-idempotency-key": idempotencyKey,
    "x-capability-version": CAPABILITY_VERSION,
  };
  if (contractVersion !== undefined) {
    headers["Aip-Contract-Version"] = String(contractVersion);
  }
  return SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
      method: "POST",
      headers,
      body: JSON.stringify({ capability_id: "clinic.visit_summary" }),
    }),
  );
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
});

describe("E2E-P7.3-05", () => {
  it("E2E-P7.3-05", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);
    const token = await mintAat(scenario);

    const accepted = await postAdmissionRequest({
      token,
      contractVersion: WORKER_VERSION,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(accepted.status).toBe(200);
    expect(accepted.headers.get("Aip-Contract-Version")).toBe(
      String(WORKER_VERSION),
    );

    const missingVersion = await postAdmissionRequest({
      token,
      contractVersion: undefined,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(missingVersion.status).toBe(503);
    const missingBody = (await missingVersion.json()) as Record<string, unknown>;
    expect(missingBody.code).toBe("coverage_unknown");

    const unsupported = await postAdmissionRequest({
      token,
      contractVersion: 3,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(unsupported.status).toBe(503);
    const unsupportedBody = (await unsupported.json()) as Record<string, unknown>;
    expect(unsupportedBody.code).toBe("coverage_unknown");

    const doRefused = await quotaDoStub(scenario.installationId).fetch(
      DO_RPC_URL,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kind: "inspect", contract_version: 3 }),
      },
    );
    const doRefusedBody = (await doRefused.json()) as Record<string, unknown>;
    expect(doRefusedBody.result).toBe("rejected");
    expect(doRefusedBody.code).toBe("contract_version_unsupported");
    expect(doRefusedBody.accepted_versions).toEqual(ACCEPTED_VERSIONS);
    expect(doRefusedBody.contract_version).toBe(DO_RECEIVER_CURRENT);
  });
});
