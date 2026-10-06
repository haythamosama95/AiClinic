/**
 * P3.11 — Platform rebuild procedures (H-AP, E2E-P3.11-01–04).
 */

import { env, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import {
  CHANNEL_VERSIONS,
  grantIdPaid,
  sha256Hex,
} from "vendor-contracts";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
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
  setupVendorHarness,
  signCoverAbo,
  terminalEventTypes,
  vendorCall,
  type Scenario,
  type VendorMethod,
  type VendorResultEnvelope,
} from "./harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const QUOTA_WEIGHT = 1;

type P311VendorMethod =
  | VendorMethod
  | "rebuildClinicDo"
  | "rebuildGrantLedger"
  | "refreshCoverageSnapshot";

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

function ledgerRowsEqual(
  left: GrantLedgerRow[],
  right: GrantLedgerRow[],
): void {
  expect(right).toHaveLength(left.length);
  for (let index = 0; index < left.length; index += 1) {
    const a = left[index]!;
    const b = right[index]!;
    expect(b.grant_id).toBe(a.grant_id);
    expect(b.origin_grant_id).toBe(a.origin_grant_id);
    expect(b.org_id).toBe(a.org_id);
    expect(b.installation_id).toBe(a.installation_id);
    expect(b.kind).toBe(a.kind);
    expect(b.source_kind).toBe(a.source_kind);
    expect(b.operator_credential_id).toBe(a.operator_credential_id);
    expect(b.envelope_sha256).toBe(a.envelope_sha256);
    expect(JSON.parse(b.receipt)).toEqual(JSON.parse(a.receipt));
    expect(b.applied_at).toBe(a.applied_at);
  }
}

function voidRowsEqual(left: GrantVoidRow[], right: GrantVoidRow[]): void {
  expect(right).toHaveLength(left.length);
  for (let index = 0; index < left.length; index += 1) {
    const a = left[index]!;
    const b = right[index]!;
    expect(b.grant_id).toBe(a.grant_id);
    expect(b.reason).toBe(a.reason);
    expect(b.source).toBe(a.source);
    expect(b.evidence_sha256).toBe(a.evidence_sha256);
    expect(b.at).toBe(a.at);
  }
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
  it("E2E-P3.11-01 FM-20 wiped DO rebuilds terms positions holds and usage and the compare is clean", async () => {
    const scenario = await newScenario();
    await setupFm20Clinic(scenario);

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
  });

  it("E2E-P3.11-02 a rebuild that diverges from the mirror alerts", async () => {
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
    expect(rebuilt.result).toBe("ok");

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
  });

  it("E2E-P3.11-03 grant_ledger truncated rebuilds from R2 identical", async () => {
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
    expect(rebuilt.result).toBe("ok");
    expect(rebuilt.code).toBe("");
    expect(rebuilt.receipt).toBeUndefined();

    const detail = JSON.parse(rebuilt.detail) as {
      grant_ledger: number;
      grant_void: number;
    };
    expect(detail.grant_ledger).toBe(copy.ledger.length);
    expect(detail.grant_void).toBe(copy.voids.length);

    const reloaded = await copyGrantLedgerForInstallation(scenario.installationId);
    ledgerRowsEqual(copy.ledger, reloaded.ledger);
    voidRowsEqual(copy.voids, reloaded.voids);
  });

  it("E2E-P3.11-04 snapshot refresh writes one coverage_event and updates the mirror", async () => {
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
  });
});
