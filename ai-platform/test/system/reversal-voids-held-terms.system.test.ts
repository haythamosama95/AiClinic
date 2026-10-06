/**
 * P3.7 — Reversal voids, tombstones, held terms, operator voids (H-AP).
 */

import { env, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import {
  CHANNEL_VERSIONS,
  grantIdComp,
  grantIdPaid,
  operationChallenge,
  sha256Hex,
} from "vendor-contracts";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  applyAllMigrations,
  coverClinic,
  coverClinicAboKid,
  coverClinicSigner,
  encodeVendorAssertion,
  fakePolicyDocument,
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
  r2Exists,
  setTestClock,
  setupVendorHarness,
  signCoverAbo,
  vendorCall,
  VENDOR_OPERATOR_EMAIL,
  type Scenario,
  type VendorMethod,
  type VendorResultEnvelope,
} from "./harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const NIL_UUID = "00000000-0000-0000-0000-000000000000";

const PLAN_ID = "live-monthly";
const PLAN_VERSION = 1;
const PLAN_MAX_ALLOWANCE = 10_000;

type GrantResultEnvelope = VendorResultEnvelope & {
  receipt?: Record<string, unknown>;
};

type P37VendorMethod =
  | VendorMethod
  | "voidForReversal"
  | "releaseHeld"
  | "voidGrant";

const p37VendorCall = vendorCall as (
  method: P37VendorMethod,
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
  ends_at: string | null;
  grace_ends_at: string | null;
};

type DoGrantRow = {
  grant_id: string;
};

async function readDoTerms(installationId: string): Promise<DoTermRow[]> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect<DoTermRow>(
      state,
      `SELECT term_id, grant_id, origin_grant_id, state, end_reason, position, ends_at, grace_ends_at
       FROM term ORDER BY position ASC`,
    ),
  );
}

async function readDoGrants(installationId: string): Promise<DoGrantRow[]> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect<DoGrantRow>(
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
): Promise<GrantResultEnvelope> {
  const envelope = await buildPaidGrantEnvelope({
    orgId: scenario.orgId,
    grantId,
  });
  const aboSignature = await signCoverAbo(envelope);
  return p37VendorCall("grant", {
    contract_version: CONTRACT_VERSION,
    envelope,
    abo_kid: coverClinicAboKid(),
    abo_signature: aboSignature,
  });
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
  return p37VendorCall("voidForReversal", {
    ...body,
    abo_kid: coverClinicAboKid(),
    abo_signature: aboSignature,
  });
}

