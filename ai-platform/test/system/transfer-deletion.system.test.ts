/**
 * P3.8 — Transfer, deletion with coverage left, ledger retention (H-AP).
 */

import { env, runDurableObjectAlarm, runInDurableObject, SELF } from "cloudflare:test";
import { CHANNEL_VERSIONS, grantIdPaid, sha256Hex } from "vendor-contracts";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  applyAllMigrations,
  coverClinic,
  coverClinicAboKid,
  coverClinicSigner,
  encodeVendorAssertion,
  fakePolicyDocument,
  GATEWAY_ORIGIN,
  getCapturedVendorEmails,
  getVendorTestClockIso,
  invoke,
  mintAat,
  mintVendorAccessJwt,
  newClinic,
  newScenario,
  POLICY_ID,
  POLICY_VERSION,
  promote,
  publishPolicy,
  queryAll,
  queryOne,
  registerVisitSummaryCapability,
  resetPlatformState,
  runScheduled,
  setTestClock,
  setupVendorHarness,
  signCoverAbo,
  vendorCall,
  VENDOR_OPERATOR_EMAIL,
  clearCapturedVendorEmails,
  count,
  type Scenario,
  type VendorMethod,
  type VendorResultEnvelope,
} from "./harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;

const PLAN_ID = "live-monthly";
const PLAN_VERSION = 1;
const PLAN_MAX_ALLOWANCE = 10_000;

type GrantResultEnvelope = VendorResultEnvelope & {
  receipt?: Record<string, unknown>;
};

type P38VendorMethod =
  | VendorMethod
  | "beginTransfer"
  | "transferOut"
  | "transferIn"
  | "deleteInstallation"
  | "voidGrant";

const p38VendorCall = vendorCall as (
  method: P38VendorMethod,
  args: Record<string, unknown>,
  opts?: {
    accessJwt?: string;
    assertion?: Record<string, unknown>;
  },
) => Promise<GrantResultEnvelope>;

function quotaDoStub(installationId: string) {
  return env.DO.get(env.DO.idFromName(installationId));
}

function sqlSelect<T extends Record<string, unknown>>(
  state: DurableObjectState,
  query: string,
): T[] {
  const storage = state.storage as DurableObjectStorage & {
    sql?: { exec: (q: string) => Iterable<T> };
  };
  if (!storage.sql) {
    return [];
  }
  return [...storage.sql.exec(query)];
}

type DoTermRow = {
  term_id: string;
  grant_id: string;
  origin_grant_id: string;
  state: string;
  end_reason: string | null;
  position: number;
  allowance: number | null;
  ends_at: string | null;
  grace_ends_at: string | null;
};

async function readDoTerms(installationId: string): Promise<DoTermRow[]> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect<DoTermRow>(
      state,
      `SELECT term_id, grant_id, origin_grant_id, state, end_reason, position, allowance,
              ends_at, grace_ends_at
       FROM term ORDER BY position ASC`,
    ),
  );
}

async function readHotUsed(installationId: string): Promise<number> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ used: number }>(state, "SELECT used FROM hot LIMIT 1"),
  );
  return rows[0]?.used ?? 0;
}

async function buildPaidGrantEnvelope(input: {
  orgId: string;
  grantId: string;
  allowanceCredits?: number;
}): Promise<Record<string, unknown>> {
  const paidAt = getVendorTestClockIso() ?? new Date().toISOString();
  const paymentRef = crypto.randomUUID().replace(/-/g, "");
  const contentSha256 = await sha256Hex(new TextEncoder().encode(paymentRef));
  return {
    contract_version: CONTRACT_VERSION,
    grant_id: input.grantId,
    org_id: input.orgId,
    kind: "term",
    placement: "queue",
    source: { kind: "paid", ref: paymentRef },
    plan: { plan_id: PLAN_ID, plan_version: PLAN_VERSION },
    duration: { unit: "month", count: 1 },
    allowance_credits: input.allowanceCredits ?? PLAN_MAX_ALLOWANCE,
    grace: { days: 7, cap_rule: "proportional" },
    paid_at: paidAt,
    evidence: {
      content_sha256: contentSha256,
      approvals: [{ credential_id: "cred-001", assertion: "stub" }],
    },
  };
}

