/**
 * P3.11 — Platform rebuild procedures (H-AP, E2E-P3.11-01–04).
 */

import { env, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import {
  CHANNEL_VERSIONS,
  grantIdComp,
  grantIdPaid,
  sha256Hex,
} from "vendor-contracts";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  applyAllMigrations,
  CAPABILITY_ID,
  coverClinic,
  coverClinicAboKid,
  coverClinicSigner,
  encodeVendorAssertion,
  fakePolicyDocument,
  getVendorTestClockIso,
  VENDOR_OPERATOR_EMAIL,
  flushBackgroundWork,
  invoke,
  mintAat,
  mintVendorAccessJwt,
  newClinic,
  newScenario as harnessNewScenario,
  POLICY_ID,
  POLICY_VERSION,
  promote,
  publishPolicy,
  queryAll,
  queryOne,
  registerVisitSummaryCapability,
  resetPlatformState,
  r2Exists,
  setupVendorHarness,
  signCoverAbo,
  terminalEventTypes,
  vendorCall,
  type Scenario,
  type VendorMethod,
  type VendorResultEnvelope,
} from "./harness";

const diag = (msg: string) => console.log(`[DIAG] ${new Date().toISOString()} ${msg}`);

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const QUOTA_WEIGHT = 1;

type P311VendorMethod =
  | VendorMethod
  | "rebuildClinicDo"
  | "rebuildGrantLedger"
  | "refreshCoverageSnapshot"
  | "beginTransfer"
  | "transferOut"
  | "transferIn";

type P311ResultEnvelope = VendorResultEnvelope;

const p311VendorCall = vendorCall as (
  method: P311VendorMethod,
  args: Record<string, unknown>,
  opts?: {
    accessJwt?: string;
    assertion?: Record<string, unknown>;
  },
) => Promise<P311ResultEnvelope>;

function quotaDoStub(installationId: string) {
  return env.DO.get(env.DO.idFromName(installationId));
}

// Installations whose DO may have armed a real alarm during the current test.
// Cleared by the afterEach in the top-level describe.
const touchedInstallations = new Set<string>();

async function newScenario(
  ...args: Parameters<typeof harnessNewScenario>
): Promise<Awaited<ReturnType<typeof harnessNewScenario>>> {
  const scenario = await harnessNewScenario(...args);
  touchedInstallations.add(scenario.installationId);
  return scenario;
}

function sqlExec(state: DurableObjectState, query: string): void {
  const storage = state.storage as DurableObjectStorage & {
    sql?: { exec: (q: string) => unknown };
  };
  storage.sql?.exec(query);
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
  position: number;
  state: string;
  allowance: number | null;
  used_final: number | null;
};

type RecordedTerm = {
  term_id: string;
  position: number;
  state: string;
  held: boolean;
  allowance: number | null;
  used: number;
};

type GrantLedgerRow = {
  grant_id: string;
  origin_grant_id: string;
  org_id: string;
  installation_id: string;
  kind: string;
  source_kind: string;
  operator_credential_id: string;
  envelope_sha256: string;
  receipt: string;
  applied_at: string;
};

type GrantVoidRow = {
  grant_id: string;
  reason: string;
  source: string;
  evidence_sha256: string;
  at: string;
};

