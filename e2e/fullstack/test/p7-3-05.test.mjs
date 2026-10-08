import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { getPlatformProxy } from "wrangler";
import {
  CAPABILITY_VERSION,
  ensurePlatformGrantPrerequisites,
  platformFetch,
  sqlLiteral,
  startStack,
} from "./p7-3-stack.mjs";

// H-FS unit harness (P7.3 US1): node --import tsx --test test/p7-3-05.test.mjs

const PLATFORM_WORKER_N = "test/variant/platform-worker-n.toml";
const PLATFORM_DO_RECEIVER = "test/variant/platform-do-receiver.toml";

const WORKER_VERSION = 1;
const DO_RECEIVER_CURRENT = 2;
const ACCEPTED_VERSIONS = [1, 2];

let stack = null;
let platformProxy = null;

before(async () => {
  stack = await startStack({
    platformConfig: PLATFORM_WORKER_N,
    platformDoReceiverConfig: PLATFORM_DO_RECEIVER,
  });
  platformProxy = await getPlatformProxy({
    configPath: stack.platformConfigPath,
    environment: "development",
    persist: { path: stack.platformPersistPath },
  });
});

after(async () => {
  await platformProxy?.dispose();
  platformProxy = null;
  await stack?.stop();
  stack = null;
});

function installationIdForOrg(orgId) {
  const row = stack.queryPlatformD1One(
    `SELECT installation_id FROM tenant_binding WHERE org_id = ${sqlLiteral(orgId)} AND status = 'active'`,
  );
  return row?.installation_id ?? null;
}

async function postAdmissionRequest({ token, contractVersion, idempotencyKey }) {
  const headers = {
    authorization: `Bearer ${token}`,
    "content-type": "application/json",
    "x-idempotency-key": idempotencyKey,
    "x-capability-version": CAPABILITY_VERSION,
  };
  if (contractVersion !== undefined) {
    headers["Aip-Contract-Version"] = String(contractVersion);
  }
  return platformFetch("/v1/requests", {
    method: "POST",
    headers,
    body: JSON.stringify({ capability_id: "clinic.visit_summary" }),
  });
}

test("E2E-P7.3-05", async () => {
  const { orgId, installationId } = stack.clinics.orgA;
  ensurePlatformGrantPrerequisites(orgId, installationId);
  const boundInstallationId = installationIdForOrg(orgId);
  assert.ok(boundInstallationId);

  const token = await stack.mintPlatformToken(orgId, installationId);
  const accepted = await postAdmissionRequest({
    token,
    contractVersion: WORKER_VERSION,
    idempotencyKey: crypto.randomUUID(),
  });
  assert.equal(accepted.status, 200);
  assert.equal(accepted.headers.get("Aip-Contract-Version"), String(WORKER_VERSION));

  const missingVersion = await postAdmissionRequest({
    token,
    contractVersion: undefined,
    idempotencyKey: crypto.randomUUID(),
  });
  assert.equal(missingVersion.status, 503);
  const missingBody = await missingVersion.json();
  assert.equal(missingBody.code, "coverage_unknown");

  const unsupported = await postAdmissionRequest({
    token,
    contractVersion: 3,
    idempotencyKey: crypto.randomUUID(),
  });
  assert.equal(unsupported.status, 503);
  const unsupportedBody = await unsupported.json();
  assert.equal(unsupportedBody.code, "coverage_unknown");

  const doRefused = await platformProxy.env.DO.get(
    platformProxy.env.DO.idFromName(boundInstallationId),
  ).fetch("https://quota-do.internal/rpc", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ kind: "inspect", contract_version: 3 }),
  });
  const doRefusedBody = await doRefused.json();
  assert.equal(doRefusedBody.result, "rejected");
  assert.equal(doRefusedBody.code, "contract_version_unsupported");
  assert.deepEqual(doRefusedBody.accepted_versions, ACCEPTED_VERSIONS);
  assert.equal(doRefusedBody.contract_version, DO_RECEIVER_CURRENT);
});