async function paidGrant(
  scenario: Scenario,
  grantId: string,
  opts: { installationId?: string } = {},
): Promise<GrantResultEnvelope> {
  const envelope = await buildPaidGrantEnvelope({
    orgId: scenario.orgId,
    grantId,
  });
  const aboSignature = await signCoverAbo(envelope);
  const args: Record<string, unknown> = {
    contract_version: CONTRACT_VERSION,
    envelope,
    abo_kid: coverClinicAboKid(),
    abo_signature: aboSignature,
  };
  if (opts.installationId !== undefined) {
    args.installation_id = opts.installationId;
  }
  return p38VendorCall("grant", args);
}

async function operationForHp(input: {
  op: "beginTransfer" | "deleteInstallation";
  accessJwt: string;
  params: Record<string, unknown>;
}): Promise<Record<string, unknown>> {
  return {
    op: input.op,
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      ...input.params,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function hpBeginTransfer(input: {
  orgId: string;
  fromInstallationId: string;
  reason?: string;
}): Promise<GrantResultEnvelope> {
  const signer = coverClinicSigner();
  const accessJwt = await mintVendorAccessJwt();
  const operation = await operationForHp({
    op: "beginTransfer",
    accessJwt,
    params: {
      org_id: input.orgId,
      from_installation_id: input.fromInstallationId,
      reason: input.reason ?? "clinic relocation",
    },
  });
  const assertion = encodeVendorAssertion(
    await signer.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  return p38VendorCall(
    "beginTransfer",
    {
      contract_version: CONTRACT_VERSION,
      org_id: input.orgId,
      from_installation_id: input.fromInstallationId,
      reason: input.reason ?? "clinic relocation",
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function hpDeleteInstallation(input: {
  orgId: string;
  reason?: string;
}): Promise<GrantResultEnvelope> {
  const signer = coverClinicSigner();
  const accessJwt = await mintVendorAccessJwt();
  const operation = await operationForHp({
    op: "deleteInstallation",
    accessJwt,
    params: {
      org_id: input.orgId,
      reason: input.reason ?? "decommission",
    },
  });
  const assertion = encodeVendorAssertion(
    await signer.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  return p38VendorCall(
    "deleteInstallation",
    {
      contract_version: CONTRACT_VERSION,
      org_id: input.orgId,
      reason: input.reason ?? "decommission",
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function transferOut(transferId: string): Promise<GrantResultEnvelope> {
  return p38VendorCall("transferOut", {
    contract_version: CONTRACT_VERSION,
    transfer_id: transferId,
  });
}

async function transferIn(transferId: string): Promise<GrantResultEnvelope> {
  return p38VendorCall("transferIn", {
    contract_version: CONTRACT_VERSION,
    transfer_id: transferId,
  });
}

async function getCoverageForInstallation(
  orgId: string,
  installationId: string,
): Promise<VendorResultEnvelope> {
  return p38VendorCall("getCoverage", {
    contract_version: CONTRACT_VERSION,
    org_id: orgId,
    installation_id: installationId,
  });
}

async function inspectCoverageTerms(
  scenario: Scenario,
): Promise<DoTermRow[]> {
  const accessJwt = await mintVendorAccessJwt();
  const inspected = await p38VendorCall(
    "inspectCoverage",
    {
      contract_version: CONTRACT_VERSION,
      org_id: scenario.orgId,
    },
    { accessJwt },
  );
  expect(inspected.result).toBe("ok");
  const detail = JSON.parse(inspected.detail) as { terms: DoTermRow[] };
  return detail.terms;
}

async function setupPromotedPolicy(scenario: Scenario): Promise<string> {
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  expect(published.status).toBe(200);
  const promoted = await promote(POLICY_ID, POLICY_VERSION);
  expect(promoted.status).toBe(200);
  return await mintAat(scenario);
}

async function expireActivePaidTerm(installationId: string): Promise<void> {
  const terms = await readDoTerms(installationId);
  const active = terms.find((row) => row.state === "active");
  expect(active?.ends_at).toBeTruthy();
  await setTestClock(String(active!.ends_at));
  await runDurableObjectAlarm(quotaDoStub(installationId));

  const afterBoundary = await readDoTerms(installationId);
  const grace = afterBoundary.find((row) => row.state === "grace");
  if (grace?.grace_ends_at) {
    await setTestClock(grace.grace_ends_at);
    await runDurableObjectAlarm(quotaDoStub(installationId));
  }

  const ended = (await readDoTerms(installationId)).find(
    (row) => row.state === "ended",
  );
  expect(ended).toBeTruthy();
}

async function operationForVoidGrant(input: {
  accessJwt: string;
  grantId: string;
  reason: string;
}): Promise<Record<string, unknown>> {
  return {
    op: "voidGrant",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      grant_id: input.grantId,
      reason: input.reason,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function hpVoidGrant(grantId: string): Promise<GrantResultEnvelope> {
  const signer = coverClinicSigner();
  const accessJwt = await mintVendorAccessJwt();
  const operation = await operationForVoidGrant({
    accessJwt,
    grantId,
    reason: "operator void",
  });
  const assertion = encodeVendorAssertion(
    await signer.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  return p38VendorCall(
    "voidGrant",
    {
      contract_version: CONTRACT_VERSION,
      grant_id: grantId,
      reason: "operator void",
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function issuerCapabilitiesFetch(
  scenario: Scenario,
): Promise<Response> {
  const token = await mintAat(scenario);
  return SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/capabilities`, {
      headers: {
        authorization: `Bearer ${token}`,
        "Aip-Contract-Version": "1",
      },
    }),
  );
}

function parseAlEmailBodies(): Array<Record<string, unknown>> {
  return getCapturedVendorEmails().map(
    (email) => JSON.parse(email.text) as Record<string, unknown>,
  );
}

function al18Emails(): Array<Record<string, unknown>> {
  return parseAlEmailBodies().filter((body) => body.code === "AL-18");
}

async function readTransferPackage(
  transferId: string,
): Promise<string | null> {
  const row = await queryOne<{ package: string | null }>(
    "SELECT package FROM transfer WHERE transfer_id = ?",
    [transferId],
  );
  return row?.package ?? null;
}

type TransferSetup = {
  scenario: Scenario;
  oldInstallationId: string;
  transferId: string;
  newInstallationId: string;
  activeGrantId: string;
  queuedGrantId: string;
};

async function setupActiveAndQueuedTerms(): Promise<{
  scenario: Scenario;
  activeGrantId: string;
  queuedGrantId: string;
}> {
  const scenario = await newScenario();
  await coverClinic(scenario);
  const termsAfterCover = await readDoTerms(scenario.installationId);
  const activeGrantId = termsAfterCover.find((row) => row.state === "active")!
    .grant_id;

  const queuedGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
  const queued = await paidGrant(scenario, queuedGrantId);
  expect(queued.result).toBe("applied");
  await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

  return { scenario, activeGrantId, queuedGrantId };
}

async function setupBeginTransferOnly(): Promise<TransferSetup> {
  const { scenario, activeGrantId, queuedGrantId } =
    await setupActiveAndQueuedTerms();
  const oldInstallationId = scenario.installationId;

  const begun = await hpBeginTransfer({
    orgId: scenario.orgId,
    fromInstallationId: oldInstallationId,
  });
  expect(begun.result).toBe("ok");
  expect(begun.code).toBe("");
  expect(begun.receipt).toBeUndefined();
  const transferRow = JSON.parse(begun.detail) as {
    transfer_id: string;
    to_installation_id: string;
    package: unknown;
  };
  expect(transferRow.package).toBeNull();
  expect(transferRow.transfer_id).toBeTruthy();

  const binding = await queryOne<{ installation_id: string }>(
    "SELECT installation_id FROM tenant_binding WHERE org_id = ? AND status = 'active'",
    [scenario.orgId],
  );
  expect(binding?.installation_id).toBe(transferRow.to_installation_id);

  return {
    scenario,
    oldInstallationId,
    transferId: transferRow.transfer_id,
    newInstallationId: transferRow.to_installation_id,
    activeGrantId,
    queuedGrantId,
  };
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
  await setupVendorHarness();
});

beforeEach(async () => {
  await resetPlatformState();
  registerVisitSummaryCapability();
  await setupVendorHarness();
});

describe("transfer, deletion with coverage left, ledger retention", () => {
  it("E2E-P3.8-01 A14 beginTransfer moves an active term and a queued term", async () => {
    const { scenario, activeGrantId, queuedGrantId } =
      await setupActiveAndQueuedTerms();
    const oldInstallationId = scenario.installationId;

    const termsBefore = await readDoTerms(oldInstallationId);
    const activeBefore = termsBefore.find((row) => row.grant_id === activeGrantId);
    const queuedBefore = termsBefore.find((row) => row.grant_id === queuedGrantId);
    expect(activeBefore?.state).toBe("active");
    expect(queuedBefore?.state).toBe("queued");
    const hotUsed = await readHotUsed(oldInstallationId);

    const begun = await hpBeginTransfer({
      orgId: scenario.orgId,
      fromInstallationId: oldInstallationId,
    });
    expect(begun.result).toBe("ok");
    expect(begun.code).toBe("");
    expect(begun.receipt).toBeUndefined();
    const transferRow = JSON.parse(begun.detail) as {
      transfer_id: string;
      to_installation_id: string;
      package: unknown;
    };
    expect(transferRow.package).toBeNull();
    expect(transferRow.transfer_id).toBeTruthy();

    const out = await transferOut(transferRow.transfer_id);
    expect(out.result).toBe("applied");
    expect(out.receipt).toBeDefined();
    await runDurableObjectAlarm(quotaDoStub(oldInstallationId));

    clearCapturedVendorEmails();
    const inResult = await transferIn(transferRow.transfer_id);
    expect(inResult.result).toBe("applied");
    expect(inResult.receipt).toBeDefined();
    await runDurableObjectAlarm(quotaDoStub(transferRow.to_installation_id));

    const newTerms = await readDoTerms(transferRow.to_installation_id);
    const oldOrigins = termsBefore.map((row) => row.origin_grant_id).sort();
    const newOrigins = newTerms.map((row) => row.origin_grant_id).sort();
    expect(newOrigins).toEqual(oldOrigins);

    const newActive = newTerms.find(
      (row) => row.origin_grant_id === activeBefore!.origin_grant_id,
    );
    const newQueued = newTerms.find(
      (row) => row.origin_grant_id === queuedBefore!.origin_grant_id,
    );
    expect(newActive?.allowance).toBe((activeBefore!.allowance ?? 0) - hotUsed);
    expect(newQueued?.allowance).toBe(queuedBefore?.allowance);

    const oldCoverage = await getCoverageForInstallation(
      scenario.orgId,
      oldInstallationId,
    );
    expect(oldCoverage.result).toBe("ok");
    const oldSnapshot = JSON.parse(oldCoverage.detail) as {
      snapshot: { state: string };
    };
    expect(oldSnapshot.snapshot.state).toBe("transferred");

    const rejected = await paidGrant(
      scenario,
      await grantIdPaid(crypto.randomUUID().replace(/-/g, "")),
      { installationId: oldInstallationId },
    );
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("transferred_out");

    const al11Bodies = parseAlEmailBodies().filter(
      (body) => body.code === "AL-11",
    );
    expect(al11Bodies.some((body) => body.transfer_id === transferRow.transfer_id)).toBe(
      true,
    );

    const events = await queryAll<{ binding_epoch: number }>(
      `SELECT binding_epoch FROM coverage_event
       WHERE installation_id = ? AND kind = 'transfer'
       ORDER BY feed_seq ASC`,
      [transferRow.to_installation_id],
    );
    expect(events.length).toBeGreaterThan(0);
    expect(events.every((row) => row.binding_epoch === 2)).toBe(true);
  });

  it("E2E-P3.8-02 a non-transfer grant during awaiting_transfer is transient and then queues behind the moved terms", async () => {
    const setup = await setupBeginTransferOnly();
    const { scenario, transferId, newInstallationId } = setup;

    const originsBefore = (await readDoTerms(setup.oldInstallationId)).map(
      (row) => row.origin_grant_id,
    );

    const pendingGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    const pending = await paidGrant(scenario, pendingGrantId);
    expect(pending.result).toBe("transient");
    expect(pending.detail).toBe("awaiting_transfer");
    const termsMid = await readDoTerms(newInstallationId);
    expect(termsMid.find((row) => row.grant_id === pendingGrantId)).toBeUndefined();

    const out = await transferOut(transferId);
    expect(out.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(setup.oldInstallationId));

    const inResult = await transferIn(transferId);
    expect(inResult.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(newInstallationId));

    const applied = await paidGrant(scenario, pendingGrantId);
    expect(applied.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(newInstallationId));

    const inspected = await inspectCoverageTerms(scenario);
    const moved = inspected.filter((row) =>
      originsBefore.includes(row.origin_grant_id),
    );
    const pendingTerm = inspected.find((row) => row.grant_id === pendingGrantId);
    expect(pendingTerm?.state).toBe("queued");
    const maxMovedPosition = Math.max(...moved.map((row) => row.position));
    expect(pendingTerm!.position).toBeGreaterThan(maxMovedPosition);
  });

  it("E2E-P3.8-03 transfer steps retry as already_applied and transferIn before transferOut is transient", async () => {
    const { scenario, activeGrantId, queuedGrantId } =
      await setupActiveAndQueuedTerms();
    const oldInstallationId = scenario.installationId;

    const begun = await hpBeginTransfer({
      orgId: scenario.orgId,
      fromInstallationId: oldInstallationId,
    });
    expect(begun.result).toBe("ok");
    const transferRow = JSON.parse(begun.detail) as { transfer_id: string };
    const transferId = transferRow.transfer_id;

    const termsBefore = await readDoTerms(oldInstallationId);
    const packageBefore = await readTransferPackage(transferId);

    const earlyIn = await transferIn(transferId);
    expect(earlyIn.result).toBe("transient");
    expect(earlyIn.detail).toBe("awaiting_transfer_out");
    const termsAfterEarly = await readDoTerms(oldInstallationId);
    expect(termsAfterEarly).toEqual(termsBefore);
    expect(await readTransferPackage(transferId)).toBe(packageBefore);

    const out = await transferOut(transferId);
    expect(out.result).toBe("applied");
    expect(out.receipt).toBeDefined();
    const outReceipt = out.receipt as Record<string, unknown>;

    const inResult = await transferIn(transferId);
    expect(inResult.result).toBe("applied");
    expect(inResult.receipt).toBeDefined();
    const inReceipt = inResult.receipt as Record<string, unknown>;

    const outRetry = await transferOut(transferId);
    expect(outRetry.result).toBe("already_applied");
    expect(outRetry.receipt).toEqual(outReceipt);

    const inRetry = await transferIn(transferId);
    expect(inRetry.result).toBe("already_applied");
    expect(inRetry.receipt).toEqual(inReceipt);

    expect(activeGrantId).toBeTruthy();
    expect(queuedGrantId).toBeTruthy();
  });

  it("E2E-P3.8-04 A24 delete with paid time left holds the binding", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const installationId = scenario.installationId;

    clearCapturedVendorEmails();
    const deleted = await hpDeleteInstallation({ orgId: scenario.orgId });
    expect(deleted.result).toBe("ok");
    expect(deleted.code).toBe("");
    expect(deleted.receipt).toBeUndefined();
    const effects = JSON.parse(deleted.detail) as {
      installation: { status: string };
      tenant_binding: { status: string };
    };
    expect(effects.installation.status).toBe("deleted");
    expect(effects.tenant_binding.status).toBe("held_for_transfer");

    const token = await setupPromotedPolicy(scenario);
    const denied = await invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(denied.status).toBe(403);
    expect(denied.body?.code).toBe("coverage_lapsed");
    expect(denied.body?.coverage_reason).toBe("transfer_pending");

    const grantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    const grantDuringHold = await paidGrant(scenario, grantId);
    expect(grantDuringHold.result).toBe("transient");
    expect(grantDuringHold.detail).toBe("transfer_pending");

    const bindingsBefore = await count("tenant_binding", "org_id = ?", [
      scenario.orgId,
    ]);
    const capResponse = await issuerCapabilitiesFetch(scenario);
    expect(capResponse.status).toBe(200);
    expect(await count("tenant_binding", "org_id = ?", [scenario.orgId])).toBe(
      bindingsBefore,
    );

    expect(al18Emails()).toHaveLength(1);

    clearCapturedVendorEmails();
    const repeatDelete = await hpDeleteInstallation({ orgId: scenario.orgId });
    expect(repeatDelete.result).toBe("ok");
    expect(al18Emails()).toHaveLength(0);

    const clockIso = getVendorTestClockIso() ?? new Date().toISOString();
    await setTestClock(
      new Date(Date.parse(clockIso) + 24 * 60 * 60 * 1000).toISOString(),
    );
    clearCapturedVendorEmails();
    await runScheduled("0 3 * * *");
    expect(al18Emails().length).toBeGreaterThanOrEqual(1);

    const transfer = await hpBeginTransfer({
      orgId: scenario.orgId,
      fromInstallationId: installationId,
    });
    expect(transfer.result).toBe("ok");
  });

  it("E2E-P3.8-05 delete with no coverage retires the binding and the next token creates epoch 2", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await expireActivePaidTerm(scenario.installationId);

    const deleted = await hpDeleteInstallation({ orgId: scenario.orgId });
    expect(deleted.result).toBe("ok");
    const effects = JSON.parse(deleted.detail) as {
      tenant_binding: { status: string };
    };
    expect(effects.tenant_binding.status).toBe("retired");

    const capResponse = await issuerCapabilitiesFetch(scenario);
    expect(capResponse.status).toBe(200);

    const binding = await queryOne<{ epoch: number; status: string }>(
      "SELECT epoch, status FROM tenant_binding WHERE org_id = ? ORDER BY epoch DESC LIMIT 1",
      [scenario.orgId],
    );
    expect(binding?.status).toBe("active");
    expect(binding?.epoch).toBe(2);
  });

  it("E2E-P3.8-06 voiding the remaining grants of a held binding retires it", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    const deleted = await hpDeleteInstallation({ orgId: scenario.orgId });
    expect(deleted.result).toBe("ok");
    const held = await queryOne<{ epoch: number; status: string }>(
      "SELECT epoch, status FROM tenant_binding WHERE org_id = ? AND installation_id = ?",
      [scenario.orgId, scenario.installationId],
    );
    expect(held?.status).toBe("held_for_transfer");

    const terms = await readDoTerms(scenario.installationId);
    const openTerms = terms.filter(
      (row) =>
        row.state === "active" ||
        row.state === "grace" ||
        row.state === "queued" ||
        row.state === "held",
    );
    for (const term of openTerms) {
      const voided = await hpVoidGrant(term.grant_id);
      expect(voided.result).toBe("applied");
      await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    }

    const retired = await queryOne<{ status: string }>(
      "SELECT status FROM tenant_binding WHERE org_id = ? AND installation_id = ?",
      [scenario.orgId, scenario.installationId],
    );
    expect(retired?.status).toBe("retired");

    const capResponse = await issuerCapabilitiesFetch(scenario);
    expect(capResponse.status).toBe(200);

    const latest = await queryOne<{ epoch: number }>(
      "SELECT epoch FROM tenant_binding WHERE org_id = ? ORDER BY epoch DESC LIMIT 1",
      [scenario.orgId],
    );
    expect(latest?.epoch).toBe((held?.epoch ?? 0) + 1);
  });
});
