/**
 * P3.8 — Transfer, deletion with coverage left, ledger retention (H-AP).
 */

import { env, runDurableObjectAlarm, runInDurableObject, SELF } from "cloudflare:test";
import { CHANNEL_VERSIONS, grantIdPaid, sha256Hex } from "vendor-contracts";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  setTransferPendingRPC,
  transferPackageAccountingIsValid,
} from "../../src/quota-do/coverage";
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
  vendorSuspend,
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
  | "voidGrant"
  | "voidForReversal";

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
  opts: { installationId?: string; envelope?: Record<string, unknown> } = {},
): Promise<GrantResultEnvelope> {
  const envelope = opts.envelope ?? await buildPaidGrantEnvelope({
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

async function buildHpBeginTransferRequest(input: {
  orgId: string;
  fromInstallationId: string;
  reason?: string;
}): Promise<{ args: Record<string, unknown>; accessJwt: string }> {
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
  return {
    args: {
      contract_version: CONTRACT_VERSION,
      org_id: input.orgId,
      from_installation_id: input.fromInstallationId,
      reason: input.reason ?? "clinic relocation",
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    accessJwt,
  };
}

async function hpBeginTransfer(input: {
  orgId: string;
  fromInstallationId: string;
  reason?: string;
}): Promise<GrantResultEnvelope> {
  const request = await buildHpBeginTransferRequest(input);
  return p38VendorCall("beginTransfer", request.args, { accessJwt: request.accessJwt });
}

async function buildHpDeleteInstallationRequest(input: {
  orgId: string;
  reason?: string;
}): Promise<{ args: Record<string, unknown>; accessJwt: string }> {
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
  return {
    args: {
      contract_version: CONTRACT_VERSION,
      org_id: input.orgId,
      reason: input.reason ?? "decommission",
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    accessJwt,
  };
}

async function hpDeleteInstallation(input: {
  orgId: string;
  reason?: string;
}): Promise<GrantResultEnvelope> {
  const request = await buildHpDeleteInstallationRequest(input);
  return p38VendorCall("deleteInstallation", request.args, { accessJwt: request.accessJwt });
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

async function countTransferForOrg(orgId: string): Promise<number> {
  const table = await queryOne<{ name: string }>(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'transfer'",
  );
  if (!table) {
    return 0;
  }
  return count("transfer", "org_id = ?", [orgId]);
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

async function readDoGrants(installationId: string): Promise<Record<string, unknown>[]> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect<Record<string, unknown>>(
      state,
      "SELECT grant_id, source_kind, envelope_sha256, envelope, receipt FROM grant ORDER BY applied_at ASC",
    ),
  );
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

function randomHex64(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function callVoidForReversal(input: {
  grantId: string;
  partial: boolean;
  reversalId?: string;
  reason?: string;
  evidenceSha256?: string;
}): Promise<GrantResultEnvelope> {
  const body = {
    contract_version: CONTRACT_VERSION,
    grant_id: input.grantId,
    reversal_id: input.reversalId ?? randomHex64(),
    reason: input.reason ?? "payment reversed",
    evidence_sha256: input.evidenceSha256 ?? randomHex64(),
    partial: input.partial,
  };
  const aboSignature = await signCoverAbo(body);
  return p38VendorCall("voidForReversal", {
    ...body,
    abo_kid: coverClinicAboKid(),
    abo_signature: aboSignature,
  });
}

async function completePaidGrantTransfer(): Promise<{
  scenario: Scenario;
  oldInstallationId: string;
  newInstallationId: string;
  paidGrantId: string;
  paidOriginGrantId: string;
}> {
  const scenario = await newScenario();
  await coverClinic(scenario);
  const oldInstallationId = scenario.installationId;
  const termsBefore = await readDoTerms(oldInstallationId);
  const activeBefore = termsBefore.find((row) => row.state === "active")!;
  const paidGrantId = activeBefore.grant_id;
  const paidOriginGrantId = activeBefore.origin_grant_id;

  const begun = await hpBeginTransfer({
    orgId: scenario.orgId,
    fromInstallationId: oldInstallationId,
  });
  expect(begun.result).toBe("ok");
  const transferRow = JSON.parse(begun.detail) as {
    transfer_id: string;
    to_installation_id: string;
  };

  const out = await transferOut(transferRow.transfer_id);
  expect(out.result).toBe("applied");
  await runDurableObjectAlarm(quotaDoStub(oldInstallationId));

  const inResult = await transferIn(transferRow.transfer_id);
  const transferDiagnostics = {
    claims: await queryAll<{
      grant_id: string;
      org_id: string;
      source_kind: string;
      envelope: string;
      envelope_sha256: string;
      installation_id: string;
      route_generation: number;
      state: string;
    }>(
      `SELECT grant_id, org_id, source_kind, envelope, envelope_sha256, installation_id, route_generation, state
       FROM grant_claim WHERE org_id = ? AND source_kind = 'transfer'`,
      [scenario.orgId],
    ),
    disputes: await queryAll<{ grant_id: string; reason: string; count: number }>(
      "SELECT grant_id, reason, count FROM grant_claim_dispute WHERE org_id = ?",
      [scenario.orgId],
    ),
    doGrants: await readDoGrants(transferRow.to_installation_id),
  };
  expect(inResult.result, JSON.stringify({ inResult, transferDiagnostics })).toBe("applied");
  await runDurableObjectAlarm(quotaDoStub(transferRow.to_installation_id));

  return {
    scenario,
    oldInstallationId,
    newInstallationId: transferRow.to_installation_id,
    paidGrantId,
    paidOriginGrantId,
  };
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
  it("R6-DM1: active legacy packages require finite nonnegative integer allowance", () => {
    const legacy = {
      origin_grant_id: "origin",
      position: 0,
      state: "active",
      plan_snapshot: {},
      allowance: 40,
      duration_unit: "month",
      duration_count: 1,
      grace_days: 0,
      grace_cap: "proportional",
      calendar_start: "2026-01-01T00:00:00.000Z",
      starts_at: "2026-01-01T00:00:00.000Z",
      ends_at: "2026-02-01T00:00:00.000Z",
      grace_ends_at: null,
    };
    expect(transferPackageAccountingIsValid(legacy)).toBe(true);
    expect(transferPackageAccountingIsValid({ ...legacy, allowance: -1 })).toBe(false);
    expect(transferPackageAccountingIsValid({ ...legacy, allowance: 1.5 })).toBe(false);
    expect(transferPackageAccountingIsValid({
      ...legacy,
      state: "grace",
      plan_allowance: 40,
      hot_grace_base_used: 0,
      hot_used: 0,
      calendar_start: null,
      grace_ends_at: "2026-02-06T00:00:00.000Z",
    })).toBe(false);
  });

  it("R2-C3: transfer out does not record a step for a mismatched DO version", async () => {
    const setup = await setupBeginTransferOnly();
    const packageBefore = await readTransferPackage(setup.transferId);
    const stepsBefore = await queryOne<{ count: number }>(
      "SELECT COUNT(*) AS count FROM transfer_step WHERE transfer_id = ?",
      [setup.transferId],
    );
    const doFetch = vi.fn(async () =>
      Response.json({
        contract_version: CHANNEL_VERSIONS.platformDo + 1,
        result: "applied",
        package: [],
        term_ids: [],
        ledger_seq: 1,
        receipt: { transfer_id: setup.transferId },
      }),
    );
    const getSpy = vi
      .spyOn(env.DO, "get")
      .mockReturnValue({ fetch: doFetch } as unknown as DurableObjectStub);

    let result: GrantResultEnvelope;
    try {
      result = await transferOut(setup.transferId);
    } finally {
      getSpy.mockRestore();
    }

    expect(doFetch).toHaveBeenCalledTimes(1);
    expect(result.result).toBe("rejected");
    expect(result.code).toBe("bad_request");
    expect(result.receipt).toBeUndefined();
    expect(await readTransferPackage(setup.transferId)).toBe(packageBefore);
    expect(
      await queryOne<{ count: number }>(
        "SELECT COUNT(*) AS count FROM transfer_step WHERE transfer_id = ?",
        [setup.transferId],
      ),
    ).toEqual(stepsBefore);
  });

  it("R6-PT2: an authorized pre-preparation transfer replay adopts its published fence", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const request = await buildHpBeginTransferRequest({
      orgId: scenario.orgId,
      fromInstallationId: scenario.installationId,
    });
    const first = await p38VendorCall("beginTransfer", request.args, {
      accessJwt: request.accessJwt,
    });
    expect(first.result).toBe("ok");
    const transfer = JSON.parse(first.detail) as { transfer_id: string };
    await env.DB.prepare(
      `DELETE FROM transfer_preparation WHERE transfer_id = ?`,
    ).bind(transfer.transfer_id).run();

    const replay = await p38VendorCall("beginTransfer", request.args, {
      accessJwt: request.accessJwt,
    });
    expect(replay.result).toBe("ok");
    expect(JSON.parse(replay.detail).transfer_id).toBe(transfer.transfer_id);
    expect(await queryOne<{ phase: string }>(
      `SELECT phase FROM transfer_preparation WHERE transfer_id = ?`,
      [transfer.transfer_id],
    )).toEqual({ phase: "published" });
  });

  it("R6-PT2: unknown destination initialization stays unpublished and the accepted preparation resumes once", async () => {
    const { scenario } = await setupActiveAndQueuedTerms();
    const request = await buildHpBeginTransferRequest({
      orgId: scenario.orgId,
      fromInstallationId: scenario.installationId,
    });
    const realGet = env.DO.get.bind(env.DO);
    let failOpen = true;
    const getSpy = vi.spyOn(env.DO, "get").mockImplementation((id) => {
      const stub = realGet(id);
      return {
        fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
          const body = typeof init?.body === "string"
            ? JSON.parse(init.body) as Record<string, unknown>
            : {};
          if (body.kind === "open_awaiting_transfer" && failOpen) {
            failOpen = false;
            return new Response(null, { status: 503 });
          }
          return stub.fetch(input, init);
        },
      } as DurableObjectStub;
    });
    let first: GrantResultEnvelope;
    let resumed: GrantResultEnvelope;
    try {
      first = await p38VendorCall("beginTransfer", request.args, { accessJwt: request.accessJwt });
      const oldBinding = await queryOne<{ status: string; epoch: number }>(
        `SELECT status, epoch FROM tenant_binding WHERE org_id = ? AND installation_id = ?`,
        [scenario.orgId, scenario.installationId],
      );
      const preparations = await queryAll<{
        transfer_id: string; to_installation_id: string; phase: string;
      }>(
        `SELECT transfer_id, to_installation_id, phase FROM transfer_preparation
         WHERE org_id = ? AND phase <> 'completed'`,
        [scenario.orgId],
      );
      expect(first.result).toBe("transient");
      expect(oldBinding).toEqual({ status: "active", epoch: 1 });
      expect(preparations).toHaveLength(1);
      expect(preparations[0]?.phase).toBe("accepted");
      expect(await count("transfer", "org_id = ?", [scenario.orgId])).toBe(0);

      resumed = await p38VendorCall("beginTransfer", request.args, { accessJwt: request.accessJwt });
    } finally {
      getSpy.mockRestore();
    }
    expect(resumed!.result).toBe("ok");
    const transfer = JSON.parse(resumed!.detail) as {
      transfer_id: string; to_installation_id: string;
    };
    const preparation = await queryOne<{
      phase: string; to_installation_id: string; accepted_actor: string;
    }>(
      `SELECT phase, to_installation_id, accepted_actor FROM transfer_preparation
       WHERE transfer_id = ?`,
      [transfer.transfer_id],
    );
    expect(preparation?.phase).toBe("published");
    expect(preparation?.to_installation_id).toBe(transfer.to_installation_id);
    expect(preparation?.accepted_actor).toBe(VENDOR_OPERATOR_EMAIL);
    expect(await queryOne<{ status: string }>(
      `SELECT status FROM tenant_binding WHERE org_id = ? AND installation_id = ?`,
      [scenario.orgId, scenario.installationId],
    )).toEqual({ status: "retired" });
    expect(await queryOne<{ status: string; epoch: number }>(
      `SELECT status, epoch FROM tenant_binding WHERE org_id = ? AND installation_id = ?`,
      [scenario.orgId, transfer.to_installation_id],
    )).toEqual({ status: "active", epoch: 2 });
    const sourceHot = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, state) => sqlSelect<{ transfer_pending: number; transfer_pending_id: string }>(
        state, "SELECT transfer_pending, transfer_pending_id FROM hot LIMIT 1",
      )[0],
    );
    expect(sourceHot).toEqual({ transfer_pending: 1, transfer_pending_id: transfer.transfer_id });
    const destinationHot = await runInDurableObject(
      quotaDoStub(transfer.to_installation_id),
      async (_instance, state) => sqlSelect<{ awaiting_transfer: number; awaiting_transfer_id: string }>(
        state, "SELECT awaiting_transfer, awaiting_transfer_id FROM hot LIMIT 1",
      )[0],
    );
    expect(destinationHot).toEqual({ awaiting_transfer: 1, awaiting_transfer_id: transfer.transfer_id });
  });

  it("R6-PT2: scheduled recovery resumes after destination acknowledgement but unknown source-freeze acknowledgement", async () => {
    const { scenario } = await setupActiveAndQueuedTerms();
    const request = await buildHpBeginTransferRequest({
      orgId: scenario.orgId,
      fromInstallationId: scenario.installationId,
    });
    const realGet = env.DO.get.bind(env.DO);
    let failFreeze = true;
    const getSpy = vi.spyOn(env.DO, "get").mockImplementation((id) => {
      const stub = realGet(id);
      return {
        fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
          const body = typeof init?.body === "string"
            ? JSON.parse(init.body) as Record<string, unknown>
            : {};
          if (body.kind === "set_transfer_pending" && failFreeze) {
            failFreeze = false;
            return new Response(null, { status: 503 });
          }
          return stub.fetch(input, init);
        },
      } as DurableObjectStub;
    });
    let first: GrantResultEnvelope;
    try {
      first = await p38VendorCall("beginTransfer", request.args, { accessJwt: request.accessJwt });
    } finally {
      getSpy.mockRestore();
    }
    expect(first!.result).toBe("transient");
    const pending = await queryOne<{ transfer_id: string; phase: string; to_installation_id: string }>(
      `SELECT transfer_id, phase, to_installation_id FROM transfer_preparation WHERE org_id = ?`,
      [scenario.orgId],
    );
    expect(pending?.phase).toBe("destination_ready");
    expect(await count("transfer", "org_id = ?", [scenario.orgId])).toBe(0);
    expect(await queryOne<{ status: string }>(
      `SELECT status FROM tenant_binding WHERE org_id = ? AND installation_id = ?`,
      [scenario.orgId, scenario.installationId],
    )).toEqual({ status: "active" });

    await runScheduled("*/5 * * * *");
    expect(await queryOne<{ phase: string }>(
      `SELECT phase FROM transfer_preparation WHERE transfer_id = ?`,
      [pending!.transfer_id],
    )).toEqual({ phase: "published" });
    expect(await queryOne<{ count: number }>(
      "SELECT COUNT(*) AS count FROM transfer WHERE transfer_id = ?",
      [pending!.transfer_id],
    )).toEqual({ count: 1 });
    expect(await queryOne<{ status: string; epoch: number }>(
      `SELECT status, epoch FROM tenant_binding WHERE org_id = ? AND installation_id = ?`,
      [scenario.orgId, pending!.to_installation_id],
    )).toEqual({ status: "active", epoch: 2 });
  });

  it("R6-DM1 waits for pending request accounting and fallback admission before source export", async () => {
    const { scenario } = await setupActiveAndQueuedTerms();
    const begun = await hpBeginTransfer({
      orgId: scenario.orgId,
      fromInstallationId: scenario.installationId,
    });
    expect(begun.result).toBe("ok");
    const transfer = JSON.parse(begun.detail) as { transfer_id: string };
    const terms = await readDoTerms(scenario.installationId);
    const activeTerm = terms.find((row) => row.state === "active")!;
    const now = getVendorTestClockIso() ?? new Date().toISOString();
    const accountingRequestId = crypto.randomUUID();
    await env.DB.prepare(
      `INSERT INTO ai_request (
         request_id, request_reference, installation_id, actor_id, branch_id,
         capability_id, capability_version, prompt_artifact_hash, idempotency_key,
         trace_id, state, created_at, updated_at, accounting_mode,
         accounting_term_id, accounting_request_id, accounting_quota_weight,
         accounting_outcome, accounting_state
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Completed', ?, ?, 'fallback', ?, ?, 1,
         'consumed', 'pending')`,
    ).bind(
      accountingRequestId,
      `R6DM1-${accountingRequestId.slice(-8)}`,
      scenario.installationId,
      scenario.actorId,
      scenario.branchId,
      "r6-dm1-capability",
      "1",
      "prompt/r6-dm1@v1",
      `r6-dm1-${accountingRequestId}`,
      `trace-${accountingRequestId}`,
      now,
      now,
      activeTerm.term_id,
      accountingRequestId,
    ).run();

    const accountingPending = await transferOut(transfer.transfer_id);
    expect(accountingPending.result).toBe("transient");
    await env.DB.prepare(
      "UPDATE ai_request SET accounting_state = 'settled' WHERE request_id = ?",
    ).bind(accountingRequestId).run();

    const fallbackRequestId = crypto.randomUUID();
    const fallbackKey = `r6-dm1-${fallbackRequestId}`;
    await env.DB.prepare(
      `INSERT INTO fallback_admission (
         installation_id, idempotency_key, term_id, request_id,
         weight, admitted_at, state
       ) VALUES (?, ?, ?, ?, 1, ?, 'pending')`,
    ).bind(
      scenario.installationId,
      fallbackKey,
      activeTerm.term_id,
      fallbackRequestId,
      now,
    ).run();
    const fallbackPending = await transferOut(transfer.transfer_id);
    expect(fallbackPending.result).toBe("transient");

    await env.DB.prepare(
      `UPDATE fallback_admission SET state = 'settled'
       WHERE installation_id = ? AND idempotency_key = ?`,
    ).bind(scenario.installationId, fallbackKey).run();
    expect((await transferOut(transfer.transfer_id)).result).toBe("applied");
  });

  it("R6-DM1 R4-PG1 E2E-P3.8-01 A14 preserves settled usage while moving terms and ignores a client-selected old route", async () => {
    const { scenario, activeGrantId, queuedGrantId } =
      await setupActiveAndQueuedTerms();
    const oldInstallationId = scenario.installationId;

    const termsBefore = await readDoTerms(oldInstallationId);
    const activeBefore = termsBefore.find((row) => row.grant_id === activeGrantId);
    const queuedBefore = termsBefore.find((row) => row.grant_id === queuedGrantId);
    expect(activeBefore?.state).toBe("active");
    expect(queuedBefore?.state).toBe("queued");
    await runInDurableObject(quotaDoStub(oldInstallationId), async (_instance, state) => {
      state.storage.sql?.exec("UPDATE hot SET used = 40");
    });
    const hotUsed = await readHotUsed(oldInstallationId);
    expect(hotUsed).toBe(40);

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
    expect(inResult.result, JSON.stringify(inResult)).toBe("applied");
    expect(inResult.receipt).toBeDefined();
    await runDurableObjectAlarm(quotaDoStub(transferRow.to_installation_id));

    const newTerms = await readDoTerms(transferRow.to_installation_id);
    for (let index = 0; index < newTerms.length; index += 1) {
      const transferredGrantId = await sha256Hex(
        new TextEncoder().encode(`grant:transfer:${transferRow.transfer_id}:${index}`),
      );
      expect(await queryOne<{ source_kind: string; state: string }>(
        "SELECT source_kind, state FROM grant_claim WHERE grant_id = ?",
        [transferredGrantId],
      )).toEqual({ source_kind: "transfer", state: "completed" });
    }
    const oldOrigins = termsBefore.map((row) => row.origin_grant_id).sort();
    const newOrigins = newTerms.map((row) => row.origin_grant_id).sort();
    expect(newOrigins).toEqual(oldOrigins);

    const newActive = newTerms.find(
      (row) => row.origin_grant_id === activeBefore!.origin_grant_id,
    );
    const newQueued = newTerms.find(
      (row) => row.origin_grant_id === queuedBefore!.origin_grant_id,
    );
    expect(newActive?.allowance).toBe(activeBefore?.allowance);
    expect(newQueued?.allowance).toBe(queuedBefore?.allowance);
    expect(await readHotUsed(transferRow.to_installation_id)).toBe(hotUsed);
    expect((newActive?.allowance ?? 0) - (await readHotUsed(transferRow.to_installation_id)))
      .toBe((activeBefore?.allowance ?? 0) - hotUsed);

    const oldCoverage = await getCoverageForInstallation(
      scenario.orgId,
      oldInstallationId,
    );
    expect(oldCoverage.result).toBe("ok");
    const oldSnapshot = JSON.parse(oldCoverage.detail) as {
      snapshot: { state: string };
    };
    expect(oldSnapshot.snapshot.state).toBe("transferred");

    const overrideGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    const routed = await paidGrant(
      scenario,
      overrideGrantId,
      { installationId: oldInstallationId },
    );
    expect(routed.result).toBe("applied");
    expect((await readDoTerms(oldInstallationId)).some((row) => row.grant_id === overrideGrantId)).toBe(false);
    expect((await readDoTerms(transferRow.to_installation_id)).some((row) => row.grant_id === overrideGrantId)).toBe(true);
    expect(await queryOne<{ installation_id: string }>(
      "SELECT installation_id FROM grant_claim WHERE grant_id = ?",
      [overrideGrantId],
    )).toEqual({ installation_id: transferRow.to_installation_id });

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

    const secondBegin = await hpBeginTransfer({
      orgId: scenario.orgId,
      fromInstallationId: transferRow.to_installation_id,
    });
    expect(secondBegin.result).toBe("ok");
    const secondTransfer = JSON.parse(secondBegin.detail) as {
      transfer_id: string; to_installation_id: string;
    };
    expect((await transferOut(secondTransfer.transfer_id)).result).toBe("applied");
    expect((await transferIn(secondTransfer.transfer_id)).result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(secondTransfer.to_installation_id));
    const repeatedTerms = await readDoTerms(secondTransfer.to_installation_id);
    const repeatedActive = repeatedTerms.find(
      (row) => row.origin_grant_id === activeBefore!.origin_grant_id,
    );
    expect(repeatedActive?.allowance).toBe(newActive?.allowance);
    expect(await readHotUsed(secondTransfer.to_installation_id)).toBe(hotUsed);
  });

  it("R6-DM1 preserves grace base usage, remaining budget, cap, and calendar dates", async () => {
    const { scenario, activeGrantId } = await setupActiveAndQueuedTerms();
    const sourceTerms = await readDoTerms(scenario.installationId);
    const active = sourceTerms.find((row) => row.grant_id === activeGrantId)!;
    await runInDurableObject(quotaDoStub(scenario.installationId), async (_instance, state) => {
      state.storage.sql?.exec(
        `UPDATE term SET state = 'grace', grace_ends_at = '2026-11-03T00:00:00.000Z'
         WHERE term_id = '${active.term_id.replace(/'/g, "''")}'`,
      );
      state.storage.sql?.exec(
        `UPDATE hot SET active_term_id = '${active.term_id.replace(/'/g, "''")}',
           used = 80, grace_base_used = 50`,
      );
    });
    const before = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, state) => sqlSelect<{
        allowance: number; grace_cap: string; ends_at: string; grace_ends_at: string;
      }>(state,
        `SELECT allowance, grace_cap, ends_at, grace_ends_at FROM term WHERE term_id = '${active.term_id.replace(/'/g, "''")}'`,
      )[0],
    );

    const begun = await hpBeginTransfer({
      orgId: scenario.orgId,
      fromInstallationId: scenario.installationId,
    });
    expect(begun.result).toBe("ok");
    const transfer = JSON.parse(begun.detail) as {
      transfer_id: string; to_installation_id: string;
    };
    expect((await transferOut(transfer.transfer_id)).result).toBe("applied");
    expect((await transferIn(transfer.transfer_id)).result).toBe("applied");
    const after = await runInDurableObject(
      quotaDoStub(transfer.to_installation_id),
      async (_instance, state) => sqlSelect<{
        allowance: number; grace_cap: string; ends_at: string; grace_ends_at: string;
      }>(state,
        `SELECT allowance, grace_cap, ends_at, grace_ends_at FROM term WHERE origin_grant_id = '${active.origin_grant_id.replace(/'/g, "''")}'`,
      )[0],
    );
    const hot = await runInDurableObject(
      quotaDoStub(transfer.to_installation_id),
      async (_instance, state) => sqlSelect<{ used: number; grace_base_used: number }>(
        state, "SELECT used, grace_base_used FROM hot LIMIT 1",
      )[0],
    );
    expect(after).toEqual(before);
    expect(hot).toEqual({ used: 80, grace_base_used: 50 });
  });

  it("R4-PG1 a pending no-effect claim seals its retired route before applying once on the live route", async () => {
    const { scenario } = await setupActiveAndQueuedTerms();
    const oldInstallationId = scenario.installationId;
    const grantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    const envelope = await buildPaidGrantEnvelope({ orgId: scenario.orgId, grantId });
    const aboSignature = await signCoverAbo(envelope);
    const grantArgs = {
      contract_version: CONTRACT_VERSION,
      envelope,
      abo_kid: coverClinicAboKid(),
      abo_signature: aboSignature,
    };
    const realGet = env.DO.get.bind(env.DO);
    const getSpy = vi.spyOn(env.DO, "get").mockImplementation((id) => {
      const stub = realGet(id);
      return {
        fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
          const body = typeof init?.body === "string" ? JSON.parse(init.body) as Record<string, unknown> : {};
          if (body.kind === "apply_grant") return new Response(null, { status: 503 });
          return stub.fetch(input, init);
        },
      } as DurableObjectStub;
    });
    let pending: GrantResultEnvelope;
    try {
      pending = await p38VendorCall("grant", grantArgs);
    } finally {
      getSpy.mockRestore();
    }
    expect(pending.result).toBe("transient");
    expect(pending.detail).toBe("unavailable");

    const begun = await hpBeginTransfer({ orgId: scenario.orgId, fromInstallationId: oldInstallationId });
    expect(begun.result).toBe("ok");
    const transfer = JSON.parse(begun.detail) as { transfer_id: string; to_installation_id: string };
    expect((await transferOut(transfer.transfer_id)).result).toBe("applied");
    const transferInResult = await transferIn(transfer.transfer_id);
    const transferClaims = await queryAll<{
      grant_id: string;
      source_kind: string;
      installation_id: string;
      route_generation: number;
      state: string;
    }>(
      `SELECT grant_id, source_kind, installation_id, route_generation, state
       FROM grant_claim WHERE org_id = ? AND source_kind = 'transfer'`,
      [scenario.orgId],
    );
    const transferDisputes = await queryAll<{ grant_id: string; reason: string; count: number }>(
      "SELECT grant_id, reason, count FROM grant_claim_dispute WHERE org_id = ?",
      [scenario.orgId],
    );
    expect(transferInResult.result, JSON.stringify({ transferInResult, transferClaims, transferDisputes })).toBe("applied");

    const applied = await p38VendorCall("grant", grantArgs);
    expect(applied.result).toBe("applied");
    expect((await readDoTerms(oldInstallationId)).some((row) => row.grant_id === grantId)).toBe(false);
    expect((await readDoTerms(transfer.to_installation_id)).some((row) => row.grant_id === grantId)).toBe(true);
    expect(await queryOne<{ installation_id: string; route_generation: number }>(
      "SELECT installation_id, route_generation FROM grant_claim WHERE grant_id = ?",
      [grantId],
    )).toEqual({ installation_id: transfer.to_installation_id, route_generation: 2 });
  });

  it("R6-PT2 E2E-P3.8-02 a non-transfer grant during awaiting_transfer is transient and then queues behind the moved terms", async () => {
    const setup = await setupBeginTransferOnly();
    const { scenario, transferId, newInstallationId } = setup;

    const originsBefore = (await readDoTerms(setup.oldInstallationId)).map(
      (row) => row.origin_grant_id,
    );

    const pendingGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    const pendingEnvelope = await buildPaidGrantEnvelope({
      orgId: scenario.orgId,
      grantId: pendingGrantId,
    });
    const pending = await paidGrant(scenario, pendingGrantId, { envelope: pendingEnvelope });
    expect(pending.result).toBe("transient");
    expect(pending.detail).toBe("awaiting_transfer");
    const termsMid = await readDoTerms(newInstallationId);
    expect(termsMid.find((row) => row.grant_id === pendingGrantId)).toBeUndefined();

    const out = await transferOut(transferId);
    expect(out.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(setup.oldInstallationId));

    const inResult = await transferIn(transferId);
    const transferDiagnostics = {
      claims: await queryAll<{
        grant_id: string;
        org_id: string;
        source_kind: string;
        envelope: string;
        envelope_sha256: string;
        installation_id: string;
        route_generation: number;
        state: string;
      }>(
        `SELECT grant_id, org_id, source_kind, envelope, envelope_sha256, installation_id, route_generation, state
         FROM grant_claim WHERE org_id = ? AND source_kind = 'transfer'`,
        [scenario.orgId],
      ),
      disputes: await queryAll<{ grant_id: string; reason: string; count: number }>(
        "SELECT grant_id, reason, count FROM grant_claim_dispute WHERE org_id = ?",
        [scenario.orgId],
      ),
      doGrants: await readDoGrants(newInstallationId),
    };
    expect(inResult.result, JSON.stringify({ inResult, transferDiagnostics })).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(newInstallationId));

    const applied = await paidGrant(scenario, pendingGrantId, { envelope: pendingEnvelope });
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

  it("R6-DM2 E2E-P3.8-03 transfer steps retry as already_applied without duplicate terms and transferIn before transferOut is transient", async () => {
    const { scenario, activeGrantId, queuedGrantId } =
      await setupActiveAndQueuedTerms();
    const oldInstallationId = scenario.installationId;

    const begun = await hpBeginTransfer({
      orgId: scenario.orgId,
      fromInstallationId: oldInstallationId,
    });
    expect(begun.result).toBe("ok");
    const transferRow = JSON.parse(begun.detail) as {
      transfer_id: string;
      to_installation_id: string;
    };
    const transferId = transferRow.transfer_id;

    const termsBefore = await readDoTerms(oldInstallationId);
    const packageBefore = await readTransferPackage(transferId);

    const earlyIn = await transferIn(transferId);
    expect(earlyIn.result, JSON.stringify(earlyIn)).toBe("transient");
    expect(earlyIn.detail).toBe("awaiting_transfer_out");
    const termsAfterEarly = await readDoTerms(oldInstallationId);
    expect(termsAfterEarly).toEqual(termsBefore);
    expect(await readTransferPackage(transferId)).toBe(packageBefore);

    const out = await transferOut(transferId);
    expect(out.result).toBe("applied");
    expect(out.receipt).toBeDefined();
    const outReceipt = out.receipt as Record<string, unknown>;

    const inResult = await transferIn(transferId);
    expect(inResult.result, JSON.stringify(inResult)).toBe("applied");
    expect(inResult.receipt).toBeDefined();
    const inReceipt = inResult.receipt as Record<string, unknown>;
    const termsAfterApply = await readDoTerms(transferRow.to_installation_id);

    await env.DB.prepare(
      "DELETE FROM transfer_step WHERE transfer_id = ? AND step = 'transfer_out'",
    ).bind(transferId).run();
    const outRetry = await transferOut(transferId);
    expect(outRetry.result).toBe("already_applied");
    expect(outRetry.receipt).toEqual(outReceipt);

    await env.DB.prepare(
      "DELETE FROM transfer_step WHERE transfer_id = ? AND step = 'transfer_in'",
    ).bind(transferId).run();
    const inRetry = await transferIn(transferId);
    expect(inRetry.result).toBe("already_applied");
    expect(inRetry.receipt).toEqual(inReceipt);
    expect(await readDoTerms(transferRow.to_installation_id)).toEqual(termsAfterApply);

    await runDurableObjectAlarm(quotaDoStub(transferRow.to_installation_id));
    expect(await queryOne<{ count: number }>(
      `SELECT COUNT(*) AS count FROM coverage_event
       WHERE installation_id = ? AND kind = 'grant_applied'`,
      [transferRow.to_installation_id],
    )).toEqual({ count: termsAfterApply.length });

    expect(activeGrantId).toBeTruthy();
    expect(queuedGrantId).toBeTruthy();
  });

  it.each(["generation", "binding_epoch"] as const)(
    "R6-PT1: transfer-in rejects a stale source route %s",
    async (staleField) => {
      const setup = await setupBeginTransferOnly();
      const exported = await transferOut(setup.transferId);
      expect(exported.result).toBe("applied");
      const manifest = await queryOne<{ source_epoch: number; source_generation: number }>(
        `SELECT source_epoch, source_generation FROM transfer_route_manifest
         WHERE transfer_id = ? AND grant_id = ?`,
        [setup.transferId, setup.activeGrantId],
      );
      expect(manifest).toBeTruthy();
      const beforeImport = await queryOne<{ binding_epoch: number; generation: number }>(
        `SELECT binding_epoch, generation FROM live_value_route WHERE grant_id = ?`,
        [setup.activeGrantId],
      );
      expect(beforeImport).toEqual({
        binding_epoch: manifest!.source_epoch,
        generation: manifest!.source_generation,
      });

      await env.DB.prepare(
        `UPDATE live_value_route SET ${staleField} = ${staleField} + 1
         WHERE grant_id = ? AND state = 'moving' AND transfer_id = ?`,
      ).bind(setup.activeGrantId, setup.transferId).run();

      const imported = await transferIn(setup.transferId);
      expect(imported.result).toBe("rejected");
      expect(imported.code).toBe("bad_request");
      expect((await readDoTerms(setup.newInstallationId)).some(
        (term) => term.origin_grant_id === setup.activeGrantId,
      )).toBe(false);
      const route = await queryOne<{
        installation_id: string;
        binding_epoch: number;
        generation: number;
        state: string;
      }>(
        `SELECT installation_id, binding_epoch, generation, state
         FROM live_value_route WHERE grant_id = ?`,
        [setup.activeGrantId],
      );
      expect(route).toEqual({
        installation_id: setup.oldInstallationId,
        binding_epoch: staleField === "binding_epoch" ? manifest!.source_epoch + 1 : manifest!.source_epoch,
        generation: staleField === "generation" ? manifest!.source_generation + 1 : manifest!.source_generation,
        state: "moving",
      });
    },
  );

  it("R6-PT1: quarantined historical route blocks transfer-in pending operator adjudication", async () => {
    const setup = await setupBeginTransferOnly();
    const exported = await transferOut(setup.transferId);
    expect(exported.result).toBe("applied");
    await env.DB.prepare(
      `INSERT INTO transfer_route_quarantine (transfer_id, grant_id, reason, created_at)
       VALUES (?, ?, 'route_not_at_authorized_source', ?)`
    ).bind(setup.transferId, setup.activeGrantId, new Date().toISOString()).run();

    const imported = await transferIn(setup.transferId);
    expect(imported.result).toBe("rejected");
    expect(imported.code).toBe("transfer_route_quarantined");
    expect((await readDoTerms(setup.newInstallationId)).some(
      (term) => term.origin_grant_id === setup.activeGrantId,
    )).toBe(false);
    const route = await queryOne<{ installation_id: string; state: string; transfer_id: string | null }>(
      `SELECT installation_id, state, transfer_id FROM live_value_route WHERE grant_id = ?`,
      [setup.activeGrantId],
    );
    expect(route).toEqual({
      installation_id: setup.oldInstallationId,
      state: "moving",
      transfer_id: setup.transferId,
    });
  });

  it("R6-PT1: transfer-out receipt identity must authenticate its package before import", async () => {
    const setup = await setupBeginTransferOnly();
    expect((await transferOut(setup.transferId)).result).toBe("applied");
    const stored = await queryOne<{ receipt: string }>(
      `SELECT receipt FROM transfer_step WHERE transfer_id = ? AND step = 'transfer_out'`,
      [setup.transferId],
    );
    expect(stored).toBeTruthy();
    const altered = JSON.parse(stored!.receipt) as Record<string, unknown>;
    altered.org_id = "different-org";
    await env.DB.prepare(
      `UPDATE transfer_step SET receipt = ? WHERE transfer_id = ? AND step = 'transfer_out'`,
    ).bind(JSON.stringify(altered), setup.transferId).run();

    const imported = await transferIn(setup.transferId);
    expect(imported.result).toBe("rejected");
    expect(imported.code).toBe("transfer_route_quarantined");
    expect(await count("transfer_route_quarantine", "transfer_id = ?", [setup.transferId])).toBe(1);
    expect((await readDoTerms(setup.newInstallationId)).some(
      (term) => term.origin_grant_id === setup.activeGrantId,
    )).toBe(false);
  });

  it("R6-PT3 R7-PS1 resumes unknown deletion freeze and publishes held unavailability once", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    expect((await vendorSuspend(scenario)).status).toBe(200);
    const request = await buildHpDeleteInstallationRequest({ orgId: scenario.orgId });
    clearCapturedVendorEmails();

    const realGet = env.DO.get.bind(env.DO);
    let failFreeze = true;
    const getSpy = vi.spyOn(env.DO, "get").mockImplementation((id) => {
      const stub = realGet(id);
      return {
        fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
          const body = typeof init?.body === "string"
            ? JSON.parse(init.body) as Record<string, unknown>
            : {};
          if (body.kind === "set_transfer_pending" && failFreeze) {
            failFreeze = false;
            return new Response(null, { status: 503 });
          }
          return stub.fetch(input, init);
        },
      } as DurableObjectStub;
    });
    let first: GrantResultEnvelope;
    try {
      first = await p38VendorCall("deleteInstallation", request.args, {
        accessJwt: request.accessJwt,
      });
    } finally {
      getSpy.mockRestore();
    }
    expect(first!.result).toBe("transient");
    expect(await queryOne<{ phase: string }>(
      `SELECT phase FROM deletion_command WHERE org_id = ?`, [scenario.orgId],
    )).toEqual({ phase: "accepted" });
    expect(await queryOne<{ status: string }>(
      `SELECT status FROM tenant_binding WHERE org_id = ?`, [scenario.orgId],
    )).toEqual({ status: "active" });
    expect(await queryOne<{ status: string }>(
      `SELECT status FROM installation WHERE installation_id = ?`, [scenario.installationId],
    )).toEqual({ status: "active" });

    await runScheduled("*/5 * * * *");
    const resumed = await p38VendorCall("deleteInstallation", request.args, {
      accessJwt: request.accessJwt,
    });
    expect(resumed.result).toBe("ok");
    expect(await queryOne<{ phase: string; purge_state: string; held: number }>(
      `SELECT phase, purge_state, held FROM deletion_command WHERE org_id = ?`, [scenario.orgId],
    )).toEqual({ phase: "completed", purge_state: "completed", held: 1 });
    expect(al18Emails()).toHaveLength(1);

    const live = await getCoverageForInstallation(scenario.orgId, scenario.installationId);
    const liveSnapshot = JSON.parse(live.detail).snapshot as Record<string, unknown>;
    expect(liveSnapshot.state).toBe("transfer_pending");
    expect(liveSnapshot.reason).toBe("transfer_pending");
    expect(liveSnapshot.suspended).toBe(true);
    expect(liveSnapshot.term).toBeTruthy();

    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    const mirror = await queryOne<{ state: string; term_snapshot: string }>(
      `SELECT state, term_snapshot FROM coverage_mirror WHERE installation_id = ?`,
      [scenario.installationId],
    );
    expect(mirror?.state).toBe("transfer_pending");
    expect((JSON.parse(mirror!.term_snapshot) as Record<string, unknown>).reason)
      .toBe("transfer_pending");
    expect(await count("coverage_event", "installation_id = ? AND kind = 'transfer'", [
      scenario.installationId,
    ])).toBe(1);

    const repeat = await p38VendorCall("deleteInstallation", request.args, {
      accessJwt: request.accessJwt,
    });
    expect(repeat.result).toBe("ok");
    expect(repeat.detail).toBe(resumed.detail);
    expect(await count("coverage_event", "installation_id = ? AND kind = 'transfer'", [
      scenario.installationId,
    ])).toBe(1);
    expect(await count("control_audit", "audit_id LIKE 'rm27-delete-purge:%'", [])).toBe(1);
  });

  it("R6-PT3 keeps a malformed acknowledged reservation inventory due", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const request = await buildHpDeleteInstallationRequest({ orgId: scenario.orgId });
    const realGet = env.DO.get.bind(env.DO);
    let malformed = true;
    const getSpy = vi.spyOn(env.DO, "get").mockImplementation((id) => {
      const stub = realGet(id);
      return {
        fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
          const body = typeof init?.body === "string"
            ? JSON.parse(init.body) as Record<string, unknown>
            : {};
          if (body.kind === "set_transfer_pending" && malformed) {
            malformed = false;
            return Response.json({
              contract_version: CHANNEL_VERSIONS.platformDo,
              kind: "set_transfer_pending",
              result: "ok",
              terms: [],
              reservations: [{ id: "incomplete" }],
            });
          }
          return stub.fetch(input, init);
        },
      } as DurableObjectStub;
    });
    let first: GrantResultEnvelope;
    try {
      first = await p38VendorCall("deleteInstallation", request.args, {
        accessJwt: request.accessJwt,
      });
    } finally {
      getSpy.mockRestore();
    }
    expect(first!.result).toBe("transient");
    expect(await queryOne<{ phase: string }>(
      `SELECT phase FROM deletion_command WHERE org_id = ?`, [scenario.orgId],
    )).toEqual({ phase: "accepted" });
    expect(await queryOne<{ status: string }>(
      `SELECT status FROM tenant_binding WHERE org_id = ?`, [scenario.orgId],
    )).toEqual({ status: "active" });

    const resumed = await p38VendorCall("deleteInstallation", request.args, {
      accessJwt: request.accessJwt,
    });
    expect(resumed.result).toBe("ok");
  });

  it("R7-PS1 re-arms a lost outbox alarm on transfer-pending replay", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const request = {
      kind: "set_transfer_pending" as const,
      transferId: "rm27-rearm-freeze",
      emitDeletionSnapshot: true,
      installationId: scenario.installationId,
      orgId: scenario.orgId,
      bindingEpoch: 1,
      vendorContractVersion: CHANNEL_VERSIONS.platformDo,
      nowIso: getVendorTestClockIso() ?? new Date().toISOString(),
    };
    await runInDurableObject(quotaDoStub(scenario.installationId), async (_instance, state) => {
      const invoke = () => setTransferPendingRPC(
        state,
        state.storage,
        (fn) => fn(),
        request,
      );
      expect((await invoke()).result).toBe("ok");
      await state.storage.deleteAlarm();
      expect(await state.storage.getAlarm()).toBeNull();
      expect((await invoke()).result).toBe("ok");
      expect(await state.storage.getAlarm()).not.toBeNull();
    });
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    expect(await count("coverage_event", "installation_id = ? AND kind = 'transfer'", [
      scenario.installationId,
    ])).toBe(1);
  });

  it("R6-PT3: purge retry survives final grant void retiring the held epoch", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const request = await buildHpDeleteInstallationRequest({ orgId: scenario.orgId });
    const realBatch = env.DB.batch.bind(env.DB);
    let batchCount = 0;
    const batchSpy = vi.spyOn(env.DB, "batch").mockImplementation((statements) => {
      batchCount += 1;
      if (batchCount === 3) return Promise.reject(new Error("simulated purge interruption"));
      return realBatch(statements);
    });
    let first: GrantResultEnvelope;
    try {
      first = await p38VendorCall("deleteInstallation", request.args, {
        accessJwt: request.accessJwt,
      });
    } finally {
      batchSpy.mockRestore();
    }
    expect(first!.result).toBe("transient");
    expect(await queryOne<{ phase: string; purge_state: string; held: number }>(
      `SELECT phase, purge_state, held FROM deletion_command WHERE org_id = ?`, [scenario.orgId],
    )).toEqual({ phase: "frozen", purge_state: "due", held: 1 });
    expect(await queryOne<{ status: string }>(
      `SELECT status FROM tenant_binding WHERE org_id = ?`, [scenario.orgId],
    )).toEqual({ status: "held_for_transfer" });

    const openTerms = (await readDoTerms(scenario.installationId)).filter(
      (term) => term.state === "active" || term.state === "grace" ||
        term.state === "queued" || term.state === "held",
    );
    expect(openTerms.length).toBeGreaterThan(0);
    for (const term of openTerms) {
      expect((await hpVoidGrant(term.grant_id)).result).toBe("applied");
      await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    }
    expect(await queryOne<{ status: string }>(
      `SELECT status FROM tenant_binding WHERE org_id = ?`, [scenario.orgId],
    )).toEqual({ status: "retired" });

    const resumed = await p38VendorCall("deleteInstallation", request.args, {
      accessJwt: request.accessJwt,
    });
    expect(resumed.result).toBe("ok");
    expect(await queryOne<{ phase: string; purge_state: string }>(
      `SELECT phase, purge_state FROM deletion_command WHERE org_id = ?`, [scenario.orgId],
    )).toEqual({ phase: "completed", purge_state: "completed" });
    expect(await count("control_audit", "audit_id LIKE 'rm27-delete-purge:%'", [])).toBe(1);
  });

  it("R6-PT3 R7-PS1: fresh delete replay preserves freeze for held transfer (E2E-P3.8-04)", async () => {
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
    expect(await queryOne<{ assertions: number; freeze_ids: number }>(
      `SELECT COUNT(DISTINCT assertion_sha256) AS assertions,
              COUNT(DISTINCT freeze_id) AS freeze_ids
       FROM deletion_command WHERE org_id = ?`,
      [scenario.orgId],
    )).toEqual({ assertions: 2, freeze_ids: 1 });

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

  it("R6-PT3: successful empty freeze retires the binding and the next token creates epoch 2", async () => {
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

  it("R6-PT3 R7-PS1: voiding the remaining grants of a held binding retires it", async () => {
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

  it("R6-PT1: voidForReversal of a moved paid grant lands on the new installation", async () => {
    const {
      scenario,
      oldInstallationId,
      newInstallationId,
      paidGrantId,
      paidOriginGrantId,
    } = await completePaidGrantTransfer();

    const voided = await callVoidForReversal({
      grantId: paidGrantId,
      partial: false,
    });
    expect(voided.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(newInstallationId));

    const inspected = await inspectCoverageTerms(scenario);
    const reversed = inspected.find(
      (row) => row.origin_grant_id === paidOriginGrantId,
    );
    expect(reversed?.state).toBe("ended");
    expect(reversed?.end_reason).toBe("reversed");

    const oldTerms = await readDoTerms(oldInstallationId);
    const transferred = oldTerms.find(
      (row) => row.origin_grant_id === paidOriginGrantId,
    );
    expect(transferred?.end_reason).toBe("transferred");
  });

  it("R6-PT1: reversal stays due while value moves and then voids the imported route", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const oldInstallationId = scenario.installationId;
    const grant = (await readDoGrants(oldInstallationId))[0]!;
    const begun = await hpBeginTransfer({
      orgId: scenario.orgId,
      fromInstallationId: oldInstallationId,
    });
    expect(begun.result).toBe("ok");
    const transfer = JSON.parse(begun.detail) as {
      transfer_id: string; to_installation_id: string;
    };
    expect(await queryOne<{ state: string }>(
      "SELECT state FROM live_value_route WHERE grant_id = ?",
      [grant.grant_id],
    )).toEqual({ state: "moving" });

    const reversal = {
      grantId: grant.grant_id,
      partial: false,
      reversalId: crypto.randomUUID().replace(/-/g, "").padEnd(64, "0"),
      reason: "refund-during-transfer",
      evidenceSha256: crypto.randomUUID().replace(/-/g, "").padEnd(64, "0"),
    };
    const pending = await callVoidForReversal(reversal);
    expect(pending.result).toBe("transient");

    expect((await transferOut(transfer.transfer_id)).result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(oldInstallationId));
    expect((await transferIn(transfer.transfer_id)).result).toBe("applied");
    const settledRoute = await queryOne<{ installation_id: string; state: string }>(
      "SELECT installation_id, state FROM live_value_route WHERE grant_id = ?",
      [grant.grant_id],
    );
    expect(settledRoute).toEqual({ installation_id: transfer.to_installation_id, state: "stable" });

    const applied = await callVoidForReversal(reversal);
    expect(applied.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(transfer.to_installation_id));
    const destinationTerms = await readDoTerms(transfer.to_installation_id);
    expect(destinationTerms.find((row) => row.origin_grant_id === grant.grant_id)?.end_reason)
      .toBe("reversed");
  });

  it("R6-PT1: full reversal accepts the exact held installation route after deletion", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const grant = (await readDoGrants(scenario.installationId))[0]!;
    expect((await hpDeleteInstallation({ orgId: scenario.orgId })).result).toBe("ok");
    expect(await queryOne<{ status: string }>(
      "SELECT status FROM tenant_binding WHERE org_id = ? AND installation_id = ?",
      [scenario.orgId, scenario.installationId],
    )).toEqual({ status: "held_for_transfer" });

    const voided = await callVoidForReversal({ grantId: grant.grant_id, partial: false });
    expect(voided.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    expect((await readDoTerms(scenario.installationId)).find((row) => row.grant_id === grant.grant_id)?.end_reason)
      .toBe("reversed");
  });

  it("R6-PT3 R7-PS1 E2E-P3.8-08 purge of a deleted installation keeps the ledger", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const installationId = scenario.installationId;
    const orgId = scenario.orgId;

    const activeTerm = (await readDoTerms(installationId)).find(
      (row) => row.state === "active",
    );
    expect(activeTerm?.term_id).toBeTruthy();

    const recordedAt = getVendorTestClockIso() ?? new Date().toISOString();
    const usageEventId = crypto.randomUUID();
    await env.DB.prepare(
      `INSERT INTO usage_event (
        usage_event_id, installation_id, term_id, request_id, quota_weight, tokens, cost, recorded_at
      ) VALUES (?, ?, ?, NULL, ?, ?, ?, ?)`,
    )
      .bind(usageEventId, installationId, activeTerm!.term_id, 1, 50, 0.01, recordedAt)
      .run();

    const ledgerBefore = await count("grant_ledger", "org_id = ?", [orgId]);
    const voidBefore = await count(
      "grant_void",
      "grant_id IN (SELECT grant_id FROM grant_ledger WHERE org_id = ?)",
      [orgId],
    );
    const eventsBefore = await count("coverage_event", "installation_id = ?", [
      installationId,
    ]);
    const transfersBefore = await countTransferForOrg(orgId);
    const usageBefore = await count("usage_event", "term_id = ?", [
      activeTerm!.term_id,
    ]);

    expect(ledgerBefore).toBeGreaterThan(0);
    expect(eventsBefore).toBeGreaterThan(0);
    expect(usageBefore).toBe(1);

    const deleted = await hpDeleteInstallation({ orgId });
    expect(deleted.result).toBe("ok");
    await runDurableObjectAlarm(quotaDoStub(installationId));

    const installation = await queryOne<{ status: string }>(
      "SELECT status FROM installation WHERE installation_id = ?",
      [installationId],
    );
    expect(installation?.status).toBe("deleted");

    expect(await count("grant_ledger", "org_id = ?", [orgId])).toBe(ledgerBefore);
    expect(
      await count(
        "grant_void",
        "grant_id IN (SELECT grant_id FROM grant_ledger WHERE org_id = ?)",
        [orgId],
      ),
    ).toBe(voidBefore);
    expect(
      await count("coverage_event", "installation_id = ?", [installationId]),
    ).toBe(eventsBefore + 1);
    expect(await queryOne<{ state: string; clinic_seq: number }>(
      `SELECT state, clinic_seq FROM coverage_mirror WHERE installation_id = ?`,
      [installationId],
    )).toMatchObject({ state: "transfer_pending" });
    expect(await countTransferForOrg(orgId)).toBe(transfersBefore);
    expect(await count("usage_event", "term_id = ?", [activeTerm!.term_id])).toBe(
      usageBefore,
    );
  });
});
