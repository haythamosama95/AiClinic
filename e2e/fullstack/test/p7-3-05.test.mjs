import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { ensurePlatformActiveCoverage } from "./p7-2-stack.mjs";
import {
  CAPABILITY_VERSION,
  ensurePlatformGrantPrerequisites,
  platformFetch,
  sqlLiteral,
  startStack,
} from "./p7-3-stack.mjs";

// H-FS unit harness (P7.3 US1): node --import tsx --test test/p7-3-05.test.mjs

const PLATFORM_WORKER_N = "test/variant/platform-worker-n.toml";

const WORKER_VERSION = 1;
const CLINIC_ACCEPTED_VERSIONS = [0, 1];

let stack = null;

before(async () => {
  stack = await startStack({
    platformConfig: PLATFORM_WORKER_N,
    platformDoReceiverConfig: "test/variant/platform-do-receiver.toml",
  });
});

after(async () => {
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
    body: JSON.stringify({
      capability_id: "clinic.visit_summary",
      context: {
        org: stack.clinics.orgA.orgId,
        branch: stack.clinics.orgA.branchId,
        "visit.chief_complaint@v1": {
          visit_id: stack.clinics.orgA.branchId,
          complaint: "Persistent headache for three days.",
          recorded_at: "2026-07-31T12:00:00Z",
        },
      },
    }),
  });
}

test("E2E-P7.3-05", async () => {
  const { orgId, installationId } = stack.clinics.orgA;
  ensurePlatformGrantPrerequisites(orgId, installationId);
  await ensurePlatformActiveCoverage(stack, orgId, installationId);
  const boundInstallationId = installationIdForOrg(orgId);
  assert.ok(
    boundInstallationId,
    `platform tenant binding should be ready for org=${orgId}, installation=${installationId}`,
  );

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
  assert.equal(missingVersion.status, 400);
  const missingBody = await missingVersion.json();
  assert.equal(missingBody.code, "contract_version_unsupported");
  assert.deepEqual(missingBody.accepted_versions, CLINIC_ACCEPTED_VERSIONS);

  const unsupported = await postAdmissionRequest({
    token,
    contractVersion: 3,
    idempotencyKey: crypto.randomUUID(),
  });
  assert.equal(unsupported.status, 400);
  const unsupportedBody = await unsupported.json();
  assert.equal(unsupportedBody.code, "contract_version_unsupported");
  assert.deepEqual(unsupportedBody.accepted_versions, CLINIC_ACCEPTED_VERSIONS);

});
