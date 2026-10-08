import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { getPlatformProxy } from "wrangler";
import {
  billingFetch,
  countAboTable,
  countAboWork,
  ensurePlatformGrantPrerequisites,
  HARNESS_URL,
  issueFeedToken,
  mintAccessJwt,
  opsFetch,
  platformFetch,
  queryAboD1One,
  queryPlatformD1One,
  rpc,
  sqlLiteral,
  startStack,
  triggerAboScheduled,
} from "./p7-3-stack.mjs";

// H-FS unit harness (P7.3 US1): node --import tsx --test test/p7-3-01.test.mjs

const ABO_N_PLUS_1 = "test/variant/abo-n-plus-1.toml";
const PLATFORM_N_PLUS_1 = "test/variant/platform-n-plus-1.toml";

const RECEIVER_CURRENT = 2;
const ACCEPTED_VERSIONS = [1, 2];
const PAYMOB_ADAPTER_VERSION = 2;

let stack = null;
let platformProxy = null;

before(async () => {
  stack = await startStack({
    aboConfig: ABO_N_PLUS_1,
    platformConfig: PLATFORM_N_PLUS_1,
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

async function vendorCall(method, args) {
  const response = await fetch(`${HARNESS_URL}/vendor-call`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ method, args }),
  });
  return response.json();
}

function installationIdForOrg(orgId) {
  const row = queryPlatformD1One(
    `SELECT installation_id FROM tenant_binding WHERE org_id = ${sqlLiteral(orgId)} AND status = 'active'`,
  );
  return row?.installation_id ?? null;
}

async function fetchGatewayObjectRpc(installationId, body) {
  const stub = platformProxy.env.DO.get(
    platformProxy.env.DO.idFromName(installationId),
  );
  return stub.fetch("https://quota-do.internal/rpc", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function expectAboClinicRefusal(pathname, version) {
  const headers = { authorization: "Bearer invalid-token" };
  if (version !== undefined) {
    headers["Abo-Contract-Version"] = String(version);
  }
  const notificationsBefore = countAboTable("notification");
  const response = await billingFetch(pathname, { headers });
  assert.equal(response.status, 400);
  const body = await response.json();
  assert.equal(body.code, "contract_version_unsupported");
  assert.deepEqual(body.accepted_versions, ACCEPTED_VERSIONS);
  assert.equal(body.contract_version, RECEIVER_CURRENT);
  assert.equal(response.headers.get("Abo-Contract-Version"), String(RECEIVER_CURRENT));
  assert.equal(countAboTable("notification"), notificationsBefore);
}

async function expectAboConsoleRefusal(pathname, version) {
  const headers = {};
  if (version !== undefined) {
    headers["Abo-Contract-Version"] = String(version);
  }
  const workBefore = countAboWork();
  const response = await opsFetch(pathname, { headers });
  assert.equal(response.status, 400);
  const body = await response.json();
  assert.equal(body.code, "contract_version_unsupported");
  assert.equal(body.reload, true);
  assert.deepEqual(body.accepted_versions, ACCEPTED_VERSIONS);
  assert.equal(countAboWork(), workBefore);
}

async function expectPlatformClinicRefusal(pathname, init = {}) {
  const headers = new Headers(init.headers ?? {});
  if (!headers.has("Aip-Contract-Version")) {
    headers.delete("Aip-Contract-Version");
  }
  const response = await platformFetch(pathname, { ...init, headers });
  assert.equal(response.status, 400);
  const body = await response.json();
  assert.equal(body.code, "contract_version_unsupported");
  assert.deepEqual(body.accepted_versions, ACCEPTED_VERSIONS);
}

test("E2E-P7.3-01", async () => {
  const { administrator, orgId, installationId } = stack.clinics.orgA;
  ensurePlatformGrantPrerequisites(orgId, installationId);

  for (const version of [undefined, 0, 3]) {
    await expectAboClinicRefusal("/v1/offers", version);
    await expectAboConsoleRefusal("/ops/lookup", version);
    await expectPlatformClinicRefusal("/v1/capabilities", {
      headers: version === undefined
        ? { authorization: "Bearer invalid-token" }
        : {
            authorization: "Bearer invalid-token",
            "Aip-Contract-Version": String(version),
          },
    });
    await expectPlatformClinicRefusal("/v1/coverage", {
      headers: version === undefined
        ? { authorization: "Bearer invalid-token" }
        : {
            authorization: "Bearer invalid-token",
            "Aip-Contract-Version": String(version),
          },
    });
    await expectPlatformClinicRefusal("/v1/requests", {
      method: "POST",
      headers: {
        authorization: "Bearer invalid-token",
        "content-type": "application/json",
        "x-idempotency-key": crypto.randomUUID(),
        "x-capability-version": "1.0.0",
        ...(version === undefined ? {} : { "Aip-Contract-Version": String(version) }),
      },
      body: JSON.stringify({ capability_id: "clinic.visit_summary" }),
    });
  }

  const aiToken = await rpc(administrator, "issue_ai_token", {
    p_contract_version: RECEIVER_CURRENT,
  });
  assert.ok(aiToken);

  const capabilitiesV2 = await platformFetch("/v1/capabilities", {
    headers: {
      authorization: `Bearer ${aiToken}`,
      "Aip-Contract-Version": "2",
    },
  });
  assert.equal(capabilitiesV2.status, 200);
  assert.equal(capabilitiesV2.headers.get("Aip-Contract-Version"), "2");

  const capabilitiesV1 = await platformFetch("/v1/capabilities", {
    headers: {
      authorization: `Bearer ${aiToken}`,
      "Aip-Contract-Version": "1",
    },
  });
  assert.equal(capabilitiesV1.status, 200);
  assert.equal(capabilitiesV1.headers.get("Aip-Contract-Version"), "1");

  const feedToken = issueFeedToken();
  const feedRefused = await platformFetch("/v1/feed/coverage?after=0&limit=1", {
    headers: {
      authorization: `Bearer ${feedToken}`,
      "Aip-Contract-Version": "0",
    },
  });
  assert.equal(feedRefused.status, 400);
  const feedRefusedBody = await feedRefused.json();
  assert.equal(feedRefusedBody.code, "contract_version_unsupported");

  const feedOk = await platformFetch("/v1/feed/coverage?after=0&limit=1", {
    headers: {
      authorization: `Bearer ${feedToken}`,
      "Aip-Contract-Version": "2",
    },
  });
  assert.equal(feedOk.status, 200);
  assert.equal(feedOk.headers.get("Aip-Contract-Version"), "2");

  const vendorMissing = await vendorCall("listOperatorCredentials", {});
  assert.equal(vendorMissing.result, "rejected");
  assert.equal(vendorMissing.code, "contract_version_unsupported");

  const vendorOk = await vendorCall("listOperatorCredentials", {
    contract_version: RECEIVER_CURRENT,
  });
  assert.equal(vendorOk.result, "ok");

  const doInstallationId = installationIdForOrg(orgId);
  assert.ok(doInstallationId);
  const doAccepted = await fetchGatewayObjectRpc(doInstallationId, {
    contract_version: 1,
    kind: "inspect",
  });
  assert.equal(doAccepted.status, 200);
  const doAcceptedBody = await doAccepted.json();
  assert.equal(doAcceptedBody.contract_version, 1);

  const doRefused = await fetchGatewayObjectRpc(doInstallationId, {
    contract_version: 3,
    kind: "inspect",
  });
  const doRefusedBody = await doRefused.json();
  assert.equal(doRefusedBody.result, "rejected");
  assert.equal(doRefusedBody.code, "contract_version_unsupported");
  assert.deepEqual(doRefusedBody.accepted_versions, ACCEPTED_VERSIONS);

  const returnResponse = await billingFetch("/return/paymob?v=99");
  assert.equal(returnResponse.status, 200);
  const returnHtml = (await returnResponse.text()).toLowerCase();
  assert.equal(returnHtml.includes("contract_version_unsupported"), false);

  const billingV2 = await rpc(administrator, "issue_billing_token", {
    p_contract_version: 2,
  });
  assert.equal(billingV2.success, true);
  assert.equal(billingV2.contract_version, 2);

  const billingBadVer = await billingFetch("/v1/offers", {
    headers: {
      authorization: "Bearer invalid-token",
      "Abo-Contract-Version": "2",
    },
  });
  assert.equal(billingBadVer.status, 401);
  const billingBadVerBody = await billingBadVer.json();
  assert.equal(billingBadVerBody.code, "unauthenticated");

  const notificationsBefore = countAboTable("notification");
  const unparseable = await billingFetch("/notify/paymob?hmac=deadbeef", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": "203.0.113.88",
    },
    body: JSON.stringify({ type: "TRANSACTION" }),
  });
  assert.equal(unparseable.status, 200);
  assert.equal(countAboTable("notification"), notificationsBefore + 1);
  const evidence = queryAboD1One(
    "SELECT adapter_version FROM notification ORDER BY notification_id DESC LIMIT 1",
  );
  assert.equal(evidence?.adapter_version, PAYMOB_ADAPTER_VERSION);
  const alertRow = queryAboD1One(
    `SELECT code FROM alert WHERE code = 'AL-23' ORDER BY alert_key DESC LIMIT 1`,
  );
  assert.equal(alertRow?.code, "AL-23");

  const accessJwt = await mintAccessJwt(stack.accessTeam);
  const unknownAnswer = await vendorCall("grant", {
    contract_version: RECEIVER_CURRENT,
    abo_kid: "missing-kid",
    abo_signature: "missing-signature",
    envelope_b64: "e30=",
    access_jwt: accessJwt,
    answer_contract_version: RECEIVER_CURRENT + 1,
  });
  assert.equal(unknownAnswer.result, "rejected");
  assert.equal(unknownAnswer.code, "contract_version_unsupported");

  await triggerAboScheduled("0 * * * *");
  const parkedGrant = queryAboD1One(
    `SELECT state, last_error FROM work WHERE kind = 'grant' ORDER BY opened_at DESC LIMIT 1`,
  );
  if (parkedGrant) {
    assert.match(String(parkedGrant.last_error ?? ""), /contract_version_unsupported/);
  }
});