async function readDoTerms(installationId: string): Promise<DoTermRow[]> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect<DoTermRow>(
      state,
      `SELECT term_id, grant_id, position, state, allowance, used_final
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

async function readHotReservationsState(
  installationId: string,
): Promise<{ reservations: unknown[]; reserved: number }> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ reservations: string; reserved: number }>(
        state,
        "SELECT reservations, reserved FROM hot LIMIT 1",
      ),
  );
  const raw = rows[0]?.reservations ?? "[]";
  return {
    reservations: JSON.parse(raw) as unknown[],
    reserved: rows[0]?.reserved ?? 0,
  };
}

async function recordDoTermSnapshots(
  installationId: string,
): Promise<{ terms: RecordedTerm[]; hotUsed: number }> {
  const hotUsed = await readHotUsed(installationId);
  const terms = await readDoTerms(installationId);
  const activeId = terms.find((row) => row.state === "active")?.term_id;
  return {
    hotUsed,
    terms: terms.map((row) => ({
      term_id: row.term_id,
      position: row.position,
      state: row.state,
      held: row.state === "held",
      allowance: row.allowance,
      used:
        row.term_id === activeId
          ? hotUsed
          : (row.used_final ?? 0),
    })),
  };
}

async function wipeClinicDo(installationId: string): Promise<void> {
  await runInDurableObject(quotaDoStub(installationId), async (_instance, state) => {
    sqlExec(state, "DELETE FROM hot");
    sqlExec(state, "DELETE FROM term");
    sqlExec(state, "DELETE FROM grant");
    sqlExec(state, "DELETE FROM outbox");
  });
}

async function shipCoverageOutbox(installationId: string): Promise<void> {
  await runDurableObjectAlarm(quotaDoStub(installationId));
}

// Drain any unshipped outbox evidence and cancel the alarm the DO re-arms
// afterwards, so no real alarm is left pending when the test storage frame is
// torn down. Mirrors shipCoverageOutbox in admission-settlement.system.test.ts.
async function drainAndCancelDoAlarm(installationId: string): Promise<void> {
  await shipCoverageOutbox(installationId);
  await runInDurableObject(quotaDoStub(installationId), async (_instance, state) => {
    await state.storage.deleteAlarm();
  });
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
    plan: { plan_id: "live-monthly", plan_version: 1 },
    duration: { unit: "month", count: 1 },
    allowance_credits: input.allowanceCredits ?? 10_000,
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
): Promise<P311ResultEnvelope> {
  const envelope = await buildPaidGrantEnvelope({
    orgId: scenario.orgId,
    grantId,
  });
  const aboSignature = await signCoverAbo(envelope);
  return p311VendorCall("grant", {
    contract_version: CONTRACT_VERSION,
    envelope,
    abo_kid: coverClinicAboKid(),
    abo_signature: aboSignature,
  });
}

async function complimentaryGrant(
  scenario: Scenario,
  grantId: string,
): Promise<P311ResultEnvelope> {
  const signer = coverClinicSigner();
  const accessJwt = await mintVendorAccessJwt();
  const ref = crypto.randomUUID().replace(/-/g, "");
  const contentSha256 = await sha256Hex(new TextEncoder().encode(ref));
  const envelope: Record<string, unknown> = {
    contract_version: CONTRACT_VERSION,
    grant_id: grantId,
    org_id: scenario.orgId,
    kind: "term",
    placement: "queue",
    source: {
      kind: "complimentary",
      ref,
      operator_email: "untrusted-source@example.test",
      reason: "RM29 recovery provenance fixture",
    },
    plan: { plan_id: "live-monthly", plan_version: 1 },
    duration: { unit: "day", count: 14 },
    allowance_credits: 10_000,
    grace: { days: 7, cap_rule: "proportional" },
    evidence: {
      content_sha256: contentSha256,
      approvals: [{ credential_id: signer.signerCredentialId, assertion: "stub" }],
    },
  };
  const operation = {
    op: "grant",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: accessJwt,
      envelope,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
  const assertion = encodeVendorAssertion(
    await signer.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  return p311VendorCall(
    "grant",
    {
      contract_version: CONTRACT_VERSION,
      envelope,
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function setupComplimentaryRecoveryCapsule(): Promise<{
  scenario: Scenario;
  grantId: string;
  capsuleKey: string;
  capsuleText: string;
}> {
  const scenario = await newScenario();
  await coverClinic(scenario);
  await newClinic(scenario);
  const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
  expect((await complimentaryGrant(scenario, grantId)).result).toBe("applied");
  await shipCoverageOutbox(scenario.installationId);

  const target = await queryOne<{ grant_id: string }>(
    `SELECT grant_id FROM grant_ledger
     WHERE installation_id = ? AND source_kind = 'complimentary' AND grant_id = ?`,
    [scenario.installationId, grantId],
  );
  expect(target).toEqual({ grant_id: grantId });
  const capsuleKey = `grant-ledger/${grantId}.recovery-v1.ndjson`;
  const capsuleObject = await env.R2.get(capsuleKey);
  expect(capsuleObject).not.toBeNull();
  return {
    scenario,
    grantId,
    capsuleKey,
    capsuleText: await capsuleObject!.text(),
  };
}

async function readDoGrants(
  installationId: string,
): Promise<Array<{ grant_id: string }>> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect<{ grant_id: string }>(
      state,
      "SELECT grant_id FROM grant ORDER BY applied_at ASC",
    ),
  );
}

function randomHex64(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function callVoidForReversal(grantId: string): Promise<P311ResultEnvelope> {
  const body = {
    contract_version: CONTRACT_VERSION,
    grant_id: grantId,
    reversal_id: randomHex64(),
    reason: "payment reversed",
    evidence_sha256: randomHex64(),
    partial: false,
  };
  const aboSignature = await signCoverAbo(body);
  return p311VendorCall("voidForReversal", {
    ...body,
    abo_kid: coverClinicAboKid(),
    abo_signature: aboSignature,
  });
}

async function callReleaseHeld(grantId: string): Promise<P311ResultEnvelope> {
  const signer = coverClinicSigner();
  const accessJwt = await mintVendorAccessJwt();
  const operation = {
    op: "releaseHeld",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: accessJwt,
      grant_id: grantId,
      reason: "release held for rebuild test",
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
  const assertion = encodeVendorAssertion(
    await signer.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  return p311VendorCall(
    "releaseHeld",
    {
      contract_version: CONTRACT_VERSION,
      grant_id: grantId,
      reason: "release held for rebuild test",
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function completeTransferForRebuild(
  scenario: Scenario,
  options: { shipDestinationOutbox?: boolean } = {},
): Promise<{
  transferId: string;
  destinationInstallationId: string;
}> {
  const accessJwt = await mintVendorAccessJwt();
  const signer = coverClinicSigner();
  const reason = "platform rebuild transfer evidence fixture";
  const operation = {
    op: "beginTransfer",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: accessJwt,
      org_id: scenario.orgId,
      from_installation_id: scenario.installationId,
      reason,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
  const assertion = encodeVendorAssertion(
    await signer.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const begun = await p311VendorCall("beginTransfer", {
    contract_version: CONTRACT_VERSION,
    org_id: scenario.orgId,
    from_installation_id: scenario.installationId,
    reason,
    signer_credential_id: signer.signerCredentialId,
    operation,
    assertion,
  }, { accessJwt });
  expect(begun.result).toBe("ok");
  const transfer = JSON.parse(begun.detail ?? "{}") as {
    transfer_id?: string; to_installation_id?: string;
  };
  expect(transfer.transfer_id).toBeTruthy();
  expect(transfer.to_installation_id).toBeTruthy();
  const transferId = transfer.transfer_id!;
  const destinationInstallationId = transfer.to_installation_id!;
  touchedInstallations.add(destinationInstallationId);
  expect((await p311VendorCall("transferOut", {
    contract_version: CONTRACT_VERSION,
    transfer_id: transferId,
  })).result).toBe("applied");
  await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
  expect((await p311VendorCall("transferIn", {
    contract_version: CONTRACT_VERSION,
    transfer_id: transferId,
  })).result).toBe("applied");
  if (options.shipDestinationOutbox !== false) {
    await runDurableObjectAlarm(quotaDoStub(destinationInstallationId));
  }
  return { transferId, destinationInstallationId };
}

async function setupPromotedPolicy(scenario: Scenario): Promise<string> {
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  expect(published.status).toBe(200);
  const promoted = await promote(POLICY_ID, POLICY_VERSION);
  expect(promoted.status).toBe(200);
  return await mintAat(scenario);
}

async function completeChargedRequest(scenario: Scenario): Promise<void> {
  const invoked = await invoke(scenario, {
    token: await mintAat(scenario),
    idempotencyKey: crypto.randomUUID(),
  });
  expect(invoked.status).toBe(200);
  expect(terminalEventTypes(invoked.events)).toEqual(["completed"]);
  await flushBackgroundWork();
  await shipCoverageOutbox(scenario.installationId);
}

async function seedOpenReservation(scenario: Scenario): Promise<void> {
  const stub = quotaDoStub(scenario.installationId);
  const nowRow = await queryOne<{ now_iso: string }>(
    "SELECT now_iso FROM harness_test_clock WHERE id = 'default'",
  );
  const nowMs = nowRow?.now_iso ? Date.parse(nowRow.now_iso) : Date.now();
  const response = await stub.fetch("https://quota-do.internal/rpc", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contract_version: CHANNEL_VERSIONS.platformDo,
      kind: "admission",
      now: nowMs,
      jti: crypto.randomUUID(),
      installationId: scenario.installationId,
      idempotencyKey: crypto.randomUUID(),
      requestReference: `REBUILD-OPEN-${crypto.randomUUID()}`,
      capabilityId: CAPABILITY_ID,
      quotaWeight: QUOTA_WEIGHT,
      orgId: scenario.orgId,
    }),
  });
  expect(response.ok).toBe(true);
  const body = (await response.json()) as { outcome?: string };
  expect(body.outcome).toBe("admitted");
}

async function setupFm20Clinic(scenario: Scenario): Promise<void> {
  await coverClinic(scenario);
  await newClinic(scenario);

  const grantsBefore = await readDoGrants(scenario.installationId);
  const activeGrantId = grantsBefore[0]!.grant_id;

  const secondGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
  expect((await paidGrant(scenario, secondGrantId)).result).toBe("applied");
  await shipCoverageOutbox(scenario.installationId);

  expect((await callVoidForReversal(activeGrantId)).result).toBe("applied");
  await shipCoverageOutbox(scenario.installationId);

  expect((await callReleaseHeld(secondGrantId)).result).toBe("applied");
  await shipCoverageOutbox(scenario.installationId);

  const thirdGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
  expect((await paidGrant(scenario, thirdGrantId)).result).toBe("applied");
  await shipCoverageOutbox(scenario.installationId);

  const heldCount = (await readDoTerms(scenario.installationId)).filter(
    (row) => row.state === "held",
  ).length;
  expect(heldCount).toBeGreaterThanOrEqual(0);

  await setupPromotedPolicy(scenario);
  await completeChargedRequest(scenario);
  await completeChargedRequest(scenario);
  await seedOpenReservation(scenario);
}

async function callRebuildClinicDo(
  installationId: string,
): Promise<P311ResultEnvelope> {
  const accessJwt = await mintVendorAccessJwt();
  return p311VendorCall(
    "rebuildClinicDo",
    {
      contract_version: CONTRACT_VERSION,
      installation_id: installationId,
    },
    { accessJwt },
  );
}

async function copyGrantLedgerForInstallation(
  installationId: string,
): Promise<{ ledger: GrantLedgerRow[]; voids: GrantVoidRow[] }> {
  const ledger = await queryAll<GrantLedgerRow>(
    `SELECT grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
            operator_credential_id, envelope_sha256, receipt, applied_at
     FROM grant_ledger WHERE installation_id = ? ORDER BY applied_at ASC, grant_id ASC`,
    [installationId],
  );
  const voids = await queryAll<GrantVoidRow>(
    `SELECT grant_id, reason, source, evidence_sha256, at
     FROM grant_void
     WHERE grant_id IN (SELECT grant_id FROM grant_ledger WHERE installation_id = ?)
     ORDER BY at ASC, grant_id ASC`,
    [installationId],
  );
  return { ledger, voids };
}

async function truncateGrantLedgerForInstallation(
  installationId: string,
): Promise<void> {
  await env.DB.prepare("DROP TRIGGER IF EXISTS grant_ledger_no_delete").run();
  await env.DB.prepare("DROP TRIGGER IF EXISTS grant_void_no_delete").run();
  await env.DB.prepare(
    `DELETE FROM grant_void
     WHERE grant_id IN (SELECT grant_id FROM grant_ledger WHERE installation_id = ?)`,
  )
    .bind(installationId)
    .run();
  await env.DB.prepare("DELETE FROM grant_ledger WHERE installation_id = ?")
    .bind(installationId)
    .run();
  await env.DB.prepare(
    `CREATE TRIGGER grant_ledger_no_delete
     BEFORE DELETE ON grant_ledger
     BEGIN
       SELECT RAISE(ABORT, 'grant_ledger is append-only');
     END`,
  ).run();
  await env.DB.prepare(
    `CREATE TRIGGER grant_void_no_delete
     BEFORE DELETE ON grant_void
     BEGIN
       SELECT RAISE(ABORT, 'grant_void is append-only');
     END`,
  ).run();
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
  await setupVendorHarness();
});

beforeEach(async () => {
  vi.restoreAllMocks();
  await resetPlatformState();
  registerVisitSummaryCapability();
  await setupVendorHarness();
});

describe("platform rebuild procedures", () => {
  afterEach(async () => {
    try {
      for (const installationId of touchedInstallations) {
        await runInDurableObject(quotaDoStub(installationId), async (_instance, state) => {
          await state.storage.deleteAlarm();
        });
      }
    } finally {
      touchedInstallations.clear();
    }
  });

  it("R2-C3: rebuild and refresh reject mismatched DO versions without advancing projection", async () => {
    diag("START R2-C3: rebuild and refresh reject mismatched DO ");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    await shipCoverageOutbox(scenario.installationId);

    const eventsBefore = await queryOne<{ count: number }>(
      "SELECT COUNT(*) AS count FROM coverage_event WHERE installation_id = ?",
      [scenario.installationId],
    );
    const mirrorBefore = await queryOne<{
      clinic_seq: number;
      binding_epoch: number;
      state: string;
      suspended: number;
      term_snapshot: string;
    }>(
      `SELECT clinic_seq, binding_epoch, state, suspended, term_snapshot
       FROM coverage_mirror WHERE installation_id = ?`,
      [scenario.installationId],
    );
    const doFetch = vi.fn(async () =>
      Response.json({
        contract_version: CHANNEL_VERSIONS.platformDo + 1,
        result: "ok",
        snapshot: {},
        event_id: "mismatched-version-event",
      }),
    );
    const getSpy = vi
      .spyOn(env.DO, "get")
      .mockReturnValue({ fetch: doFetch } as unknown as DurableObjectStub);

    let rebuilt: P311ResultEnvelope;
    let refreshed: P311ResultEnvelope;
    try {
      rebuilt = await callRebuildClinicDo(scenario.installationId);
      const accessJwt = await mintVendorAccessJwt();
      refreshed = await p311VendorCall(
        "refreshCoverageSnapshot",
        {
          contract_version: CONTRACT_VERSION,
          installation_id: scenario.installationId,
        },
        { accessJwt },
      );
    } finally {
      getSpy.mockRestore();
    }

    expect(doFetch).toHaveBeenCalledTimes(2);
    expect(rebuilt.result).toBe("rejected");
    expect(rebuilt.code).toBe("not_found");
    expect(refreshed.result).toBe("rejected");
    expect(refreshed.code).toBe("not_found");
    expect(
      await queryOne<{ count: number }>(
        "SELECT COUNT(*) AS count FROM coverage_event WHERE installation_id = ?",
        [scenario.installationId],
      ),
    ).toEqual(eventsBefore);
    expect(
      await queryOne(
        `SELECT clinic_seq, binding_epoch, state, suspended, term_snapshot
         FROM coverage_mirror WHERE installation_id = ?`,
        [scenario.installationId],
      ),
    ).toEqual(mirrorBefore);
    diag("END R2-C3: rebuild and refresh reject mismatched DO ");
  });

  it("R9-PUS1 FM-20: distinct accounting sequences rebuild usage once and compare clean", async () => {
    diag("START R9-PUS1 FM-20: distinct accounting sequences reb");
    const scenario = await newScenario();
    await setupFm20Clinic(scenario);

    const usage = await queryAll<{ accounting_seq: number; origin_request_id: string }>(
      `SELECT accounting_seq, origin_request_id FROM usage_event
       WHERE installation_id = ? ORDER BY accounting_seq`,
      [scenario.installationId],
    );
    expect(usage).toHaveLength(2);
    expect(new Set(usage.map((row) => row.accounting_seq)).size).toBe(2);
    expect(new Set(usage.map((row) => row.origin_request_id)).size).toBe(2);

    const before = await recordDoTermSnapshots(scenario.installationId);

    await wipeClinicDo(scenario.installationId);

    const rebuilt = await callRebuildClinicDo(scenario.installationId);
    expect(rebuilt.result).toBe("ok");
    expect(rebuilt.code).toBe("");
    expect(rebuilt.receipt).toBeUndefined();
    expect(JSON.parse(rebuilt.detail)).toEqual({
      compare: "clean",
      installation_id: scenario.installationId,
    });

    const after = await recordDoTermSnapshots(scenario.installationId);
    expect(after.terms).toEqual(before.terms);
    expect(after.hotUsed).toBe(before.hotUsed);

    const hotState = await readHotReservationsState(scenario.installationId);
    expect(hotState.reservations).toEqual([]);
    expect(hotState.reserved).toBe(0);

    const alert = await queryOne<{ alert_key: string }>(
      "SELECT alert_key FROM platform_alert WHERE alert_key = ?",
      [`do-rebuild:${scenario.installationId}`],
    );
    expect(alert).toBeNull();
    diag("END R9-PUS1 FM-20: distinct accounting sequences reb");
  });

  it("R9-PUS1: delayed journal rows after an accounting-watermarked snapshot do not double-charge", async () => {
    diag("START R9-PUS1: delayed journal rows after an accountin");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    await setupPromotedPolicy(scenario);
    await completeChargedRequest(scenario);
    await completeChargedRequest(scenario);

    const usage = await queryAll<{ usage_event_id: string; origin_request_id: string; accounting_seq: number; term_id: string; quota_weight: number; tokens: number; cost: number; recorded_at: string }>(
      `SELECT usage_event_id, origin_request_id, accounting_seq, term_id, quota_weight, tokens, cost, recorded_at FROM usage_event
       WHERE installation_id = ? ORDER BY accounting_seq`,
      [scenario.installationId],
    );
    expect(usage).toHaveLength(2);
    expect(new Set(usage.map((row) => row.accounting_seq)).size).toBe(2);
    expect(usage[0]!.recorded_at).toBe(usage[1]!.recorded_at);
    await env.DB.prepare("DELETE FROM usage_event WHERE installation_id = ?")
      .bind(scenario.installationId).run();

    const accessJwt = await mintVendorAccessJwt();
    const snapshotResult = await p311VendorCall(
      "refreshCoverageSnapshot",
      { contract_version: CONTRACT_VERSION, installation_id: scenario.installationId },
      { accessJwt },
    );
    expect(snapshotResult.result).toBe("ok");
    const detail = JSON.parse(snapshotResult.detail) as { event_id: string };
    const event = await queryOne<{ snapshot: string; at: string }>(
      "SELECT snapshot, at FROM coverage_event WHERE event_id = ?",
      [detail.event_id],
    );
    expect(JSON.parse(event!.snapshot).accounting_seq).toBe(usage[1]!.accounting_seq);

    const before = await recordDoTermSnapshots(scenario.installationId);
    const delayedAt = new Date(Date.parse(event!.at) + 1000).toISOString();
    for (const row of usage) {
      await env.DB.prepare(
        `INSERT INTO usage_event (
          usage_event_id, installation_id, term_id, origin_request_id, accounting_seq,
          quota_weight, tokens, cost, recorded_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        row.usage_event_id, scenario.installationId, row.term_id, row.origin_request_id,
        row.accounting_seq, row.quota_weight, row.tokens, row.cost, delayedAt,
      ).run();
    }
    await wipeClinicDo(scenario.installationId);

    const rebuilt = await callRebuildClinicDo(scenario.installationId);
    expect(rebuilt.result).toBe("ok");
    expect(await recordDoTermSnapshots(scenario.installationId)).toEqual(before);
    diag("END R9-PUS1: delayed journal rows after an accountin");
  });

  it("R9-PUS1: a missing post-snapshot accounting sequence blocks rebuild", async () => {
    diag("START R9-PUS1: a missing post-snapshot accounting sequ");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    await setupPromotedPolicy(scenario);
    await completeChargedRequest(scenario);
    await completeChargedRequest(scenario);
    const rows = await queryAll<{ usage_event_id: string; accounting_seq: number }>(
      `SELECT usage_event_id, accounting_seq FROM usage_event
       WHERE installation_id = ? ORDER BY accounting_seq`,
      [scenario.installationId],
    );
    expect(rows.map((row) => row.accounting_seq)).toEqual([1, 2]);
    await env.DB.prepare("DELETE FROM usage_event WHERE usage_event_id = ?")
      .bind(rows[0]!.usage_event_id).run();
    await wipeClinicDo(scenario.installationId);

    const rebuilt = await callRebuildClinicDo(scenario.installationId);
    expect(rebuilt.result).toBe("rejected");
    expect(rebuilt.code).toBe("recovery_blocked");
    expect(rebuilt.detail).toContain("usage_accounting_sequence_gap");
    diag("END R9-PUS1: a missing post-snapshot accounting sequ");
  });

  it("R9-PUS1: replayed zero-weight release advances the next settlement sequence", async () => {
    diag("START R9-PUS1: replayed zero-weight release advances t");
    const scenario = await newScenario();
    await setupPromotedPolicy(scenario);
    await coverClinic(scenario);
    const activeTerm = (await readDoTerms(scenario.installationId))
      .find((term) => term.state === "active");
    expect(activeTerm).toBeTruthy();

    const releasedId = crypto.randomUUID();
    const released = await quotaDoStub(scenario.installationId).fetch(
      "https://quota-do.internal/rpc",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contract_version: CHANNEL_VERSIONS.platformDo,
          kind: "settleFallback",
          installationId: scenario.installationId,
          request_id: releasedId,
          term_id: activeTerm!.term_id,
          weight: 1,
          outcome: "released",
        }),
      },
    );
    expect(await released.json()).toMatchObject({
      kind: "settleFallback", outcome: "settled", chargedWeight: 0,
      accountingSequence: 1,
    });
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    const releasedFact = await queryOne<{ accounting_seq: number; quota_weight: number }>(
      `SELECT accounting_seq, quota_weight FROM usage_event
       WHERE installation_id = ? AND origin_request_id = ?`,
      [scenario.installationId, releasedId],
    );
    expect(releasedFact).toEqual({ accounting_seq: 1, quota_weight: 0 });
    await wipeClinicDo(scenario.installationId);

    expect((await callRebuildClinicDo(scenario.installationId)).result).toBe("ok");
    const consumedId = crypto.randomUUID();
    const consumed = await quotaDoStub(scenario.installationId).fetch(
      "https://quota-do.internal/rpc",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contract_version: CHANNEL_VERSIONS.platformDo,
          kind: "settleFallback",
          installationId: scenario.installationId,
          request_id: consumedId,
          term_id: activeTerm!.term_id,
          weight: 1,
          outcome: "consumed",
        }),
      },
    );
    expect(await consumed.json()).toMatchObject({
      kind: "settleFallback", outcome: "settled", chargedWeight: 1,
      accountingSequence: 2,
    });
    const receipts = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, state) => sqlSelect<{ request_id: string; accounting_seq: number }>(
        state,
        "SELECT request_id, accounting_seq FROM usage_settlement_receipt ORDER BY accounting_seq",
      ),
    );
    expect(receipts).toEqual([
      { request_id: releasedId, accounting_seq: 1 },
      { request_id: consumedId, accounting_seq: 2 },
    ]);
    await drainAndCancelDoAlarm(scenario.installationId);
    diag("END R9-PUS1: replayed zero-weight release advances t");
  });

  it("R9-PUS1: rebuild blocks while a settlement accounting intent remains unshipped", async () => {
    diag("START R9-PUS1: rebuild blocks while a settlement accou");
    diag("R9-PUS1: rebuild blocks while a settleme step 1 before newScenario");
    const scenario = await newScenario();
    diag("R9-PUS1: rebuild blocks while a settleme step 1 after newScenario");
    diag("R9-PUS1: rebuild blocks while a settleme step 2 before coverClinic");
    await coverClinic(scenario);
    diag("R9-PUS1: rebuild blocks while a settleme step 2 after coverClinic");
    diag("R9-PUS1: rebuild blocks while a settleme step 3 before readDoTerms");
    const activeTerm = (await readDoTerms(scenario.installationId))
      .find((term) => term.state === "active");
    diag("R9-PUS1: rebuild blocks while a settleme step 3 after readDoTerms");
    expect(activeTerm).toBeTruthy();
    const requestId = crypto.randomUUID();
    diag("R9-PUS1: rebuild blocks while a settleme step 4 before quotaDoStub");
    const settled = await quotaDoStub(scenario.installationId).fetch(
      "https://quota-do.internal/rpc",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contract_version: CHANNEL_VERSIONS.platformDo,
          kind: "settleFallback",
          installationId: scenario.installationId,
          request_id: requestId,
          term_id: activeTerm!.term_id,
          weight: 1,
          outcome: "consumed",
        }),
      },
    );
    diag("R9-PUS1: rebuild blocks while a settleme step 4 after quotaDoStub");
    diag("R9-PUS1: rebuild blocks while a settleme step 5 before settled");
    expect(await settled.json()).toMatchObject({
      kind: "settleFallback", outcome: "settled", accountingSequence: 1,
    });
    diag("R9-PUS1: rebuild blocks while a settleme step 5 after settled");

    diag("R9-PUS1: rebuild blocks while a settleme step 6 before callRebuildClinicDo");
    const rebuild = await callRebuildClinicDo(scenario.installationId);
    diag("R9-PUS1: rebuild blocks while a settleme step 6 after callRebuildClinicDo");
    expect(rebuild.result).toBe("rejected");
    expect(rebuild.code).toBe("recovery_blocked");
    diag("R9-PUS1: rebuild blocks while a settleme step 7 before runInDurableObject");
    const intent = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, state) => sqlSelect<{ payload: string }>(
        state, "SELECT payload FROM outbox WHERE kind = 'usage_adjustment'",
      ).map((row) => JSON.parse(row.payload) as Record<string, unknown>),
    );
    diag("R9-PUS1: rebuild blocks while a settleme step 7 after runInDurableObject");
    expect(intent).toContainEqual(expect.objectContaining({
      request_id: requestId, term_id: activeTerm!.term_id,
      quota_weight: 1, accounting_seq: 1,
    }));
    diag("R9-PUS1: rebuild blocks while a settleme step 8 before readHotUsed");
    expect(await readHotUsed(scenario.installationId)).toBe(1);
    diag("R9-PUS1: rebuild blocks while a settleme step 8 after readHotUsed");
    // All assertions above run against the unshipped intent. Drain afterwards
    // so no re-armed alarm can fire during storage-frame teardown.
    diag("R9-PUS1: rebuild blocks while a settleme step 9 before drainAndCancelDoAlarm");
    await drainAndCancelDoAlarm(scenario.installationId);
    diag("R9-PUS1: rebuild blocks while a settleme step 9 after drainAndCancelDoAlarm");
    diag("END R9-PUS1: rebuild blocks while a settlement accou");
  });

  it("R9-PDO1: rebuild refuses a nonempty DO and preserves an unshipped grant", async () => {
    diag("START R9-PDO1: rebuild refuses a nonempty DO and prese");
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 1 before newScenario");
    const scenario = await newScenario();
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 1 after newScenario");
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 2 before coverClinic");
    await coverClinic(scenario);
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 2 after coverClinic");
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 3 before newClinic");
    await newClinic(scenario);
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 3 after newClinic");
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 4 before recordDoTermSnapshots");
    const before = await recordDoTermSnapshots(scenario.installationId);
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 4 after recordDoTermSnapshots");
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 5 before runInDurableObject");
    const outboxBefore = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, state) => sqlSelect<{ count: number }>(state, "SELECT COUNT(*) AS count FROM outbox")[0]?.count ?? 0,
    );
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 5 after runInDurableObject");

    diag("R9-PDO1: rebuild refuses a nonempty DO a step 6 before callRebuildClinicDo");
    const rebuilt = await callRebuildClinicDo(scenario.installationId);
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 6 after callRebuildClinicDo");
    expect(rebuilt.result).toBe("rejected");
    expect(rebuilt.code).toBe("recovery_blocked");
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 7 before recordDoTermSnapshots");
    expect(await recordDoTermSnapshots(scenario.installationId)).toEqual(before);
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 7 after recordDoTermSnapshots");
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 8 before runInDurableObject");
    const outboxAfter = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, state) => sqlSelect<{ count: number }>(state, "SELECT COUNT(*) AS count FROM outbox")[0]?.count ?? 0,
    );
    diag("R9-PDO1: rebuild refuses a nonempty DO a step 8 after runInDurableObject");
    expect(outboxAfter).toBe(outboxBefore);
    diag("END R9-PDO1: rebuild refuses a nonempty DO and prese");
  });

  it("R9-PDO1 RM29-F1: a building recovery marker cannot authorize wiping a nonempty DO", async () => {
    diag("START R9-PDO1 RM29-F1: a building recovery marker cann");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const before = await recordDoTermSnapshots(scenario.installationId);
    const anchor = await queryOne<{ event_id: string; binding_epoch: number }>(
      `SELECT event_id, binding_epoch FROM coverage_event
       WHERE installation_id = ? ORDER BY clinic_seq DESC LIMIT 1`,
      [scenario.installationId],
    );
    expect(anchor).not.toBeNull();
    await runInDurableObject(quotaDoStub(scenario.installationId), async (_instance, state) => {
      sqlExec(state, `INSERT INTO recovery_state (
        singleton, generation, installation_id, org_id, binding_epoch,
        anchor_event_id, status, updated_at
      ) VALUES (1, '${scenario.installationId}:${anchor!.binding_epoch}:${anchor!.event_id}',
        '${scenario.installationId}', '${scenario.orgId}', ${anchor!.binding_epoch},
        '${anchor!.event_id}', 'building', '2026-10-21T00:00:00.000Z')`);
    });

    const rebuilt = await callRebuildClinicDo(scenario.installationId);
    expect(rebuilt.result).toBe("rejected");
    expect(rebuilt.code).toBe("recovery_blocked");
    expect(await recordDoTermSnapshots(scenario.installationId)).toEqual(before);
    diag("END R9-PDO1 RM29-F1: a building recovery marker cann");
  });

  it("R9-PDO1: mirror mismatch blocks activation and alerts", async () => {
    diag("START R9-PDO1: mirror mismatch blocks activation and a");
    const scenario = await newScenario();
    await setupFm20Clinic(scenario);
    await recordDoTermSnapshots(scenario.installationId);

    await env.DB.prepare(
      "UPDATE coverage_mirror SET state = ? WHERE installation_id = ?",
    )
      .bind("mirror_diverged_for_test", scenario.installationId)
      .run();

    await wipeClinicDo(scenario.installationId);
    const rebuilt = await callRebuildClinicDo(scenario.installationId);
    expect(rebuilt.result).toBe("rejected");
    expect(rebuilt.code).toBe("recovery_blocked");

    const alert = await queryOne<{
      alert_key: string;
      code: string;
      severity: string;
      send_state: string;
    }>(
      `SELECT alert_key, code, severity, send_state
       FROM platform_alert WHERE alert_key = ?`,
      [`do-rebuild:${scenario.installationId}`],
    );
    expect(alert).toEqual({
      alert_key: `do-rebuild:${scenario.installationId}`,
      code: "do_rebuild_mismatch",
      severity: "high",
      send_state: "unsent",
    });
    diag("END R9-PDO1: mirror mismatch blocks activation and a");
  });

  it("R9-PDO1: rebuild preserves signed pre-anchor void evidence and exact void state", async () => {
    diag("START R9-PDO1: rebuild preserves signed pre-anchor voi");
    const scenario = await newScenario();
    await setupFm20Clinic(scenario);
    const voidRow = await queryOne<{
      grant_id: string; reason: string; at: string;
    }>(
      `SELECT grant_id, reason, at FROM grant_void
       WHERE grant_id IN (SELECT grant_id FROM grant_ledger WHERE installation_id = ?)
       ORDER BY at ASC LIMIT 1`,
      [scenario.installationId],
    );
    expect(voidRow).not.toBeNull();
    const before = await queryOne<{ at: string; reason: string }>(
      `SELECT at, reason FROM grant_void WHERE grant_id = ?`, [voidRow!.grant_id],
    );
    await wipeClinicDo(scenario.installationId);

    const rebuilt = await callRebuildClinicDo(scenario.installationId);
    expect(rebuilt.result).toBe("ok");
    const state = await runInDurableObject(
      quotaDoStub(scenario.installationId),
      async (_instance, durableState) => ({
        grant: sqlSelect<{ voided_at: string | null; void_reason: string | null }>(
          durableState,
          `SELECT voided_at, void_reason FROM grant WHERE grant_id = '${voidRow!.grant_id}'`,
        )[0],
        term: sqlSelect<{ state: string; end_reason: string | null; ended_at: string | null }>(
          durableState,
          `SELECT state, end_reason, ended_at FROM term WHERE grant_id = '${voidRow!.grant_id}'`,
        )[0],
      }),
    );
    expect(state.grant).toEqual({ voided_at: before!.at, void_reason: before!.reason });
    expect(state.term?.state).toBe("ended");
    expect(state.term?.end_reason).toBe("reversed");
    expect(state.term?.ended_at).toBe(before!.at);
    diag("END R9-PDO1: rebuild preserves signed pre-anchor voi");
  });

  it("R9-PDO1: rebuild blocks with operator evidence reason when a pre-anchor void proof is missing", async () => {
    diag("START R9-PDO1: rebuild blocks with operator evidence r");
    const scenario = await newScenario();
    await setupFm20Clinic(scenario);
    const voidRow = await queryOne<{ grant_id: string; reason: string; at: string }>(
      `SELECT grant_id, reason, at FROM grant_void
       WHERE grant_id IN (SELECT grant_id FROM grant_ledger WHERE installation_id = ?)
       ORDER BY at ASC LIMIT 1`,
      [scenario.installationId],
    );
    expect(voidRow).not.toBeNull();
    await env.R2.delete(`grant-ledger/${voidRow!.grant_id}.void.ndjson`);
    await wipeClinicDo(scenario.installationId);

    const rebuilt = await callRebuildClinicDo(scenario.installationId);
    expect(rebuilt.result).toBe("rejected");
    expect(rebuilt.code).toBe("recovery_blocked");
    expect(rebuilt.detail).toContain("grant_void_recovery_evidence_missing");
    expect(await queryOne(
      `SELECT grant_id FROM grant_void WHERE grant_id = ?`, [voidRow!.grant_id],
    )).toEqual({ grant_id: voidRow!.grant_id });
    diag("END R9-PDO1: rebuild blocks with operator evidence r");
  });

  it("R9-PDO1: missing transfer replay evidence fences rebuild and preserves the D1 step", async () => {
    diag("START R9-PDO1: missing transfer replay evidence fences");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const { transferId, destinationInstallationId } = await completeTransferForRebuild(scenario);
    const stepBefore = await queryOne<{ receipt: string }>(
      `SELECT receipt FROM transfer_step WHERE transfer_id = ? AND step = 'transfer_in'`,
      [transferId],
    );
    expect(stepBefore?.receipt).toBeTruthy();
    await runInDurableObject(
      quotaDoStub(destinationInstallationId),
      async (_instance, state) => sqlExec(state,
        `DELETE FROM transfer_replay WHERE transfer_id = '${transferId}' AND step = 'transfer_in'`,
      ),
    );
    await wipeClinicDo(destinationInstallationId);

    const rebuilt = await callRebuildClinicDo(destinationInstallationId);
    expect(rebuilt.result).toBe("rejected");
    expect(rebuilt.code).toBe("recovery_blocked");
    expect(rebuilt.detail).toContain("transfer_replay_evidence_missing");
    expect(rebuilt.detail).toContain("do not synthesize request hashes or response_json");

    const stepAfter = await queryOne<{ receipt: string }>(
      "SELECT receipt FROM transfer_step WHERE transfer_id = ? AND step = 'transfer_in'",
      [transferId],
    );
    expect(stepAfter?.receipt).toBe(stepBefore?.receipt);
    const recovery = await runInDurableObject(
      quotaDoStub(destinationInstallationId),
      async (_instance, state) => sqlSelect<{ status: string }>(
        state,
        "SELECT status FROM recovery_state WHERE singleton = 1",
      )[0]?.status,
    );
    expect(recovery).toBe("blocked");
    const alert = await queryOne<{ alert_key: string; code: string }>(
      "SELECT alert_key, code FROM platform_alert WHERE alert_key = ?",
      [`do-rebuild:${destinationInstallationId}:transfer_replay_evidence_missing`],
    );
    expect(alert?.code).toBe("do_rebuild_mismatch");
    diag("END R9-PDO1: missing transfer replay evidence fences");
  });

  it("R9-PDO1: rebuild preserves verified transfer replay evidence without blocking", async () => {
    diag("START R9-PDO1: rebuild preserves verified transfer rep");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const { transferId, destinationInstallationId } = await completeTransferForRebuild(scenario);
    const ledger = await queryOne<{ grant_id: string }>(
      `SELECT grant_id FROM grant_ledger
       WHERE installation_id = ? AND source_kind = 'transfer' LIMIT 1`,
      [destinationInstallationId],
    );
    expect(ledger?.grant_id).toBeTruthy();
    expect(await r2Exists(`grant-ledger/${ledger!.grant_id}.recovery-v1.ndjson`)).toBe(true);
    const step = await queryOne<{ receipt: string }>(
      `SELECT receipt FROM transfer_step WHERE transfer_id = ? AND step = 'transfer_in'`,
      [transferId],
    );
    expect(step?.receipt).toBeTruthy();
    await wipeClinicDo(destinationInstallationId);

    const rebuilt = await callRebuildClinicDo(destinationInstallationId);
    expect(rebuilt.result).toBe("ok");
    const preserved = await runInDurableObject(
      quotaDoStub(destinationInstallationId),
      async (_instance, state) => sqlSelect<{
        request_sha256: string;
        response_json: string;
      }>(
        state,
        `SELECT request_sha256, response_json FROM transfer_replay
         WHERE transfer_id = '${transferId}' AND step = 'transfer_in'`,
      )[0],
    );
    expect(preserved?.request_sha256).toMatch(/^[a-f0-9]{64}$/u);
    expect(JSON.parse(preserved!.response_json).receipt).toEqual(JSON.parse(step!.receipt));
    diag("END R9-PDO1: rebuild preserves verified transfer rep");
  });

  it("R9-PDO1 RM29-F3: transfer grant recovery capsule ships from the outbox and is acknowledged", async () => {
    diag("START R9-PDO1 RM29-F3: transfer grant recovery capsule");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const { transferId, destinationInstallationId } = await completeTransferForRebuild(
      scenario,
      { shipDestinationOutbox: false },
    );
    const pending = await runInDurableObject(
      quotaDoStub(destinationInstallationId),
      async (_instance, state) => sqlSelect<{ seq: number; kind: string; payload: string }>(
        state,
        "SELECT seq, kind, payload FROM outbox WHERE kind = 'grant_ledger' ORDER BY seq ASC",
      ),
    );
    const grantOutbox = pending.filter((row) => {
      const payload = JSON.parse(row.payload) as { source_kind?: string };
      return payload.source_kind === "transfer";
    });
    expect(grantOutbox).toHaveLength(1);
    const outboxSeq = grantOutbox[0]!.seq;
    const grantId = (JSON.parse(grantOutbox[0]!.payload) as { grant_id: string }).grant_id;
    const capsuleKey = `grant-ledger/${grantId}.recovery-v1.ndjson`;
    expect(await env.R2.get(capsuleKey)).toBeNull();

    await shipCoverageOutbox(destinationInstallationId);

    const acknowledged = await runInDurableObject(
      quotaDoStub(destinationInstallationId),
      async (_instance, state) => sqlSelect<{ seq: number }>(
        state,
        `SELECT seq FROM outbox WHERE seq = ${outboxSeq}`,
      ),
    );
    expect(acknowledged).toEqual([]);
    const ledger = await queryOne<{
      grant_id: string;
      org_id: string;
      installation_id: string;
      source_kind: string;
      envelope_sha256: string;
      receipt: string;
    }>(
      `SELECT grant_id, org_id, installation_id, source_kind, envelope_sha256, receipt
       FROM grant_ledger WHERE grant_id = ?`,
      [grantId],
    );
    expect(ledger).toBeTruthy();
    const capsuleObject = await env.R2.get(capsuleKey);
    expect(capsuleObject).not.toBeNull();
    const capsule = JSON.parse(await capsuleObject!.text()) as {
      version: number;
      grant_id: string;
      org_id: string;
      installation_id: string;
      source_kind: string;
      envelope_sha256: string;
      receipt: unknown;
      transfer_evidence: { transfer_id: string; step: string; receipt_text: string };
    };
    expect(capsule).toMatchObject({
      version: 1,
      grant_id: ledger!.grant_id,
      org_id: ledger!.org_id,
      installation_id: ledger!.installation_id,
      source_kind: "transfer",
      envelope_sha256: ledger!.envelope_sha256,
      receipt: JSON.parse(ledger!.receipt),
      transfer_evidence: { transfer_id: transferId, step: "transfer_in" },
    });
    const transferStep = await queryOne<{ receipt: string }>(
      "SELECT receipt FROM transfer_step WHERE transfer_id = ? AND step = 'transfer_in'",
      [transferId],
    );
    expect(capsule.transfer_evidence.receipt_text).toBe(transferStep?.receipt);
    diag("END R9-PDO1 RM29-F3: transfer grant recovery capsule");
  });

  it("R9-PDO1: transfer replay request-hash and signed-receipt tampering fence rebuild", async () => {
    diag("START R9-PDO1: transfer replay request-hash and signed");
    for (const tamper of ["request_hash", "receipt"] as const) {
      const scenario = await newScenario();
      await coverClinic(scenario);
      await newClinic(scenario);
      const { transferId, destinationInstallationId } = await completeTransferForRebuild(scenario);
      await runInDurableObject(
        quotaDoStub(destinationInstallationId),
        async (_instance, state) => {
          const replay = sqlSelect<{ response_json: string }>(
            state,
            `SELECT response_json FROM transfer_replay
             WHERE transfer_id = '${transferId}' AND step = 'transfer_in'`,
          )[0];
          if (replay === undefined) throw new Error("transfer-in replay missing from fixture");
          if (tamper === "request_hash") {
            sqlExec(state,
              `UPDATE transfer_replay SET request_sha256 = '${"e".repeat(64)}'
               WHERE transfer_id = '${transferId}' AND step = 'transfer_in'`,
            );
          } else {
            const response = JSON.parse(replay.response_json) as Record<string, unknown>;
            const receipt = response.receipt as Record<string, unknown>;
            receipt.signature = `${String(receipt.signature)}-tampered`;
            const responseJson = JSON.stringify(response).replaceAll("'", "''");
            sqlExec(state,
              `UPDATE transfer_replay SET response_json = '${responseJson}'
               WHERE transfer_id = '${transferId}' AND step = 'transfer_in'`,
            );
          }
        },
      );
      await wipeClinicDo(destinationInstallationId);
      const rebuilt = await callRebuildClinicDo(destinationInstallationId);
      expect(rebuilt.result).toBe("rejected");
      expect(rebuilt.code).toBe("recovery_blocked");
      expect(rebuilt.detail).toContain("transfer_replay_evidence_missing");
    }
    diag("END R9-PDO1: transfer replay request-hash and signed");
  });

  it("R9-PDO1: ledger replay blocks when the verified recovery capsule is missing", async () => {
    diag("START R9-PDO1: ledger replay blocks when the verified ");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    await shipCoverageOutbox(scenario.installationId);

    const grantRow = await queryOne<{ grant_id: string }>(
      "SELECT grant_id FROM grant_ledger WHERE installation_id = ? ORDER BY applied_at ASC LIMIT 1",
      [scenario.installationId],
    );
    expect(grantRow?.grant_id).toBeTruthy();
    expect(await r2Exists(`grant-ledger/${grantRow!.grant_id}.ndjson`)).toBe(
      true,
    );

    const copy = await copyGrantLedgerForInstallation(scenario.installationId);
    expect(copy.ledger.length).toBeGreaterThan(0);
    await env.R2.delete(`grant-ledger/${grantRow!.grant_id}.recovery-v1.ndjson`);

    await truncateGrantLedgerForInstallation(scenario.installationId);
    expect(
      await queryOne("SELECT grant_id FROM grant_ledger WHERE installation_id = ?", [
        scenario.installationId,
      ]),
    ).toBeNull();

    const accessJwt = await mintVendorAccessJwt();
    const rebuilt = await p311VendorCall(
      "rebuildGrantLedger",
      { contract_version: CONTRACT_VERSION },
      { accessJwt },
    );
    expect(rebuilt.result).toBe("rejected");
    expect(rebuilt.code).toBe("recovery_evidence_required");
    expect(rebuilt.detail).toContain("grant_recovery_capsule_required");

    const stillEmpty = await copyGrantLedgerForInstallation(scenario.installationId);
    expect(stillEmpty.ledger).toEqual([]);
    expect(stillEmpty.voids).toEqual([]);
    diag("END R9-PDO1: ledger replay blocks when the verified ");
  });

  it("R9-PDO1: verified recovery capsule restores the exact grant ledger and accepted claim", async () => {
    diag("START R9-PDO1: verified recovery capsule restores the ");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    await shipCoverageOutbox(scenario.installationId);
    const original = await queryOne<{ grant_id: string; receipt: string }>(
      `SELECT grant_id, receipt FROM grant_ledger WHERE installation_id = ? ORDER BY applied_at ASC LIMIT 1`,
      [scenario.installationId],
    );
    expect(original?.grant_id).toBeTruthy();
    await truncateGrantLedgerForInstallation(scenario.installationId);

    const accessJwt = await mintVendorAccessJwt();
    const rebuilt = await p311VendorCall(
      "rebuildGrantLedger",
      { contract_version: CONTRACT_VERSION },
      { accessJwt },
    );
    expect(rebuilt.result).toBe("ok");
    const restored = await queryOne<{ grant_id: string; receipt: string }>(
      `SELECT grant_id, receipt FROM grant_ledger WHERE grant_id = ?`,
      [original!.grant_id],
    );
    expect(restored?.grant_id).toBe(original!.grant_id);
    expect(JSON.parse(restored!.receipt)).toEqual(JSON.parse(original!.receipt));
    const claim = await queryOne<{ state: string; receipt: string }>(
      `SELECT state, receipt FROM grant_claim WHERE grant_id = ?`,
      [original!.grant_id],
    );
    expect(claim?.state).toBe("completed");
    expect(JSON.parse(claim!.receipt)).toEqual(JSON.parse(original!.receipt));
    diag("END R9-PDO1: verified recovery capsule restores the ");
  });

  it("R9-PDO1 RM29-F2: capsule ceiling-claim tampering is rejected before any ledger import", async () => {
    diag("START R9-PDO1 RM29-F2: capsule ceiling-claim tampering");
    const { scenario, capsuleKey, capsuleText } = await setupComplimentaryRecoveryCapsule();
    const capsule = JSON.parse(capsuleText) as Record<string, unknown>;
    capsule.ceiling_claim = null;
    await env.R2.put(capsuleKey, `${JSON.stringify(capsule)}\n`);
    await truncateGrantLedgerForInstallation(scenario.installationId);

    const accessJwt = await mintVendorAccessJwt();
    const rejected = await p311VendorCall(
      "rebuildGrantLedger", { contract_version: CONTRACT_VERSION }, { accessJwt },
    );
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("recovery_evidence_required");
    expect(rejected.detail).toContain("grant_recovery_ceiling_claim_required");
    expect(await queryOne(
      `SELECT grant_id FROM grant_ledger WHERE installation_id = ?`,
      [scenario.installationId],
    )).toBeNull();
    diag("END R9-PDO1 RM29-F2: capsule ceiling-claim tampering");
  });

  it("R9-PDO1 RM29-F2: accepted-actor capsule provenance tampering is rejected", async () => {
    diag("START R9-PDO1 RM29-F2: accepted-actor capsule provenan");
    const { scenario, capsuleKey, capsuleText } = await setupComplimentaryRecoveryCapsule();
    const capsule = JSON.parse(capsuleText) as Record<string, unknown>;
    capsule.accepted_actor = "forged-actor@example.invalid";
    await env.R2.put(capsuleKey, `${JSON.stringify(capsule)}\n`);
    await truncateGrantLedgerForInstallation(scenario.installationId);

    const accessJwt = await mintVendorAccessJwt();
    const rejected = await p311VendorCall(
      "rebuildGrantLedger", { contract_version: CONTRACT_VERSION }, { accessJwt },
    );
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("recovery_evidence_required");
    expect(rejected.detail).toContain("grant_recovery_command_provenance_conflict");
    expect(await queryOne(
      `SELECT grant_id FROM grant_ledger WHERE installation_id = ?`,
      [scenario.installationId],
    )).toBeNull();
    diag("END R9-PDO1 RM29-F2: accepted-actor capsule provenan");
  });

  it("R9-PDO1 RM29-F2: route-generation capsule provenance tampering is rejected", async () => {
    diag("START R9-PDO1 RM29-F2: route-generation capsule proven");
    const { scenario, capsuleKey, capsuleText } = await setupComplimentaryRecoveryCapsule();
    const capsule = JSON.parse(capsuleText) as Record<string, unknown>;
    capsule.route_generation = 999;
    await env.R2.put(capsuleKey, `${JSON.stringify(capsule)}\n`);
    await truncateGrantLedgerForInstallation(scenario.installationId);

    const accessJwt = await mintVendorAccessJwt();
    const rejected = await p311VendorCall(
      "rebuildGrantLedger", { contract_version: CONTRACT_VERSION }, { accessJwt },
    );
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("recovery_evidence_required");
    expect(rejected.detail).toContain("grant_recovery_route_provenance_conflict");
    expect(await queryOne(
      `SELECT grant_id FROM grant_ledger WHERE installation_id = ?`,
      [scenario.installationId],
    )).toBeNull();
    diag("END R9-PDO1 RM29-F2: route-generation capsule proven");
  });

  it("R9-PDO1 RM29-F2: fresh complimentary recovery accepts source_reconciled=0 and JSON-text ceiling receipts", async () => {
    diag("START R9-PDO1 RM29-F2: fresh complimentary recovery ac");
    const { scenario, grantId, capsuleText } = await setupComplimentaryRecoveryCapsule();
    const capsule = JSON.parse(capsuleText) as Record<string, unknown>;
    const ceiling = capsule.ceiling_claim as Record<string, unknown>;
    expect(ceiling.source_reconciled).toBe(0);
    expect(typeof ceiling.receipt).toBe("string");
    expect(JSON.parse(ceiling.receipt as string)).toEqual(capsule.receipt);
    await truncateGrantLedgerForInstallation(scenario.installationId);
    await env.DB.prepare("DROP TRIGGER IF EXISTS complimentary_ceiling_claim_no_delete_guard").run();
    await env.DB.prepare(
      "DELETE FROM complimentary_ceiling_claim WHERE grant_id = ?",
    ).bind(grantId).run();
    await env.DB.prepare(`CREATE TRIGGER complimentary_ceiling_claim_no_delete_guard
      BEFORE DELETE ON complimentary_ceiling_claim
      BEGIN
        SELECT RAISE(ABORT, 'complimentary_ceiling_claim is append-only');
      END`).run();

    const accessJwt = await mintVendorAccessJwt();
    const rebuilt = await p311VendorCall(
      "rebuildGrantLedger", { contract_version: CONTRACT_VERSION }, { accessJwt },
    );
    expect(rebuilt.result).toBe("ok");
    const restored = await queryOne<{ source_reconciled: number; receipt: string }>(
      `SELECT source_reconciled, receipt FROM complimentary_ceiling_claim WHERE grant_id = ?`,
      [grantId],
    );
    expect(restored?.source_reconciled).toBe(0);
    expect(JSON.parse(restored!.receipt)).toEqual(capsule.receipt);
    diag("END R9-PDO1 RM29-F2: fresh complimentary recovery ac");
  });

  it("R9-PDO1 RM29-F2: malformed or non-object ceiling receipts are rejected", async () => {
    diag("START R9-PDO1 RM29-F2: malformed or non-object ceiling");
    for (const invalidReceipt of ["{", "[]"]) {
      const { scenario, capsuleKey, capsuleText } = await setupComplimentaryRecoveryCapsule();
      const capsule = JSON.parse(capsuleText) as Record<string, unknown>;
      (capsule.ceiling_claim as Record<string, unknown>).receipt = invalidReceipt;
      await env.R2.put(capsuleKey, `${JSON.stringify(capsule)}\n`);
      await truncateGrantLedgerForInstallation(scenario.installationId);

      const accessJwt = await mintVendorAccessJwt();
      const rejected = await p311VendorCall(
        "rebuildGrantLedger", { contract_version: CONTRACT_VERSION }, { accessJwt },
      );
      expect(rejected.result).toBe("rejected");
      expect(rejected.code).toBe("recovery_evidence_required");
      expect(rejected.detail).toContain("grant_recovery_ceiling_claim_conflict");
      expect(await queryOne(
        `SELECT grant_id FROM grant_ledger WHERE installation_id = ?`,
        [scenario.installationId],
      )).toBeNull();
    }
    diag("END R9-PDO1 RM29-F2: malformed or non-object ceiling");
  });

  it("R9-PDO1 RM29-F4: later ledger collision leaves earlier recovery rows uninstalled", async () => {
    diag("START R9-PDO1 RM29-F4: later ledger collision leaves e");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    await shipCoverageOutbox(scenario.installationId);
    const secondGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    expect((await paidGrant(scenario, secondGrantId)).result).toBe("applied");
    await shipCoverageOutbox(scenario.installationId);
    const rows = await queryAll<GrantLedgerRow & { operator_email: string | null }>(
      `SELECT grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
              operator_credential_id, operator_email, envelope_sha256, receipt, applied_at
       FROM grant_ledger WHERE installation_id = ? ORDER BY grant_id ASC`,
      [scenario.installationId],
    );
    expect(rows.length).toBeGreaterThan(1);
    await truncateGrantLedgerForInstallation(scenario.installationId);
    const first = rows[0]!;
    const colliding = rows.at(-1)!;
    await env.DB.prepare(
      `INSERT INTO grant_ledger (
        grant_id, origin_grant_id, org_id, installation_id, kind, source_kind,
        operator_credential_id, operator_email, envelope_sha256, receipt, applied_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      colliding.grant_id, colliding.origin_grant_id, colliding.org_id,
      colliding.installation_id, colliding.kind, colliding.source_kind,
      "forged-credential", colliding.operator_email, colliding.envelope_sha256,
      colliding.receipt, colliding.applied_at,
    ).run();

    const accessJwt = await mintVendorAccessJwt();
    const rebuilt = await p311VendorCall(
      "rebuildGrantLedger", { contract_version: CONTRACT_VERSION }, { accessJwt },
    );
    expect(rebuilt.result).toBe("rejected");
    expect(rebuilt.code).toBe("recovery_evidence_required");
    expect(rebuilt.detail).toContain("grant_ledger_recovery_conflict");
    expect(await queryOne(
      `SELECT grant_id FROM grant_ledger WHERE grant_id = ?`, [first.grant_id],
    )).toBeNull();
    expect(await queryOne<{ operator_credential_id: string }>(
      `SELECT operator_credential_id FROM grant_ledger WHERE grant_id = ?`,
      [colliding.grant_id],
    )).toEqual({ operator_credential_id: "forged-credential" });
    diag("END R9-PDO1 RM29-F4: later ledger collision leaves e");
  });

  it("R9-PDO1 RM29-F5: fetch and alarm shipments remain fenced during recovery", async () => {
    diag("START R9-PDO1 RM29-F5: fetch and alarm shipments remai");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    const anchor = await queryOne<{ event_id: string; binding_epoch: number }>(
      `SELECT event_id, binding_epoch FROM coverage_event
       WHERE installation_id = ? ORDER BY clinic_seq DESC LIMIT 1`,
      [scenario.installationId],
    );
    expect(anchor).not.toBeNull();
    await runInDurableObject(quotaDoStub(scenario.installationId), async (_instance, state) => {
      sqlExec(state, `INSERT INTO recovery_state (
        singleton, generation, installation_id, org_id, binding_epoch,
        anchor_event_id, status, updated_at
      ) VALUES (1, '${scenario.installationId}:${anchor!.binding_epoch}:${anchor!.event_id}',
        '${scenario.installationId}', '${scenario.orgId}', ${anchor!.binding_epoch},
        '${anchor!.event_id}', 'building', '2026-10-21T00:00:00.000Z')`);
      sqlExec(state, `INSERT INTO outbox (kind, payload) VALUES ('coverage_event', '{}')`);
    });

    const blockedResponse = await quotaDoStub(scenario.installationId).fetch(
      "https://quota-do.internal/rpc",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contract_version: CHANNEL_VERSIONS.platformDo,
          kind: "refresh_coverage_snapshot",
        }),
      },
    );
    expect(blockedResponse.status).toBe(409);
    expect((await blockedResponse.json() as { result: string }).result).toBe("recovery_blocked");

    const pendingBeforeAlarm = await runInDurableObject(quotaDoStub(scenario.installationId), async (_instance, state) =>
      sqlSelect<{ count: number }>(state, "SELECT COUNT(*) AS count FROM outbox")[0]?.count ?? 0,
    );
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    const remaining = await runInDurableObject(quotaDoStub(scenario.installationId), async (_instance, state) =>
      sqlSelect<{ count: number }>(state, "SELECT COUNT(*) AS count FROM outbox")[0]?.count ?? 0,
    );
    expect(remaining).toBe(pendingBeforeAlarm);
    diag("END R9-PDO1 RM29-F5: fetch and alarm shipments remai");
  });

  it("E2E-P3.11-04 snapshot refresh writes one coverage_event and updates the mirror", async () => {
    diag("START E2E-P3.11-04 snapshot refresh writes one coverag");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    await shipCoverageOutbox(scenario.installationId);

    const eventsBefore = await queryOne<{ count: number }>(
      "SELECT COUNT(*) AS count FROM coverage_event WHERE installation_id = ?",
      [scenario.installationId],
    );
    const mirrorBefore = await queryOne<{
      clinic_seq: number;
      binding_epoch: number;
      state: string;
      suspended: number;
      term_snapshot: string;
    }>(
      `SELECT clinic_seq, binding_epoch, state, suspended, term_snapshot
       FROM coverage_mirror WHERE installation_id = ?`,
      [scenario.installationId],
    );
    expect(mirrorBefore).toBeTruthy();

    const accessJwt = await mintVendorAccessJwt();
    const refreshed = await p311VendorCall(
      "refreshCoverageSnapshot",
      {
        contract_version: CONTRACT_VERSION,
        installation_id: scenario.installationId,
      },
      { accessJwt },
    );
    expect(refreshed.result).toBe("ok");
    expect(refreshed.code).toBe("");
    expect(refreshed.receipt).toBeUndefined();

    const detail = JSON.parse(refreshed.detail) as {
      event_id: string;
      installation_id: string;
    };
    expect(detail.installation_id).toBe(scenario.installationId);
    expect(detail.event_id.length).toBeGreaterThan(0);

    const eventsAfter = await queryOne<{ count: number }>(
      "SELECT COUNT(*) AS count FROM coverage_event WHERE installation_id = ?",
      [scenario.installationId],
    );
    expect(eventsAfter!.count - eventsBefore!.count).toBe(1);

    const snapshotEvent = await queryOne<{
      event_id: string;
      kind: string;
      snapshot: string;
      binding_epoch: number;
      clinic_seq: number;
    }>(
      `SELECT event_id, kind, snapshot, binding_epoch, clinic_seq
       FROM coverage_event WHERE event_id = ?`,
      [detail.event_id],
    );
    expect(snapshotEvent?.kind).toBe("snapshot");

    const mirrorAfter = await queryOne<{
      clinic_seq: number;
      binding_epoch: number;
      state: string;
      suspended: number;
      term_snapshot: string;
    }>(
      `SELECT clinic_seq, binding_epoch, state, suspended, term_snapshot
       FROM coverage_mirror WHERE installation_id = ?`,
      [scenario.installationId],
    );
    expect(mirrorAfter?.clinic_seq).toBe(snapshotEvent!.clinic_seq);
    expect(mirrorAfter?.binding_epoch).toBe(snapshotEvent!.binding_epoch);
    expect(mirrorAfter?.term_snapshot).toBe(snapshotEvent!.snapshot);
    expect(mirrorAfter!.clinic_seq).toBe(mirrorBefore!.clinic_seq + 1);
    diag("END E2E-P3.11-04 snapshot refresh writes one coverag");
  });

  it("R9-PD1: restored binding bootstraps a surviving DO after event and mirror loss", async () => {
    diag("START R9-PD1: restored binding bootstraps a surviving ");
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);
    await shipCoverageOutbox(scenario.installationId);
    const prior = await queryOne<{ clinic_seq: number; binding_epoch: number }>(
      `SELECT clinic_seq, binding_epoch FROM coverage_mirror WHERE installation_id = ?`,
      [scenario.installationId],
    );
    expect(prior).toBeTruthy();

    await env.DB.prepare("DROP TRIGGER IF EXISTS coverage_event_no_delete").run();
    await env.DB.prepare("DROP TRIGGER IF EXISTS coverage_mirror_no_delete").run();
    await env.DB.prepare("DELETE FROM coverage_event WHERE installation_id = ?")
      .bind(scenario.installationId).run();
    await env.DB.prepare("DELETE FROM coverage_mirror WHERE installation_id = ?")
      .bind(scenario.installationId).run();

    const accessJwt = await mintVendorAccessJwt();
    const refreshed = await p311VendorCall(
      "refreshCoverageSnapshot",
      { contract_version: CONTRACT_VERSION, installation_id: scenario.installationId },
      { accessJwt },
    );
    expect(refreshed.result).toBe("ok");

    const event = await queryOne<{
      org_id: string;
      installation_id: string;
      binding_epoch: number;
      clinic_seq: number;
      kind: string;
    }>(
      `SELECT org_id, installation_id, binding_epoch, clinic_seq, kind FROM coverage_event
       WHERE installation_id = ? ORDER BY clinic_seq DESC LIMIT 1`,
      [scenario.installationId],
    );
    expect(event).toMatchObject({
      org_id: scenario.orgId,
      installation_id: scenario.installationId,
      binding_epoch: prior!.binding_epoch,
      kind: "snapshot",
    });
    expect(event!.clinic_seq).toBeGreaterThan(prior!.clinic_seq);
    const mirror = await queryOne<{ clinic_seq: number; binding_epoch: number }>(
      `SELECT clinic_seq, binding_epoch FROM coverage_mirror WHERE installation_id = ?`,
      [scenario.installationId],
    );
    expect(mirror).toEqual({ clinic_seq: event!.clinic_seq, binding_epoch: event!.binding_epoch });
    diag("END R9-PD1: restored binding bootstraps a surviving ");
  });
});