async function inspectCoverageTerms(
  scenario: Scenario,
): Promise<DoTermRow[]> {
  const accessJwt = await mintVendorAccessJwt();
  const inspected = await p37VendorCall(
    "inspectCoverage",
    {
      contract_version: CONTRACT_VERSION,
      org_id: scenario.orgId,
    },
    { accessJwt },
  );
  expect(inspected.result).toBe("ok");
  const detail = JSON.parse(inspected.detail) as {
    terms: DoTermRow[];
  };
  return detail.terms;
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

async function setupPromotedPolicy(scenario: Scenario): Promise<string> {
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  expect(published.status).toBe(200);
  const promoted = await promote(POLICY_ID, POLICY_VERSION);
  expect(promoted.status).toBe(200);
  return await mintAat(scenario);
}

async function buildComplimentaryEnvelope(input: {
  orgId: string;
  grantId: string;
}): Promise<Record<string, unknown>> {
  const ref = crypto.randomUUID().replace(/-/g, "");
  const contentSha256 = await sha256Hex(new TextEncoder().encode(ref));
  return {
    contract_version: CONTRACT_VERSION,
    grant_id: input.grantId,
    org_id: input.orgId,
    kind: "term",
    placement: "queue",
    source: {
      kind: "complimentary",
      ref,
      operator_email: VENDOR_OPERATOR_EMAIL,
      reason: "goodwill",
    },
    plan: { plan_id: PLAN_ID, plan_version: PLAN_VERSION },
    duration: { unit: "day", count: 14 },
    allowance_credits: PLAN_MAX_ALLOWANCE,
    grace: { days: 7, cap_rule: "proportional" },
    evidence: {
      content_sha256: contentSha256,
      approvals: [{ credential_id: "cred-001", assertion: "stub" }],
    },
  };
}

async function operationForHp(input: {
  op: "releaseHeld" | "voidGrant";
  accessJwt: string;
  grantId: string;
  reason: string;
}): Promise<Record<string, unknown>> {
  return {
    op: input.op,
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

async function hpVoidOp(input: {
  op: "releaseHeld" | "voidGrant";
  grantId: string;
  reason?: string;
}): Promise<{
  result: GrantResultEnvelope;
  operation: Record<string, unknown>;
}> {
  const signer = coverClinicSigner();
  const accessJwt = await mintVendorAccessJwt();
  const operation = await operationForHp({
    op: input.op,
    accessJwt,
    grantId: input.grantId,
    reason: input.reason ?? "operator void",
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
  const result = await p37VendorCall(
    input.op,
    {
      contract_version: CONTRACT_VERSION,
      grant_id: input.grantId,
      reason: input.reason ?? "operator void",
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
  return { result, operation };
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

describe("reversal voids, tombstones, held terms, operator voids", () => {
  it("E2E-P3.7-01 A15 void of the active term holds T2 and refuses coverage_lapsed reversed", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);

    const grantsBefore = await readDoGrants(scenario.installationId);
    const activeGrantId = grantsBefore[0]!.grant_id;

    const secondGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    const second = await paidGrant(scenario, secondGrantId);
    expect(second.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const voided = await callVoidForReversal({
      grantId: activeGrantId,
      partial: false,
    });
    expect(voided.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const terms = await inspectCoverageTerms(scenario);
    const t1 = terms.find((row) => row.grant_id === activeGrantId);
    const t2 = terms.find((row) => row.grant_id === secondGrantId);
    expect(t1?.state).toBe("ended");
    expect(t1?.end_reason).toBe("reversed");
    expect(t2?.state).toBe("held");

    const token = await setupPromotedPolicy(scenario);
    const denied = await invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    expect(denied.status).toBe(403);
    expect(denied.body?.code).toBe("coverage_lapsed");
    expect(denied.body?.coverage_reason).toBe("reversed");
  });

  it("E2E-P3.7-02 void of a queued term removes that term and leaves the active term", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    const grantsBefore = await readDoGrants(scenario.installationId);
    const activeGrantId = grantsBefore[0]!.grant_id;

    const queuedGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    const queued = await paidGrant(scenario, queuedGrantId);
    expect(queued.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const voided = await callVoidForReversal({
      grantId: queuedGrantId,
      partial: false,
    });
    expect(voided.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const terms = await inspectCoverageTerms(scenario);
    const active = terms.find((row) => row.grant_id === activeGrantId);
    const removed = terms.find((row) => row.grant_id === queuedGrantId);
    expect(active?.state).toBe("active");
    expect(removed?.state).toBe("ended");
    expect(removed?.end_reason).toBe("reversed");
  });

  it("E2E-P3.7-03 A17 void of an ended term is recorded only", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    const grantsBefore = await readDoGrants(scenario.installationId);
    const grantId = grantsBefore[0]!.grant_id;

    const termsBefore = await readDoTerms(scenario.installationId);
    const active = termsBefore.find((row) => row.state === "active");
    expect(active?.ends_at).toBeTruthy();
    await setTestClock(String(active!.ends_at));
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    let termsAfterExpiry = await readDoTerms(scenario.installationId);
    const grace = termsAfterExpiry.find(
      (row) => row.grant_id === grantId && row.state === "grace",
    );
    if (grace?.grace_ends_at) {
      await setTestClock(grace.grace_ends_at);
      await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
      termsAfterExpiry = await readDoTerms(scenario.installationId);
    }

    const ended = termsAfterExpiry.find((row) => row.grant_id === grantId);
    expect(ended?.state).toBe("ended");
    expect(ended?.end_reason).toBe("expired");

    const voided = await callVoidForReversal({ grantId, partial: false });
    expect(voided.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const termsAfterVoid = await inspectCoverageTerms(scenario);
    const after = termsAfterVoid.find((row) => row.grant_id === grantId);
    expect(after?.state).toBe("ended");
    expect(after?.end_reason).toBe("expired");

    const grantVoid = await queryOne<{ grant_id: string }>(
      "SELECT grant_id FROM grant_void WHERE grant_id = ?",
      [grantId],
    );
    expect(grantVoid?.grant_id).toBe(grantId);
  });

  it("E2E-P3.7-04 void before the grant stores a tombstone and the later grant is voided", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    const tombstoneGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    const eventsBefore = await queryAll<{ event_id: string }>(
      "SELECT event_id FROM coverage_event",
    );
    const voided = await callVoidForReversal({
      grantId: tombstoneGrantId,
      partial: false,
    });
    expect(voided.result).toBe("applied");
    const receipt = voided.receipt as Record<string, unknown>;
    expect(receipt.installation_id).toBe(NIL_UUID);
    expect(receipt.org_id).toBe(NIL_UUID);
    expect(receipt.ledger_seq).toBe(0);
    expect(receipt.term_ids).toEqual([]);

    const grantVoid = await queryOne<{ grant_id: string }>(
      "SELECT grant_id FROM grant_void WHERE grant_id = ?",
      [tombstoneGrantId],
    );
    expect(grantVoid?.grant_id).toBe(tombstoneGrantId);
    expect(
      await r2Exists(`grant-ledger/${tombstoneGrantId}.void.ndjson`),
    ).toBe(true);

    const eventsAfter = await queryAll<{ event_id: string }>(
      "SELECT event_id FROM coverage_event",
    );
    expect(eventsAfter).toHaveLength(eventsBefore.length);

    const rejected = await paidGrant(scenario, tombstoneGrantId);
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("voided");
    expect(rejected.detail).toBe("");
  });

  it("E2E-P3.7-05 releaseHeld re-queues a held term and activates it when nothing is active", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    const grantsBefore = await readDoGrants(scenario.installationId);
    const activeGrantId = grantsBefore[0]!.grant_id;

    const secondGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    const thirdGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    expect((await paidGrant(scenario, secondGrantId)).result).toBe("applied");
    expect((await paidGrant(scenario, thirdGrantId)).result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const voided = await callVoidForReversal({
      grantId: activeGrantId,
      partial: false,
    });
    expect(voided.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const heldTerms = (await readDoTerms(scenario.installationId)).filter(
      (row) => row.state === "held",
    );
    expect(heldTerms).toHaveLength(2);
    const firstHeldGrantId = heldTerms[0]!.grant_id;
    const secondHeldGrantId = heldTerms[1]!.grant_id;

    const firstRelease = await hpVoidOp({
      op: "releaseHeld",
      grantId: firstHeldGrantId,
    });
    expect(firstRelease.result.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    let terms = await readDoTerms(scenario.installationId);
    expect(terms.find((row) => row.grant_id === firstHeldGrantId)?.state).toBe(
      "active",
    );
    expect(terms.filter((row) => row.state === "active")).toHaveLength(1);

    const secondRelease = await hpVoidOp({
      op: "releaseHeld",
      grantId: secondHeldGrantId,
    });
    expect(secondRelease.result.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    terms = await readDoTerms(scenario.installationId);
    expect(terms.find((row) => row.grant_id === firstHeldGrantId)?.state).toBe(
      "active",
    );
    expect(terms.find((row) => row.grant_id === secondHeldGrantId)?.state).toBe(
      "queued",
    );
    const positions = terms
      .filter((row) => row.state === "active" || row.state === "queued")
      .sort((a, b) => a.position - b.position);
    expect(positions[positions.length - 1]?.grant_id).toBe(secondHeldGrantId);
  });

  it("E2E-P3.7-06 voidGrant ends an active complimentary term and activates the successor", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    await expireActivePaidTerm(scenario.installationId);

    const compGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const compEnvelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: compGrantId,
    });
    const signer = coverClinicSigner();
    const accessJwt = await mintVendorAccessJwt();
    const compOperation = {
      op: "grant",
      params: {
        contract_version: CONTRACT_VERSION,
        access_jwt: accessJwt,
        envelope: compEnvelope,
      },
      actor_email: VENDOR_OPERATOR_EMAIL,
      issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
      nonce: crypto.randomUUID(),
      contract_version: CONTRACT_VERSION,
    };
    const compAssertion = encodeVendorAssertion(
      await signer.signerAuthenticator.assert({
        operation: compOperation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      }),
    );
    const compApplied = await p37VendorCall(
      "grant",
      {
        contract_version: CONTRACT_VERSION,
        envelope: compEnvelope,
        signer_credential_id: signer.signerCredentialId,
        operation: compOperation,
        assertion: compAssertion,
      },
      { accessJwt },
    );
    expect(compApplied.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const afterComp = await readDoTerms(scenario.installationId);
    expect(
      afterComp.find((row) => row.grant_id === compGrantId)?.state,
    ).toBe("active");

    const successorGrantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
    expect((await paidGrant(scenario, successorGrantId)).result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const { result: voided, operation } = await hpVoidOp({
      op: "voidGrant",
      grantId: compGrantId,
      reason: "operator correction",
    });
    expect(voided.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const terms = await inspectCoverageTerms(scenario);
    const compTerm = terms.find((row) => row.grant_id === compGrantId);
    const successor = terms.find((row) => row.grant_id === successorGrantId);
    expect(compTerm?.state).toBe("ended");
    expect(compTerm?.end_reason).toBe("voided");
    expect(successor?.state).toBe("active");

    const grantVoid = await queryOne<{ source: string; evidence_sha256: string }>(
      "SELECT source, evidence_sha256 FROM grant_void WHERE grant_id = ?",
      [compGrantId],
    );
    expect(grantVoid?.source).toBe("operator");
    const expectedChallenge = await operationChallenge(operation);
    expect(grantVoid?.evidence_sha256).toBe(expectedChallenge);
    expect(await r2Exists(`grant-ledger/${compGrantId}.void.ndjson`)).toBe(
      true,
    );
  });
});
